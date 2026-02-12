#!/usr/bin/env bash

# Guard: exit silently if tmux is not installed or we're not in a session
command -v tmux >/dev/null 2>&1 || exit 0
[ -n "$TMUX" ] || exit 0

case "$1" in
  on)
    W=$(tmux display-message -p '#W')
    case "$W" in
      *!) ;; # already marked
      *) tmux rename-window "${W}!" ;;
    esac
    ;;
  off)
    tmux rename-window "$(tmux display-message -p '#W' | sed 's/!$//')"
    ;;
esac
