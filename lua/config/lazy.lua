local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- add LazyVim and import its plugins
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    -- import/override with your plugins
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.ui.mini-animate" },
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

require("gitsigns").setup({
  current_line_blame = true,

  vim.keymap.set("n", "<leader>gp", ":Gitsigns preview_hunk<CR>", {}),
  vim.keymap.set("n", "<leader>gt", ":Gitsigns toggle_current_line_blame", {}),
})

-- require("lspconfig").ruff.setup({
--     on_attach = function(client, bufnr)
--         client.server_capabilities.documentFormattingProvider = false
--     end,
-- })

require("lspconfig").ruff.setup({
  init_options = {
    settings = {
      args = {
        "--line-length=120",
      },
    },
  },
})

local dap = require("dap")

-- Configurar el adaptador para Python
dap.adapters.python = {
  type = "executable",
  command = "python",
  args = { "-m", "debugpy.adapter" },
}

-- Configuración de la sesión de depuración
dap.configurations.python = {
  {
    type = "python",
    request = "launch",
    name = "Depurar archivo fijo",
    program = os.getenv("DEBUG_EXEC") or "${file}",
    args = os.getenv("DEBUG_ARGS") and vim.split(os.getenv("DEBUG_ARGS"), " ") or {},
    pythonPath = function()
      return "python"
    end,
  },
}

--dap.adapters.cppdbg = {
--  id = "cppdbg",
--  type = "executable",
--  command = "/home/parallels/.vscode/extensions/ms-vscode.cpptools-1.23.6-linux-x64/debugAdapters/bin/OpenDebugAD7",
--}

