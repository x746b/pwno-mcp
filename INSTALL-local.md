# INSTALL locally

## Purpose

Local installation and execution of pwno-mcp on the host without containers, using uv for environment and dependency management.

The upstream service starts the server using:

- uv run -m pwnomcp --host 0.0.0.0 --port 5500

This guide follows the same approach, with a localhost default.

## Requirements

### Platform

- Linux is assumed (examples use Ubuntu/Debian package names).
- macOS should work with equivalent packages and toolchains.

### Python

- Python 3.13+ is required by the project (`requires-python = ">=3.13"`).

### Tooling

- git
- uv (Astral)
- a working compiler toolchain (for native wheels if needed)

### Debugger prerequisites

- GDB installed on the host
- GDB built with Python support
- pwndbg installed and enabled via `~/.gdbinit`

## 1) System packages (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install -y git gdb build-essential cmake pkg-config wget
````

If Python packages need native compilation, these are commonly required:

```bash
sudo apt install -y python3-dev libffi-dev libssl-dev
```

## 2) Install uv

Install uv using Astral’s installer:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Ensure `~/.local/bin` is on PATH, then verify:

```bash
uv --version
```

## 3) Clone the repository

```bash
git clone https://github.com/pwno-io/pwno-mcp.git
cd pwno-mcp
```

## 4) Install Python 3.13 via uv

Install a managed Python 3.13 interpreter:

```bash
uv python install 3.13
```

Verify:

```bash
uv run --python 3.13 -- python -V
```

## 5) Create/sync the virtual environment

Create and sync the environment from `pyproject.toml`:

```bash
uv sync
```

If an explicit venv location is preferred, set `UV_PROJECT_ENVIRONMENT` (similar to the service pattern):

```bash
export UV_PROJECT_ENVIRONMENT="$PWD/.venv"
uv sync
```

## 6) Install and enable pwndbg

pwndbg is expected to be loaded by GDB (typically via `~/.gdbinit`). A common install method:

```bash
git clone https://github.com/pwndbg/pwndbg.git ~/pwndbg
cd ~/pwndbg
./setup.sh
```

Sanity check:

```bash
gdb -q -ex "pi print('pwndbg ok')" -ex quit
```

If pwndbg does not load, check `~/.gdbinit` for pwndbg initialization.

## 7) Optional: .nonce file

A `.nonce` file is ignored by `.gitignore`, so it can be created locally without affecting the repo.

```bash
openssl rand -hex 16 > .nonce
chmod 600 .nonce
```

If authentication is enabled in the runtime configuration, the `.nonce` content may be required by the client (implementation-dependent).

## 8) Run pwno-mcp (no container)

Bind to localhost (recommended default):

```bash
export UV_PROJECT_ENVIRONMENT="$PWD/.venv"
uv run -m pwnomcp --host 127.0.0.1 --port 5500
```

Bind to all interfaces (LAN-accessible):

```bash
export UV_PROJECT_ENVIRONMENT="$PWD/.venv"
uv run -m pwnomcp --host 0.0.0.0 --port 5500
```

## 9) Optional: systemd service (host-native)

A systemd unit can be installed to run the server at boot. Create:

`/etc/systemd/system/pwnomcp.service`

Adjust `User`, paths, and `--host/--port` as needed.

```ini
[Unit]
Description=Pwno MCP
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=REPLACE_WITH_USER
WorkingDirectory=/home/REPLACE_WITH_USER/pwno-mcp
Environment=PYTHONPATH=/home/REPLACE_WITH_USER/pwno-mcp
Environment=UV_PROJECT_ENVIRONMENT=/home/REPLACE_WITH_USER/pwno-mcp/.venv
ExecStart=/bin/bash -lc '/home/REPLACE_WITH_USER/.local/bin/uv run -m pwnomcp --host 127.0.0.1 --port 5500'
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now pwnomcp
sudo systemctl status pwnomcp
```

Logs:

```bash
journalctl -u pwnomcp -f
```

## Troubleshooting

### Python version mismatch

If `uv sync` fails due to Python version constraints:

```bash
uv python install 3.13
uv run --python 3.13 -- python -V
```

### pwndbg not loading in GDB

* confirm pwndbg installation completed successfully
* confirm `~/.gdbinit` contains pwndbg initialization
* confirm GDB has Python support (some minimal builds do not)

Quick check:

```bash
gdb -q -ex "pi import sys; print(sys.version)" -ex quit
```

If Python import fails inside GDB, a Python-enabled GDB build must be installed.

### Build failures while installing dependencies

If compilation errors occur during dependency install:

```bash
sudo apt install -y build-essential python3-dev libffi-dev libssl-dev
uv sync
```

## Notes

* The default port used by the repo’s service example is 5500.
* Binding to 127.0.0.1 keeps the service local; binding to 0.0.0.0 exposes it to the network.

```
::contentReference[oaicite:0]{index=0}
```
