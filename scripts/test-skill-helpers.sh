#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run cargo test --offline --manifest-path home/.codex/skills/atlas/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/sql-read/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/gh-address-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/gh-fix-ci/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/gh-manage-pr/scripts/Cargo.toml

run cargo test --offline --manifest-path home/.claude/skills/sql-read/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-address-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-fix-ci/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-manage-pr/scripts/Cargo.toml

run diff -ru --exclude agents --exclude target \
  home/.codex/skills/gh-manage-pr \
  home/.claude/skills/gh-manage-pr
