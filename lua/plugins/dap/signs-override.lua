--[[
================================================================================
DAP SIGNS OVERRIDE - FORCE RED CIRCLE BREAKPOINTS
================================================================================
This plugin forcefully overrides LazyVim's DAP sign configuration.
It loads with very low priority to ensure it runs AFTER LazyVim.
================================================================================
--]]

return {
  "mfussenegger/nvim-dap",
  event = "VeryLazy",
  priority = 1, -- Muy baja prioridad = carga al final

  config = function()
    -- Esperar a que todo esté cargado
    vim.schedule(function()
      -- Definir los signos con círculo rojo
      local signs = {
        DapBreakpoint = { text = "●", texthl = "DapBreakpoint" },
        DapBreakpointCondition = { text = "●", texthl = "DapBreakpoint" },
        DapBreakpointRejected = { text = "●", texthl = "DapBreakpoint" },
        DapLogPoint = { text = "●", texthl = "DapLogPoint" },
        DapStopped = { text = "➜", texthl = "DapStopped" },
      }

      -- Aplicar los signos
      for name, sign in pairs(signs) do
        vim.fn.sign_define(name, sign)
      end

      -- Colores
      vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff0000", bold = true })
      vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef" })
      vim.api.nvim_set_hl(0, "DapStopped", { fg = "#98c379" })

      -- Volver a aplicar después de un delay
      vim.defer_fn(function()
        for name, sign in pairs(signs) do
          vim.fn.sign_define(name, sign)
        end
      end, 500)

      -- Autocomando al cambiar colorscheme
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#ff0000", bold = true })
          vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef" })
          vim.api.nvim_set_hl(0, "DapStopped", { fg = "#98c379" })
          for name, sign in pairs(signs) do
            vim.fn.sign_define(name, sign)
          end
        end,
      })
    end)
  end,
}
