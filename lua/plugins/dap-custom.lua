-- Fichero de configuración para "mfussenegger/nvim-dap" (versión mínima)

return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui" }, -- Mantenemos la UI para consistencia

  config = function()
    local dap = require("dap")

    -- 1. Forzamos el uso de la terminal de Neovim
    -- Esto es lo más importante.
    require("dap").defaults.fallback.terminal_win_cmd = "vsplit | terminal"

    -- 2. Definimos el adaptador de forma directa
    dap.adapters.cppdbg = {
      id = "cppdbg",
      type = "executable",
      -- Asegúrate de que esta ruta sea correcta para tu sistema
      command = "/home/oscar/.local/share/nvim/mason/bin/OpenDebugAD7",
    }

    -- 3. Creamos una única configuración de lanzamiento, muy simple
    dap.configurations.cpp = {
      {
        name = "Prueba de Lanzamiento Mínimo",
        type = "cppdbg",
        request = "launch",
        -- Rutas directas para evitar cualquier problema con variables de entorno
        program = "/home/oscar/zone-core/zotest/out/Debug/manager/zotest",
        cwd = "/home/oscar/zone-core/zotest/out/Debug/manager",

        MIMode = "gdb",
        miDebuggerPath = "/usr/bin/gdb",

        -- Esta opción es clave para que el programa se detenga al inicio
        stopAtEntry = true,
        externalConsole = true,
      },
    }

    -- Hacemos que la misma configuración sirva para archivos C
    dap.configurations.c = dap.configurations.cpp

    vim.notify("Configuración MÍNIMA de DAP cargada para la prueba.", vim.log.levels.WARN)
  end,
}
