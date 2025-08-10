return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },

  config = function()
    local dap = require("dap")
    local dapui = require("dapui")

    -- ================= ICONOS =================
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

    -- ================= SSH helper =================
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

    -- ================= Adapter cpptools → GDB =================
    local cppdbg = os.getenv("CPPDBG")
      or (vim.fn.stdpath("data") .. "/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7")
    dap.adapters.cppdbg = {
      id = "cppdbg",
      type = "executable",
      command = cppdbg,
    }

    -- ========= CONFIG LOCAL con diagnóstico =========
    local function make_local_launch(args_list)
      return {
        name = "LOCAL DEBUG (diag, GDB)",
        type = "cppdbg",
        request = "launch",

        program = function()
          local function pick_local_program()
            local build_dir = vim.fn.getcwd() .. "/build"
            local candidates = {}
            if vim.fn.isdirectory(build_dir) == 1 then
              local files = vim.fn.glob(build_dir .. "/**/*", true, true)
              for _, p in ipairs(files) do
                if vim.fn.executable(p) == 1 and not p:match("%.so$") and not p:match("/CMakeFiles/") then
                  table.insert(candidates, p)
                end
              end
            end
            local sel = (#candidates > 0) and candidates[1]
              or vim.fn.input("Ruta del ejecutable local: ", vim.fn.getcwd() .. "/", "file")
            return vim.fn.fnamemodify(sel, ":p")
          end

          local prog = pick_local_program()
          vim.g._last_prog = prog
          if prog == nil or prog == "" then
            error("No se seleccionó ejecutable")
          end
          if vim.fn.filereadable(prog) ~= 1 or vim.fn.executable(prog) ~= 1 then
            error("El ejecutable no existe o no es ejecutable: " .. tostring(prog))
          end
          return prog
        end,

        args = args_list or {},
        stopAtEntry = true,
        externalConsole = false,
        console = "internalConsole", -- Forzar uso consola interna

        cwd = function()
          local prog = (type(vim.g._last_prog) == "string" and vim.g._last_prog) or ""
          if prog == "" then
            return "${workspaceFolder}"
          end
          return vim.fn.fnamemodify(prog, ":h")
        end,

        environment = (function()
          local libdir = vim.fn.getcwd() .. "/build/lib"
          if vim.fn.isdirectory(libdir) == 1 then
            return { { name = "LD_LIBRARY_PATH", value = libdir .. ":" .. (os.getenv("LD_LIBRARY_PATH") or "") } }
          end
          return {}
        end)(),

        miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
        MIMode = "gdb",

        setupCommands = {
          { text = "-enable-pretty-printing", description = "Enable GDB pretty printing", ignoreFailures = true },
          { text = "-gdb-set new-console off", ignoreFailures = true }, -- Evita abrir PTY
        },

        logging = { engineLogging = true, trace = true, traceResponse = true },
      }
    end

    local function make_local_attach()
      return {
        name = "LOCAL ATTACH (PID)",
        type = "cppdbg",
        request = "attach",
        processId = function()
          local pid = vim.fn.input("PID del proceso local: ")
          return tonumber(pid)
        end,
        MIMode = "gdb",
        miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
        cwd = "${workspaceFolder}",
        setupCommands = {
          { text = "-enable-pretty-printing", description = "Enable GDB pretty printing", ignoreFailures = true },
        },
      }
    end

    dap.configurations.c = dap.configurations.c or {}
    dap.configurations.cpp = dap.configurations.cpp or {}
    table.insert(dap.configurations.c, make_local_launch({}))
    table.insert(dap.configurations.cpp, make_local_launch({}))
    table.insert(dap.configurations.c, make_local_attach())
    table.insert(dap.configurations.cpp, make_local_attach())

    vim.keymap.set("n", "<leader>dL", function()
      vim.ui.input({ prompt = "Args (local):", default = "" }, function(input)
        if input == nil then
          return
        end
        local args = {}
        if input ~= "" then
          args = vim.split(input, "%s+", { trimempty = true })
        end
        local cfg = make_local_launch(args)
        -- Blindaje extra
        cfg.externalConsole = false
        cfg.console = "internalConsole"
        dap.set_log_level("TRACE")
        dap.run(cfg)
      end)
    end, { desc = "Debug Local (GDB, diag)" })

    vim.keymap.set("n", "<leader>dP", function()
      dap.run(make_local_attach())
    end, { desc = "Attach Local (GDB) a PID" })

    -- ========= CONFIG REMOTA (gdbserver) =========
    local function add_remote_config()
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
          miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
          miDebuggerServerAddress = string.format(
            "%s:%s",
            os.getenv("REMOTE_SSH_HOST"),
            os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
          ),
          cwd = "${workspaceFolder}",
          stopAtEntry = true,
          setupCommands = {
            { text = "-enable-pretty-printing", description = "Habilitar impresión mejorada", ignoreFailures = false },
          },
        }
        table.insert(dap.configurations.c, remote_config)
        table.insert(dap.configurations.cpp, remote_config)
      end
    end

    if os.getenv("REMOTE_SSH_HOST") then
      add_remote_config()
    end

    -- ========= LANZAMIENTO REMOTO =========
    function _G.dap_remote_debug()
      local env_checks = { "SSHPASS", "REMOTE_SSH_HOST", "REMOTE_PROGRAM_PATH", "LOCAL_PROGRAM_PATH" }
      for _, var in ipairs(env_checks) do
        if not os.getenv(var) then
          return vim.notify("❌ Variable de entorno no definida: " .. var, vim.log.levels.ERROR)
        end
      end

      local remote_configs = dap.configurations.cpp
      if not (remote_configs and #remote_configs > 0) then
        return vim.notify("❌ No se encontraron configuraciones DAP", vim.log.levels.ERROR)
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
          vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
          dap.run(target_config)
        end, wait_time)
      end)
    end
    vim.keymap.set("n", "<leader>dR", _G.dap_remote_debug, { desc = "Debug Remote (con Argumentos)" })

    -- ========= LOGS de gdbserver → REPL =========
    local function append_to_repl(line)
      if line and line ~= "" then
        require("dap.repl").append(line)
        vim.schedule(function()
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
            if ft == "dap-repl" then
              vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
            end
          end
        end)
      end
    end

    local function show_gdbserver_log()
      local ssh_cmd = build_ssh_command("tail -f /tmp/gdbserver.log")
      if not ssh_cmd then
        return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
      end
      dapui.open("repl")
      vim.fn.jobstart(ssh_cmd, {
        stdout_buffered = false,
        on_stdout = function(_, data)
          for _, l in ipairs(data) do
            append_to_repl(l)
          end
        end,
        on_stderr = function(_, data)
          for _, l in ipairs(data) do
            append_to_repl(l)
          end
        end,
        on_exit = function(_, code)
          append_to_repl("<<< gdbserver log exited: " .. code .. " >>>")
        end,
      })
    end

    vim.api.nvim_create_user_command(
      "DapGdbServerLog",
      show_gdbserver_log,
      { desc = "Mostrar logs de gdbserver remoto" }
    )

    -- ========= DAP UI toggle =========
    vim.keymap.set("n", "<leader>du", function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
        if ft == "neo-tree" then
          vim.api.nvim_win_close(win, true)
        end
      end
      dapui.toggle()
    end)

    dapui.setup()

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

    -- Limpieza de configs lldb y consola externa
    local function _filter_cfgs(tbl)
      local out = {}
      for _, c in ipairs(tbl or {}) do
        if
          c.type ~= "lldb"
          and c.externalConsole ~= true
          and c.console ~= "integratedTerminal"
          and c.console ~= "externalTerminal"
        then
          table.insert(out, c)
        end
      end
      return out
    end
    dap.configurations.c = _filter_cfgs(dap.configurations.c)
    dap.configurations.cpp = _filter_cfgs(dap.configurations.cpp)

    -- Notificación al terminar depuración local
    dap.listeners.after.event_terminated["show-exit"] = function(_, body)
      local code = body and body.exitCode
      if code ~= nil then
        vim.notify(("Proceso terminado (exit code %s)"):format(code), vim.log.levels.INFO)
      else
        vim.notify("Proceso terminado (sin exit code)", vim.log.levels.INFO)
      end
    end
  end,
}
