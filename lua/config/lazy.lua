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
    name = "Depurar archivo actual",
    program = "${file}", -- Usa el archivo actual
    args = os.getenv("DEBUG_ARGS") and vim.split(os.getenv("DEBUG_ARGS"), " ") or {},
    pythonPath = function()
      return "python" -- Ruta a tu intérprete (ajusta si es necesario)
    end,
  },
}

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
    vim.cmd("split | buffer " .. buf)
  else
    vim.notify("No hay logs disponibles", vim.log.levels.WARN)
  end
end, { desc = "Mostrar logs de depuración" })
