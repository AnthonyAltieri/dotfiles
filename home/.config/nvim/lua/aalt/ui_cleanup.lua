local M = {}

local managed_ui_filetypes = {
	["dashboard"] = true,
	["neo-tree"] = true,
	["neo-tree-popup"] = true,
}

local cleanup_in_progress = false

local function is_real_file_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function is_managed_ui_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	return managed_ui_filetypes[vim.bo[bufnr].filetype] == true
end

local function should_close_other_windows(current_win, other_wins)
	local current_buf = vim.api.nvim_win_get_buf(current_win)
	if not (is_real_file_buffer(current_buf) or is_managed_ui_buffer(current_buf)) then
		return false
	end

	if #other_wins == 0 then
		return false
	end

	for _, win in ipairs(other_wins) do
		local bufnr = vim.api.nvim_win_get_buf(win)
		if is_real_file_buffer(bufnr) then
			return false
		end

		if not is_managed_ui_buffer(bufnr) then
			return false
		end
	end

	return true
end

function M.close_managed_ui_windows_for_current_quit()
	if cleanup_in_progress then
		return 0
	end

	local current_win = vim.api.nvim_get_current_win()
	if not vim.api.nvim_win_is_valid(current_win) then
		return 0
	end

	local current_tab = vim.api.nvim_get_current_tabpage()
	local other_wins = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
		if win ~= current_win and vim.api.nvim_win_is_valid(win) then
			other_wins[#other_wins + 1] = win
		end
	end

	if not should_close_other_windows(current_win, other_wins) then
		return 0
	end

	cleanup_in_progress = true
	local closed = 0
	for _, win in ipairs(other_wins) do
		if vim.api.nvim_win_is_valid(win) and pcall(vim.api.nvim_win_close, win, false) then
			closed = closed + 1
		end
	end
	cleanup_in_progress = false

	return closed
end

function M.setup()
	local group = vim.api.nvim_create_augroup("AAltUiCleanup", { clear = true })
	vim.api.nvim_create_autocmd("QuitPre", {
		group = group,
		callback = function()
			M.close_managed_ui_windows_for_current_quit()
		end,
		desc = "Close managed UI windows before quitting the last real file",
	})
end

return M
