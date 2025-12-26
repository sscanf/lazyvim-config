--[[
================================================================================
REMOTE C/C++ DEBUGGING CONFIGURATION
================================================================================
Advanced configuration for remote C/C++ debugging via SSH and gdbserver.
Features:
  - Remote debugging over SSH with gdbserver
  - Automatic program deployment to remote host
  - CMake integration for build paths
  - Environment variables configuration (REMOTE_SSH_HOST, REMOTE_SSH_PORT, etc.)
  - GDB pretty printers support
  - Real-time output streaming (stdout/stderr) using tail -f (NO POLLING!)
  - Keymap: <leader>dR to start remote debugging with arguments

Output Capture:
  - Simple bash redirection (>> file 2>&1) for maximum compatibility
  - Uses stdbuf to disable buffering for instant output
  - Streams output in real-time with 'tail -f' (zero polling, zero delay)
  - One persistent SSH connection for streaming (very low resource usage)
  - Control with <leader>dC (cleanup) and <leader>dM (status)
  - Disable with: export DAP_MONITOR_ENABLED=false

Requirements:
  - sshpass for SSH authentication
  - CMake project with CMakeCache.txt
  - stdbuf and tail commands on remote host (standard in GNU coreutils)
  - Environment variables: REMOTE_SSH_HOST, SSHPASS, LOCAL_PROGRAM_PATH, etc.
Plugin: mfussenegger/nvim-dap with cppdbg adapter
================================================================================
--]]

local dap = require("dap")

-- ===== Configs base =====
dap.configurations.c = dap.configurations.c
dap.configurations.cpp = dap.configurations.cpp

dap.adapters.cppdbg = {
  id = "cppdbg",
  type = "executable",
  command = vim.fn.stdpath("data") .. "/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7",
  options = {
    detached = false,
  },
}

local function shell_quote(str)
  return "'" .. tostring(str):gsub("'", "'\\''") .. "'"
end

local function path_basename(p)
  return p:match("([^/]+)$") or p
end

local function get_cmake_cache_var(var_name)
  local function find_cache_buf()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("CMakeCache") then
        return buf
      end
    end
    return nil
  end

  local buf = find_cache_buf()
  if not buf then
    local cache_path = vim.fn.findfile("CMakeCache.txt", "**")
    if not cache_path or cache_path == "" then
      print("CMakeCache.txt not found.")
      return nil, "CMakeCache.txt not found."
    end
    buf = vim.fn.bufadd(cache_path)
    vim.fn.bufload(buf)
  end
  if not buf then
    print("Failed to open CMakeCache buffer.")
    return nil, "Failed to open CMakeCache buffer."
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, line in ipairs(lines) do
    local var, value = line:match("^([%w_]+):[%w_]+=(.+)$")
    if var == var_name then
      return value
    end
  end
  return nil, "Variable '" .. var_name .. "' not found in CMakeCache."
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
    return 1, "Error building ssh command"
  end
  print(ssh_cmd)
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

-- Base REMOTE DEBUG (para que exista y no coja otro perfil)
--
local function ensure_remote_base_config()
  for _, c in ipairs(dap.configurations.cpp) do
    if c.name == "REMOTE DEBUG" then
      return
    end
  end

  local toolchain_path = os.getenv("OECORE_TARGET_SYSROOT")
  local pretty_printer_path = toolchain_path .. "/usr/lib/cmake/ZOne/tools/gdb"

  table.insert(dap.configurations.cpp, {
    name = "REMOTE DEBUG",
    type = "cppdbg",
    request = "launch",
    program = os.getenv("LOCAL_PROGRAM_PATH") or "/bin/true", -- se sobreescribe en runtime
    MIMode = "gdb",
    miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
    miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST")) .. ":" .. (os.getenv("REMOTE_GDBSERVER_PORT") or "10000"),
    cwd = "/",
    stopAtEntry = false,
    console = "internalConsole",
    setupCommands = {
      { text = "-enable-pretty-printing" },
      { text = "set auto-load off" },
      { text = "set pagination off" },
      { text = "set print pretty on" },
      { text = "set target-async on" },
      { text = "set auto-load safe-path /", ignoreFailures = true },
      { text = "set auto-load yes", ignoreFailures = true },
      { text = "python sys.path.insert(0, '" .. pretty_printer_path .. "')" },
      { text = "python import zo_pretty_printers; zo_pretty_printers.register_printers(gdb.current_objfile())" },
    },
    logging = { engineLogging = true },
  })
