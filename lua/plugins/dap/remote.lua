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

-- SSH ControlMaster to reuse SSH connections and speed up deploys
local function get_ssh_control_options()
  local host = os.getenv("REMOTE_SSH_HOST") or "unknown"
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
  local control_path = string.format("/tmp/nvim-ssh-control-%s-%s", host, port)

  return string.format(
    "-o ControlMaster=auto -o ControlPath=%s -o ControlPersist=600",
    control_path
  )
end

-- Helper for logging before log_to_console is defined
local function debug_log(msg, level)
  level = level or vim.log.levels.INFO
  -- Try using log_to_console if available, otherwise use vim.notify only for errors
  if _G.log_to_console then
    _G.log_to_console(msg, level)
  else
    -- Only show notifications for errors and warnings
    if level == vim.log.levels.ERROR or level == vim.log.levels.WARN then
      vim.notify(msg, level)
    end
  end
end

local function get_cmake_cache_var(var_name)
  local function find_cache_buf()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("CMakeCache") then
        debug_log("📝 CMakeCache buffer already open: " .. name, vim.log.levels.INFO)
        return buf
      end
    end
    return nil
  end

  local buf = find_cache_buf()
  if not buf then
    -- Search for CMakeCache.txt from current project directory, not recursively in entire system
    local cwd = vim.fn.getcwd()
    debug_log("📂 Searching for CMakeCache.txt from: " .. cwd, vim.log.levels.INFO)

    local cache_path = vim.fn.findfile("CMakeCache.txt", cwd .. ";")  -- Busca en cwd y directorios padre

    if not cache_path or cache_path == "" then
      debug_log("⚠️  Not found in current or parent directory, searching in common subdirectories...", vim.log.levels.INFO)

      -- Segundo intento: buscar en subdirectorios comunes
      local common_paths = {
        cwd .. "/out/Debug/CMakeCache.txt",
        cwd .. "/out/Release/CMakeCache.txt",
        cwd .. "/out/device-Debug/CMakeCache.txt",
        cwd .. "/out/toolchain-Debug/CMakeCache.txt",
        cwd .. "/build/CMakeCache.txt",
        cwd .. "/CMakeCache.txt",
      }

      for _, path in ipairs(common_paths) do
        debug_log("   Probando: " .. path, vim.log.levels.INFO)
        if vim.fn.filereadable(path) == 1 then
          cache_path = path
          debug_log("   ✅ Encontrado en: " .. path, vim.log.levels.INFO)
          break
        end
      end
    else
      debug_log("✅ CMakeCache.txt found: " .. cache_path, vim.log.levels.INFO)
    end

    if not cache_path or cache_path == "" then
      debug_log("❌ CMakeCache.txt NOT found in: " .. cwd, vim.log.levels.ERROR)
      return nil, "CMakeCache.txt not found in project directory: " .. cwd
    end

    buf = vim.fn.bufadd(cache_path)
    vim.fn.bufload(buf)
  end

  if not buf then
    debug_log("❌ Could not open CMakeCache.txt buffer", vim.log.levels.ERROR)
    return nil, "Failed to open CMakeCache buffer."
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Debug: show which file is being read
  local cache_file = vim.api.nvim_buf_get_name(buf)
  if cache_file and cache_file ~= "" then
    debug_log("🔍 Searching for " .. var_name .. " en: " .. cache_file, vim.log.levels.INFO)
  end

  -- Debug: show some lines containing the searched variable
  local matching_lines = {}
  for _, line in ipairs(lines) do
    if line:match(var_name) then
      table.insert(matching_lines, line)
    end
  end

  if #matching_lines > 0 then
    debug_log("📋 Líneas que contienen '" .. var_name .. "':", vim.log.levels.INFO)
    for _, line in ipairs(matching_lines) do
      debug_log("   " .. line, vim.log.levels.INFO)
    end
  end

  for _, line in ipairs(lines) do
    -- El formato de CMakeCache.txt es: VARIABLE:TYPE=value
    -- donde TYPE puede ser: UNINITIALIZED, STRING, FILEPATH, PATH, BOOL, INTERNAL, etc.
    local var, var_type, value = line:match("^([%w_]+):([%w_]+)=(.+)$")
    if var == var_name then
      -- Debug: show the found variable
      debug_log(string.format("✅ Found %s:%s=%s", var_name, var_type, value), vim.log.levels.INFO)
      return value
    end
  end

  -- Debug: show that it was not found
  debug_log(string.format("⚠️  Variable '%s' not found", var_name), vim.log.levels.WARN)
  return nil, "Variable '" .. var_name .. "' not found in CMakeCache."
end

local function build_ssh_command(cmd)
  local host = os.getenv("REMOTE_SSH_HOST")
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
  if not host then
    vim.notify("❌ REMOTE_SSH_HOST not defined", vim.log.levels.ERROR)
    return nil
  end
  local control_opts = get_ssh_control_options()
  return string.format(
    "sshpass -e ssh -p %s %s -o StrictHostKeyChecking=no root@%s %s",
    port,
    control_opts,
    host,
    shell_quote(cmd)
  )
end

-- ============================================================================
-- DAP UI CONSOLE LOGGING
-- ============================================================================

local deploy_log_buffer = nil
local deploy_log_window = nil

-- Función para escribir logs en la consola de DAP UI durante el deploy
_G.log_to_console = function(message, level)
  level = level or vim.log.levels.INFO

  -- Only show notifications for errors and warnings
  if level == vim.log.levels.ERROR or level == vim.log.levels.WARN then
    vim.notify(message, level)
  end

  -- Intentar escribir en la consola de DAP UI
  local ok, dapui = pcall(require, "dapui")
  if not ok then
    return
  end

  -- Si no hay buffer de log, crear uno
  if not deploy_log_buffer or not vim.api.nvim_buf_is_valid(deploy_log_buffer) then
    deploy_log_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(deploy_log_buffer, "DAP Deploy Logs")
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'swapfile', false)
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'filetype', 'dap-console')
  end

  -- Añadir el mensaje al buffer
  local lines = vim.split(message, "\n")
  local line_count = vim.api.nvim_buf_line_count(deploy_log_buffer)
  vim.api.nvim_buf_set_lines(deploy_log_buffer, line_count, line_count, false, lines)

  -- Si la ventana está abierta, hacer scroll al final
  if deploy_log_window and vim.api.nvim_win_is_valid(deploy_log_window) then
    vim.api.nvim_win_set_cursor(deploy_log_window, {vim.api.nvim_buf_line_count(deploy_log_buffer), 0})
  end
end

-- Función para abrir la ventana de logs de deploy
local function open_deploy_console()
  -- Verificar si la ventana ya está abierta
  if deploy_log_window and vim.api.nvim_win_is_valid(deploy_log_window) then
    -- La ventana ya existe, no crear otra
    -- Solo limpiar el buffer si es necesario
    if deploy_log_buffer and vim.api.nvim_buf_is_valid(deploy_log_buffer) then
      vim.api.nvim_buf_set_lines(deploy_log_buffer, 0, -1, false, {})
      -- Agregar header
      local header = {
        "═══════════════════════════════════════════════════════════",
        "   REMOTE DEPLOYMENT LOGS",
        "═══════════════════════════════════════════════════════════",
        ""
      }
      vim.api.nvim_buf_set_lines(deploy_log_buffer, 0, 0, false, header)
    end
    return
  end

  -- Crear buffer si no existe
  if deploy_log_buffer and vim.api.nvim_buf_is_valid(deploy_log_buffer) then
    -- Limpiar buffer anterior
    vim.api.nvim_buf_set_lines(deploy_log_buffer, 0, -1, false, {})
  else
    -- Crear nuevo buffer
    deploy_log_buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(deploy_log_buffer, "DAP Deploy Logs")
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'swapfile', false)
    vim.api.nvim_buf_set_option(deploy_log_buffer, 'filetype', 'dap-console')
  end

  -- Abrir ventana en la parte inferior (solo si no existe)
  vim.cmd('botright 15split')
  deploy_log_window = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(deploy_log_window, deploy_log_buffer)

  -- Configurar opciones de la ventana
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false

  -- Header
  local header = {
    "═══════════════════════════════════════════════════════════",
    "   REMOTE DEPLOYMENT LOGS",
    "═══════════════════════════════════════════════════════════",
    ""
  }
  vim.api.nvim_buf_set_lines(deploy_log_buffer, 0, 0, false, header)

  -- Volver a la ventana anterior
  vim.cmd('wincmd p')
end

-- Función global para cerrar la ventana de logs
_G.close_deploy_console = function()
  if deploy_log_window and vim.api.nvim_win_is_valid(deploy_log_window) then
    vim.api.nvim_win_close(deploy_log_window, true)
    deploy_log_window = nil
  end
end

-- Función para cerrar ventanas vacías (sin buffer válido o con buffer vacío sin nombre)
local function close_empty_windows()
  local closed_count = 0

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)

      -- No cerrar si es el buffer de Remote Debug Output
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if not buf_name:match(REMOTE_OUTPUT_BUFFER_NAME) then
        -- Verificar si es un buffer vacío sin nombre
        local is_empty = buf_name == "" or buf_name == "[No Name]"
        local line_count = vim.api.nvim_buf_line_count(buf)
        local first_line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""

        -- Cerrar si es un buffer vacío sin nombre y solo tiene una línea en blanco
        if is_empty and line_count == 1 and first_line == "" then
          -- Verificar que no sea la última ventana
          local total_windows = #vim.api.nvim_list_wins()
          if total_windows > 1 then
            pcall(vim.api.nvim_win_close, win, true)
            closed_count = closed_count + 1
          end
        end
      end
    end
  end

  if closed_count > 0 then
    log_to_console(string.format("🧹 Closed %d empty window(s)", closed_count), vim.log.levels.INFO)
  end
