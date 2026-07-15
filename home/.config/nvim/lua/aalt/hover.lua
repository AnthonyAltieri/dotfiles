local M = {}

local MOUSE_HOVER_DELAY_MS = 500

local mouse_hover_state = {
	delay_ms = MOUSE_HOVER_DELAY_MS,
	generation = 0,
	timer = nil,
	winid = nil,
}

local active_session
local pending_standard_hover

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

local function client_position_params(source_buf, source_cursor, verbosity_level)
	local row = source_cursor[1] - 1
	local byte_col = source_cursor[2]

	return function(client)
		local ret = {
			textDocument = vim.lsp.util.make_text_document_params(source_buf),
			position = {
				line = row,
				character = vim.lsp.util.character_offset(source_buf, row, byte_col, client.offset_encoding),
			},
		}

		if client.name == "tsgo" and verbosity_level ~= nil then
			ret.verbosityLevel = verbosity_level
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
	local params
	if opts.position then
		params = client_mouse_position_params(source_buf, opts.position)
	else
		params = client_position_params(source_buf, vim.api.nvim_win_get_cursor(0))
	end

	return vim.lsp.buf_request_all(source_buf, "textDocument/hover", params, function(results, ctx)
		if opts.on_response then
			opts.on_response()
		end

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
	local can_increase_verbosity = false

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
		return nil, nil, empty_response and "Empty hover response" or "No information available", false
	end
	table.sort(client_ids)

	local lines = {}
	local format = "markdown"

	for _, client_id in ipairs(client_ids) do
		local result = hover_results[client_id]
		local client = vim.lsp.get_client_by_id(client_id)
		if client and client.name == "tsgo" then
			can_increase_verbosity = can_increase_verbosity or result.canIncreaseVerbosity == true
		end

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
	return lines, format, nil, can_increase_verbosity
end

local function cancel_session_request(session)
	local cancel = session.cancel_request
	session.cancel_request = nil
	if cancel then
		pcall(cancel)
	end
end

local function close_session(session, close_float)
	if not session then
		return
	end

	session.request_seq = session.request_seq + 1
	cancel_session_request(session)

	if active_session == session then
		active_session = nil
	end
	if session.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
		session.augroup = nil
	end

	local float_win = session.float_win
	session.float_buf = nil
	session.float_win = nil
	if
		vim.api.nvim_buf_is_valid(session.source_buf)
		and vim.b[session.source_buf].lsp_floating_preview == float_win
	then
		vim.b[session.source_buf].lsp_floating_preview = nil
	end
	if close_float ~= false and float_win and vim.api.nvim_win_is_valid(float_win) then
		pcall(vim.api.nvim_win_close, float_win, true)
	end
end

local function cancel_standard_hover_request(request)
	if not request then
		return false
	end

	if pending_standard_hover == request then
		pending_standard_hover = nil
	end
	request.cancelled = true

	local cancel = request.cancel
	request.cancel = nil
	if cancel then
		pcall(cancel)
	end

	return true
end

local function hover_source_buffer(win)
	local ok, source_buf = pcall(vim.api.nvim_win_get_var, win, "textDocument/hover")
	if ok and type(source_buf) == "number" then
		return source_buf
	end
end

local function close_standard_hover(win, source_buf)
	if
		type(win) ~= "number"
		or not vim.api.nvim_win_is_valid(win)
		or not vim.api.nvim_buf_is_valid(source_buf)
		or hover_source_buffer(win) ~= source_buf
		or vim.b[source_buf].lsp_floating_preview ~= win
	then
		return false
	end

	vim.api.nvim_win_close(win, true)
	return true
end

function M.close_float()
	local current_win = vim.api.nvim_get_current_win()
	local current_buf = vim.api.nvim_get_current_buf()
	if active_session and (current_win == active_session.source_win or current_win == active_session.float_win) then
		close_session(active_session)
		return true
	end

	local focused_hover_source = hover_source_buffer(current_win)
	local cancelled_pending = false
	if
		pending_standard_hover
		and (
			current_buf == pending_standard_hover.source_buf
			or focused_hover_source == pending_standard_hover.source_buf
		)
	then
		cancelled_pending = cancel_standard_hover_request(pending_standard_hover)
	end

	if close_standard_hover(vim.b[current_buf].lsp_floating_preview, current_buf) then
		return true
	end

	if focused_hover_source ~= nil and close_standard_hover(current_win, focused_hover_source) then
		return true
	end

	return cancelled_pending
end

local function source_is_unchanged(session)
	return active_session == session
		and vim.api.nvim_buf_is_valid(session.source_buf)
		and vim.api.nvim_buf_is_loaded(session.source_buf)
		and vim.api.nvim_win_is_valid(session.source_win)
		and vim.api.nvim_win_get_buf(session.source_win) == session.source_buf
		and vim.api.nvim_buf_get_changedtick(session.source_buf) == session.source_changedtick
		and vim.deep_equal(vim.api.nvim_win_get_cursor(session.source_win), session.source_cursor)
end

local function float_is_valid(session)
	return session.float_buf
		and vim.api.nvim_buf_is_valid(session.float_buf)
		and session.float_win
		and vim.api.nvim_win_is_valid(session.float_win)
		and vim.api.nvim_win_get_buf(session.float_win) == session.float_buf
end

local function session_float_options(session)
	local opts = M.float_options()
	opts.focus_id = "textDocument/hover"
	opts.focus = false
	if session.tsgo_client_id then
		opts.title = " Hover types [+/-] "
		opts.title_pos = "center"
	end
	return opts
end

local function resize_session_float(session, opts)
	local contents = vim.api.nvim_buf_get_lines(session.float_buf, 0, -1, false)
	local sizing = vim.deepcopy(opts)
	sizing._update_win = nil
	sizing.wrap_at = vim.api.nvim_win_get_width(session.source_win)

	local width, height = vim.lsp.util._make_floating_popup_size(contents, sizing)
	local config = vim.lsp.util.make_floating_popup_options(width, height, sizing)
	if config.width < 1 or config.height < 1 then
		return
	end

	vim.api.nvim_win_set_config(session.float_win, config)
	local visible_height = vim.api.nvim_win_text_height(session.float_win, {}).all
	if visible_height > 0 and visible_height < config.height then
		vim.api.nvim_win_set_config(session.float_win, { height = visible_height })
	end
end

local request_session_level

local function adjust_session_level(session, delta)
	if not source_is_unchanged(session) or not float_is_valid(session) then
		close_session(session)
		return
	end
	if session.request_pending then
		return
	end
	if delta > 0 and not session.can_increase_verbosity then
		return
	end

	local next_level = session.displayed_level + delta
	if next_level < 0 then
		return
	end

	request_session_level(session, next_level, false)
end

local function install_session_mappings(session)
	local map_opts = function(desc)
		return { buffer = session.float_buf, silent = true, nowait = true, desc = desc }
	end

	local close = function()
		close_session(session)
	end
	vim.keymap.set("n", "q", close, map_opts("Close hover preview"))
	vim.keymap.set("n", "<Esc>", close, map_opts("Close hover preview"))

	if session.tsgo_client_id then
		vim.keymap.set("n", "+", function()
			adjust_session_level(session, 1)
		end, map_opts("Expand hover type details"))
		vim.keymap.set("n", "-", function()
			adjust_session_level(session, -1)
		end, map_opts("Collapse hover type details"))
	end
end

local function render_session_float(session, lines, format)
	if not source_is_unchanged(session) then
		return false
	end

	local updating = float_is_valid(session)
	local float_buf
	local float_win
	local ok = pcall(vim.api.nvim_win_call, session.source_win, function()
		local opts = session_float_options(session)
		if updating then
			opts._update_win = session.float_win
		end
		float_buf, float_win = vim.lsp.util.open_floating_preview(lines, format, opts)
		if updating then
			resize_session_float(session, opts)
		end
	end)
	if not ok or not float_buf or not float_win or not vim.api.nvim_win_is_valid(float_win) then
		return false
	end
	if updating then
		return float_buf == session.float_buf and float_win == session.float_win
	end

	session.float_buf = float_buf
	session.float_win = float_win
	install_session_mappings(session)

	session.augroup = vim.api.nvim_create_augroup("aalt-hover-session-" .. float_win, { clear = true })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = session.augroup,
		pattern = tostring(float_win),
		once = true,
		callback = function()
			if active_session == session then
				close_session(session, false)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinEnter", {
		group = session.augroup,
		callback = function()
			local current_win = vim.api.nvim_get_current_win()
			if active_session == session and current_win ~= session.source_win and current_win ~= session.float_win then
				close_session(session)
			end
		end,
	})

	return true
