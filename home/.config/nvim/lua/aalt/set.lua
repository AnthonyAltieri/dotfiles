-- Set highlight on search, but clear on pressing <Esc> in normal mode
vim.opt.hlsearch = true
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous [D]iagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next [D]iagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic [E]rror messages" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })

-- Project
vim.keymap.set("n", "<leader>pv", "<cmd>Neotree focus reveal<CR>", { desc = "Focus file tree at current file" })

-- Move selected lines in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Keep cursor in place when moving lines up
vim.keymap.set("n", "J", "mzJ`z")

-- Keep screen in center while navigating with <C-d> and <C-u>
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Keep screen in center while navigating search results
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Replace currently selected text with default register without yanking it
vim.keymap.set("x", "<leader>p", [["_dP]])

-- Yank to operating system clipboard
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]])
vim.keymap.set("n", "<leader>Y", [["+Y]])

vim.keymap.set({ "n", "v" }, "<leader>d", [["_d]])

vim.keymap.set("n", "Q", "<nop>")

-- Window resize
vim.keymap.set("n", "<M-.>", "<cmd>vertical resize +2<CR>", { desc = "Increase window width" })
vim.keymap.set("n", "<M-,>", "<cmd>vertical resize -2<CR>", { desc = "Decrease window width" })
vim.keymap.set("n", "<M-=>", "<C-w>=", { desc = "Equalize window sizes" })
vim.keymap.set("n", "q:", "<nop>")
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

vim.keymap.set("n", "<C-\\>", "<cmd>Neotree toggle reveal<CR>", { desc = "Toggle file tree" })

-- Cheat sheet (loads telescope on demand)
_G.show_cheatsheet = function()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local commands = require("aalt.cheatsheet")

	pickers
		.new({}, {
			prompt_title = "Cheat Sheet",
			finder = finders.new_table({
				results = commands,
				entry_maker = function(entry)
					local display = string.format("%-12s │ %-15s │ %s", entry.cat, entry.key, entry.desc)
					return {
						value = entry,
						display = display,
						ordinal = entry.cat .. " " .. entry.key .. " " .. entry.desc,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
		})
		:find()
end

vim.keymap.set("n", "<M-/>", _G.show_cheatsheet, { desc = "Show cheat sheet" })
