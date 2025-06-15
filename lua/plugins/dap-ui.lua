return {
  "rcarriga/nvim-dap-ui",
  lazy = false,
  dependencies = { "nvim-neotest/nvim-nio" },
  opts = {
    auto_open = true,
    icons = { expanded = "▾", collapsed = "▸" },
    mappings = {
      expand = { "<CR>", "<2-LeftMouse>" },
      open = "o",
      remove = "d",
      edit = "e",
      repl = "r",
    },
    layouts = {
      -- Panel derecho (variables, watches, stack)
      {
        position = "right",
        size = 40,
        elements = {
          { id = "scopes", size = 0.35 }, -- Variables locales (35% del espacio)
          { id = "watches", size = 0.35 }, -- Expresiones vigiladas (35%)
          { id = "stacks", size = 0.30 }, -- Pila de llamadas (30%)
        },
      },
      -- Panel inferior (consola y REPL)
      {
        position = "bottom",
        size = 30,
        elements = {
          "console", -- Salida del programa
          "repl", -- Consola interactiva
          "breakpoints", -- Puntos de interrupción
        },
      },
    },
    floating = {
      max_height = nil,
      max_width = nil,
      border = "single",
      mappings = {
        close = { "q", "<Esc>" },
      },
    },
    windows = { indent = 1 },
    render = {
      max_type_length = nil,
      max_value_lines = 100, -- ¡Importante para mostrar logs largos!
    },
  },

  config = function(_, opts)
    print("--- [DEBUG] CONFIGURACIÓN DE DAP-UI SE ESTÁ EJECUTANDO ---")
    local dap = require("dap")
    local dapui = require("dapui")
    dapui.setup(opts)

    -- Listeners para abrir/cerrar automáticamente
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close({})
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close({})
    end

    -- ===================================================================
    -- LISTENER CORREGIDO: ENVIAR LOGS A CONSOLA EN LUGAR DE REPL
    -- ===================================================================
    dap.listeners.after["event_output"]["dapui_gdb"] = function(_, body)
      -- Solo enviar a la consola (no al REPL)
      if body.category == "stderr" or body.category == "log" or body.category == "output" then
        -- Obtener el buffer de la consola
        --
        local console_buf = dapui.elements.console.buffer().stdout

        -- Asegurarse de que el buffer existe
        if console_buf and vim.api.nvim_buf_is_valid(console_buf) then
          -- Añadir el contenido al final del buffer
          local lines = vim.split(body.output or "", "\n")
          local line_count = vim.api.nvim_buf_line_count(console_buf)
          vim.api.nvim_buf_set_lines(console_buf, line_count, line_count, false, lines)

          -- Mover el cursor al final
          vim.api.nvim_win_set_cursor(0, { line_count + #lines, 0 })
        end
      end
    end

    -- Atajo para alternar la interfaz
    vim.keymap.set("n", "<leader>du", function()
      dapui.toggle({})
    end, { desc = "Toggle DAP UI" })

    -- ===================================================================
    -- CONFIGURACIÓN ADICIONAL PARA MEJORAR VISUALIZACIÓN DE LOGS
    -- ===================================================================

    -- Forzar que la consola use el tipo de buffer correcto
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "dap-repl",
      callback = function()
        vim.schedule(function()
          local buf = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_set_option(buf, "filetype", "dapui_console")
        end)
      end,
    })

    -- Configuración especial para la consola
    vim.api.nvim_create_autocmd("BufWinEnter", {
      pattern = "dapui_console",
      callback = function()
        vim.wo.number = false
        vim.wo.relativenumber = false
        vim.wo.signcolumn = "no"
      end,
    })
  end,
}
