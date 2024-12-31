return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	as = "harpoon",
	dependencies = { "nvim-lua/plenary.nvim" },
	config = function()
		local harpoon = require("harpoon")

		harpoon:setup()

		vim.keymap.set("n", "<leader>a", function()
			harpoon:list():append()
		end, { desc = "[A] Append (Harpoon)" })

		vim.keymap.set("n", "<m-h>", function()
			harpoon.ui:toggle_quick_menu(harpoon:list())
		end)

		-- Set <space>1..<space>5 be my shortcuts to moving to the files
		for _, idx in ipairs({ 1, 2, 3, 4, 5 }) do
			vim.keymap.set("n", string.format("<space>%d", idx), function()
				harpoon:list():select(idx)
			end)
		end
	end,
}
