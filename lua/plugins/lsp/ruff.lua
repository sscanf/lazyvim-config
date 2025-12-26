--[[
================================================================================
RUFF LSP CONFIGURATION (PYTHON LINTER/FORMATTER)
================================================================================
Configures Ruff language server for Python linting and formatting.
Features:
  - Fast Python linter (faster than flake8, pylint)
  - Code formatting compatible with Black
  - Line length set to 120 characters
  - Automatic code fixes and imports sorting
Plugin: neovim/nvim-lspconfig with Ruff LSP
================================================================================
--]]

return {
  "neovim/nvim-lspconfig",
  opts = function(_, opts)
    opts.servers = opts.servers or {}
    opts.servers.ruff = {
      init_options = {
        settings = {
          args = {
            "--line-length=120",
          },
        },
      },
    }
    return opts
  end,
}
