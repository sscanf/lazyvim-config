return {
  "jay-babu/mason-nvim-dap.nvim",
  -- Opcional, pero buena práctica: asegúrate de que se cargue después de nvim-dap
  dependencies = { "mfussenegger/nvim-dap" },
  config = function()
    require("mason-nvim-dap").setup({
      ensure_installed = { "cpptools" },
      automatic_installation = true,
      handlers = {}
    })
  end,
}
