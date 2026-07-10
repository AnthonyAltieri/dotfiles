local M = {}

local MOUSE_HOVER_DELAY_MS = 500

local mouse_hover_state = {
	delay_ms = MOUSE_HOVER_DELAY_MS,
	generation = 0,
	timer = nil,
	winid = nil,
}

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

local function client_mouse_position_params(bufnr, position)
	local line = vim.api.nvim_buf_get_lines(bufnr, position.line, position.line + 1, true)[1] or ""

	return function(client)
		return {
			textDocument = vim.lsp.util.make_text_document_params(bufnr),
			position = {
				line = position.line,
				character = vim.str_utfindex(line, client.offset_encoding or "utf-16", position.byte_col, false),
			},
		}
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

local function request_hover(callback, opts)
	opts = opts or {}

	local source_buf = opts.bufnr or vim.api.nvim_get_current_buf()
	local params = opts.position and client_mouse_position_params(source_buf, opts.position) or client_position_params()

	vim.lsp.buf_request_all(source_buf, "textDocument/hover", params, function(results, ctx)
		if opts.is_valid then
			if not opts.is_valid() then
				return
			end
		elseif vim.api.nvim_get_current_buf() ~= ctx.bufnr then
			return
		end

		local lines, format, message = M.hover_lines_from_results(results)
		if not lines or #lines == 0 then
			if not opts.silent then
				vim.notify(message or "No information available", vim.log.levels.INFO, { title = "Hover Preview" })
			end
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

local function close_mouse_hover()
	local winid = mouse_hover_state.winid
	mouse_hover_state.winid = nil

	if winid and vim.api.nvim_win_is_valid(winid) then
		pcall(vim.api.nvim_win_close, winid, true)
	end
end

local function cancel_mouse_hover()
	mouse_hover_state.generation = mouse_hover_state.generation + 1

	local timer = mouse_hover_state.timer
	mouse_hover_state.timer = nil
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end

	close_mouse_hover()
end

local function mouse_target()
	local mouse = vim.fn.getmousepos()
	local winid = tonumber(mouse.winid) or 0
	local line = tonumber(mouse.line) or 0
	local column = tonumber(mouse.column) or 0

	if winid == 0 or line < 1 or column < 1 or not vim.api.nvim_win_is_valid(winid) then
		return nil
	end

	if vim.api.nvim_win_get_config(winid).relative ~= "" then
		return nil
	end

	local bufnr = vim.api.nvim_win_get_buf(winid)
	if not vim.api.nvim_buf_is_loaded(bufnr) or line > vim.api.nvim_buf_line_count(bufnr) then
		return nil
	end

	local text = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, true)[1] or ""
	if column > #text then
		return nil
	end

	return {
		bufnr = bufnr,
		winid = winid,
		line = line - 1,
		byte_col = column - 1,
		changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
	}
end

local function mouse_target_is_valid(target, generation)
	if generation ~= mouse_hover_state.generation then
		return false
	end

	if not vim.api.nvim_win_is_valid(target.winid) or not vim.api.nvim_buf_is_loaded(target.bufnr) then
		return false
	end

	if vim.api.nvim_win_get_buf(target.winid) ~= target.bufnr then
		return false
	end

	if vim.api.nvim_buf_get_changedtick(target.bufnr) ~= target.changedtick then
		return false
	end

	local mouse = vim.fn.getmousepos()
	return mouse.winid == target.winid and mouse.line - 1 == target.line and mouse.column - 1 == target.byte_col
end

local function has_other_floating_preview(bufnr)
	local preview = vim.b[bufnr].lsp_floating_preview
	return type(preview) == "number"
		and preview ~= mouse_hover_state.winid
		and vim.api.nvim_win_is_valid(preview)
end

local function show_mouse_hover(target, generation)
	local is_valid = function()
		return mouse_target_is_valid(target, generation) and not has_other_floating_preview(target.bufnr)
	end

	request_hover(function(lines, format)
		if not is_valid() then
			return
		end

		local opts = M.float_options()
		opts.relative = "mouse"
		opts.focusable = false
		opts.focus = false
		opts.offset_x = 1

		local opened_win
		local ok = pcall(vim.api.nvim_win_call, target.winid, function()
			local _
			_, opened_win = vim.lsp.util.open_floating_preview(lines, format, opts)
		end)

		if ok and opened_win and vim.api.nvim_win_is_valid(opened_win) then
			mouse_hover_state.winid = opened_win
		end
	end, {
		bufnr = target.bufnr,
		position = target,
		is_valid = is_valid,
		silent = true,
	})
end

function M.handle_mouse_move()
	cancel_mouse_hover()
	local generation = mouse_hover_state.generation

	local target = mouse_target()
	if not target then
		return
	end

	if #vim.lsp.get_clients({ bufnr = target.bufnr, method = "textDocument/hover" }) == 0 then
		return
	end

	local timer
	timer = vim.defer_fn(function()
		if mouse_hover_state.timer == timer then
			mouse_hover_state.timer = nil
		end

		if mouse_target_is_valid(target, generation) and not has_other_floating_preview(target.bufnr) then
			show_mouse_hover(target, generation)
		end
	end, mouse_hover_state.delay_ms)
	mouse_hover_state.timer = timer
end

function M.setup_mouse_hover(opts)
	opts = opts or {}
	vim.validate("opts", opts, "table")
	vim.validate("opts.delay_ms", opts.delay_ms, "number", true)

	mouse_hover_state.delay_ms = math.max(0, opts.delay_ms or MOUSE_HOVER_DELAY_MS)
	cancel_mouse_hover()

	vim.keymap.set({ "n", "i" }, "<MouseMove>", M.handle_mouse_move, {
		desc = "Show LSP documentation under mouse",
		silent = true,
	})
end

function M.show_float()
	cancel_mouse_hover()
	request_hover(function(lines, format)
		local opts = M.float_options()
		opts.focus_id = "textDocument/hover"
		vim.lsp.util.open_floating_preview(lines, format, opts)
	end)
end

function M.show_split()
	cancel_mouse_hover()
	request_hover(function(lines, format)
		open_split(lines, format)
	end)
end

return M
