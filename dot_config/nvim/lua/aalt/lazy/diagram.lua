return {
	"3rd/diagram.nvim",
	dependencies = {
		"3rd/image.nvim",
	},
	ft = { "markdown" },
	opts = {
		renderer_options = {
			mermaid = {
				background = nil,
				theme = nil,
			},
		},
	},
}
