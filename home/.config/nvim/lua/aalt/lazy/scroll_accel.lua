return {
	{
		"rhysd/accelerated-jk",
		event = "VeryLazy",
		config = function()
			vim.keymap.set(
				"n",
				"j",
				"<Plug>(accelerated_jk_j)",
				{ desc = "Down (accelerated)", remap = true, silent = true }
			)
			vim.keymap.set(
				"n",
				"k",
				"<Plug>(accelerated_jk_k)",
				{ desc = "Up (accelerated)", remap = true, silent = true }
			)
			vim.keymap.set(
				"n",
				"<Down>",
				"<Plug>(accelerated_jk_j)",
				{ desc = "Down (accelerated)", remap = true, silent = true }
			)
			vim.keymap.set(
				"n",
				"<Up>",
				"<Plug>(accelerated_jk_k)",
				{ desc = "Up (accelerated)", remap = true, silent = true }
			)
		end,
	},
}
