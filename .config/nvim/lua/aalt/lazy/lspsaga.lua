return {
	"nvimdev/lspsaga.nvim",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
	event = "LspAttach",
	opts = {
		lightbulb = {
			enable = false,
		},
		symbol_in_winbar = {
			enable = true,
		},
		hover = {
			max_width = 0.6,
			max_height = 0.6,
		},
	},
}
