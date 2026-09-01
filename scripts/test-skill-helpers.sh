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

run cargo test --offline --manifest-path pkgs/atlas-cli/Cargo.toml
run nix build --no-link --impure .#codex-thread-manager
run bash tests/claude-mcp-servers-smoke.sh
run cargo test --offline --manifest-path pkgs/sql-read/Cargo.toml
run tests/sql-read-state-migration-smoke.sh
run cargo test --offline --manifest-path pkgs/gh-comment-tools/Cargo.toml
run cargo test --offline --manifest-path pkgs/gh-ci-tools/Cargo.toml
run cargo test --offline --manifest-path pkgs/gh-pr-tools/Cargo.toml
