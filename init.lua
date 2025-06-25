-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

-- Bloquea la apertura automática con Tab
vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    vim.keymap.set("i", "<Tab>", "<Tab>", {
      buffer = true,
      silent = true,
      noremap = true,
      expr = false,
      desc = "Tab normal en modo inserción",
    })
  end,
})
