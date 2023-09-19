local status, telescope = pcall(require, "telescope")
if (not status) then return end
local actions = require('telescope.actions')
local builtin = require('telescope.builtin')

telescope.setup {
  defaults = {
    mappings = {
      n = {
        ["q"] = actions.close
      },
      i = {
        ["<esc>"] = actions.close,
      }
    },
  },
}

vim.keymap.set('n', '<C-p>', builtin.git_files, {})
vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
vim.keymap.set('n', '<leader>ps', function()
  builtin.live_grep()
end)
