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

-- The Obsidian CLI opens the tab in the existing window without focusing the
-- app, so bring it to the front once the file has opened.
local function activate_obsidian()
	local ok, launch_err = pcall(vim.system, { "open", "-a", "Obsidian" }, { detach = true }, function(result)
		if result.code == 0 then
			return
		end
		vim.schedule(function()
			notify(string.format("Could not bring Obsidian to the front (exit %d)", result.code), vim.log.levels.WARN)
		end)
	end)
	if not ok then
		notify("Could not bring Obsidian to the front: " .. tostring(launch_err), vim.log.levels.WARN)
	end
end

local function open_markdown_preview()
	local path, err = resolve_markdown_path()
	if not path then
		notify(err, vim.log.levels.WARN)
		return
	end

	local uv = vim.uv or vim.loop
	if uv.os_uname().sysname ~= "Darwin" then
		notify(":Md is configured for Obsidian on macOS", vim.log.levels.ERROR)
		return
	end

	local obsidian = vim.fn.exepath("obsidian")
	if obsidian == "" then
		obsidian = "/Applications/Obsidian.app/Contents/MacOS/obsidian-cli"
		if vim.fn.executable(obsidian) ~= 1 then
			notify("Obsidian CLI is unavailable; install Obsidian manually and enable the CLI", vim.log.levels.ERROR)
			return
		end
	end

	-- Obsidian 1.14.2 identifies files outside the vault with a file: prefix.
	local ok, launch_err = pcall(vim.system, {
		obsidian,
		"open",
		"path=file:" .. path,
	}, { text = true, detach = true }, function(result)
		local stdout = vim.trim(result.stdout or "")
		local stderr = vim.trim(result.stderr or "")
		-- The CLI also reports command errors on stdout with exit code zero.
		if result.code == 0 and not stdout:match("^Error:") then
			vim.schedule(activate_obsidian)
			return
		end

		local detail = stderr ~= "" and stderr or stdout
		if detail == "" then
			detail = string.format("exit %d", result.code)
		end
		vim.schedule(function()
			notify("Could not open Markdown in Obsidian: " .. detail, vim.log.levels.ERROR)
		end)
	end)

	if not ok then
		notify("Could not start Obsidian CLI: " .. tostring(launch_err), vim.log.levels.ERROR)
	end
end

function M.setup()
	vim.api.nvim_create_user_command("Md", open_markdown_preview, {
		desc = "Open the current Markdown file with the Obsidian CLI",
	})
end

return M
