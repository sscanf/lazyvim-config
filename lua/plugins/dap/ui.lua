--[[
================================================================================
DAP UI (DEBUG INTERFACE)
================================================================================
Provides a comprehensive UI for nvim-dap debugging sessions.
Layout configuration:
  Right panel (40 cols):
    - Scopes (35%)
    - Locals (35%)
    - Watches (30%)
  Bottom panel (10 rows):
    - REPL (50%)
    - Console (20%)
    - Breakpoints (10%)
    - Stacks (20%)
Features:
  - Auto-open on debug session start
  - Auto-close on debug session end
  - Floating window support
  - Persistent layout sizes (saved automatically)
  - Persistent watch expressions (saved automatically)
Plugin: rcarriga/nvim-dap-ui
================================================================================
--]]

-- Path for storing persistent data
local data_path = vim.fn.stdpath("data") .. "/dap-session.json"

-- Default layout configuration
local default_layouts = {
  {
    elements = {
      { id = "scopes", size = 0.35 },
      { id = "locals", size = 0.35 },
      { id = "watches", size = 0.3 },
    },
    size = 40,
    position = "right",
  },
  {
    elements = {
      { id = "repl", size = 0.5 },
      { id = "console", size = 0.2 },
      { id = "breakpoints", size = 0.1 },
      { id = "stacks", size = 0.2 },
    },
    size = 10,
    position = "bottom",
  },
}

-- Initialize global persistence module (only once)
if not _G.DapPersistence then
  _G.DapPersistence = {}

  -- Load persistent data from file
  function _G.DapPersistence.load()
    local file = io.open(data_path, "r")
    if not file then
      return { layouts = nil, watches = {} }
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
      return { layouts = nil, watches = {} }
    end
    local ok, data = pcall(vim.json.decode, content)
    if not ok or type(data) ~= "table" then
      return { layouts = nil, watches = {} }
    end
    -- Ensure watches is a table
    if type(data.watches) ~= "table" then
      data.watches = {}
    end
    return data
  end

  -- Save persistent data to file
  function _G.DapPersistence.save(data)
    local file = io.open(data_path, "w")
    if not file then
      vim.notify("No se pudo guardar configuración DAP UI: " .. data_path, vim.log.levels.WARN)
      return false
    end
    local ok, json = pcall(vim.json.encode, data)
    if ok and json then
      file:write(json)
    else
      vim.notify("Error codificando JSON", vim.log.levels.WARN)
      file:close()
      return false
    end
    file:close()
    return true
  end

  -- Get layouts with saved sizes applied
  function _G.DapPersistence.get_layouts()
    local saved = _G.DapPersistence.load()
    if saved.layouts then
      return saved.layouts
    end
    return default_layouts
  end

  -- Save current layout sizes
  function _G.DapPersistence.save_layout_sizes(layouts)
    local data = _G.DapPersistence.load()
    data.layouts = layouts
    _G.DapPersistence.save(data)
  end

  -- Get saved watch expressions
  function _G.DapPersistence.get_watches()
    local data = _G.DapPersistence.load()
    return data.watches or {}
  end

  -- Save watch expressions
  function _G.DapPersistence.save_watches(watches)
    local data = _G.DapPersistence.load()
    data.watches = watches
    _G.DapPersistence.save(data)
  end

  -- Add a watch expression
  function _G.DapPersistence.add_watch(expr)
    local watches = _G.DapPersistence.get_watches()
    -- Avoid duplicates
    for _, w in ipairs(watches) do
      if w == expr then
        return
      end
    end
    table.insert(watches, expr)
    _G.DapPersistence.save_watches(watches)
  end

  -- Remove a watch expression
  function _G.DapPersistence.remove_watch(expr)
    local watches = _G.DapPersistence.get_watches()
    for i, w in ipairs(watches) do
      if w == expr then
        table.remove(watches, i)
        _G.DapPersistence.save_watches(watches)
        return
      end
    end
  end

  -- Clear all watch expressions
  function _G.DapPersistence.clear_watches()
    _G.DapPersistence.save_watches({})
  end
end

-- Local reference for convenience
local DapPersistence = _G.DapPersistence

