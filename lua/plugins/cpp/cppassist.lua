--[[
================================================================================
C++ DEVELOPMENT ASSISTANT
================================================================================
Provides C++ specific productivity tools.
Features:
  - Generate function implementations from declarations
  - Switch between source/header files
  - Implement functions in source files
  - Navigate between header and implementation
File types: C/C++ headers and source files
Plugin: Kohirus/cppassist.nvim
================================================================================
--]]

return {
  "Kohirus/cppassist.nvim",
  ft = { "h", "cpp", "hpp", "c", "cc", "cxx" },
  config = function()
    require("cppassist").setup()
  end,
}
