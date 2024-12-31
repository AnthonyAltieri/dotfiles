return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
		"MunifTanjim/nui.nvim",
		-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
	},
	config = function()
		-- By default <C-\\> is set to toggle the neotree window
		vim.keymap.set("n", "<leader>\\", "<Cmd>Neotree reveal<CR>", { desc = "Show Current File (Neotree)" })

		require("neo-tree").setup({
			close_if_last_window = true,
			filesystem = {
				filtered_items = {
					hide_hidden = false,
				},
				hijack_netrw_behavior = "disabled",
			},
		})
	end,
}
