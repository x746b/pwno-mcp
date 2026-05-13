# pwno-mcp (fork) — Docker-Free CTF Pwn Box

Fork of [pwno-io/pwno-mcp](https://github.com/pwno-io/pwno-mcp) adapted for **bare-metal cloud deployment** without Docker.

Runs GDB + pwndbg natively and exposes stateful debugging over MCP for agentic coding clients.

---

## Cloud pwn/rev dropplet

https://github.com/x746b/pwno-mcp/blob/main/setup-droplet.sh

Provision a fresh Ubuntu 24.04 droplet (DigitalOcean, Scaleway, etc.) as a fully configured CTF pwn box:

```bash
scp setup-droplet.sh root@<DROPLET_IP>:/root/
ssh root@<DROPLET_IP> 'bash /root/setup-droplet.sh'
```

Recommended: **1 vCPU / 1GB RAM / 25GB disk** (~$6/month). The script creates 2GB swap automatically.

### What it installs

- **Toolchain**: gcc, g++, clang, make, cmake, 32-bit libs, ASAN
- **Debuggers**: GDB + pwndbg, gdb-multiarch, lldb, strace, ltrace
- **Emulation**: qemu-user, qemu-system-x86
- **Python**: uv + Python 3.12, pwntools, ropper
- **pwno-mcp**: cloned, synced, running as systemd service
- **AI CLIs: Codex/Claude Code**: installed with pwno-mcp registered as MCP server
- **Shell**: zsh with syntax highlighting + autosuggestions, tmux with custom config
- **Extras**: pwninit, patchelf, elfutils

[![DigitalOcean Referral Badge](https://web-platforms.sfo2.cdn.digitaloceanspaces.com/WWW/Badge%201.svg)](https://www.digitalocean.com/?refcode=3afc1c808652&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge)

---

## Differences from Upstream

| Feature | Upstream | This fork |
|---------|----------|-----------|
| Runtime | Docker container | Bare metal / systemd |
| Workspace | Hardcoded `/workspace` | Configurable via `--workspace` or `PWNO_WORKSPACE` |
| Setup | Manual Docker + MCP config | Single `setup-droplet.sh` script |
| Target | General MCP deployment | Cloud CTF box with full toolchain |

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

See [README_orig.md](README_orig.md) for the full upstream documentation including:
- Complete tool reference (set_file, breakpoints, stepping, memory, context, etc.)
- MCP client configs for Claude Desktop, Cursor, OpenCode, Codex
- Project structure and design decisions
- Upstream docs site: [docs.pwno.io](https://docs.pwno.io)

## Upstream

Synced with [pwno-io/pwno-mcp](https://github.com/pwno-io/pwno-mcp) through upstream `v0.2.1` era changes. Original project by [Pwno Team](https://pwno.io).
