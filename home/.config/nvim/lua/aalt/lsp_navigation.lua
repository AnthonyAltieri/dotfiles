local M = {}

local setup_done = false
local last_errors = {}

local ACTIONS = {
	definition = {
		command = "LspDefinitionLastError",
		command_desc = "Open the most recent go-to-definition error report",
		debug_name = "go-to-definition-error",
		item_label = "definition",
		key = "gd",
		lsp_method = "definition",
		no_results = "No definition found.",
		result_label = "Definition",
		telescope_fn = "lsp_definitions",
		title = "Go To Definition",
	},
	implementation = {
		command = "LspImplementationLastError",
		command_desc = "Open the most recent go-to-implementation error report",
		debug_name = "go-to-implementation-error",
		item_label = "implementation",
		key = "gi/gI",
		lsp_method = "implementation",
		no_results = "No implementation found.",
		result_label = "Implementation",
		telescope_fn = "lsp_implementations",
		title = "Go To Implementation",
	},
	type_definition = {
		command = "LspTypeDefinitionLastError",
		command_desc = "Open the most recent go-to-type-definition error report",
		debug_name = "go-to-type-definition-error",
		item_label = "type definition",
		key = "gD",
		lsp_method = "type_definition",
		no_results = "No type definition found.",
		result_label = "Type Definition",
		telescope_fn = "lsp_type_definitions",
		title = "Go To Type Definition",
	},
}

local function append(lines, value)
	lines[#lines + 1] = value
end

local function append_kv(lines, key, value)
	append(lines, string.format("%-18s %s", key .. ":", tostring(value)))
end

local function append_multiline(lines, value)
	for _, line in ipairs(vim.split(tostring(value), "\n", { plain = true })) do
		append(lines, line)
	end
end

local function inspect_value(value)
	local ok, inspected = pcall(vim.inspect, value)
	if ok then
		return inspected
	end
	return "<could not inspect value>"
end

local function normalize_path(path)
	if not path or path == "" then
		return nil
	end
	return vim.fs.normalize(path)
end

local function source_context()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local clients = {}

	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		clients[#clients + 1] = {
			id = client.id,
			name = client.name,
			root_dir = client.root_dir or "-",
			offset_encoding = client.offset_encoding or "-",
		}
	end

	return {
		bufnr = bufnr,
		clients = clients,
		col = cursor[2] + 1,
		filetype = vim.bo[bufnr].filetype,
		line = cursor[1],
		path = vim.api.nvim_buf_get_name(bufnr),
		word = vim.fn.expand("<cword>"),
	}
end

local function open_report(action, lines)
	vim.cmd("botright new")
	local bufnr = vim.api.nvim_get_current_buf()
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "markdown"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	pcall(vim.api.nvim_buf_set_name, bufnr, "debug://" .. action.debug_name)
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = bufnr, silent = true, nowait = true })
end

local function build_report(action, reason, context, details)
	details = details or {}

	local lines = {
		"# " .. action.title .. " Error",
		"",
	}

	append_kv(lines, "Time", os.date("%Y-%m-%d %H:%M:%S"))
	append_kv(lines, "Reason", reason)
	append(lines, "")

	append(lines, "## Source")
	append_kv(lines, "Buffer", context.bufnr)
	append_kv(lines, "Path", context.path ~= "" and context.path or "<unnamed>")
	append_kv(lines, "Filetype", context.filetype ~= "" and context.filetype or "<none>")
	append_kv(lines, "Cursor", string.format("%d:%d", context.line, context.col))
	append_kv(lines, "Word", context.word ~= "" and context.word or "<none>")
	append(lines, "")

	append(lines, "## Attached LSP Clients")
	if #context.clients == 0 then
		append(lines, "No LSP clients were attached to the source buffer.")
	else
		for _, client in ipairs(context.clients) do
			append(
				lines,
				string.format(
					"- %s (id=%s, root=%s, offset=%s)",
					client.name,
					client.id,
					client.root_dir,
					client.offset_encoding
				)
			)
		end
	end
	append(lines, "")

	if details.item_count ~= nil then
		append(lines, "## " .. action.result_label .. " Result")
		append_kv(lines, "Item count", details.item_count)
		append(lines, "")
	end

	if details.item ~= nil then
		append(lines, "## Selected Item")
		append(lines, "```lua")
		append_multiline(lines, inspect_value(details.item))
		append(lines, "```")
		append(lines, "")
	end

	if details.options ~= nil then
		append(lines, "## Raw List Options")
		append(lines, "```lua")
		append_multiline(lines, inspect_value(details.options))
		append(lines, "```")
		append(lines, "")
	end

	if details.error ~= nil then
		append(lines, "## Error")
		append(lines, "```")
		append_multiline(lines, details.error)
		append(lines, "```")
		append(lines, "")
	end

	if details.stack ~= nil then
		append(lines, "## Stack Trace")
		append(lines, "```")
		append_multiline(lines, details.stack)
		append(lines, "```")
	end

	return lines
