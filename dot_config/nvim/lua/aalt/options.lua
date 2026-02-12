-- Line Numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Spacing
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.wrap = false

-- Search
-- case-insensitive searching UNLESS \C or capital in search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true

-- Preview substitutions live, as you type!
vim.opt.inccommand = 'split'

-- Allow unsaved buffers to be hidden (needed for LSP go-to-definition, etc.)
vim.opt.hidden = true

-- Don't use swapfiles, use an undofile instead
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = os.getenv("HOME") .. "/.vim/undodir"
vim.opt.undofile = true

-- Decrease update time
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- Colors
vim.opt.termguicolors = true

vim.opt.signcolumn = "yes"

-- Floating window border (0.11+: applies to hover, signature help, diagnostics, etc.)
vim.o.winborder = "rounded"
vim.opt.isfname:append("@-@")
