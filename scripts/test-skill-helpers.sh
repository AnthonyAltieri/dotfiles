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
run tests/sql-read-state-migration-smoke.sh
run cargo test --offline --manifest-path home/.codex/skills/gh-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/gh-ci/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.codex/skills/gh-pr-body/scripts/Cargo.toml

run cargo test --offline --manifest-path home/.claude/skills/sql-read/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-address-comments/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-fix-ci/scripts/Cargo.toml
run cargo test --offline --manifest-path home/.claude/skills/gh-manage-pr/scripts/Cargo.toml

run bash scripts/test-codex-skill-display-names.sh
run bash scripts/test-github-skill-contracts.sh
run scripts/test-shared-skills-sync.sh