end

-- Function to close DAP Console window (dapui_console) but keep DAP REPL (dap-repl)
local function close_dap_console_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_is_valid(buf) then
        local ft = vim.api.nvim_buf_get_option(buf, "filetype")
        -- Close only dapui_console, NOT dap-repl
        if ft == "dapui_console" then
          pcall(vim.api.nvim_win_close, win, true)
          log_to_console("🧹 Closed DAP Console window (dapui_console)", vim.log.levels.INFO)
          return true
        end
      end
    end
  end
  return false
end

-- Synchronous version (kept for compatibility)
local function run_remote(cmd)
  local ssh_cmd = build_ssh_command(cmd)
  if not ssh_cmd then
    return 1, "Error building ssh command"
  end
  local out = vim.fn.systemlist(ssh_cmd)
  local code = vim.v.shell_error
  return code, table.concat(out, "\n")
end

-- Asynchronous version with callback
local function run_remote_async(cmd, callback)
  local ssh_cmd = build_ssh_command(cmd)
  if not ssh_cmd then
    callback(1, "Error building ssh command")
    return
  end

  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(ssh_cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
            log_to_console("  " .. line, vim.log.levels.DEBUG)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local output = table.concat(stdout_data, "\n")
      local err_output = table.concat(stderr_data, "\n")
      callback(exit_code, output, err_output)
    end,
  })
end

-- Synchronous version (kept for compatibility)
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

-- Asynchronous version with callback and progress
local function scp_upload_async(local_path, remote_path, callback)
  local host = os.getenv("REMOTE_SSH_HOST")
  local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
  if not host then
    callback(1, "REMOTE_SSH_HOST no definida")
    return
  end

  local control_opts = get_ssh_control_options()
  local scp_cmd = string.format(
    "sshpass -e scp -P %s %s -o StrictHostKeyChecking=no %s root@%s:%s",
    port,
    control_opts,
    shell_quote(local_path),
    host,
    shell_quote(remote_path)
  )

  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(scp_cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local output = table.concat(stdout_data, "\n")
      callback(exit_code, output)
    end,
  })
end

