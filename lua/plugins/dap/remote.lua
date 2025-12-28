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

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local REMOTE_OUTPUT_BUFFER_NAME = "Remote Debug Output"
local DEFAULT_SSH_PORT = "2222"
local DEFAULT_GDB_PORT = "10000"
local DEFAULT_WAIT_TIME = 3000

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

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
      return nil, "CMakeCache.txt not found."
    end
    buf = vim.fn.bufadd(cache_path)
    vim.fn.bufload(buf)
  end

  if not buf then
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
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
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
  local out = vim.fn.systemlist(ssh_cmd)
  local code = vim.v.shell_error
  return code, table.concat(out, "\n")
end

local function scp_upload(local_path, remote_path)
  local host = os.getenv("REMOTE_SSH_HOST")
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
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

-- ============================================================================
-- BUFFER MANAGEMENT
-- ============================================================================

local BufferManager = {}

function BufferManager.find_by_name(name_pattern)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name:match(name_pattern) then
        return buf
      end
    end
  end
  return nil
end

function BufferManager.find_window_for_buffer(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
  return nil
end

function BufferManager.create_output_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, REMOTE_OUTPUT_BUFFER_NAME)
  vim.api.nvim_buf_set_option(buf, "filetype", "log")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  return buf
end

function BufferManager.open_in_split(buf)
  vim.cmd("botright 15split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.cmd("wincmd p")
  return win
end

function BufferManager.get_or_create_output_buffer()
  local buf = BufferManager.find_by_name(REMOTE_OUTPUT_BUFFER_NAME)

  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = BufferManager.create_output_buffer()
  end

  local win = BufferManager.find_window_for_buffer(buf)

  if not win then
    win = BufferManager.open_in_split(buf)
    _G.dap_remote_output_win = win
    vim.notify("📋 Buffer de output remoto abierto en split inferior", vim.log.levels.INFO)
  else
    _G.dap_remote_output_win = win
  end

  return buf
end

function BufferManager.append_line(buf, message, is_error)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  pcall(function()
    local last_line = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_option(buf, "modifiable", true)

    local timestamp = os.date("%H:%M:%S")
    local prefix = is_error and "🚨 [ERR] " or "📤 [OUT] "
    local formatted_msg = string.format("[%s] %s%s", timestamp, prefix, message)

    vim.api.nvim_buf_set_lines(buf, last_line, last_line, false, { formatted_msg })
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    -- Auto-scroll
    local win = BufferManager.find_window_for_buffer(buf)
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { last_line + 1, 0 })
    end
  end)

  return true
end

_G.close_remote_output_window = function()
  local buf = BufferManager.find_by_name(REMOTE_OUTPUT_BUFFER_NAME)
  if buf then
    local win = BufferManager.find_window_for_buffer(buf)
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, false)
      _G.dap_remote_output_win = nil
      return true
    end
  end
  return false
end

-- ============================================================================
-- CMAKE INSTALL PATHS PARSING
-- ============================================================================

-- Extrae la ruta de instalación de un target desde un CMakeLists.txt
local function get_install_destination(cmake_file, target_pattern)
  if vim.fn.filereadable(cmake_file) ~= 1 then
    return nil
  end

  local content = table.concat(vim.fn.readfile(cmake_file), "\n")
  -- Buscar: install(TARGETS ... DESTINATION /path/to/dest)
  local pattern = "install%s*%(.-TARGETS%s+" .. (target_pattern or "[%w_%-]+") .. ".-DESTINATION%s+([%S]+)%s*%)"
  local destination = content:match(pattern)

  return destination
end

-- Obtiene la ruta de instalación del ejecutable principal
local function get_executable_install_path()
  local source_dir = get_cmake_cache_var("CMAKE_SOURCE_DIR")
  if not source_dir then
    return "/usr/bin" -- Fallback si no se encuentra
  end

  local manager_cmake = source_dir .. "/manager/CMakeLists.txt"
  local install_path = get_install_destination(manager_cmake, "${PROJECT_NAME}")

  return install_path or "/usr/bin"
end

