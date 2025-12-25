# DAP (Debug Adapter Protocol) Configuration

This directory contains comprehensive debugging configurations for multiple languages and scenarios, including remote debugging support.

## Files Overview

- **init.lua** - Base DAP configuration with colored breakpoint icons
- **python.lua** - Python debugging with debugpy adapter
- **remote.lua** - Remote C++ debugging via SSH and gdbserver (436 lines, complex)
- **ui.lua** - DAP UI layout and panels
- **logger.lua** - Debug output capture with show/hide keybindings

## Quick Start

### Local Python Debugging

1. Open a Python file
2. Set breakpoints with `<leader>db`
3. Start debugging with `:DapContinue` or `<leader>dc`

**Environment Variables:**
- `DEBUG_EXEC` - Path to Python script to debug (default: current file)
- `DEBUG_ARGS` - Space-separated command-line arguments

**Example:**
```bash
DEBUG_EXEC=/path/to/script.py DEBUG_ARGS="--arg1 value1 --arg2" nvim
```

### Local C++ Debugging

1. Build your project with debug symbols (`cmake -DCMAKE_BUILD_TYPE=Debug`)
2. Open the source file
3. Set breakpoints with `<leader>db`
4. Launch with `:DapContinue`

## Remote C++ Debugging

The remote debugging configuration (`remote.lua`) provides sophisticated SSH-based debugging with automatic file deployment and output monitoring.

### Architecture

```
┌─────────────┐                 ┌──────────────┐
│   Neovim    │    SSH Tunnel   │    Remote    │
│             │◄───────────────►│   Device     │
│   DAP UI    │                 │              │
│             │                 │  gdbserver   │
│   GDB       │◄───────────────►│  :10000      │
│             │                 │              │
└─────────────┘                 └──────────────┘
        │                               ▲
        │ SCP Upload                    │
        └──────────────────────────────►│
                                  Program + Libs
```

### Prerequisites

1. **Remote Device Setup:**
   - SSH access with root privileges
   - gdbserver installed
   - Network connectivity on specified ports

2. **Local Setup:**
   - `sshpass` installed for password authentication
   - GDB with remote debugging support
   - Cross-compilation toolchain (for embedded targets)

3. **CMake Project:**
   - CMakeCache.txt must contain:
     - `DEPLOY_REMOTE_PATH` - Remote deployment directory
     - `REMOTE_SSH_HOST` - Remote device IP/hostname
     - `REMOTE_SSH_PASS` - SSH password (consider using SSH keys instead)

### Environment Variables

#### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `REMOTE_SSH_HOST` | Remote device IP or hostname | `192.168.1.100` |
| `REMOTE_SSH_PORT` | SSH port (default: 2222) | `2222` |
| `SSHPASS` | SSH password for sshpass | `yourpassword` |
| `LOCAL_PROGRAM_PATH` | Local executable path to deploy | `build/bin/myapp` |
| `REMOTE_GDBSERVER_PORT` | gdbserver port (default: 10000) | `10000` |

#### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCAL_GDB_PATH` | Path to local GDB | `/usr/bin/gdb` |
| `OECORE_TARGET_SYSROOT` | Yocto SDK sysroot path | - |

#### CMakeCache.txt Variables

These are automatically read from CMakeCache.txt:

- `DEPLOY_REMOTE_PATH` - Remote directory for deployment (e.g., `/home/root/`)
- `REMOTE_SSH_HOST` - Can override environment variable
- `REMOTE_SSH_PASS` - Can override SSHPASS

### Remote Debugging Workflow

#### Method 1: Using CMake Integration (Recommended)

The `cpp/cmake.lua` plugin automatically triggers deployment before remote debugging.

1. **Set environment variables:**
   ```bash
   export LOCAL_PROGRAM_PATH=build/bin/myapp
   export REMOTE_SSH_HOST=192.168.1.100
   export SSHPASS=yourpassword
   ```

2. **Launch debug session:**
   ```vim
   :lua dap_remote_debug()
   ```
   Or use the keymap: `<leader>dR` (defined in your keymaps.lua)

3. **What happens automatically:**
   - Reads CMakeCache.txt for DEPLOY_REMOTE_PATH
   - Creates remote directory if needed
   - Uploads executable via SCP
   - Sets executable permissions
   - Launches gdbserver on remote device
   - Monitors stdout/stderr via remote file tailing
   - Connects GDB to gdbserver
   - Opens DAP UI

#### Method 2: Manual Configuration

You can also set variables programmatically:

```lua
vim.env.LOCAL_PROGRAM_PATH = "build/bin/myapp"
vim.env.REMOTE_SSH_HOST = "192.168.1.100"
vim.env.SSHPASS = "yourpassword"
vim.env.REMOTE_SSH_PORT = "2222"
vim.env.REMOTE_GDBSERVER_PORT = "10000"

require('dap').continue()
```

### Remote Debugging Features

#### 1. Automatic File Deployment

- Parses `DEPLOY_REMOTE_PATH` from CMakeCache.txt
- Creates remote directory structure if missing
- Uploads executable via SCP
- Sets execute permissions (`chmod +x`)

#### 2. Remote Output Monitoring

The configuration monitors remote program output in real-time:

- Creates `/tmp/dap_stdout.txt` and `/tmp/dap_stderr.txt` on remote device
- Uses timer-based polling to tail output
- Displays output in DAP UI console with timestamps
- Format: `[TIMESTAMP] [STDOUT/STDERR] message`

#### 3. Pretty Printers

