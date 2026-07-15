#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua"

run_case() {
	local name="$1"
	local script_path="${TMP_DIR}/${name}.lua"

	cat >"$script_path"

	REPO_LUA="$REPO_LUA" \
	TMP_DIR="$TMP_DIR" \
	TEST_SCRIPT="$script_path" \
	NVIM_LOG_FILE="${TMP_DIR}/${name}.log" \
	XDG_CACHE_HOME="${TMP_DIR}/cache-${name}" \
	XDG_DATA_HOME="${TMP_DIR}/data-${name}" \
	XDG_STATE_HOME="${TMP_DIR}/state-${name}" \
	nvim --clean --headless -i NONE \
		--cmd 'lua vim.loader.enable(false)' \
		--cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
		+"lua local ok, err = xpcall(function() dofile(vim.fn.getenv('TEST_SCRIPT')) end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
		+qa!
	echo
}

run_case "capability_merge" <<'EOF'
local configured = {}
local original_lsp_config = vim.lsp.config

package.loaded["aalt.lsp_navigation"] = { setup = function() end }
package.loaded["aalt.mason_packages"] = { ensure_installed = function() return {} end }
package.loaded["blink.cmp"] = {
	get_lsp_capabilities = function()
		return { experimental = { sentinel = true } }
	end,
}
package.loaded["mason"] = { setup = function() end }
package.loaded["mason-tool-installer"] = { setup = function() end }
package.loaded["mason-lspconfig"] = { setup = function() end }

vim.lsp.config = function(name, config)
	configured[name] = vim.deepcopy(config)
end

local config_path = vim.fn.getenv("REPO_LUA") .. "/aalt/lazy/lsp.lua"
local plugin = assert(dofile(config_path)[1])
plugin.config()
vim.lsp.config = original_lsp_config

local tsgo_experimental = assert(configured.tsgo.capabilities.experimental)
assert(tsgo_experimental.hoverVerbosityLevel == true, "tsgo should advertise hover verbosity")
assert(tsgo_experimental.sentinel == true, "tsgo capability merge should preserve shared fields")

local pyright_experimental = assert(configured.pyright.capabilities.experimental)
assert(pyright_experimental.sentinel == true, "other servers should retain shared experimental fields")
assert(pyright_experimental.hoverVerbosityLevel == nil, "hover verbosity should remain tsgo-specific")

print("ok tsgo hover verbosity capability merge")
EOF

run_case "non_tsgo_session" <<'EOF'
local hover = require("aalt.hover")
local set_path = vim.fn.getenv("REPO_LUA") .. "/aalt/set.lua"
dofile(set_path)
local source_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(source_buf, vim.fn.getenv("TMP_DIR") .. "/non-tsgo.lua")
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "value" })
local source_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
local client = { id = 7, name = "lua_ls", offset_encoding = "utf-16", stop = function() end }
local clients = { client }
local request_count = 0
local defer_response = false
local deferred_request
local notifications = {}
local original_get_clients = vim.lsp.get_clients
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_buf_request_all = vim.lsp.buf_request_all
local original_notify = vim.notify

vim.lsp.get_clients = function()
	return clients
end
vim.lsp.get_client_by_id = function(client_id)
	return client_id == client.id and client or nil
end
vim.lsp.buf_request_all = function(bufnr, method, params, callback)
	request_count = request_count + 1
	local request_params = params(client, bufnr)
	assert(method == "textDocument/hover", method)
	assert(request_params.verbosityLevel == nil, vim.inspect(request_params))
	local results = {
		[client.id] = {
			result = { contents = { kind = "markdown", value = "```lua\nlocal value: string\n```" } },
		},
	}
	local ctx = { bufnr = bufnr }
	if defer_response then
		deferred_request = { callback = callback, results = results, ctx = ctx, cancelled = false }
		return function()
			deferred_request.cancelled = true
		end
	end
	callback(results, ctx)
	return function() end