end

local function apply_session_result(session, err, result, ctx, level, initial, request_seq)
	if session.request_seq ~= request_seq then
		return
	end
	if not source_is_unchanged(session) then
		close_session(session)
		return
	end
	if initial and vim.api.nvim_get_current_win() ~= session.source_win then
		close_session(session)
		return
	end

	session.cancel_request = nil
	session.request_pending = false

	local lines, format, message, can_increase_verbosity = M.hover_lines_from_results({
		[session.tsgo_client_id] = { err = err, result = result, context = ctx },
	})
	if not lines or #lines == 0 then
		if initial then
			close_session(session)
			vim.notify(message or "No information available", vim.log.levels.INFO, { title = "Hover Preview" })
		end
		return
	end

	lines, format = M.format_hover_lines(lines, format)
	session.displayed_level = level
	session.can_increase_verbosity = can_increase_verbosity == true

	if not render_session_float(session, lines, format) then
		close_session(session)
	end
end

request_session_level = function(session, level, initial)
	if not source_is_unchanged(session) then
		close_session(session)
		return
	end
	local tsgo_client
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = session.source_buf, method = "textDocument/hover" })) do
		if client.id == session.tsgo_client_id then
			tsgo_client = client
			break
		end
	end
	if not tsgo_client then
		close_session(session)
		return
	end

	session.request_seq = session.request_seq + 1
	local request_seq = session.request_seq
	cancel_session_request(session)
	session.request_pending = true

	local completed = false
	local params = client_position_params(session.source_buf, session.source_cursor, level)
	local request_ok, request_id = tsgo_client:request(
		"textDocument/hover",
		params(tsgo_client, session.source_buf),
		function(err, result, ctx)
			completed = true
			apply_session_result(session, err, result, ctx, level, initial, request_seq)
		end,
		session.source_buf
	)
	if not request_ok then
		session.request_pending = false
		close_session(session)
		return
	end
	local cancel = function()
		pcall(tsgo_client.cancel_request, tsgo_client, request_id)
	end

	if not completed and session.request_seq == request_seq and active_session == session then
		session.cancel_request = cancel
	elseif cancel and active_session ~= session then
		pcall(cancel)
	end
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

