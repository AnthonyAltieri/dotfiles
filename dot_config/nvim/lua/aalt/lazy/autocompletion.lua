return {
	"saghen/blink.cmp",
	version = "1.*",
	event = "InsertEnter",
	opts = {
		keymap = {
			["<C-n>"] = { "select_next", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-y>"] = { "accept", "fallback" },
			["<C-Space>"] = { "show", "fallback" },
			["<C-l>"] = { "snippet_forward", "fallback" },
			["<C-h>"] = { "snippet_backward", "fallback" },
		},
		completion = {
			documentation = {
				auto_show = true,
				auto_show_delay_ms = 200,
				window = { border = "rounded" },
			},
			menu = {
				border = "rounded",
			},
		},
		sources = {
			default = { "lsp", "path", "snippets" },
		},
		snippets = { preset = "default" },
		signature = {
			enabled = true,
			window = { border = "rounded" },
		},
	},
}
