return {
  "rmagatti/auto-session",
  config = function()
    require("auto-session").setup({
      auto_session_suppres_dirs = { "~/", "~/projects/", "~/Downloads", "/" },
      session_lens = {
        buftypes_to_ignore = {},
        load_on_setup = true,
        theme_conf = { border = true },
        previewer = false,
      },
      vim.keymap.set("n", "<Leader>ls", require("auto-session.session-lens").search_session, {
        noremap = true,
      }),
    })
  end,
}
