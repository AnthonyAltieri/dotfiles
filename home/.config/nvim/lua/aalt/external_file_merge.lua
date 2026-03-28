local M = {}

local MERGE_GROUP = vim.api.nvim_create_augroup("aalt-external-file-merge", { clear = true })
local CONFLICT_MARKER_STYLE = "zdiff3"
local MERGE_LABELS = { "LOCAL", "BASE", "DISK" }
local buffer_states = {}

local function is_normal_file_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
		return false
	end

	if vim.bo[bufnr].buftype ~= "" or vim.bo[bufnr].binary or not vim.bo[bufnr].modifiable then
		return false
	end

	return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function state_for(bufnr)
	local state = buffer_states[bufnr]
	if type(state) ~= "table" then
		state = {}
		buffer_states[bufnr] = state
	end

	return state
end

local function read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end

	local data = file:read("*a")
	file:close()
	return data
end

local function write_file(path, data)
	local file, err = io.open(path, "wb")
	if not file then
		return nil, err
	end

	file:write(data)
	file:close()
	return true
end

local function is_binary_data(data)
	return data:find("\0", 1, true) ~= nil
end

local function buffer_text(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local text = table.concat(lines, "\n")

	if vim.bo[bufnr].endofline then
		text = text .. "\n"
	end

	return text
end

local function text_to_lines(text)
	local trailing_newline = text:sub(-1) == "\n"
	local lines = vim.split(text, "\n", { plain = true, trimempty = false })

	if trailing_newline then
		table.remove(lines)
	end

	return lines, trailing_newline
end

local function with_preserved_views(bufnr, callback)
	local views = {}

	for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
		if vim.api.nvim_win_is_valid(win) then
			views[win] = vim.api.nvim_win_call(win, function()
				return vim.fn.winsaveview()
			end)
		end
	end

	callback()

	for win, view in pairs(views) do
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_call, win, function()
				vim.fn.winrestview(view)
			end)
		end
	end
end

local function replace_buffer_text(bufnr, text)
	local lines, trailing_newline = text_to_lines(text)

	with_preserved_views(bufnr, function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].endofline = trailing_newline
	end)
end

local function update_disk_state(bufnr, disk_text)
	local text = disk_text or read_file(vim.api.nvim_buf_get_name(bufnr))
	if not text or is_binary_data(text) then
		return false
	end

	local state = state_for(bufnr)
	state.base_text = text
	state.last_disk_text = text
	return true
end

function M.track_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not is_normal_file_buffer(bufnr) then
		return false
	end

	local state = state_for(bufnr)
	if state.base_text ~= nil and vim.bo[bufnr].modified then
		return true
	end

	return update_disk_state(bufnr)
end

local function merge_text(local_text, base_text, disk_text)
	local local_path = vim.fn.tempname()
	local base_path = vim.fn.tempname()
	local disk_path = vim.fn.tempname()

	local ok, err = write_file(local_path, local_text)
	if not ok then
		return nil, err
	end

	ok, err = write_file(base_path, base_text)
	if not ok then
		os.remove(local_path)
		return nil, err
	end

	ok, err = write_file(disk_path, disk_text)
	if not ok then
		os.remove(local_path)
		os.remove(base_path)
		return nil, err
	end

	local result = vim.system({
		"git",
		"merge-file",
		"--stdout",
		"--" .. CONFLICT_MARKER_STYLE,
		"-L",
		MERGE_LABELS[1],
		"-L",
		MERGE_LABELS[2],
		"-L",
		MERGE_LABELS[3],
		local_path,
		base_path,
		disk_path,
	}, { text = true }):wait()

	os.remove(local_path)
	os.remove(base_path)
	os.remove(disk_path)

	if result.code == 0 then
		return { text = result.stdout or "", conflicted = false }
	end

	if result.code == 1 then
		return { text = result.stdout or "", conflicted = true }
	end

	return nil, (result.stderr ~= "" and result.stderr) or ("git merge-file failed with exit code " .. result.code)
end

local function reload_clean_buffer(bufnr)
	with_preserved_views(bufnr, function()
		vim.api.nvim_buf_call(bufnr, function()
			vim.cmd("silent edit!")
		end)
	end)
end

function M.handle_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not is_normal_file_buffer(bufnr) then
		return
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	local disk_text = read_file(path)
	if not disk_text or is_binary_data(disk_text) then
		return
	end

	local state = state_for(bufnr)
	if state.in_progress then
		return
	end

	if state.last_disk_text == nil then
		M.track_buffer(bufnr)
		return
	end

	if disk_text == state.last_disk_text then
		return
	end

	if not vim.bo[bufnr].modified then
		state.in_progress = true
		local ok, err = pcall(reload_clean_buffer, bufnr)
		state.in_progress = false

		if not ok then
			vim.notify("External file reload failed: " .. err, vim.log.levels.WARN)
			return
		end

		update_disk_state(bufnr, read_file(path))
		return
	end

	local local_text = buffer_text(bufnr)
	if local_text == disk_text then
		update_disk_state(bufnr, disk_text)
		return
	end

	state.in_progress = true
	local merged, merge_err = merge_text(local_text, state.base_text or state.last_disk_text, disk_text)
	state.in_progress = false

	if not merged then
		vim.notify("External file merge failed: " .. merge_err, vim.log.levels.WARN)
		return
	end

	replace_buffer_text(bufnr, merged.text)
	state.base_text = disk_text
	state.last_disk_text = disk_text

	if merged.conflicted then
		vim.notify("External changes merged into buffer with conflicts", vim.log.levels.WARN)
	end
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = MERGE_GROUP,
		callback = function(args)
			M.track_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = MERGE_GROUP,
		callback = function(args)
			buffer_states[args.buf] = nil
		end,
	})

	vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
		group = MERGE_GROUP,
		callback = function(args)
			M.track_buffer(args.buf)
			M.handle_buffer(args.buf)
		end,
	})

	vim.schedule(function()
		M.track_buffer(vim.api.nvim_get_current_buf())
	end)
end

return M
