return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },
  config = function()
    vim.g.dap_log_level = "TRACE"
    require("dap").set_log_level("TRACE")
    local dap = require("dap")
    local dapui = require("dapui")
    require("dap").defaults.fallback.terminal_win_cmd = "vsplit | terminal"

    -- ===== ICONOS =====
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

    -- ===== Adapters =====
    -- OpenDebugAD7 (cpptools)
    local cppdbg = os.getenv("CPPDBG") or (vim.fn.stdpath("data") .. "/OpenDebugAD7")
    dap.adapters.cppdbg = { id = "cppdbg", type = "executable", command = cppdbg }

    -- GDB DAP nativo (evita OpenDebugAD7)
    dap.adapters.gdb = {
      type = "executable",
      command = os.getenv("LOCAL_GDB_PATH") or "gdb",
      args = { "--interpreter=dap" }, -- sin gdbinit
    }

    -- ===== Helpers =====
    local function find_latest_executable_in_build()
      local build_dir = "out"
      if vim.fn.isdirectory(build_dir) ~= 1 then
        return nil
      end
      local files = vim.fn.systemlist("find " .. build_dir .. " -type f -perm -111")
      local latest, latest_time
      for _, f in ipairs(files) do
        if vim.fn.filereadable(f) == 1 then
          local abs_f = vim.fn.fnamemodify(f, ":p")
          local stat = vim.loop.fs_stat(abs_f)
          if stat and (not latest_time or stat.mtime.sec > latest_time) then
            latest = abs_f
            latest_time = stat.mtime.sec
          end
        end
      end
      return latest
    end

    local function path_basename(p)
      return p:match("([^/]+)$") or p
    end

    local function build_ssh_command(cmd)
      local host = os.getenv("REMOTE_SSH_HOST")
      local port = os.getenv("REMOTE_SSH_PORT") or "2222"
      if not host then
        vim.notify("❌ REMOTE_SSH_HOST no definida", vim.log.levels.ERROR)
        return nil
      end
      return string.format("sshpass -e ssh -p %s -o StrictHostKeyChecking=no root@%s %s", port, host, shell_quote(cmd))
    end

    local function run_remote(cmd)
      local ssh_cmd = build_ssh_command(cmd)
      if not ssh_cmd then
        return 1, ""
      end
      local out = vim.fn.systemlist(ssh_cmd)
      local code = vim.v.shell_error
      return code, table.concat(out, "\n")
    end

    local function scp_upload(local_path, remote_path)
      local host = os.getenv("REMOTE_SSH_HOST")
      local port = os.getenv("REMOTE_SSH_PORT") or "2222"
      if not host then
        return 1, "REMOTE_SSH_HOST no definida"
      end
      local scp_cmd = string.format(
        "sshpass -e scp -P %s -o StrictHostKeyChecking=no %s root@%s:%s",
        port,
        shell_quote(local_path),
        host,
        shell_quote(remote_path)
      )
      local out = vim.fn.systemlist(scp_cmd)
      return vim.v.shell_error, table.concat(out, "\n")
    end

    local function ensure_remote_program()
      -- 1) Si REMOTE_PROGRAM_PATH es ejecutable en el target, úsalo
      local rpath = os.getenv("REMOTE_PROGRAM_PATH")
      if rpath and rpath ~= "" then
        local code = select(1, run_remote(string.format("test -x %s", shell_quote(rpath))))
        if code == 0 then
          return rpath, nil
        end
      end
      -- 2) Si no, sube LOCAL_PROGRAM_PATH a REMOTE_UPLOAD_DIR (o /tmp)
      local lpath = os.getenv("LOCAL_PROGRAM_PATH")
      if not lpath or vim.fn.filereadable(lpath) ~= 1 then
        return nil, "LOCAL_PROGRAM_PATH no existe o no es legible"
      end
      local upload_dir = os.getenv("REMOTE_UPLOAD_DIR") or "/tmp"
      local base = path_basename(lpath)
      local stamp = tostring(os.time())
      local target = string.format("%s/%s-%s", upload_dir, base, stamp)

      local mk_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(upload_dir))))
      if mk_code ~= 0 then
        return nil, "No se pudo crear REMOTE_UPLOAD_DIR en el target"
      end
      local scp_code, scp_out = scp_upload(lpath, target)
      if scp_code ~= 0 then
        return nil, "SCP falló: " .. scp_out
      end
      local ch_code = select(1, run_remote(string.format("chmod +x %s", shell_quote(target))))
      if ch_code ~= 0 then
        return nil, "chmod +x falló en el target"
      end
      return target, nil
    end

    -- Nunca preguntar si $ENV está y el binario existe; si no, pregunta una vez.
    local function resolve_program_or_prompt(envvar, default_path, cb)
      local p = os.getenv(envvar)
      if p and p ~= "" and vim.fn.filereadable(p) == 1 then
        return cb(p)
      end
      -- Busca ejecutable sugerido en out/
      local deduced = find_latest_executable_in_build()
      local prompt_default = deduced or default_path or ""
      vim.ui.input({ prompt = "Ruta del ejecutable:", default = prompt_default }, function(answer)
        if not answer or answer == "" then
          return vim.notify(
            "❌ No se proporcionó ejecutable y $" .. envvar .. " no está definida",
            vim.log.levels.ERROR
          )
        end
        if vim.fn.filereadable(answer) ~= 1 then
          return vim.notify("❌ El ejecutable no existe/legible: " .. answer, vim.log.levels.ERROR)
        end
        vim.fn.setenv(envvar, answer)
        cb(answer)
      end)
    end

    local function gcc_python_path()
      local candidates = {
        "/usr/share/gcc/python",
      }
      for _, p in ipairs(candidates) do
        if vim.loop.fs_stat(p) then
          return p
        end
      end
      return nil
    end

    -- ===== Configs base =====
    dap.configurations.c = dap.configurations.c or {}
    dap.configurations.cpp = dap.configurations.cpp or {}

    -- Base REMOTE DEBUG (para que exista y no coja otro perfil)
    local function ensure_remote_base_config()
      for _, c in ipairs(dap.configurations.cpp) do
        if c.name == "REMOTE DEBUG" then
          return
        end
      end
      table.insert(dap.configurations.cpp, {
        name = "REMOTE DEBUG",
        type = "cppdbg",
        request = "launch",
        program = os.getenv("LOCAL_PROGRAM_PATH") or "/bin/true", -- se sobreescribe en runtime
        MIMode = "gdb",
        miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
        miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST"))
          .. ":"
          .. (os.getenv("REMOTE_GDBSERVER_PORT") or "10000"),
        cwd = "/",
        stopAtEntry = false,
        console = "internalConsole",
        setupCommands = {
          { text = "-enable-pretty-printing", description = "enable pretty printing", ignoreFailures = false },
          { text = "set auto-load off" },
          { text = "set pagination off" },
          { text = "set print pretty on" },
          { text = "set target-async on" },
        },
        logging = { engineLogging = true },
      })
    end

    -- ====== LOCAL (cppdbg) ======
    local function add_local_config_cppdbg()
      local p = os.getenv("LOCAL_PROGRAM_PATH")
      if p and vim.fn.filereadable(p) ~= 1 then
        p = nil
      end
      local local_config = {
        log = true,
        logToFile = false,
        name = "LOCAL DEBUG",
        type = "cppdbg",
        request = "launch",
        program = p or "/bin/true", -- se resuelve antes de run()
        MIMode = "gdb",
        miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
        cwd = p and vim.fn.fnamemodify(p, ":h") or "${workspaceFolder}",
        stopAtEntry = true,
        console = "internalConsole", -- evita TTY/runInTerminal
        externalConsole = false,
        env = { GDBINIT = "/dev/null" },
        setupCommands = {
          { text = "set auto-load off" },
          { text = "set pagination off" },
          { text = "set print pretty on" },
          { text = "set target-async on" },
        },
        logging = { engineLogging = true, trace = true, traceResponse = true },
      }
      table.insert(dap.configurations.c, local_config)
      table.insert(dap.configurations.cpp, local_config)
    end
    add_local_config_cppdbg()

    function _G.dap_local_debug()
      local cfgs = dap.configurations.cpp
      if not (cfgs and #cfgs > 0) then
        return vim.notify("❌ No se encontraron configuraciones DAP", vim.log.levels.ERROR)
      end

      vim.ui.input({ prompt = "Argumentos de ejecución:", default = "" }, function(input_args)
        if input_args == nil then
          return vim.notify("❌ Depuración cancelada", vim.log.levels.WARN)
        end
        local args = {}
        if input_args ~= "" then
          args = vim.split(input_args, "%s+", { trimempty = true })
        end

        local target
        for _, c in ipairs(cfgs) do
          if c.name == "LOCAL DEBUG" then
            target = vim.deepcopy(c)
            break
          end
        end
        target = target or vim.deepcopy(cfgs[1])
        target.args = args

        resolve_program_or_prompt("LOCAL_PROGRAM_PATH", target.program, function(p)
          target.program = p
          target.cwd = vim.fn.fnamemodify(p, ":h")
          dap.run(target)
        end)
      end)
    end
    vim.keymap.set("n", "<leader>dL", _G.dap_local_debug, { desc = "Debug Local (cppdbg) con argumentos" })

    -- ====== LOCAL (GDB DAP nativo) ======
    local function add_local_gdbdap_config()
      local p = os.getenv("LOCAL_PROGRAM_PATH")
      if p and vim.fn.filereadable(p) ~= 1 then
        p = nil
      end
      local gcc_py = gcc_python_path()
      local setup = {
        { text = "set pagination off" },
        { text = "set print pretty on" },
        { text = "set target-async on" },
      }
      if gcc_py then
        table.insert(setup, { text = ('python import sys; sys.path.insert(0, "%s")'):format(gcc_py) })
        table.insert(setup, { text = "python from libstdcxx.v6.printers import register_libstdcxx_printers" })
        table.insert(setup, { text = "python register_libstdcxx_printers(None)" })
      else
        vim.notify(
          "⚠️ No encontré /usr/share/gcc-*/python; sin pretty-printers libstdc++ para GDB DAP",
          vim.log.levels.WARN
        )
      end

      local cfg = {
        name = "LOCAL (GDB DAP, no autoload)",
        type = "gdb",
        request = "launch",
        program = p or "/bin/true", -- se resuelve antes de run()
        cwd = p and vim.fn.fnamemodify(p, ":h") or "${workspaceFolder}",
        stopAtEntry = true,
        env = { GDBINIT = "/dev/null" },
        setupCommands = setup,
      }
      table.insert(dap.configurations.c, cfg)
      table.insert(dap.configurations.cpp, cfg)
    end
    add_local_gdbdap_config()

    function _G.dap_local_gdbdap()
      local list = dap.configurations.cpp or {}
      local target
      for _, c in ipairs(list) do
        if c.name == "LOCAL (GDB DAP, no autoload)" then
          target = vim.deepcopy(c)
          break
        end
      end
      if not target then
        return vim.notify('❌ Config "LOCAL (GDB DAP, no autoload)" no encontrada', vim.log.levels.ERROR)
      end
      vim.ui.input({ prompt = "Argumentos de ejecución:", default = "" }, function(input_args)
        if input_args == nil then
          return vim.notify("❌ Depuración cancelada", vim.log.levels.WARN)
        end
        target.args = (input_args == "" and {} or vim.split(input_args, "%s+", { trimempty = true }))
        resolve_program_or_prompt("LOCAL_PROGRAM_PATH", target.program, function(p)
          target.program = p
          target.cwd = vim.fn.fnamemodify(p, ":h")
          dap.run(target)
        end)
      end)
    end
    vim.keymap.set("n", "<leader>dG", _G.dap_local_gdbdap, { desc = "Debug Local (GDB DAP) con argumentos" })

    -- ====== REMOTO (cppdbg + gdbserver por SSH) ======
    function _G.dap_remote_debug()
      for _, var in ipairs({ "SSHPASS", "REMOTE_SSH_HOST" }) do
        if not os.getenv(var) then
          return vim.notify("❌ Variable de entorno no definida: " .. var, vim.log.levels.ERROR)
        end
      end

      vim.ui.input({ prompt = "Argumentos de ejecución:", default = "" }, function(input_args)
        if input_args == nil then
          return vim.notify("❌ Depuración cancelada", vim.log.levels.WARN)
        end
        local args = {}
        if input_args ~= "" then
          args = vim.split(input_args, "%s+", { trimempty = true })
        end

        -- No preguntar ejecutable si $LOCAL_PROGRAM_PATH está y es válido:
        resolve_program_or_prompt("LOCAL_PROGRAM_PATH", nil, function(local_prog)
          -- Propaga al entorno para usos posteriores (ensure_remote_program, etc.)
          vim.fn.setenv("LOCAL_PROGRAM_PATH", local_prog)

          ensure_remote_base_config()

          -- Asegura binario remoto (usa REMOTE_PROGRAM_PATH si existe; si no, sube el local)
          local rprog, err = ensure_remote_program()
          if not rprog then
            return vim.notify("❌ " .. err, vim.log.levels.ERROR)
          end

          -- Construye config remota
          local cfgs = dap.configurations.cpp
          if not (cfgs and #cfgs > 0) then
            return vim.notify("❌ No se encontraron configuraciones DAP", vim.log.levels.ERROR)
          end
          local target
          for _, c in ipairs(cfgs) do
            if c.name == "REMOTE DEBUG" then
              target = vim.deepcopy(c)
              break
            end
          end
          target = target or vim.deepcopy(cfgs[1])
          local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"

          target.args = args
          target.program = local_prog -- símbolos locales
          target.type = "cppdbg"
          target.request = "launch"
          target.MIMode = "gdb"
          target.miDebuggerPath = target.miDebuggerPath or "/usr/bin/gdb"
          target.miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST"))
            .. ":"
            .. (os.getenv("REMOTE_GDBSERVER_PORT") or "10000")

          target.console = "internalConsole"
          target.stopAtEntry = false

          -- Mata gdbserver previo y lanza uno nuevo
          local qargs = {}
          for _, a in ipairs(args) do
            table.insert(qargs, shell_quote(a))
          end
          local kill_pat = shell_quote("gdbserver :" .. gdb_port)
          local cmd = string.format(
            "pkill -f %s || true; nohup gdbserver :%s %s %s > /tmp/gdbserver.log 2>&1 & disown",
            kill_pat,
            gdb_port,
            shell_quote(rprog),
            table.concat(qargs, " ")
          )

          local ssh_cmd = build_ssh_command(cmd)
          if not ssh_cmd then
            return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
          end

          vim.notify("🚀 Iniciando gdbserver remoto en " .. rprog .. "...", vim.log.levels.INFO)
          vim.fn.jobstart(ssh_cmd, {
            detach = true,
            on_exit = function(_, code)
              if code ~= 0 then
                vim.notify("❌ Fallo al iniciar gdbserver: código " .. code, vim.log.levels.ERROR)
              end
            end,
          })

          local wait_ms = tonumber(os.getenv("DEBUG_WAIT_TIME")) or 700
          vim.notify("⏳ Esperando " .. (wait_ms / 1000) .. " s para que gdbserver escuche...", vim.log.levels.WARN)
          vim.defer_fn(function()
            vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
            dap.run(target)
          end, wait_ms)
        end)
      end)
    end
    vim.keymap.set("n", "<leader>dR", _G.dap_remote_debug, { desc = "Debug Remote (con Argumentos)" })

    -- ===== DAP UI, REPL y logs =====
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

    local function show_gdbserver_log_remote()
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
      show_gdbserver_log_remote,
      { desc = "Logs de gdbserver remoto" }
    )

    vim.keymap.set("n", "<leader>du", function()
      dapui.toggle()
    end)
    dapui.setup()
  end,
}
