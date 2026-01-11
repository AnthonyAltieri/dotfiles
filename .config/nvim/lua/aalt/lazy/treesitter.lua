-- Workaround for nvim-treesitter Swift query bug
-- See: https://github.com/nvim-treesitter/nvim-treesitter/issues/7364
--
-- The Swift highlights.scm file references "try?" and "try!" as node types, but
-- the Swift treesitter grammar doesn't define them as valid nodes. This causes
-- Neovim 0.10.x to throw "Invalid node type" errors when opening Swift files.
--
-- This function patches the Swift highlights.scm file after nvim-treesitter
-- installs or updates, removing the invalid node type references.
local function patch_swift_highlights()
	local swift_highlights_path = vim.fn.stdpath("data")
		.. "/lazy/nvim-treesitter/queries/swift/highlights.scm"

	local file = io.open(swift_highlights_path, "r")
	if not file then
		return
	end

	local content = file:read("*all")
	file:close()

	-- Check if the file contains the problematic lines
	if not content:find('"try%?"') and not content:find('"try!"') then
		return
	end

	-- Remove the "try?" and "try!" lines from the operators list
	local patched_content = content:gsub('%s*"try%?"\n', "\n"):gsub('%s*"try!"\n', "\n")

	file = io.open(swift_highlights_path, "w")
	if not file then
		return
	end

	file:write(patched_content)
	file:close()
end

return {
	"nvim-treesitter/nvim-treesitter",
	event = { "BufReadPost", "BufNewFile" },
	build = function()
		vim.cmd("TSUpdate")
		patch_swift_highlights()
	end,
	config = function()
		require("nvim-treesitter.configs").setup({
			-- A list of parser names, or "all"
			ensure_installed = {
				"bash",
				"c",
				"html",
				"javascript",
				"jsdoc",
				"lua",
				"markdown",
				"rust",
				"typescript",
				"vim",
				"vimdoc",
			},

			-- Install parsers synchronously (only applied to `ensure_installed`)
			sync_install = false,

			-- Automatically install missing parsers when entering buffer
			-- Recommendation: set to false if you don"t have `tree-sitter` CLI installed locally
			auto_install = true,

			indent = {
				enable = true,
			},

			highlight = {
				-- `false` will disable the whole extension
				enable = true,

				-- Setting this to true will run `:h syntax` and tree-sitter at the same time.
				-- Set this to `true` if you depend on "syntax" being enabled (like for indentation).
				-- Using this option may slow down your editor, and you may see some duplicate highlights.
				-- Instead of true it can also be a list of languages
				additional_vim_regex_highlighting = { "markdown" },
			},
		})

		local treesitter_parser_config = require("nvim-treesitter.parsers").get_parser_configs()
		treesitter_parser_config.templ = {
			install_info = {
				url = "https://github.com/vrischmann/tree-sitter-templ.git",
				files = { "src/parser.c", "src/scanner.c" },
				branch = "master",
			},
		}

		vim.treesitter.language.register("templ", "templ")
	end,
}
