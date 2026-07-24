#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# setup-droplet.sh — Bootstrap a DigitalOcean Ubuntu 24.04 droplet
#                     as a docker-free CTF pwn box with pwno-mcp
#
# Usage:
#   ssh root@<DROPLET_IP> 'bash -s' < setup-droplet.sh
#   ssh root@<DROPLET_IP> 'PWNO_REF=<branch-or-commit> bash -s' < setup-droplet.sh
#   # or copy to droplet and run:
#   chmod +x setup-droplet.sh && ./setup-droplet.sh
#
# What it does:
#   1. Creates swap (needed on 1GB droplets)
#   2. Installs system packages (compilers, GDB, 32-bit libs, qemu, etc.)
#   3. Installs zsh + tmux with custom configs
#   4. Installs pwndbg (GDB plugin)
#   5. Installs uv (Python package manager) + Python 3.12
#   6. Clones & sets up pwno-mcp with all dependencies
#   7. Creates a shared analysis venv with pwntools/ropper
#   8. Configures pwno-mcp as systemd service
#   9. Installs/configures Codex CLI by default
#  10. Optionally installs/configures Claude Code
#  11. Creates /root/ctf workspace directory
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────
PWNO_REPO="${PWNO_REPO:-https://github.com/x746b/pwno-mcp.git}"
PWNO_REF="${PWNO_REF:-main}"
PWNO_DIR="${PWNO_DIR:-/opt/pwno-mcp}"
WORKSPACE="${WORKSPACE:-/root/ctf}"
PWNO_USER="${PWNO_USER:-root}"          # root simplifies ptrace on disposable CTF boxes
PWNO_HOST="${PWNO_HOST:-127.0.0.1}"     # bind locally; access via SSH tunnel
PWNO_PORT="${PWNO_PORT:-5500}"
PWNO_GDB_DEBUGINFOD="${PWNO_GDB_DEBUGINFOD:-off}"
PWNO_HEALTH_RETRIES="${PWNO_HEALTH_RETRIES:-30}"
CODEX_HOME="${CODEX_HOME:-/root/.codex}"
CODEX_VERSION="${CODEX_VERSION:-rust-v0.130.0}"
PWNINIT_VERSION="${PWNINIT_VERSION:-3.3.1}"
INSTALL_CODEX="${INSTALL_CODEX:-}"
INSTALL_CLAUDE="${INSTALL_CLAUDE:-}"

case "$PWNO_GDB_DEBUGINFOD" in
  on|off|ask) ;;
  *)
    echo "PWNO_GDB_DEBUGINFOD must be one of: on, off, ask" >&2
    exit 2
    ;;
esac

if [[ ! "$PWNO_HEALTH_RETRIES" =~ ^[1-9][0-9]*$ ]]; then
  echo "PWNO_HEALTH_RETRIES must be a positive integer" >&2
  exit 2
fi

log() { printf '\n\033[1;36m>>> %s\033[0m\n' "$*"; }

prompt_cli_selection() {
  if [[ -n "$INSTALL_CODEX" || -n "$INSTALL_CLAUDE" ]]; then
    INSTALL_CODEX="${INSTALL_CODEX:-1}"
    INSTALL_CLAUDE="${INSTALL_CLAUDE:-0}"
    return
  fi

  if [[ -t 0 ]]; then
    echo ""
    echo "Which agent CLI should be installed/configured?"
    echo "  1) Codex CLI (default)"
    echo "  2) Claude Code"
    echo "  3) Both"
    echo "  4) None"
    read -r -p "Choice [1]: " cli_choice
    case "${cli_choice:-1}" in
      1) INSTALL_CODEX=1; INSTALL_CLAUDE=0 ;;
      2) INSTALL_CODEX=0; INSTALL_CLAUDE=1 ;;
      3) INSTALL_CODEX=1; INSTALL_CLAUDE=1 ;;
      4) INSTALL_CODEX=0; INSTALL_CLAUDE=0 ;;
      *) INSTALL_CODEX=1; INSTALL_CLAUDE=0 ;;
    esac
  else
    # Non-interactive bootstrap should not hang. Prefer Codex for this setup.
    INSTALL_CODEX=1
    INSTALL_CLAUDE=0
  fi
}