If using Yocto/embedded toolchain with custom GDB pretty printers:

```lua
setupCommands = {
  { text = "python sys.path.insert(0, '/path/to/pretty_printers')" },
  { text = "python import zo_pretty_printers; zo_pretty_printers.register_printers(gdb.current_objfile())" },
}
```

### Keybindings

#### Debug Control
- `<leader>dc` - Continue execution
- `<leader>ds` - Step over
- `<leader>di` - Step into
- `<leader>do` - Step out
- `<leader>db` - Toggle breakpoint
- `<leader>dB` - Set conditional breakpoint
- `<leader>dd` - Disconnect debugger
- `<leader>dR` - Launch remote debug with arguments prompt

#### Log Viewing
- `<leader>dl` - Show debug logs
- `<leader>dh` - Hide debug logs

#### DAP UI
- Automatically opens when debugging starts
- Automatically closes when debugging ends
- Panels:
  - **Left/Right**: Scopes, locals, watches
  - **Bottom**: REPL, console, breakpoints, stack trace

## Troubleshooting

### Common Issues

#### 1. "REMOTE_SSH_HOST not defined"
```bash
export REMOTE_SSH_HOST=192.168.1.100
# Or add to CMakeCache.txt:
REMOTE_SSH_HOST:STRING=192.168.1.100
```

#### 2. "LOCAL_PROGRAM_PATH does not exist"
Ensure your executable is built and the path is correct:
```bash
export LOCAL_PROGRAM_PATH=$(pwd)/build/bin/myapp
ls -l $LOCAL_PROGRAM_PATH  # Verify it exists
```

#### 3. "SCP failed" or "SSH connection refused"
Check connectivity:
```bash
ssh -p 2222 root@$REMOTE_SSH_HOST echo "Connected"
```

#### 4. "gdbserver not found on remote"
Install gdbserver on the remote device:
```bash
ssh root@remote "apt-get install gdbserver"  # Debian/Ubuntu
# Or for Yocto/embedded: include gdbserver in your image recipe
```

#### 5. "Cannot connect to gdbserver"
- Verify gdbserver is running: `ssh root@remote "ps aux | grep gdbserver"`
- Check port is not in use: `ssh root@remote "netstat -tuln | grep 10000"`
- Verify firewall allows the port

#### 6. "Breakpoints not hitting"
- Ensure program is built with debug symbols: `-g` flag
- Check that deployed binary matches source code
- Verify source paths match between local and remote

### Debug Mode Verification

Check DAP configuration:
```lua
:lua print(vim.inspect(require('dap').configurations.cpp))
```

Check environment variables:
```lua
:lua print(os.getenv("REMOTE_SSH_HOST"))
:lua print(os.getenv("LOCAL_PROGRAM_PATH"))
```

### Verbose Logging

Enable DAP logging to see detailed communication:
```lua
require('dap').set_log_level('TRACE')
```

View logs:
```bash
tail -f ~/.cache/nvim/dap.log
```

## Advanced Configuration

### Custom GDB Commands

Modify `setupCommands` in remote.lua to add custom GDB initialization:

```lua
setupCommands = {
  { text = "-enable-pretty-printing" },
  { text = "set print pretty on" },
  { text = "source /path/to/custom.gdb" },  -- Add custom commands
}
```

### Custom Deployment Paths

Override CMakeCache.txt values at runtime:

```lua
vim.fn.setenv("DEPLOY_REMOTE_PATH", "/custom/remote/path/")
```

### Multiple Remote Configurations

Create additional configurations in remote.lua:

```lua
table.insert(dap.configurations.cpp, {
  name = "REMOTE DEBUG - Device 2",
  type = "cppdbg",
  request = "launch",
  miDebuggerServerAddress = "192.168.1.101:10000",
  -- ... rest of config
})
```

### SSH Key Authentication

For better security, use SSH keys instead of passwords:

1. Generate SSH key: `ssh-keygen -t ed25519`
2. Copy to remote: `ssh-copy-id root@remote`
3. Modify remote.lua to remove `sshpass -e` and use plain `ssh/scp`

## Project-Specific DAP Configuration

For project-specific settings, create `.nvim/dap.lua` in your project root:

```lua
-- .nvim/dap.lua
local dap = require('dap')

-- Add project-specific Python configuration
table.insert(dap.configurations.python, {
  type = 'python',
  request = 'launch',
  name = 'Launch with Django',
  program = '${workspaceFolder}/manage.py',
  args = {'runserver', '--noreload'},
  django = true,
})

-- Customize remote paths
vim.env.LOCAL_PROGRAM_PATH = vim.fn.getcwd() .. "/build/bin/myproject"
vim.env.REMOTE_GDBSERVER_PORT = "10001"
```

This file is automatically loaded by `python.lua` on VimEnter.

## Resources

- [nvim-dap Documentation](https://github.com/mfussenegger/nvim-dap)
- [DAP Protocol Specification](https://microsoft.github.io/debug-adapter-protocol/)
- [cpptools (Microsoft C++ Debug Adapter)](https://github.com/microsoft/vscode-cpptools)
- [GDB Remote Debugging](https://sourceware.org/gdb/onlinedocs/gdb/Remote-Debugging.html)
- [gdbserver Documentation](https://sourceware.org/gdb/onlinedocs/gdb/Server.html)

## Contributing

When modifying DAP configurations:

1. Test thoroughly with both local and remote debugging
2. Update this README with any new environment variables
3. Add inline comments for complex logic
4. Consider backward compatibility with existing workflows