local function has_blocking_hover(bufnr)
	if active_session and active_session.source_buf == bufnr and source_is_unchanged(active_session) then
		return true
	end

	local preview = vim.b[bufnr].lsp_floating_preview
	return type(preview) == "number" and preview ~= mouse_hover_state.winid and vim.api.nvim_win_is_valid(preview)
end

local function show_mouse_hover(target, generation)
	local is_valid = function()
		return mouse_target_is_valid(target, generation) and not has_blocking_hover(target.bufnr)
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

		if mouse_target_is_valid(target, generation) and not has_blocking_hover(target.bufnr) then
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
	cancel_standard_hover_request(pending_standard_hover)
	local source_buf = vim.api.nvim_get_current_buf()
	local source_win = vim.api.nvim_get_current_win()
	local source_cursor = vim.api.nvim_win_get_cursor(source_win)

	if
		active_session
		and active_session.source_buf == source_buf
		and active_session.source_win == source_win
		and vim.deep_equal(active_session.source_cursor, source_cursor)
		and source_is_unchanged(active_session)
		and float_is_valid(active_session)
	then
		vim.api.nvim_set_current_win(active_session.float_win)
		vim.cmd.stopinsert()
		return
	end

	close_session(active_session)

	local hover_clients = vim.lsp.get_clients({ bufnr = source_buf, method = "textDocument/hover" })
	if #hover_clients == 0 then
		vim.notify("No hover-capable language server attached", vim.log.levels.INFO, { title = "Hover Preview" })
		return
	end

	local tsgo_client_id
	for _, client in ipairs(hover_clients) do
		if client.name == "tsgo" then
			tsgo_client_id = client.id
			break
		end
	end
	if not tsgo_client_id then
		local request = {
			cancel = nil,
			cancelled = false,
			source_buf = source_buf,
		}
		pending_standard_hover = request

		local completed = false
		local cancel = request_hover(function(lines, format)
			local opts = M.float_options()
			opts.focus_id = "textDocument/hover"
			vim.lsp.util.open_floating_preview(lines, format, opts)
		end, {
			bufnr = source_buf,
			is_valid = function()
				return not request.cancelled and vim.api.nvim_get_current_buf() == source_buf
			end,
			on_response = function()
				completed = true
				request.cancel = nil
				if pending_standard_hover == request then
					pending_standard_hover = nil
				end
			end,
		})
		if not completed and pending_standard_hover == request then
			request.cancel = cancel
		end
		return
	end

	local session = {
		source_buf = source_buf,
		source_win = source_win,
		source_cursor = source_cursor,
		source_changedtick = vim.api.nvim_buf_get_changedtick(source_buf),
		tsgo_client_id = tsgo_client_id,
		displayed_level = 0,
		can_increase_verbosity = false,
		request_pending = false,
		request_seq = 0,
	}
	active_session = session
	request_session_level(session, 0, true)
end

function M.show_split()
	cancel_mouse_hover()
	request_hover(function(lines, format)
		open_split(lines, format)
	end)
end

return M
