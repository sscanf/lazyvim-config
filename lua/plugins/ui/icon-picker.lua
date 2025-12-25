return {
  "ziontee113/icon-picker.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    -- Verifica si el módulo se carga correctamente
    local ok, icon_picker = pcall(require, "icon-picker")
    if not ok then
      vim.notify("Error cargando icon-picker: " .. icon_picker, vim.log.levels.ERROR)
      return
    end

    icon_picker.setup({
      disable_legacy_commands = true,
      show_nerd_font_icons = true,
      use_telescope = false, -- Usar el selector interno
      picker_window = {
        mappings = {
          next_item = "<C-Tab>",
          prev_item = "<S-Tab>",
          accept_icon = "<CR>",
          close = "<Esc>",
          delete_icon = "<Del>",
        },
        width = 80,
        height = 20,
        border = "rounded",
      },
    })

    -- Mapeos de teclado
    vim.keymap.set({ "i", "n" }, "<C-i>", "<cmd>IconPickerInsert<cr>")
    vim.keymap.set("n", "<leader>ip", "<cmd>IconPickerNormal<cr>")
    vim.notify("Icon Picker configurado correctamente")
  end,
}
