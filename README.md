# 💤 LazyVim Configuration

A comprehensive Neovim configuration based on [LazyVim](https://github.com/LazyVim/LazyVim) with specialized support for C/C++ development, remote debugging, and AI-assisted coding.

## 📋 Table of Contents

- [Features](#-features)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Project Structure](#-project-structure)
- [Plugins](#-plugins)
- [Remote Debugging](#-remote-debugging)
- [Key Mappings](#-key-mappings)
- [Configuration](#-configuration)

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

1. **Backup your existing Neovim configuration** (if any):

```bash
mv ~/.config/nvim ~/.config/nvim.backup
mv ~/.local/share/nvim ~/.local/share/nvim.backup
```

2. **Clone this configuration**:

```bash
git clone <your-repo-url> ~/.config/nvim
```

3. **Start Neovim**:

```bash
nvim
```

LazyVim will automatically install all plugins on first launch.

4. **Install LSP servers** (optional, most will auto-install):

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

This configuration includes advanced remote debugging capabilities for C/C++ development, perfect for embedded systems or remote servers.

### How It Works

1. **Build locally** with CMake
2. **Deploy automatically** to remote host via SSH/SCP
3. **Start gdbserver** on remote machine
4. **Connect GDB** from Neovim to remote gdbserver
5. **Monitor output** in real-time from remote stdout/stderr

### Prerequisites

```bash
# On local machine
sudo apt install sshpass gdb

# On remote machine (target)
sudo apt install gdbserver
```

### Environment Variables

Configure these in your CMakeCache.txt or environment:

```cmake
# In CMakeCache.txt or CMakeLists.txt
set(REMOTE_SSH_HOST "192.168.1.100")
set(REMOTE_SSH_PORT "22")
set(REMOTE_SSH_PASS "your_password")
set(REMOTE_GDBSERVER_PORT "10000")
set(DEPLOY_REMOTE_PATH "/tmp/debug/")
set(CMAKE_PROJECT_NAME "your_project_name")
```

Or export as environment variables:

```bash
export REMOTE_SSH_HOST="192.168.1.100"
export REMOTE_SSH_PORT="22"
export SSHPASS="your_password"
export LOCAL_PROGRAM_PATH="/path/to/local/executable"
export LOCAL_GDB_PATH="/path/to/cross-gdb"
export REMOTE_GDBSERVER_PORT="10000"
```

### Usage

1. **Build your project**:
   ```vim
   :CMakeBuild
   ```

2. **Deploy to remote** (optional, auto-deployed on debug):
   ```vim
   :CMakeDeploy
   ```

3. **Start remote debugging**:
   - Press `<leader>dR` (Remote Debug with Arguments)
   - Enter program arguments when prompted
   - The configuration will:
     - Upload executable to remote host
     - Start gdbserver on remote machine
     - Connect local GDB to remote gdbserver
     - Open DAP UI with console
     - Monitor remote stdout/stderr in real-time

### Features

- ✅ **Automatic deployment** via SCP
- ✅ **Remote output monitoring** - stdout/stderr shown in DAP console
- ✅ **GDB pretty printers** support
- ✅ **Breakpoints** work across network
- ✅ **Variable inspection** in DAP UI
- ✅ **Step debugging** (step in/out/over)
- ✅ **Watch expressions**
- ✅ **CMake integration** - reads paths from CMakeCache.txt

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
| `:CMakeDeploy` | Deploy to remote (custom command) |
| `:CMakeClean` | Clean build |
| `:CMakeSelectBuildType` | Select build type |

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

Feel free to open issues or submit pull requests for improvements!

## 📝 License

This configuration is provided as-is. Individual plugins have their own licenses.

---

**Enjoy coding with LazyVim! 🚀**
