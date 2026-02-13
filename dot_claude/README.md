# Claude Code Tmux Notifications

Adds `!` to the tmux window name when Claude Code needs your attention (task complete, plan approval, questions, etc.), so you can see at a glance which tab needs attention. The `!` clears automatically when you switch to that window or submit a new prompt.

## How it works

### Hooks (`settings.json`)

Claude Code fires three hooks:

| Event               | Action                        |
|---------------------|-------------------------------|
| `Stop`              | `tmux-notify.sh on` — append `!` (task complete) |
| `Notification`      | `tmux-notify.sh on` — append `!` (plan approval, questions, etc.) |
| `UserPromptSubmit`  | `tmux-notify.sh off` — remove `!` from the window name |

### Window targeting (`$TMUX_PANE`)

When Claude Code invokes hooks, `$TMUX_PANE` is set to the pane where Claude is running. The script passes `-t "$TMUX_PANE"` to all tmux commands so it always modifies the correct window — even if you're focused on a different one.

### Mark-as-read (`@claude-notify`)

The `on` command sets a tmux window user option `@claude-notify` as a marker. An `after-select-window` hook in `tmux.conf` runs `tmux-notify.sh off-if-claude` whenever you switch windows, which only clears the `!` if `@claude-notify` is present. This means:

- Switching to a Claude window clears its `!` (mark as read)
- Other programs that use `!` in window names are left untouched

### Script commands (`tmux-notify.sh`)

| Command         | Description |
|-----------------|-------------|
| `on`            | Append `!` to window name, set `@claude-notify` marker |
| `off`           | Remove `!` from window name, unset `@claude-notify` marker |
| `off-if-claude` | Same as `off`, but only if `@claude-notify` is set on the window |
