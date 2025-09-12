local dap = require("dap")

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

local function resolve_program_or_prompt(envvar, default_path, cb)
  local p = os.getenv(envvar)
  if p and p ~= "" and vim.fn.filereadable(p) == 1 then
    return cb(p)
  end
  local deduced = find_latest_executable_in_build()
  local prompt_default = deduced or default_path or ""
  vim.ui.input({ prompt = "Ruta del ejecutable:", default = prompt_default }, function(answer)
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
    program = p or "/bin/true",
    MIMode = "gdb",
    miDebuggerPath = os.getenv("LOCAL_GDB_PATH") or "/usr/bin/gdb",
    cwd = p and vim.fn.fnamemodify(p, ":h") or "${workspaceFolder}",
    stopAtEntry = true,
    console = "internalConsole",
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
  dap.configurations.c = dap.configurations.c or {}
  dap.configurations.cpp = dap.configurations.cpp or {}
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
    program = p or "/bin/true",
    cwd = p and vim.fn.fnamemodify(p, ":h") or "${workspaceFolder}",
    stopAtEntry = true,
    env = { GDBINIT = "/dev/null" },
    setupCommands = setup,
  }
  dap.configurations.c = dap.configurations.c or {}
  dap.configurations.cpp = dap.configurations.cpp or {}
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

return {}
