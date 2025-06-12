-- ~/.config/nvim/lua/plugins/dap-custom.lua

return {
  "mfussenegger/nvim-dap",
  dependencies = { "rcarriga/nvim-dap-ui", "nvim-neotest/nvim-nio" },

  config = function()
    local dap = require("dap")

    vim.api.nvim_set_hl(0, "DapBreakpointColor", { fg = "#ff00ef" }) -- Un azul claro

    -- 2. Usamos vim.fn.sign_define() para cambiar los símbolos
    vim.fn.sign_define("DapBreakpoint", {
      text = "●", -- El símbolo del punto
      texthl = "DapBreakpointColor", -- El grupo de color que acabamos de definir
      linehl = "",
      numhl = "DapBreakpointColor", -- El número de línea también tendrá el color
    })
    vim.fn.sign_define("DapBreakpointCondition", {
      text = "●", -- También para breakpoints condicionales
      texthl = "DapBreakpointColor",
      linehl = "",
      numhl = "DapBreakpointColor",
    })

    -- Opcional: Icono para la línea de ejecución parada
    vim.api.nvim_set_hl(0, "DapStoppedColor", { fg = "#98c379" }) -- Un verde
    vim.fn.sign_define("DapStopped", {
      text = "➜",
      texthl = "DapStoppedColor",
      linehl = "DapStoppedLine",
      numhl = "DapStoppedColor",
    })

    -- 1. CONFIGURACIÓN DE LA SESIÓN REMOTA
    -- ... (esta parte no cambia) ...
    local remote_host = os.getenv("REMOTE_HOST")
    local gdb_path = os.getenv("REMOTE_DEBUG_GDB_PATH")
    local deploy_base = os.getenv("DEPLOY_REMOTE_BASE_PATH")
    local remote_bin = os.getenv("REMOTE_BINARY_NAME")

    if remote_host and gdb_path and deploy_base and remote_bin then
      local program_path = string.format("%s/usr/bin/%s", deploy_base, remote_bin)
      local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
      local remote_config = {
        name = "REMOTE DEBUG",
        type = "cppdbg",
        request = "launch",
        program = program_path,
        MIMode = "gdb",
        miDebuggerPath = gdb_path,
        miDebuggerServerAddress = remote_host .. ":" .. gdb_port,
        cwd = "${workspaceFolder}",
        stopOnEntry = true,
      }
      dap.configurations.c = { remote_config }
      dap.configurations.cpp = { remote_config }
    end

    -- ===================================================================
    -- MAPEADOS DE TECLADO CON LÓGICA DE ARGUMENTOS
    -- ===================================================================
    vim.keymap.set("n", "<leader>dR", function()
      local remote_configs = dap.configurations.cpp
      if not (remote_configs and remote_configs[1]) then
        vim.notify("❌ No se encontró la configuración remota de DAP.", vim.log.levels.ERROR)
        return
      end

      -- PASO 1: Pedir al usuario los argumentos de ejecución
      vim.ui.input({ prompt = "Argumentos de ejecución:" }, function(input_args)
        -- Si el usuario pulsa <esc>, input_args será nil.
        if not input_args then
          vim.notify("❌ Depuración cancelada.", vim.log.levels.WARN)
          return
        end

        -- PASO 2: Convertir el string de argumentos en una tabla
        -- vim.split divide el string por los espacios.
        local args_table = vim.split(input_args, " ", { trimempty = true })

        -- PASO 3: Clonar la configuración y añadirle los nuevos argumentos
        local launch_config = vim.deepcopy(remote_configs[1])
        launch_config.args = args_table

        -- PASO 4: Lanzar gdbserver en el servidor remoto
        vim.notify("🚀 Lanzando gdbserver remoto...", vim.log.levels.INFO)
        local ssh_port = os.getenv("REMOTE_SSH_PORT") or "2222"
        local gdb_port = os.getenv("REMOTE_GDBSERVER_PORT") or "10000"
        local program_path =
          string.format("%s/usr/bin/%s", os.getenv("DEPLOY_REMOTE_BASE_PATH"), os.getenv("REMOTE_BINARY_NAME"))

        -- ¡Importante! Añadimos los argumentos al comando de gdbserver también.
        local remote_command = string.format(
          "nohup gdbserver :%s %s %s > /tmp/gdbserver.log 2>&1 &",
          gdb_port,
          program_path,
          table.concat(args_table, " ") -- Unimos la tabla de argumentos en un string
        )

        local ssh_cmd_args = { --
          "sshpass",
          "-e",
          "ssh",
          "-p",
          ssh_port,
          "-o",
          "StrictHostKeyChecking=no", -- Opción para evitar prompts adicionales
          "root@" .. (os.getenv("REMOTE_HOST")),
          remote_command,
        }
        vim.fn.jobstart(ssh_cmd_args, { detach = true })

        -- PASO 5: Pausa y conexión del depurador
        vim.notify("⏳ Esperando 2 segundos...", vim.log.levels.WARN)
        vim.defer_fn(function()
          vim.notify("🛰️ Conectando el depurador local.", vim.log.levels.INFO)
          dap.run(launch_config) -- Usamos la configuración con los nuevos argumentos
        end, 500)
      end)
    end, { desc = "Debug Remote (con Argumentos)" })
    -- ... (otros mapeos estándar) ...
  end,
}
