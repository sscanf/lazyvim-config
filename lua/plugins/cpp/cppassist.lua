return {
  "Kohirus/cppassist.nvim",
  ft = { "h", "cpp", "hpp", "c", "cc", "cxx" },
  config = function()
    require("cppassist").setup()
  end,
}
