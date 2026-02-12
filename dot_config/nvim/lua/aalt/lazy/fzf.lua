local function get_launch_root()
	local arg = vim.fn.argv(0)
	if arg and arg ~= "" then
		local path = vim.fn.fnamemodify(arg, ":p")
		if vim.fn.isdirectory(path) == 1 then
			return path
		end
		return vim.fn.fnamemodify(path, ":h")
	end
	return vim.fn.getcwd()
end

return {
	{
		"ibhagwan/fzf-lua",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = "FzfLua",
		keys = {
			{
				"<C-p>",
				mode = { "n", "i" },
				desc = "Quick Open (fzf-lua)",
				function()
					if vim.fn.executable("fzf") ~= 1 then
						vim.notify("Missing `fzf` binary. Install with: brew install fzf", vim.log.levels.WARN)
						return
					end

					vim.cmd("stopinsert")

					local cmd =
						[[(rg --files --hidden --glob '!**/.git/**' --glob '!**/.gitignore' ; rg --files --hidden --no-ignore --glob '.env*' --glob '!**/.git/**') | awk '!seen[$0]++']]

					require("fzf-lua").files({
						cmd = cmd,
						cwd = get_launch_root(),
						hidden = true,
						git_icons = false,
						file_icons = "mini",
					})
				end,
			},
		},
		opts = {
			defaults = {
				git_icons = false,
				file_icons = "mini",
			},
			winopts = {
				height = 0.6,
				width = 0.7,
				preview = { hidden = "hidden" },
			},
			fzf_opts = {
				["--layout"] = "reverse",
			},
		},
	},
}