end

local function ensure_remote_program()
  local lpath = os.getenv("LOCAL_PROGRAM_PATH")
  if not lpath or vim.fn.filereadable(lpath) ~= 1 then
    return nil, "LOCAL_PROGRAM_PATH no existe o no es legible"
  end

  local deploy_path = get_cmake_cache_var("DEPLOY_REMOTE_PATH")
  if not deploy_path or deploy_path == "" then
    return nil, "DEPLOY_REMOTE_PATH no encontrado en CMake cache"
  end

  local base = path_basename(lpath)
  local rpath = deploy_path

  local target = string.format("%s%s", rpath, base)

  print("Checking if remote directory exists: " .. deploy_path)
  local exists_code = select(1, run_remote(string.format("test -d %s", shell_quote(deploy_path))))
  if exists_code ~= 0 then
    print("Creating directory remote: " .. deploy_path)
    local mk_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(deploy_path))))
    if mk_code ~= 0 then
      return nil, "No se pudo crear " .. deploy_path
    end
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

local function resolve_program_or_prompt(envvar, default_path, cb)
  ensure_remote_base_config()

  local p = os.getenv(envvar)
  if p and p ~= "" and vim.fn.filereadable(p) == 1 then
    return cb(p)
  end
  vim.ui.input({ prompt = "Ruta del ejecutable:", default = default_path or "" }, function(answer)
    if not answer or answer == "" then
      return vim.notify("❌ No se proporcionó ejecutable y $" .. envvar .. " no está definida", vim.log.levels.ERROR)
    end
    if vim.fn.filereadable(answer) ~= 1 then
      return vim.notify("❌ El ejecutable no existe/legible: " .. answer, vim.log.levels.ERROR)
    end
    vim.fn.setenv(envvar, answer)
    cb(answer)
  end)
end

