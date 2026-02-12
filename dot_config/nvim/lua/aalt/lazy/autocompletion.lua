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
			-- Disable dot_repeat to work around upstream bug where auto-wrap
			-- formatoptions cause 'start is higher than end' crash in
			-- write_to_dot_repeat (see blink.cmp#1445, PR#2378)
			accept = {
				dot_repeat = false,
			},
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
