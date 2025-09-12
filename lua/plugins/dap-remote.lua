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
    miDebuggerPath = os.getenv("GDB") or "/usr/bin/gdb",
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
      target.miDebuggerServerAddress = (os.getenv("REMOTE_SSH_HOST"))
        .. ":"
        .. (os.getenv("REMOTE_GDBSERVER_PORT") or "10000")

      target.console = "internalConsole"
      target.stopAtEntry = false

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
return {}
