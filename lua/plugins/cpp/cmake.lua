--[[
================================================================================
CMAKE TOOLS CONFIGURATION
================================================================================
Integrates CMake build system with Neovim.
Features:
  - Parallel builds (uses all available CPU cores)
  - CMakeDeploy command for deployment
  - Automatic deployment before remote debugging
  - Build management (CMakeBuild, CMakeDebug, etc.)
Plugin: Civitasv/cmake-tools.nvim
================================================================================
--]]

return {
  "Civitasv/cmake-tools.nvim",
  commit = "d6fa30479c5f392f6f80b4b2e542f91155b289a8",
  config = function()
    -- Configure CMake tools with parallel builds
    require("cmake-tools").setup({
      cmake_build_args = { "-j", tostring(vim.loop.cpu_info() and #vim.loop.cpu_info() or 4) },
    })

    -- Create CMakeDeploy command
    vim.api.nvim_create_user_command("CMakeDeploy", function()
      vim.cmd("CMakeBuild deploy")
    end, {})

    -- Automatically run CMakeDeploy before remote debugging
    -- This listener triggers when attaching to a debug session
    local dap = require("dap")
    dap.listeners.before.attach["cmake_deploy"] = function(session, body)
      -- Only for remote debugging (adjust condition based on your configuration)
      if body and body.name and body.name:lower():find("remote") then
        vim.cmd("CMakeDeploy")
      end
    end
  end,
}
