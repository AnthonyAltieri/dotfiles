#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE="$ROOT/scripts/share-claude-sessions.sh"
WORK="$(mktemp -d -t claude-shared-sessions-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

primary="$WORK/.claude"
second="$WORK/.claude-anthropic2"
mkdir -p "$primary/projects/-home-me-app" "$second/projects/-home-me-app" "$second/sessions"
printf 'primary transcript\n' > "$primary/projects/-home-me-app/shared-id.jsonl"
printf 'primary prompt\n' > "$primary/history.jsonl"
# The second account already has history of its own, including a name clash.
printf 'second transcript\n' > "$second/projects/-home-me-app/second-only.jsonl"
printf 'clashing transcript\n' > "$second/projects/-home-me-app/shared-id.jsonl"
printf 'second prompt\n' > "$second/history.jsonl"
printf 'running-process state\n' > "$second/sessions/123.json"

bash "$SHARE" "$primary" "$second"

for name in projects file-history todos plans paste-cache history.jsonl; do
  [[ -L "$second/$name" && "$(readlink "$second/$name")" == "$primary/$name" ]] \
    || fail "Expected $name in the second config dir to link to the primary"
done
[[ ! -L "$second/sessions" ]] || fail "Did not expect per-process session state to be shared"

[[ "$(cat "$primary/projects/-home-me-app/shared-id.jsonl")" == "primary transcript" ]] \
  || fail "Expected the primary transcript to win a name clash"
[[ -f "$primary/projects/-home-me-app/second-only.jsonl" ]] \
  || fail "Expected the second account's transcripts to be merged into the shared history"
grep -Fxq 'primary prompt' "$primary/history.jsonl" && grep -Fxq 'second prompt' "$primary/history.jsonl" \
  || fail "Expected both accounts' prompt history to be kept"
ls -d "$second"/projects.pre-shared-* >/dev/null 2>&1 \
  || fail "Expected the second account's original projects dir to be kept aside"

# A session written by the second account is visible from the first.
printf 'new session\n' > "$second/projects/-home-me-app/new.jsonl"
[[ -f "$primary/projects/-home-me-app/new.jsonl" ]] || fail "Expected new sessions to be shared live"

backups_before="$(ls -d "$second"/*.pre-shared-* | wc -l)"
bash "$SHARE" "$primary" "$second"
[[ "$(ls -d "$second"/*.pre-shared-* | wc -l)" == "$backups_before" ]] \
  || fail "Expected re-running to change nothing"

echo "Claude shared sessions smoke test passed."