append_toml_section_once() {
  local file="$1"
  local section="$2"
  local body="$3"

  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Eq "^\[$section\]$" "$file"; then
    {
      echo ""
      echo "[$section]"
      printf '%s\n' "$body"
    } >> "$file"
  fi
}

prepend_toml_key_once() {
  local file="$1"
  local key="$2"
  local line="$3"
  local tmp_file

  mkdir -p "$(dirname "$file")"
  touch "$file"
  if ! grep -Eq "^${key}[[:space:]]*=" "$file"; then
    tmp_file="$(mktemp)"
    {
      printf '%s\n' "$line"
      cat "$file"
    } > "$tmp_file"
    install -m 0644 "$tmp_file" "$file"
    rm -f "$tmp_file"
  fi
}

install_codex_release() {
  local arch
  local asset
  local url
  local tmp_dir
  local archive
  local extracted

  arch="$(uname -m)"
  case "$arch" in
    x86_64) asset="codex-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) asset="codex-aarch64-unknown-linux-musl.tar.gz" ;;
    *)
      echo "Codex release binary not configured for architecture: $arch"
      return 1
      ;;
  esac

  url="https://github.com/openai/codex/releases/download/${CODEX_VERSION}/${asset}"
  tmp_dir="$(mktemp -d)"
  archive="$tmp_dir/$asset"

  curl -fsSL "$url" -o "$archive"
  tar -xzf "$archive" -C "$tmp_dir"
  extracted="$(find "$tmp_dir" -maxdepth 1 -type f -name 'codex-*' -perm /111 | head -n 1)"
  if [[ -z "$extracted" ]]; then
    echo "Codex archive did not contain an executable binary"
    rm -rf "$tmp_dir"
    return 1
  fi

  install -m 0755 "$extracted" /usr/local/bin/codex
  rm -rf "$tmp_dir"
}

checkout_pwno_ref() {
  local remote_ref="refs/remotes/origin/$PWNO_REF"

  git -C "$PWNO_DIR" remote set-url origin "$PWNO_REPO"
  if git -C "$PWNO_DIR" ls-remote --exit-code --heads origin "$PWNO_REF" \
    >/dev/null; then
    git -C "$PWNO_DIR" fetch origin \
      "+refs/heads/$PWNO_REF:$remote_ref"
    if git -C "$PWNO_DIR" show-ref --verify --quiet "refs/heads/$PWNO_REF"; then
      git -C "$PWNO_DIR" checkout "$PWNO_REF"
    else
      git -C "$PWNO_DIR" checkout --track -b "$PWNO_REF" "origin/$PWNO_REF"
    fi
    git -C "$PWNO_DIR" merge --ff-only "origin/$PWNO_REF"
  else
    git -C "$PWNO_DIR" fetch origin "$PWNO_REF"
    git -C "$PWNO_DIR" checkout --detach FETCH_HEAD
  fi
}

wait_for_pwno_mcp() {
  local health_host="$PWNO_HOST"
  local health_url
  local attempt

  case "$health_host" in
    0.0.0.0|::) health_host="127.0.0.1" ;;
  esac
  if [[ "$health_host" == *:* ]]; then
    health_url="http://[$health_host]:$PWNO_PORT"
  else
    health_url="http://$health_host:$PWNO_PORT"
  fi

  for ((attempt = 1; attempt <= PWNO_HEALTH_RETRIES; attempt++)); do
    if curl -fsS "$health_url/healthz" | jq -e '.status == "ok"' >/dev/null \
      && "$PWNO_DIR/.venv/bin/python" -m pwnomcp.healthcheck \
        --url "$health_url/mcp"; then
      return 0
    fi
    sleep 1
  done

  echo "pwno-mcp failed its health check after $PWNO_HEALTH_RETRIES attempts" >&2
  systemctl --no-pager --full status pwnomcp >&2 || true
  journalctl -u pwnomcp --no-pager -n 80 >&2 || true
  return 1
}

prompt_cli_selection

# ── 0. Swap (needed on 1GB droplets) ─────────────────────────────────
log "Setting up swap"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
  echo "2GB swap created"
else
  echo "Swap already active, skipping"
fi

# ── 1. System packages ──────────────────────────────────────────────
log "Installing system packages"
export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386

