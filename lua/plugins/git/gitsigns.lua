--[[
================================================================================
GITSIGNS - GIT DECORATIONS AND HUNKS
================================================================================
Shows git diff information in the sign column and provides git hunk operations.
Features:
  - Git signs in gutter (add, change, delete)
  - Current line blame display (enabled by default)
  - Preview hunks with <leader>gp
  - Toggle line blame with <leader>gt
  - Stage/unstage hunks
  - Navigate between hunks
Plugin: lewis6991/gitsigns.nvim
================================================================================
--]]

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
