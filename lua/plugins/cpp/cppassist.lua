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

    -- Patch RemoveLeadingKeywords to handle custom macros like ZO_EXPORTABLE
    local func = require("cppassist.func")
    local original_remove = func.RemoveLeadingKeywords
    func.RemoveLeadingKeywords = function(funcstr)
      -- Remove custom export/visibility macros (add your macros here)
      local custom_macros = {
        "ZO_EXPORTABLE",
        "ZO_EXPORT",
        "DLL_EXPORT",
        "API_EXPORT",
        "__declspec%([^%)]+%)",  -- Windows __declspec(dllexport)
      }
      for _, macro in ipairs(custom_macros) do
        funcstr = string.gsub(funcstr, "^" .. macro .. "%s+", "", 1)
      end
      return original_remove(funcstr)
    end
  end,
}
