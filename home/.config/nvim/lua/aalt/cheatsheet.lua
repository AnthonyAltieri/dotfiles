-- Shared cheatsheet data used by both the telescope picker and the dashboard
return {
	-- Search
	{ cat = "Search", key = "<C-p>", desc = "Quick Open (files)" },
	{ cat = "Search", key = "<leader>fp", desc = "Find all files" },
	{ cat = "Search", key = "<M-p>", desc = "Live grep" },
	{ cat = "Search", key = "<leader>fw", desc = "Grep current word" },
	{ cat = "Search", key = "<leader>f.", desc = "Recent files" },
	{ cat = "Search", key = "<leader>fh", desc = "Help tags" },
	{ cat = "Search", key = "<leader>fk", desc = "Keymaps" },

	-- File Tree
	{ cat = "File Tree", key = "<C-\\>", desc = "Toggle file tree" },
	{ cat = "File Tree", key = "<leader>pv", desc = "Focus tree at current file" },

	-- Go To
	{ cat = "Go To", key = "gd", desc = "Go to definition" },
	{ cat = "Go To", key = "gr", desc = "Go to references" },
	{ cat = "Go To", key = "gI", desc = "Go to implementation" },
	{ cat = "Go To", key = "gD", desc = "Go to declaration" },

	-- Hover & Documentation
	{ cat = "Hover/Docs", key = "<M-v>", desc = "Hover documentation (normal mode)" },
	{ cat = "Hover/Docs", key = "<M-v>", desc = "Signature help (insert mode)" },
	{ cat = "Hover/Docs", key = "<leader>D", desc = "Type definition" },
	{ cat = "Hover/Docs", key = "<leader>ds", desc = "Document symbols" },
	{ cat = "Hover/Docs", key = "<leader>ws", desc = "Workspace symbols" },

	-- Harpoon
	{ cat = "Harpoon", key = "<leader>ha", desc = "Add file to harpoon" },
	{ cat = "Harpoon", key = "<leader>hr", desc = "Remove file from harpoon" },
	{ cat = "Harpoon", key = "<M-e>", desc = "Harpoon menu" },
	{ cat = "Harpoon", key = "<M-j>", desc = "Jump to harpoon slot 1" },
	{ cat = "Harpoon", key = "<M-k>", desc = "Jump to harpoon slot 2" },
	{ cat = "Harpoon", key = "<M-l>", desc = "Jump to harpoon slot 3" },
	{ cat = "Harpoon", key = "<M-;>", desc = "Jump to harpoon slot 4" },
	{ cat = "Harpoon", key = "<M-'>", desc = "Jump to harpoon slot 5" },

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
}
