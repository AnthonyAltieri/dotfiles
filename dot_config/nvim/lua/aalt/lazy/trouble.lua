return {
	{
		"folke/trouble.nvim",
		cmd = "Trouble",
		keys = {
			{ "<leader>tt", function() require("trouble").toggle() end, desc = "Diagnostics (Trouble)" },
			{ "]t", function() require("trouble").next({ skip_groups = true, jump = true }) end, desc = "Next Trouble Diagnostic" },
			{ "[t", function() require("trouble").previous({ skip_groups = true, jump = true }) end, desc = "Previous Trouble Diagnostic" },
		},
		opts = {
			icons = false,
		},
	},
}
