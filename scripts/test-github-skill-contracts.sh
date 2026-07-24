#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

assert_contains() {
  local file="$1"
  local expected="$2"

  if ! grep -Fq -- "$expected" "$file"; then
    printf 'Expected %s to contain: %s\n' "$file" "$expected" >&2
    exit 1
  fi
}

summary_skill="home/.codex/skills/gh-comments/SKILL.md"
summary_ui="home/.codex/skills/gh-comments/agents/openai.yaml"
codex_policy="home/.codex/AGENTS.md"
claude_handler="home/.claude/skills/gh-address-comments/SKILL.md"

assert_contains "$summary_skill" "# Github Summarize Comments"
assert_contains "$summary_skill" "Keep this workflow read-only"
assert_contains "$summary_ui" 'display_name: "Github Summarize Comments"'

assert_contains "$codex_policy" "## GitHub Review Comment Handling"
assert_contains "$codex_policy" '$github:gh-address-comments'
assert_contains "$codex_policy" "authorization to reply on GitHub and resolve"
assert_contains "$codex_policy" '`no write`'
assert_contains "$codex_policy" "Reply before resolving"
assert_contains "$codex_policy" '`Our response (posted)`'
assert_contains "$codex_policy" '`Code change`'

assert_contains "$claude_handler" "# Github Handle Comments"
assert_contains "$claude_handler" "Default to GitHub writes enabled"
assert_contains "$claude_handler" "## Required output format"
assert_contains "$claude_handler" '`Our response (posted)`'
assert_contains "$claude_handler" '`Code change`'

echo "GitHub skill contracts are configured."
