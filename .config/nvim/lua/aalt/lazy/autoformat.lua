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
			oxfmt = {
				command = "oxfmt",
				args = { "--stdin-filepath", "$FILENAME" },
				stdin = true,
			},
		},
		formatters_by_ft = {
			lua = { "stylua" },
			-- Conform can also run multiple formatters sequentially
			-- python = { "isort", "black" },
			--
			-- You can use a sub-list to tell conform to run *until* a formatter
			-- is found.
			-- javascript = { { "prettierd", "prettier" } },
			javascript = { "oxfmt", "prettierd", "prettier" },
			javascriptreact = { "oxfmt", "prettierd", "prettier" },
			typescript = { "oxfmt", "prettierd", "prettier" },
			typescriptreact = { "oxfmt", "prettierd", "prettier" },
		},
	},
}