end

local function report_error(action, reason, context, details)
	last_errors[action.debug_name] = build_report(action, reason, context, details)
	vim.notify(
		action.key .. " failed: " .. reason .. ". Opened :" .. action.command .. " report.",
		vim.log.levels.ERROR,
		{ title = action.title }
	)
	open_report(action, last_errors[action.debug_name])
end

local function target_from_item(action, item)
	if type(item) ~= "table" then
		return nil, action.item_label .. " item is not a table"
	end

	local filename = item.filename
	if (not filename or filename == "") and item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
		filename = vim.api.nvim_buf_get_name(item.bufnr)
	end

	if not filename or filename == "" then
		return nil, action.item_label .. " item has no filename or resolvable buffer"
	end

	local lnum = tonumber(item.lnum)
	if not lnum or lnum < 1 then
		return nil, action.item_label .. " item has no valid line number"
	end

	local col = tonumber(item.col)
	if not col or col < 1 then
		return nil, action.item_label .. " item has no valid column number"
	end

	return {
		bufnr = item.bufnr,
		col = math.floor(col),
		filename = filename,
		lnum = math.floor(lnum),
	}
end

local function loaded_buffer_for_path(path)
	local normalized = normalize_path(path)
	if not normalized then
		return nil
	end

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) and normalize_path(vim.api.nvim_buf_get_name(bufnr)) == normalized then
			return bufnr
		end
	end

	return nil
end

local function open_target_buffer(target)
	local current_bufnr = vim.api.nvim_get_current_buf()
	local current_path = vim.api.nvim_buf_get_name(current_bufnr)

	if normalize_path(current_path) == normalize_path(target.filename) then
		return
	end

	if target.bufnr and vim.api.nvim_buf_is_valid(target.bufnr) and vim.api.nvim_buf_is_loaded(target.bufnr) then
		vim.api.nvim_set_current_buf(target.bufnr)
		return
	end

	local loaded_bufnr = loaded_buffer_for_path(target.filename)
	if loaded_bufnr then
		vim.api.nvim_set_current_buf(loaded_bufnr)
		return
	end

	vim.cmd("edit " .. vim.fn.fnameescape(target.filename))
end

local function is_current_location(target)
	local current_path = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
	local cursor = vim.api.nvim_win_get_cursor(0)

	return normalize_path(current_path) == normalize_path(target.filename)
		and cursor[1] == target.lnum
		and cursor[2] == target.col - 1
end

