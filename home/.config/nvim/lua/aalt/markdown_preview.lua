local M = {}

local function notify(message, level)
	vim.notify(message, level, { title = "Md" })
end

local function resolve_markdown_path()
	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return nil, "Current buffer is not a file"
	end

	if vim.bo[bufnr].filetype ~= "markdown" then
		return nil, "Current buffer is not Markdown"
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" then
		return nil, "Save the Markdown file before running :Md"
	end

	path = vim.fn.fnamemodify(path, ":p")
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "Save the Markdown file before running :Md"
	end

	return path
end

local function open_markdown_preview()
	local path, err = resolve_markdown_path()
	if not path then
		notify(err, vim.log.levels.WARN)
		return
	end

	local uv = vim.uv or vim.loop
	if uv.os_uname().sysname ~= "Darwin" then
		notify(":Md is configured for Ghostty on macOS", vim.log.levels.ERROR)
		return
	end

	local glow = vim.fn.exepath("glow")
	if glow == "" then
		notify("Glow is not available on PATH", vim.log.levels.ERROR)
		return
	end

	local job_id = vim.fn.jobstart({
		"open",
		"-na",
		"Ghostty.app",
		"--args",
		"-e",
		glow,
		"--tui",
		"--",
		path,
	}, {
		detach = true,
		on_exit = function(_, exit_code)
			if exit_code == 0 then
				return
			end

			vim.schedule(function()
				notify(string.format("Could not open Glow in Ghostty (exit %d)", exit_code), vim.log.levels.ERROR)
			end)
		end,
	})

	if job_id <= 0 then
		notify("Could not start the Ghostty launcher", vim.log.levels.ERROR)
	end
end

function M.setup()
	vim.api.nvim_create_user_command("Md", open_markdown_preview, {
		desc = "Open the current Markdown file in Glow in a new Ghostty window",
	})
end

return M
