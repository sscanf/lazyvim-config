--[[
================================================================================
DAP (DEBUG ADAPTER PROTOCOL) BASE CONFIGURATION
================================================================================
Base configuration for nvim-dap (Debug Adapter Protocol) debugging.
Features:
  - Breakpoint icons and highlighting
  - Foundation for language-specific debug adapters
  - Loads alongside other DAP modules (python.lua, remote.lua, ui.lua, logger.lua)
Plugin: mfussenegger/nvim-dap
================================================================================
--]]

return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },

  config = function()
    -- ===== ICONS =====
    vim.api.nvim_set_hl(0, "DapBreakpointColor", { fg = "#ff00ef" })
    vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpointColor", numhl = "DapBreakpointColor" })
    vim.fn.sign_define(
      "DapBreakpointCondition",
      { text = "●", texthl = "DapBreakpointColor", numhl = "DapBreakpointColor" }
    )
    vim.api.nvim_set_hl(0, "DapStoppedColor", { fg = "#98c379" })
    vim.fn.sign_define(
      "DapStopped",
      { text = "➜", texthl = "DapStoppedColor", linehl = "DapStoppedLine", numhl = "DapStoppedColor" }
    )
  end,
}
