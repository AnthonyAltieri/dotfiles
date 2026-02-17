-- Set leader key before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Initial Configuration
require("aalt.options")
require("aalt.set")
require("aalt.autocommands")
require("aalt.debug_commands").setup()

-- Bootstrap Lazy plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- Load Lazy plugins
require("lazy").setup({
	spec = { import = "aalt.lazy" },
	performance = {
		rtp = {
			disabled_plugins = {
				"gzip",
				"matchit",
				"matchparen",
				"netrwPlugin",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
			},
		},
	},
})

-- Dashboard (after lazy so its VimEnter fires after neo-tree's)
require("aalt.dashboard")
