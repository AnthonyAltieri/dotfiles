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

## Two personal Claude accounts

The personal dotfiles profile deploys skills to both `~/.claude` and
`~/.claude-anthropic2` and shares their conversation history. Logins, settings,
and running-process state stay separate. `anthropic2` is a local profile label;
it does not require any particular email address or login provider.

Run `./bootstrap.sh personal` from the dotfiles repository to install the login
helper, skills, and shared history links. Open a new terminal afterward, or load
the helper in an existing one:

```zsh
source ~/.config/zsh/functions/cc-login.zsh
```

Use the numbered commands to log in and select an account for this terminal:

```zsh
cc-login 1 # primary account, ~/.claude
cc-login 2 # second account, ~/.claude-anthropic2
```

The helper prefills the email saved in the chosen profile. On a first login,
choose that account in the browser. Once login succeeds, subsequent `claude`
commands in the same terminal use that profile. Cancelling or failing login
keeps the previous selection. New terminals start with the default profile.

For an account created using Apple sign-in, first check the account email in
Claude for iOS: tap your initials, then look under Settings. If you used Hide My
Email, use the `@privaterelay.appleid.com` address shown there. Choose
**Continue with email** in the browser; Apple forwards the login email to your
Apple ID email address. See [Anthropic's login instructions](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account).

If the browser selects your primary account automatically, switch accounts or
open the authorization URL in a private window and use the second account's
email. After signing in, verify the email reported by:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude-anthropic2" claude auth status --text
```

After selecting an account, open the shared conversation picker:

```bash
claude --resume
```

To use a profile for a single command:

```bash
CLAUDE_CONFIG_DIR="$HOME/.claude" claude --resume
CLAUDE_CONFIG_DIR="$HOME/.claude-anthropic2" claude --resume
```

## Status line

`statusline-command.sh` renders two rows:

```
dotfiles-e2 · Fable [ctx: 93%] in dotfiles on main
PRs  #166  #165  #164  #163  #162
```

The first segment is the session's short name, the same name `ListAgents` and
`SendMessage` use to address this session from another one. Claude only puts a
name on the status line's stdin after `/rename`, so the script reads it from
the per-process registry Claude writes to `<config dir>/sessions/<pid>.json`,
matched on `session_id`. It falls back to the stdin `session_name`, then to
the first eight characters of the session id.

The second row lists the most recent pull requests you authored in the
current directory's GitHub repository, newest first. Each entry is a state
glyph, the PR number as an OSC 8 hyperlink to the PR on GitHub (clickable in
Ghostty, iTerm2, Kitty, and WezTerm), and, for an open PR with a signal, one
check glyph. The glyphs are GitHub's own octicons from the Nerd Font symbol
set, which Ghostty bundles, so no font install is needed; set
`CLAUDE_STATUSLINE_ICONS=unicode` for a terminal without Nerd Font fallback.

| State glyph | Unicode | Meaning |
|-------------|---------|---------|
| `` nf-oct-git_pull_request | `○` | open |
| `` nf-oct-git_merge | `✔` | merged |
| `` nf-oct-git_pull_request_closed | `✖` | closed without merging |
| `` nf-oct-git_pull_request_draft | `◌` | draft |

| Check glyph | Unicode | Meaning (open PRs only, first match wins) |
|-------------|---------|--------------------------------------------|
| `` nf-oct-x | `✗` | checks failing |
| `` nf-oct-alert | `⚠` | changes requested |
| `` nf-oct-dot_fill | `●` | checks pending |
| `` nf-oct-check | `✓` | approved |

`gh` never runs on the status line's synchronous path. The row is rendered from
`~/.cache/claude-statusline/prs-<owner>_<repo>.json`, which a detached
background refresh rewrites atomically once it is older than the TTL; the
`refreshInterval` in `settings.json` re-runs the script while the session is
idle so the row keeps up with CI. A row older than five TTLs is marked
`(stale Nm)`. Without `gh`, outside a repository, or without a GitHub remote
the row is omitted.

Environment knobs: `CLAUDE_STATUSLINE_PR_LIMIT` (default 5),
`CLAUDE_STATUSLINE_PR_TTL` seconds (default 60), `CLAUDE_STATUSLINE_CACHE_DIR`,
`CLAUDE_STATUSLINE_SYNC=1` to refresh in the foreground, `CLAUDE_STATUSLINE_LINKS=0`
for plain numbers, `CLAUDE_STATUSLINE_ICONS=unicode`, and `NO_COLOR`.
`tests/claude-statusline-smoke.sh` covers the registry lookup, every glyph in both
sets, the hyperlinks, and the cache contract with a stubbed `gh`.

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
