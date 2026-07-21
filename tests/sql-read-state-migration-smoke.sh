#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE="$ROOT/scripts/migrate-sql-read-state.sh"
WORK="$(mktemp -d -t sql-read-migration-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

mkdir -p "$WORK/legacy/codex" "$WORK/legacy/claude" "$WORK/state/sql-read"

printf '%s\n' '{"version":1,"targets":{"existing":{"engine":"sqlite","value":"/tmp/existing.db"}}}' \
  > "$WORK/state/sql-read/targets.json"
printf '%s\n' '{"version":1,"targets":{"codex":{"engine":"postgres","value":"postgres://codex-secret"},"shared":{"engine":"sqlite","value":"/tmp/shared.db"}}}' \
  > "$WORK/legacy/codex/targets.json"
printf '%s\n' '{"version":1,"targets":{"claude":{"engine":"postgres","value":"postgres://claude-secret"},"shared":{"engine":"sqlite","value":"/tmp/shared.db"}}}' \
  > "$WORK/legacy/claude/targets.json"

bash "$MIGRATE" "$(command -v jq)" \
  "$WORK/state/sql-read/targets.json" \
  "$WORK/legacy/codex/targets.json" \
  "$WORK/legacy/claude/targets.json"

jq -e '
  .version == 1
  and (.targets | keys == ["claude", "codex", "existing", "shared"])
  and .targets.codex.value == "postgres://codex-secret"
  and .targets.claude.value == "postgres://claude-secret"
' "$WORK/state/sql-read/targets.json" >/dev/null
[[ "$(mode "$WORK/state/sql-read")" == "700" ]]
[[ "$(mode "$WORK/state/sql-read/targets.json")" == "600" ]]

mkdir -p "$WORK/conflict/state" "$WORK/conflict/legacy"
printf '%s\n' '{"version":1,"targets":{"same":{"engine":"postgres","value":"postgres://original-secret"}}}' \
  > "$WORK/conflict/state/targets.json"
printf '%s\n' '{"version":1,"targets":{"same":{"engine":"postgres","value":"postgres://different-secret"}}}' \
  > "$WORK/conflict/legacy/targets.json"
cp "$WORK/conflict/state/targets.json" "$WORK/conflict/original.json"

if bash "$MIGRATE" "$(command -v jq)" \
  "$WORK/conflict/state/targets.json" \
  "$WORK/conflict/legacy/targets.json" \
  > "$WORK/conflict/stdout" 2> "$WORK/conflict/stderr"
then
  echo "Expected conflicting SQL Read migration to fail" >&2
  exit 1
fi

cmp "$WORK/conflict/original.json" "$WORK/conflict/state/targets.json"
if grep -Eq 'original-secret|different-secret' "$WORK/conflict/stdout" "$WORK/conflict/stderr"; then
  echo "Migration conflict output exposed a stored value" >&2
  exit 1
fi

echo "SQL Read state migration smoke test passed."