return {
  "rcarriga/nvim-dap-ui",
  lazy = false,
  dependencies = { "mfussenegger/nvim-dap" },
  opts = function()
    return {
      layouts = DapPersistence.get_layouts(),
      floating = {
        max_height = nil,
        max_width = nil,
        border = "single",
      },
      windows = { indent = 1 },
    }
  end,
  config = function(_, opts)
    local dap = require("dap")
    local dapui = require("dapui")

    -- Track current layout sizes for persistence
    local current_layouts = vim.deepcopy(opts.layouts)

    dapui.setup(opts)

    -- Restore saved watches when DAP UI is set up
    local function restore_watches()
      local watches = DapPersistence.get_watches()
      if #watches > 0 then
        vim.defer_fn(function()
          for _, expr in ipairs(watches) do
            pcall(function()
              require("dapui").elements.watches.add(expr)
            end)
          end
        end, 100)
      end
    end

    -- Function to detect layout window and save its size
    local function save_layout_sizes()
      -- Find DAP UI windows and save their sizes
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[buf].filetype

        -- Check if this is a DAP UI window
        if ft and ft:match("^dapui_") then
          local win_config = vim.api.nvim_win_get_config(win)
          -- Only process non-floating windows
          if win_config.relative == "" then
            local width = vim.api.nvim_win_get_width(win)
            local height = vim.api.nvim_win_get_height(win)

            -- Determine if this is the right panel (by position/width)
            -- Right panel windows have significant width
            if width > 20 and width < 200 then
              -- Update right panel size
              current_layouts[1].size = width
            end

            -- Bottom panel windows have significant height
            if height > 3 and height < 50 then
              -- Update bottom panel size (check position)
              local row = vim.api.nvim_win_get_position(win)[1]
              local total_height = vim.o.lines
              if row > total_height / 2 then
                current_layouts[2].size = height
              end
            end
          end
        end
      end

      DapPersistence.save_layout_sizes(current_layouts)
    end

    -- Hook into window resize events for DAP UI windows
    vim.api.nvim_create_autocmd("WinResized", {
      callback = function()
        -- Check if any DAP UI window was resized
        local resized_wins = vim.v.event and vim.v.event.windows or {}
        for _, win in ipairs(resized_wins) do
          if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            local ft = vim.bo[buf].filetype
            if ft and ft:match("^dapui_") then
              -- Debounce the save operation
              vim.defer_fn(save_layout_sizes, 500)
              return
            end
          end
        end
      end,
    })

    -- Also save on VimLeavePre in case resize event was missed
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        save_layout_sizes()
      end,
    })

    -- listeners para abrir/cerrar automáticamente
    dap.listeners.after.event_initialized["dapui_config"] = function()
      -- Open dap-ui (layouts already configured in setup)
      dapui.open()
      -- Restore watches after UI is open
      restore_watches()
    end

    -- Function to save current watches from dap-ui to persistence
    local function save_watches_from_ui()
      local ok, watches_data = pcall(function()
        return dapui.elements.watches.get()
      end)
      if ok and watches_data then
        local expressions = {}
        for _, w in ipairs(watches_data) do
          if w.expression and w.expression ~= "" then
            table.insert(expressions, w.expression)
          end
        end
        -- Save even if empty (user deleted all watches)
        DapPersistence.save_watches(expressions)
      end
    end

    dap.listeners.before.event_terminated["dapui_config"] = function()
      save_watches_from_ui()
      save_layout_sizes()
      dapui.close()
      -- Cerrar también la ventana de logs remotos
      if _G.close_remote_output_window then
        _G.close_remote_output_window()
      end
    end

    dap.listeners.before.event_exited["dapui_config"] = function()
      save_watches_from_ui()
      save_layout_sizes()
      dapui.close()
      -- Cerrar también la ventana de logs remotos
      if _G.close_remote_output_window then
        _G.close_remote_output_window()
      end
    end

    -- User commands for watch management
    vim.api.nvim_create_user_command("DapWatchAdd", function(cmd_opts)
      local expr = cmd_opts.args
      if expr and expr ~= "" then
        DapPersistence.add_watch(expr)
        pcall(function()
          require("dapui").elements.watches.add(expr)
        end)
        vim.notify("Watch añadido y guardado: " .. expr, vim.log.levels.INFO)
      else
        vim.ui.input({ prompt = "Expresión a observar: " }, function(input)
          if input and input ~= "" then
            DapPersistence.add_watch(input)
            pcall(function()
              require("dapui").elements.watches.add(input)
            end)
            vim.notify("Watch añadido y guardado: " .. input, vim.log.levels.INFO)
          end
        end)
      end
    end, { nargs = "?", desc = "Add and persist a watch expression" })

    vim.api.nvim_create_user_command("DapWatchRemove", function(cmd_opts)
      local expr = cmd_opts.args
      if expr and expr ~= "" then
        DapPersistence.remove_watch(expr)
        vim.notify("Watch eliminado: " .. expr, vim.log.levels.INFO)
      else
        local watches = DapPersistence.get_watches()
        if #watches == 0 then
          vim.notify("No hay watches guardados", vim.log.levels.INFO)
          return
        end
        vim.ui.select(watches, { prompt = "Selecciona watch a eliminar:" }, function(selected)
          if selected then
            DapPersistence.remove_watch(selected)
            vim.notify("Watch eliminado: " .. selected, vim.log.levels.INFO)
          end
        end)
      end
    end, { nargs = "?", desc = "Remove a persisted watch expression" })

    vim.api.nvim_create_user_command("DapWatchList", function()
      local watches = DapPersistence.get_watches()
      if #watches == 0 then
        vim.notify("No hay watches guardados", vim.log.levels.INFO)
      else
        vim.notify("Watches guardados:\n  - " .. table.concat(watches, "\n  - "), vim.log.levels.INFO)
      end
    end, { desc = "List all persisted watch expressions" })

    vim.api.nvim_create_user_command("DapWatchClear", function()
      DapPersistence.clear_watches()
      vim.notify("Todos los watches han sido eliminados", vim.log.levels.INFO)
    end, { desc = "Clear all persisted watch expressions" })

    vim.api.nvim_create_user_command("DapLayoutReset", function()
      -- Reset to default layouts
      DapPersistence.save_layout_sizes(default_layouts)
      vim.notify("Layout restaurado a valores por defecto. Reinicia la sesión de debug.", vim.log.levels.INFO)
    end, { desc = "Reset DAP UI layout to defaults" })
  end,
}
