return {
  "rcarriga/nvim-dap-ui",

  lazy = false,
  dependencies = { "nvim-neotest/nvim-nio" },

  config = function()
    local dap = require("dap")
    local dapui = require("dapui")
    dapui.setup({

      auto_open = true,
      icons = { expanded = "▾", collapsed = "▸", current_frame = "★" },
      mappings = {
        expand = { "<cr>", "<2-leftmouse>" },
        open = "o",
        remove = "d",
        edit = "e",
        repl = "r",
      },
      element_mappings = {},
      expand_lines = true,
      force_buffers = true,
      controls = {},
      layouts = {
        {
          position = "right",
          size = 40,
          elements = {
            { id = "scopes", size = 0.35 },
            { id = "watches", size = 0.35 },
            { id = "stacks", size = 0.30 },
          },
        },
        {
          position = "bottom",
          size = 30,
          elements = {
            "console",
            "repl",
            "breakpoints",
          },
        },
      },
      floating = {
        max_height = nil,
        max_width = nil,
        border = "single",
        mappings = {
          close = { "q", "<esc>" },
        },
      },
      windows = { indent = 1 },
      render = {
        max_type_length = nil,
        max_value_lines = 100,
        indent = 1,
      },
    })

    -- listeners para abrir/cerrar automáticamente
    dap.listeners.after.event_initialized["dapui_config"] = function()
      dapui.open()
    end
    dap.listeners.before.event_terminated["dapui_config"] = function()
      dapui.close({})
    end
    dap.listeners.before.event_exited["dapui_config"] = function()
      dapui.close({})
    end
  end,
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
}
