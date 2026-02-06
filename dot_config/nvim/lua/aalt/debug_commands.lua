local M = {}

local function append(lines, value)
	lines[#lines + 1] = value
end

local function append_kv(lines, key, value)
	append(lines, string.format("%-20s %s", key .. ":", tostring(value)))
end

local function open_report(title, lines)
	vim.cmd("botright new")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "markdown"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	pcall(vim.api.nvim_buf_set_name, bufnr, "debug://" .. title)
end

local function flatten_formatter_units(units)
	local names = {}
	local seen = {}

	local function add(name)
		if not seen[name] then
			names[#names + 1] = name
			seen[name] = true
		end
	end

	local function walk(item)
		if type(item) == "string" then
			add(item)
		elseif type(item) == "table" then
			for _, value in ipairs(item) do
				walk(value)
			end
		end
	end

	for _, unit in ipairs(units) do
		walk(unit)
	end

	return names
end

local function detect_toolchain(monorepo, path)
	local biome_root = monorepo.find_biome_root(path)
	if biome_root then
		return "biome", biome_root
	end

	local oxc_root = monorepo.find_oxc_root(path)
	if oxc_root then
		return "oxc", oxc_root
	end

	local eslint_root = monorepo.find_eslint_root(path)
	if eslint_root then
		return "eslint", eslint_root
	end

	return "none", "-"
end

local function eval_linter_value(value)
	if type(value) == "function" then
		local ok, resolved = pcall(value)
		if ok then
			return resolved
		end
		return "<error evaluating function>"
	end
	return value
end

local function format_debug()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	local ft = vim.bo[bufnr].filetype
	local lines = {}

	local monorepo = require("aalt.monorepo")
	local toolchain, root = detect_toolchain(monorepo, path)

	append(lines, "# FormatDebug")
	append(lines, "")
	append_kv(lines, "file", path ~= "" and path or "<no file>")
	append_kv(lines, "filetype", ft)
	append_kv(lines, "toolchain", toolchain)
	append_kv(lines, "root", root)
	append(lines, "")

	local ok, conform = pcall(require, "conform")
	if not ok then
		append(lines, "Conform not available.")
		open_report("format-debug", lines)
		return
	end

	local units = conform.list_formatters_for_buffer(bufnr)
	append(lines, "## Formatter Units")
	append(lines, vim.inspect(units))
	append(lines, "")

	local names = flatten_formatter_units(units)
	append(lines, "## Formatter Details")
	if #names == 0 then
		append(lines, "No formatter candidates.")
	else
		for _, name in ipairs(names) do
			local info = conform.get_formatter_info(name, bufnr)
			append(lines, string.format("- %s", name))
			append_kv(lines, "  available", info.available)
			append_kv(lines, "  command", info.command or "-")
			append_kv(lines, "  cwd", info.cwd or "-")
			append_kv(lines, "  reason", info.available_msg or "-")
		end
	end

	open_report("format-debug", lines)
end

local function lint_debug()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	local ft = vim.bo[bufnr].filetype
	local lines = {}

	local monorepo = require("aalt.monorepo")
	local toolchain, root = detect_toolchain(monorepo, path)
	local selected_linters, lint_cwd = monorepo.linters_for_buf(bufnr)

	append(lines, "# LintDebug")
	append(lines, "")
	append_kv(lines, "file", path ~= "" and path or "<no file>")
	append_kv(lines, "filetype", ft)
	append_kv(lines, "toolchain", toolchain)
	append_kv(lines, "root", root)
	append_kv(lines, "lint cwd", lint_cwd or "-")
	append(lines, "")
	append(lines, "## Selected Linters")
	append(lines, vim.inspect(selected_linters))
	append(lines, "")

	local ok, lint = pcall(require, "lint")
	if not ok then
		append(lines, "nvim-lint not available.")
		open_report("lint-debug", lines)
		return
	end

	append(lines, "## Linter Config")
	if #selected_linters == 0 then
		append(lines, "No linters selected for this buffer.")
	else
		for _, linter_name in ipairs(selected_linters) do
			local linter = lint.linters[linter_name]
			if type(linter) == "function" then
				local ok_linter, resolved = pcall(linter)
				linter = ok_linter and resolved or nil
			end

			append(lines, string.format("- %s", linter_name))
			if not linter then
				append(lines, "  <unavailable>")
			else
				append_kv(lines, "  cmd", eval_linter_value(linter.cmd) or "-")
				append_kv(lines, "  stream", linter.stream or "-")
				append_kv(lines, "  stdin", linter.stdin == true)
				append_kv(lines, "  ignore_exitcode", linter.ignore_exitcode == true)
				if linter.args then
					local args = {}
					for _, arg in ipairs(linter.args) do
						args[#args + 1] = eval_linter_value(arg)
					end
					append_kv(lines, "  args", vim.inspect(args))
				else
					append_kv(lines, "  args", "-")
				end
			end
		end
	end

	append(lines, "")
	append(lines, "## Current Diagnostics By Source")
	local counts = {}
	for _, diag in ipairs(vim.diagnostic.get(bufnr)) do
		local source = diag.source or "unknown"
		counts[source] = (counts[source] or 0) + 1
	end
	if next(counts) == nil then
		append(lines, "No diagnostics in current buffer.")
	else
		for source, count in pairs(counts) do
			append(lines, string.format("- %s: %d", source, count))
		end
	end

	open_report("lint-debug", lines)
end

function M.setup()
	vim.api.nvim_create_user_command("FormatDebug", format_debug, {
		desc = "Show formatter routing/debug details for current buffer",
	})
	vim.api.nvim_create_user_command("LintDebug", lint_debug, {
		desc = "Show linter routing/debug details for current buffer",
	})
end

return M
