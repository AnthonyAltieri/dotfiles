return {
	"nvim-treesitter/nvim-treesitter",
	-- Upstream does not support lazy-loading this plugin.
	lazy = false,
	build = ":TSUpdate",
	config = function()
		local ts_install = require("nvim-treesitter.install")

		-- Newer tree-sitter CLIs removed `--no-bindings`, but this pinned plugin still adds it.
		if vim.fn.executable("tree-sitter") == 1 then
			local help = vim.fn.system({ "tree-sitter", "generate", "--help" })
			if vim.v.shell_error == 0 and not help:find("--no-bindings", 1, true) then
				local generate_args = { "generate" }
				if help:find("--abi", 1, true) then
					table.insert(generate_args, "--abi")
					table.insert(generate_args, tostring(vim.treesitter.language_version))
				end
				ts_install.ts_generate_args = generate_args
			end
		end

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
				"markdown_inline",
				"rust",
				"swift",
				"tsx",
				"typescript",
				"vim",
				"vimdoc",
			},

			-- Install parsers synchronously (only applied to `ensure_installed`)
			sync_install = false,

			-- Keep parser installation out of the buffer-open path.
			auto_install = false,

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
