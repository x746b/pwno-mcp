# Building cloud mcp-pwn box

## Cloud box config (e.g.: Digital Ocean)
1 GB Memory / 1 Intel vCPU / 35 GB Disk / Ubuntu 24.04 (LTS) x64 ~ 8 EUR/month

## Ubuntu packages installation
`apt update && apt install git docker.io docker-compose python3 python3-pwntools npm`

## pwno-mcp installation && test
```bash
cd /opt
git clone https://github.com/pwno-io/pwno-mcp

./docker-build.local.sh
...
Successfully tagged pwno-mcp:latest
Successfully tagged pwno-mcp:f75de6d
✓ Build successful!
To run the container:
  docker run -it --cap-add=SYS_PTRACE --cap-add=SYS_ADMIN --security-opt seccomp=unconfined pwno-mcp:latest
Or use docker-compose:
  docker-compose up -d
```

### test 
```bash
docker run -it --cap-add=SYS_PTRACE --cap-add=SYS_ADMIN --security-opt seccomp=unconfined pwno-mcp:latest

pwno@7645f98273d4:/app$ pwndbg 
pwndbg: loaded 212 pwndbg commands. Type pwndbg [filter] for a list.
pwndbg: created 13 GDB functions (can be used with print/break). Type help function to see them.
------- tip of the day (disable with set show-tips off) -------
Pwndbg sets the SIGLARM, SIGBUS, SIGPIPE and SIGSEGV signals so they are not passed to the app; see info signals for full GDB signals configuration
pwndbg> 
```

## Install claude code
```bash
npm install -g @anthropic-ai/claude-code
```

## Adding MCP to claude

```bash
claude mcp add pwndbg-mcp --scope user -- \
  docker run --rm -i \
    --user root \
    --cap-add=SYS_PTRACE \
    --cap-add=SYS_ADMIN \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -e PYTHONUNBUFFERED=1 \
    -v /root/ctf:/workspace \
    --entrypoint uv \
    pwno-mcp:latest \
    run python -m pwnomcp --stdio
```
### test
```bash
claude
/mcp 

 Manage MCP servers
 1 server

 ❯ 1. pwndbg-mcp  ✔ connected · Enter to view details
```

## Success

Example of outputs seen in claude code:
```bash
● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__set_file")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__run")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__set_breakpoint")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__get_context")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__run_command")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__sendinput")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__step_control")
  ⎿  Found 1 tool

● MCPSearch(Search MCP tools: "select:mcp__pwndbg-mcp__get_memory")
  ⎿  Found 1 tool

● pwndbg-mcp - set_file (MCP)(binary_path: "/root/ctf/challenge/ctf")
  ⎿  {                                                                       
       "result": {
         "command": "-file-exec-and-symbols /root/ctf/challenge/ctf",
     … +15 lines (ctrl+o to expand)

● Bash(pwd && realpath challenge/ctf)
  ⎿  /root/ctf                  
     /root/ctf/challenge/ctf

● Bash(cp -r challenge /tmp/ && ls -la /tmp/challenge/)
  ⎿  total 2440                                     
     drwxr-xr-x  2 root root    4096 Dec 20 22:00 .
     drwxrwxrwt 14 root root    4096 Dec 20 22:00 ..
     … +4 lines (ctrl+o to expand)

● pwndbg-mcp - set_file (MCP)(binary_path: "/workspace/challenge/ctf")
  ⎿  {                                                                    
       "result": {
         "command": "-file-exec-and-symbols /workspace/challenge/ctf",
     … +13 lines (ctrl+o to expand)

● pwndbg-mcp - set_breakpoint (MCP)(location: "vuln")
  ⎿  {                                   
       "result": {
         "command": "-break-insert vuln",
     … +27 lines (ctrl+o to expand)

● pwndbg-mcp - set_breakpoint (MCP)(location: "malloc")
  ⎿  {                                     
       "result": {
         "command": "-break-insert malloc",
     … +27 lines (ctrl+o to expand)

● pwndbg-mcp - set_breakpoint (MCP)(location: "free")
  ⎿  {                                   
       "result": {
         "command": "-break-insert free",
     … +27 lines (ctrl+o to expand)

● Bash(objdump -d -M intel challenge/ctf | grep -A 30 "<vuln>:")
  ⎿  00000000000011ee <vuln>:                              
         11ee:  55                      push   rbp
         11ef:  48 89 e5                mov    rbp,rsp
     … +28 lines (ctrl+o to expand)

● pwndbg-mcp - run (MCP)(args: "0x1000", start: true)
  ⎿  {                                  
       "result": {
         "command": "-exec-run --start",
     … +301 lines (ctrl+o to expand)

● pwndbg-mcp - get_context (MCP)(context_type: "regs")
  ⎿  {                              
       "result": {
         "command": "context regs",
     … +154 lines (ctrl+o to expand)

● pwndbg-mcp - step_control (MCP)(command: "c")
  ⎿  {                               
       "result": {
         "command": "-exec-continue",
     … +76 lines (ctrl+o to expand)

● pwndbg-mcp - get_context (MCP)(context_type: "regs")
  ⎿  {                              
       "result": {
         "command": "context regs",
     … +148 lines (ctrl+o to expand)

...
  Looking at the disassembly:
  - 122a-123c: This is the buggy bounds check logic
    - The check !(0 <= i < size) is implemented incorrectly
    - At 122d: not eax followed by shr eax, 0x1f - this extracts the sign bit
    - Then it compares with size at 1239: cmp rdx, rax
    - And jumps if below at 123c: jb 1248
...

● pwndbg-mcp - step_control (MCP)(command: "c")
  ⎿  {                                                                                     
       "result": {
         "command": "-exec-continue",
         "responses": [
           {
             "type": "result",
             "message": "running",
             "payload": null,
             "token": null,
             "stream": "stdout"
           },
           {
             "type": "notify",
             "message": "running",
             "payload": {
               "thread-id": "all"
             },
             "token": null,
             "stream": "stdout"
           },
           {
             "type": "notify",
             "message": "breakpoint-modified",
             "payload": {
               "bkpt": {
                 "number": "2",
                 "type": "breakpoint",
                 "disp": "keep",
                 "enabled": "y",
                 "addr": "0x00007ffff7ca5120",
                 "at": "<malloc>",
                 "thread-groups": [
                   "i1"
                 ],
                 "times": "1",
                 "original-location": "malloc"
               }
             },
             "token": null,
             "stream": "stdout"
           },
           {
             "type": "console",
             "message": null,
             "payload": "\n",
             "stream": "stdout"
           },
           {
             "type": "console",
             "message": null,
             "payload": "Breakpoint 2, 0x00007ffff7ca5120 in malloc () from ./libc.so.6\n",
             "stream": "stdout"
           },
           {
             "type": "notify",
             "message": "stopped",
             "payload": {
               "reason": "breakpoint-hit",
               "disp": "keep",
               "bkptno": "2",
               "frame": {
                 "addr": "0x00007ffff7ca5120",
                 "func": "malloc",
                 "args": [],
                 "from": "./libc.so.6",
                 "arch": "i386:x86-64"
               },
               "thread-id": "1",
               "stopped-threads": "all",
               "core": "0"
             },
             "token": null,
             "stream": "stdout"
           }
         ],
         "success": true,
         "state": "stopped"
       }
     }
...
```

