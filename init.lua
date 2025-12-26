--[[
================================================================================
NEOVIM MAIN CONFIGURATION FILE
================================================================================
This is the main entry point for Neovim configuration.
Responsibilities:
  - Initialize lazy.nvim (plugin manager)
  - Load LazyVim base configuration
  - Configure Tab key behavior in insert mode

This file loads the config.lazy module which in turn loads all plugins
organized by categories (ai, cpp, dap, dev-tools, git, lsp, ui).
================================================================================
--]]

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Bloquea la apertura automática con Tab
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    vim.keymap.set("i", "<Tab>", "<Tab>", {
      buffer = true,
      silent = true,
      noremap = true,
      expr = false,
      desc = "Tab normal en modo inserción",
    })
  end,
})
