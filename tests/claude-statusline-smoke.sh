#!/usr/bin/env bash
# Smoke test for home/.claude/statusline-command.sh.
#
# Bugs this catches: the session name not being read from the registry file,
# the wrong icon for a PR state, `gh` running on the synchronous path, a fresh
# cache being refetched, a stale cache not being refreshed, and the status
# line failing when `gh` is missing.

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
export CLAUDE_STATUSLINE_CACHE_DIR="$WORK/cache"
export CLAUDE_STATUSLINE_SYNC=1
export CLAUDE_STATUSLINE_PR_TTL=60
export NO_COLOR=1
export CLAUDE_STATUSLINE_LINKS=0
mkdir -p "$CLAUDE_CONFIG_DIR/sessions" "$WORK/bin" "$WORK/nogh-bin" "$WORK/cwd"

# A PATH with the tools the script needs but no gh.
for tool in bash cat jq git sed awk stat date basename head tr mkdir rm mv rmdir; do
  ln -s "$(command -v "$tool")" "$WORK/nogh-bin/$tool"
done

# Two running sessions; only the one matching session_id should be shown.
cat > "$CLAUDE_CONFIG_DIR/sessions/111.json" <<'JSON'
{"pid":111,"sessionId":"other-session","name":"other-9z","nameSource":"derived"}
JSON
cat > "$CLAUDE_CONFIG_DIR/sessions/222.json" <<'JSON'
{"pid":222,"sessionId":"this-session","name":"app-1a","nameSource":"derived"}
JSON

# A gh stub that records each invocation and returns one PR per icon.
calls="$WORK/gh-calls"
: > "$calls"
cat > "$WORK/bin/gh" <<EOF_GH
#!/usr/bin/env bash
echo "\$*" >> "$calls"
cat <<'JSON'
[
  {"number":8,"url":"https://github.com/me/app/pull/8","title":"open plain","state":"OPEN","isDraft":false,"reviewDecision":"","statusCheckRollup":[]},
  {"number":7,"title":"approved","state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]},
  {"number":6,"title":"pending","state":"OPEN","isDraft":false,"reviewDecision":"","statusCheckRollup":[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null}]},
  {"number":5,"title":"changes requested","state":"OPEN","isDraft":false,"reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"__typename":"StatusContext","state":"SUCCESS"}]},
  {"number":4,"title":"failing","state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","statusCheckRollup":[{"__typename":"StatusContext","state":"FAILURE"}]},
  {"number":3,"title":"draft","state":"OPEN","isDraft":true,"reviewDecision":"","statusCheckRollup":[]},
  {"number":2,"title":"closed","state":"CLOSED","isDraft":false,"reviewDecision":"","statusCheckRollup":[]},
  {"number":1,"title":"merged","state":"MERGED","isDraft":false,"reviewDecision":"","statusCheckRollup":[]}
]
JSON
EOF_GH
chmod +x "$WORK/bin/gh"

input=$(cat <<JSON
{"session_id":"this-session","cwd":"$WORK/cwd","model":{"display_name":"Fable"},
 "context_window":{"remaining_percentage":42},
 "workspace":{"current_dir":"$WORK/cwd","repo":{"host":"github.com","owner":"me","name":"app"}}}
JSON
)

run() { printf '%s' "$input" | PATH="$WORK/bin:$PATH" bash "$SCRIPT"; }

# First run: empty cache, synchronous refresh, both lines rendered.
out="$(run)"
line1="$(sed -n 1p <<<"$out")"
line2="$(sed -n 2p <<<"$out")"
[[ "$line1" == "app-1a · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the session name from the registry on line 1, got: $line1"
g() { jq -rn "\"\\u$1\""; }
pr=$(g f407) merged=$(g f419) closed=$(g f4dc) draft=$(g f4dd)
failing=$(g f467) changes=$(g f421) pending=$(g f444) approved=$(g f42e)
expected="PRs $pr #8 $pr #7$approved $pr #6$pending $pr #5$changes $pr #4$failing $draft #3 $closed #2 $merged #1"
[[ "$line2" == "$expected" ]] \
  || fail "Expected a state glyph per PR and a check glyph per signal, got: $(printf '%q' "$line2")"
[[ "$(wc -l < "$calls" | tr -d ' ')" == "1" ]] || fail "Expected exactly one gh call on a cold cache"
grep -q -- '--repo me/app --author @me --state all --limit 5' "$calls" \
  || fail "Expected gh to query the user's PRs in the cwd's repo, got: $(cat "$calls")"

# The plain-Unicode glyph set is one environment variable away.
out="$(printf '%s' "$input" | PATH="$WORK/bin:$PATH" CLAUDE_STATUSLINE_ICONS=unicode bash "$SCRIPT" | sed -n 2p)"
[[ "$out" == "PRs ○ #8 ○ #7✓ ○ #6● ○ #5⚠ ○ #4✗ ◌ #3 ✖ #2 ✔ #1" ]] \
  || fail "Expected the unicode glyph set, got: $out"

# Second run: cache is fresh, so gh is not called again.
out="$(run)"
[[ "$(sed -n 2p <<<"$out")" == "$line2" ]] || fail "Expected the PR line to render from cache"
[[ "$(wc -l < "$calls" | tr -d ' ')" == "1" ]] || fail "Expected a fresh cache to skip gh"

# PR numbers become OSC 8 hyperlinks unless links are disabled.
esc=$'\033'
linked="$(printf '%s' "$input" | PATH="$WORK/bin:$PATH" CLAUDE_STATUSLINE_LINKS=1 bash "$SCRIPT" | sed -n 2p)"
[[ "$linked" == *"$pr ${esc}]8;;https://github.com/me/app/pull/8${esc}\\#8${esc}]8;;${esc}\\ $pr #7$approved"* ]] \
  || fail "Expected #8 wrapped in an OSC 8 hyperlink and #7 (no url) plain, got: $(printf '%q' "$linked")"
[[ "$(wc -l < "$calls" | tr -d ' ')" == "1" ]] || fail "Expected the link run to use the cache"

# Third run: an expired cache triggers exactly one more refresh.
cache_file="$CLAUDE_STATUSLINE_CACHE_DIR/prs-me_app.json"
[[ -f "$cache_file" ]] || fail "Expected the cache file at $cache_file"
touch -t 200001010000 "$cache_file"
run >/dev/null
[[ "$(wc -l < "$calls" | tr -d ' ')" == "2" ]] || fail "Expected an expired cache to refresh once"

# Without gh the first line still renders and there is no PR line.
out="$(printf '%s' "$input" | PATH="$WORK/nogh-bin" bash "$SCRIPT")"
[[ "$out" == "$line1" ]] || fail "Expected only the first line without gh, got: $out"

# A session the registry does not know falls back to the stdin session_name,
# then to the session id prefix.
named=$(jq -c '.session_id = "unknown" | .session_name = "renamed"' <<<"$input")
[[ "$(printf '%s' "$named" | PATH="$WORK/nogh-bin" bash "$SCRIPT")" == "renamed · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the stdin session_name fallback"
anon=$(jq -c '.session_id = "0123456789abcdef"' <<<"$input")
[[ "$(printf '%s' "$anon" | PATH="$WORK/nogh-bin" bash "$SCRIPT")" == "01234567 · Fable [ctx: 42%] in cwd" ]] \
  || fail "Expected the session id prefix fallback"

echo "Claude status line smoke test passed."