apt-get update -qq
apt-get install -y --no-install-recommends \
  curl wget git vim nano file sudo unzip ca-certificates jq ripgrep less procps \
  cpio gzip xz-utils zstd bsdextrautils bc kmod dwarves \
  tmux zsh zsh-autosuggestions zsh-syntax-highlighting \
  build-essential gcc g++ clang make cmake bison flex gcc-multilib binutils binutils-multiarch \
  gdb gdbserver gdb-multiarch lldb strace ltrace patchelf elfutils libc6-dbg \
  socat netcat-openbsd \
  qemu-system-x86 qemu-user qemu-user-binfmt \
  python3 python3-pip python3-venv python3-dev python3-setuptools \
  pkg-config libffi-dev libssl-dev \
  libasan8 libubsan1 liblsan0 libtsan2 \
  libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 lib32z1 \
  libc6-dbg:i386 \
  libssl3:i386 libncurses6:i386 libreadline8:i386 libtinfo6:i386 \
  libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev

# ── 2. Shell config (zsh + tmux) ─────────────────────────────────────
log "Configuring zsh and tmux"

# Set zsh as default shell
chsh -s /usr/bin/zsh root 2>/dev/null || true

# ── .zshrc ──
cat > /root/.zshrc << 'ZSHRC'
# ~/.zshrc file for zsh interactive shells.
# see /usr/share/doc/zsh/examples/zshrc for examples

setopt autocd              # change directory just by typing its name
#setopt correct            # auto correct mistakes
setopt interactivecomments # allow comments in interactive mode
setopt magicequalsubst     # enable filename expansion for arguments of the form 'anything=expression'
setopt nonomatch           # hide error message if there is no match for the pattern
setopt notify              # report the status of background jobs immediately
setopt numericglobsort     # sort filenames numerically when it makes sense
setopt promptsubst         # enable command substitution in prompt

WORDCHARS=${WORDCHARS//\/} # Don't consider certain characters part of the word

# hide EOL sign ('%')
PROMPT_EOL_MARK=""

# configure key keybindings
bindkey -e                                        # emacs key bindings
bindkey ' ' magic-space                           # do history expansion on space
bindkey '^U' backward-kill-line                   # ctrl + U
bindkey '^[[3;5~' kill-word                       # ctrl + Supr
bindkey '^[[3~' delete-char                       # delete
bindkey '^[[1;5C' forward-word                    # ctrl + ->
bindkey '^[[1;5D' backward-word                   # ctrl + <-
bindkey '^[[5~' beginning-of-buffer-or-history    # page up
bindkey '^[[6~' end-of-buffer-or-history          # page down
bindkey '^[[H' beginning-of-line                  # home
bindkey '^[[F' end-of-line                        # end
bindkey '^[[Z' undo                               # shift + tab undo last action

# enable completion features
autoload -Uz compinit
compinit -d ~/.cache/zcompdump
zstyle ':completion:*:*:*:*:*' menu select
zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' rehash true
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

# History configurations
HISTFILE=~/.zsh_history
HISTSIZE=100000000000
SAVEHIST=200000000000
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
#setopt share_history         # share command history data

# force zsh to show the complete history
alias history="history 0"

# configure `time` format
TIMEFMT=$'\nreal\t%E\nuser\t%U\nsys\t%S\ncpu\t%P'

# make less more friendly for non-text input files, see lesspipe(1)
#[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

configure_prompt() {
    prompt_symbol=㉿
    # Skull emoji for root terminal
    #[ "$EUID" -eq 0 ] && prompt_symbol=💀
    case "$PROMPT_ALTERNATIVE" in
        twoline)
            PROMPT=$'%F{%(#.blue.green)}┌──${debian_chroot:+($debian_chroot)─}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))─}(%B%F{%(#.red.blue)}%n'$prompt_symbol$'%m%b%F{%(#.blue.green)})-[%B%F{reset}%(6~.%-1~/…/%4~.%5~)%b%F{%(#.blue.green)}]\n└─%B%(#.%F{red}#.%F{blue}$)%b%F{reset} '
            # Right-side prompt with exit codes and background processes
            #RPROMPT=$'%(?.. %? %F{red}%B⨯%b%F{reset})%(1j. %j %F{yellow}%B⚙%b%F{reset}.)'
            ;;
        oneline)
            PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{%(#.red.blue)}%n@%m%b%F{reset}:%B%F{%(#.blue.green)}%~%b%F{reset}%(#.#.$) '
            RPROMPT=
            ;;
        backtrack)
            PROMPT=$'${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%B%F{red}%n@%m%b%F{reset}:%B%F{blue}%~%b%F{reset}%(#.#.$) '
            RPROMPT=
            ;;
    esac
    unset prompt_symbol
}

