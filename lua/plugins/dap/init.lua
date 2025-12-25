-- Base DAP configuration with breakpoint icons
-- Other DAP configs (python.lua, remote.lua, ui.lua, logger.lua) are loaded automatically by lazy.nvim
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
