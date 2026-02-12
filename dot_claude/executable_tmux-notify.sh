#!/usr/bin/env bash

# Guard: exit silently if tmux is not installed or we're not in a session
command -v tmux >/dev/null 2>&1 || exit 0
[ -n "$TMUX" ] || exit 0

# When called from Claude Code hooks, $TMUX_PANE targets the correct window.
# When called from tmux hooks, it's unset and tmux defaults to the current window.
T=()
if [ -n "$TMUX_PANE" ]; then
  T=(-t "$TMUX_PANE")
fi

case "$1" in
  on)
    W=$(tmux display-message "${T[@]}" -p '#W')
    case "$W" in
      *!) ;; # already marked
      *) tmux rename-window "${T[@]}" "${W}!" ;;
    esac
    tmux set-option -w "${T[@]}" @claude-notify on
    ;;
  off)
    tmux rename-window "${T[@]}" "$(tmux display-message "${T[@]}" -p '#W' | sed 's/!$//')"
    tmux set-option -wu "${T[@]}" @claude-notify
    ;;
  off-if-claude)
    # Only clear if this window's ! was set by Claude Code
    if [ "$(tmux show-option -wqv "${T[@]}" @claude-notify)" = "on" ]; then
      tmux rename-window "${T[@]}" "$(tmux display-message "${T[@]}" -p '#W' | sed 's/!$//')"
      tmux set-option -wu "${T[@]}" @claude-notify
    fi
    ;;
esac
