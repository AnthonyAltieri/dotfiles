local M = {}

local function is_file_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	if vim.bo[bufnr].buftype ~= "" then
		return false
	end

	return vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local function find_file_buffers()
	local file_buffers = {}

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_file_buffer(bufnr) then
			file_buffers[#file_buffers + 1] = bufnr
		end
	end

	return file_buffers
end

local function resolve_target_buffer()
	local current = vim.api.nvim_get_current_buf()
	if is_file_buffer(current) then
		return current
	end

	local file_buffers = find_file_buffers()
	if #file_buffers == 1 then
		return file_buffers[1]
	end

	if #file_buffers == 0 then
		return nil, "No file buffer is available to copy from"
	end

	return nil, "Current buffer is not a file buffer; focus a file buffer before running :Crp"
end

local function copy_to_registers(value)
	vim.fn.setreg('"', value)
	pcall(vim.fn.setreg, "+", value)
end

local function copy_relative_path()
	local bufnr, err = resolve_target_buffer()
	if not bufnr then
		vim.notify(err, vim.log.levels.WARN, { title = "Crp" })
		return
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	local relative_path = vim.fn.fnamemodify(path, ":.")
	if relative_path == "" then
		relative_path = path
	end

	copy_to_registers(relative_path)
	vim.notify(string.format("Copied relative path: %s", relative_path), vim.log.levels.INFO, { title = "Crp" })
end

function M.setup()
	vim.api.nvim_create_user_command("Crp", copy_relative_path, {
		desc = "Copy the current file path relative to the current working directory",
	})
end

return M
