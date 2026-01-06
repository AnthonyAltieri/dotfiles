return {
	-- "gc" to comment visual regions/lines
	{ "numToStr/Comment.nvim", event = "VeryLazy", opts = {} },
	-- Highlight todo, notes, etc in comments
	{
		"folke/todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = { signs = false },
	},
}