function _G.dap_remote_debug()
  vim.env.SSHPASS = get_cmake_cache_var("REMOTE_SSH_PASS")
  vim.env.REMOTE_SSH_HOST = get_cmake_cache_var("REMOTE_SSH_HOST")

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

    local project_name = get_cmake_cache_var("CMAKE_PROJECT_NAME")
    local cmake_key = string.format("%s_BINARY_DIR", project_name)
    local default_exec = get_cmake_cache_var(cmake_key) or ""
    default_exec = string.format("%s/%s", default_exec, project_name)

    resolve_program_or_prompt("LOCAL_PROGRAM_PATH", default_exec, function(local_prog)
      local rprog, err = ensure_remote_program()
      if not rprog then
        return vim.notify("❌ " .. err, vim.log.levels.ERROR)
      end

      local cfgs = dap.configurations.cpp
      if type(cfgs) ~= "table" or #cfgs == 0 then
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
      target.program = local_prog
      target.type = "cppdbg"
      target.request = "launch"
      target.MIMode = "gdb"
      target.miDebuggerPath = os.getenv("GDB")
      target.miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST")) .. ":" .. gdb_port

      -- 🔥 CAMBIOS IMPORTANTES: Configurar para capturar salida
      target.console = "integratedTerminal" -- o "integratedTerminal" si prefieres
      target.externalConsole = true
      target.stopAtEntry = false

      -- Configuración adicional para capturar salida
      target.logging = {
        engineLogging = true,
        trace = true,
      }

      local qargs = {}
      for _, a in ipairs(args) do
        table.insert(qargs, shell_quote(a))
      end

      -- 🔥 STREAMING: Captura salida con redirecciones simples (más confiable)
      local output_base = "/tmp/" .. path_basename(rprog)
      local output_file = output_base .. ".output"
      local script_file = output_base .. ".sh"
      local kill_pat = shell_quote("gdbserver :" .. gdb_port)

      -- Crear script bash que ejecuta gdbserver con output sin buffer
      local gdb_command = string.format("gdbserver :%s %s %s", gdb_port, rprog, table.concat(args, " "))
      local create_script = string.format(
        "cat > %s << 'EOFSCRIPT'\n#!/bin/bash\n# Deshabilitar buffering para output inmediato\nstdbuf -oL -eL %s\nEOFSCRIPT\nchmod +x %s",
        shell_quote(script_file),
        gdb_command,
        shell_quote(script_file)
      )

      -- Crear el script
      local create_cmd = build_ssh_command(create_script)
      vim.notify("📝 Preparando gdbserver remoto...", vim.log.levels.INFO)

      local create_result = vim.fn.system(create_cmd)
      if vim.v.shell_error ~= 0 then
        vim.notify("❌ Error preparando script: " .. create_result, vim.log.levels.ERROR)
        return
      end

      -- Comando final: ejecutar script con redirecciones simples
      -- Matar procesos gdbserver anteriores (compatible con sistemas sin pkill)
      local kill_cmd = string.format(
        "ps aux | grep 'gdbserver :%s' | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null || true",
        gdb_port
      )

      local cmd = string.format(
        "%s; rm -f %s; touch %s; nohup %s >> %s 2>&1 & echo $!",
        kill_cmd,
        shell_quote(output_file),
        shell_quote(output_file),
        shell_quote(script_file),
        shell_quote(output_file)
      )

      local ssh_cmd = build_ssh_command(cmd)
      if not ssh_cmd then
        return vim.notify("❌ Error construyendo comando SSH", vim.log.levels.ERROR)
      end

      vim.notify("🚀 Iniciando gdbserver remoto...", vim.log.levels.INFO)
      vim.notify("📋 Comando: " .. gdb_command, vim.log.levels.DEBUG)

      -- Ejecutar y capturar el PID
      local result = vim.fn.system(ssh_cmd)
      local gdbserver_pid = vim.trim(result)

      if vim.v.shell_error ~= 0 or gdbserver_pid == "" then
        vim.notify("❌ Error al iniciar gdbserver", vim.log.levels.ERROR)
        vim.notify("💡 Ejecuta :DapRemoteDiagnostic para más información", vim.log.levels.INFO)
        return
      end

      vim.notify("✅ Gdbserver iniciado (PID: " .. gdbserver_pid .. ")", vim.log.levels.INFO)
      vim.notify("📁 Output: " .. output_file, vim.log.levels.DEBUG)

      local wait_ms = tonumber(os.getenv("DEBUG_WAIT_TIME")) or 3000
      vim.notify("⏳ Esperando " .. (wait_ms / 1000) .. " s para que gdbserver escuche...", vim.log.levels.WARN)

      vim.defer_fn(function()
        -- Verificar si gdbserver está corriendo (compatible sin pgrep)
        local check_cmd = build_ssh_command("ps aux | grep 'gdbserver :" .. gdb_port .. "' | grep -v grep")
        local check_result = vim.fn.system(check_cmd)

        if vim.v.shell_error ~= 0 or check_result == "" then
          vim.notify("⚠️  Gdbserver no está corriendo en el host remoto", vim.log.levels.WARN)
          -- Intentar leer el output file para ver errores
          local error_check = build_ssh_command("cat " .. shell_quote(output_file) .. " 2>/dev/null | head -20")
          local error_output = vim.fn.system(error_check)
          if error_output ~= "" then
            vim.notify("📄 Output de gdbserver:\n" .. error_output, vim.log.levels.WARN)
          end
        else
          vim.notify("✅ Gdbserver está corriendo", vim.log.levels.INFO)
        end

        -- Verificar si el puerto está escuchando (con fallback a netstat)
        local port_check = build_ssh_command("(ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null) | grep ':" .. gdb_port .. "'")
        local port_result = vim.fn.system(port_check)

        if vim.v.shell_error ~= 0 or not port_result:match(gdb_port) then
          vim.notify("⚠️  Puerto " .. gdb_port .. " puede no estar escuchando aún", vim.log.levels.WARN)
          vim.notify("💡 Esto es normal - gdbserver espera la primera conexión para abrir el puerto", vim.log.levels.INFO)
        else
          vim.notify("✅ Puerto " .. gdb_port .. " está escuchando", vim.log.levels.INFO)
        end

        vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
        vim.notify("ℹ️  Si ves 'Cursor position outside buffer', recompila el ejecutable con símbolos de debug (-g)", vim.log.levels.INFO)

        -- 🔥 Configurar función para monitorear la salida
        local function setup_output_monitoring()
          -- 🔥 VARIABLE DE CONTROL
          _G.dapui_monitoring_active = true

          -- 🔥 FUNCIÓN MEJORADA PARA ENCONTRAR LA CONSOLA DAP-UI
          local function find_dapui_console_buffer()
            -- Buscar por filetype (dapui_console o dap-repl)
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                local ok, ft = pcall(vim.api.nvim_buf_get_option, buf, "filetype")
                if ok and (ft == "dapui_console" or ft == "dap-repl") then
                  vim.notify("✅ Buffer de consola encontrado (ft: " .. ft .. ")", vim.log.levels.DEBUG)
                  return buf
                end
              end
            end

            -- Buscar por nombre de buffer
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                local name = vim.api.nvim_buf_get_name(buf)
                if name:match("DAP Console") or name:match("dap%-repl") then
                  vim.notify("✅ Buffer de consola encontrado (name: " .. name .. ")", vim.log.levels.DEBUG)
                  return buf
                end
              end
            end

            -- Debug: Listar todos los buffers disponibles
            vim.notify("⚠️  No se encontró buffer de consola DAP. Buffers disponibles:", vim.log.levels.WARN)
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
                local ok, ft = pcall(vim.api.nvim_buf_get_option, buf, "filetype")
                local name = vim.api.nvim_buf_get_name(buf)
                if ok then
                  vim.notify(string.format("  buf %d: ft=%s, name=%s", buf, ft or "none", name), vim.log.levels.WARN)
                end
              end
            end

            return nil
          end

          -- Buffer de fallback para output remoto
          local fallback_buf = nil
          local function get_or_create_fallback_buffer()
            if not fallback_buf or not vim.api.nvim_buf_is_valid(fallback_buf) then
              fallback_buf = vim.api.nvim_create_buf(false, true)
              vim.api.nvim_buf_set_name(fallback_buf, "Remote Debug Output")
              vim.api.nvim_buf_set_option(fallback_buf, "filetype", "log")
              vim.api.nvim_buf_set_option(fallback_buf, "bufhidden", "hide")
              vim.api.nvim_buf_set_option(fallback_buf, "swapfile", false)
              vim.notify("📋 Creado buffer de fallback para output remoto. Usa :buffer 'Remote Debug Output'", vim.log.levels.INFO)
            end
            return fallback_buf
          end

          -- 🔥 FUNCIÓN PARA AÑADIR TEXTO A LA CONSOLA
          local function append_to_console(message, is_error)
            local console_buf = find_dapui_console_buffer()

            -- Si no hay consola DAP-UI, usar buffer de fallback
            if not console_buf or not vim.api.nvim_buf_is_valid(console_buf) then
              console_buf = get_or_create_fallback_buffer()
            end

            pcall(function()
              local last_line = vim.api.nvim_buf_line_count(console_buf)
              vim.api.nvim_buf_set_option(console_buf, "modifiable", true)

              local timestamp = os.date("%H:%M:%S")
              local prefix = is_error and "🚨 [ERR] " or "📤 [OUT] "
              local formatted_msg = string.format("[%s] %s%s", timestamp, prefix, message)

              vim.api.nvim_buf_set_lines(console_buf, last_line, last_line, false, { formatted_msg })
              vim.api.nvim_buf_set_option(console_buf, "modifiable", false)

              -- Auto-scroll si la ventana está visible
              local buf_info = vim.fn.getbufinfo(console_buf)
              if buf_info and buf_info[1] and buf_info[1].windows then
                for _, winid in ipairs(buf_info[1].windows) do
                  if vim.api.nvim_win_is_valid(winid) then
                    vim.api.nvim_win_set_cursor(winid, { last_line + 1, 0 })
                  end
                end
              end
            end)

            return true
          end

          -- 🔥 STREAMING EN TIEMPO REAL CON TAIL -F (SIN POLLING)
          local monitor_enabled = os.getenv("DAP_MONITOR_ENABLED") ~= "false"

          if monitor_enabled then
            -- Construir comando SSH con tail -f para streaming continuo
            local tail_cmd = build_ssh_command("tail -f -n 0 " .. shell_quote(output_file) .. " 2>/dev/null")

            vim.notify("🔍 Iniciando streaming de salida remota...", vim.log.levels.INFO)

            -- Iniciar job con tail -f (streaming continuo, sin polling)
            _G.dapui_monitor_job = vim.fn.jobstart(tail_cmd, {
              on_stdout = function(_, lines)
                if not _G.dapui_monitoring_active then
                  return
                end

                -- Este callback se ejecuta AUTOMÁTICAMENTE cuando hay nuevas líneas
                vim.schedule(function()
                  for _, line in ipairs(lines) do
                    -- Filtrar líneas vacías y mensajes de control de gdbserver
                    if line ~= "" and not line:match("^Remote debugging") and not line:match("^Process .* created") then
                      -- Detectar si es stderr (líneas con "error", "warning", etc.)
                      local is_error = line:match("[Ee]rror") or line:match("[Ww]arning") or line:match("FAIL")
                      append_to_console(line, is_error)
                    end
                  end
                end)
              end,
              on_stderr = function(_, lines)
                -- Errores del comando SSH/tail mismo
                vim.schedule(function()
                  for _, line in ipairs(lines) do
                    if line ~= "" then
                      vim.notify("SSH/tail error: " .. line, vim.log.levels.WARN)
                    end
                  end
                end)
              end,
              on_exit = function(_, code)
                if code ~= 0 and _G.dapui_monitoring_active then
                  vim.notify("⚠️  Streaming de salida terminó (código: " .. code .. ")", vim.log.levels.WARN)
                end
                _G.dapui_monitor_job = nil
              end,
              stdout_buffered = false,  -- Streaming inmediato, sin buffer
              stderr_buffered = false,
            })

            -- Mensaje inicial
            vim.defer_fn(function()
              append_to_console("🎯 Streaming remoto iniciado (sin polling)", false)
              append_to_console("📁 Archivo: " .. output_file, false)
              append_to_console("⚡ Modo: tail -f (tiempo real)", false)
            end, 500)
          else
            vim.notify("ℹ️  Monitoreo remoto deshabilitado", vim.log.levels.INFO)
          end

          -- 🔥 LIMPIAR AL TERMINAR
          local function cleanup_monitor()
            if _G.dapui_monitoring_active then
              _G.dapui_monitoring_active = false

              -- Matar el job de tail -f
              if _G.dapui_monitor_job then
                pcall(function()
                  vim.fn.jobstop(_G.dapui_monitor_job)
                  _G.dapui_monitor_job = nil
                end)
              end

              append_to_console("🛑 Streaming remoto finalizado", false)
            end
          end

          -- Registrar limpieza en múltiples eventos
          dap.listeners.before.event_terminated["dapui_monitor"] = cleanup_monitor
          dap.listeners.before.event_exited["dapui_monitor"] = cleanup_monitor
          dap.listeners.before.disconnect["dapui_monitor"] = cleanup_monitor
        end

        -- Iniciar monitoreo de salida
        setup_output_monitoring()

        -- Ejecutar la configuración DAP
        dap.run(target)
      end, wait_ms)
    end)
  end)
