return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	as = "harpoon",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = {
		{ "<leader>a", function() require("harpoon"):list():add() end, desc = "[A] Append (Harpoon)" },
		{ "<m-e>", function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end, desc = "Harpoon menu" },
		{ "<space>1", function() require("harpoon"):list():select(1) end, desc = "Harpoon 1" },
		{ "<space>2", function() require("harpoon"):list():select(2) end, desc = "Harpoon 2" },
		{ "<space>3", function() require("harpoon"):list():select(3) end, desc = "Harpoon 3" },
		{ "<space>4", function() require("harpoon"):list():select(4) end, desc = "Harpoon 4" },
		{ "<space>5", function() require("harpoon"):list():select(5) end, desc = "Harpoon 5" },
	},
	config = function()
		require("harpoon"):setup()
	end,
}
