-- Seamless Ctrl+h/j/k/l navigation between Neovim windows and herdr panes.
--
-- Replaces vim-tmux-navigator: Ctrl+<dir> moves between Neovim windows, and
-- when the current window is already at that edge the focus request is handed
-- to the surrounding pane: `herdr pane focus --direction <dir> --current` in
-- the herdr TUI, or `herdr-app do pane.go --direction <dir>` in the Herdr
-- desktop app, whose terminals run under herdr-core and get HC_TERMINAL_ID.
-- Outside both the mapping degrades to a plain window move.

local M = {}

local directions = {
	h = { wincmd = "h", herdr = "left" },
	j = { wincmd = "j", herdr = "down" },
	k = { wincmd = "k", herdr = "up" },
	l = { wincmd = "l", herdr = "right" },
}

function M.inside_herdr()
	return vim.env.HERDR_ENV == "1" and vim.env.HERDR_SOCKET_PATH ~= nil and vim.env.HERDR_SOCKET_PATH ~= ""
end

function M.inside_herdr_app()
	return vim.env.HC_TERMINAL_ID ~= nil and vim.env.HC_TERMINAL_ID ~= ""
end

---@return string[]|nil
function M.herdr_command(direction)
	if M.inside_herdr() then
		return { "herdr", "pane", "focus", "--direction", direction, "--current" }
	end
	if M.inside_herdr_app() then
		return { "herdr-app", "do", "pane.go", "--direction", direction }
	end
	return nil
end

---@param key "h"|"j"|"k"|"l"
---@param opts? { run?: fun(cmd: string[]) }
function M.navigate(key, opts)
	local direction = directions[key]
	if not direction then
		return
	end

	local before = vim.api.nvim_get_current_win()
	vim.cmd.wincmd(direction.wincmd)
	if vim.api.nvim_get_current_win() ~= before then
		return
	end

	local cmd = M.herdr_command(direction.herdr)
	if not cmd then
		return
	end

	local run = opts and opts.run or function(argv)
		vim.system(argv, { detach = false })
	end
	run(cmd)
end

function M.setup()
	for key in pairs(directions) do
		vim.keymap.set({ "n", "t" }, "<C-" .. key .. ">", function()
			M.navigate(key)
		end, { desc = "Focus window/pane " .. directions[key].herdr, silent = true })
	end
end

return M
