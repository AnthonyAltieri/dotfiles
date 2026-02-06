local monorepo = require("aalt.monorepo")

return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		notify_on_error = false,
		format_on_save = {
			timeout_ms = 500,
			lsp_fallback = true,
		},
		formatters = {
			biome = {
				command = function(_, ctx)
					return monorepo.biome_cmd(ctx.filename)
				end,
				args = { "format", "--stdin-file-path", "$FILENAME" },
				stdin = true,
				cwd = function(_, ctx)
					return monorepo.find_biome_root(ctx.filename)
				end,
				require_cwd = true,
			},
			oxfmt = {
				command = function(_, ctx)
					return monorepo.oxfmt_cmd(ctx.filename)
				end,
				args = { "--stdin-filepath", "$FILENAME" },
				stdin = true,
				cwd = function(_, ctx)
					return monorepo.find_oxc_root(ctx.filename)
				end,
				require_cwd = true,
			},
		},
		formatters_by_ft = {
			lua = { "stylua" },
			javascript = monorepo.javascript_formatters,
			javascriptreact = monorepo.javascript_formatters,
			typescript = monorepo.javascript_formatters,
			typescriptreact = monorepo.javascript_formatters,
		},
	},
}
