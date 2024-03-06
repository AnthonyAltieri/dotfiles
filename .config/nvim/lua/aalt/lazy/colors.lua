function ColorMyPencils(color)
    color = color or "catppuccin"
    vim.cmd.colorscheme(color)

    vim.api.nvim_set_hl(0, "Normal", {
        bg = "none"
    })
    vim.api.nvim_set_hl(0, "NormalFloat", {
        bg = "none"
    })

end

return {{
    "catppuccin/nvim",
    -- Load during startup
    lazy = false,
    -- Load this before all other plugins
    priority = 1000,
    config = function()
        require("catppuccin").setup({
            flavour = "mocha", -- latte, frappe, macchiato, mocha
            background = { -- :h background
                light = "latte",
                dark = "mocha"
            },
            transparent_background = false,
            term_colors = true,
            dim_inactive = {
                enabled = false,
                shade = "dark",
                percentage = 0.15
            },
            no_italic = false, -- Force no italic
            no_bold = false, -- Force no bold
            styles = {
                comments = {"italic"},
                conditionals = {"italic"},
                loops = {},
                functions = {"italic"},
                keywords = {"italic"},
                strings = {},
                variables = {},
                numbers = {},
                booleans = {},
                properties = {},
                types = {},
                operators = {}
            },
            color_overrides = {},
            custom_highlights = {},
            integrations = {
                cmp = true,
                gitsigns = true,
                nvimtree = false,
                telescope = true,
                notify = false,
                mini = false
                -- For more plugins integrations please scroll down (https://github.com/catppuccin/nvim#integrations)
            }
        })

        vim.cmd("colorscheme catppuccin")
    end
}}
