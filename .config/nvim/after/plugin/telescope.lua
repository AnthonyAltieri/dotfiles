local status, telescope = pcall(require, "telescope")
if (not status) then return end

local builtin = require('telescope.builtin')
local actions = require('telescope.actions')
require("telescope").load_extension("undo")

vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
vim.keymap.set('n', '<leader>pg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>pb', builtin.buffers, {})
vim.keymap.set('n', '<leader>ph', builtin.help_tags, {})
vim.keymap.set('n', '<C-p>', builtin.git_files, {})
vim.keymap.set('n', '<leader>ps', function()
	builtin.grep_string({ search = vim.fn.input("Grep > ") })
end)
vim.keymap.set('n', '<leader>pr', builtin.resume, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>pu", "<cmd>Telescope undo<cr>")


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


-- REFERENCE
-- undo = {
--   mappings = {
--     i = {
--       ["<cr>"] = require("telescope-undo.actions").yank_additions,
--       ["<S-cr>"] = require("telescope-undo.actions").yank_deletions,
--       ["<C-cr>"] = require("telescope-undo.actions").restore,
--       -- alternative defaults, for users whose terminals do questionable things with modified <cr>
--       ["<C-y>"] = require("telescope-undo.actions").yank_deletions,
--       ["<C-r>"] = require("telescope-undo.actions").restore,
--     },
--     n = {
--       ["y"] = require("telescope-undo.actions").yank_additions,
--       ["Y"] = require("telescope-undo.actions").yank_deletions,
--       ["u"] = require("telescope-undo.actions").restore,
--     },
--   },
-- },
