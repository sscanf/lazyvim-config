-- Debug log capture system for DAP
-- Captures debug output and provides keybindings to show/hide logs
return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require("dap")

    -- Use a table to store the log buffer
    local debug_logs = {
      buffer = nil,
    }

    -- Function to create/get log buffer
    local function get_log_buffer()
      if not debug_logs.buffer or not vim.api.nvim_buf_is_valid(debug_logs.buffer) then
        debug_logs.buffer = vim.api.nvim_create_buf(false, true) -- Create unlisted buffer
        vim.api.nvim_buf_set_name(debug_logs.buffer, "Debug-Logs")
        vim.api.nvim_buf_set_option(debug_logs.buffer, "filetype", "log")
      end
      return debug_logs.buffer
    end

    -- Configure listener to capture output
    dap.listeners.before["event_output"]["log_output"] = function(_, body)
      local buf = get_log_buffer()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        -- Clear buffer before adding new lines
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        -- Use vim.schedule to avoid threading issues
        vim.schedule(function()
          local lines = vim.split(body.output, "\n")
          vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
        end)
      end
    end

    -- Configure listener to show buffer on termination
    dap.listeners.after["event_terminated"]["show_logs"] = function()
      local buf = get_log_buffer()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.schedule(function()
          vim.cmd("split | buffer " .. buf)
        end)
      end
    end

    -- Shortcut to open logs
    vim.keymap.set("n", "<leader>dl", function()
      local buf = get_log_buffer()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local win_id = vim.fn.bufwinid(buf)
        if win_id ~= -1 then
          vim.cmd("hide")
        end
        vim.cmd("split | buffer " .. buf)
      else
        vim.notify("No logs available", vim.log.levels.WARN)
      end
    end, { desc = "Show debug logs" })

    -- Shortcut to close logs
    vim.keymap.set("n", "<leader>dh", function()
      local buf = get_log_buffer()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local win_id = vim.fn.bufwinid(buf)
        if win_id ~= -1 then
          vim.cmd("hide")
        end
      else
        vim.notify("No logs available", vim.log.levels.WARN)
      end
    end, { desc = "Hide debug logs" })
  end,
}