end
vim.keymap.set("n", "<leader>dR", _G.dap_remote_debug, { desc = "Debug Remote (con Argumentos)" })

-- ========== COMANDOS PARA VER OUTPUT ==========

-- Comando para abrir el buffer de output remoto
vim.api.nvim_create_user_command("DapShowOutput", function()
  -- Buscar el buffer de output
  local buf = nil
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if name:match("Remote Debug Output") then
      buf = b
      break
    end
  end

  if buf then
    -- Abrir en split horizontal
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.notify("✅ Buffer de output abierto", vim.log.levels.INFO)
  else
    vim.notify("⚠️  No hay buffer de output remoto. Inicia un debug remoto primero.", vim.log.levels.WARN)
  end
end, { desc = "Abrir buffer de output remoto" })

-- Keymap para abrir output rápidamente
vim.keymap.set("n", "<leader>do", ":DapShowOutput<CR>", { desc = "Show Remote Debug Output" })

-- Comando para abrir/cerrar DAP-UI
vim.api.nvim_create_user_command("DapUIToggle", function()
  require("dapui").toggle()
end, { desc = "Toggle DAP UI" })

vim.keymap.set("n", "<leader>du", ":DapUIToggle<CR>", { desc = "Toggle DAP UI" })

-- ========== COMANDOS DE CONTROL DEL MONITOREO ==========

