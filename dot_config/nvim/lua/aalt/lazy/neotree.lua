return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	lazy = false,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-tree/nvim-web-devicons",
		{ "MunifTanjim/nui.nvim", commit = "7cd18e7" },
	},
	config = function()
		require("neo-tree").setup({
			close_if_last_window = true,
			filesystem = {
				hijack_netrw_behavior = "disabled",
				follow_current_file = {
					enabled = true,
				},
				filtered_items = {
					visible = true,
					hide_dotfiles = false,
					hide_gitignored = false,
				},
			},
			window = {
				width = 40,
				mappings = {
					["/"] = function(state)
						local cwd = state.path
						require("fzf-lua").files({
							cwd = cwd,
							hidden = true,
							git_icons = false,
							file_icons = "mini",
							actions = {
								["default"] = function(selected)
									if not selected or #selected == 0 then
										return
									end
									local file = require("fzf-lua").path.entry_to_file(selected[1], { cwd = cwd })
									local path = file.path
									if not vim.startswith(path, "/") then
										path = cwd .. "/" .. path
									end
									vim.cmd("Neotree reveal_file=" .. vim.fn.fnameescape(path))
								end,
							},
						})
					end,
					["<M-.>"] = function()
						vim.cmd("vertical resize +2")
					end,
					["<M-,>"] = function()
						vim.cmd("vertical resize -2")
					end,
					["<M-=>"] = function()
						vim.cmd("wincmd =")
					end,
				},
			},
		})

		-- Auto-open neo-tree when launching nvim with no args or with a directory
		vim.api.nvim_create_autocmd("VimEnter", {
			callback = function()
				local arg = vim.fn.argv(0)
				if vim.fn.argc() == 0 or (arg ~= "" and vim.fn.isdirectory(arg) == 1) then
					vim.cmd("Neotree show")
					vim.cmd("wincmd l")
				end
			end,
		})
	end,
}
