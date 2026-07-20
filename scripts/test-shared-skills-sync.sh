#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

compare_skill() {
  local skill="$1"

  diff -ru --exclude agents --exclude target \
    "home/.codex/skills/$skill" \
    "home/.claude/skills/$skill"
}

compare_resources() {
  local codex_skill="$1"
  local claude_skill="$2"

  diff -ru --exclude agents --exclude SKILL.md --exclude target \
    "home/.codex/skills/$codex_skill" \
    "home/.claude/skills/$claude_skill"
}

for skill in \
  frontend-design \
  improve-codebase-architecture \
  notion-knowledge-capture \
  notion-read \
  observe \
  programming \
  sql-read
do
  compare_skill "$skill"
done

# GitHub entrypoints intentionally differ by agent, but the deterministic
# helpers and static resources remain one mirrored implementation.
compare_resources atlas atlas
compare_resources gh-review-thread-actions gh-address-comments
compare_resources gh-ci-log-tools gh-fix-ci
compare_resources gh-pr-body gh-manage-pr

echo "Shared skill payloads are synchronized."
