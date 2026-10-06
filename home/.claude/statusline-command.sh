#!/bin/bash
# Claude Code status line.
#
# Line 1: <session name> · <model> [ctx: N%] in <dir> on <branch>
# Line 2: PRs  #123  #124 …   (the user's most recent PRs in the cwd's repo)
#
# The session name is the short peer-messaging name other local Claude
# sessions use to address this one (what ListAgents / SendMessage show). It
# is only in the stdin JSON after /rename, so it is read from the per-process
# registry file Claude writes under <config dir>/sessions/.
#
# PR data comes from `gh` and is never fetched on the status line's
# synchronous path: it is rendered from a cache file that a detached
# background refresh rewrites atomically once the cache is older than the TTL.
#
# Environment knobs (all optional):
#   CLAUDE_STATUSLINE_PR_LIMIT   how many PRs to show (default 5)
#   CLAUDE_STATUSLINE_PR_TTL     cache lifetime in seconds (default 60)
#   CLAUDE_STATUSLINE_CACHE_DIR  cache location (default ~/.cache/claude-statusline)
#   CLAUDE_STATUSLINE_SYNC       1 = refresh in the foreground (tests, debugging)
#   NO_COLOR                     disable ANSI colors

input=$(cat)

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
cache_dir="${CLAUDE_STATUSLINE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline}"
pr_limit="${CLAUDE_STATUSLINE_PR_LIMIT:-5}"
pr_ttl="${CLAUDE_STATUSLINE_PR_TTL:-60}"
pr_links="${CLAUDE_STATUSLINE_LINKS:-1}"
pr_icons="${CLAUDE_STATUSLINE_ICONS:-nerd}"

if [ -n "${NO_COLOR:-}" ]; then
    c_name="" c_dim="" c_red="" c_green="" c_yellow="" c_magenta="" c_reset=""
else
    c_name=$'\033[1;36m' c_dim=$'\033[2m' c_red=$'\033[31m' c_green=$'\033[32m'
    c_yellow=$'\033[33m' c_magenta=$'\033[35m' c_reset=$'\033[0m'
fi

jq_field() {
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
}

file_age() {
    local mtime
    mtime=$(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null) || return 1
    echo $(( $(date +%s) - mtime ))
}

# --- session identity --------------------------------------------------------

session_id=$(jq_field '.session_id')

