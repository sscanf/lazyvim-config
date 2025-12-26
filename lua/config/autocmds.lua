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
vim.api.nvim_create_autocmd({ "VimEnter", "ColorScheme", "BufEnter" }, {
  callback = function()
    vim.schedule(function()
      -- Definir highlight groups
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff0000", bold = true })
      vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef" })
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#98c379" })

      -- Definir signos con círculo rojo
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint", numhl = "DapBreakpoint" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "●", texthl = "DapBreakpoint", numhl = "DapBreakpoint" })
      vim.fn.sign_define("DapBreakpointRejected", { text = "●", texthl = "DapBreakpoint", numhl = "DapBreakpoint" })
      vim.fn.sign_define("DapLogPoint", { text = "●", texthl = "DapLogPoint", numhl = "DapLogPoint" })
      vim.fn.sign_define("DapStopped", { text = "➜", texthl = "DapStopped", linehl = "DapStoppedLine", numhl = "DapStopped" })
    end)
  end,
})
