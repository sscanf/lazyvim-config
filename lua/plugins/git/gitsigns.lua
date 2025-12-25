return {
  "lewis6991/gitsigns.nvim",
  opts = {
    current_line_blame = true,
  },
  keys = {
    { "<leader>gp", ":Gitsigns preview_hunk<CR>", desc = "Preview Hunk" },
    { "<leader>gt", ":Gitsigns toggle_current_line_blame", desc = "Toggle Line Blame" },
  },
}
