--[[
================================================================================
NEOMINIMAP - CODE MINIMAP
================================================================================
Provides a code minimap similar to VSCode/Sublime Text.
Features:
  - Traditional minimap showing code structure
  - Syntax-highlighted minimap
  - Auto-update on buffer changes
  - Customizable width and position
  - Git integration
  - LSP diagnostics markers
  - Search results highlighting
Keymaps:
  - <leader>nm: Toggle minimap
  - <leader>nmo: Open minimap
  - <leader>nmc: Close minimap
  - <leader>nmr: Refresh minimap
  - <leader>nmt: Toggle minimap focus
Plugin: Isrothy/neominimap.nvim
================================================================================
--]]

return {
  "Isrothy/neominimap.nvim",
  version = "v3.*.*",
  enabled = true,
  lazy = false, -- Load immediately to ensure minimap is available
  init = function()
    -- Configuration for neominimap v3
    -- Global options must be set before the plugin loads
    vim.g.neominimap = {
      auto_enable = true,

      -- Layout
      layout = "float", -- "float" or "split"
      split = "right",

      -- Appearance
      width = 20,
      height = 0.8,
      x = 1.0,
      y = 0.1,

      -- Window options
      border = "single",

      -- Filters
      buf_filter = function(bufnr)
        local buftype = vim.bo[bufnr].buftype
        local filetype = vim.bo[bufnr].filetype

        if buftype ~= "" and buftype ~= "acwrite" then
          return false
        end

        local excluded = {
          "help", "alpha", "dashboard", "neo-tree", "Trouble",
          "lazy", "mason", "notify", "toggleterm", "lazyterm"
        }

        for _, ft in ipairs(excluded) do
          if filetype == ft then
            return false
          end
        end

        return true
      end,

      -- Click behavior
      click = {
        enabled = true,
        auto_switch_focus = true,
      },

      -- Integrations
      diagnostic = {
        enabled = true,
        severity = vim.diagnostic.severity.WARN,
        mode = "icon",
        icon = {
          ERROR = "󰅚",
          WARN = "󰀪",
          INFO = "󰋽",
          HINT = "󰌶",
        },
      },

      git = {
        enabled = true,
        mode = "icon",
      },

      search = {
        enabled = true,
      },

      mark = {
        enabled = true,
        mode = "icon",
        show_builtins = false,
      },

      treesitter = {
        enabled = true,
      },

      fold = {
        enabled = true,
      },
    }
  end,
  config = function()
    -- Keymaps - usando <leader>m para evitar conflicto con notification history
    vim.keymap.set("n", "<leader>mt", "<cmd>Neominimap toggle<cr>", { desc = "Toggle minimap" })
    vim.keymap.set("n", "<leader>mo", "<cmd>Neominimap on<cr>", { desc = "Open minimap" })
    vim.keymap.set("n", "<leader>mc", "<cmd>Neominimap off<cr>", { desc = "Close minimap" })
    vim.keymap.set("n", "<leader>mr", "<cmd>Neominimap refresh<cr>", { desc = "Refresh minimap" })
    vim.keymap.set("n", "<leader>mf", "<cmd>Neominimap toggleFocus<cr>", { desc = "Toggle minimap focus" })

    -- Auto-disable minimap when windows open to the right
    local minimap_auto_disabled = false
    local minimap_was_enabled = false

    -- Check if there are windows to the right side (excluding floating windows and minimap)
    local function has_windows_to_right()
      local current_win = vim.api.nvim_get_current_win()
      local wins = vim.api.nvim_tabpage_list_wins(0)
      local editor_width = vim.o.columns

      for _, win in ipairs(wins) do
        local config = vim.api.nvim_win_get_config(win)
        -- Skip floating windows (minimap is floating)
        if config.relative == "" then
          local pos = vim.api.nvim_win_get_position(win)
          local width = vim.api.nvim_win_get_width(win)
          local win_right_edge = pos[2] + width

          -- Consider a window "to the right" if it starts past 70% of the editor width
          if pos[2] > editor_width * 0.6 then
            local bufnr = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[bufnr].filetype
            local bt = vim.bo[bufnr].buftype

            -- Exclude certain filetypes that shouldn't trigger this
            local excluded = { "neo-tree", "NvimTree", "neominimap" }
            local is_excluded = false
            for _, ex in ipairs(excluded) do
              if ft == ex then
                is_excluded = true
                break
              end
            end

            if not is_excluded then
              return true
            end
          end
        end
      end
      return false
    end

    local function update_minimap_visibility()
      vim.defer_fn(function()
        local has_right_windows = has_windows_to_right()

        if has_right_windows and not minimap_auto_disabled then
          -- Disable minimap
          minimap_was_enabled = vim.g.neominimap and vim.g.neominimap.auto_enable
          minimap_auto_disabled = true
          vim.cmd("Neominimap off")
        elseif not has_right_windows and minimap_auto_disabled then
          -- Re-enable minimap
          minimap_auto_disabled = false
          if minimap_was_enabled then
            vim.cmd("Neominimap on")
          end
        end
      end, 50) -- Small delay to let window layout settle
    end

    -- Create autocommands for window events
    local augroup = vim.api.nvim_create_augroup("NeominimapAutoToggle", { clear = true })

    vim.api.nvim_create_autocmd({ "WinNew", "WinEnter", "BufWinEnter" }, {
      group = augroup,
      callback = update_minimap_visibility,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      callback = function()
        -- Delay to let the window actually close
        vim.defer_fn(update_minimap_visibility, 100)
      end,
    })

    vim.notify("Neominimap configurado correctamente", vim.log.levels.INFO)
  end,
}
