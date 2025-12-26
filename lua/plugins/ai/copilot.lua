--[[
================================================================================
GITHUB COPILOT INTEGRATION
================================================================================
Configures GitHub Copilot AI assistant for code completion.
Features:
  - Auto-trigger suggestions while typing
  - Accept suggestions with Shift+Tab
  - Enabled for all file types
  - Panel disabled (suggestions shown inline)
Plugin: zbirenbaum/copilot.lua
================================================================================
--]]

return {
  {
    "zbirenbaum/copilot.lua",
    event = "VeryLazy",
    config = function()
      require("copilot").setup({

        suggestion = {
          enabled = true,
          auto_trigger = true,
          accept = false,
        },
        panel = {
          enabled = false,
        },
        filetypes = {
          markdowen = true,
          help = true,
          html = true,
          javascript = true,
          ["*"] = true,
        },
      })

      vim.keymap.set("i", "<S-Tab>", function()
        if require("copilot.suggestion").is_visible() then
          require("copilot.suggestion").accept()
        else
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<S-Tab>", true, false, true), "n", false)
        end
      end, {
        silent = true,
      })
    end,
  },
}
