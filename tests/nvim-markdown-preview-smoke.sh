#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

MARKDOWN_PATH="$TEST_ROOT/- preview; file.md"
TEST_LUA="$TEST_ROOT/test.lua"

printf '# Saved heading\n\nSaved body.\n' > "$MARKDOWN_PATH"

cat > "$TEST_LUA" <<'LUA'
local launches = {}
local uv = vim.uv or vim.loop

vim.fn.exepath = function(command)
	assert(command == "glow", "unexpected executable lookup: " .. command)
	return "/managed/bin/glow"
end

vim.fn.jobstart = function(argv, options)
	launches[#launches + 1] = {
		argv = argv,
		options = options,
	}
	return 17
end

uv.os_uname = function()
	return { sysname = "Darwin" }
end

require("aalt.markdown_preview").setup()
assert(vim.fn.exists(":Md") == 2, ":Md was not registered")

vim.api.nvim_buf_set_lines(0, 0, 1, false, { "# Unsaved heading" })
assert(vim.bo.modified, "test buffer should be modified before :Md")

vim.cmd("Md")

assert(#launches == 1, ":Md should start exactly one launcher")
local launch = launches[1]
local expected_path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p")
local expected_argv = {
	"open",
	"-na",
	"Ghostty.app",
	"--args",
	"-e",
	"/managed/bin/glow",
	"--tui",
	"--",
	expected_path,
}

assert(vim.deep_equal(launch.argv, expected_argv), "unexpected launcher argv: " .. vim.inspect(launch.argv))
assert(launch.options.detach == true, "Ghostty launcher should be detached")
assert(type(launch.options.on_exit) == "function", "launcher should report asynchronous failures")
assert(vim.bo.modified, ":Md must not save or clear the modified buffer")

local saved_lines = vim.fn.readfile(vim.env.MD_TEST_PATH)
assert(saved_lines[1] == "# Saved heading", ":Md must not write unsaved buffer contents")

print("ok :Md external Glow preview")
vim.cmd("qa!")
LUA

MD_TEST_PATH="$MARKDOWN_PATH" \
XDG_CONFIG_HOME="$TEST_ROOT/config" \
XDG_DATA_HOME="$TEST_ROOT/data" \
XDG_STATE_HOME="$TEST_ROOT/state" \
XDG_CACHE_HOME="$TEST_ROOT/cache" \
nvim --headless -u NONE -i NONE -n \
  --cmd "set runtimepath^=$ROOT/home/.config/nvim" \
  "$MARKDOWN_PATH" \
  "+set filetype=markdown" \
  "+lua dofile('$TEST_LUA')"
