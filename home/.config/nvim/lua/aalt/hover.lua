local M = {}

local function bounded(value, lower, upper)
	upper = math.max(1, upper)
	lower = math.min(lower, upper)
	return math.max(lower, math.min(value, upper))
end

local function display_width(lines)
	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	return width
end

local function split_lines(value)
	return vim.split(value or "", "\n", { trimempty = true })
end

local function trim(value)
	return vim.trim(value or "")
end

local function nonspace_before(value, index)
	for i = index - 1, 1, -1 do
		local ch = value:sub(i, i)
		if ch ~= " " and ch ~= "\t" then
			return ch
		end
	end
	return ""
end

local function nonspace_after(value, index)
	for i = index + 1, #value do
		local ch = value:sub(i, i)
		if ch ~= " " and ch ~= "\t" then
			return ch
		end
	end
	return ""
end

local function hover_has_content(contents)
	if type(contents) == "string" then
		return #contents > 0
	end

	if type(contents) ~= "table" then
		return false
	end

	local value = vim.tbl_get(contents, "value")
		or vim.tbl_get(contents, 1, "value")
		or contents[1]
		or ""
	return #value > 0
end

local function client_position_params(params)
	local win = vim.api.nvim_get_current_win()
	return function(client)
		local ret = vim.lsp.util.make_position_params(win, client.offset_encoding)
		if params then
			ret = vim.tbl_extend("force", ret, params)
		end
		return ret
	end
end

local function split_window_width(lines)
	local screen_width = vim.o.columns
	local natural_width = display_width(lines) + 4
	local max_width = math.min(100, math.floor(screen_width * 0.55))
	return bounded(natural_width, math.min(60, max_width), max_width)
end