# The following block is surrounded by two delimiters.
# These delimiters must not be modified. Thanks.
# START KALI CONFIG VARIABLES
PROMPT_ALTERNATIVE=twoline
NEWLINE_BEFORE_PROMPT=yes
# STOP KALI CONFIG VARIABLES

if [ "$color_prompt" = yes ]; then
    # override default virtualenv indicator in prompt
    VIRTUAL_ENV_DISABLE_PROMPT=1

    configure_prompt

    # enable syntax-highlighting
    if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
        . /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
        ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
        ZSH_HIGHLIGHT_STYLES[default]=none
        ZSH_HIGHLIGHT_STYLES[unknown-token]=underline
        ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=cyan,bold
        ZSH_HIGHLIGHT_STYLES[suffix-alias]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[global-alias]=fg=green,bold
        ZSH_HIGHLIGHT_STYLES[precommand]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[commandseparator]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[autodirectory]=fg=green,underline
        ZSH_HIGHLIGHT_STYLES[path]=bold
        ZSH_HIGHLIGHT_STYLES[path_pathseparator]=
        ZSH_HIGHLIGHT_STYLES[path_prefix_pathseparator]=
        ZSH_HIGHLIGHT_STYLES[globbing]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[history-expansion]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[command-substitution]=none
        ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[process-substitution]=none
        ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[single-hyphen-option]=fg=green
        ZSH_HIGHLIGHT_STYLES[double-hyphen-option]=fg=green
        ZSH_HIGHLIGHT_STYLES[back-quoted-argument]=none
        ZSH_HIGHLIGHT_STYLES[back-quoted-argument-delimiter]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[single-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[double-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]=fg=yellow
        ZSH_HIGHLIGHT_STYLES[rc-quote]=fg=magenta
        ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[assign]=none
        ZSH_HIGHLIGHT_STYLES[redirection]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[comment]=fg=black,bold
        ZSH_HIGHLIGHT_STYLES[named-fd]=none
        ZSH_HIGHLIGHT_STYLES[numeric-fd]=none
        ZSH_HIGHLIGHT_STYLES[arg0]=fg=cyan
        ZSH_HIGHLIGHT_STYLES[bracket-error]=fg=red,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-1]=fg=blue,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-2]=fg=green,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-3]=fg=magenta,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-4]=fg=yellow,bold
        ZSH_HIGHLIGHT_STYLES[bracket-level-5]=fg=cyan,bold
        ZSH_HIGHLIGHT_STYLES[cursor-matchingbracket]=standout
    fi
else
    PROMPT='${debian_chroot:+($debian_chroot)}%n@%m:%~%(#.#.$) '
fi
unset color_prompt force_color_prompt

toggle_oneline_prompt(){
    if [ "$PROMPT_ALTERNATIVE" = oneline ]; then
        PROMPT_ALTERNATIVE=twoline
    else
        PROMPT_ALTERNATIVE=oneline
    fi
    configure_prompt
    zle reset-prompt
}
zle -N toggle_oneline_prompt
bindkey ^P toggle_oneline_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty)
    TERM_TITLE=$'\e]0;${debian_chroot:+($debian_chroot)}${VIRTUAL_ENV:+($(basename $VIRTUAL_ENV))}%n@%m: %~\a'
    ;;
*)
    ;;
esac

precmd() {
    # Print the previously configured title
    print -Pnr -- "$TERM_TITLE"

    # Print a new line before the prompt, but only if it is not the first line
    if [ "$NEWLINE_BEFORE_PROMPT" = yes ]; then
        if [ -z "$_NEW_LINE_BEFORE_PROMPT" ]; then
            _NEW_LINE_BEFORE_PROMPT=1
        else
            print ""
        fi
    fi
}

