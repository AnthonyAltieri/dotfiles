#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFORM_RTP="${HOME}/.local/share/nvim/lazy/conform.nvim"
LINT_RTP="${HOME}/.local/share/nvim/lazy/nvim-lint"
REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua"

make_bin_dir() {
  mkdir -p "$1/node_modules/.bin"
}

write_bin() {
  local path="$1"
  shift
  cat >"$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
  printf '%s\n' "$@" >>"$path"
  chmod +x "$path"
}

setup_oxc_fixture() {
  local dir="$TMP_DIR/oxc-app"
  mkdir -p "$dir/src"
  make_bin_dir "$dir"
  cat >"$dir/.oxlintrc.json" <<'EOF'
{"rules":{}}
EOF
  cat >"$dir/src/example.ts" <<'EOF'
export const value = 1
EOF
  write_bin "$dir/node_modules/.bin/oxfmt" 'cat'
  write_bin "$dir/node_modules/.bin/oxlint" 'printf "{\"diagnostics\":[]}"'
}

setup_eslint_owned_fixture() {
  local dir="$TMP_DIR/eslint-owned"
  mkdir -p "$dir/src"
  make_bin_dir "$dir"
  cat >"$dir/eslint.config.mjs" <<'EOF'
export default [];
EOF
  cat >"$dir/src/example.ts" <<'EOF'
export const value = 1
EOF
  write_bin "$dir/node_modules/.bin/eslint" \
    'if [ "${1:-}" = "--print-config" ]; then' \
    '  printf "{\"rules\":{\"prettier/prettier\":[\"error\",{\"endOfLine\":\"auto\"}]}}"' \
    'else' \
    '  printf "[]"' \
    'fi'
  write_bin "$dir/node_modules/.bin/eslint_d" 'cat'
}

setup_eslint_plain_fixture() {
  local dir="$TMP_DIR/eslint-plain"
  mkdir -p "$dir/src"
  make_bin_dir "$dir"
  cat >"$dir/eslint.config.mjs" <<'EOF'
export default [];
EOF
  cat >"$dir/src/example.ts" <<'EOF'
export const value = 1
EOF
  write_bin "$dir/node_modules/.bin/eslint" \
    'if [ "${1:-}" = "--print-config" ]; then' \
    '  printf "{\"rules\":{\"semi\":[\"error\",\"always\"]}}"' \
    'else' \
    '  printf "[]"' \
    'fi'
  write_bin "$dir/node_modules/.bin/prettierd" 'cat'
  write_bin "$dir/node_modules/.bin/prettier" 'cat'
}

run_case() {
  local file_path="$1"
  local expected_policy="$2"
  local expected_formatter="$3"
  local expected_linter="$4"
  local expected_autoformat="$5"

  FILE_PATH="$file_path" \
  EXPECTED_POLICY="$expected_policy" \
  EXPECTED_FORMATTER="$expected_formatter" \
  EXPECTED_LINTER="$expected_linter" \
  EXPECTED_AUTOFORMAT="$expected_autoformat" \
  REPO_LUA="$REPO_LUA" \
  CONFORM_RTP="$CONFORM_RTP" \
  LINT_RTP="$LINT_RTP" \
  XDG_CACHE_HOME=/tmp \
  XDG_STATE_HOME=/tmp \
  XDG_DATA_HOME=/tmp \
  nvim --clean --headless \
    --cmd 'lua vim.loader.enable(false)' \
    --cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
    --cmd 'lua vim.opt.runtimepath:append(vim.fn.getenv("CONFORM_RTP"))' \
    --cmd 'lua vim.opt.runtimepath:append(vim.fn.getenv("LINT_RTP"))' \
    --cmd 'lua require("conform").setup(require("aalt.lazy.autoformat").opts)' \
    --cmd 'lua require("aalt.lazy.lint").config()' \
    --cmd 'lua require("aalt.debug_commands").setup()' \
    +"edit ${file_path}" \
    +"lua local monorepo = require('aalt.monorepo'); local formatter_state = monorepo.formatter_state_for_buf(0); local linter_state = monorepo.linter_state_for_buf(0); local conform = require('conform'); local active_formatter = conform.resolve_formatters(formatter_state.formatters, 0, false, true)[1]; local lint = require('lint'); local active_linter = linter_state.linters[1]; local autoformat_should_work = active_formatter ~= nil; assert(formatter_state.detected_policy == vim.fn.getenv('EXPECTED_POLICY'), string.format('expected policy %s, got %s', vim.fn.getenv('EXPECTED_POLICY'), formatter_state.detected_policy)); assert((active_formatter and active_formatter.name or 'none') == vim.fn.getenv('EXPECTED_FORMATTER'), string.format('expected formatter %s, got %s', vim.fn.getenv('EXPECTED_FORMATTER'), active_formatter and active_formatter.name or 'none')); assert((active_linter or 'none') == vim.fn.getenv('EXPECTED_LINTER'), string.format('expected linter %s, got %s', vim.fn.getenv('EXPECTED_LINTER'), active_linter or 'none')); assert((autoformat_should_work and 'yes' or 'no') == vim.fn.getenv('EXPECTED_AUTOFORMAT'), string.format('expected autoformat %s, got %s', vim.fn.getenv('EXPECTED_AUTOFORMAT'), autoformat_should_work and 'yes' or 'no')); vim.cmd('Format'); print(string.format('ok %s', vim.fn.fnamemodify(vim.fn.getenv('FILE_PATH'), ':t')))" \
    +qa
}

setup_oxc_fixture
setup_eslint_owned_fixture
setup_eslint_plain_fixture

run_case "$TMP_DIR/oxc-app/src/example.ts" "oxc-only" "oxfmt" "oxlint_monorepo" "yes"
run_case "$TMP_DIR/eslint-owned/src/example.ts" "eslint-only" "eslint_d_monorepo" "eslint_d_monorepo" "yes"
run_case "$TMP_DIR/eslint-plain/src/example.ts" "eslint+prettier" "prettierd" "eslint_d_monorepo" "yes"
