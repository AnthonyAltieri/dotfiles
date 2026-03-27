local M = {}

local function append(lines, value)
	lines[#lines + 1] = value
end

local function append_kv(lines, key, value)
	append(lines, string.format("%-24s %s", key .. ":", tostring(value)))
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

local function resolve_linter_entries(lint, selected_linters)
	local entries = {}

	for _, linter_name in ipairs(selected_linters) do
		local linter = lint.linters[linter_name]
		if type(linter) == "function" then
			local ok_linter, resolved = pcall(linter)
			linter = ok_linter and resolved or nil
		end

		local entry = {
			args = {},
			cmd = nil,
			ignore_exitcode = false,
			linter = linter,
			name = linter_name,
			stdin = false,
			stream = "-",
		}

		if linter then
			entry.cmd = eval_linter_value(linter.cmd)
			entry.stream = linter.stream or "-"
			entry.stdin = linter.stdin == true
			entry.ignore_exitcode = linter.ignore_exitcode == true
			if linter.args then
				for _, arg in ipairs(linter.args) do
					entry.args[#entry.args + 1] = eval_linter_value(arg)
				end
			end
		end

		entries[#entries + 1] = entry
	end

	return entries
end

local function append_formatter_candidates(lines, conform, bufnr, formatter_state)
	append(lines, "## Formatter Candidates")
	if #formatter_state.formatters == 0 then
		append(lines, "No formatter candidates.")
		return nil
	end

	local available = conform.resolve_formatters(formatter_state.formatters, bufnr, false, true)
	for _, name in ipairs(formatter_state.formatters) do
		local info = conform.get_formatter_info(name, bufnr)
		append(lines, string.format("- %s", name))
		append_kv(lines, "  available", info.available)
		append_kv(lines, "  command", info.command or "-")
		append_kv(lines, "  cwd", info.cwd or "-")
		append_kv(lines, "  reason", info.available_msg or "-")
	end

	return available[1]
end

local function append_linter_candidates(lines, lint_entries)
	append(lines, "## Linter Candidates")
	if #lint_entries == 0 then
		append(lines, "No linters selected for this buffer.")
		return nil
	end

	for _, entry in ipairs(lint_entries) do
		append(lines, string.format("- %s", entry.name))
		if not entry.linter then
			append(lines, "  <unavailable>")
		else
			append_kv(lines, "  cmd", entry.cmd or "-")
			append_kv(lines, "  stream", entry.stream)
			append_kv(lines, "  stdin", entry.stdin)
			append_kv(lines, "  ignore_exitcode", entry.ignore_exitcode)
			append_kv(lines, "  args", #entry.args > 0 and vim.inspect(entry.args) or "-")
		end
	end

	return lint_entries[1]
end

local function append_policy_details(lines, formatter_state)
	local details = formatter_state.policy_details
	if not details then
		return
	end

	append(lines, "## ESLint Formatting Probe")
	append_kv(lines, "probe status", details.status or "-")
	append_kv(lines, "probe reason", details.reason or "-")
	append_kv(lines, "probe cache key", details.cache_key or "-")
	append_kv(lines, "probe command", details.command or "-")
	append_kv(lines, "probe cwd", details.cwd or "-")
	append(lines, "")
end

local function append_diagnostic_counts(lines, bufnr)
	append(lines, "## Current Diagnostics By Source")
	local counts = {}
	for _, diag in ipairs(vim.diagnostic.get(bufnr)) do
		local source = diag.source or "unknown"
		counts[source] = (counts[source] or 0) + 1
	end
	if next(counts) == nil then
		append(lines, "No diagnostics in current buffer.")
		return
	end
	for source, count in pairs(counts) do
		append(lines, string.format("- %s: %d", source, count))
	end
end

local function build_summary(lines, path, ft, formatter_state, active_formatter, linter_state, active_linter)
	local autoformat_should_work = active_formatter ~= nil
	local autoformat_reason = formatter_state.reason
	if #formatter_state.formatters > 0 and not autoformat_should_work then
		autoformat_reason = formatter_state.reason .. " No routed formatter is currently available."
	end

	append(lines, "## Summary")
	append_kv(lines, "file", path ~= "" and path or "<no file>")
	append_kv(lines, "filetype", ft)
	append_kv(lines, "detected toolchain", formatter_state.detected_toolchain or "none")
	append_kv(lines, "detected root", formatter_state.detected_root or "-")
	append_kv(lines, "detected policy", formatter_state.detected_policy or "-")
	append_kv(lines, "autoformat should work", autoformat_should_work and "yes" or "no")
	append_kv(lines, "autoformat reason", autoformat_reason)
	append_kv(lines, "active formatter", active_formatter and active_formatter.name or "none")
	append_kv(lines, "active formatter cmd", active_formatter and active_formatter.command or "none")
	append_kv(lines, "active linter", active_linter and active_linter.name or "none")
	append_kv(lines, "active linter cmd", active_linter and active_linter.cmd or "none")
	append_kv(lines, "lint routing", linter_state.reason or "-")
	append(lines, "")
end

local function gather_states(bufnr)
	local monorepo = require("aalt.monorepo")
	local formatter_state = monorepo.formatter_state_for_buf(bufnr)
	local linter_state = monorepo.linter_state_for_buf(bufnr)
	return monorepo, formatter_state, linter_state
end

local function format_debug()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	local ft = vim.bo[bufnr].filetype
	local lines = { "# FormatDebug", "" }

	local _, formatter_state, linter_state = gather_states(bufnr)

	local ok_conform, conform = pcall(require, "conform")
	if not ok_conform then
		append(lines, "Conform not available.")
		open_report("format-debug", lines)
		return
	end

	local ok_lint, lint = pcall(require, "lint")
	local lint_entries = ok_lint and resolve_linter_entries(lint, linter_state.linters) or {}
	local active_linter = lint_entries[1]
	local active_formatter = conform.resolve_formatters(formatter_state.formatters, bufnr, false, true)[1]

	build_summary(lines, path, ft, formatter_state, active_formatter, linter_state, active_linter)
	append_policy_details(lines, formatter_state)
	append_formatter_candidates(lines, conform, bufnr, formatter_state)
	append(lines, "")
	append_linter_candidates(lines, lint_entries)
	append(lines, "")
	append_diagnostic_counts(lines, bufnr)

	open_report("format-debug", lines)
end

local function lint_debug()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	local ft = vim.bo[bufnr].filetype
	local lines = { "# LintDebug", "" }

	local _, formatter_state, linter_state = gather_states(bufnr)

	local ok_lint, lint = pcall(require, "lint")
	if not ok_lint then
		append(lines, "nvim-lint not available.")
		open_report("lint-debug", lines)
		return
	end

	local ok_conform, conform = pcall(require, "conform")
	local active_formatter = nil
	if ok_conform then
		active_formatter = conform.resolve_formatters(formatter_state.formatters, bufnr, false, true)[1]
	end

	local lint_entries = resolve_linter_entries(lint, linter_state.linters)
	local active_linter = lint_entries[1]

	build_summary(lines, path, ft, formatter_state, active_formatter, linter_state, active_linter)
	append_policy_details(lines, formatter_state)
	if ok_conform then
		append_formatter_candidates(lines, conform, bufnr, formatter_state)
		append(lines, "")
	end
	append_linter_candidates(lines, lint_entries)
	append(lines, "")
	append_diagnostic_counts(lines, bufnr)

	open_report("lint-debug", lines)
end

local function format_current_buffer()
	local ok_conform, conform = pcall(require, "conform")
	if not ok_conform then
		vim.notify("Conform not available.", vim.log.levels.ERROR, { title = "Format" })
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local format_config = require("aalt.lazy.autoformat")
	local monorepo = require("aalt.monorepo")
	local format_opts = format_config.format_opts_for_buf(bufnr)
	local formatter_state = monorepo.formatter_state_for_buf(bufnr)

	conform.format(vim.tbl_extend("force", format_opts, {
		async = false,
		bufnr = bufnr,
		formatters = formatter_state.formatters,
		stop_after_first = true,
	}))
end

function M.setup()
	vim.api.nvim_create_user_command("Format", format_current_buffer, {
		desc = "Format current buffer using routed formatter selection",
	})
	vim.api.nvim_create_user_command("FormatDebug", format_debug, {
		desc = "Show formatter routing/debug details for current buffer",
	})
	vim.api.nvim_create_user_command("LintDebug", lint_debug, {
		desc = "Show linter routing/debug details for current buffer",
	})
	vim.api.nvim_create_user_command("MonorepoClearCaches", function()
		require("aalt.monorepo").clear_caches()
		vim.notify("Cleared monorepo routing caches.", vim.log.levels.INFO, { title = "MonorepoClearCaches" })
	end, {
		desc = "Clear cached monorepo formatter/linter routing state",
	})
end

return M
