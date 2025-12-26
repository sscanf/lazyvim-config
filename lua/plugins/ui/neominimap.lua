--[[
================================================================================
NEOMINIMAP - CODE MINIMAP
================================================================================
Provides a code minimap similar to VSCode/Sublime Text.
Features:
  - Traditional minimap showing code structure
  - Syntax-highlighted minimap
  - Auto-update on buffer changes
  - Customizable width and position
  - Git integration
  - LSP diagnostics markers
  - Search results highlighting
Keymaps:
  - <leader>nm: Toggle minimap
  - <leader>nmo: Open minimap
  - <leader>nmc: Close minimap
  - <leader>nmr: Refresh minimap
  - <leader>nmt: Toggle minimap focus
Plugin: Isrothy/neominimap.nvim
================================================================================
--]]

return {
  "Isrothy/neominimap.nvim",
  version = "v3.*.*",
  enabled = true,
  lazy = false, -- Load immediately to ensure minimap is available
  init = function()
    -- Configuration for neominimap v3
    -- Global options must be set before the plugin loads
    vim.g.neominimap = {
      auto_enable = true,

      -- Layout
      layout = "float", -- "float" or "split"
      split = "right",

      -- Appearance
      width = 20,
      height = 0.8,
      x = 1.0,
      y = 0.1,

      -- Window options
      border = "single",

      -- Filters
      buf_filter = function(bufnr)
        local buftype = vim.bo[bufnr].buftype
        local filetype = vim.bo[bufnr].filetype

        if buftype ~= "" and buftype ~= "acwrite" then
          return false
        end

        local excluded = {
          "help", "alpha", "dashboard", "neo-tree", "Trouble",
          "lazy", "mason", "notify", "toggleterm", "lazyterm"
        }

        for _, ft in ipairs(excluded) do
          if filetype == ft then
            return false
          end
        end

        return true
      end,

      -- Click behavior
      click = {
        enabled = true,
        auto_switch_focus = true,
      },

      -- Integrations
      diagnostic = {
        enabled = true,
        severity = vim.diagnostic.severity.WARN,
        mode = "icon",
        icon = {
          ERROR = "󰅚",
          WARN = "󰀪",
          INFO = "󰋽",
          HINT = "󰌶",
        },
      },

      git = {
        enabled = true,
        mode = "icon",
      },

      search = {
        enabled = true,
      },

      mark = {
        enabled = true,
        mode = "icon",
        show_builtins = false,
      },

      treesitter = {
        enabled = true,
      },

      fold = {
        enabled = true,
      },
    }
  end,
  config = function()
    -- Keymaps
    vim.keymap.set("n", "<leader>nm", "<cmd>Neominimap toggle<cr>", { desc = "Toggle minimap" })
    vim.keymap.set("n", "<leader>nmo", "<cmd>Neominimap on<cr>", { desc = "Open minimap" })
    vim.keymap.set("n", "<leader>nmc", "<cmd>Neominimap off<cr>", { desc = "Close minimap" })
    vim.keymap.set("n", "<leader>nmr", "<cmd>Neominimap refresh<cr>", { desc = "Refresh minimap" })
    vim.keymap.set("n", "<leader>nmt", "<cmd>Neominimap toggleFocus<cr>", { desc = "Toggle minimap focus" })

    vim.notify("Neominimap configurado correctamente", vim.log.levels.INFO)
  end,
}