end
vim.notify = function(message, level, opts)
	notifications[#notifications + 1] = { message = message, level = level, opts = opts }
end

local function find_mapping(bufnr, lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
		if mapping.lhs == lhs then
			return mapping
		end
	end
end

local function global_mapping_callback(lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
		if mapping.lhs == lhs then
			assert(type(mapping.callback) == "function", lhs .. " should use a Lua callback")
			return mapping.callback
		end
	end
	error("missing global mapping: " .. lhs)
end

local escape = global_mapping_callback("<Esc>")

hover.show_float()
assert(request_count == 1, "non-tsgo hover should request once")
local float_win = assert(vim.b[source_buf].lsp_floating_preview)
local float_buf = vim.api.nvim_win_get_buf(float_win)
assert(find_mapping(float_buf, "+") == nil, "non-tsgo hover should not map expansion")
assert(find_mapping(float_buf, "-") == nil, "non-tsgo hover should not map collapse")
assert(vim.api.nvim_get_current_win() == source_win, "initial non-tsgo hover should retain source focus")

vim.fn.setreg("/", "value")
vim.cmd("let v:hlsearch = 1")
escape()
assert(not vim.api.nvim_win_is_valid(float_win), "source Escape should close the non-tsgo hover")
assert(vim.v.hlsearch == 0, "source Escape should retain nohlsearch behavior")

hover.show_float()
assert(request_count == 2, "reopened non-tsgo hover should request again")
float_win = assert(vim.b[source_buf].lsp_floating_preview)
hover.show_float()
assert(vim.api.nvim_get_current_win() == float_win, "second non-tsgo hover should focus the float")
assert(request_count == 3, "non-tsgo hover should retain the existing aggregate request behavior")
escape()
assert(not vim.api.nvim_win_is_valid(float_win), "focused Escape should close the non-tsgo hover")

vim.api.nvim_set_current_win(source_win)
local _, unrelated_win = vim.lsp.util.open_floating_preview({ "unrelated" }, "markdown", hover.float_options())
escape()
assert(vim.api.nvim_win_is_valid(unrelated_win), "Escape should not close an unrelated floating preview")
vim.api.nvim_win_close(unrelated_win, true)

vim.api.nvim_set_current_win(source_win)
defer_response = true
hover.show_float()
assert(request_count == 4, "pending non-tsgo hover should start a request")
escape()
assert(deferred_request.cancelled == true, "source Escape should cancel a pending non-tsgo hover")
deferred_request.callback(deferred_request.results, deferred_request.ctx)
assert(vim.b[source_buf].lsp_floating_preview == nil, "a stale non-tsgo response should stay closed")
defer_response = false

clients = {}
hover.show_float()
assert(request_count == 4, "no-client hover should not start a request")
assert(#notifications == 1, "no-client hover should notify once")
assert(notifications[1].message:find("No hover-capable language server attached", 1, true), notifications[1].message)

vim.lsp.get_clients = original_get_clients
vim.lsp.get_client_by_id = original_get_client_by_id
vim.lsp.buf_request_all = original_buf_request_all
vim.notify = original_notify

print("ok non-tsgo and no-client hover fallbacks")
EOF

run_case "interactive_session" <<'EOF'
local hover = require("aalt.hover")
local set_path = vim.fn.getenv("REPO_LUA") .. "/aalt/set.lua"
dofile(set_path)
local line = 'const icon = "😀"; setSpanAttrs({})'
local source_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(source_buf, vim.fn.getenv("TMP_DIR") .. "/hover.ts")
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { line })
local source_win = vim.api.nvim_get_current_win()
local byte_col = assert(line:find("setSpanAttrs", 1, true)) - 1
vim.api.nvim_win_set_cursor(source_win, { 1, byte_col })
vim.cmd("belowright new")
local unrelated_win = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(source_win)

local requests = {}
local client_requests = {}
local next_request_id = 0
local clients = {
	{ id = 1, name = "tsgo", offset_encoding = "utf-16", stop = function() end },
	{ id = 2, name = "other-ls", offset_encoding = "utf-8", stop = function() end },
}
local clients_by_id = { [1] = clients[1], [2] = clients[2] }
clients[1].request = function(self, method, params, callback, bufnr)
	next_request_id = next_request_id + 1
	local request = {
		kind = "client",
		bufnr = bufnr,
		method = method,
		callback = callback,
		params = { [self.id] = params },
		cancelled = false,
		request_id = next_request_id,
	}
	requests[#requests + 1] = request
	client_requests[next_request_id] = request
	return true, next_request_id
end
clients[1].cancel_request = function(_, request_id)
	client_requests[request_id].cancelled = true
end
local original_get_clients = vim.lsp.get_clients
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_buf_request_all = vim.lsp.buf_request_all
local original_getmousepos = vim.fn.getmousepos

vim.lsp.get_clients = function()
	return clients
end
vim.lsp.get_client_by_id = function(client_id)
	return clients_by_id[client_id]
end
vim.lsp.buf_request_all = function(bufnr, method, params, callback)
	local request = {
		kind = "all",
		bufnr = bufnr,
		method = method,
		callback = callback,
		params = {},
		cancelled = false,
	}
	for _, client in ipairs(clients) do
		request.params[client.id] = params(client, bufnr)
	end
	requests[#requests + 1] = request
	return function()
		request.cancelled = true
	end
end

local function hover_result(value, can_increase)
	local result = {
		contents = { kind = "markdown", value = value },
	}
	if can_increase ~= nil then
		result.canIncreaseVerbosity = can_increase
	end
	return result
end

local function deliver(request, value, can_increase)
	if request.kind == "client" then
		request.callback(nil, hover_result(value, can_increase), { bufnr = source_buf, client_id = 1 })
	else
		request.callback({
			[1] = { result = hover_result(value, can_increase) },
			[2] = { result = nil },
		}, { bufnr = source_buf })
	end
end

local compact = "```typescript\nfunction setSpanAttrs(attrs: Attributes): void\n```"
local expanded = table.concat({
	"```typescript",
	"function setSpanAttrs(attrs: { [attributeKey: string]: AttributeValue | undefined }): void",
	"```",
}, "\n")
local nested = table.concat({
	"```typescript",
	"function setSpanAttrs(attrs: { [attributeKey: string]: string | number | boolean | undefined }): void",
	"```",
}, "\n")

local function assert_request(request, level)
	assert(request.bufnr == source_buf, "hover should retain the source buffer")
	assert(request.method == "textDocument/hover", request.method)
	assert(request.params[1].verbosityLevel == level, vim.inspect(request.params[1]))
	if request.params[2] then
		assert(request.params[2].verbosityLevel == nil, vim.inspect(request.params[2]))
	end
	assert(request.params[1].position.line == 0, vim.inspect(request.params[1]))
	assert(request.params[1].position.character == vim.str_utfindex(line, "utf-16", byte_col, false))
	if request.params[2] then
		assert(request.params[2].position.character == vim.str_utfindex(line, "utf-8", byte_col, false))
	end
end

local function mapping_callback(bufnr, lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
		if mapping.lhs == lhs then
			assert(type(mapping.callback) == "function", lhs .. " should use a Lua callback")
			return mapping.callback
		end
	end
	error("missing hover mapping: " .. lhs)
end

local function has_mapping(bufnr, lhs)
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
		if mapping.lhs == lhs then
			return true
		end
	end
	return false
end

local function global_mapping_callback(lhs)
	for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
		if mapping.lhs == lhs then
			assert(type(mapping.callback) == "function", lhs .. " should use a Lua callback")
			return mapping.callback
		end
	end
	error("missing global mapping: " .. lhs)
end

local escape = global_mapping_callback("<Esc>")

hover.show_float()
assert(#requests == 1, "initial hover should make one request")
assert(requests[1].kind == "client", "interactive hover should request tsgo directly")
assert_request(requests[1], 0)

vim.fn.getmousepos = function()
	return { winid = source_win, line = 1, column = byte_col + 1 }
end
hover.setup_mouse_hover({ delay_ms = 0 })
hover.handle_mouse_move()
vim.wait(20, function()
	return #requests > 1
end, 1)
assert(#requests == 1, "a pending explicit tsgo hover should block passive mouse requests")
vim.fn.getmousepos = original_getmousepos

deliver(requests[1], compact, true)

local float_win = assert(vim.b[source_buf].lsp_floating_preview)
local float_buf = vim.api.nvim_win_get_buf(float_win)
local compact_height = vim.api.nvim_win_get_height(float_win)
local expand = mapping_callback(float_buf, "+")
local collapse = mapping_callback(float_buf, "-")

hover.show_float()
assert(vim.api.nvim_get_current_win() == float_win, "second hover should focus the existing float")

expand()
assert(#requests == 2, "expand should request the next level")
assert(requests[2].kind == "client", "expansion should request tsgo directly")
assert_request(requests[2], 1)
expand()
assert(#requests == 2, "another keypress should not overlap an in-flight request")
deliver(requests[2], expanded, true)

assert(vim.api.nvim_win_is_valid(float_win), "expansion should preserve the float window")
assert(vim.api.nvim_win_get_buf(float_win) == float_buf, "expansion should preserve the float buffer")
assert(vim.api.nvim_get_current_win() == float_win, "expansion should preserve hover focus")
local expanded_text = table.concat(vim.api.nvim_buf_get_lines(float_buf, 0, -1, false), "\n")
assert(expanded_text:find("attributeKey", 1, true), expanded_text)
assert(vim.api.nvim_win_get_height(float_win) >= compact_height, "expanded hover should not shrink")
local expanded_height = vim.api.nvim_win_get_height(float_win)

expand()
assert_request(requests[3], 2)
deliver(requests[3], nested, nil)
expand()
assert(#requests == 3, "terminal verbosity should disable further expansion")

collapse()
assert_request(requests[4], 1)
deliver(requests[4], expanded, true)
collapse()
assert_request(requests[5], 0)
deliver(requests[5], compact, true)
assert(vim.api.nvim_win_get_height(float_win) <= expanded_height, "collapsed hover should not remain expanded")
collapse()
assert(#requests == 5, "collapse should stop at level zero")

expand()
assert_request(requests[6], 1)
vim.api.nvim_set_current_win(unrelated_win)
assert(requests[6].cancelled == true, "leaving the hover context should cancel the pending request")
assert(vim.b[source_buf].lsp_floating_preview == nil, "closing the hover should clear source preview state")
deliver(requests[6], expanded, true)
assert(not vim.api.nvim_win_is_valid(float_win), "a stale response should not reopen a closed hover")

vim.api.nvim_set_current_win(source_win)
hover.show_float()
assert_request(requests[7], 0)
deliver(requests[7], compact, true)
local escaped_float_win = assert(vim.b[source_buf].lsp_floating_preview)
assert(vim.api.nvim_get_current_win() == source_win, "initial hover should retain source focus")
escape()
assert(not vim.api.nvim_win_is_valid(escaped_float_win), "source Escape should close the interactive hover")

hover.show_float()
assert_request(requests[8], 0)
deliver(requests[8], compact, true)
escaped_float_win = assert(vim.b[source_buf].lsp_floating_preview)
local escaped_float_buf = vim.api.nvim_win_get_buf(escaped_float_win)
hover.show_float()
assert(vim.api.nvim_get_current_win() == escaped_float_win, "second hover should focus the reopened float")
mapping_callback(escaped_float_buf, "<Esc>")()
assert(not vim.api.nvim_win_is_valid(escaped_float_win), "focused Escape should close the interactive hover")

vim.api.nvim_set_current_win(source_win)
hover.show_float()
assert_request(requests[9], 0)
escape()
assert(requests[9].cancelled == true, "source Escape should cancel a pending interactive hover")
deliver(requests[9], compact, true)
assert(vim.b[source_buf].lsp_floating_preview == nil, "a cancelled hover response should stay closed")

hover.show_split()
assert(#requests == 10, "split hover should make a request")
assert(requests[10].kind == "all", "split hover should retain aggregate server results")
assert_request(requests[10], nil)
deliver(requests[10], compact, true)
local split_buf = vim.api.nvim_get_current_buf()
local split_text = table.concat(vim.api.nvim_buf_get_lines(split_buf, 0, -1, false), "\n")
assert(split_buf ~= source_buf, "split hover should open a separate buffer")
assert(split_text:find("setSpanAttrs", 1, true), split_text)
assert(not has_mapping(split_buf, "+"), "split hover should not install verbosity mappings")

vim.lsp.get_clients = original_get_clients
vim.lsp.get_client_by_id = original_get_client_by_id
vim.lsp.buf_request_all = original_buf_request_all

print("ok interactive tsgo hover verbosity")
EOF

echo "ok nvim hover verbosity smoke"