local function push_current_location_to_jumplist(target)
	if is_current_location(target) then
		return
	end

	vim.cmd([[normal! m']])
end

local function jump_to_item(action, item, context)
	context = context or source_context()
	local target, target_err = target_from_item(action, item)
	if not target then
		report_error(action, target_err, context, { item = item })
		return false
	end

	local ok, err = xpcall(function()
		push_current_location_to_jumplist(target)
		open_target_buffer(target)
		vim.api.nvim_win_set_cursor(0, { target.lnum, target.col - 1 })
		vim.cmd("normal! zv")
	end, debug.traceback)

	if not ok then
		report_error(action, "could not open " .. action.item_label .. " target", context, { error = err, item = item })
		return false
	end

	return true
end

function M.jump_to_definition_item(item, context)
	return jump_to_item(ACTIONS.definition, item, context)
end

function M.jump_to_implementation_item(item, context)
	return jump_to_item(ACTIONS.implementation, item, context)
end

function M.jump_to_type_definition_item(item, context)
	return jump_to_item(ACTIONS.type_definition, item, context)
end

local function open_multiple_locations(action, telescope_opts, context, options)
	local ok_require, builtin = pcall(require, "telescope.builtin")
	if not ok_require then
		report_error(action, "multiple " .. action.item_label .. "s returned, but telescope.builtin could not load", context, {
			error = builtin,
			item_count = #(options.items or {}),
			options = options,
		})
		return false
	end

	local ok_call, err = xpcall(function()
		vim.api.nvim_feedkeys("", "n", true)
		builtin[action.telescope_fn](telescope_opts or { layout_strategy = "vertical" })
	end, debug.traceback)

	if not ok_call then
		report_error(action, "telescope failed while opening multiple " .. action.item_label .. "s", context, {
			error = err,
			item_count = #(options.items or {}),
			options = options,
		})
		return false
	end

	return true
end

local function handle_location_list(action, options, opts)
	opts = opts or {}
	local context = opts.context or source_context()

	if type(options) ~= "table" then
		report_error(action, "LSP " .. action.item_label .. " callback did not receive an options table", context, {
			options = options,
		})
		return false
	end

	if type(options.items) ~= "table" then
		report_error(action, "LSP " .. action.item_label .. " callback did not receive an items table", context, {
			options = options,
		})
		return false
	end

	if #options.items == 0 then
		vim.notify(action.no_results, vim.log.levels.INFO, { title = action.title })
		return false
	end

	if #options.items == 1 then
		return jump_to_item(action, options.items[1], context)
	end

	return open_multiple_locations(action, opts.telescope, context, options)
end

function M.handle_definition_list(options, opts)
	return handle_location_list(ACTIONS.definition, options, opts)
end

function M.handle_implementation_list(options, opts)
	return handle_location_list(ACTIONS.implementation, options, opts)
end

function M.handle_type_definition_list(options, opts)
	return handle_location_list(ACTIONS.type_definition, options, opts)
end

local function go_to_location(action, opts)
	opts = opts or {}
	local context = source_context()

	local ok, err = xpcall(function()
		vim.lsp.buf[action.lsp_method]({
			on_list = function(options)
				local list_ok, list_err = xpcall(function()
					handle_location_list(action, options, {
						context = context,
						telescope = opts.telescope,
					})
				end, debug.traceback)

				if not list_ok then
					report_error(action, "failed while processing LSP " .. action.item_label .. " results", context, {
						error = list_err,
						options = options,
					})
				end
			end,
		})
	end, debug.traceback)

	if not ok then
		report_error(action, "could not request LSP " .. action.item_label .. "s", context, { error = err })
		return false
	end

	return true
end

function M.go_to_definition(opts)
	return go_to_location(ACTIONS.definition, opts)
end

function M.go_to_implementation(opts)
	return go_to_location(ACTIONS.implementation, opts)
end

function M.go_to_type_definition(opts)
	return go_to_location(ACTIONS.type_definition, opts)
end

local function open_last_error(action)
	local last_error = last_errors[action.debug_name]
	if not last_error then
		vim.notify("No " .. action.item_label .. " navigation error has been recorded.", vim.log.levels.INFO, {
			title = action.title,
		})
		return
	end

	open_report(action, last_error)
end

function M.open_last_definition_error()
	open_last_error(ACTIONS.definition)
end

function M.open_last_implementation_error()
	open_last_error(ACTIONS.implementation)
end

function M.open_last_type_definition_error()
	open_last_error(ACTIONS.type_definition)
end

function M.setup()
	if setup_done then
		return
	end
	setup_done = true

	for _, action in pairs(ACTIONS) do
		vim.api.nvim_create_user_command(action.command, function()
			open_last_error(action)
		end, {
			desc = action.command_desc,
		})
	end
end

return M
