#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/dotfiles-herdr.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

nix_eval() {
  XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --impure --no-write-lock-file --raw "$@"
}

MANAGED_SOURCE="$(nix_eval "path:${ROOT_DIR}#homeConfigurations.personal-linux.config.xdg.configFile.\"herdr/config.toml\".source")"
LINUX_ON_CHANGE_HOOK="$(nix_eval "path:${ROOT_DIR}#homeConfigurations.personal-linux.config.xdg.configFile.\"herdr/config.toml\".onChange")"
DARWIN_ON_CHANGE_HOOK="$(nix_eval "path:${ROOT_DIR}#darwinConfigurations.personal.config.home-manager.users.${USER}.xdg.configFile.\"herdr/config.toml\".onChange")"

if ! cmp -s "$MANAGED_SOURCE" "$ROOT_DIR/home/.config/herdr/config.toml"; then
  printf 'expected Home Manager to link the repo herdr config verbatim\n' >&2
  exit 1
fi

for on_change_hook in "$LINUX_ON_CHANGE_HOOK" "$DARWIN_ON_CHANGE_HOOK"; do
  if ! rg -Fq 'server reload-config' <<<"$on_change_hook"; then
    printf 'expected Home Manager activation to reload a running herdr server\n' >&2
    exit 1
  fi
done

if ! rg -q '/nix/store/[a-z0-9]+-herdr-[^ /]+/bin/herdr' <<<"$LINUX_ON_CHANGE_HOOK"; then
  printf 'expected Linux activation to use the Nix-managed herdr binary\n' >&2
  exit 1
fi

for homebrew_herdr in /opt/homebrew/bin/herdr /usr/local/bin/herdr; do
  if ! rg -Fq "$homebrew_herdr" <<<"$DARWIN_ON_CHANGE_HOOK"; then
    printf 'expected Darwin activation to consider %s\n' "$homebrew_herdr" >&2
    exit 1
  fi
done

if rg -Fq 'command -v herdr' <<<"$LINUX_ON_CHANGE_HOOK$DARWIN_ON_CHANGE_HOOK"; then
  printf 'expected Herdr reload not to depend on Home Manager activation PATH\n' >&2
  exit 1
fi

expect_key() {
  if ! rg -Fq "$1" "$ROOT_DIR/home/.config/herdr/config.toml"; then
    printf 'expected herdr config to contain: %s\n' "$1" >&2
    exit 1
  fi
}

expect_key 'prefix = "ctrl+space"'
expect_key 'split_vertical = "prefix+v"'
expect_key 'split_horizontal = "prefix+s"'
expect_key '"ctrl+shift+q"'
expect_key '"ctrl+shift+comma"'
expect_key 'switch_tab = ["prefix+1..9", "ctrl+1..9"]'
expect_key 'switch_workspace = "ctrl+shift+1..9"'
expect_key '"ctrl+alt+h"'
expect_key 'onboarding = false'

# Ghostty must no longer translate the chords herdr binds directly.
if rg -q 'text:\\x00' "$ROOT_DIR/home/.config/ghostty/config"; then
  printf 'expected Ghostty to stop injecting the tmux prefix for Ctrl+digit\n' >&2
  exit 1
fi

if command -v herdr >/dev/null 2>&1; then
  HERDR_CONFIG_PATH="$ROOT_DIR/home/.config/herdr/config.toml" herdr --default-config >/dev/null
fi

printf 'ok Nix-managed herdr configuration is linked with the ported keybindings\n'
