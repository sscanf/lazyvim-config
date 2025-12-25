# Neovim Plugins Organization

This directory contains custom plugin configurations organized by category for better maintainability.

## Directory Structure

```
plugins/
├── README.md              # This file
├── ai/                    # AI-assisted coding tools
│   └── copilot.lua       # GitHub Copilot integration
├── cpp/                   # C++ development tools
│   ├── cmake.lua         # CMake build system integration with deployment
│   └── cppassist.lua     # C++ code generation assistant
├── dap/                   # Debug Adapter Protocol configurations
│   ├── README.md         # Detailed DAP documentation and remote debugging guide
│   ├── init.lua          # Base DAP setup with breakpoint icons
│   ├── python.lua        # Python debugging with debugpy
│   ├── remote.lua        # Remote C++ debugging via SSH/gdbserver
│   ├── ui.lua            # DAP UI configuration (panels, layout)
│   └── logger.lua        # Debug log capture and viewing
├── dev-tools/            # Development utilities
│   ├── sessions.lua      # Auto-session management
│   └── toggleterm.lua    # Terminal integration
├── git/                   # Git integration tools
│   ├── fugitive.lua      # Git commands wrapper
│   └── gitsigns.lua      # Git status indicators and hunks
├── lsp/                   # Language Server Protocol configurations
│   └── ruff.lua          # Ruff Python linter/formatter config
└── ui/                    # UI enhancements
    └── icon-picker.lua   # Icon/emoji picker
```

## Category Descriptions

### 🤖 AI (`ai/`)
AI-powered coding assistance tools that help with code completion, generation, and suggestions.

- **copilot.lua**: GitHub Copilot integration for AI-powered code completion

### 🔧 C++ (`cpp/`)
Tools specifically for C++ development, including build systems and code generation.

- **cmake.lua**: CMake build system integration with parallel builds, deploy command, and auto-deployment before remote debugging
- **cppassist.lua**: C++ code generation (implement functions, switch header/source, out-of-class methods)

### 🐛 DAP (`dap/`)
Debug Adapter Protocol configurations for debugging various languages. See [dap/README.md](dap/README.md) for comprehensive remote debugging documentation.

- **init.lua**: Base DAP configuration with colored breakpoint icons
- **python.lua**: Python debugging with debugpy adapter, supports DEBUG_EXEC/DEBUG_ARGS environment variables
- **remote.lua**: Complex remote C++ debugging via SSH tunnel and gdbserver with file deployment
- **ui.lua**: DAP UI layout with scopes, watches, REPL, console, breakpoints, and stack panels
- **logger.lua**: Captures debug output to a dedicated buffer with `<leader>dl` (show) and `<leader>dh` (hide)

### 🛠️ Dev Tools (`dev-tools/`)
General development utilities that improve workflow and productivity.

- **sessions.lua**: Automatically save and restore project sessions (buffers, window layout, etc.)
- **toggleterm.lua**: Integrated terminal window within Neovim

### 🔀 Git (`git/`)
Git integration tools for version control operations and status visualization.

- **fugitive.lua**: Comprehensive Git command wrapper (`:Git`, `:Gdiff`, etc.)
- **gitsigns.lua**: Shows git status in sign column, current line blame, preview hunks with `<leader>gp`

### 📝 LSP (`lsp/`)
Language Server Protocol configurations for code intelligence features.

- **ruff.lua**: Configures Ruff Python linter/formatter with 120 character line length

### 🎨 UI (`ui/`)
Visual enhancements and UI improvements.

- **icon-picker.lua**: Visual picker for icons and emojis with `<C-i>` or `<leader>ip`

## How Plugin Loading Works

All plugins are automatically loaded by lazy.nvim through the import system configured in `lua/config/lazy.lua`:

```lua
{ import = "plugins.ai" },
{ import = "plugins.cpp" },
{ import = "plugins.dap" },
-- ... etc
```

When lazy.nvim imports a directory (e.g., `plugins.ai`), it:
1. Loads all `.lua` files in that directory
2. Each file should return a plugin specification table
3. Multiple files can configure the same plugin (specs are merged)

## Adding New Plugins

To add a new plugin:

1. **Choose the appropriate category** based on the plugin's primary function
2. **Create a new `.lua` file** in that category directory
3. **Return a plugin spec** following lazy.nvim format:

```lua
return {
  "author/plugin-name",
  dependencies = { "optional/dependencies" },
  config = function()
    -- Plugin configuration here
  end,
  keys = {
    { "<leader>xx", "<cmd>Command<cr>", desc = "Description" },
  },
}
```

4. **Test the plugin** by restarting Neovim or running `:Lazy reload`

### Creating a New Category

If your plugin doesn't fit existing categories:

1. Create a new directory: `mkdir lua/plugins/category-name`
2. Add the import to `lua/config/lazy.lua`:
   ```lua
   { import = "plugins.category-name" },
   ```
3. Add your plugin spec file(s) to the new directory
4. Update this README with the new category

## Plugin Spec Patterns

### Basic Plugin
```lua
return {
  "author/plugin",
  opts = {
    option1 = true,
  },
}
```

### Plugin with Configuration
```lua
return {
  "author/plugin",
  config = function()
    require("plugin").setup({
      option = "value",
    })
  end,
}
```

### Plugin with Keybindings
```lua
return {
  "author/plugin",
  keys = {
    { "<leader>x", "<cmd>Command<cr>", desc = "Description" },
  },
}
```

### Configuring Existing Plugin
```lua
return {
  "existing/plugin",  -- Already loaded by LazyVim
  opts = function(_, opts)
    opts.new_option = "value"
    return opts
  end,
}
```

## Troubleshooting

### Plugin Not Loading
1. Check `:Lazy` to see if the plugin appears in the list
2. Look for errors with `:checkhealth`
3. Ensure the file returns a valid plugin spec table
4. Verify the import path in `lua/config/lazy.lua`

### Conflicting Configurations
If multiple files configure the same plugin, lazy.nvim merges them. Later specs override earlier ones. Use `opts` functions for safe merging:

```lua
opts = function(_, opts)
  opts.new_field = "value"
  return opts
end
```

### Category Not Loading
- Ensure the category is imported in `lua/config/lazy.lua`
- Check that `.lua` files in the directory return valid plugin specs
- Restart Neovim or run `:Lazy reload`

## Additional Resources

- [lazy.nvim Documentation](https://github.com/folke/lazy.nvim)
- [LazyVim Documentation](https://www.lazyvim.org/)
- [DAP Remote Debugging Guide](dap/README.md)