-- Obtiene la ruta de instalación de los plugins .so
local function get_plugin_install_path()
  local source_dir = get_cmake_cache_var("CMAKE_SOURCE_DIR")
  if not source_dir then
    return "/usr/lib/zone/zovideo/" -- Fallback si no se encuentra
  end

  -- Buscar en todos los plugins
  local plugins_dir = source_dir .. "/plugins"
  local plugin_dirs = vim.fn.globpath(plugins_dir, "*", false, true)

  for _, plugin_dir in ipairs(plugin_dirs) do
    if vim.fn.isdirectory(plugin_dir) == 1 then
      local plugin_cmake = plugin_dir .. "/CMakeLists.txt"
      local install_path = get_install_destination(plugin_cmake)
      if install_path then
        -- Asegurar que termina con /
        if not install_path:match("/$") then
          install_path = install_path .. "/"
        end
        return install_path
      end
    end
  end

  return "/usr/lib/zone/zovideo/" -- Fallback
end

-- ============================================================================
-- GDB CONFIGURATION
-- ============================================================================

local function get_gdb_setup_commands()
  return {
    { text = "set sysroot remote:/" }, -- Buscar librerías en el sistema remoto
    { text = "-enable-pretty-printing" },
    { text = "set pagination off" },
    { text = "set print pretty on" },
    { text = "set target-async on" },
    { text = "set breakpoint pending on" },
    { text = "set print inferior-events off" },
    { text = "set auto-solib-add on" },
    { text = "set stop-on-solib-events 0" },
  }
end

local function create_base_dap_config()
  local toolchain_path = os.getenv("OECORE_TARGET_SYSROOT")
  local pretty_printer_path = toolchain_path and (toolchain_path .. "/usr/lib/cmake/ZOne/tools/gdb") or ""

  local config = {
    name = "REMOTE DEBUG",
    type = "cppdbg",
    request = "launch",
    program = os.getenv("LOCAL_PROGRAM_PATH") or "/bin/true",
    MIMode = "gdb",
    miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
    miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST") or "")
      .. ":"
      .. (os.getenv("REMOTE_GDBSERVER_PORT") or DEFAULT_GDB_PORT),
    cwd = "/",
    stopAtEntry = false,
    console = "internalConsole",
    setupCommands = get_gdb_setup_commands(),
    logging = { engineLogging = true },
  }

  if pretty_printer_path ~= "" then
    table.insert(config.setupCommands, { text = "set auto-load safe-path /", ignoreFailures = true })
    table.insert(config.setupCommands, { text = "set auto-load yes", ignoreFailures = true })
    table.insert(config.setupCommands, { text = "python sys.path.insert(0, '" .. pretty_printer_path .. "')" })
    table.insert(
      config.setupCommands,
      { text = "python import zo_pretty_printers; zo_pretty_printers.register_printers(gdb.current_objfile())" }
    )
  end

  return config
end

local function ensure_remote_base_config()
  for _, c in ipairs(dap.configurations.cpp) do
    if c.name == "REMOTE DEBUG" then
      return
    end
  end
  table.insert(dap.configurations.cpp, create_base_dap_config())
end

-- ============================================================================
-- REMOTE PROGRAM DEPLOYMENT
-- ============================================================================

