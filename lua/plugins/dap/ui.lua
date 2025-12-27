--[[
================================================================================
DAP UI (DEBUG INTERFACE)
================================================================================
Provides a comprehensive UI for nvim-dap debugging sessions.
Layout configuration:
  Right panel (40 cols):
    - Scopes (35%)
    - Locals (35%)
    - Watches (30%)
  Bottom panel (10 rows):
    - REPL (50%)
    - Console (20%)
    - Breakpoints (10%)
    - Stacks (20%)
Features:
  - Auto-open on debug session start
  - Auto-close on debug session end
  - Floating window support
Plugin: rcarriga/nvim-dap-ui
================================================================================
--]]

return {
  "rcarriga/nvim-dap-ui",
  lazy = false,
  dependencies = { "mfussenegger/nvim-dap" },
  opts = {
    layouts = {
      {
        elements = {
          { id = "scopes", size = 0.35 },
          { id = "locals", size = 0.35 },
          { id = "watches", size = 0.3 },
        },
        size = 40,
        position = "right",
      },
      {
        elements = {
          { id = "repl", size = 0.5 },
          { id = "console", size = 0.2 }, -- Agrega este elemento
          { id = "breakpoints", size = 0.1 },
          { id = "stacks", size = 0.2 },
        },
        size = 10,
        position = "bottom",
      },
    },
    floating = {
      max_height = nil,
      max_width = nil,
      border = "single",
    },
    windows = { indent = 1 },
  },
  config = function(_, opts)
    local dap = require("dap")
    local dapui = require("dapui")
    dapui.setup(opts)

    -- listeners para abrir/cerrar automáticamente
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.setup(opts)
      dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close()
      -- Cerrar también la ventana de logs remotos
      if _G.close_remote_output_window then
        _G.close_remote_output_window()
      end
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close()
      -- Cerrar también la ventana de logs remotos
      if _G.close_remote_output_window then
        _G.close_remote_output_window()
      end
    end

    -- Verificar que la configuración se aplica correctamente
    vim.notify("Configuración personalizada de dap-ui aplicada", vim.log.levels.INFO)
  end,
}
--
--    -- listener corregido: enviar logs a consola en lugar de repl
--    dap.listeners.after["event_output"]["dapui_gdb"] = function(_, body)
--      if body.category == "stderr" or body.category == "log" or body.category == "output" then
--        local console_buf = dapui.elements.console.buffer().stdout
--        if console_buf and vim.api.nvim_buf_is_valid(console_buf) then
--          local lines = vim.split(body.output or "", "\n")
--          local line_count = vim.api.nvim_buf_line_count(console_buf)
--          vim.api.nvim_buf_set_lines(console_buf, line_count, line_count, false, lines)
--          vim.api.nvim_win_set_cursor(0, { line_count + #lines, 0 })
--        end
--      end
--    end
--
--    -- atajo para alternar la interfaz
--    vim.keymap.set("n", "<leader>du", function()
--      dapui.toggle({})
--    end, { desc = "toggle dap ui" })
--
--    -- forzar que la consola use el tipo de buffer correcto
--    vim.api.nvim_create_autocmd("filetype", {
--      pattern = "dap-repl",
--      callback = function()
--        vim.schedule(function()
--          local buf = vim.api.nvim_get_current_buf()
--          vim.api.nvim_buf_set_option(buf, "filetype", "dapui_console")
--        end)
--      end,
--    })
--
--    -- configuración especial para la consola
--    vim.api.nvim_create_autocmd("bufwinenter", {
--      pattern = "dapui_console",
--      callback = function()
--        vim.wo.number = false
--        vim.wo.relativenumber = false
--        vim.wo.signcolumn = "no"
--      end,
--    })
--  end,
