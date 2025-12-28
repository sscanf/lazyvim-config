# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a comprehensive Neovim configuration based on LazyVim with specialized support for C/C++ remote debugging, particularly for embedded systems development. The configuration is located at `~/.config/nvim/`.

## Core Architecture

### Plugin System
- Uses **lazy.nvim** for plugin management
- Plugin configurations are self-contained in `lua/plugins/` organized by category:
  - `dap/` - Debug Adapter Protocol (remote debugging system)
  - `cpp/` - C/C++ development tools
  - `ai/` - AI assistants (Copilot)
  - `git/` - Git integration
  - `ui/` - UI enhancements

### Remote Debugging System (`lua/plugins/dap/remote.lua`)

This is the most complex component. Key architectural decisions:

**Asynchronous Operations:**
- All network operations (SSH, SCP, rsync) use `vim.fn.jobstart()` for non-blocking execution
- Callback-based flow: `run_remote_async()`, `scp_upload_async()`, `rsync_async()`
- Deployment chain: create remote dirs → upload executable → upload plugins → sync config directories
- Neovim remains responsive during all operations

**Console Logging:**
- Unified logging system via `log_to_console()` and `open_deploy_console()`
- Single deploy console window (idempotent - reuses existing window)
- All operations (deploy, diagnostic, debug startup) write to this console
- Close with `<leader>dL` or `:DapCloseDeployConsole`

**CMake Integration:**
- Automatically parses `CMakeCache.txt` to read configuration variables
- Detects installation paths from `install(TARGETS ...)` and `install(DIRECTORY ...)` directives in CMakeLists.txt
- No hardcoded paths - everything derived from CMake files
- Function: `get_executable_install_path()`, `get_plugin_install_path()`, `get_additional_install_dirs()`

**Remote Deployment Flow:**
1. `ensure_remote_program_async()` orchestrates the entire deployment
2. Uploads executable to path detected from `install(TARGETS ...)`
3. Uploads all `.so` plugins from `build_dir/plugins/**/*.so`
4. Syncs config directories using rsync (parsed from `install(DIRECTORY ...)`)
5. Safety validation blocks deployment to critical system directories (`/usr/bin`, `/lib`, etc.)

**GDB Setup:**
- Critical commands for `.so` debugging:
  - `set sysroot remote:/` - Load libraries from remote system
  - `set breakpoint pending on` - Allow breakpoints in unloaded libraries
  - `set auto-solib-add on` - Auto-load shared library symbols
- Function: `get_gdb_setup_commands()`

**Output Monitoring:**
- Uses `tail -f` over SSH for zero-latency output streaming
- `OutputMonitor` module manages persistent SSH connection
- Streams to both DAP console and separate output buffer
- Cleanup on debug session end

## Key Commands

### Remote Debugging Workflow
```vim
:CMakeBuild                 " Build project with debug symbols
:CMakeDeploy                " Deploy executable + plugins + configs to remote (async)
:DapRemoteDiagnostic        " Verify SSH, paths, gdbserver availability
<leader>dR                  " Start remote debug session (deploys if needed)
:DapShowGdbCommands         " Show GDB commands that will be executed
:DapCloseDeployConsole      " Close deploy log window
```

### Configuration Requirements
Variables read from `CMakePresets.json` or environment:
- `REMOTE_SSH_HOST` - Target machine IP/hostname
- `REMOTE_SSH_PORT` - SSH port (default: 2222)
- `REMOTE_SSH_PASS` - SSH password (via SSHPASS env var)
- `REMOTE_GDBSERVER_PORT` - Port for gdbserver (default: 10000)
- `LOCAL_GDB_PATH` - Path to GDB executable

## Critical Implementation Details

### BusyBox Compatibility
- Remote system may use BusyBox with limited commands
- `ps` used without options (BusyBox doesn't support `ps aux`)
- PID extracted from column 1, not column 2

### Safety Features
- rsync operations **never** use `--delete` flag (prevents system file deletion)
- Dangerous directory validation before any rsync
- Blocked destinations: `/usr/bin`, `/bin`, `/sbin`, `/lib`, etc.

### CMakeLists.txt Parsing
- Uses Lua pattern matching to extract `install()` directives
- Pattern for directories: `install%s*%(%s*DIRECTORY%s+[^%)]+%)`
- Must distinguish `install(DIRECTORY ...)` from `install(TARGETS ...)`
- Expands `${CMAKE_CURRENT_SOURCE_DIR}` during parsing

### Function Order Dependencies
- `upload_config_directories()` must be defined **before** `ensure_remote_program_async()` (Lua requires forward declarations)
- Console functions (`open_deploy_console`, `log_to_console`) used throughout

## Debugging Issues

Common problems and solutions:

**Breakpoints not working in `.so` files:**
- Verify GDB commands include `set sysroot remote:/` and `set breakpoint pending on`
- Check `LD_LIBRARY_PATH` set correctly in gdbserver startup script
- Ensure plugins deployed to remote system

**Multiple console windows opening:**
- `open_deploy_console()` checks if `deploy_log_window` is valid before creating new window
- Must be idempotent

**Async operations not working:**
- All callbacks must be properly chained
- Error: "attempt to call global 'X' (a nil value)" → function definition order issue

## Plugin Configuration Pattern

Each plugin file in `lua/plugins/` follows this structure:
```lua
return {
  "author/plugin-name",
  event = "VeryLazy",  -- or other lazy-loading trigger
  opts = {
    -- configuration options
  },
  config = function(_, opts)
    -- setup logic
  end,
}
```

## Testing Changes

After modifying `lua/plugins/dap/remote.lua`:
```bash
# Check for Lua syntax errors
nvim --headless -c "luafile /home/vboxuser/.config/nvim/lua/plugins/dap/remote.lua" -c "qa"

# Reload Neovim or restart
```

## Commit Message Format

Use conventional commits with detailed bodies:
```
feat(dap): description of feature

Detailed explanation of changes:
- Bullet point 1
- Bullet point 2

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```
