return {
  "Kohirus/cppassist.nvim",
  opt = true,
  ft = { "h", "cpp", "hpp", "c", "cc", "cxx" },
  config = function()
    require("cppassist").setup()
  end,
}
