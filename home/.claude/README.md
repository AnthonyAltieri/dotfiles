# Claude Code + herdr

Claude Code runs inside [herdr](https://herdr.dev), which detects the agent's
state (working, blocked, idle, done) from the pane itself and surfaces it in
the sidebar and tab bar. No custom notification hooks are needed for that.

## Codex implementation workers

Managed settings default Claude sessions to Opus and enable
OpenAI's `codex@openai-codex` plugin. On Darwin, the `codex-threads` MCP server
adds persistent Codex App thread lifecycle controls. The Claude
`spawn-orchestrator` skill combines them by keeping an isolated Claude agent
alive in the background while its inner Sol/xhigh Codex worker runs with
`--wait`; this preserves both the worktree and the durable Codex thread.

The MCP server runs the app-server binary bundled with Codex Desktop when it
is installed, so the bridge and the Desktop share one Codex version and thread
store format. Codex tags threads started this way with the Desktop's own
interactive source, `vscode`, rather than `appServer`. In the Desktop they show
up under chronological sort or search after the window regains focus; the
by-project sidebar only groups threads the Desktop created itself.

## Claude accounts

Every account uses the single `~/.claude` home, so settings, skills, and
history are shared and one account is signed in at a time. Switching applies to
every terminal. Use the numbered helper to switch:

```zsh
cc-login 1 # primary account
cc-login 2 # second account
```

Each number remembers the email it last signed in with, in
`~/.local/state/cc-login/accounts.json`, and prefills it on the login page. On
a first login, choose that account in the browser. For an account created with
Apple sign-in and Hide My Email, use the `@privaterelay.appleid.com` address shown
under Settings in Claude for iOS and choose **Continue with email**. If the
browser picks the wrong account, open the authorization URL in a private window.
Check who is signed in with `claude auth status --text`.

## Status line

`statusline-command.sh` renders one row:

```
dotfiles-e2 · Fable [ctx: 93%] in dotfiles on main
```

The first segment is the session's short name, the same name `ListAgents` and
`SendMessage` use to address this session from another one. Claude only puts a
name on the status line's stdin after `/rename`, so the script reads it from
the per-process registry Claude writes to `<config dir>/sessions/<pid>.json`,
matched on `session_id`. It falls back to the stdin `session_name`, then to
the first eight characters of the session id. `NO_COLOR` disables colors.
`tests/claude-statusline-smoke.sh` covers the registry lookup and both fallbacks.

## Session identity hook

`hooks/herdr-agent-state.sh` is herdr's Claude Code integration asset, vendored
here so the hook can be declared in the managed `settings.json` rather than
installed by `herdr integration install claude` (which would edit a file Home
Manager owns).

| Hook           | Command |
|----------------|---------|
| `SessionStart` | `herdr-agent-state.sh session` — reports the Claude session id and transcript path to the local herdr socket so herdr can resume the session after a server restart. |

The script exits silently unless it is running inside a herdr pane
(`HERDR_ENV=1`, `HERDR_SOCKET_PATH`, `HERDR_PANE_ID`), so it is harmless in a
plain terminal.

When bumping herdr, refresh the script from
`src/integration/assets/claude/herdr-agent-state.sh` in the matching release.

## Session state hook

`hooks/session_state.py` keeps one small file per main session in
`~/.cache/claude-sessions/<session id>.json` for `$root-orchestrator`: busy or
idle, the `AskUserQuestion` question or permission prompt waiting on the user,
whether the session is an orchestrator, and the Codex and Opus workers it
dispatched. An orchestrator's own attention block (`NEEDS YOUR ATTENTION` with numbered
headings, or `EVERYTHING IS GOOD` followed by `Next:` or `Run complete`) sets the verdict directly. Without one, when an orchestrator's turn ends, even with a Monitor or other
background task still running, a detached child asks Haiku (no tools,
settings, or hooks; about 800 tokens) whether its last message needs the user,
and stores a one-line `YOU:`, `WAIT:`, or `DONE:` verdict that the next prompt or tool call clears. It runs on `SessionStart`, `UserPromptSubmit`, `PreToolUse`
(`AskUserQuestion`, `Skill`), `PostToolUse`, `PostToolUseFailure`,
`PermissionRequest`, `PermissionDenied`, `Notification` (`permission_prompt`),
`SubagentStop`, `Stop`, and `SessionEnd`. It prints nothing, so it adds no
tokens to any context, takes about 30 ms, and always exits 0. Unit tests:
`python3 -m unittest discover -s home/.claude/hooks`.