# enable color support of ls, less and man, and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    export LS_COLORS="$LS_COLORS:ow=30;44:" # fix ls color for folders with 777 permissions

    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    alias diff='diff --color=auto'
    alias ip='ip --color=auto'

    export LESS_TERMCAP_mb=$'\E[1;31m'     # begin blink
    export LESS_TERMCAP_md=$'\E[1;36m'     # begin bold
    export LESS_TERMCAP_me=$'\E[0m'        # reset bold/blink
    export LESS_TERMCAP_so=$'\E[01;33m'    # begin reverse video
    export LESS_TERMCAP_se=$'\E[0m'        # reset reverse video
    export LESS_TERMCAP_us=$'\E[1;32m'     # begin underline
    export LESS_TERMCAP_ue=$'\E[0m'        # reset underline

    # Take advantage of $LS_COLORS for completion as well
    zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
    zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
fi

# enable auto-suggestions based on the history
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    . /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    # change suggestion color
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#999'
fi

# enable command-not-found if installed
if [ -f /etc/zsh_command_not_found ]; then
    . /etc/zsh_command_not_found
fi

# some more ls aliases
alias ll='ls -la'
alias la='ls -A'
alias lr='ls -lR'
alias l='ls -CF'
alias c='clear'

export PATH=$HOME/.local/bin:$PATH
ZSHRC

# ── .tmux.conf ──
cat > /root/.tmux.conf << 'TMUXCONF'
# ── Prefix ────────────────────────────────────────────
unbind-key C-b
set-option -g prefix C-a
bind-key C-a send-prefix

# ── General ───────────────────────────────────────────
set-option -g default-shell /usr/bin/zsh
set-option -g display-time 2000
set-option -g display-panes-time 2000
set-option -g history-limit 50000
set-option -g lock-after-time 3600
set-option -wg automatic-rename off
set-option -g mouse on
set-option -s escape-time 0

# ── Reload config ─────────────────────────────────────
bind-key C-r source-file ~/.tmux.conf \; display "Config Reloaded!"

# ── Indexing (start at 1) ─────────────────────────────
set-option -g base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on

# ── Kill pane / session ───────────────────────────────
unbind-key x
bind-key x kill-pane
bind-key X kill-session

# ── Splits (| and _ , keep cwd) ──────────────────────
bind-key | split-window -h -c "#{pane_current_path}"
bind-key _ split-window -v -c "#{pane_current_path}"

# ── Vim-style pane navigation ─────────────────────────
bind-key -r h select-pane -L
bind-key -r j select-pane -D
bind-key -r k select-pane -U
bind-key -r l select-pane -R
bind-key Up select-pane -U
bind-key Down select-pane -D
bind-key Left select-pane -L
bind-key Right select-pane -R
bind-key -r C-h select-window -t :-
bind-key -r C-l select-window -t :+
set-option -g status-keys vi

# ── Vim-style pane resizing ───────────────────────────
bind-key -r H resize-pane -L 2
bind-key -r J resize-pane -D 2
bind-key -r K resize-pane -U 2
bind-key -r L resize-pane -R 2

# ── Copy mode (vi + xclip) ───────────────────────────
set-window-option -g mode-keys vi
bind-key Escape copy-mode
bind-key -T copy-mode-vi 'v' send-keys -X begin-selection
bind-key -T copy-mode-vi 'y' send-keys -X copy-selection-and-cancel
bind-key C-b choose-buffer
unbind-key p
bind-key p paste-buffer
bind-key -T copy-mode-vi C-c send -X copy-pipe "xclip -i -sel p -f | xclip -i -sel c" \; display-message "copied to system clipboard"
bind-key C-v run "tmux set-buffer \"$(xclip -o -sel clipboard)\"; tmux paste-buffer"

# ── Colors (transparent-friendly) ─────────────────────
set -g default-terminal "screen-256color"
set-window-option -g pane-border-style fg=colour240
set-window-option -g pane-active-border-style fg=colour245
set-window-option -g window-style default
set-window-option -g window-active-style default
set-window-option -g message-style fg=colour250,bg=colour235

