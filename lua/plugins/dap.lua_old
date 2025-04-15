return {
  -- DAP core dependencies
  { import = "lazyvim.plugins.extras.dap.core" },

  -- activate LazyVim's python extras
  { import = "lazyvim.plugins.extras.lang.python" },
  --
  -- disable venv because it's I'm handling this outside of nvim
  { "linux-cultist/venv-selector.nvim", enabled = false },

  --  disable automatic dap installation because it screws up my venv setup
  -- { "jay-babu/mason-nvim-dap.nvim", enabled = true},

  -- use local venv python for debugging
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      --  NOTE: make sure to install 'debugpy' in the local venv to use debugger
      "mfussenegger/nvim-dap-python",
      config = function()
        require("dap-python").setup("python")
      end,
    },
  },

  -- setup linting/formatting
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "mypy", "ruff" })
    end,
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        python = { "mypy" },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        ["python"] = { "ruff_fix", "ruff_format" },
      },
    },
  },
}
