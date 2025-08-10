return {
  "Civitas/cmake-tools.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "mfussenegger/nvim-dap" },
  opts = function()
    -- AÑADE ESTE PRINT
    print("✅ Cargando configuración personalizada para cmake-tools.nvim")
    return {
      dap = {
        configuration = {
          type = "cppdbg",
          MIMode = "gdb",
          setupCommands = {
            {
              description = "Enable GDB pretty printing via .gdbinit",
              text = "source ~/.gdbinit",
              ignoreFailures = false,
            },
          },
        },
      },
    }
  end,
  commit = "d6fa30479c5f392f6f80b4b2e542f91155b289a8",
  url = 'git@github.com/Civitasv/cmake-tools.nvim.git'
}
