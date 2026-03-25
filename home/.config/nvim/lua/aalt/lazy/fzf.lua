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

local FILE_IGNORE_GLOBS = {
	"!**/.git/**",
	"!**/.gitignore",
	"!**/.codex/worktrees/**",
}

local function build_rg_files_command(opts)
	opts = opts or {}

	local parts = { "rg", "--files", "--hidden" }
	if opts.no_ignore then
		table.insert(parts, "--no-ignore")
	end

	for _, glob in ipairs(FILE_IGNORE_GLOBS) do
		table.insert(parts, "--glob")
		table.insert(parts, vim.fn.shellescape(glob))
	end

	if opts.include_glob then
		table.insert(parts, "--glob")
		table.insert(parts, vim.fn.shellescape(opts.include_glob))
	end

	return table.concat(parts, " ")
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

					local cmd = string.format(
						"(%s ; %s) | awk '!seen[$0]++'",
						build_rg_files_command(),
						build_rg_files_command({ no_ignore = true, include_glob = ".env*" })
					)

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