local function ensure_remote_program()
  local lpath = os.getenv("LOCAL_PROGRAM_PATH")
  if not lpath or vim.fn.filereadable(lpath) ~= 1 then
    return nil, "LOCAL_PROGRAM_PATH no existe o no es legible"
  end

  -- Usar ruta de instalación desde CMakeLists.txt
  local exe_install_path = get_executable_install_path()
  -- Asegurar que termina con /
  if not exe_install_path:match("/$") then
    exe_install_path = exe_install_path .. "/"
  end

  local base = path_basename(lpath)
  local target = exe_install_path .. base

  vim.notify(string.format("📦 Ruta ejecutable detectada: %s", exe_install_path), vim.log.levels.INFO)

  -- Crear directorio si no existe
  local exists_code = select(1, run_remote(string.format("test -d %s", shell_quote(exe_install_path))))
  if exists_code ~= 0 then
    local mk_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(exe_install_path))))
    if mk_code ~= 0 then
      return nil, "No se pudo crear " .. exe_install_path
    end
  end

  -- Upload ejecutable principal y hacer ejecutable
  vim.notify(string.format("📦 Subiendo ejecutable: %s -> %s", base, target), vim.log.levels.INFO)
  local scp_code, scp_out = scp_upload(lpath, target)
  if scp_code ~= 0 then
    return nil, "SCP falló: " .. scp_out
  end

  local ch_code = select(1, run_remote(string.format("chmod +x %s", shell_quote(target))))
  if ch_code ~= 0 then
    return nil, "chmod +x falló en el target"
  end
  vim.notify(string.format("✅ Ejecutable desplegado: %s", target), vim.log.levels.INFO)

  -- Subir también los plugins .so del directorio de build
  -- Obtener el directorio raíz del build (donde está CMakeCache.txt)
  local cmake_cache_path = vim.fn.findfile("CMakeCache.txt", lpath .. ";")
  local build_dir = nil

  if cmake_cache_path ~= "" then
    build_dir = vim.fn.fnamemodify(cmake_cache_path, ":h")
  else
    -- Fallback: usar CMAKE_HOME_DIRECTORY + /out/Debug
    local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
    if source_dir then
      build_dir = source_dir .. "/out/Debug"
    else
      -- Último fallback: dos niveles arriba del ejecutable
      build_dir = vim.fn.fnamemodify(lpath, ":h:h")
    end
  end

  vim.notify(string.format("🔍 Buscando plugins en: %s/plugins", build_dir), vim.log.levels.INFO)

  local so_files = vim.fn.globpath(build_dir .. "/plugins", "**/*.so", false, true)
  vim.notify(string.format("🔍 Encontrados %d archivo(s) .so", #so_files), vim.log.levels.INFO)

  if #so_files > 0 then
    -- Obtener ruta de instalación de plugins desde CMakeLists.txt
    local plugin_path = get_plugin_install_path()
    vim.notify(string.format("📦 Ruta de plugins detectada: %s", plugin_path), vim.log.levels.INFO)

    -- Crear directorio de plugins si no existe
    local mk_plugin_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(plugin_path))))
    if mk_plugin_code ~= 0 then
      vim.notify("⚠️  No se pudo crear directorio de plugins", vim.log.levels.WARN)
    end

    vim.notify(string.format("📦 Subiendo %d plugin(s) .so...", #so_files), vim.log.levels.INFO)
    for _, so_file in ipairs(so_files) do
      local so_name = path_basename(so_file)
      local remote_so = plugin_path .. so_name
      local so_scp_code, so_scp_out = scp_upload(so_file, remote_so)
      if so_scp_code ~= 0 then
        vim.notify(string.format("⚠️  Falló subir %s: %s", so_name, so_scp_out), vim.log.levels.WARN)
      else
        vim.notify(string.format("✓ Subido: %s", so_name), vim.log.levels.INFO)
      end
    end
  end

  return target, nil
end

-- ============================================================================
-- GDBSERVER MANAGEMENT
-- ============================================================================

local function create_gdbserver_script(script_file, gdb_port, rprog, args)
  -- Obtener ruta de plugins desde CMakeLists.txt y configurar LD_LIBRARY_PATH
  local plugin_path = get_plugin_install_path()
  -- Remover trailing slash si existe (LD_LIBRARY_PATH no lo necesita)
  plugin_path = plugin_path:gsub("/$", "")

  -- Usar 'env' en lugar de 'export' porque stdbuf solo puede ejecutar comandos externos
  local gdb_command = string.format(
    "env LD_LIBRARY_PATH=%s:$LD_LIBRARY_PATH gdbserver :%s %s %s",
    plugin_path,
    gdb_port,
    rprog,
    table.concat(args, " ")
  )
  local create_script = string.format(
    "cat > %s << 'EOFSCRIPT'\n#!/bin/bash\nstdbuf -oL -eL %s\nEOFSCRIPT\nchmod +x %s",
    shell_quote(script_file),
    gdb_command,
    shell_quote(script_file)
  )

  local create_cmd = build_ssh_command(create_script)
  local result = vim.fn.system(create_cmd)

  if vim.v.shell_error ~= 0 then
    return nil, "Error preparando script: " .. result
  end

  return gdb_command
end

local function start_gdbserver(script_file, output_file, gdb_port)
  -- BusyBox compatible: ps sin opciones, PID está en columna 1
  local kill_cmd = string.format(
    "ps | grep 'gdbserver :%s' | grep -v grep | awk '{print $1}' | xargs kill -9 2>/dev/null || true",
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
    return nil, "Error construyendo comando SSH"
  end

  local result = vim.fn.system(ssh_cmd)
  local gdbserver_pid = vim.trim(result)

  if vim.v.shell_error ~= 0 or gdbserver_pid == "" then
    return nil, "Error al iniciar gdbserver"
  end

  return gdbserver_pid
end

local function verify_gdbserver(gdb_port, output_file)
  -- Verificar proceso (BusyBox compatible)
  local check_cmd = build_ssh_command("ps | grep 'gdbserver :" .. gdb_port .. "' | grep -v grep")
  local check_result = vim.fn.system(check_cmd)

  if vim.v.shell_error ~= 0 or check_result == "" then
    vim.notify("⚠️  Gdbserver no está corriendo en el host remoto", vim.log.levels.WARN)

    -- Leer output file para ver errores
    local error_check = build_ssh_command("cat " .. shell_quote(output_file) .. " 2>/dev/null | head -20")
    local error_output = vim.fn.system(error_check)
    if error_output ~= "" then
      vim.notify("📄 Output de gdbserver:\n" .. error_output, vim.log.levels.WARN)
    end
    return false
  end

  vim.notify("✅ Gdbserver está corriendo", vim.log.levels.INFO)

  -- Verificar puerto
  local port_check =
    build_ssh_command("(ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null) | grep ':" .. gdb_port .. "'")
  local port_result = vim.fn.system(port_check)

  if vim.v.shell_error ~= 0 or not port_result:match(gdb_port) then
    vim.notify("⚠️  Puerto " .. gdb_port .. " puede no estar escuchando aún", vim.log.levels.WARN)
    vim.notify("💡 Esto es normal - gdbserver espera la primera conexión para abrir el puerto", vim.log.levels.INFO)
  else
    vim.notify("✅ Puerto " .. gdb_port .. " está escuchando", vim.log.levels.INFO)
  end

  return true
end

-- ============================================================================
-- OUTPUT MONITORING
-- ============================================================================

local OutputMonitor = {}
OutputMonitor.active = false
OutputMonitor.job_id = nil
OutputMonitor.buffer = nil
OutputMonitor.buffer_initialized = false

function OutputMonitor.setup(output_file)
  OutputMonitor.active = true
  _G.dapui_monitoring_active = true

  -- Crear buffer de output
  if not OutputMonitor.buffer_initialized then
    OutputMonitor.buffer = BufferManager.get_or_create_output_buffer()
    OutputMonitor.buffer_initialized = true
  end

  if os.getenv("DAP_MONITOR_ENABLED") == "false" then
    vim.notify("ℹ️  Monitoreo remoto deshabilitado", vim.log.levels.INFO)
    return
  end

  -- Asegurar que la ventana esté abierta
  BufferManager.get_or_create_output_buffer()

  -- Iniciar streaming con tail -f
  local tail_cmd = build_ssh_command("tail -f -n 0 " .. shell_quote(output_file) .. " 2>/dev/null")
  vim.notify("🔍 Iniciando streaming de salida remota...", vim.log.levels.INFO)

  OutputMonitor.job_id = vim.fn.jobstart(tail_cmd, {
    on_stdout = function(_, lines)
      if not OutputMonitor.active then
        return
      end

      vim.schedule(function()
        for _, line in ipairs(lines) do
          if line ~= "" and not line:match("^Remote debugging") and not line:match("^Process .* created") then
            local is_error = line:match("[Ee]rror") or line:match("[Ww]arning") or line:match("FAIL")
            BufferManager.append_line(OutputMonitor.buffer, line, is_error)
          end
        end
      end)
    end,
    on_stderr = function(_, lines)
      vim.schedule(function()
        for _, line in ipairs(lines) do
          if line ~= "" then
            vim.notify("SSH/tail error: " .. line, vim.log.levels.WARN)
          end
        end
      end)
    end,
    on_exit = function(_, code)
      if code ~= 0 and OutputMonitor.active then
        vim.notify("⚠️  Streaming de salida terminó (código: " .. code .. ")", vim.log.levels.WARN)
      end
      OutputMonitor.job_id = nil
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  _G.dapui_monitor_job = OutputMonitor.job_id

  -- Mensajes iniciales
  vim.defer_fn(function()
    BufferManager.append_line(OutputMonitor.buffer, "🎯 Streaming remoto iniciado (sin polling)", false)
    BufferManager.append_line(OutputMonitor.buffer, "📁 Archivo: " .. output_file, false)
    BufferManager.append_line(OutputMonitor.buffer, "⚡ Modo: tail -f (tiempo real)", false)
  end, 500)
end

function OutputMonitor.cleanup()
  if not OutputMonitor.active then
    return
  end

  OutputMonitor.active = false
  _G.dapui_monitoring_active = false

  if OutputMonitor.job_id then
    pcall(vim.fn.jobstop, OutputMonitor.job_id)
    OutputMonitor.job_id = nil
    _G.dapui_monitor_job = nil
  end

  if OutputMonitor.buffer and vim.api.nvim_buf_is_valid(OutputMonitor.buffer) then
    BufferManager.append_line(OutputMonitor.buffer, "🛑 Streaming remoto finalizado", false)
  end

  _G.close_remote_output_window()

  OutputMonitor.buffer_initialized = false
end

-- ============================================================================
-- MAIN DEBUG FUNCTION
-- ============================================================================

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
  -- Cargar variables de CMake
  vim.env.SSHPASS = get_cmake_cache_var("REMOTE_SSH_PASS")
  vim.env.REMOTE_SSH_HOST = get_cmake_cache_var("REMOTE_SSH_HOST")

  for _, var in ipairs({ "SSHPASS", "REMOTE_SSH_HOST" }) do
    if not os.getenv(var) then
      return vim.notify("❌ Variable de entorno no definida: " .. var, vim.log.levels.ERROR)
    end
  end

  -- Solicitar argumentos
  vim.ui.input({ prompt = "Argumentos de ejecución:", default = "" }, function(input_args)
    if input_args == nil then
      return vim.notify("❌ Depuración cancelada", vim.log.levels.WARN)
    end

    local args = {}
    if input_args ~= "" then
      args = vim.split(input_args, "%s+", { trimempty = true })
    end

    -- Resolver ejecutable
    local project_name = get_cmake_cache_var("CMAKE_PROJECT_NAME")
    local cmake_key = string.format("%s_BINARY_DIR", project_name)
    local default_exec = get_cmake_cache_var(cmake_key) or ""
    default_exec = string.format("%s/%s", default_exec, project_name)

    resolve_program_or_prompt("LOCAL_PROGRAM_PATH", default_exec, function(local_prog)
      local rprog, err = ensure_remote_program()
      if not rprog then
        return vim.notify("❌ " .. err, vim.log.levels.ERROR)
      end

      -- Crear configuración DAP
      local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or DEFAULT_GDB_PORT
      local target = vim.deepcopy(create_base_dap_config())

      target.args = args
      target.program = local_prog
      target.miDebuggerPath = os.getenv("GDB")
      target.miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST")) .. ":" .. gdb_port
      target.console = "integratedTerminal"
      target.externalConsole = true
      -- setupCommands ya vienen de create_base_dap_config() con todos los comandos necesarios
      target.logging = { engineLogging = true, trace = true }

      -- Preparar archivos remotos
      local output_base = "/tmp/" .. path_basename(rprog)
      local output_file = output_base .. ".output"
      local script_file = output_base .. ".sh"

      -- Crear script de gdbserver
      vim.notify("📝 Preparando gdbserver remoto...", vim.log.levels.INFO)
      local gdb_command, create_err = create_gdbserver_script(script_file, gdb_port, rprog, args)
      if not gdb_command then
        return vim.notify("❌ " .. create_err, vim.log.levels.ERROR)
      end

      -- Iniciar gdbserver
      vim.notify("🚀 Iniciando gdbserver remoto...", vim.log.levels.INFO)
      vim.notify("📋 Comando: " .. gdb_command, vim.log.levels.DEBUG)

      local gdbserver_pid, start_err = start_gdbserver(script_file, output_file, gdb_port)
      if not gdbserver_pid then
        vim.notify("❌ " .. start_err, vim.log.levels.ERROR)
        vim.notify("💡 Ejecuta :DapRemoteDiagnostic para más información", vim.log.levels.INFO)
        return
      end

      vim.notify("✅ Gdbserver iniciado (PID: " .. gdbserver_pid .. ")", vim.log.levels.INFO)
      vim.notify("📁 Output: " .. output_file, vim.log.levels.DEBUG)

      -- Esperar a que gdbserver esté listo
      local wait_ms = tonumber(os.getenv("DEBUG_WAIT_TIME")) or DEFAULT_WAIT_TIME
      vim.notify("⏳ Esperando " .. (wait_ms / 1000) .. " s para que gdbserver escuche...", vim.log.levels.WARN)

      vim.defer_fn(function()
        verify_gdbserver(gdb_port, output_file)
        vim.notify("🛰️ Conectando depurador...", vim.log.levels.INFO)
        vim.notify(
          "ℹ️  Si ves 'Cursor position outside buffer', recompila el ejecutable con símbolos de debug (-g)",
          vim.log.levels.INFO
        )

        -- Configurar monitoreo de output
        OutputMonitor.setup(output_file)

        -- Registrar cleanup
        dap.listeners.before.event_terminated["dapui_monitor"] = OutputMonitor.cleanup
        dap.listeners.before.event_exited["dapui_monitor"] = OutputMonitor.cleanup
        dap.listeners.before.disconnect["dapui_monitor"] = OutputMonitor.cleanup

        -- Iniciar DAP
        dap.run(target)
      end, wait_ms)
    end)
  end)
end

-- ============================================================================
-- UI UTILITIES
-- ============================================================================

local function is_dapui_open()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        if ft:match("^dapui_") or ft == "dap-repl" then
          return true
        end
      end
    end
  end
  return false
end

-- ============================================================================
-- DAP ADAPTER CONFIGURATION
-- ============================================================================

dap.configurations.c = dap.configurations.c
dap.configurations.cpp = dap.configurations.cpp

dap.adapters.cppdbg = {
  id = "cppdbg",
  type = "executable",
  command = vim.fn.stdpath("data") .. "/mason/packages/cpptools/extension/debugAdapters/bin/OpenDebugAD7",
  options = { detached = false },
}

-- ============================================================================
-- COMMANDS AND KEYMAPS
-- ============================================================================

-- Main debug command
vim.keymap.set("n", "<leader>dR", _G.dap_remote_debug, { desc = "Debug Remote (con Argumentos)" })

-- Show output buffer
vim.api.nvim_create_user_command("DapShowOutput", function()
  local buf = BufferManager.find_by_name(REMOTE_OUTPUT_BUFFER_NAME)

  if not buf then
    vim.notify("⚠️  No hay buffer de output remoto. Inicia un debug remoto primero.", vim.log.levels.WARN)
    return
  end

  local win = BufferManager.find_window_for_buffer(buf)

  if win then
    vim.api.nvim_set_current_win(win)
    vim.notify("📋 Ventana de output enfocada", vim.log.levels.INFO)
  else
    BufferManager.open_in_split(buf)
    vim.notify("✅ Buffer de output abierto", vim.log.levels.INFO)
  end
end, { desc = "Abrir buffer de output remoto" })

vim.keymap.set("n", "<leader>do", ":DapShowOutput<CR>", { desc = "Show Remote Debug Output" })

-- Toggle DAP-UI
vim.api.nvim_create_user_command("DapUIToggle", function()
  local dapui = require("dapui")
  local was_open = is_dapui_open()

  dapui.toggle()

  if was_open then
    vim.defer_fn(_G.close_remote_output_window, 100)
  end
end, { desc = "Toggle DAP UI" })

vim.keymap.set("n", "<leader>du", ":DapUIToggle<CR>", { desc = "Toggle DAP UI" })

-- Monitor control commands
vim.api.nvim_create_user_command("DapCleanupMonitor", function()
  if OutputMonitor.active then
    OutputMonitor.cleanup()
    vim.notify("✅ Streaming de monitoreo detenido", vim.log.levels.INFO)
  else
    vim.notify("ℹ️  No hay streaming activo", vim.log.levels.INFO)
  end
end, { desc = "Detener streaming de monitoreo remoto" })

vim.api.nvim_create_user_command("DapMonitorStatus", function()
  if OutputMonitor.active then
    local job_status = OutputMonitor.job_id and "Activo (streaming)" or "Inactivo"
    vim.notify(
      string.format("🔍 Monitor: %s | Job ID: %s", job_status, tostring(OutputMonitor.job_id or "N/A")),
      vim.log.levels.INFO
    )
  else
    vim.notify("ℹ️  Monitoreo inactivo", vim.log.levels.INFO)
  end
end, { desc = "Estado del monitoreo remoto" })

vim.keymap.set("n", "<leader>dC", ":DapCleanupMonitor<CR>", { desc = "Cleanup Debug Monitor" })
vim.keymap.set("n", "<leader>dM", ":DapMonitorStatus<CR>", { desc = "Monitor Status" })

-- ============================================================================
-- PUBLIC DEPLOY FUNCTION
-- ============================================================================

function _G.deploy_remote_program()
  -- Cargar variables desde CMakeCache.txt
  vim.env.SSHPASS = get_cmake_cache_var("REMOTE_SSH_PASS")
  vim.env.REMOTE_SSH_HOST = get_cmake_cache_var("REMOTE_SSH_HOST")

  -- Verificar variables obligatorias
  for _, var in ipairs({ "SSHPASS", "REMOTE_SSH_HOST" }) do
    if not os.getenv(var) then
      return vim.notify("❌ Variable de entorno no definida: " .. var, vim.log.levels.ERROR)
    end
  end

  -- Resolver ejecutable
  local project_name = get_cmake_cache_var("CMAKE_PROJECT_NAME")
  local cmake_key = string.format("%s_BINARY_DIR", project_name)
  local default_exec = get_cmake_cache_var(cmake_key) or ""
  default_exec = string.format("%s/%s", default_exec, project_name)

  resolve_program_or_prompt("LOCAL_PROGRAM_PATH", default_exec, function(local_prog)
    vim.notify("🚀 Iniciando deploy remoto...", vim.log.levels.INFO)
    vim.notify("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

    local rprog, err = ensure_remote_program()
    if not rprog then
      return vim.notify("❌ " .. err, vim.log.levels.ERROR)
    end

    vim.notify("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
    vim.notify("✅ Deploy completado exitosamente", vim.log.levels.INFO)
  end)
end

-- Show GDB setup commands
vim.api.nvim_create_user_command("DapShowGdbCommands", function()
  vim.notify("🔧 Comandos GDB que se ejecutarán:", vim.log.levels.INFO)
  local commands = get_gdb_setup_commands()
  for i, cmd in ipairs(commands) do
    vim.notify(string.format("  %d. %s", i, cmd.text), vim.log.levels.INFO)
  end

  local toolchain_path = os.getenv("OECORE_TARGET_SYSROOT")
  if toolchain_path and toolchain_path ~= "" then
    vim.notify("", vim.log.levels.INFO)
    vim.notify("📚 Pretty printers detectados:", vim.log.levels.INFO)
    vim.notify("  - set auto-load safe-path /", vim.log.levels.INFO)
    vim.notify("  - set auto-load yes", vim.log.levels.INFO)
    vim.notify(
      "  - python sys.path.insert(0, '" .. toolchain_path .. "/usr/lib/cmake/ZOne/tools/gdb')",
      vim.log.levels.INFO
    )
    vim.notify("  - python import zo_pretty_printers...", vim.log.levels.INFO)
  else
    vim.notify("", vim.log.levels.INFO)
    vim.notify("⚠️  No se detectó OECORE_TARGET_SYSROOT, pretty printers no disponibles", vim.log.levels.WARN)
  end
end, { desc = "Mostrar comandos GDB que se ejecutarán" })

-- Diagnostic command
vim.api.nvim_create_user_command("DapRemoteDiagnostic", function()
  -- Cargar variables desde CMakeCache.txt (como lo hace dap_remote_debug)
  vim.env.SSHPASS = get_cmake_cache_var("REMOTE_SSH_PASS")
  vim.env.REMOTE_SSH_HOST = get_cmake_cache_var("REMOTE_SSH_HOST")
  vim.env.REMOTE_SSH_PORT = get_cmake_cache_var("REMOTE_SSH_PORT")
  vim.env.REMOTE_GDBSERVER_PORT = get_cmake_cache_var("REMOTE_GDBSERVER_PORT")
  vim.env.LOCAL_GDB_PATH = os.getenv("GDB")

  local host = os.getenv("REMOTE_SSH_HOST")
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
  local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or DEFAULT_GDB_PORT

  vim.notify("🔍 Diagnóstico de Debugging Remoto", vim.log.levels.INFO)
  vim.notify(
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    vim.log.levels.INFO
  )

  -- Mostrar fuente de configuración
  local cmake_cache = get_cmake_cache_var("CMAKE_CACHEFILE_DIR")
  if cmake_cache then
    vim.notify(string.format("📋 Configuración desde: %s/CMakeCache.txt", cmake_cache), vim.log.levels.INFO)
  else
    vim.notify("⚠️  No se encontró CMakeCache.txt", vim.log.levels.WARN)
  end
  vim.notify("", vim.log.levels.INFO)

  -- Verificar variables
  local vars =
    { "REMOTE_SSH_HOST", "REMOTE_SSH_PORT", "SSHPASS", "LOCAL_PROGRAM_PATH", "LOCAL_GDB_PATH", "REMOTE_GDBSERVER_PORT" }
  for _, var in ipairs(vars) do
    local value = os.getenv(var)
    if value then
      local display = var == "SSHPASS" and "***" or value
      vim.notify("✅ " .. var .. ": " .. display, vim.log.levels.INFO)
    else
      vim.notify("❌ " .. var .. ": NO DEFINIDA", vim.log.levels.WARN)
    end
  end

  if not host then
    vim.notify("❌ REMOTE_SSH_HOST no definida. No se pueden hacer más verificaciones.", vim.log.levels.ERROR)
    return
  end

  vim.notify(
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    vim.log.levels.INFO
  )

  -- Conectividad SSH
  vim.notify("🔌 Verificando conectividad SSH...", vim.log.levels.INFO)
  local ssh_test = build_ssh_command("echo 'OK'")
  local result = vim.fn.system(ssh_test)
  if vim.v.shell_error == 0 then
    vim.notify("✅ Conexión SSH exitosa", vim.log.levels.INFO)
  else
    vim.notify("❌ Conexión SSH fallida: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Rutas de instalación detectadas desde CMakeLists.txt
  vim.notify("📂 Rutas de instalación detectadas:", vim.log.levels.INFO)
  local exe_install_path = get_executable_install_path()
  local plugin_install_path = get_plugin_install_path()
  vim.notify(string.format("   Ejecutable: %s", exe_install_path), vim.log.levels.INFO)
  vim.notify(string.format("   Plugins:    %s", plugin_install_path), vim.log.levels.INFO)

  local deploy_path = get_cmake_cache_var("DEPLOY_REMOTE_PATH")
  if deploy_path then
    vim.notify(string.format("   Deploy:     %s", deploy_path), vim.log.levels.INFO)
    if deploy_path == "/usr/bin/" or deploy_path == exe_install_path then
      vim.notify("   ⚠️  DEPLOY_REMOTE_PATH debería ser temporal (/tmp/), no la ruta de instalación", vim.log.levels.WARN)
    end
  end

  -- Verificar gdbserver
  vim.notify("📦 Verificando gdbserver...", vim.log.levels.INFO)
  local gdb_check = build_ssh_command("which gdbserver")
  local gdb_path = vim.fn.system(gdb_check)
  if vim.v.shell_error == 0 then
    vim.notify("✅ Gdbserver encontrado en: " .. vim.trim(gdb_path), vim.log.levels.INFO)
  else
    vim.notify("❌ Gdbserver NO instalado en el host remoto", vim.log.levels.ERROR)
    vim.notify("💡 Instala con: ssh root@" .. host .. " 'apt-get install gdbserver'", vim.log.levels.INFO)
  end

  -- Procesos activos (BusyBox compatible)
  vim.notify("🔍 Buscando procesos gdbserver...", vim.log.levels.INFO)
  local ps_check = build_ssh_command("ps | grep gdbserver | grep -v grep")
  local ps_result = vim.fn.system(ps_check)
  if vim.v.shell_error == 0 and ps_result ~= "" then
    vim.notify("⚙️  Procesos gdbserver activos:", vim.log.levels.INFO)
    for line in ps_result:gmatch("[^\r\n]+") do
      vim.notify("   " .. line, vim.log.levels.INFO)
    end
  else
    vim.notify("ℹ️  No hay procesos gdbserver corriendo", vim.log.levels.INFO)
  end

  -- Puertos en escucha
  vim.notify("🔌 Verificando puertos en escucha...", vim.log.levels.INFO)
  local port_check = build_ssh_command("ss -tuln | grep LISTEN")
  local ports = vim.fn.system(port_check)
  if ports:find(":" .. gdb_port) then
    vim.notify("✅ Puerto " .. gdb_port .. " está en escucha", vim.log.levels.INFO)
  else
    vim.notify("ℹ️  Puerto " .. gdb_port .. " NO está en escucha", vim.log.levels.INFO)
  end

  vim.notify(
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
    vim.log.levels.INFO
  )
  vim.notify("✅ Diagnóstico completado", vim.log.levels.INFO)
end, { desc = "Diagnóstico de debugging remoto" })

return {}