## codex

### Install
```bash
wget https://github.com/openai/codex/releases/download/rust-v0.76.0/codex-x86_64-unknown-linux-gnu.tar.gz
tar -xvzf codex-x86_64-unknown-linux-gnu.tar.gz && mv codex-x86_64-unknown-linux-gnu /usr/local/bin/codex
```

### Activation codex without browser:
```bash
ssh -L 1455:localhost:1455 -i ubupwn root@ubupwn
```

## Adding MCP to codex
```bash
codex mcp add pwndbg-mcp -- \
  docker run --rm -i \
    --user root \
    --cap-add=SYS_PTRACE \
    --cap-add=SYS_ADMIN \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -e PYTHONUNBUFFERED=1 \
    -v /root/ctf:/workspace \
    --entrypoint uv \
    pwno-mcp:latest \
    run python -m pwnomcp --stdio
```

### Test:
```bash
/mcp

🔌  MCP Tools

  • pwndbg-mcp
    • Status: enabled
    • Auth: Unsupported
    • Command: docker run --rm -i --user root --cap-add=SYS_PTRACE --cap-add=SYS_ADMIN --security-opt seccomp=unconfined --security-opt apparmor=unconfined -e PYTHONUNBUFFERED=1 -v /root/ctf:/workspace --entrypoint uv pwno-mcp:latest run
python -m pwnomcp --stdio
    • Tools: attach, checkoutput, execute, execute_python_code, execute_python_script, fetch_repo, finish, get_context, get_decompiled_code, get_memory, get_process, get_retdec_status, get_session_info, install_python_packages, jump,
kill_process, list_processes, list_python_packages, pwncli, return_from_function, run, run_command, sendinput, set_breakpoint, set_file, spawn_process, step_control, until
    • Resources: (none)
    • Resource templates: (none)
```

codex using pwno-mcp:

```bash
Called pwndbg-mcp.run_command({"command":"ls -la /workspace/challenge","timeout":10})
  └ {"success": true, "command": "ls -la /workspace/challenge", "returncode": 0, "stdout": "total 2448\ndrwxr-xr-x 3 root root    4096 Dec 21 20:14 .\ndrwxr-xr-x 4 root root    4096 Dec 21 20:13 ..\ndrwxr-xr-x 2 root root    4096 Dec 21
        20:14 __pycache__\n-rwxr-xr-x 1 root root   20704 Dec 20 20:53 ctf\n-rwxr-xr-x 1 root root  240936 Dec 20 20:53 ld-2.35.so\n-rw-r--r-- 1 root root 2216304 Dec 20 20:53 libc.so.6\n-rw-r--r-- 1 root root      29 Dec 20 22:42
        password\n-rw-r--r-- 1 root root    2192 Dec 20 20:53 server.py\n", "stderr": "", "cwd": "/workspace"}

• I’m piecing together a plan to exploit a local service with pwntools and pwndbg MCP, focusing on leveraging tcache poisoning despite safe-linking in glibc 2.35. I want to get arbitrary write by crafting fake chunks on the heap and use byte-wise writes through negative indexing. 

  Setting breakpoint at vuln function

• Called pwndbg-mcp.set_file({"binary_path":"/workspace/challenge/ctf"})
  └ {"command": "-file-exec-and-symbols /workspace/challenge/ctf", "responses": [{"type": "result", "message": "done", "payload": null, "token": null, "stream": "stdout"}], "success": true, "state": "stopped"}

• Called pwndbg-mcp.set_breakpoint({"location":"vuln"})
  └ {"command": "-break-insert vuln", "responses": [{"type": "result", "message": "done", "payload": {"bkpt": {"number": "1", "type": "breakpoint", "disp": "keep", "enabled": "y", "addr": "0x00000000000011f2", "at": "<vuln+4>", "thread-
        groups": ["i1"], "times": "0", "original-location": "vuln"}}, "token": null, "stream": "stdout"}], "success": true, "state": "stopped"}

• Called pwndbg-mcp.run({"args":"4096","start":false})
  └ {"command": "-exec-run", "responses": [{"type": "notify", "message": "thread-group-started", "payload": {"id": "i1", "pid": "33"}, "token": null, "stream": "stdout"}, {"type": "notify", "message": "thread-created", "payload": {"id":
        "1", "group-id": "i1"}, "token": null, "stream": "stdout"}, {"type": "notify", "message": "breakpoint-modified", "payload": {"bkpt": {"number": "1", "type": "breakpoint", "disp": "keep", "enabled": "y", "addr":
        "0x00005555555551f2", "at": "<vuln+4>", "thread-groups": ["i1"], "times": "0", "original-location": "vuln"}}, "token": null, "stream": "stdout"}, {"type": "notify", "message": "library-loaded", "payload": {"id": "./ld-2.35.so",
        "target-name": "./ld-2.35.so", "host-name": "./ld-2.35.so", "symbols-loaded": "0", "thread-group": "i1", "ranges": [{"from": "0x00007ffff7fc5090", "to": "0x00007ffff7fee335"}]}, "token": null, "stream": "stdout"}, {"type":
        "result", "message": "running", "payload": null, "token": null, "stream": "stdout"}, {"type": "notify", "message": "running", "payload": {"thread-id": "all"}, "token": null, "stream": "stdout"}, {"type": "notify", "message":
        "library-loaded", "payload": {"id": "./lib...

• Called pwndbg-mcp.execute({"command":"info proc mappings"})
  └ {"command": "info proc mappings", "responses": [{"type": "log", "message": null, "payload": "info proc mappings\n", "stream": "stdout"}, {"type": "console", "message": null, "payload": "process 33\n", "stream": "stdout"}, {"type":
        "console", "message": null, "payload": "Mapped address spaces:\n\n", "stream": "stdout"}, {"type": "console", "message": null, "payload": "Start Addr         End Addr           Size               Offset             Perms File \n",
        "stream": "stdout"}, {"type": "console", "message": null, "payload": "0x0000555555554000 0x0000555555555000 0x1000             0x0                r--p  /workspace/challenge/ctf \n", "stream": "stdout"}, {"type": "console",
        "message": null, "payload": "0x0000555555555000 0x0000555555556000 0x1000             0x1000             r-xp  /workspace/challenge/ctf \n", "stream": "stdout"}, {"type": "console", "message": null, "payload":
        "0x0000555555556000 0x0000555555557000 0x1000             0x2000             r--p  /workspace/challenge/ctf \n", "stream": "stdout"}, {"type": "console", "message": null, "payload": "0x0000555555557000 0x0000555555558000
        0x1000             0x2000         ...

• Called pwndbg-mcp.execute({"command":"p/x $rbp"})
  └ {"command": "p/x $rbp", "responses": [{"type": "log", "message": null, "payload": "p/x $rbp\n", "stream": "stdout"}, {"type": "console", "message": null, "payload": "$1 = 0x7fffffffe9b0\n", "stream": "stdout"}, {"type": "result",
        "message": "done", "payload": null, "token": null, "stream": "stdout"}], "success": true, "state": "stopped"}

• Called pwndbg-mcp.execute_python_code({"code":"stack_high=0x7ffffffff000\nrbp=0x7fffffffe9b0\nsaved=rbp+8\nprint(hex(stack_high-saved))"})
  └ {"success": true, "script": "/tmp/pwno_script_efrzg5rc.py", "venv_path": "/tmp/pwno_python_workspace/shared_venv", "returncode": 0, "stdout": "0x648\n", "stderr": "", "command": "/tmp/pwno_python_workspace/shared_venv/bin/python /tmp/
        pwno_script_efrzg5rc.py", "cwd": "/workspace", "code_preview": "stack_high=0x7ffffffff000\nrbp=0x7fffffffe9b0\nsaved=rbp+8\nprint(hex(stack_high-saved))"}
...
```