-- Asynchronous rsync with real-time output
local function rsync_async(source_dir, dest_dir, callback)
  local remote_port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
  local remote_host = os.getenv("REMOTE_SSH_HOST")
  local control_opts = get_ssh_control_options()

  local rsync_cmd = string.format(
    "rsync -avz -e 'sshpass -e ssh -p %s %s -o StrictHostKeyChecking=no' '%s/' root@%s:'%s/'",
    remote_port,
    control_opts,
    source_dir,
    remote_host,
    dest_dir
  )

  local stdout_data = {}
  local stderr_data = {}

  vim.fn.jobstart(rsync_cmd, {
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
            -- Show rsync progress in real-time
            if line:match("^sending") or line:match("^sent") or line:match("^total size") then
              log_to_console("    " .. line, vim.log.levels.DEBUG)
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
            log_to_console("    ⚠️  " .. line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      local output = table.concat(stdout_data, "\n")
      callback(exit_code, output)
    end,
  })
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
    vim.notify("📋 Remote output buffer opened in bottom split", vim.log.levels.INFO)
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

-- Gets the build directory (binaryDir) from CMakeCache.txt
local function get_binary_dir()
  debug_log("🔍 Obteniendo binary_dir desde CMakeCache.txt...", vim.log.levels.INFO)

  local binary_dir = get_cmake_cache_var("CMAKE_BINARY_DIR")

  if binary_dir then
    debug_log("✅ CMAKE_BINARY_DIR found: " .. binary_dir, vim.log.levels.INFO)
    return binary_dir
  end

  -- Fallback: usar la ubicación del CMakeCache.txt mismo
  debug_log("⚠️  CMAKE_BINARY_DIR not found in cache, using CMakeCache.txt location...", vim.log.levels.INFO)

  -- Buscar el buffer del CMakeCache.txt para obtener su ruta
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if name:match("CMakeCache%.txt$") then
      -- El directorio del CMakeCache.txt es el binary_dir
      binary_dir = vim.fn.fnamemodify(name, ":h")
      debug_log("✅ Binary_dir obtenido desde ubicación de CMakeCache.txt: " .. binary_dir, vim.log.levels.INFO)
      return binary_dir
    end
  end

  -- If there's no buffer, search for the file
  local cwd = vim.fn.getcwd()
  local common_paths = {
    cwd .. "/out/device-Debug/CMakeCache.txt",
    cwd .. "/out/toolchain-Debug/CMakeCache.txt",
    cwd .. "/out/Debug/CMakeCache.txt",
    cwd .. "/out/Release/CMakeCache.txt",
    cwd .. "/build/CMakeCache.txt",
    cwd .. "/CMakeCache.txt",
  }

  for _, path in ipairs(common_paths) do
    if vim.fn.filereadable(path) == 1 then
      binary_dir = vim.fn.fnamemodify(path, ":h")
      debug_log("✅ Binary_dir obtenido desde: " .. binary_dir, vim.log.levels.INFO)
      return binary_dir
    end
  end

  debug_log("❌ Could not determine binary_dir", vim.log.levels.ERROR)
  return nil
end

-- Parsea un archivo cmake_install.cmake y extrae los comandos file(INSTALL ...)
local function parse_cmake_install_file(file_path)
  if vim.fn.filereadable(file_path) ~= 1 then
    return {}
  end

  local content = table.concat(vim.fn.readfile(file_path), "\n")
  local install_items = {}

  -- Obtener CMAKE_INSTALL_PREFIX para expandir variables
  local install_prefix = get_cmake_cache_var("CMAKE_INSTALL_PREFIX") or "/usr"

  -- Parsear comandos file(INSTALL DESTINATION ... TYPE ... FILES ...)
  -- Puede estar en múltiples líneas, por lo que usamos un approach más robusto
  for install_block in content:gmatch("file%s*%(%s*INSTALL[^)]+%)") do
    local dest = install_block:match('DESTINATION%s+"([^"]+)"')
    local install_type = install_block:match('TYPE%s+(%w+)')

    if dest and install_type then
      -- Expandir ${CMAKE_INSTALL_PREFIX}
      dest = dest:gsub("%${CMAKE_INSTALL_PREFIX}", install_prefix)

      -- Extraer FILES o DIRECTORY
      local files_section = install_block:match('FILES%s+(.-)%)') or install_block:match('FILES%s+(.+)$')

      if files_section then
        -- Extract all files between quotes
        for file_path in files_section:gmatch('"([^"]+)"') do
          -- Determinar tipo normalizado
          local norm_type = "file"
          if install_type == "DIRECTORY" then
            norm_type = "directory"
          elseif install_type == "SHARED_LIBRARY" or install_type == "STATIC_LIBRARY" then
            norm_type = "library"
          elseif install_type == "EXECUTABLE" then
            norm_type = "executable"
          end

          table.insert(install_items, {
            type = norm_type,
            cmake_type = install_type,  -- Tipo original de CMake
            source = file_path,
            destination = dest,
            name = path_basename(file_path)
          })
        end
      end
    end
  end

  return install_items
end

-- Obtiene TODOS los items a instalar desde los archivos cmake_install.cmake generados por CMake
local function get_install_items_from_cmake()
  local binary_dir = get_binary_dir()
  if not binary_dir or binary_dir == "" then
    log_to_console("❌ Could not determine binary_dir from CMakeCache.txt", vim.log.levels.ERROR)
    return {}
  end

  log_to_console("📂 Reading cmake_install.cmake files from: " .. binary_dir, vim.log.levels.INFO)

  -- Buscar TODOS los archivos cmake_install.cmake recursivamente
  local install_files = vim.fn.globpath(binary_dir, "**/cmake_install.cmake", false, true)

  if #install_files == 0 then
    log_to_console("⚠️  No cmake_install.cmake files found in " .. binary_dir, vim.log.levels.WARN)
    log_to_console("💡 Have you compiled the project with CMake?", vim.log.levels.INFO)
    return {}
  end

  log_to_console(string.format("🔍 Found %d cmake_install.cmake files", #install_files), vim.log.levels.INFO)

  local all_items = {}
  local seen = {}  -- Para evitar duplicados

  for _, install_file in ipairs(install_files) do
    local rel_path = install_file:gsub(binary_dir, ""):gsub("^/", "")
    log_to_console(string.format("   📄 Parsing: %s", rel_path), vim.log.levels.DEBUG)

    local items = parse_cmake_install_file(install_file)
    for _, item in ipairs(items) do
      -- Evitar duplicados (mismo source + destination)
      local key = item.source .. "|" .. item.destination
      if not seen[key] then
        seen[key] = true
        table.insert(all_items, item)
        log_to_console(string.format("      📦 %s: %s -> %s", item.cmake_type, item.name, item.destination), vim.log.levels.INFO)
      end
    end
  end

  log_to_console(string.format("✅ Total: %d unique items to install", #all_items), vim.log.levels.INFO)
  return all_items
end

-- DEPRECATED: Las siguientes funciones se mantienen por compatibilidad pero ya no se usan en deploy
-- Resuelve variables CMake en un path
local function resolve_cmake_variables(path, cmake_file_dir, source_dir)
  if not path then
    return nil
  end

  -- Expandir variables comunes
  path = path:gsub("%${CMAKE_CURRENT_SOURCE_DIR}", cmake_file_dir)
  path = path:gsub("%${CMAKE_CURRENT_LIST_DIR}", cmake_file_dir)
  path = path:gsub("%${CMAKE_SOURCE_DIR}", source_dir)
  path = path:gsub("%${CMAKE_HOME_DIRECTORY}", source_dir)
  path = path:gsub("%${PROJECT_SOURCE_DIR}", source_dir)

  -- Expandir variables de CMakeCache.txt
  local project_name = get_cmake_cache_var("CMAKE_PROJECT_NAME")
  if project_name then
    path = path:gsub("%${PROJECT_NAME}", project_name)
    path = path:gsub("%${CMAKE_PROJECT_NAME}", project_name)
  end

  return path
end

-- Obtiene TODOS los items a instalar desde TODOS los CMakeLists.txt
local function get_all_install_items()
  local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
  if not source_dir then
    log_to_console("⚠️  CMAKE_HOME_DIRECTORY not found", vim.log.levels.WARN)
    return {}
  end

  local build_dir = get_cmake_cache_var("CMAKE_BINARY_DIR") or (source_dir .. "/out/Debug")

  -- Encontrar todos los CMakeLists.txt en el proyecto
  local cmake_files = vim.fn.globpath(source_dir, "**/CMakeLists.txt", false, true)
  local install_items = {}

  log_to_console(string.format("🔍 Searching for install() directives in %d CMakeLists.txt files", #cmake_files), vim.log.levels.INFO)

  for _, cmake_file in ipairs(cmake_files) do
    -- Evitar archivos en out/ o build/
    if not cmake_file:match("/out/") and not cmake_file:match("/build/") and not cmake_file:match("/_deps/") then
      local cmake_dir = vim.fn.fnamemodify(cmake_file, ":h")
      local content = table.concat(vim.fn.readfile(cmake_file), "\n")

      -- Parsear install(TARGETS ...)
      for install_line in content:gmatch("install%s*%(%s*TARGETS%s+[^%)]+%)") do
        local target_name = install_line:match("TARGETS%s+([^%s]+)")
        local dest = install_line:match("DESTINATION%s+([^%s%)]+)")

        if target_name and dest then
          dest = resolve_cmake_variables(dest, cmake_dir, source_dir)

          -- Determinar tipo de target y encontrar el archivo compilado
          local target_file = nil
          local rel_dir = cmake_dir:gsub(source_dir, ""):gsub("^/", "")

          -- Buscar .so en build_dir
          local so_pattern = build_dir .. "/" .. rel_dir .. "/*" .. target_name .. "*.so"
          local so_files = vim.fn.glob(so_pattern, false, true)

          if #so_files > 0 then
            target_file = so_files[1]
          else
            -- Search for executable
            local exe_path = build_dir .. "/" .. rel_dir .. "/" .. target_name
            if vim.fn.filereadable(exe_path) == 1 then
              target_file = exe_path
            end
          end

          if target_file then
            log_to_console(string.format("   📦 TARGETS: %s -> %s", path_basename(target_file), dest), vim.log.levels.INFO)
            table.insert(install_items, {
              type = "file",
              source = target_file,
              destination = dest,
              name = path_basename(target_file),
            })
          else
            log_to_console(string.format("   ⚠️  Target not found: %s (pattern: %s)", target_name, so_pattern), vim.log.levels.WARN)
          end
        end
      end

      -- Parsear install(DIRECTORY ...)
      for install_line in content:gmatch("install%s*%(%s*DIRECTORY%s+[^%)]+%)") do
        local source_path = install_line:match("DIRECTORY%s+([^%s]+)")
        local dest = install_line:match("DESTINATION%s+([^%s%)]+)")

        if source_path and dest then
          source_path = resolve_cmake_variables(source_path, cmake_dir, source_dir)
          dest = resolve_cmake_variables(dest, cmake_dir, source_dir)
          source_path = source_path:gsub("/$", "")

          if vim.fn.isdirectory(source_path) == 1 then
            log_to_console(string.format("   📁 DIRECTORY: %s -> %s", path_basename(source_path), dest), vim.log.levels.INFO)
            table.insert(install_items, {
              type = "directory",
              source = source_path,
              destination = dest,
              name = path_basename(source_path),
            })
          else
            log_to_console(string.format("   ⚠️  Directory does not exist: %s", source_path), vim.log.levels.WARN)
          end
        end
      end

      -- Parsear install(FILES ...)
      for install_line in content:gmatch("install%s*%(%s*FILES%s+[^%)]+%)") do
        local files_str = install_line:match("FILES%s+(.-)%s+DESTINATION")
        local dest = install_line:match("DESTINATION%s+([^%s%)]+)")

        if files_str and dest then
          dest = resolve_cmake_variables(dest, cmake_dir, source_dir)

          for file_path in files_str:gmatch("[^%s]+") do
            file_path = resolve_cmake_variables(file_path, cmake_dir, source_dir)

            if vim.fn.filereadable(file_path) == 1 then
              log_to_console(string.format("   📄 FILE: %s -> %s", path_basename(file_path), dest), vim.log.levels.INFO)
              table.insert(install_items, {
                type = "file",
                source = file_path,
                destination = dest,
                name = path_basename(file_path),
              })
            else
              log_to_console(string.format("   ⚠️  File does not exist: %s", file_path), vim.log.levels.WARN)
            end
          end
        end
      end
    end
  end

  log_to_console(string.format("✅ Total: %d items to install", #install_items), vim.log.levels.INFO)
  return install_items
end

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

-- Gets the main executable installation path
local function get_executable_install_path()
  local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
  if not source_dir then
    return "/usr/bin" -- Fallback si no se encuentra
  end

  local manager_cmake = source_dir .. "/manager/CMakeLists.txt"
  local install_path = get_install_destination(manager_cmake, "${PROJECT_NAME}")

  return install_path or "/usr/bin"
end

-- Obtiene la ruta de instalación de los plugins .so
local function get_plugin_install_path()
  local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
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

-- Obtiene directorios adicionales para deploy desde install(DIRECTORY ...)
local function get_additional_install_dirs()
  local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
  if not source_dir then
    vim.notify("⚠️  CMAKE_HOME_DIRECTORY not found", vim.log.levels.WARN)
    return {}
  end

  local manager_cmake = source_dir .. "/manager/CMakeLists.txt"
  vim.notify(string.format("🔍 Searching for install(DIRECTORY) en: %s", manager_cmake), vim.log.levels.INFO)

  if vim.fn.filereadable(manager_cmake) ~= 1 then
    vim.notify(string.format("⚠️  Could not read: %s", manager_cmake), vim.log.levels.WARN)
    return {}
  end

  local content = table.concat(vim.fn.readfile(manager_cmake), "\n")
  local dirs = {}

  -- Buscar SOLO líneas install(DIRECTORY ...), no install(TARGETS ...)
  local count = 0
  -- Pattern más específico: install(DIRECTORY debe estar al principio
  for install_line in content:gmatch("install%s*%(%s*DIRECTORY%s+[^%)]+%)") do
    count = count + 1
    vim.notify(string.format("   📄 Línea install #%d: %s", count, install_line:sub(1, 80)), vim.log.levels.INFO)

    -- Extraer el path después de DIRECTORY y antes de DESTINATION
    local source_path = install_line:match("DIRECTORY%s+([^%s]+)")
    local dest_path = install_line:match("DESTINATION%s+([^%s%)]+)")

    if source_path and dest_path then
      -- Expandir ${CMAKE_CURRENT_SOURCE_DIR}
      source_path = source_path:gsub("%${CMAKE_CURRENT_SOURCE_DIR}", source_dir .. "/manager")
      -- Remover trailing slash si existe
      source_path = source_path:gsub("/$", "")

      vim.notify(string.format("   ✓ Detectado: %s -> %s", path_basename(source_path), dest_path), vim.log.levels.INFO)

      table.insert(dirs, {
        source = source_path,
        destination = dest_path,
      })
    else
      vim.notify(
        string.format("   ⚠️  Could not parse: source=%s dest=%s", tostring(source_path), tostring(dest_path)),
        vim.log.levels.WARN
      )
    end
  end

  if count == 0 then
    vim.notify("   ⚠️  No se encontraron líneas install(DIRECTORY ...)", vim.log.levels.WARN)
  end

  return dirs
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

-- Resuelve la ruta absoluta de un comando en el PATH
local function resolve_command_path(command)
  if not command or command == "" then
    return nil
  end

  -- Si ya es una ruta absoluta, verificar que existe
  if command:match("^/") then
    if vim.fn.executable(command) == 1 then
      return command
    end
    return nil
  end

  -- Resolver usando vim.fn.exepath (busca en PATH)
  local resolved = vim.fn.exepath(command)
  if resolved ~= "" then
    return resolved
  end

  return nil
end

local function create_base_dap_config()
  local toolchain_path = os.getenv("OECORE_TARGET_SYSROOT")
  local pretty_printer_path = toolchain_path and (toolchain_path .. "/usr/lib/cmake/ZOne/tools/gdb") or ""

  -- Resolver ruta absoluta del GDB
  local gdb_path = os.getenv("LOCAL_GDB_PATH") or os.getenv("GDB") or "gdb"
  local resolved_gdb = resolve_command_path(gdb_path)
  if not resolved_gdb then
    resolved_gdb = "/usr/bin/gdb" -- Fallback final
  end

  local config = {
    name = "REMOTE DEBUG",
    type = "cppdbg",
    request = "launch",
    program = os.getenv("LOCAL_PROGRAM_PATH") or "/bin/true",
    MIMode = "gdb",
    miDebuggerPath = resolved_gdb,
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

-- Helper function to upload config directories (defined first for use by ensure_remote_program_async)
local function upload_config_directories(target, final_callback)
  local additional_dirs = get_additional_install_dirs()
  if #additional_dirs == 0 then
    log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
    log_to_console("✅ DEPLOY COMPLETED SUCCESSFULLY", vim.log.levels.INFO)
    log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
    final_callback(target, nil)
    return
  end

  log_to_console(string.format("📂 Uploading %d configuration director...", #additional_dirs), vim.log.levels.INFO)

  local dir_index = 1
  local function upload_next_directory()
    if dir_index > #additional_dirs then
      -- All directories uploaded
      log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
      log_to_console("✅ DEPLOY COMPLETED SUCCESSFULLY", vim.log.levels.INFO)
      log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
      final_callback(target, nil)
      return
    end

    local dir_info = additional_dirs[dir_index]
    local source_dir = dir_info.source
    local dest_dir = dir_info.destination
    dir_index = dir_index + 1

    log_to_console(string.format("🔍 Verifying: %s", source_dir), vim.log.levels.INFO)

    if vim.fn.isdirectory(source_dir) ~= 1 then
      log_to_console(string.format("⚠️  Directory does not exist: %s", source_dir), vim.log.levels.WARN)
      upload_next_directory()
      return
    end

    log_to_console(string.format("📁 Creating remote directory: %s", dest_dir), vim.log.levels.INFO)
    run_remote_async(string.format("mkdir -p %s", shell_quote(dest_dir)), function(mk_code, _)
      if mk_code ~= 0 then
        log_to_console(string.format("⚠️  Could not create %s", dest_dir), vim.log.levels.WARN)
        upload_next_directory()
        return
      end

      -- Validate dangerous directories
      local dangerous_dirs = { "/usr/bin", "/bin", "/sbin", "/usr/sbin", "/lib", "/usr/lib" }
      for _, danger_dir in ipairs(dangerous_dirs) do
        if dest_dir == danger_dir or dest_dir == danger_dir .. "/" then
          log_to_console(
            string.format("❌ PELIGRO: No se permite copiar directorios a %s (ruta crítica del sistema)", dest_dir),
            vim.log.levels.ERROR
          )
          upload_next_directory()
          return
        end
      end

      -- rsync directory
      local remote_host = os.getenv("REMOTE_SSH_HOST")
      log_to_console(
        string.format("🔄 Executing: rsync %s/ -> %s:%s/", path_basename(source_dir), remote_host, dest_dir),
        vim.log.levels.INFO
      )

      rsync_async(source_dir, dest_dir, function(rsync_code, _)
        if rsync_code == 0 then
          log_to_console(string.format("✓ Synchronized: %s -> %s", path_basename(source_dir), dest_dir), vim.log.levels.INFO)
        else
          log_to_console(
            string.format("⚠️  Falló sincronizar %s (code: %d)", path_basename(source_dir), rsync_code),
            vim.log.levels.WARN
          )
        end
        upload_next_directory()
      end)
    end)
  end

  upload_next_directory()
end

-- Deploy all items from cmake_install.cmake generated by CMake
local function deploy_all_install_items_async(final_callback)
  open_deploy_console()

  log_to_console("📦 Reading installation information from CMake-generated files...", vim.log.levels.INFO)
  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Obtener todos los items desde cmake_install.cmake (generados por CMake)
  local install_items = get_install_items_from_cmake()

  if #install_items == 0 then
    log_to_console("⚠️  No items found to install", vim.log.levels.WARN)
    log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
    log_to_console("✅ DEPLOY COMPLETED (no items)", vim.log.levels.INFO)
    log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
    final_callback(nil, nil)
    return
  end

  -- Agrupar archivos por directorio destino para enviarlos con tar
  local groups = {}  -- { [dest_dir] = { files = {...}, dirs = {...}, executables = {...} } }

  for _, item in ipairs(install_items) do
    if not groups[item.destination] then
      groups[item.destination] = { files = {}, dirs = {}, executables = {} }
    end

    if item.type == "directory" then
      table.insert(groups[item.destination].dirs, item)
    elseif item.type == "executable" then
      table.insert(groups[item.destination].executables, item)
    else
      table.insert(groups[item.destination].files, item)
    end
  end

  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
  log_to_console(string.format("📦 Optimized deploy: %d items grouped into %d destinations", #install_items, vim.tbl_count(groups)), vim.log.levels.INFO)
  log_to_console("⚡ Using tar+ssh for fast transfer", vim.log.levels.INFO)

  -- Convertir groups a array para iterar
  local group_list = {}
  for dest, group in pairs(groups) do
    table.insert(group_list, { destination = dest, group = group })
  end

  local group_index = 1

  local function deploy_next_group()
    if group_index > #group_list then
      log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
      log_to_console("✅ DEPLOY COMPLETED SUCCESSFULLY", vim.log.levels.INFO)
      log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
      final_callback("success", nil)
      return
    end

    local current = group_list[group_index]
    group_index = group_index + 1

    local dest_dir = current.destination
    if not dest_dir:match("/$") then
      dest_dir = dest_dir .. "/"
    end

    -- Crear directorio destino primero
    run_remote_async(string.format("mkdir -p %s", shell_quote(dest_dir)), function(mk_code, _)
      if mk_code ~= 0 then
        log_to_console(string.format("⚠️  Could not create %s", dest_dir), vim.log.levels.WARN)
        deploy_next_group()
        return
      end

      -- Forward declarations
      local deploy_next_dir
      local deploy_files_with_tar

      -- Deploy files and executables using tar
      deploy_files_with_tar = function()
        local all_files = {}
        for _, f in ipairs(current.group.files) do
          table.insert(all_files, f)
        end
        for _, f in ipairs(current.group.executables) do
          table.insert(all_files, f)
        end

        if #all_files == 0 then
          deploy_next_group()
          return
        end

        -- Crear lista de archivos para tar
        local file_list = {}
        for _, f in ipairs(all_files) do
          table.insert(file_list, shell_quote(f.source))
        end

        -- Usar tar | ssh | tar para transferencia rápida
        -- --transform quita el path completo y deja solo el nombre del archivo
        local host = os.getenv("REMOTE_SSH_HOST")
        local port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
        local control_opts = get_ssh_control_options()

        local tar_cmd = string.format(
          "tar czf - --transform='s|.*/||' %s | sshpass -e ssh -p %s %s -o StrictHostKeyChecking=no root@%s 'tar xzf - -C %s'",
          table.concat(file_list, " "),
          port,
          control_opts,
          host,
          shell_quote(dest_dir)
        )

        log_to_console(string.format("   📦 Sending %d files to %s with tar...", #all_files, dest_dir), vim.log.levels.INFO)

        vim.fn.jobstart(tar_cmd, {
          on_exit = function(_, exit_code, _)
            if exit_code == 0 then
              for _, f in ipairs(all_files) do
                log_to_console(string.format("   ✓ %s -> %s", f.name, f.destination), vim.log.levels.INFO)
              end

              -- Make executables executable with chmod +x
              if #current.group.executables > 0 then
                local chmod_files = {}
                for _, ex in ipairs(current.group.executables) do
                  table.insert(chmod_files, shell_quote(dest_dir .. ex.name))
                end
                local chmod_cmd = string.format("chmod +x %s", table.concat(chmod_files, " "))
                run_remote_async(chmod_cmd, function()
                  deploy_next_group()
                end)
              else
                deploy_next_group()
              end
            else
              log_to_console(string.format("   ⚠️  tar transfer failed to %s", dest_dir), vim.log.levels.WARN)
              deploy_next_group()
            end
          end,
        })
      end

      -- Deploy directories (using rsync as before)
      local dir_index = 1
      deploy_next_dir = function()
        if dir_index > #current.group.dirs then
          -- When directories are done, deploy files with tar
          deploy_files_with_tar()
          return
        end

        local dir_item = current.group.dirs[dir_index]
        dir_index = dir_index + 1

        rsync_async(dir_item.source, dir_item.destination, function(rsync_code, _)
          if rsync_code == 0 then
            log_to_console(string.format("   ✓ %s/ -> %s", dir_item.name, dir_item.destination), vim.log.levels.INFO)
          else
            log_to_console(string.format("   ⚠️  rsync failed: %s", dir_item.name), vim.log.levels.WARN)
          end
          deploy_next_dir()
        end)
      end

      -- Start deploy
      if #current.group.dirs > 0 then
        deploy_next_dir()
      else
        deploy_files_with_tar()
      end
    end)
  end

  deploy_next_group()
end

-- Asynchronous version with callbacks
local function ensure_remote_program_async(final_callback)
  -- Abrir consola de logs al iniciar deploy
  open_deploy_console()

  local lpath = os.getenv("LOCAL_PROGRAM_PATH")
  if not lpath or vim.fn.filereadable(lpath) ~= 1 then
    log_to_console("❌ LOCAL_PROGRAM_PATH does not exist or is not readable", vim.log.levels.ERROR)
    final_callback(nil, "LOCAL_PROGRAM_PATH no existe o no es legible")
    return
  end

  -- Usar ruta de instalación desde CMakeLists.txt
  local exe_install_path = get_executable_install_path()
  if not exe_install_path:match("/$") then
    exe_install_path = exe_install_path .. "/"
  end

  local base = path_basename(lpath)
  local target = exe_install_path .. base

  log_to_console(string.format("📦 Executable path detected: %s", exe_install_path), vim.log.levels.INFO)

  -- Step 1: Create remote directory
  run_remote_async(string.format("mkdir -p %s", shell_quote(exe_install_path)), function(code, _)
    if code ~= 0 then
      log_to_console("❌ Could not create remote directory", vim.log.levels.ERROR)
      final_callback(nil, "Could not create " .. exe_install_path)
      return
    end

    -- Step 2: Upload executable
    log_to_console(string.format("📦 Uploading executable: %s -> %s", base, target), vim.log.levels.INFO)
    scp_upload_async(lpath, target, function(scp_code, scp_out)
      if scp_code ~= 0 then
        log_to_console(string.format("❌ SCP failed: %s", scp_out), vim.log.levels.ERROR)
        final_callback(nil, "SCP failed: " .. scp_out)
        return
      end

      -- Step 3: Make executable
      run_remote_async(string.format("chmod +x %s", shell_quote(target)), function(ch_code, _)
        if ch_code ~= 0 then
          log_to_console("❌ chmod +x failed on target", vim.log.levels.ERROR)
          final_callback(nil, "chmod +x failed on target")
          return
        end
        log_to_console(string.format("✅ Executable deployed: %s", target), vim.log.levels.INFO)

        -- Step 4: Find and upload plugins
        local cmake_cache_path = vim.fn.findfile("CMakeCache.txt", lpath .. ";")
        local build_dir = nil

        if cmake_cache_path ~= "" then
          build_dir = vim.fn.fnamemodify(cmake_cache_path, ":h")
        else
          local source_dir = get_cmake_cache_var("CMAKE_HOME_DIRECTORY")
          if source_dir then
            build_dir = source_dir .. "/out/Debug"
          else
            build_dir = vim.fn.fnamemodify(lpath, ":h:h")
          end
        end

        log_to_console(string.format("🔍 Searching for plugins in: %s/plugins", build_dir), vim.log.levels.INFO)

        local so_files = vim.fn.globpath(build_dir .. "/plugins", "**/*.so", false, true)
        log_to_console(string.format("🔍 Found %d .so file(s)", #so_files), vim.log.levels.INFO)

        if #so_files > 0 then
          local plugin_path = get_plugin_install_path()
          log_to_console(string.format("📦 Plugin path detected: %s", plugin_path), vim.log.levels.INFO)

          -- Create plugin directory
          run_remote_async(string.format("mkdir -p %s", shell_quote(plugin_path)), function(mk_code, _)
            if mk_code ~= 0 then
              log_to_console("⚠️  Could not create directorio de plugins", vim.log.levels.WARN)
            end

            log_to_console(string.format("📦 Uploading %d .so plugin(s)...", #so_files), vim.log.levels.INFO)

            -- Upload plugins sequentially (could be parallelized)
            local plugin_index = 1
            local function upload_next_plugin()
              if plugin_index > #so_files then
                -- All plugins uploaded, continue to config directories
                upload_config_directories(target, final_callback)
                return
              end

              local so_file = so_files[plugin_index]
              local so_name = path_basename(so_file)
              local remote_so = plugin_path .. so_name
              plugin_index = plugin_index + 1

              scp_upload_async(so_file, remote_so, function(so_code, so_out)
                if so_code ~= 0 then
                  log_to_console(string.format("⚠️  Failed to upload %s: %s", so_name, so_out), vim.log.levels.WARN)
                else
                  log_to_console(string.format("✓ Uploaded: %s", so_name), vim.log.levels.INFO)
                end
                -- Continue with next plugin
                upload_next_plugin()
              end)
            end

            upload_next_plugin()
          end)
        else
          -- No plugins, go to config directories
          upload_config_directories(target, final_callback)
        end
      end)
    end)
  end)
end

-- Synchronous version (kept for compatibility)
local function ensure_remote_program()
  -- Abrir consola de logs al iniciar deploy
  open_deploy_console()

  local lpath = os.getenv("LOCAL_PROGRAM_PATH")
  if not lpath or vim.fn.filereadable(lpath) ~= 1 then
    log_to_console("❌ LOCAL_PROGRAM_PATH does not exist or is not readable", vim.log.levels.ERROR)
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

  log_to_console(string.format("📦 Executable path detected: %s", exe_install_path), vim.log.levels.INFO)

  -- Crear directorio si no existe
  local exists_code = select(1, run_remote(string.format("test -d %s", shell_quote(exe_install_path))))
  if exists_code ~= 0 then
    local mk_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(exe_install_path))))
    if mk_code ~= 0 then
      return nil, "Could not create " .. exe_install_path
    end
  end

  -- Upload main executable and make it executable
  log_to_console(string.format("📦 Uploading executable: %s -> %s", base, target), vim.log.levels.INFO)
  local scp_code, scp_out = scp_upload(lpath, target)
  if scp_code ~= 0 then
    log_to_console(string.format("❌ SCP failed: %s", scp_out), vim.log.levels.ERROR)
    return nil, "SCP failed: " .. scp_out
  end

  local ch_code = select(1, run_remote(string.format("chmod +x %s", shell_quote(target))))
  if ch_code ~= 0 then
    log_to_console("❌ chmod +x failed on target", vim.log.levels.ERROR)
    return nil, "chmod +x failed on target"
  end
  log_to_console(string.format("✅ Executable deployed: %s", target), vim.log.levels.INFO)

  -- Also upload .so plugins from build directory
  -- Get the root build directory (where CMakeCache.txt is located)
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

  log_to_console(string.format("🔍 Searching for plugins in: %s/plugins", build_dir), vim.log.levels.INFO)

  local so_files = vim.fn.globpath(build_dir .. "/plugins", "**/*.so", false, true)
  log_to_console(string.format("🔍 Found %d .so file(s)", #so_files), vim.log.levels.INFO)

  if #so_files > 0 then
    -- Obtener ruta de instalación de plugins desde CMakeLists.txt
    local plugin_path = get_plugin_install_path()
    log_to_console(string.format("📦 Plugin path detected: %s", plugin_path), vim.log.levels.INFO)

    -- Crear directorio de plugins si no existe
    local mk_plugin_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(plugin_path))))
    if mk_plugin_code ~= 0 then
      log_to_console("⚠️  Could not create directorio de plugins", vim.log.levels.WARN)
    end

    log_to_console(string.format("📦 Uploading %d .so plugin(s)...", #so_files), vim.log.levels.INFO)
    for _, so_file in ipairs(so_files) do
      local so_name = path_basename(so_file)
      local remote_so = plugin_path .. so_name
      local so_scp_code, so_scp_out = scp_upload(so_file, remote_so)
      if so_scp_code ~= 0 then
        log_to_console(string.format("⚠️  Failed to upload %s: %s", so_name, so_scp_out), vim.log.levels.WARN)
      else
        log_to_console(string.format("✓ Uploaded: %s", so_name), vim.log.levels.INFO)
      end
    end
  end

  -- Subir directorios adicionales (config files, dbus, etc.)
  local additional_dirs = get_additional_install_dirs()
  if #additional_dirs > 0 then
    log_to_console(string.format("📂 Uploading %d configuration director...", #additional_dirs), vim.log.levels.INFO)

    for _, dir_info in ipairs(additional_dirs) do
      local source_dir = dir_info.source
      local dest_dir = dir_info.destination

      -- Verificar que el directorio fuente existe
      log_to_console(string.format("🔍 Verifying: %s", source_dir), vim.log.levels.INFO)

      if vim.fn.isdirectory(source_dir) == 1 then
        -- Crear directorio destino si no existe
        log_to_console(string.format("📁 Creating remote directory: %s", dest_dir), vim.log.levels.INFO)
        local mk_code = select(1, run_remote(string.format("mkdir -p %s", shell_quote(dest_dir))))
        if mk_code ~= 0 then
          log_to_console(string.format("⚠️  Could not create %s", dest_dir), vim.log.levels.WARN)
        else
          -- VALIDACIÓN: Evitar copiar a directorios críticos del sistema
          local dangerous_dirs = { "/usr/bin", "/bin", "/sbin", "/usr/sbin", "/lib", "/usr/lib" }
          local is_dangerous = false
          for _, danger_dir in ipairs(dangerous_dirs) do
            if dest_dir == danger_dir or dest_dir == danger_dir .. "/" then
              log_to_console(
                string.format("❌ PELIGRO: No se permite copiar directorios a %s (ruta crítica del sistema)", dest_dir),
                vim.log.levels.ERROR
              )
              is_dangerous = true
              break
            end
          end

          if not is_dangerous then
            -- Usar rsync para subir el contenido del directorio
            -- IMPORTANTE: NO usar --delete para evitar borrar archivos del sistema
            local remote_port = os.getenv("REMOTE_SSH_PORT") or DEFAULT_SSH_PORT
            local remote_host = os.getenv("REMOTE_SSH_HOST")

            local rsync_cmd = string.format(
              "rsync -avz -e 'sshpass -e ssh -p %s -o StrictHostKeyChecking=no' '%s/' root@%s:'%s/'",
              remote_port,
              source_dir,
              remote_host,
              dest_dir
            )

            log_to_console(string.format("🔄 Executing: rsync %s/ -> %s:%s/", path_basename(source_dir), remote_host, dest_dir), vim.log.levels.INFO)
          local rsync_result = vim.fn.system(rsync_cmd)

          if vim.v.shell_error == 0 then
            log_to_console(string.format("✓ Synchronized: %s -> %s", path_basename(source_dir), dest_dir), vim.log.levels.INFO)
          else
            log_to_console(
              string.format("⚠️  Falló sincronizar %s (code: %d)", path_basename(source_dir), vim.v.shell_error),
              vim.log.levels.WARN
            )
            log_to_console(string.format("   Error: %s", vim.trim(rsync_result)), vim.log.levels.WARN)
          end
          end -- fin if not is_dangerous
        end
      else
        log_to_console(string.format("⚠️  Directory does not exist: %s", source_dir), vim.log.levels.WARN)
      end
    end
  end

  log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
  log_to_console("✅ DEPLOY COMPLETED SUCCESSFULLY", vim.log.levels.INFO)
  log_to_console("✅ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

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
    return nil, "Error preparing script: " .. result
  end

  return gdb_command
end

-- Cleanup function: kills gdbserver and debugged process
local function cleanup_remote_debug_processes(program_name, gdb_port)
  log_to_console("🧹 Cleaning up previous debug session...", vim.log.levels.INFO)

  -- Kill all gdbserver processes
  local kill_gdbserver = string.format(
    "ps | grep 'gdbserver' | grep -v grep | awk '{print $1}' | xargs kill -9 2>/dev/null || true"
  )

  -- Kill the debugged program by name (if running)
  local kill_program = ""
  if program_name and program_name ~= "" then
    kill_program = string.format(
      "; ps | grep '%s' | grep -v grep | awk '{print $1}' | xargs kill -9 2>/dev/null || true",
      program_name
    )
  end

  local cleanup_cmd = kill_gdbserver .. kill_program
  local ssh_cmd = build_ssh_command(cleanup_cmd)

  if ssh_cmd then
    local result = vim.fn.system(ssh_cmd)
    if vim.v.shell_error == 0 then
      log_to_console("✅ Previous processes cleaned up", vim.log.levels.INFO)
    else
      log_to_console("⚠️  Cleanup completed with warnings: " .. vim.trim(result), vim.log.levels.WARN)
    end
  end

  -- Wait a moment for processes to die
  vim.cmd("sleep 500m")
end

local function start_gdbserver(script_file, output_file, gdb_port)
  local cmd = string.format(
    "rm -f %s; touch %s; nohup %s >> %s 2>&1 & echo $!",
    shell_quote(output_file),
    shell_quote(output_file),
    shell_quote(script_file),
    shell_quote(output_file)
  )

  local ssh_cmd = build_ssh_command(cmd)
  if not ssh_cmd then
    return nil, "Error building SSH command"
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
  log_to_console("🔍 Verifying estado de gdbserver...", vim.log.levels.INFO)
  local check_cmd = build_ssh_command("ps | grep 'gdbserver :" .. gdb_port .. "' | grep -v grep")
  local check_result = vim.fn.system(check_cmd)

  if vim.v.shell_error ~= 0 or check_result == "" then
    log_to_console("⚠️  Gdbserver is not running on remote host", vim.log.levels.WARN)

    -- Leer output file para ver errores
    local error_check = build_ssh_command("cat " .. shell_quote(output_file) .. " 2>/dev/null | head -20")
    local error_output = vim.fn.system(error_check)
    if error_output ~= "" then
      log_to_console("📄 gdbserver output:", vim.log.levels.WARN)
      for line in error_output:gmatch("[^\r\n]+") do
        log_to_console("   " .. line, vim.log.levels.WARN)
      end
    end
    return false
  end

  log_to_console("✅ Gdbserver is running", vim.log.levels.INFO)

  -- Verificar puerto
  local port_check =
    build_ssh_command("(ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null) | grep ':" .. gdb_port .. "'")
  local port_result = vim.fn.system(port_check)

  if vim.v.shell_error ~= 0 or not port_result:match(gdb_port) then
    log_to_console("⚠️  Puerto " .. gdb_port .. " puede no estar escuchando aún", vim.log.levels.WARN)
    log_to_console("💡 This is normal - gdbserver waits for first connection to open the port", vim.log.levels.INFO)
  else
    log_to_console("✅ Puerto " .. gdb_port .. " is listening", vim.log.levels.INFO)
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
    log_to_console("ℹ️  Remote monitoring disabled", vim.log.levels.INFO)
    return
  end

  -- Asegurar que la ventana esté abierta
  BufferManager.get_or_create_output_buffer()

  -- Iniciar streaming con tail -f
  local tail_cmd = build_ssh_command("tail -f -n 0 " .. shell_quote(output_file) .. " 2>/dev/null")
  log_to_console("🔍 Starting remote output streaming...", vim.log.levels.INFO)

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
        vim.notify("⚠️  Output streaming ended (code: " .. code .. ")", vim.log.levels.WARN)
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
      return vim.notify("❌ No executable provided and $" .. envvar .. " is not defined", vim.log.levels.ERROR)
    end
    if vim.fn.filereadable(answer) ~= 1 then
      return vim.notify("❌ Executable does not exist/not readable: " .. answer, vim.log.levels.ERROR)
    end
    vim.fn.setenv(envvar, answer)
    cb(answer)
  end)
end

function _G.dap_remote_debug()
  -- Abrir consola de logs
  open_deploy_console()

  log_to_console("🐛 Starting remote debugging session...", vim.log.levels.INFO)
  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Cargar variables desde CMakeCache.txt
  local ssh_pass = get_cmake_cache_var("REMOTE_SSH_PASS")
  local ssh_host = get_cmake_cache_var("REMOTE_SSH_HOST")
  local ssh_port = get_cmake_cache_var("REMOTE_SSH_PORT")
  local gdb_port = get_cmake_cache_var("REMOTE_GDBSERVER_PORT")

  -- Verificar que existan en CMakeCache.txt
  if not ssh_pass then
    log_to_console("❌ REMOTE_SSH_PASS not found in CMakeCache.txt", vim.log.levels.ERROR)
    log_to_console("💡 Did you configure the project with a preset that has REMOTE_SSH_PASS?", vim.log.levels.INFO)
    return vim.notify("❌ REMOTE_SSH_PASS not found in CMakeCache.txt", vim.log.levels.ERROR)
  end
  if not ssh_host then
    log_to_console("❌ REMOTE_SSH_HOST not found in CMakeCache.txt", vim.log.levels.ERROR)
    log_to_console("💡 Did you configure the project with a preset that has REMOTE_SSH_HOST?", vim.log.levels.INFO)
    return vim.notify("❌ REMOTE_SSH_HOST not found in CMakeCache.txt", vim.log.levels.ERROR)
  end

  -- Setear variables de entorno
  vim.env.SSHPASS = ssh_pass
  vim.env.REMOTE_SSH_HOST = ssh_host
  vim.env.REMOTE_SSH_PORT = ssh_port or DEFAULT_SSH_PORT
  vim.env.REMOTE_GDBSERVER_PORT = gdb_port or DEFAULT_GDB_PORT

  -- Show SSH configuration
  log_to_console("📡 SSH Configuration:", vim.log.levels.INFO)
  log_to_console("   Host: " .. ssh_host, vim.log.levels.INFO)
  log_to_console("   SSH Port: " .. (ssh_port or DEFAULT_SSH_PORT), vim.log.levels.INFO)
  log_to_console("   GDB Port: " .. (gdb_port or DEFAULT_GDB_PORT), vim.log.levels.INFO)
  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Solicitar argumentos
  vim.ui.input({ prompt = "Execution arguments: ", default = "" }, function(input_args)
    if input_args == nil then
      log_to_console("❌ Debugging cancelled", vim.log.levels.WARN)
      return vim.notify("❌ Debugging cancelled", vim.log.levels.WARN)
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
      -- Use async version - Neovim won't block during deployment
      ensure_remote_program_async(function(rprog, err)
        if not rprog then
          log_to_console("❌ " .. err, vim.log.levels.ERROR)
          return vim.notify("❌ " .. err, vim.log.levels.ERROR)
        end

        -- Create DAP configuration
        local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or DEFAULT_GDB_PORT
        local target = vim.deepcopy(create_base_dap_config())

      target.args = args
      target.program = local_prog
      target.miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST")) .. ":" .. gdb_port
      target.console = "integratedTerminal"
      target.externalConsole = true
      -- setupCommands ya vienen de create_base_dap_config() con todos los comandos necesarios
      target.logging = { engineLogging = true, trace = true }

      -- Validar que el GDB path existe y es ejecutable
      if not target.miDebuggerPath or vim.fn.executable(target.miDebuggerPath) ~= 1 then
        local gdb_var = os.getenv("GDB") or os.getenv("LOCAL_GDB_PATH") or "gdb"
        log_to_console("❌ ERROR: GDB not found", vim.log.levels.ERROR)
        log_to_console("   Searching for: " .. gdb_var, vim.log.levels.ERROR)
        log_to_console("   Resolved path: " .. (target.miDebuggerPath or "NONE"), vim.log.levels.ERROR)
        log_to_console("", vim.log.levels.ERROR)
        log_to_console("💡 Solution:", vim.log.levels.INFO)
        log_to_console("   1. Configura la variable GDB con la ruta completa:", vim.log.levels.INFO)
        log_to_console("      export GDB=/ruta/a/tu/gdb", vim.log.levels.INFO)
        log_to_console("   2. O asegúrate que el comando esté en el PATH", vim.log.levels.INFO)
        return vim.notify("❌ GDB not found: " .. gdb_var, vim.log.levels.ERROR)
      end

      -- Log DAP configuration
      log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
      log_to_console("🔧 DAP Configuration:", vim.log.levels.INFO)
      log_to_console("   Local GDB: " .. target.miDebuggerPath, vim.log.levels.INFO)
      log_to_console("   Remote GDB: " .. target.miDebuggerServerAddress, vim.log.levels.INFO)
      log_to_console("   Program: " .. target.program, vim.log.levels.INFO)
      if #target.args > 0 then
        log_to_console("   Args: " .. table.concat(target.args, " "), vim.log.levels.INFO)
      end
      log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

      -- Preparar archivos remotos
      local output_base = "/tmp/" .. path_basename(rprog)
      local output_file = output_base .. ".output"
      local script_file = output_base .. ".sh"

      -- Cleanup any previous debug session
      local program_name = path_basename(rprog)
      cleanup_remote_debug_processes(program_name, gdb_port)

      -- Create gdbserver script
      log_to_console("📝 Preparing remote gdbserver...", vim.log.levels.INFO)
      local gdb_command, create_err = create_gdbserver_script(script_file, gdb_port, rprog, args)
      if not gdb_command then
        log_to_console("❌ " .. create_err, vim.log.levels.ERROR)
        return vim.notify("❌ " .. create_err, vim.log.levels.ERROR)
      end

      -- Iniciar gdbserver
      log_to_console("🚀 Starting remote gdbserver...", vim.log.levels.INFO)
      log_to_console("📋 Command: " .. gdb_command, vim.log.levels.DEBUG)

      local gdbserver_pid, start_err = start_gdbserver(script_file, output_file, gdb_port)
      if not gdbserver_pid then
        log_to_console("❌ " .. start_err, vim.log.levels.ERROR)
        log_to_console("💡 Run :DapRemoteDiagnostic for more information", vim.log.levels.INFO)
        return
      end

      log_to_console("✅ Gdbserver started (PID: " .. gdbserver_pid .. ")", vim.log.levels.INFO)
      log_to_console("📁 Output: " .. output_file, vim.log.levels.DEBUG)

      -- Wait for gdbserver to be ready
      local wait_ms = tonumber(os.getenv("DEBUG_WAIT_TIME")) or DEFAULT_WAIT_TIME
      log_to_console("⏳ Waiting " .. (wait_ms / 1000) .. " s for gdbserver to listen...", vim.log.levels.INFO)

      vim.defer_fn(function()
        verify_gdbserver(gdb_port, output_file)
        log_to_console("🛰️ Connecting debugger...", vim.log.levels.INFO)
        log_to_console(
          "ℹ️  Si ves 'Cursor position outside buffer', recompila el ejecutable con símbolos de debug (-g)",
          vim.log.levels.INFO
        )

        -- Configurar monitoreo de output
        OutputMonitor.setup(output_file)

        -- Registrar listeners de DAP para debugging
        dap.listeners.after.event_initialized["remote_debug_log"] = function()
          log_to_console("🎯 DAP initialized - debug session active", vim.log.levels.INFO)
        end

        dap.listeners.after.event_stopped["remote_debug_log"] = function(session, body)
          local reason = body.reason or "unknown"
          log_to_console("⏸️  Execution paused: " .. reason, vim.log.levels.INFO)
        end

        dap.listeners.after.event_terminated["remote_debug_log"] = function()
          log_to_console("🛑 Debug session terminated", vim.log.levels.WARN)
        end

        dap.listeners.after.event_exited["remote_debug_log"] = function(session, body)
          local code = body and body.exitCode or "unknown"
          log_to_console("🚪 Program exited with code: " .. tostring(code), vim.log.levels.INFO)

          -- Si el programa terminó con error, mostrar los logs del output remoto
          if code ~= 0 and code ~= "unknown" then
            log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.ERROR)
            log_to_console("❌ Error detected - Capturing remote program logs:", vim.log.levels.ERROR)

            -- Leer el archivo de output remoto
            local read_cmd = build_ssh_command(string.format("cat %s 2>/dev/null | tail -30", shell_quote(output_file)))
            local output = vim.fn.system(read_cmd)

            if vim.v.shell_error == 0 and output ~= "" then
              log_to_console("📄 Last 30 lines from " .. output_file .. ":", vim.log.levels.ERROR)
              for line in output:gmatch("[^\r\n]+") do
                log_to_console("   " .. line, vim.log.levels.ERROR)
              end
            else
              log_to_console("⚠️  Could not read remote output file", vim.log.levels.WARN)
            end
            log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.ERROR)
          end
        end

        -- Registrar cleanup
        dap.listeners.before.event_terminated["dapui_monitor"] = OutputMonitor.cleanup
        dap.listeners.before.event_exited["dapui_monitor"] = OutputMonitor.cleanup
        dap.listeners.before.disconnect["dapui_monitor"] = OutputMonitor.cleanup

        -- Cleanup remote processes when debug session ends
        dap.listeners.after.event_terminated["remote_cleanup"] = function()
          log_to_console("🧹 Cleaning up remote gdbserver...", vim.log.levels.INFO)
          cleanup_remote_debug_processes(program_name, gdb_port)
        end
        dap.listeners.after.event_exited["remote_cleanup"] = function()
          log_to_console("🧹 Cleaning up remote processes...", vim.log.levels.INFO)
          cleanup_remote_debug_processes(program_name, gdb_port)
        end

        log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
        log_to_console("🚀 Calling dap.run()...", vim.log.levels.INFO)

        -- Iniciar DAP
        local ok, err = pcall(function()
          dap.run(target)
        end)

        if not ok then
          log_to_console("❌ Error starting DAP: " .. tostring(err), vim.log.levels.ERROR)
          return vim.notify("❌ Error starting DAP: " .. tostring(err), vim.log.levels.ERROR)
        end

        -- Verificar que la sesión se inició
        vim.defer_fn(function()
          local session = dap.session()
          if not session then
            log_to_console("⚠️  WARNING: No DAP session active after 1 second", vim.log.levels.WARN)
            log_to_console("💡 Check DAP logs for errors", vim.log.levels.INFO)
          else
            log_to_console("✅ DAP session confirmed active", vim.log.levels.INFO)

            -- Cerrar la consola de deploy, ventanas vacías y DAP Console (pero mantener DAP REPL)
            vim.defer_fn(function()
              close_deploy_console()
              close_empty_windows()
              close_dap_console_window()
              -- Asegurar que el buffer de Remote Debug Output está visible
              local output_buf = BufferManager.find_by_name(REMOTE_OUTPUT_BUFFER_NAME)
              if output_buf then
                local win = BufferManager.find_window_for_buffer(output_buf)
                if not win then
                  BufferManager.open_in_split(output_buf)
                end
              end
            end, 500)
          end
        end, 1000)
      end, wait_ms)
      end) -- end ensure_remote_program_async callback
    end) -- end resolve_program_or_prompt callback
  end) -- end vim.ui.input callback
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
    vim.notify("⚠️  No remote output buffer. Start remote debug first.", vim.log.levels.WARN)
    return
  end

  local win = BufferManager.find_window_for_buffer(buf)

  if win then
    vim.api.nvim_set_current_win(win)
    vim.notify("📋 Output window focused", vim.log.levels.INFO)
  else
    BufferManager.open_in_split(buf)
    vim.notify("✅ Output buffer opened", vim.log.levels.INFO)
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
    vim.notify("✅ Monitor streaming stopped", vim.log.levels.INFO)
  else
    vim.notify("ℹ️  No active streaming", vim.log.levels.INFO)
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
    vim.notify("ℹ️  Monitoring inactive", vim.log.levels.INFO)
  end
end, { desc = "Estado del monitoreo remoto" })

vim.keymap.set("n", "<leader>dC", ":DapCleanupMonitor<CR>", { desc = "Cleanup Debug Monitor" })
vim.keymap.set("n", "<leader>dM", ":DapMonitorStatus<CR>", { desc = "Monitor Status" })
vim.keymap.set("n", "<leader>dL", ":DapCloseDeployConsole<CR>", { desc = "Close Deploy Console" })

-- ============================================================================
-- PUBLIC DEPLOY FUNCTION
-- ============================================================================

function _G.deploy_remote_program()
  -- Cargar variables desde CMakeCache.txt
  local ssh_pass = get_cmake_cache_var("REMOTE_SSH_PASS")
  local ssh_host = get_cmake_cache_var("REMOTE_SSH_HOST")
  local ssh_port = get_cmake_cache_var("REMOTE_SSH_PORT")

  -- Verificar que existan en CMakeCache.txt
  if not ssh_pass then
    return vim.notify("❌ REMOTE_SSH_PASS not found in CMakeCache.txt. Did you configure the correct preset?", vim.log.levels.ERROR)
  end
  if not ssh_host then
    return vim.notify("❌ REMOTE_SSH_HOST not found in CMakeCache.txt. Did you configure the correct preset?", vim.log.levels.ERROR)
  end

  -- Setear variables de entorno para que las funciones SSH las usen
  vim.env.SSHPASS = ssh_pass
  vim.env.REMOTE_SSH_HOST = ssh_host
  vim.env.REMOTE_SSH_PORT = ssh_port or "22"

  -- Usar la nueva función comprehensiva que parsea TODOS los install() de CMakeLists.txt
  deploy_all_install_items_async(function(result, err)
    if err then
      log_to_console("❌ " .. tostring(err), vim.log.levels.ERROR)
      vim.notify("❌ Deploy failed: " .. tostring(err), vim.log.levels.ERROR)
    else
      vim.notify("✅ Deploy completed", vim.log.levels.INFO)
    end
  end)
end

-- Show GDB setup commands
vim.api.nvim_create_user_command("DapShowGdbCommands", function()
  vim.notify("🔧 GDB commands that will be executed:", vim.log.levels.INFO)
  local commands = get_gdb_setup_commands()
  for i, cmd in ipairs(commands) do
    vim.notify(string.format("  %d. %s", i, cmd.text), vim.log.levels.INFO)
  end

  local toolchain_path = os.getenv("OECORE_TARGET_SYSROOT")
  if toolchain_path and toolchain_path ~= "" then
    vim.notify("", vim.log.levels.INFO)
    vim.notify("📚 Pretty printers detected:", vim.log.levels.INFO)
    vim.notify("  - set auto-load safe-path /", vim.log.levels.INFO)
    vim.notify("  - set auto-load yes", vim.log.levels.INFO)
    vim.notify(
      "  - python sys.path.insert(0, '" .. toolchain_path .. "/usr/lib/cmake/ZOne/tools/gdb')",
      vim.log.levels.INFO
    )
    vim.notify("  - python import zo_pretty_printers...", vim.log.levels.INFO)
  else
    vim.notify("", vim.log.levels.INFO)
    vim.notify("⚠️  OECORE_TARGET_SYSROOT not detected, pretty printers not available", vim.log.levels.WARN)
  end
end, { desc = "Mostrar comandos GDB que se ejecutarán" })

-- Close deploy console
vim.api.nvim_create_user_command("DapCloseDeployConsole", function()
  _G.close_deploy_console()
  vim.notify("✅ Deploy console closed", vim.log.levels.INFO)
end, { desc = "Cerrar ventana de logs de deploy" })

-- Diagnostic command
vim.api.nvim_create_user_command("DapRemoteDiagnostic", function()
  -- Abrir consola de logs
  open_deploy_console()

  log_to_console("🔍 Remote Debugging Diagnostic", vim.log.levels.INFO)
  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Cargar variables desde CMakeCache.txt
  local ssh_pass = get_cmake_cache_var("REMOTE_SSH_PASS")
  local ssh_host = get_cmake_cache_var("REMOTE_SSH_HOST")
  local ssh_port = get_cmake_cache_var("REMOTE_SSH_PORT")
  local gdb_port = get_cmake_cache_var("REMOTE_GDBSERVER_PORT")

  -- Verificar variables requeridas
  if not ssh_pass then
    log_to_console("❌ REMOTE_SSH_PASS not found in CMakeCache.txt", vim.log.levels.ERROR)
    log_to_console("💡 Did you configure the project with a preset that has REMOTE_SSH_PASS?", vim.log.levels.INFO)
    return
  end
  if not ssh_host then
    log_to_console("❌ REMOTE_SSH_HOST not found in CMakeCache.txt", vim.log.levels.ERROR)
    return
  end

  -- Setear variables de entorno para las funciones SSH
  vim.env.SSHPASS = ssh_pass
  vim.env.REMOTE_SSH_HOST = ssh_host
  vim.env.REMOTE_SSH_PORT = ssh_port or DEFAULT_SSH_PORT
  vim.env.REMOTE_GDBSERVER_PORT = gdb_port or DEFAULT_GDB_PORT
  vim.env.LOCAL_GDB_PATH = os.getenv("GDB")

  local host = ssh_host
  local port = ssh_port or DEFAULT_SSH_PORT
  gdb_port = gdb_port or DEFAULT_GDB_PORT

  -- Show configuration source
  local cmake_cache = get_cmake_cache_var("CMAKE_CACHEFILE_DIR")
  if cmake_cache then
    log_to_console(string.format("📋 Configuration from: %s/CMakeCache.txt", cmake_cache), vim.log.levels.INFO)
  else
    log_to_console("⚠️  CMakeCache.txt not found", vim.log.levels.WARN)
  end
  log_to_console("", vim.log.levels.INFO)

  -- Verificar variables
  local vars =
    { "REMOTE_SSH_HOST", "REMOTE_SSH_PORT", "SSHPASS", "LOCAL_PROGRAM_PATH", "LOCAL_GDB_PATH", "REMOTE_GDBSERVER_PORT" }
  for _, var in ipairs(vars) do
    local value = os.getenv(var)
    if value then
      local display = var == "SSHPASS" and "***" or value
      log_to_console("✅ " .. var .. ": " .. display, vim.log.levels.INFO)
    else
      log_to_console("❌ " .. var .. ": NO DEFINIDA", vim.log.levels.WARN)
    end
  end

  if not host then
    log_to_console("❌ REMOTE_SSH_HOST not defined. No se pueden hacer más verificaciones.", vim.log.levels.ERROR)
    return
  end

  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)

  -- Conectividad SSH
  log_to_console("🔌 Verificando conectividad SSH...", vim.log.levels.INFO)
  local ssh_test = build_ssh_command("echo 'OK'")
  local result = vim.fn.system(ssh_test)
  if vim.v.shell_error == 0 then
    log_to_console("✅ Conexión SSH exitosa", vim.log.levels.INFO)
  else
    log_to_console("❌ Conexión SSH fallida: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Rutas de instalación detectadas desde CMakeLists.txt
  log_to_console("📂 Rutas de instalación detectadas:", vim.log.levels.INFO)
  local exe_install_path = get_executable_install_path()
  local plugin_install_path = get_plugin_install_path()
  log_to_console(string.format("   Ejecutable: %s", exe_install_path), vim.log.levels.INFO)
  log_to_console(string.format("   Plugins:    %s", plugin_install_path), vim.log.levels.INFO)

  -- Mostrar directorios adicionales
  local additional_dirs = get_additional_install_dirs()
  if #additional_dirs > 0 then
    log_to_console(string.format("   Config directories: %d detected", #additional_dirs), vim.log.levels.INFO)
    for _, dir_info in ipairs(additional_dirs) do
      log_to_console(string.format("      • %s -> %s", path_basename(dir_info.source), dir_info.destination), vim.log.levels.INFO)
    end
  end

  local deploy_path = get_cmake_cache_var("DEPLOY_REMOTE_PATH")
  if deploy_path then
    log_to_console(string.format("   Deploy:     %s", deploy_path), vim.log.levels.INFO)
    if deploy_path == "/usr/bin/" or deploy_path == exe_install_path then
      log_to_console("   ⚠️  DEPLOY_REMOTE_PATH debería ser temporal (/tmp/), no la ruta de instalación", vim.log.levels.WARN)
    end
  end

  -- Verificar gdbserver
  log_to_console("📦 Verificando gdbserver...", vim.log.levels.INFO)
  local gdb_check = build_ssh_command("which gdbserver")
  local gdb_path = vim.fn.system(gdb_check)
  if vim.v.shell_error == 0 then
    log_to_console("✅ Gdbserver found at: " .. vim.trim(gdb_path), vim.log.levels.INFO)
  else
    log_to_console("❌ Gdbserver NO instalado en el host remoto", vim.log.levels.ERROR)
    log_to_console("💡 Instala con: ssh root@" .. host .. " 'apt-get install gdbserver'", vim.log.levels.INFO)
  end

  -- Procesos activos (BusyBox compatible)
  log_to_console("🔍 Searching for procesos gdbserver...", vim.log.levels.INFO)
  local ps_check = build_ssh_command("ps | grep gdbserver | grep -v grep")
  local ps_result = vim.fn.system(ps_check)
  if vim.v.shell_error == 0 and ps_result ~= "" then
    log_to_console("⚙️  Procesos gdbserver activos:", vim.log.levels.INFO)
    for line in ps_result:gmatch("[^\r\n]+") do
      log_to_console("   " .. line, vim.log.levels.INFO)
    end
  else
    log_to_console("ℹ️  No hay procesos gdbserver corriendo", vim.log.levels.INFO)
  end

  -- Puertos en escucha
  log_to_console("🔌 Verificando puertos en escucha...", vim.log.levels.INFO)
  local port_check = build_ssh_command("ss -tuln | grep LISTEN")
  local ports = vim.fn.system(port_check)
  if ports:find(":" .. gdb_port) then
    log_to_console("✅ Puerto " .. gdb_port .. " está en escucha", vim.log.levels.INFO)
  else
    log_to_console("ℹ️  Puerto " .. gdb_port .. " NO está en escucha", vim.log.levels.INFO)
  end

  log_to_console("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", vim.log.levels.INFO)
  log_to_console("✅ Diagnóstico completado", vim.log.levels.INFO)
end, { desc = "Diagnóstico de debugging remoto" })

return {}
