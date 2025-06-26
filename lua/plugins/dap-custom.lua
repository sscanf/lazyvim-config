return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },

  config = function()
    local dap = require("dap")

    -- ===================================================================
    -- PERSONALIZACIÓN DE ICONOS
    -- ===================================================================
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
    -- ===================================================================
    -- FUNCIÓN AUXILIAR SSH
    -- ===================================================================
    local function build_ssh_command(cmd)
      local host = os.getenv("REMOTE_SSH_HOST")
      if not host then
        vim.notify("❌ Variable REMOTE_SSH_HOST no definida", vim.log.levels.ERROR)
        return nil
      end

      return string.format(
        "sshpass -e ssh -p %s -o StrictHostKeyChecking=no root@%s '%s'",
        os.getenv("REMOTE_SSH_PORT") or "2222",
        host,
        cmd
      )
    end

    -- ===================================================================
    -- CONFIGURACIÓN DE LA SESIÓN REMOTA
    -- ===================================================================
    if os.getenv("REMOTE_SSH_HOST") then
      local local_program_path = os.getenv("LOCAL_PROGRAM_PATH")
      if local_program_path then
        local remote_config = {
          log = true,
          logToFile = false,
          name = "REMOTE DEBUG",
          type = "cppdbg",
          request = "launch",
          program = local_program_path,
          MIMode = "gdb",
          miDebuggerPath = os.getenv("LOCAL_GDB_PATH"),
          miDebuggerServerAddress = string.format(
            "%s:%s",
            os.getenv("REMOTE_SSH_HOST"),
            os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
          ),
          cwd = "${workspaceFolder}",
          stopOnEntry = true,
          setupCommands = {
            {
              text = "-enable-pretty-printing",
              description = "Habilitar impresión mejorada",
              ignoreFailures = false,
            },
          },
        }
        dap.configurations.c = dap.configurations.c or {}
        dap.configurations.cpp = dap.configurations.cpp or {}
        table.insert(dap.configurations.c, remote_config)
        table.insert(dap.configurations.cpp, remote_config)
      end
    end

    -- ===================================================================
    -- LISTENER PARA CAPTURAR SALIDA DEL SERVIDOR GDB
    -- ===================================================================
    dap.listeners.after["event_output"]["dapui_gdb"] = function(_, body)
      -- Capturar logs de GDB Server
      if body.category == "stderr" or body.category == "log" or body.category == "output" then
        -- Enviar a la consola de dap-ui
        --       require("dap.repl").append(body.output)
        require("dapui").eval(body.output, { panel = "console" })
      end
    end

    -- ===================================================================
    -- LÓGICA DE LANZAMIENTO REMOTO
    -- ===================================================================
    -- Define la función globalmente para poder llamarla desde dapui
    function _G.dap_remote_debug()
      local remote_configs = dap.configurations.cpp

      if not (remote_configs and #remote_configs > 0) then
        return vim.notify("❌ No se encontraron configuraciones DAP", vim.log.levels.ERROR)
      end

      local env_checks = {
        "SSHPASS",
        "REMOTE_SSH_HOST",
        "REMOTE_PROGRAM_PATH",
        "LOCAL_PROGRAM_PATH",
      }

      for _, var in ipairs(env_checks) do
        if not os.getenv(var) then
          return vim.notify("❌ Variable de entorno no definida: " .. var, vim.log.levels.ERROR)
        end
      end

      vim.ui.input({ prompt = "Argumentos de ejecución:", default = "" }, function(input_args)
        if input_args == nil then
          return vim.notify("❌ Depuración cancelada", vim.log.levels.WARN)
        end

        local args_table = {}
        if input_args ~= "" then
          args_table = vim.split(input_args, "%s+", { trimempty = true })
        end

        local target_config
        for _, config in ipairs(remote_configs) do
          if config.name == "REMOTE DEBUG" then
            target_config = vim.deepcopy(config)
            break
          end
        end

        if not target_config then
          target_config = vim.deepcopy(remote_configs[1])
        end

        target_config.args = args_table

        local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
        local remote_cmd = string.format(
          "nohup gdbserver :%s %s %s > /tmp/gdbserver.log 2>&1 &",
          gdb_port,
          os.getenv("REMOTE_PROGRAM_PATH"),
          table.concat(args_table, " ")
        )

        local ssh_cmd = build_ssh_command(remote_cmd)
        if not ssh_cmd then
          return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
        end

        vim.notify("🚀 Iniciando gdbserver remoto...", vim.log.levels.INFO)
        vim.fn.jobstart(ssh_cmd, {
          detach = true,
          on_exit = function(_, code)
            if code ~= 0 then
              vim.notify("❌ Fallo al iniciar gdbserver: código " .. code, vim.log.levels.ERROR)
            end
          end,
        })

        local wait_time = tonumber(os.getenv("DEBUG_WAIT_TIME")) or 500
        vim.notify("⏳ Esperando " .. (wait_time / 1000) .. " segundos...", vim.log.levels.WARN)
        vim.defer_fn(function()
          vim.notify("🛰️ Target_config " .. vim.inspect(target_config), vim.log.levels.INFO)
          vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
          dap.run(target_config)
        end, wait_time)
      end)
    end

    -- Mapea <leader>dR a la función global
    vim.keymap.set("n", "<leader>dR", _G.dap_remote_debug, { desc = "Debug Remote (con Argumentos)" })

    -- ===================================================================
    -- COMANDOS ADICIONALES
    -- ===================================================================
    -- Extrae la lógica a una función
    -- Usa una variable para guardar el job_id del tail remoto
    local tail_job_id = nil

    local function show_gdbserver_log()
      local dapui = require("dapui")
      local ssh_cmd = build_ssh_command("tail -f /tmp/gdbserver.log")
      if not ssh_cmd then
        return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
      end

      local function append_to_repl(line)
        require("dap.repl").append(line)
      end

      dapui.open("repl")

      print("[DEBUG] job lanzado")
      tail_job_id = vim.fn.jobstart(ssh_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
          for _, line in ipairs(data) do
            print("[DEBUG] línea: " .. line)
            if line ~= "" then
              append_to_repl(line)
            end
          end
        end,
        on_stderr = function(_, data)
          for _, line in ipairs(data) do
            print("[DEBUG] línea: " .. line)
            if line ~= "" then
              append_to_repl(line)
            end
          end
        end,
        on_exit = function(_, code)
          append_to_repl("<<< gdbserver log job exited with code: " .. code .. " >>>")
        end,
      })
    end

    vim.api.nvim_create_user_command(
      "DapGdbServerLog",
      show_gdbserver_log,
      { desc = "Mostrar logs de gdbserver remoto en dap-ui Console" }
    )

    -- Lanza el job automáticamente al inicializar la sesión DAP
    local dapui = require("dapui")

    local function append_to_repl(line)
      require("dap.repl").append(line)
      -- Scroll automático al final del REPL (forzado con vim.schedule)
      vim.schedule(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "dap-repl" then
            vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
          end
        end
      end)
    end

    dap.listeners.after.event_initialized["gdbserver_log_job"] = function()
      local ssh_cmd = build_ssh_command("tail -f /tmp/gdbserver.log")
      if not ssh_cmd then
        return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
      end

      dapui.open("repl")

      vim.fn.jobstart(ssh_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then
              append_to_repl(line)
            end
          end
        end,
        on_stderr = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then
              append_to_repl(line)
            end
          end
        end,
        on_exit = function(_, code)
          append_to_repl("<<< gdbserver log job exited with code: " .. code .. " >>>")
        end,
      })
    end

    vim.api.nvim_create_user_command(
      "DapGdbServerLog",
      show_gdbserver_log,
      { desc = "Mostrar logs de gdbserver remoto en dap-ui Console" }
    )

    vim.api.nvim_create_autocmd("User", {
      pattern = "DapUIClose",
      callback = function()
        -- Detener el tail remoto si está corriendo
        if tail_job_id then
          vim.fn.jobstop(tail_job_id)
          tail_job_id = nil
        end
        -- También puedes matar el proceso remoto por si acaso
        local kill_cmd = build_ssh_command("pkill -f 'tail -f /tmp/gdbserver.log'")
        vim.fn.jobstart(kill_cmd, { detach = true })
      end,
    })

    vim.keymap.set("n", "<leader>du", function()
      -- Cierra Neo-tree si está abierta
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
        if ft == "neo-tree" then
          vim.api.nvim_win_close(win, true)
        end
      end
      -- Toggle DAP UI
      dapui.toggle()
    end)

    dapui.setup()

    local neotree_augroup = "NeoTreeEvent_vim_buffer_deleted" -- Ajusta si tu grupo es diferente
    vim.api.nvim_create_autocmd("User", {
      pattern = "DapUIOpen",
      callback = function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local buf = vim.api.nvim_win_get_buf(win)
          local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
          if ft == "neo-tree" then
            vim.api.nvim_win_close(win, true)
          end
        end
      end,
    })

    -- ===================================================================
    -- HABILITAR LOGS DETALLADOS PARA DEPURACIÓN
    -- ===================================================================
    --    dap.set_log_level("TRACE")

    local gdb = os.getenv("LOCAL_GDB_PATH")
    dap.adapters.cppdbg = {
      id = "cppdbg",
      type = "executable",
      command = os.getenv("CPPDBG"),
    }
  end,
}