session_name=""
if [ -n "$session_id" ]; then
    shopt -s nullglob
    registry=("$config_dir"/sessions/*.json)
    # A second account keeps its own registry; look across all config dirs.
    [ ${#registry[@]} -eq 0 ] && registry=("$HOME"/.claude*/sessions/*.json)
    shopt -u nullglob
    if [ ${#registry[@]} -gt 0 ]; then
        session_name=$(jq -r --arg id "$session_id" \
            'select(type == "object" and .sessionId == $id) | .name // empty' \
            "${registry[@]}" 2>/dev/null | head -n 1)
    fi
fi
[ -z "$session_name" ] && session_name=$(jq_field '.session_name')
[ -z "$session_name" ] && [ -n "$session_id" ] && session_name="${session_id:0:8}"

# --- model, context, location ------------------------------------------------

cwd=$(jq_field '.workspace.current_dir')
[ -z "$cwd" ] && cwd=$(jq_field '.cwd')
model=$(jq_field '.model.display_name')
remaining=$(jq_field '.context_window.remaining_percentage')

git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo "")
    [ -n "$git_branch" ] && git_branch=" on $git_branch"
fi

dir=$(basename "${cwd:-/}")
context=""
[ -n "$remaining" ] && context=" [ctx: ${remaining}%]"

printf '%s%s%s · %s%s in %s%s\n' \
    "$c_name" "$session_name" "$c_reset" "$model" "$context" "$dir" "$git_branch"

# --- recent pull requests ----------------------------------------------------

command -v gh >/dev/null 2>&1 || exit 0

# Repo slug for `gh --repo`: prefer what Claude already resolved, else origin.
repo_host=$(jq_field '.workspace.repo.host')
repo_owner=$(jq_field '.workspace.repo.owner')
repo_name=$(jq_field '.workspace.repo.name')
if [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
    repo_slug="$repo_owner/$repo_name"
    [ -n "$repo_host" ] && [ "$repo_host" != "github.com" ] && repo_slug="$repo_host/$repo_slug"
elif [ -n "$cwd" ]; then
    origin_url=$(git -C "$cwd" --no-optional-locks remote get-url origin 2>/dev/null || echo "")
    # git@host:owner/name.git | https://host/owner/name.git | ssh://git@host/owner/name
    repo_slug=$(printf '%s' "$origin_url" \
        | sed -E 's#^[a-z+]+://##; s#^[^@/]+@##; s#:#/#; s#\.git/?$##' \
        | awk -F/ 'NF >= 3 { host=$1; owner=$(NF-1); name=$NF;
                              if (host == "github.com") print owner "/" name;
                              else print host "/" owner "/" name }')
fi
[ -z "${repo_slug:-}" ] && exit 0

cache_file="$cache_dir/prs-$(printf '%s' "$repo_slug" | tr '/' '_').json"
lock_dir="$cache_file.lock"

refresh_prs() {
    local tmp="$cache_file.tmp.$$"
    if gh pr list --repo "$repo_slug" --author "@me" --state all --limit "$pr_limit" \
        --json number,title,state,isDraft,reviewDecision,statusCheckRollup,url \
        >"$tmp" 2>/dev/null && jq -e 'type == "array"' "$tmp" >/dev/null 2>&1; then
        mv -f "$tmp" "$cache_file"
    else
        rm -f "$tmp"
    fi
    rmdir "$lock_dir" 2>/dev/null
}

cache_age=$(file_age "$cache_file" 2>/dev/null || echo "")
if [ -z "$cache_age" ] || [ "$cache_age" -ge "$pr_ttl" ]; then
    mkdir -p "$cache_dir" 2>/dev/null
    # A refresh that died (e.g. the terminal closed) leaves its lock behind;
    # treat a lock older than twice the TTL as abandoned.
    lock_age=$(file_age "$lock_dir" 2>/dev/null || echo "")
    [ -n "$lock_age" ] && [ "$lock_age" -ge $(( pr_ttl * 2 )) ] && rmdir "$lock_dir" 2>/dev/null
    if mkdir "$lock_dir" 2>/dev/null; then
        if [ "${CLAUDE_STATUSLINE_SYNC:-0}" = "1" ]; then
            refresh_prs
            cache_age=$(file_age "$cache_file" 2>/dev/null || echo "")
        else
            ( trap '' HUP; refresh_prs ) </dev/null >/dev/null 2>&1 &
            disown 2>/dev/null
        fi
    fi
fi

[ -f "$cache_file" ] || exit 0

# Per PR: <state glyph> #<number><check glyph>. The state glyph follows
# GitHub's own pull-request iconography (Nerd Font octicons by default; Ghostty
# bundles the Nerd Font symbols, so no font install is needed). The check glyph
# appears only for an open, non-draft PR with a signal, by precedence:
# failing checks > changes requested > pending checks > approved.
# Each PR number is an OSC 8 hyperlink to the PR (clickable in Ghostty,
# iTerm2, Kitty, WezTerm; inert elsewhere).
pr_line=$(jq -r \
    --arg red "$c_red" --arg green "$c_green" --arg yellow "$c_yellow" \
    --arg magenta "$c_magenta" --arg dim "$c_dim" --arg reset "$c_reset" \
    --arg links "$pr_links" --arg icons "$pr_icons" '
    def glyphs:
        if $icons == "unicode" then
            {open: "○", merged: "✔", closed: "✖", draft: "◌",
             failing: "✗", changes: "⚠", pending: "●", approved: "✓"}
        else
            {open: "", merged: "", closed: "", draft: "",
             failing: "", changes: "", pending: "", approved: ""}
        end;
    def checks:
        [ .statusCheckRollup[]? ] as $r
        | ($r | map(select(
              (.conclusion // "") as $c | (.state // "") as $s
              | ($c | IN("FAILURE","ERROR","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"))
                or ($s | IN("FAILURE","ERROR")))) | length > 0) as $failing
        | ($r | map(select(
              ((.status // "COMPLETED") != "COMPLETED")
                or ((.state // "") | IN("PENDING","EXPECTED")))) | length > 0) as $pending
        | if $failing then "failing" elif $pending then "pending" else "ok" end;
    def state_glyph:
        glyphs as $g
        | if .state == "MERGED" then $magenta + $g.merged
          elif .state == "CLOSED" then $red + $g.closed
          elif .isDraft then $dim + $g.draft
          else $green + $g.open end
        + $reset;
    def check_glyph:
        glyphs as $g
        | if .state != "OPEN" or .isDraft then ""
          elif checks == "failing" then $red + $g.failing + $reset
          elif .reviewDecision == "CHANGES_REQUESTED" then $yellow + $g.changes + $reset
          elif checks == "pending" then $yellow + $g.pending + $reset
          elif .reviewDecision == "APPROVED" then $green + $g.approved + $reset
          else "" end;
    def number_text:
        "#\(.number)" as $text
        | if $links == "1" and (.url // "") != ""
          then "\u001b]8;;\(.url)\u001b\\\($text)\u001b]8;;\u001b\\"
          else $text end;
    map(state_glyph + " " + number_text + check_glyph) | join(" ")
' "$cache_file" 2>/dev/null)

[ -z "$pr_line" ] && exit 0

stale=""
if [ -n "$cache_age" ] && [ "$cache_age" -ge $(( pr_ttl * 5 )) ]; then
    stale=" ${c_dim}(stale $(( cache_age / 60 ))m)${c_reset}"
fi

printf '%sPRs%s %s%s\n' "$c_dim" "$c_reset" "$pr_line" "$stale"
