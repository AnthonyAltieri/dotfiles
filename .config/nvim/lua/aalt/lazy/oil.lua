return {
	{
		"stevearc/oil.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		lazy = false, -- Load early to hijack directory buffers (netrw replacement)
		keys = {
			{ "-", "<CMD>Oil<CR>", desc = "Open parent dir in current window (Oil)" },
			{ "<space>-", function() require("oil").toggle_float() end, desc = "Open parent dir in floating window (Oil)" },
		},
		config = function()
			CustomOilBar = function()
				local expanded = vim.fn.expand("%")
				local path = type(expanded) == "table" and expanded[1] or expanded
				path = path:gsub("oil://", "")

				return "  " .. vim.fn.fnamemodify(path, ":.")
			end

			require("oil").setup({
				columns = { "icon" },
				keymaps = {
					["<C-h>"] = false,
					["<C-l>"] = false,
					["<C-k>"] = false,
					["<C-j>"] = false,
					["<M-h>"] = "actions.select_split",
					["<C-p>"] = false,
					["<M-p>"] = "actions.preview",
					["<M-/>"] = function()
						if _G.show_cheatsheet then
							_G.show_cheatsheet()
						end
					end,
				},
				win_options = {
					winbar = "%{v:lua.CustomOilBar()}",
				},
				view_options = {
					show_hidden = true,
					is_always_hidden = function(name, _)
						local folder_skip = { "dev-tools.locks", "dune.lock", "_build" }
						return vim.tbl_contains(folder_skip, name)
					end,
				},
			})
		end,
	},
}
