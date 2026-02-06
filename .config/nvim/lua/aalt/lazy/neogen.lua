return {
	"danymat/neogen",
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"L3MON4D3/LuaSnip",
	},
	cmd = "Neogen",
	keys = {
		{ "<leader>nf", function() require("neogen").generate({ type = "func" }) end, desc = "Generate function doc" },
		{ "<leader>nt", function() require("neogen").generate({ type = "type" }) end, desc = "Generate type doc" },
	},
	opts = {
		snippet_engine = "luasnip",
	},
}
