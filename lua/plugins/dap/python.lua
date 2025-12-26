--[[
================================================================================
PYTHON DEBUG ADAPTER CONFIGURATION
================================================================================
Configures DAP for Python debugging using debugpy.
Features:
  - Python debug adapter using debugpy
  - Environment variables support (DEBUG_EXEC, DEBUG_ARGS)
  - Project-specific DAP configuration loading (.nvim/dap.lua)
  - Automatic pythonPath resolution
Plugin: mfussenegger/nvim-dap-python
================================================================================
--]]

return {
  "mfussenegger/nvim-dap",
  dependencies = { "mfussenegger/nvim-dap-python" },
  config = function()
    local dap = require("dap")

    -- Configure Python adapter
    dap.adapters.python = {
      type = "executable",
      command = "python3",
      args = { "-m", "debugpy.adapter" },
    }

    -- Debug session configuration
    dap.configurations.python = {
      {
        type = "python",
        request = "launch",
        name = "Debug Fixed File",
        program = os.getenv("DEBUG_EXEC") or "${file}",
        args = os.getenv("DEBUG_ARGS") and vim.split(os.getenv("DEBUG_ARGS"), " ") or {},
        pythonPath = function()
          return "python"
        end,
      },
    }

    -- Load project-specific DAP configuration if it exists
    local function load_project_dap_config()
      local project_root = vim.fn.getcwd()
      local dap_config_file = project_root .. "/.nvim/dap.lua"
      if vim.fn.filereadable(dap_config_file) == 1 then
        local ok, err = pcall(dofile, dap_config_file)
        if not ok then
          vim.notify("Error loading project dap config: " .. err, vim.log.levels.ERROR)
        else
          vim.notify("Loaded project-specific DAP config", vim.log.levels.INFO)
        end
      end
    end

    -- Call function when opening a project
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = load_project_dap_config,
    })
  end,
}
