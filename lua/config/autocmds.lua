--[[
================================================================================
AUTOCOMMANDS CONFIGURATION
================================================================================
This file contains custom autocommands (autocmds) for Neovim.
Default LazyVim autocmds: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

Autocommands are automatic commands triggered by specific events.
Currently empty - add custom autocmds here as needed.
================================================================================
--]]

-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

-- Force DAP breakpoint signs to be red circles
vim.api.nvim_create_autocmd({ "VimEnter", "ColorScheme" }, {
  callback = function()
    vim.schedule(function()
      vim.api.nvim_set_hl(0, "DapBreakpointColor", { fg = "#e51400" })
      vim.fn.sign_define("DapBreakpoint", { text = "🔴", texthl = "DapBreakpointColor", numhl = "DapBreakpointColor" })
      vim.fn.sign_define(
        "DapBreakpointCondition",
        { text = "🔴", texthl = "DapBreakpointColor", numhl = "DapBreakpointColor" }
      )
      vim.fn.sign_define(
        "DapBreakpointRejected",
        { text = "🔴", texthl = "DapBreakpointColor", numhl = "DapBreakpointColor" }
      )
      vim.api.nvim_set_hl(0, "DapStoppedColor", { fg = "#98c379" })
      vim.fn.sign_define(
        "DapStopped",
        { text = "➜", texthl = "DapStoppedColor", linehl = "DapStoppedLine", numhl = "DapStoppedColor" }
      )
    end)
  end,
})
