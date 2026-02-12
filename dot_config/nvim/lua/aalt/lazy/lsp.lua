return {
    -- LSP configuration
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            -- Automatically install LSPs and related tools to stdpath for neovim
            "williamboman/mason.nvim",
            "williamboman/mason-lspconfig.nvim",
            "WhoIsSethDaniel/mason-tool-installer.nvim",

            -- Completion engine (needed for LSP capabilities)
            "saghen/blink.cmp",

            -- Useful status updates for LSP.
            -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
            { "j-hui/fidget.nvim", opts = {} },
        },
        config = function()
            local function organize_typescript_imports()
                vim.lsp.buf.code_action({
                    apply = true,
                    context = {
                        only = { "source.organizeImports" },
                        diagnostics = {},
                    },
                })
            end

            -- This function gets run when an LSP attaches to a particular buffer.
            --  That is to say, every time a new file is opened that is associated with
            --  an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
            --  function will be executed to configure the current buffer
            vim.api.nvim_create_autocmd("LspAttach", {
                group = vim.api.nvim_create_augroup("kickstart-lsp-attach", { clear = true }),
                callback = function(event)
                    local opts = function(desc)
                        return { buffer = event.buf, desc = "LSP: " .. desc }
                    end

                    local telescope_vertical = { layout_strategy = "vertical" }

                    -- Jump to the definition of the word under your cursor.
                    --  Jumps directly when there is a single result, opens telescope when multiple.
                    --  To jump back, press <C-T>.
                    vim.keymap.set("n", "gd", function()
                        vim.lsp.buf.definition({
                            on_list = function(options)
                                if #options.items == 1 then
                                    local item = options.items[1]
                                    vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
                                    vim.api.nvim_win_set_cursor(0, { item.lnum, item.col - 1 })
                                else
                                    require("telescope.builtin").lsp_definitions(telescope_vertical)
                                end
                            end,
                        })
                    end, opts("[G]oto [D]efinition"))

                    -- Find references for the word under your cursor.
                    vim.keymap.set("n", "gr", function()
                        require("telescope.builtin").lsp_references(telescope_vertical)
                    end, opts("[G]oto [R]eferences"))

                    -- Find all usages of the symbol under your cursor.
                    vim.keymap.set("n", "gu", function()
                        require("telescope.builtin").lsp_references(telescope_vertical)
                    end, opts("[G]oto [U]sages"))

                    -- Jump to the implementation of the word under your cursor.
                    --  Useful when your language has ways of declaring types without an actual implementation.
                    vim.keymap.set("n", "gI", function()
                        require("telescope.builtin").lsp_implementations(telescope_vertical)
                    end, opts("[G]oto [I]mplementation"))

                    -- Jump to the type of the word under your cursor.
                    --  Useful when you're not sure what type a variable is and you want to see
                    --  the definition of its *type*, not where it was *defined*.
                    vim.keymap.set("n", "<leader>D", function()
                        require("telescope.builtin").lsp_type_definitions(telescope_vertical)
                    end, opts("Type [D]efinition"))

                    -- Fuzzy find all the symbols in your current document.
                    --  Symbols are things like variables, functions, types, etc.
                    vim.keymap.set("n", "<leader>ds", function()
                        require("telescope.builtin").lsp_document_symbols(telescope_vertical)
                    end, opts("[D]ocument [S]ymbols"))

                    -- Fuzzy find all the symbols in your current workspace
                    --  Similar to document symbols, except searches over your whole project.
                    vim.keymap.set("n", "<leader>ws", function()
                        require("telescope.builtin").lsp_dynamic_workspace_symbols(telescope_vertical)
                    end, opts("[W]orkspace [S]ymbols"))

                    -- Rename the variable under your cursor
                    --  Most Language Servers support renaming across files, etc.
                    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts("[R]e[n]ame"))

                    -- Execute a code action, usually your cursor needs to be on top of an error
                    -- or a suggestion from your LSP for this to activate.
                    vim.keymap.set("n", "<leader>.", vim.lsp.buf.code_action, opts("Code Action"))
                    vim.keymap.set("n", "<C-.>", vim.lsp.buf.code_action, opts("Code Action"))
                    -- Ghostty sends \x1b[46;5u for Ctrl+. via CSI u encoding
                    vim.keymap.set("n", "\x1b[46;5u", vim.lsp.buf.code_action, opts("Code Action"))

                    -- Opens a popup that displays documentation about the word under your cursor
                    --  See `:help K` for why this keymap
                    vim.keymap.set("n", "<m-v>", function()
                        vim.lsp.buf.hover({ max_width = 80, max_height = 30 })
                    end, opts("Hover Documentation (lsp)"))
                    vim.keymap.set("i", "<m-v>", vim.lsp.buf.signature_help, opts("Signature Help (lsp)"))

                    vim.keymap.set("n", "<m-d>", vim.diagnostic.open_float, opts("Diagnostics (lsp)"))
                    vim.keymap.set("i", "<m-d>", vim.diagnostic.open_float, opts("Diagnostics (lsp)"))

                    -- WARN: This is not Goto Definition, this is Goto Declaration.
                    --  For example, in C this would take you to the header
                    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts("[G]oto [D]eclaration"))

                    vim.keymap.set("n", "<leader>fb", vim.lsp.buf.format, opts("[F]ormat [B]uffer"))

                    -- The following two autocommands are used to highlight references of the
                    -- word under your cursor when your cursor rests there for a little while.
                    --    See `:help CursorHold` for information about when this is executed
                    --
                    -- When you move your cursor, the highlights will be cleared (the second autocommand).
                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client.name == "tsgo" then
                        vim.keymap.set("n", "<C-M-o>", organize_typescript_imports, opts("[O]rganize Imports"))
                        vim.keymap.set("n", "<F2>", vim.lsp.buf.rename, opts("[R]ename Symbol"))
                    end

                    if client and client.server_capabilities.documentHighlightProvider then
                        vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
                            buffer = event.buf,
                            callback = vim.lsp.buf.document_highlight,
                        })

                        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
                            buffer = event.buf,
                            callback = vim.lsp.buf.clear_references,
                        })
                    end
                end,
            })

            -- LSP servers and clients are able to communicate to each other what features they support.
            --  By default, Neovim doesn't support everything that is in the LSP Specification.
            --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
            --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = vim.tbl_deep_extend("force", capabilities, require("blink.cmp").get_lsp_capabilities())

            -- Enable the following language servers
            --  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
            --
            --  Add any additional override configuration in the following tables. Available keys are:
            --  - cmd (table): Override the default command used to start the server
            --  - filetypes (table): Override the default list of associated filetypes for the server
            --  - capabilities (table): Override fields in capabilities. Can be used to disable certain LSP features.
            --  - settings (table): Override the default settings passed when initializing the server.
            --        For example, to see the options for `lua_ls`, you could go to: https://luals.github.io/wiki/settings/
            local servers = {
                -- clangd = {},
                -- gopls = {},
                -- rust_analyzer = {},
                -- ... etc. See `:help lspconfig-all` for a list of all the pre-configured LSPs
                --
                pyright = {},
                ruff = {},
                lua_ls = {
                    -- cmd = {...},
                    -- filetypes { ...},
                    -- capabilities = {},
                    settings = {
                        Lua = {
                            runtime = { version = "LuaJIT" },
                            workspace = {
                                checkThirdParty = false,
                                -- Tells lua_ls where to find all the Lua files that you have loaded
                                -- for your neovim configuration.
                                library = {
                                    "${3rd}/luv/library",
                                    unpack(vim.api.nvim_get_runtime_file("", true)),
                                },
                                -- If lua_ls is really slow on your computer, you can try this instead:
                                -- library = { vim.env.VIMRUNTIME },
                            },
                            completion = {
                                callSnippet = "Replace",
                            },
                            -- You can toggle below to ignore Lua_LS's noisy `missing-fields` warnings
                            -- diagnostics = { disable = { 'missing-fields' } },
                        },
                    },
                },
            }

            -- Ensure the servers and tools above are installed
            --  To check the current status of installed tools and/or manually install
            --  other tools, you can run
            --    :Mason
            --
            --  You can press `g?` for help in this menu
            require("mason").setup()

            -- You can add other tools here that you want Mason to install
            -- for you, so that they are available from within Neovim.
            require("mason-tool-installer").setup({
                ensure_installed = {
                    "stylua", -- Used to format lua code
                    "eslint_d",
                    "oxfmt",
                    "oxlint",
                    "prettierd",
                },
            })

            require("mason-lspconfig").setup({
                ensure_installed = vim.tbl_keys(servers or {}),
                automatic_enable = true,
            })

            -- Configure each mason-managed server with capabilities and custom settings
            for server_name, server_config in pairs(servers) do
                server_config.capabilities = vim.tbl_deep_extend("force", {}, capabilities, server_config.capabilities or {})
                vim.lsp.config(server_name, server_config)
            end

            -- tsgo: fast native TypeScript LSP (installed globally via npm, not Mason-managed)
            vim.lsp.config("tsgo", {
                capabilities = capabilities,
            })
            vim.lsp.enable("tsgo")

            -- Bind any language specific commands
            vim.keymap.set("n", "<leader>fi", organize_typescript_imports, { desc = "LSP: [F]ormat [I]mports" })
        end,
    },
}
