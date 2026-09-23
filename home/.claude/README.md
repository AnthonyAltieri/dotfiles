# Claude Code + herdr

Claude Code runs inside [herdr](https://herdr.dev), which detects the agent's
state (working, blocked, idle, done) from the pane itself and surfaces it in
the sidebar and tab bar. No custom notification hooks are needed for that.

## Codex implementation workers

Managed settings use Fable for the Claude orchestration session and enable
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
