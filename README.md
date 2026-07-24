# pwno-mcp (fork) — Docker-Free CTF Pwn Box

Fork of [pwno-io/pwno-mcp](https://github.com/pwno-io/pwno-mcp) adapted for **bare-metal cloud deployment** without Docker.

Runs GDB + pwndbg natively and exposes stateful debugging over MCP for agentic coding clients.

Current release: **v0.3.0**

### v0.3.0 highlights

- deterministic bare-metal deployment with configurable Git ref, workspace, and bind settings
- post-deployment HTTP/MCP/runtime health verification
- stable GDB startup with configurable debuginfod behavior
- server-interpreter `pwncli` drivers with binary-safe I/O and structured exit events
- MCP initialization and tool guidance designed for autonomous exploit workflows

---

## Cloud pwn/rev droplet

https://github.com/x746b/pwno-mcp/blob/main/setup-droplet.sh

Provision a fresh Ubuntu 24.04 droplet (DigitalOcean, Scaleway, etc.) as a fully configured CTF pwn box:

```bash
scp setup-droplet.sh root@<DROPLET_IP>:/root/
ssh root@<DROPLET_IP> 'bash /root/setup-droplet.sh'
```

To deploy a particular branch, tag, or commit directly from your workstation:

```bash
ssh root@<DROPLET_IP> \
  'PWNO_REF=<branch-tag-or-commit> INSTALL_CODEX=0 INSTALL_CLAUDE=0 bash -s' \
  < setup-droplet.sh
```

For a reproducible v0.3.0 installation, set `PWNO_REF=v0.3.0`.

Tested on:
- DigitalOcean: s-1vcpu-1gb: 1 vCPU / 1GB RAM / 25GB disk (~$0.006/hour). The script creates 2GB swap automatically.
- Scaleway: DEV1-S: 2 vCPU/ 2GB RAM / 10GB disk (~€0.01398/hour)

### What it installs

- **Toolchain**: gcc, g++, clang, make, cmake, 32-bit libs, ASAN
- **Debuggers**: GDB + pwndbg, gdb-multiarch, lldb, strace, ltrace
- **Emulation**: qemu-user, qemu-system-x86
- **Python**: uv + Python 3.12, pwntools, ropper
- **pwno-mcp**: cloned, synced, running as systemd service
- **AI CLIs: Codex/Claude Code**: installed with pwno-mcp registered as MCP server
- **Shell**: zsh with syntax highlighting + autosuggestions, tmux with custom config
- **Extras**: pwninit, patchelf, elfutils

### Deployment controls and verification

`setup-droplet.sh` is safe to rerun and accepts environment overrides:

| Variable | Default | Purpose |
|----------|---------|---------|
| `PWNO_REPO` | this fork | Git source URL or local bundle |
| `PWNO_REF` | `main` | branch, tag, or commit to deploy |
| `PWNO_DIR` | `/opt/pwno-mcp` | installation directory |
| `WORKSPACE` | `/root/ctf` | binary workspace exposed to MCP tools |
| `PWNO_HOST` / `PWNO_PORT` | `127.0.0.1` / `5500` | HTTP bind address |
| `PWNO_GDB_DEBUGINFOD` | `off` | GDB debug-symbol downloads: `on`, `off`, or `ask` |
| `PWNO_HEALTH_RETRIES` | `30` | one-second startup verification attempts |

The setup only reports success after the systemd service responds on `/healthz`,
negotiates MCP, exposes the required tools, imports `pwn` and `pwncli`, and reports
the expected virtual-environment interpreter. Run the same complete check manually:

```bash
/opt/pwno-mcp/.venv/bin/python -m pwnomcp.healthcheck \
  --url http://127.0.0.1:5500/mcp
```

Debuginfod is disabled by default because background debug-symbol downloads can
make otherwise valid GDB calls exceed the MCP timeout. Enable it only when those
external symbols are worth the additional latency.

[![DigitalOcean Referral Badge](https://web-platforms.sfo2.cdn.digitaloceanspaces.com/WWW/Badge%201.svg)](https://www.digitalocean.com/?refcode=3afc1c808652&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge)

---

## Differences from Upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Runtime | Docker container | Bare metal / systemd |
| Workspace | Hardcoded `/workspace` | Configurable via `--workspace` or `PWNO_WORKSPACE` |
| Setup | Manual Docker + MCP config | Single `setup-droplet.sh` script |
| Target | General MCP deployment | Cloud CTF box with full toolchain |
| Exploit I/O | Text-oriented | Binary-safe base64 input/output plus structured events |

## Custom Workspace

No more symlinking binaries to `/workspace`:

```bash
# CLI flag
python -m pwnomcp --stdio --workspace /root/ctf

# Environment variable
PWNO_WORKSPACE=/root/ctf python -m pwnomcp --stdio

# systemd service (set in setup script)
Environment=PWNO_WORKSPACE=/root/ctf
```

## MCP Client Config

The setup script auto-registers pwno-mcp in Claude Code. For manual config or other clients:

### Claude Code (stdio, no Docker)

```bash
claude mcp add pwno-mcp --scope user -t stdio -- \
  /opt/pwno-mcp/.venv/bin/python -m pwnomcp --stdio --workspace /root/ctf
```

### HTTP mode (for remote access)

```bash
# On server (already running via systemd)
systemctl status pwnomcp

# From local machine, tunnel to server
ssh -L 5500:localhost:5500 root@<DROPLET_IP>

# Then connect any MCP client to
# http://127.0.0.1:5500/mcp
```

## Tool Reference

The server publishes concise operating instructions during MCP initialization, and
each tool schema includes agent-facing workflow guidance. In particular, agents are
told to create explicit sessions, use the configured workspace, keep target execution
inside GDB, and use base64 fields for exact exploit bytes.

Repository documentation:

- [Tool reference](docs/tool-reference/index.mdx)
- [Interactive exploit loop](docs/guides/interactive-exploit-loop.mdx)
- [Configuration](docs/operations/configuration.mdx)
- [Troubleshooting](docs/troubleshooting.mdx)

For a binary-safe driver loop, use `data_b64` with `sendinput`, decode
`current_output_b64` and `output_b64`, and poll `checkevents` until `exit_code` is
non-null or `alive` is false. Both `checkoutput` and `checkevents` drain the data they
return, and `sendinput` never appends a newline automatically.

## Upstream

Synced with [pwno-io/pwno-mcp](https://github.com/pwno-io/pwno-mcp) through upstream `v0.2.1` era changes. Original project by [Pwno Team](https://pwno.io).