-- Cargar configuración DAP específica del proyecto si existe
local function load_project_dap_config()
  local project_root = vim.fn.getcwd()
  local dap_config_file = project_root .. "/.nvim/dap.lua"
  if vim.fn.filereadable(dap_config_file) == 1 then
    local ok, err = pcall(dofile, dap_config_file)
    if not ok then
      vim.notify("Error loading project dap config: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("Loaded project-specific DAP config", vim.log.levels.INFO)
    end
  end
end

-- Llama a la función cuando abras un proyecto
vim.api.nvim_create_autocmd("VimEnter", {
  callback = load_project_dap_config,
})

local remote_host = os.getenv("REMOTE_HOST")
local ssh_port = os.getenv("REMOTE_SSH_PORT") or "2222"
local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
local gdb_path = os.getenv("REMOTE_DEBUG_GDB_PATH")
local deploy_base = os.getenv("DEPLOY_REMOTE_BASE_PATH")
local remote_bin = os.getenv("REMOTE_BINARY_NAME")

if remote_host and gdb_path and deploy_base and remote_bin then
  local program_path = string.format("%s/usr/bin/%s", deploy_base, remote_bin)

  dap.adapters.gdb = {
    type = "executable",
    command = gdb_path,
    args = { "-i", "dap" },
  }

  -- Crear una configuración independiente
  local remote_config = {
    name = "RemoteLaunch",
    type = "gdb",
    request = "launch",
    program = "gdbserver",
    cwd = "${workspaceFolder}",
    stopOnEntry = true,
    target = remote_host,
    port = gdb_port,
    remote = true,
    gdbpath = "/usr/bin/",
    sshPort = tonumber(ssh_port),
    env = {
      REMOTE_TARGET = "1",
    },
    is_remote_config = true,
  }

  -- Asignar la configuración a C++
  dap.configurations.cpp = dap.configurations.cpp or {}
  table.insert(dap.configurations.cpp, remote_config)

  print("Configuración remota cargada:", vim.inspect(remote_config))

  -- Mapeo específico para depuración remota
  vim.keymap.set("n", "<leader>dr", function()
    print("Ejecutando configuración remota...")
    dap.run(remote_config)
  end, { desc = "Debug Remote" })

  -- Listener usando la configuración directa
  dap.listeners.before.launch["gdbserver-start"] = function(config)
    print("Listener before.launch activado")
    print("Configuración recibida:", vim.inspect(config))

    if config and config.is_remote_config then
      local ssh_cmd = {
        "ssh",
        "-p",
        ssh_port,
        "root@" .. remote_host,
        "gdbserver",
        ":" .. gdb_port,
        program_path,
      }

      vim.notify("🚀 Iniciando gdbserver remoto...", vim.log.levels.INFO)
      print("Comando SSH: " .. table.concat(ssh_cmd, " "))

      vim.fn.jobstart(ssh_cmd, {
        detach = true,
        on_exit = function(_, code)
          if code ~= 0 then
            vim.notify("❌ gdbserver falló (código " .. code .. ")", vim.log.levels.ERROR)
          end
        end,
      })
    else
      print("Configuración no válida para listener remoto")
    end
  end
end

-- local remote_ip = os.getenv("REMOTE_HOST")
-- local gdb_path = os.getenv("REMOTE_DEBUG_GDB_PATH")
-- local program_path = os.getenv("PROGRAM_PATH")
--
-- if remote_ip and gdb_path then
--   dap.configurations.cpp = {
--     {
--       name = "Remote GDB",
--       type = "cppdbg",
--       request = "launch",
--       MIMode = "gdb",
--       miDebuggerServerAddress = remote_ip .. ":10000",
--       miDebuggerPath = gdb_path,
--       cwd = "${workspaceFolder}",
--       program = program_path,
--       setupCommands = {
--         {
--           text = "-enable-pretty-printing",
--           ignoreFailures = false,
--         },
--       },
--     },
--   }
-- end
--
require("cmake-tools").setup({
  cmake_build_args = { "-j", tostring(vim.loop.cpu_info() and #vim.loop.cpu_info() or 4) },
})

-- Usa una tabla para almacenar el buffer de logs y evitar problemas de ámbito
local debug_logs = {
  buffer = nil,
}

-- Función para crear/obtener el buffer de logs
local function get_log_buffer()
  if not debug_logs.buffer or not vim.api.nvim_buf_is_valid(debug_logs.buffer) then
    debug_logs.buffer = vim.api.nvim_create_buf(false, true) -- Crea un buffer no listado
    vim.api.nvim_buf_set_name(debug_logs.buffer, "Debug-Logs")
    vim.api.nvim_buf_set_option(debug_logs.buffer, "filetype", "log")
  end
  return debug_logs.buffer
end

-- Configura el listener para capturar la salida
dap.listeners.before["event_output"]["log_output"] = function(_, body)
  local buf = get_log_buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    -- Limpia el buffer antes de agregar nuevas líneas
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    -- Usa vim.schedule para evitar problemas de hilos
    vim.schedule(function()
      local lines = vim.split(body.output, "\n")
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    end)
  end
end

-- Configura el listener para mostrar el buffer al terminar
dap.listeners.after["event_terminated"]["show_logs"] = function()
  local buf = get_log_buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.schedule(function()
      vim.cmd("split | buffer " .. buf)
    end)
  end
end

-- Atajo para abrir los logs
vim.keymap.set("n", "<leader>dl", function()
  local buf = get_log_buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local win_id = vim.fn.bufwinid(buf)
    if win_id ~= -1 then
      vim.cmd("hide")
    end
    vim.cmd("split | buffer " .. buf)
  else
    vim.notify("No hay logs disponibles", vim.log.levels.WARN)
  end
end, { desc = "Show debug logs" })

-- Atajo para cerrar los logs
vim.keymap.set("n", "<leader>dh", function()
  local buf = get_log_buffer()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    local win_id = vim.fn.bufwinid(buf)
    if win_id ~= -1 then
      vim.cmd("hide")
    end
  else
    vim.notify("No hay logs disponibles", vim.log.levels.WARN)
  end
end, { desc = "Hide debug logs" })

-- Depuración de listeners DAP
print("\n=== LISTENERS DAP REGISTRADOS ===")
for event, listeners in pairs(dap.listeners) do
  print("Evento:", event)
  for name, _ in pairs(listeners) do
    print("  Listener:", name)
  end
end

-- Depuración de configuraciones
print("\n=== CONFIGURACIONES DAP ===")
for lang, configs in pairs(dap.configurations) do
  print("Lenguaje:", lang)
  for i, config in ipairs(configs) do
    print("  Configuración", i, ":", config.name or "sin nombre")
  end
end
