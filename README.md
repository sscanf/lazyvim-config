# 💤 LazyVim Configuration

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9+-green.svg)](https://neovim.io)
[![LazyVim](https://img.shields.io/badge/LazyVim-powered-blueviolet.svg)](https://github.com/LazyVim/LazyVim)
[![GitHub stars](https://img.shields.io/github/stars/sscanf/lazyvim-config?style=social)](https://github.com/sscanf/lazyvim-config/stargazers)

A comprehensive Neovim configuration based on [LazyVim](https://github.com/LazyVim/LazyVim) with specialized support for C/C++ development, remote debugging, and AI-assisted coding.

## ⚡ Quick Start

```bash
# Install everything automatically
curl -fsSL https://raw.githubusercontent.com/sscanf/lazyvim-config/main/install.sh | bash

# Start Neovim and let plugins install
nvim
```

For **remote C/C++ debugging**, add to your project's `CMakePresets.json`:

```json
{
  "configurePresets": [{
    "cacheVariables": {
      "REMOTE_SSH_HOST": "192.168.1.100",
      "REMOTE_SSH_PASS": "password"
    }
  }]
}
```

Then:
```vim
:CMakeBuild          " Build project
:CMakeDeploy         " Deploy to remote
<leader>dR           " Start debugging
```

## 📋 Table of Contents

- [Quick Start](#-quick-start)
- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Project Structure](#-project-structure)
- [Plugins](#-plugins)
- [Remote Debugging](#-remote-debugging)
- [Key Mappings](#-key-mappings)
- [Configuration](#-configuration)
- [Contributing](#-contributing)

## ✨ Features

- **Modern C/C++ Development**: Full LSP support with clangd, CMake integration, and debugging capabilities
- **Remote Debugging**: Advanced SSH-based remote debugging with gdbserver for embedded/remote development
- **AI Integration**: GitHub Copilot for intelligent code completion
- **Enhanced UI**: Minimap, icon picker, custom status line, and beautiful syntax highlighting
- **Git Integration**: GitSigns for inline git blame and diff, Fugitive for advanced git operations
- **Session Management**: Auto-save and restore sessions with telescope integration
- **Python Development**: Debugpy integration for Python debugging
- **Terminal Integration**: ToggleTerm for persistent terminals

## 📦 Requirements

### System Dependencies

```bash
# Core dependencies
fd                    # Fast file finder
ripgrep              # Fast text search
git                  # Version control

# For remote debugging
sshpass              # SSH password authentication
gdbserver            # Remote debugging server (on target machine)
gdb                  # GNU Debugger

# For C/C++ development
cmake                # Build system
clang                # C/C++ compiler (for clangd)
```

### Neovim

- Neovim >= 0.9.0
- Node.js (for Copilot and some LSP servers)

## 🚀 Installation

### ⚡ Automatic Installation (Recommended)

Run the automated installer that handles everything for you:

```bash
curl -fsSL https://raw.githubusercontent.com/sscanf/lazyvim-config/main/install.sh | bash
```

Or download and run manually:

```bash
git clone https://github.com/sscanf/lazyvim-config.git /tmp/lazyvim-config
cd /tmp/lazyvim-config
./install.sh
```

The installer will:
- ✅ Backup existing configuration automatically
- ✅ Install system dependencies (neovim, git, fd, ripgrep, nodejs, etc.)
- ✅ Clone the configuration
- ✅ Verify Neovim version compatibility
- ✅ Show you next steps

### 📋 Manual Installation

If you prefer manual installation:

1. **Backup your existing Neovim configuration** (if any):

```bash
mv ~/.config/nvim ~/.config/nvim.backup.$(date +%Y%m%d)
mv ~/.local/share/nvim ~/.local/share/nvim.backup.$(date +%Y%m%d)
```

2. **Clone this configuration**:

```bash
git clone https://github.com/sscanf/lazyvim-config.git ~/.config/nvim
```

3. **Install system dependencies**:

```bash
# Ubuntu/Debian
sudo apt install neovim git fd-find ripgrep nodejs npm sshpass gdb rsync cmake clang

# Arch Linux
sudo pacman -S neovim git fd ripgrep nodejs npm sshpass gdb rsync cmake clang

# macOS
brew install neovim git fd ripgrep node sshpass gdb rsync cmake llvm
```

4. **Start Neovim**:

```bash
nvim
```

LazyVim will automatically install all plugins on first launch.

5. **Install LSP servers** (optional, most will auto-install):

```vim
:Mason
```

## 📁 Project Structure

```
~/.config/nvim/
├── lua/
│   ├── config/
│   │   ├── autocmds.lua      # Automatic commands
│   │   ├── keymaps.lua       # Global key mappings
│   │   ├── lazy.lua          # Lazy.nvim plugin manager setup
│   │   └── options.lua       # Neovim options
│   └── plugins/
│       ├── ai/
│       │   └── copilot.lua   # GitHub Copilot integration
│       ├── cpp/
│       │   ├── cmake.lua     # CMake Tools integration
│       │   └── cppassist.lua # C/C++ helper utilities
│       ├── dap/
│       │   ├── init.lua      # Base DAP configuration
│       │   ├── logger.lua    # Debug logging utilities
│       │   ├── python.lua    # Python debugging setup
│       │   ├── remote.lua    # Remote C/C++ debugging
│       │   └── ui.lua        # DAP UI configuration
│       ├── dev-tools/
│       │   ├── sessions.lua  # Session management
│       │   └── toggleterm.lua # Terminal integration
│       ├── git/
│       │   ├── fugitive.lua  # Advanced git commands
│       │   └── gitsigns.lua  # Git decorations
│       ├── lsp/
│       │   └── ruff.lua      # Python linter/formatter
│       └── ui/
│           ├── icon-picker.lua # Nerd Font icon selector
│           └── neominimap.lua  # Code minimap
└── README.md
```

## 🔌 Plugins

### AI & Code Completion

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **copilot.lua** | GitHub Copilot AI assistant | Auto-suggestions, Shift+Tab to accept |

### C/C++ Development

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **cmake-tools.nvim** | CMake integration | Parallel builds, deployment, `:CMakeBuild`, `:CMakeDeploy` |
| **cppassist** | C/C++ utilities | Helper functions for C++ development |
| **clangd** (LSP) | C/C++ language server | Auto-completion, go-to-definition, diagnostics |

### Debugging (DAP)

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **nvim-dap** | Debug Adapter Protocol | Universal debugging interface |
| **nvim-dap-ui** | DAP UI | Visual debugging interface with console, variables, watches |
| **nvim-dap-python** | Python debugging | Debugpy integration for Python |
| **remote.lua** | Remote debugging | SSH + gdbserver for remote C/C++ debugging |

### Development Tools

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **auto-session** | Session management | Auto-save/restore sessions, `:SessionSearch` |
| **toggleterm.nvim** | Terminal integration | Persistent terminals, `<C-\>` to toggle |

### Git Integration

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **gitsigns.nvim** | Git decorations | Inline blame, diff hunks, stage/unstage |
| **vim-fugitive** | Git commands | `:Git`, `:Gwrite`, `:Gread`, `:Gdiffsplit` |

### UI & Visual

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **neominimap.nvim** | Code minimap | Syntax-highlighted minimap, git/LSP integration |
| **icon-picker.nvim** | Icon selector | Browse/insert Nerd Font icons, `<leader>ip` |

### LSP & Formatting

| Plugin | Description | Key Features |
|--------|-------------|--------------|
| **ruff-lsp** | Python linter/formatter | Fast Python linting and formatting |
| **mason.nvim** | LSP installer | Easy installation of LSP servers, DAP adapters |

## 🐛 Remote Debugging

This configuration includes advanced remote debugging capabilities for C/C++ development, perfect for embedded systems or remote servers. All deployment paths are **automatically extracted from CMakeLists.txt** - no manual configuration needed!

### How It Works

1. **Build locally** with CMake (`-g` flag for debug symbols)
2. **Deploy automatically** to remote host:
   - Executable → `/usr/bin` (from `manager/CMakeLists.txt`)
   - Plugins (.so) → `/usr/lib/zone/zovideo/` (from `plugins/CMakeLists.txt`)
   - Config directories → `/etc/zone`, `/etc/dbus-1/system.d`, etc.
3. **Start gdbserver** on remote machine with correct `LD_LIBRARY_PATH`
4. **Connect GDB** from Neovim to remote gdbserver
5. **Monitor output** in real-time from remote stdout/stderr

### Prerequisites

```bash
# On local machine
sudo apt install sshpass gdb rsync

# On remote machine (target)
sudo apt install gdbserver

# For BusyBox systems (embedded)
# gdbserver is usually pre-installed
```

### Configuration

#### Option 1: CMakePresets.json (Recommended)

Create or edit `CMakePresets.json` in your project root:

```json
{
  "version": 3,
  "configurePresets": [
    {
      "name": "x86_64",
      "generator": "Unix Makefiles",
      "binaryDir": "${sourceDir}/out/Debug",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "REMOTE_SSH_HOST": "192.168.1.155",
        "REMOTE_SSH_PORT": "22",
        "REMOTE_SSH_PASS": "root",
        "REMOTE_GDBSERVER_PORT": "10000",
        "LOCAL_GDB_PATH": "/path/to/gdb"
      }
    }
  ]
}
```

#### Option 2: Environment Variables

```bash
export REMOTE_SSH_HOST="192.168.1.155"
export REMOTE_SSH_PORT="22"
export SSHPASS="your_password"
export REMOTE_GDBSERVER_PORT="10000"
export LOCAL_GDB_PATH="/usr/bin/gdb"
```

#### Install Paths (Automatic from cmake_install.cmake)

The configuration automatically detects installation paths from **CMake-generated files**:

- Reads `cmake_install.cmake` files in your build directory (`binaryDir`)
- Parses `file(INSTALL ...)` directives with all variables already expanded by CMake
- Automatically discovers all subprojects and their install targets
- Supports complex multi-project structures

Example CMake install directives:
```cmake
# Main project
install(TARGETS ${PROJECT_NAME} DESTINATION /usr/bin)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/zone/ DESTINATION /etc/zone)

# Subprojects (automatically detected)
install(TARGETS zocore LIBRARY DESTINATION /usr/lib)
install(DIRECTORY headers/ DESTINATION /usr/include/zone-core)
```

**No manual configuration needed!** All paths and files are extracted from CMake's processed output.

### Deploy Performance

The deployment system is optimized for speed using multiple techniques:

1. **SSH ControlMaster**: Reuses a single SSH connection for all transfers
   - First connection: normal handshake + authentication (~200ms)
   - Subsequent transfers: reuse existing socket (~30-40ms overhead)
   - Connection persists for 10 minutes after last use

2. **Batch Transfer with tar+ssh**: Groups files by destination directory
   - Instead of 28 individual scp transfers → 3-5 tar+ssh transfers
   - Compresses data on-the-fly with gzip
   - Example: 15 library files sent in one tar instead of 15 scp calls

3. **Intelligent Grouping**: Files destined for the same directory are bundled
   - `/usr/lib/*.so*` → 1 tar transfer (15 files)
   - `/usr/include/zone-core/*` → 1 rsync per subproject
   - `/usr/lib/cmake/*` → 1 rsync (tools directory)

**Result**: Deploy time reduced from ~3-5 seconds to **~0.5-1 second** for typical projects.

### Usage

#### Quick Start

```vim
" 1. Build your project
:CMakeBuild

" 2. Deploy to remote
:CMakeDeploy

" 3. Start debugging
<leader>dR
```

#### Detailed Workflow

1. **Verify Configuration**:
   ```vim
   :DapRemoteDiagnostic
   ```
   Shows:
   - SSH connectivity
   - Detected installation paths
   - gdbserver availability
   - Configuration directories found

2. **Deploy** (uploads everything):
   ```vim
   :CMakeDeploy
   ```
   Or press `<Alt-D>`

   This uploads:
   - ✅ Executable to `/usr/bin/zovideo`
   - ✅ All `.so` plugins to `/usr/lib/zone/zovideo/`
   - ✅ Config directories:
     - `zone/` → `/etc/zone/`
     - `system.d/` → `/etc/dbus-1/system.d/`
     - `system-services/` → `/usr/share/dbus-1/system-services/`

3. **Start Remote Debug**:
   - Press `<leader>dR`
   - Enter program arguments
   - The system will:
     - Upload files if not already done
     - Start gdbserver on remote
     - Connect local GDB
     - Open DAP UI with console
     - Stream stdout/stderr in real-time

### Features

- ✅ **CMake-based deployment** - reads from `cmake_install.cmake` (CMake's processed output)
- ✅ **Multi-project support** - automatically detects and deploys all subprojects
- ✅ **Optimized transfers** - uses tar+ssh for batch file transfers (10x faster)
- ✅ **SSH ControlMaster** - reuses SSH connections for minimal overhead
- ✅ **Intelligent grouping** - groups files by destination for efficient transfer
- ✅ **Safe rsync operations** - blocks copying to critical system directories
- ✅ **Remote output monitoring** - real-time stdout/stderr in DAP console
- ✅ **GDB pretty printers** support for custom types
- ✅ **Shared library debugging** - breakpoints in `.so` files work correctly
- ✅ **BusyBox compatible** - works with embedded Linux systems
- ✅ **Diagnostic tools** - verify configuration before debugging

### Troubleshooting

#### Check Configuration

```vim
:DapRemoteDiagnostic
```

Shows complete diagnostic info:
- ✅ Environment variables status
- ✅ SSH connectivity test
- ✅ Installation paths detected
- ✅ gdbserver availability
- ✅ Active gdbserver processes

#### View GDB Commands

```vim
:DapShowGdbCommands
```

Shows all GDB setup commands including:
- `set sysroot remote:/` (load remote libraries)
- `set breakpoint pending on` (allow breakpoints in unloaded .so)
- `set auto-solib-add on` (auto-load shared library symbols)
- Pretty printer setup

#### Common Issues

**Breakpoints in `.so` not working?**
- Ensure plugins are deployed: `:CMakeDeploy`
- Check `LD_LIBRARY_PATH` includes plugin directory
- Verify `.so` files compiled with `-g` flag

**"Connection timed out" error?**
- Check SSH connectivity: `ssh root@<host>`
- Verify gdbserver port not blocked by firewall
- Confirm gdbserver installed on remote: `which gdbserver`

**Source files show as empty?**
- Ensure local source matches remote binary
- Check compilation was done with debug symbols (`-g`)
- Use `:DapRemoteDiagnostic` to verify paths

### Keymaps for Debugging

| Key | Action |
|-----|--------|
| `<leader>dR` | Start remote debug (with arguments) |
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>dc` | Continue execution |
| `<leader>di` | Step into |
| `<leader>do` | Step over |
| `<leader>dO` | Step out |
| `<leader>dt` | Terminate debugging |
| `<leader>du` | Toggle DAP UI |

## ⌨️ Key Mappings

### General

| Key | Mode | Action |
|-----|------|--------|
| `<leader>` | - | Space (leader key) |
| `<C-\>` | n/t | Toggle terminal |
| `<leader>ss` | n | Search sessions |
| `<leader>ip` | n | Pick icon |
| `<C-i>` | i/n | Insert icon |

### Minimap

| Key | Mode | Action |
|-----|------|--------|
| `<leader>nm` | n | Toggle minimap |
| `<leader>nmo` | n | Open minimap |
| `<leader>nmc` | n | Close minimap |
| `<leader>nmr` | n | Refresh minimap |
| `<leader>nmt` | n | Toggle minimap focus |

### Git (Fugitive)

| Command | Action |
|---------|--------|
| `:Git` | Open git status |
| `:Git blame` | Show git blame |
| `:Gwrite` | Stage current file |
| `:Gread` | Checkout current file |
| `:Gdiffsplit` | Open diff view |
| `:Git push` | Push changes |

### CMake

| Command | Action |
|---------|--------|
| `:CMakeBuild` | Build project |
| `:CMakeDebug` | Build in debug mode |
| `:CMakeDeploy` | Deploy executable, plugins, and config files to remote system |
| `:CMakeDeploy build` | Build first, then prompt to deploy manually |
| `:CMakeClean` | Clean build |
| `:CMakeSelectBuildType` | Select build type |
| `<Alt-D>` | Quick deploy to remote (keymap) |

### Remote Debugging Diagnostics

| Command | Action |
|---------|--------|
| `:DapRemoteDiagnostic` | Verify remote debugging configuration and connectivity |
| `:DapShowGdbCommands` | Show GDB setup commands that will be executed |
| `:DapCleanupMonitor` | Stop and cleanup remote output monitoring |
| `:DapMonitorStatus` | Check status of remote output monitor |
| `<leader>dC` | Cleanup debug monitor (keymap) |
| `<leader>dM` | Monitor status (keymap) |

### Copilot

| Key | Mode | Action |
|-----|------|--------|
| `<S-Tab>` | i | Accept Copilot suggestion |

## ⚙️ Configuration

### Options (lua/config/options.lua)

Key Neovim options are configured for optimal development experience:

- **Line numbers**: Relative numbers enabled
- **Indentation**: 2 spaces, smart indent
- **Search**: Smart case-sensitive search
- **Clipboard**: System clipboard integration
- **Undo**: Persistent undo history

### Auto Commands (lua/config/autocmds.lua)

Automatic behaviors on file events:

- Auto-format on save (configurable per language)
- Restore cursor position on file open
- Highlight yanked text briefly

### LSP Configuration

LSP servers are managed by **Mason** and configured through LazyVim extras:

- **clangd**: C/C++ (auto-installed)
- **ruff**: Python linting/formatting
- **lua_ls**: Lua (Neovim config development)
- **bashls**: Bash scripting
- **jsonls**: JSON files

To install additional LSP servers:

```vim
:Mason
```

### Customizing Plugins

Each plugin configuration file is self-contained and well-documented. To customize:

1. Navigate to `lua/plugins/<category>/<plugin>.lua`
2. Modify the configuration in the `config` function
3. Restart Neovim or run `:Lazy reload <plugin-name>`

## 🎯 Tips & Tricks

### CMake Workflow

```vim
" Configure build
:CMakeSelectBuildType

" Build
:CMakeBuild

" Deploy (for remote debugging)
:CMakeDeploy

" Debug remotely
<leader>dR
```

### Session Management

```vim
" Sessions auto-save on exit
" Restore with:
:SessionSearch

" Or just reopen Neovim in the same directory
```

### Git Workflow

```vim
" Stage hunks with gitsigns
<leader>hs  " Stage hunk
<leader>hu  " Undo stage hunk
<leader>hp  " Preview hunk

" Or use fugitive for full git operations
:Git
```

### Minimap Usage

The minimap automatically shows:
- **Git changes** (green/yellow/red bars)
- **LSP diagnostics** (error/warning indicators)
- **Search results** (highlighted regions)
- **Current cursor position**

Click on the minimap to jump to that location!

## 📚 Additional Resources

- [LazyVim Documentation](https://lazyvim.github.io/)
- [Neovim Documentation](https://neovim.io/doc/)
- [DAP Protocol](https://microsoft.github.io/debug-adapter-protocol/)
- [CMake Tools](https://github.com/Civitasv/cmake-tools.nvim)

## 🤝 Contributing

Contributions are welcome! Whether you're fixing bugs, adding features, or improving documentation, your help is appreciated.

### Quick Contribution Guide

1. **Report bugs**: Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md)
2. **Suggest features**: Use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md)
3. **Submit PRs**: Follow the [pull request template](.github/PULL_REQUEST_TEMPLATE.md)

### Development Setup

```bash
# Fork and clone your fork
git clone https://github.com/YOUR_USERNAME/lazyvim-config.git ~/.config/nvim
cd ~/.config/nvim

# Create a feature branch
git checkout -b feature/my-awesome-feature

# Make changes, test thoroughly
nvim

# Commit with conventional commits format
git commit -m "feat(dap): add support for new architecture"

# Push and create PR
git push origin feature/my-awesome-feature
```

For detailed guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).

### Areas We Need Help With

- 🧪 Testing on different platforms (macOS, Windows WSL)
- 📸 Screenshots and video demos
- 📚 Documentation improvements
- 🐛 Bug fixes and performance improvements
- ✨ New features for remote debugging

## 📝 License

This configuration is provided as-is. Individual plugins have their own licenses.

---

**Enjoy coding with LazyVim! 🚀**
