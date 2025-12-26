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

-- Sobrescribir completamente la configuración DAP de LazyVim
return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },

  -- Deshabilitar la configuración de iconos de LazyVim
  opts = function()
    -- Esto previene que LazyVim sobrescriba nuestros signos
    return {}
  end,

  keys = {
    { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input('Breakpoint condition: ')) end, desc = "Breakpoint Condition" },
    { "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
    { "<leader>dc", function() require("dap").continue() end, desc = "Continue" },
    { "<leader>di", function() require("dap").step_into() end, desc = "Step Into" },
    { "<leader>do", function() require("dap").step_over() end, desc = "Step Over" },
    { "<leader>dO", function() require("dap").step_out() end, desc = "Step Out" },
    { "<leader>dt", function() require("dap").terminate() end, desc = "Terminate" },
  },

  config = function()
    -- Definir signos inmediatamente
    local signs = {
      DapBreakpoint = { text = "●", texthl = "DapBreakpoint" },
      DapBreakpointCondition = { text = "●", texthl = "DapBreakpoint" },
      DapBreakpointRejected = { text = "●", texthl = "DapBreakpoint" },
      DapLogPoint = { text = "◆", texthl = "DapLogPoint" },
      DapStopped = { text = "➜", texthl = "DapStopped" },
    }

    for name, sign in pairs(signs) do
      vim.fn.sign_define(name, sign)
    end

    -- Colores para los signos
    vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = "#e51400" })
    vim.api.nvim_set_hl(0, "DapLogPoint", { fg = "#61afef" })
    vim.api.nvim_set_hl(0, "DapStopped", { fg = "#98c379" })

    -- Redefinir signos después de que LazyVim cargue (usar defer para ejecutar después)
    vim.defer_fn(function()
      for name, sign in pairs(signs) do
        vim.fn.sign_define(name, sign)
      end
    end, 100)

    -- Comando para redefinir signos manualmente si es necesario
    vim.api.nvim_create_user_command("DapResetSigns", function()
      for name, sign in pairs(signs) do
        vim.fn.sign_define(name, sign)
      end
      vim.notify("✅ Signos DAP redefinidos", vim.log.levels.INFO)
    end, { desc = "Redefinir signos de breakpoints DAP" })

    -- Autocomando para redefinir signos al cargar buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*",
      once = true,
      callback = function()
        vim.defer_fn(function()
          for name, sign in pairs(signs) do
            vim.fn.sign_define(name, sign)
          end
        end, 200)
      end,
    })
  end,
}