# ── Status bar (low contrast) ─────────────────────────
set-option -g status-style fg=colour245,bg=colour235
set-option -g status-justify centre
set-window-option -g window-status-style fg=colour245,bg=colour235
set-window-option -g window-status-current-style fg=colour250,bold,bg=colour238
set-window-option -g window-status-last-style fg=colour248,bg=colour236
set-window-option -g window-status-separator "|"
set-option -g status-left-length 50
set-option -g status-left "#[fg=colour245][S: #S W:#I-#W P:#P]"
set-option -g status-right-length 80
set-option -g status-right "#[fg=colour214]#(ip -4 addr show tun0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1) #[fg=colour245]#(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1) #[fg=colour240]up:#(uptime | cut -f 4-5 -d\" \" | cut -f 1 -d\",\")"
set-option -g status-interval 10
set-window-option -g monitor-activity on

# ── Plugins (tpm) ─────────────────────────────────────
# set -g @plugin 'tmux-plugins/tpm'
# set -g @plugin 'tmux-plugins/tmux-resurrect'
# set -g @plugin 'tmux-plugins/tmux-continuum'
# set -g @continuum-boot 'on'
# set -g @continuum-boot-options 'fullscreen'
# run '~/.tmux/plugins/tpm/tpm'
TMUXCONF

# ── 3. pwndbg ───────────────────────────────────────────────────────
log "Installing pwndbg"
if command -v pwndbg-gdb &>/dev/null || command -v pwndbg &>/dev/null || \
   gdb -q -batch -ex "pi import pwndbg; print('ok')" 2>/dev/null | grep -q ok; then
  echo "pwndbg already installed, skipping"
else
  curl -qsL 'https://install.pwndbg.re' | sh -s -- -t pwndbg-gdb
  if command -v pwndbg-gdb &>/dev/null && ! command -v pwndbg &>/dev/null; then
    ln -sf "$(command -v pwndbg-gdb)" /usr/local/bin/pwndbg
  fi
fi

if command -v pwndbg-gdb &>/dev/null; then
  echo "pwndbg wrapper: $(command -v pwndbg-gdb)"
elif command -v pwndbg &>/dev/null; then
  echo "pwndbg wrapper: $(command -v pwndbg)"
else
  echo "pwndbg install did not expose a wrapper in PATH; check installer output"
fi

# ── 4. pwninit ───────────────────────────────────────────────────────
log "Installing pwninit"
if ! command -v pwninit &>/dev/null; then
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    tmp_pwninit="$(mktemp)"
    curl -fsSL "https://github.com/io12/pwninit/releases/download/${PWNINIT_VERSION}/pwninit" -o "$tmp_pwninit"
    install -m 0755 "$tmp_pwninit" /usr/local/bin/pwninit
    rm -f "$tmp_pwninit"
  else
    echo "pwninit binary not available for $ARCH, skipping"
  fi
else
  echo "pwninit already installed, skipping"
fi

if command -v pwninit &>/dev/null; then
  pwninit --version 2>/dev/null || true
fi

# ── 5. uv (Python package manager) ──────────────────────────────────
log "Installing uv"
if ! command -v uv &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Source the env so uv is available in this session
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "uv already installed, skipping"
fi
if [[ -x "$HOME/.local/bin/uv" ]]; then
  ln -sf "$HOME/.local/bin/uv" /usr/local/bin/uv
fi

# ── 6. Clone & set up pwno-mcp ──────────────────────────────────────
log "Setting up pwno-mcp"
if [[ -d "$PWNO_DIR/.git" ]]; then
  echo "pwno-mcp already cloned at $PWNO_DIR, updating $PWNO_REF"
else
  git clone "$PWNO_REPO" "$PWNO_DIR"
fi
checkout_pwno_ref

# Install Python 3.12 via uv (matches pyproject.toml >=3.12,<3.14)
uv python install 3.12

# Sync the complete, locked project environment used by pwno-mcp and pwncli.
export UV_PROJECT_ENVIRONMENT="$PWNO_DIR/.venv"
uv sync --frozen --directory "$PWNO_DIR"

# ── 7. Pre-create shared Python venv (used by pwno-mcp at runtime) ──
log "Creating shared Python venv for pwno-mcp runtime"
SHARED_VENV="/tmp/pwno/python/shared_venv"
mkdir -p /tmp/pwno/python
uv venv "$SHARED_VENV" 2>/dev/null || true
uv pip install --python "$SHARED_VENV" \
  requests numpy ipython hexdump pwntools ropper 2>/dev/null || true

# ── 8. Create workspace ─────────────────────────────────────────────
log "Creating workspace at $WORKSPACE"
mkdir -p "$WORKSPACE"

