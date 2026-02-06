-- Set highlight on search, but clear on pressing <Esc> in normal mode
vim.opt.hlsearch = true
vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<CR>")

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Go to previous [D]iagnostic message" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Go to next [D]iagnostic message" })
vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic [E]rror messages" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Open diagnostic [Q]uickfix list" })

-- Project
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex, { desc = "Open [P]roject view" })

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
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

vim.keymap.set("n", "<C-\\>", "<cmd>Neotree toggle<CR>")

-- Cheat sheet (loads telescope on demand)
_G.show_cheatsheet = function()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values

	local commands = {
		-- Search
		{ cat = "Search", key = "<C-p>", desc = "Quick Open (files)" },
		{ cat = "Search", key = "<leader>fp", desc = "Find all files" },
		{ cat = "Search", key = "<M-g>", desc = "Live grep" },
		{ cat = "Search", key = "<leader>fw", desc = "Grep current word" },
		{ cat = "Search", key = "<leader>f.", desc = "Recent files" },
		{ cat = "Search", key = "<leader>fh", desc = "Help tags" },
		{ cat = "Search", key = "<leader>fk", desc = "Keymaps" },

		-- Hover & Documentation
		{ cat = "Hover/Docs", key = "<M-v>", desc = "Hover documentation (normal mode)" },
		{ cat = "Hover/Docs", key = "<M-v>", desc = "Signature help (insert mode)" },
		{ cat = "Hover/Docs", key = "<leader>D", desc = "Type definition" },
		{ cat = "Hover/Docs", key = "<leader>ds", desc = "Document symbols" },
		{ cat = "Hover/Docs", key = "<leader>ws", desc = "Workspace symbols" },

		-- Go To
		{ cat = "Go To", key = "gd", desc = "Go to definition" },
		{ cat = "Go To", key = "gr", desc = "Go to references" },
		{ cat = "Go To", key = "gI", desc = "Go to implementation" },
		{ cat = "Go To", key = "gD", desc = "Go to declaration" },

		-- LSP Actions
		{ cat = "LSP Actions", key = "<leader>rn", desc = "Rename symbol" },
		{ cat = "LSP Actions", key = "<leader>.", desc = "Code action" },
		{ cat = "LSP Actions", key = "<leader>fb", desc = "Format buffer" },

		-- Diagnostics
		{ cat = "Diagnostics", key = "<leader>e", desc = "Show diagnostic float" },
		{ cat = "Diagnostics", key = "[d", desc = "Previous diagnostic" },
		{ cat = "Diagnostics", key = "]d", desc = "Next diagnostic" },
		{ cat = "Diagnostics", key = "<leader>q", desc = "Diagnostic quickfix list" },
		{ cat = "Diagnostics", key = "<leader>tt", desc = "Toggle Trouble" },

		-- Harpoon
		{ cat = "Harpoon", key = "<leader>a", desc = "Add file to harpoon" },
		{ cat = "Harpoon", key = "<M-e>", desc = "Harpoon menu" },
		{ cat = "Harpoon", key = "<space>1", desc = "Jump to harpoon file 1" },
		{ cat = "Harpoon", key = "<space>2", desc = "Jump to harpoon file 2" },
		{ cat = "Harpoon", key = "<space>3", desc = "Jump to harpoon file 3" },
		{ cat = "Harpoon", key = "<space>4", desc = "Jump to harpoon file 4" },
		{ cat = "Harpoon", key = "<space>5", desc = "Jump to harpoon file 5" },
	}

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