-- Limpiar/detener el streaming de monitoreo
vim.api.nvim_create_user_command("DapCleanupMonitor", function()
  if _G.dapui_monitoring_active then
    _G.dapui_monitoring_active = false
    if _G.dapui_monitor_job then
      pcall(function()
        vim.fn.jobstop(_G.dapui_monitor_job)
        _G.dapui_monitor_job = nil
      end)
    end
    vim.notify("✅ Streaming de monitoreo detenido", vim.log.levels.INFO)
  else
    vim.notify("ℹ️  No hay streaming activo", vim.log.levels.INFO)
  end
end, { desc = "Detener streaming de monitoreo remoto" })

-- Mostrar estado del monitoreo
vim.api.nvim_create_user_command("DapMonitorStatus", function()
  if _G.dapui_monitoring_active then
    local job_status = _G.dapui_monitor_job and "Activo (streaming)" or "Inactivo"
    vim.notify(string.format("🔍 Monitor: %s | Job ID: %s", job_status, tostring(_G.dapui_monitor_job or "N/A")), vim.log.levels.INFO)
  else
    vim.notify("ℹ️  Monitoreo inactivo", vim.log.levels.INFO)
  end
end, { desc = "Estado del monitoreo remoto" })

-- Keymaps rápidos
vim.keymap.set("n", "<leader>dC", ":DapCleanupMonitor<CR>", { desc = "Cleanup Debug Monitor" })
vim.keymap.set("n", "<leader>dM", ":DapMonitorStatus<CR>", { desc = "Monitor Status" })

