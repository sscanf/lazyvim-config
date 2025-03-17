-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
--
vim.api.nvim_set_keymap("n", "<A-b>", ":lua require'dap'.toggle_breakpoint()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<A-d>", ":lua require'dap'.continue()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<A-i>", ":lua require'dap'.step_into()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<A-v>", ":lua require'dap'.step_over()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<A-t>", ':lua require("dap.repl").open()<CR>', { noremap = true, silent = true })

vim.api.nvim_set_keymap(
  "n",
  "<F4>",
  ":ClangdSwitchSourceHeader<CR>",
  { noremap = true, silent = true, desc = "Switch between source and header" }
)

vim.api.nvim_set_keymap("n", "<Tab>", ":bnext<CR>", { noremap = true, silent = true, desc = "Siguiente Buffer" })
vim.api.nvim_set_keymap("n", "<S-Tab>", ":bprevious<CR>", { noremap = true, silent = true, desc = "Buffer Anterior" })

vim.api.nvim_set_keymap(
  "n",
  "<S-Left>",
  "<C-w>h",
  { noremap = true, silent = true, desc = "Mover a la ventana izquierda" }
)
vim.api.nvim_set_keymap(
  "n",
  "<S-Down>",
  "<C-w>j",
  { noremap = true, silent = true, desc = "Mover a la ventana inferior" }
)
vim.api.nvim_set_keymap(
  "n",
  "<S-Up>",
  "<C-w>k",
  { noremap = true, silent = true, desc = "Mover a la ventana superior" }
)
vim.api.nvim_set_keymap(
  "n",
  "<S-Right>",
  "<C-w>l",
  { noremap = true, silent = true, desc = "Mover a la ventana derecha" }
)

-- cppassist keymaps
local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- generate the function definition or static variable definition in source
map("n", "<leader>cf", "<Cmd>ImplementInSource<CR>", opts)
-- generate the function definition or static variable definition in source in visual mode
map("v", "<leader>cf", '<Cmd>lua require("cppassist").ImplementInSourceInVisualMode<CR>', opts)
-- generate the function definition or static variable definition in header
map("n", "<leader>cv", "<Cmd>ImplementOutOfClass<CR>", opts)
-- goto the header file
map("n", "<leader>gh", "<Cmd>GotoHeaderFile<CR>", opts)