local function append_formatted_line(lines, indent, line)
	local trimmed = trim(line)
	if trimmed == "" then
		return
	end
	lines[#lines + 1] = string.rep("  ", math.max(0, indent)) .. trimmed
end

local function looks_like_typescript_hover(line)
	local stripped = trim(line)
	if #stripped < 40 then
		return false
	end

	return stripped:find("{", 1, true) ~= nil
		and (
			stripped:find(":%s*{") ~= nil
			or stripped:find("=>%s*{") ~= nil
			or stripped:find("%b()") ~= nil
			or stripped:find(";", 1, true) ~= nil
		)
end

local function format_typescript_hover_line(line)
	if not looks_like_typescript_hover(line) then
		return { line }, false
	end

	local formatted = {}
	local current = {}
	local indent = 0
	local quote = nil
	local escaped = false
	local angle_depth = 0
	local changed = false

	local function current_text()
		return table.concat(current)
	end

	local function reset_current(value)
		current = value and { value } or {}
	end

	local function push_current()
		local text = current_text()
		if trim(text) ~= "" then
			append_formatted_line(formatted, indent, text)
		end
		reset_current()
	end

	local i = 1
	while i <= #line do
		local ch = line:sub(i, i)
		local next_ch = line:sub(i + 1, i + 1)
		local prev_ch = line:sub(i - 1, i - 1)

		if quote then
			current[#current + 1] = ch
			if escaped then
				escaped = false
			elseif ch == "\\" then
				escaped = true
			elseif ch == quote then
				quote = nil
			end
		elseif ch == '"' or ch == "'" or ch == "`" then
			quote = ch
			current[#current + 1] = ch
		elseif ch == "<" then
			angle_depth = angle_depth + 1
			current[#current + 1] = ch
		elseif ch == ">" then
			if prev_ch ~= "=" and angle_depth > 0 then
				angle_depth = angle_depth - 1
			end
			current[#current + 1] = ch
		elseif ch == "{" then
			current[#current + 1] = ch
			push_current()
			indent = indent + 1
			changed = true
		elseif ch == "}" then
			push_current()
			indent = math.max(0, indent - 1)
			reset_current("}")
			changed = true
		elseif ch == ";" and indent > 0 then
			current[#current + 1] = ch
			push_current()
			changed = true
		elseif
			ch == "|"
			and indent > 0
			and angle_depth == 0
			and (nonspace_before(line, i) == "}" or nonspace_before(line, i) == "]" or nonspace_after(line, i) == "{")
		then
			push_current()
			reset_current("|")
			changed = true
		elseif ch == "," and indent == 0 and #current_text() > 90 then
			current[#current + 1] = ch
			push_current()
			changed = true
		else
			if ch ~= " " or trim(current_text()) ~= "" or next_ch ~= " " then
				current[#current + 1] = ch
			end
		end

		i = i + 1
	end

	push_current()

	if not changed or #formatted <= 1 then
		return { line }, false
	end

	return formatted, true
end

function M.format_hover_lines(lines, format)
	local formatted = {}
	local in_fence = false
	local in_typescript_fence = false
	local changed = false

	for _, line in ipairs(lines or {}) do
		local fence_lang = line:match("^```%s*([%w_-]*)")
		if fence_lang ~= nil then
			formatted[#formatted + 1] = line
			if in_fence then
				in_fence = false
				in_typescript_fence = false
			else
				in_fence = true
				in_typescript_fence = fence_lang == "typescript" or fence_lang == "ts" or fence_lang == "tsx"
			end
		elseif in_typescript_fence then
			local next_lines, line_changed = format_typescript_hover_line(line)
			vim.list_extend(formatted, next_lines)
			changed = changed or line_changed
		elseif not in_fence then
			local next_lines, line_changed = format_typescript_hover_line(line)
			if line_changed then
				formatted[#formatted + 1] = "```typescript"
				vim.list_extend(formatted, next_lines)
				formatted[#formatted + 1] = "```"
				changed = true
			else
				formatted[#formatted + 1] = line
			end
		else
			formatted[#formatted + 1] = line
		end
	end

	if changed then
		return formatted, "markdown"
	end

	return formatted, format
end

local function open_split(lines, format)
	local buf = vim.api.nvim_create_buf(false, true)
	local title = vim.fn.expand("<cword>")
	if title == "" then
		title = "hover"
	end

	pcall(vim.api.nvim_buf_set_name, buf, "type-hover://" .. title .. "-" .. buf)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = format == "plaintext" and "text" or "markdown"

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.cmd("botright vertical split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_width(win, split_window_width(lines))

	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].conceallevel = format == "markdown" and 2 or 0

	local close = function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	vim.keymap.set("n", "q", close, { buffer = buf, silent = true, nowait = true, desc = "Close hover preview" })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true, nowait = true, desc = "Close hover preview" })
end

function M.float_options()
	local max_width = bounded(
		math.floor(vim.o.columns * 0.78),
		math.min(60, vim.o.columns - 4),
		math.min(120, vim.o.columns - 4)
	)
	local max_height = bounded(
		math.floor(vim.o.lines * 0.6),
		math.min(12, vim.o.lines - 4),
		math.min(36, vim.o.lines - 4)
	)

	return {
		border = "rounded",
		focusable = true,
		max_height = max_height,
		max_width = max_width,
		wrap = true,
	}
end

local function request_hover(callback)
	local source_buf = vim.api.nvim_get_current_buf()
	vim.lsp.buf_request_all(source_buf, "textDocument/hover", client_position_params(), function(results, ctx)
		if vim.api.nvim_get_current_buf() ~= ctx.bufnr then
			return
		end

		local lines, format, message = M.hover_lines_from_results(results)
		if not lines or #lines == 0 then
			vim.notify(message or "No information available", vim.log.levels.INFO, { title = "Hover Preview" })
			return
		end

		callback(M.format_hover_lines(lines, format))
	end)
end

function M.hover_lines_from_results(results)
	local hover_results = {}
	local empty_response = false

	for client_id, response in pairs(results or {}) do
		local err = response.err
		local result = response.result

		if err then
			vim.lsp.log.error(err.code, err.message)
		elseif result and result.contents then
			if hover_has_content(result.contents) then
				hover_results[client_id] = result
			else
				empty_response = true
			end
		end
	end

	local client_ids = vim.tbl_keys(hover_results)
	if #client_ids == 0 then
		return nil, nil, empty_response and "Empty hover response" or "No information available"
	end

	local lines = {}
	local format = "markdown"

	for _, client_id in ipairs(client_ids) do
		local result = hover_results[client_id]
		local client = vim.lsp.get_client_by_id(client_id)

		if #client_ids > 1 then
			lines[#lines + 1] = string.format("# %s", client and client.name or ("client " .. client_id))
		end

		if type(result.contents) == "table" and result.contents.kind == "plaintext" then
			if #client_ids == 1 then
				format = "plaintext"
				vim.list_extend(lines, split_lines(result.contents.value))
			else
				lines[#lines + 1] = "```"
				vim.list_extend(lines, split_lines(result.contents.value))
				lines[#lines + 1] = "```"
			end
		else
			vim.list_extend(lines, vim.lsp.util.convert_input_to_markdown_lines(result.contents))
		end

		lines[#lines + 1] = "---"
	end

	lines[#lines] = nil
	return lines, format, nil
end

function M.show_float()
	request_hover(function(lines, format)
		local opts = M.float_options()
		opts.focus_id = "textDocument/hover"
		vim.lsp.util.open_floating_preview(lines, format, opts)
	end)
end

function M.show_split()
	request_hover(function(lines, format)
		open_split(lines, format)
	end)
end

return M
