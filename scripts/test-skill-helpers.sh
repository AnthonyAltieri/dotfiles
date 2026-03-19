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

run cargo test --offline --manifest-path dot_codex/skills/atlas/scripts/Cargo.toml
run cargo test --offline --manifest-path dot_codex/skills/sql-read/scripts/Cargo.toml
run cargo test --offline --manifest-path dot_codex/skills/gh-address-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path dot_codex/skills/gh-fix-ci/scripts/Cargo.toml
run rustc --test dot_codex/skills/gh-manage-pr/scripts/summarize_diff.rs -o /tmp/codex-gh-manage-pr-tests
run /tmp/codex-gh-manage-pr-tests

run cargo test --offline --manifest-path dot_claude/skills/sql-read/scripts/Cargo.toml
run cargo test --offline --manifest-path dot_claude/skills/gh-address-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path dot_claude/skills/gh-fix-ci/scripts/Cargo.toml
run rustc --test dot_claude/skills/gh-manage-pr/scripts/summarize_diff.rs -o /tmp/claude-gh-manage-pr-tests
run /tmp/claude-gh-manage-pr-tests
