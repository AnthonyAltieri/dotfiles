#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/dotfiles-homebrew-trust.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

BREWFILE="$(
  XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --impure --no-write-lock-file --raw \
    "path:${ROOT_DIR}#darwinConfigurations.personal.config.homebrew.brewfile"
)"

if [[ "$(rg -Fxc 'brew "oven-sh/bun/bun", trusted: true' <<<"$BREWFILE" || true)" != 1 ]]; then
  printf 'expected exactly one formula-scoped trusted Bun entry in the generated Brewfile\n' >&2
  exit 1
fi

if ! rg -Fqx 'tap "oven-sh/bun"' <<<"$BREWFILE"; then
  printf 'expected the generated Brewfile to retain the Bun tap\n' >&2
  exit 1
fi

if rg -Fqx 'tap "oven-sh/bun", trusted: true' <<<"$BREWFILE"; then
  printf 'expected Bun trust to remain formula-scoped instead of trusting the whole tap\n' >&2
  exit 1
fi

printf 'ok generated Brewfile trusts only the Bun formula\n'
