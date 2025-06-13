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
      local host = os.getenv("REMOTE_HOST")
      if not host then
        vim.notify("❌ Variable REMOTE_HOST no definida", vim.log.levels.ERROR)
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
    if os.getenv("REMOTE_HOST") then
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
          miDebuggerPath = os.getenv("REMOTE_DEBUG_GDB_PATH"),
          miDebuggerServerAddress = string.format(
            "%s:%s",
            os.getenv("REMOTE_HOST"),
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
        require("dap.repl").append(body.output)
      end
    end

    -- ===================================================================
    -- LÓGICA DE LANZAMIENTO REMOTO
    -- ===================================================================
    vim.keymap.set("n", "<leader>dR", function()
      local remote_configs = dap.configurations.cpp
      if not (remote_configs and #remote_configs > 0) then
        return vim.notify("❌ No se encontraron configuraciones DAP", vim.log.levels.ERROR)
      end

      local env_checks = {
        "SSHPASS",
        "REMOTE_HOST",
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

        -- Buscar configuración remota específica
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

        -- Comando para iniciar gdbserver remoto
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

        local wait_time = tonumber(os.getenv("DEBUG_WAIT_TIME")) or 2000
        vim.notify("⏳ Esperando " .. (wait_time / 1000) .. " segundos...", vim.log.levels.WARN)
        vim.defer_fn(function()
          vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
          dap.run(target_config)
        end, wait_time)
      end)
    end, { desc = "Debug Remote (con Argumentos)" })

    -- ===================================================================
    -- COMANDOS ADICIONALES
    -- ===================================================================
    -- Extrae la lógica a una función
    local function show_gdbserver_log()
      local dapui = require("dapui")
      local dap_repl = require("dap.repl")

      -- 1) Asegúrate de que el panel "Console" (REPL) esté abierto
      dapui.open("repl")

      -- 2) Construye el comando SSH como antes
      local ssh_cmd = build_ssh_command("tail -f /tmp/gdbserver.log")
      if not ssh_cmd then
        return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
      end

      -- 3) Arranca el job sin buffer y engancha los callbacks
      vim.fn.jobstart(ssh_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then
              dap_repl.append(line)

              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_option(buf, "filetype") == "dap-repl" then
                  vim.api.nvim_buf_call(buf, function()
                    vim.cmd("normal! G")
                  end)
                  break
                end
              end
            end
          end
        end,
        on_stderr = function(_, data)
          for _, line in ipairs(data) do
            if line ~= "" then
              dap_repl.append(line)
              for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_option(buf, "filetype") == "dap-repl" then
                  vim.api.nvim_buf_call(buf, function()
                    vim.cmd("normal! G")
                  end)
                  break
                end
              end
            end
          end
        end,
        on_exit = function(_, code)
          dap_repl.append("<<< gdbserver log job exited with code: " .. code .. " >>>")
        end,
      })
    end

    -- Comando manual (opcional, puedes dejarlo si quieres)
    vim.api.nvim_create_user_command(
      "DapGdbServerLog",
      show_gdbserver_log,
      { desc = "Mostrar logs de gdbserver remoto en dap-ui Console" }
    )

    vim.api.nvim_create_autocmd("User", {
      pattern = "DapUIOpen",
      callback = function()
        show_gdbserver_log()
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "dap-repl",
      callback = function()
        vim.defer_fn(function()
          show_gdbserver_log()
        end, 100)
      end,
    })

    -- ===================================================================
    -- HABILITAR LOGS DETALLADOS PARA DEPURACIÓN
    -- ===================================================================
    dap.set_log_level("TRACE")
  end,
}
