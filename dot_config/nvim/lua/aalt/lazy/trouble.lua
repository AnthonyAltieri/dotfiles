return {
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		keys = {
			{ "<leader>tt", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
			{ "]t", function() require("trouble").next({ jump = true }) end, desc = "Next Trouble Diagnostic" },
			{ "[t", function() require("trouble").prev({ jump = true }) end, desc = "Previous Trouble Diagnostic" },
		},
		opts = {
			icons = false,
		},
	},
}
