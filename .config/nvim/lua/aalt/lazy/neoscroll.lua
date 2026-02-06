return {
	{
		"karb94/neoscroll.nvim",
		event = "VeryLazy",
		config = function()
			local neoscroll = require("neoscroll")

			neoscroll.setup({
				hide_cursor = true,
				stop_eof = true,
				respect_scrolloff = true,
				easing_function = "quadratic",
				post_hook = function(info)
					if type(info) == "table" and info.center == true then
						vim.cmd("normal! zz")
					end
				end,
			})

			vim.keymap.set("n", "<C-u>", function()
				neoscroll.ctrl_u({ duration = 250, info = { center = true } })
			end, { desc = "Scroll up (smooth)" })

			vim.keymap.set("n", "<C-d>", function()
				neoscroll.ctrl_d({ duration = 250, info = { center = true } })
			end, { desc = "Scroll down (smooth)" })
		end,
	},
}