-- Comando de diagnóstico para verificar la configuración de debugging remoto
vim.api.nvim_create_user_command("DapRemoteDiagnostic", function()
  local host = os.getenv("REMOTE_SSH_HOST")
  local port = os.getenv("REMOTE_SSH_PORT") or "2222"
  local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"

  vim.notify("🔍 Diagnóstico de Debugging Remoto", vim.log.levels.INFO)
  vim.notify("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Verificar variables de entorno
  local vars = {
    "REMOTE_SSH_HOST",
    "REMOTE_SSH_PORT",
    "SSHPASS",
    "LOCAL_PROGRAM_PATH",
    "LOCAL_GDB_PATH",
    "REMOTE_GDBSERVER_PORT"
  }

  for _, var in ipairs(vars) do
    local value = os.getenv(var)
    if value then
      if var == "SSHPASS" then
        vim.notify("✅ " .. var .. ": ***", vim.log.levels.INFO)
      else
        vim.notify("✅ " .. var .. ": " .. value, vim.log.levels.INFO)
      end
    else
      vim.notify("❌ " .. var .. ": NO DEFINIDA", vim.log.levels.WARN)
    end
  end

  if not host then
    vim.notify("❌ REMOTE_SSH_HOST no definida. No se pueden hacer más verificaciones.", vim.log.levels.ERROR)
    return
  end

  vim.notify("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Verificar conectividad SSH
  vim.notify("🔌 Verificando conectividad SSH...", vim.log.levels.INFO)
  local ssh_test = build_ssh_command("echo 'OK'")
  local result = vim.fn.system(ssh_test)
  if vim.v.shell_error == 0 then
    vim.notify("✅ Conexión SSH exitosa", vim.log.levels.INFO)
  else
    vim.notify("❌ Conexión SSH fallida: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Verificar si gdbserver está instalado
  vim.notify("📦 Verificando gdbserver...", vim.log.levels.INFO)
  local gdb_check = build_ssh_command("which gdbserver")
  local gdb_path = vim.fn.system(gdb_check)
  if vim.v.shell_error == 0 then
    vim.notify("✅ Gdbserver encontrado en: " .. vim.trim(gdb_path), vim.log.levels.INFO)
  else
    vim.notify("❌ Gdbserver NO instalado en el host remoto", vim.log.levels.ERROR)
    vim.notify("💡 Instala con: ssh root@" .. host .. " 'apt-get install gdbserver'", vim.log.levels.INFO)
  end

  -- Verificar si hay procesos gdbserver corriendo
  vim.notify("🔍 Buscando procesos gdbserver...", vim.log.levels.INFO)
  local ps_check = build_ssh_command("ps aux | grep gdbserver | grep -v grep")
  local ps_result = vim.fn.system(ps_check)
  if vim.v.shell_error == 0 and ps_result ~= "" then
    vim.notify("⚙️  Procesos gdbserver activos:", vim.log.levels.INFO)
    for line in ps_result:gmatch("[^\r\n]+") do
      vim.notify("   " .. line, vim.log.levels.INFO)
    end
  else
    vim.notify("ℹ️  No hay procesos gdbserver corriendo", vim.log.levels.INFO)
  end

  -- Verificar puertos en escucha
  vim.notify("🔌 Verificando puertos en escucha...", vim.log.levels.INFO)
  local port_check = build_ssh_command("ss -tuln | grep LISTEN")
  local ports = vim.fn.system(port_check)
  if ports:find(":" .. gdb_port) then
    vim.notify("✅ Puerto " .. gdb_port .. " está en escucha", vim.log.levels.INFO)
  else
    vim.notify("ℹ️  Puerto " .. gdb_port .. " NO está en escucha", vim.log.levels.INFO)
  end

  vim.notify("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
  vim.notify("✅ Diagnóstico completado", vim.log.levels.INFO)
end, { desc = "Diagnóstico de debugging remoto" })

return {}
