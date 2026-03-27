local monorepo = require("aalt.monorepo")
local js_filetypes = {
	javascript = true,
	javascriptreact = true,
	["javascript.jsx"] = true,
	typescript = true,
	typescriptreact = true,
	["typescript.tsx"] = true,
}

return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	opts = {
		notify_on_error = false,
		format_on_save = function(bufnr)
			if js_filetypes[vim.bo[bufnr].filetype] then
				return {
					timeout_ms = 500,
					lsp_format = "never",
				}
			end

			return {
				timeout_ms = 500,
				lsp_format = "fallback",
			}
		end,
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
			eslint_d_monorepo = {
				command = function(_, ctx)
					return monorepo.eslint_format_cmd(ctx.filename)
				end,
				args = { "--fix-to-stdout", "--stdin", "--stdin-filename", "$FILENAME" },
				stdin = true,
				cwd = function(_, ctx)
					return monorepo.find_eslint_root(ctx.filename)
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
