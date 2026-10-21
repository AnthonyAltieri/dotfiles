#!/usr/bin/env bash
# Smoke test for home/.claude/statusline-command.sh.
#
# Bugs this catches: the session name not being read from the registry file,
# and the fallbacks to the stdin session_name and the session id prefix
# breaking.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/home/.claude/statusline-command.sh"
WORK="$(mktemp -d -t claude-statusline-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

command -v jq >/dev/null || fail "jq is required"

export HOME="$WORK/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export NO_COLOR=1
mkdir -p "$CLAUDE_CONFIG_DIR/sessions" "$WORK/cwd"

# Two running sessions; only the one matching session_id should be shown.
cat > "$CLAUDE_CONFIG_DIR/sessions/111.json" <<'JSON'
{"pid":111,"sessionId":"other-session","name":"other-9z","nameSource":"derived"}
JSON
cat > "$CLAUDE_CONFIG_DIR/sessions/222.json" <<'JSON'
{"pid":222,"sessionId":"this-session","name":"app-1a","nameSource":"derived"}
JSON

input=$(cat <<JSON
{"session_id":"this-session","cwd":"$WORK/cwd","model":{"display_name":"Fable"},
 "context_window":{"remaining_percentage":42},
 "workspace":{"current_dir":"$WORK/cwd"}}
JSON
)

out="$(printf '%s' "$input" | bash "$SCRIPT")"
[[ "$out" == "app-1a · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the session name from the registry as the only line, got: $out"

# A session the registry does not know falls back to the stdin session_name,
# then to the session id prefix.
named=$(jq -c '.session_id = "unknown" | .session_name = "renamed"' <<<"$input")
[[ "$(printf '%s' "$named" | bash "$SCRIPT")" == "renamed · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the stdin session_name fallback"
anon=$(jq -c '.session_id = "0123456789abcdef"' <<<"$input")
[[ "$(printf '%s' "$anon" | bash "$SCRIPT")" == "01234567 · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the session id prefix fallback"

echo "Claude status line smoke test passed."
