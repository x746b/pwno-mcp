# Building cloud mcp-pwn box

## Cloud box config (e.g.: Digital Ocean)
1 GB Memory / 1 Intel vCPU / 35 GB Disk / Ubuntu 24.04 (LTS) x64 ~ 8 EUR/month

## Ubuntu packages installation
apt update && apt install git docker.io docker-compose python3 python3-pwntools npm

## pwno-mcp installation && test
```
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
```
npm install -g @anthropic-ai/claude-code
```

## Adding MCP to claude
```
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
```
claude
/mcp 

 Manage MCP servers
 1 server

 ❯ 1. pwndbg-mcp  ✔ connected · Enter to view details
```

## Adding MCP to codex
```
## Codex
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


## Success

Example of outputs seen in claude code:
```
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

