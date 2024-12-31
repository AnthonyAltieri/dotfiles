return {
	{
		"folke/trouble.nvim",
		config = function()
			require("trouble").setup({
				icons = false,
			})

			vim.keymap.set("n", "<leader>tt", function()
				require("trouble").toggle()
			end, { desc = "Diagnostics (Trouble)" })

			vim.keymap.set("n", "]t", function()
				require("trouble").next({ skip_groups = true, jump = true })
			end, { desc = "Previous Trouble Diagnostic (Trouble)" })

			vim.keymap.set("n", "[t", function()
				require("trouble").previous({ skip_groups = true, jump = true })
			end, { desc = "Next Trouble Diagnostic (Trouble)" })
		end,
	},
}
