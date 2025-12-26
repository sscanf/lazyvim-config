--[[
================================================================================
AUTO SESSION MANAGEMENT
================================================================================
Automatically saves and restores Neovim sessions.
Features:
  - Automatic session save/restore per project
  - Session lens for browsing and loading sessions
  - Excludes specific directories (home, downloads, root)
  - Preserves buffers, windows, and tab layouts
Plugin: rmagatti/auto-session
================================================================================
--]]

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
    })
  end,
}
