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
