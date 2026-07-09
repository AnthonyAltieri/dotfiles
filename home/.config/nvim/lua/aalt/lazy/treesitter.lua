local ensure_installed = {
	"bash",
	"c",
	"html",
	"javascript",
	"jsdoc",
	"lua",
	"markdown",
	"markdown_inline",
	"rust",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
}

local filetypes = {
	"bash",
	"c",
	"html",
	"javascript",
	"javascriptreact",
	"lua",
	"markdown",
	"rust",
	"sh",
	"templ",
	"typescript",
	"typescriptreact",
	"vim",
	"vimdoc",
	"zsh",
}

local parser_aliases = {
	javascriptreact = "tsx",
	sh = "bash",
	typescriptreact = "tsx",
	zsh = "bash",
}

local templ_parser = {
	install_info = {
		url = "https://github.com/vrischmann/tree-sitter-templ.git",
		files = { "src/parser.c", "src/scanner.c" },
		branch = "master",
	},
}

local function configure_templ_parser()
	local ok, parsers = pcall(require, "nvim-treesitter.parsers")
	if not ok then
		return
	end

	if parsers.get_parser_configs then
		parsers.get_parser_configs().templ = templ_parser
	else
		parsers.templ = templ_parser
	end

	vim.treesitter.language.register("templ", "templ")
end

local function register_parser_aliases()
	for filetype, parser in pairs(parser_aliases) do
		vim.treesitter.language.register(parser, filetype)
	end
end

local function setup_current_treesitter()
	local treesitter = require("nvim-treesitter")
	treesitter.setup({
		install_dir = vim.fn.stdpath("data") .. "/site",
	})
	treesitter.install(ensure_installed)

	local group = vim.api.nvim_create_augroup("aalt-treesitter", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "TSUpdate",
		callback = configure_templ_parser,
	})

	configure_templ_parser()
	register_parser_aliases()

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = filetypes,
		callback = function()
			local ok = pcall(vim.treesitter.start)
			if ok then
				vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
			end
		end,
	})
end

local function setup_legacy_treesitter(configs)
	configs.setup({
		-- A list of parser names, or "all"
		ensure_installed = ensure_installed,

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

	configure_templ_parser()
end

return {
	"nvim-treesitter/nvim-treesitter",
	lazy = false,
	build = ":TSUpdate",
	config = function()
		local has_legacy_configs, configs = pcall(require, "nvim-treesitter.configs")
		if has_legacy_configs then
			setup_legacy_treesitter(configs)
		else
			setup_current_treesitter()
		end
	end,
}
