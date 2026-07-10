#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/mouse-hover-smoke.lua" <<'EOF'
local hover = require("aalt.hover")

assert(vim.o.mousemoveevent == true, "mouse move events should be enabled")
assert(vim.o.guicursor:find("n%-v%-c%-sm:block"), vim.o.guicursor)
assert(vim.o.guicursor:find("i%-ci%-ve:ver25"), vim.o.guicursor)

hover.setup_mouse_hover({ delay_ms = 15 })

local normal_map = vim.fn.maparg("<MouseMove>", "n", false, true)
local insert_map = vim.fn.maparg("<MouseMove>", "i", false, true)
assert(normal_map.desc == "Show LSP documentation under mouse", vim.inspect(normal_map))
assert(insert_map.desc == "Show LSP documentation under mouse", vim.inspect(insert_map))

local bufnr = vim.api.nvim_get_current_buf()
local winid = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a😀value", "cursor stays here" })
vim.api.nvim_win_set_cursor(winid, { 2, 3 })
local cursor_before = vim.api.nvim_win_get_cursor(winid)

local mouse = { winid = winid, line = 1, column = 1 }
local client = { id = 77, name = "mouse-hover-test", offset_encoding = "utf-16" }
local requests = {}
local previews = {}
local notifications = {}

local original_getmousepos = vim.fn.getmousepos
local original_get_clients = vim.lsp.get_clients
local original_get_client_by_id = vim.lsp.get_client_by_id
local original_buf_request_all = vim.lsp.buf_request_all
local original_open_floating_preview = vim.lsp.util.open_floating_preview
local original_notify = vim.notify

vim.fn.getmousepos = function()
	return vim.deepcopy(mouse)
end

vim.lsp.get_clients = function(opts)
	assert(opts.bufnr == bufnr, vim.inspect(opts))
	assert(opts.method == "textDocument/hover", vim.inspect(opts))
	return { client }
end

vim.lsp.get_client_by_id = function(client_id)
	if client_id == client.id then
		return client
	end
end

vim.lsp.buf_request_all = function(request_buf, method, params, callback)
	assert(request_buf == bufnr, request_buf)
	assert(method == "textDocument/hover", method)
	requests[#requests + 1] = {
		params = params(client),
		callback = callback,
	}
end

vim.lsp.util.open_floating_preview = function(lines, format, opts)
	local float_buf = vim.api.nvim_create_buf(false, true)
	local float_win = vim.api.nvim_open_win(float_buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = 1,
		height = 1,
		style = "minimal",
	})
	previews[#previews + 1] = {
		lines = lines,
		format = format,
		opts = opts,
		winid = float_win,
	}
	return float_buf, float_win
end

vim.notify = function(message, level, opts)
	notifications[#notifications + 1] = { message = message, level = level, opts = opts }
end

local function wait_for_requests(count)
	assert(vim.wait(1000, function()
		return #requests == count
	end, 5), string.format("timed out waiting for request %d; saw %d", count, #requests))
end

local function respond(request, contents)
	local result = contents and { contents = contents } or nil
	request.callback({ [client.id] = { result = result } }, { bufnr = bufnr })
end

-- Rapid movement should retain only one timer and request the final position.
for _, column in ipairs({ 1, 2, 6 }) do
	mouse.column = column
	hover.handle_mouse_move()
end
wait_for_requests(1)
vim.wait(40)
assert(#requests == 1, string.format("expected one coalesced request, saw %d", #requests))
assert(requests[1].params.position.line == 0, vim.inspect(requests[1].params))
assert(requests[1].params.position.character == 3, vim.inspect(requests[1].params))
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(winid), cursor_before), "mouse hover moved the editing cursor")

-- An in-flight response becomes stale as soon as the pointer moves again.
mouse.column = 7
hover.handle_mouse_move()
respond(requests[1], { kind = "markdown", value = "stale docs" })
assert(#previews == 0, "stale response opened a preview")

wait_for_requests(2)
assert(requests[2].params.position.character == 4, vim.inspect(requests[2].params))
respond(requests[2], { kind = "markdown", value = "current docs" })
assert(#previews == 1, "current response did not open a preview")
assert(previews[1].opts.relative == "mouse", vim.inspect(previews[1].opts))
assert(previews[1].opts.focusable == false, vim.inspect(previews[1].opts))
assert(previews[1].opts.focus == false, vim.inspect(previews[1].opts))
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(winid), cursor_before), "opening the preview moved the cursor")

-- Explicit hover cancels pending passive work.
mouse.column = 8
hover.handle_mouse_move()
assert(not vim.api.nvim_win_is_valid(previews[1].winid), "mouse movement should close the passive preview")
local before_explicit = #requests
hover.show_float()
assert(#requests == before_explicit + 1, "explicit hover should request immediately")
vim.wait(40)
assert(#requests == before_explicit + 1, "cancelled passive timer still requested hover")

-- A passive tooltip must not replace a manually opened LSP float.
local manual_buf = vim.api.nvim_create_buf(false, true)
local manual_win = vim.api.nvim_open_win(manual_buf, false, {
	relative = "editor",
	row = 1,
	col = 1,
	width = 1,
	height = 1,
	style = "minimal",
})
vim.b[bufnr].lsp_floating_preview = manual_win
mouse.column = 9
local before_manual_guard = #requests
hover.handle_mouse_move()
vim.wait(40)
assert(#requests == before_manual_guard, "passive hover requested while a manual preview was open")
assert(vim.api.nvim_win_is_valid(manual_win), "passive hover closed the manual preview")
vim.api.nvim_win_close(manual_win, true)
vim.b[bufnr].lsp_floating_preview = nil

-- Empty passive results stay quiet; explicit hover keeps its notification.
mouse.column = 10
hover.handle_mouse_move()
wait_for_requests(before_manual_guard + 1)
respond(requests[#requests], nil)
assert(#notifications == 0, "empty passive hover should not notify")

hover.show_float()
respond(requests[#requests], nil)
assert(#notifications == 1, "empty explicit hover should still notify")

-- Empty space after the line is not a hover target.
mouse.column = 11
local before_empty_space = #requests
hover.handle_mouse_move()
vim.wait(40)
assert(#requests == before_empty_space, "hover requested after end of line")

vim.fn.getmousepos = original_getmousepos
vim.lsp.get_clients = original_get_clients
vim.lsp.get_client_by_id = original_get_client_by_id
vim.lsp.buf_request_all = original_buf_request_all
vim.lsp.util.open_floating_preview = original_open_floating_preview
vim.notify = original_notify

print("ok mouse hover is debounced, position-aware, passive, and stale-safe")
EOF

REPO_LUA="$ROOT_DIR/home/.config/nvim/lua" \
NVIM_LOG_FILE="$TMP_DIR/nvim.log" \
XDG_CACHE_HOME="$TMP_DIR/cache" \
XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" \
nvim --clean --headless -i NONE \
	--cmd 'lua vim.loader.enable(false)' \
	--cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
	--cmd 'lua require("aalt.options")' \
	+"luafile $TMP_DIR/mouse-hover-smoke.lua" \
	+qa!

rg -Fq 'xterm-ghostty:hyperlinks:cstyle' "$ROOT_DIR/home/.config/tmux/tmux.conf"
rg -Fq 'xterm-256color:hyperlinks:cstyle' "$ROOT_DIR/home/.config/tmux/tmux.conf"

echo "ok cursor shapes are explicit in Neovim and propagated by tmux"