# ── 9. systemd service ──────────────────────────────────────────────
log "Installing systemd service"
cat > /etc/systemd/system/pwnomcp.service <<UNIT
[Unit]
Description=Pwno MCP Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$PWNO_USER
WorkingDirectory=$PWNO_DIR
Environment=PYTHONPATH=$PWNO_DIR
Environment=UV_PROJECT_ENVIRONMENT=$PWNO_DIR/.venv
Environment=PWNO_WORKSPACE=$WORKSPACE
Environment=PWNO_GDB_DEBUGINFOD=$PWNO_GDB_DEBUGINFOD
Environment=TERM=xterm-256color
Environment=PATH=$PWNO_DIR/.venv/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$PWNO_DIR/.venv/bin/python -m pwnomcp --host $PWNO_HOST --port $PWNO_PORT --workspace $WORKSPACE
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable pwnomcp
systemctl restart pwnomcp

log "Verifying pwno-mcp service and MCP protocol"
wait_for_pwno_mcp

# ── 10. Codex CLI ────────────────────────────────────────────────────
if [[ "$INSTALL_CODEX" == "1" ]]; then
  log "Installing Codex CLI"
  if ! command -v codex &>/dev/null; then
    install_codex_release
  else
    echo "Codex CLI already installed, skipping"
  fi

  log "Configuring Codex MCP"
  mkdir -p "$CODEX_HOME"

  # This droplet is an intentionally disposable CTF/debug box.
  prepend_toml_key_once "$CODEX_HOME/config.toml" "approval_policy" 'approval_policy = "never"'
  prepend_toml_key_once "$CODEX_HOME/config.toml" "sandbox_mode" 'sandbox_mode = "danger-full-access"'
  append_toml_section_once "$CODEX_HOME/config.toml" "mcp_servers.pwno-mcp" "url = \"http://127.0.0.1:$PWNO_PORT/mcp\""
fi

# ── 11. Claude Code (optional) ───────────────────────────────────────
# Claude is disabled by default for this workflow. To enable it:
#   INSTALL_CLAUDE=1 ./setup-droplet.sh
if [[ "$INSTALL_CLAUDE" == "1" ]]; then
  log "Installing Claude Code"
  if ! command -v claude &>/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
  else
    echo "Claude Code already installed, skipping"
  fi

  log "Registering pwno-mcp MCP server in Claude Code"
  mkdir -p "$HOME/.claude"

  claude mcp add pwno-mcp --scope user -t stdio -- \
    "$PWNO_DIR/.venv/bin/python" -m pwnomcp --stdio --workspace "$WORKSPACE" 2>/dev/null || \
    echo "Claude MCP registration requires interactive shell — run manually:
    claude mcp add pwno-mcp --scope user -t stdio -- \\
      $PWNO_DIR/.venv/bin/python -m pwnomcp --stdio --workspace $WORKSPACE"

  log "Setting Claude Code permissions"
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" << 'SETTINGS'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "mcp__pwno-mcp__*"
    ]
  }
}
SETTINGS
fi

# ── Done ─────────────────────────────────────────────────────────────
log "Setup complete!"
echo ""
echo "  pwno-mcp service: systemctl status pwnomcp"
echo "  pwno-mcp logs:    journalctl -u pwnomcp -f"
echo "  Workspace:        $WORKSPACE"
echo "  HTTP endpoint:    http://$PWNO_HOST:$PWNO_PORT/mcp"
echo ""
if [[ "$INSTALL_CODEX" == "1" ]]; then
  echo "  To use with Codex CLI:"
  echo "    cd $WORKSPACE && CODEX_HOME=$CODEX_HOME codex"
  echo "    CODEX_HOME=$CODEX_HOME codex mcp list  # verify pwno-mcp is connected"
  echo ""
fi
if [[ "$INSTALL_CLAUDE" == "1" ]]; then
  echo "  To use with Claude Code:"
  echo "    cd $WORKSPACE && claude"
  echo "    /mcp  # verify pwno-mcp is connected"
  echo ""
fi
echo ""
echo "  To access remotely via SSH tunnel:"
echo "    ssh -L $PWNO_PORT:localhost:$PWNO_PORT root@<DROPLET_IP>"
echo "    Then connect MCP client to http://127.0.0.1:$PWNO_PORT/mcp"
echo ""
