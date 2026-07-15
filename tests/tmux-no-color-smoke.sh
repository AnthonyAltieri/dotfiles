#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/dotfiles-tmux.XXXXXX)"
SOCKET_PATH="$TMP_DIR/socket"
EVALUATED_CONFIG="$TMP_DIR/tmux.conf"
ON_CHANGE_HOOK="$TMP_DIR/on-change-hook"
PANE_ENV="$TMP_DIR/pane-env"

tmux_test() {
  TMUX= tmux -S "$SOCKET_PATH" "$@"
}

cleanup() {
  tmux_test kill-server >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
  --extra-experimental-features 'nix-command flakes' \
  eval --impure --no-write-lock-file --raw \
  "path:${ROOT_DIR}#homeConfigurations.personal-linux.config.programs.tmux.extraConfig" \
  >"$EVALUATED_CONFIG"

XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
  --extra-experimental-features 'nix-command flakes' \
  eval --impure --no-write-lock-file --raw \
  "path:${ROOT_DIR}#homeConfigurations.personal-linux.config.xdg.configFile.\"tmux/tmux.conf\".onChange" \
  >"$ON_CHANGE_HOOK"

policy_count="$(rg -Fxc 'set-environment -gu NO_COLOR' "$EVALUATED_CONFIG" || true)"
if [[ "$policy_count" != "1" ]]; then
  printf 'expected the Nix-generated tmux config to clear NO_COLOR exactly once\n' >&2
  exit 1
fi

if ! rg -q -- '/bin/tmux -N set-environment -gu NO_COLOR' "$ON_CHANGE_HOOK"; then
  printf 'expected Home Manager activation to repair a running tmux server\n' >&2
  exit 1
fi

NO_COLOR=1 DOTFILES_TMUX_SENTINEL=present TMUX= \
  tmux -S "$SOCKET_PATH" -f "$EVALUATED_CONFIG" \
  new-session -d -s no-color-test

if [[ "$(tmux_test show-environment -g DOTFILES_TMUX_SENTINEL)" != "DOTFILES_TMUX_SENTINEL=present" ]]; then
  printf 'expected tmux to retain unrelated inherited environment values\n' >&2
  exit 1
fi

if tmux_test show-environment -g NO_COLOR >/dev/null 2>&1; then
  printf 'expected the tmux global environment to omit NO_COLOR\n' >&2
  exit 1
fi

if tmux_test show-environment -t no-color-test NO_COLOR >/dev/null 2>&1; then
  printf 'expected the tmux session environment to omit NO_COLOR\n' >&2
  exit 1
fi

tmux_test new-window -d -t no-color-test: \
  "env > '${PANE_ENV}.tmp' && mv '${PANE_ENV}.tmp' '$PANE_ENV'"
for _ in {1..100}; do
  [[ -f "$PANE_ENV" ]] && break
  sleep 0.01
done

if [[ ! -f "$PANE_ENV" ]]; then
  printf 'timed out waiting for the tmux pane environment\n' >&2
  exit 1
fi

if rg -q '^NO_COLOR=' "$PANE_ENV"; then
  printf 'expected a new tmux pane not to inherit NO_COLOR\n' >&2
  exit 1
fi

if ! rg -Fqx 'DOTFILES_TMUX_SENTINEL=present' "$PANE_ENV"; then
  printf 'expected a new tmux pane to retain unrelated environment values\n' >&2
  exit 1
fi

printf 'ok Nix-managed tmux configuration prevents NO_COLOR leakage\n'
