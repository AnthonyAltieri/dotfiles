-- Set leader key before anything else
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Initial Configuration
require("aalt.options")
require("aalt.set")
require("aalt.autocommands")
require("aalt.external_file_merge").setup()
require("aalt.debug_commands").setup()
require("aalt.path_commands").setup()

-- Bootstrap Lazy plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local config_lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
local state_lockfile = vim.fn.stdpath("state") .. "/lazy/lazy-lock.json"
local uv = vim.uv or vim.loop

local function ensure_writable_lazy_lockfile()
	if uv.fs_stat(state_lockfile) then
		return
	end

	local seed = io.open(config_lockfile, "rb")
	if not seed then
		return
	end

	local data = seed:read("*a")
	seed:close()

	vim.fn.mkdir(vim.fn.fnamemodify(state_lockfile, ":p:h"), "p")

	local target = io.open(state_lockfile, "wb")
	if not target then
		vim.notify("lazy.nvim could not create " .. state_lockfile, vim.log.levels.WARN)
		return
	end

	target:write(data)
	target:close()
end

if not vim.loop.fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

-- Load Lazy plugins
ensure_writable_lazy_lockfile()
require("lazy").setup({
	spec = { import = "aalt.lazy" },
	lockfile = state_lockfile,
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
