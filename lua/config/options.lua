--[[
================================================================================
NEOVIM OPTIONS CONFIGURATION
================================================================================
This file contains custom Neovim options and settings.
Default LazyVim options: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

Current customizations:
  - Python textwidth set to 120 characters
================================================================================
--]]

-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.opt_local.textwidth = 120
  end,
})

