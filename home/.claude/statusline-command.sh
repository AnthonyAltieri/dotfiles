#!/bin/bash
# Claude Code status line.
#
# <session name> · <model> [ctx: N%] in <dir> on <branch>
#
# The session name is the short peer-messaging name other local Claude
# sessions use to address this one (what ListAgents / SendMessage show). It
# is only in the stdin JSON after /rename, so it is read from the per-process
# registry file Claude writes under <config dir>/sessions/.
#
# NO_COLOR disables ANSI colors.

input=$(cat)

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if [ -n "${NO_COLOR:-}" ]; then
    c_name="" c_reset=""
else
    c_name=$'\033[1;36m' c_reset=$'\033[0m'
fi

jq_field() {
    printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null
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
