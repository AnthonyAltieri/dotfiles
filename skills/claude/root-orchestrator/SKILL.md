---
name: root-orchestrator
description: Watch every spawn-orchestrator session working on this repository from one named Claude Code session. Open a terminal pane that redraws the fleet table every minute at no token cost, wake only when an orchestrator needs the user, stalls, hangs, or dies, and tell orchestrators about conflicts they cannot see. Use when the user asks for a root orchestrator, an orchestrator of orchestrators, or one view over several orchestrator sessions; do not use to implement, dispatch, or merge work.
---

# Root Orchestrator

One named session watches the orchestrators working on this repository, the way an orchestrator watches its workers: passively, from files, without asking for status. It never implements, dispatches, claims, merges, or decides for another orchestrator. Each orchestrator owns its workers and decisions; the root sees across them.

Tokens are the constraint. Every turn of this session re-reads its whole context, so the root never polls or posts on a timer. Scripts build the view from files at no token cost; this session wakes only on alerts and when the user asks.

## Required Tooling

The helper `fleet.py` is deployed beside this skill at `~/.claude/skills/root-orchestrator/scripts/fleet.py`; the rest of this skill writes it as `fleet.py`. It reads, and never writes:

- `~/.cache/claude-sessions/<session id>.json`, kept by the `session_state.py` hook in every session: busy or idle, the question or permission prompt waiting on the user, whether the session is an orchestrator, and the workers it dispatched;
- the session registry (`~/.claude/sessions/*.json`) and worker files (Codex run directories, Opus subagent transcripts);
- an orchestrator's `run.json`, when it keeps one, for the settled flag only. Its issue states are written by hand and drift, so the table never reads them.

## Name Gate

Run `python3 fleet.py whoami` first. If it exits non-zero, reply `Name this session first: /rename <name>, then run me again.` and stop. Every orchestrator must be named the same way; `$spawn-orchestrator` enforces it.

## Scope

- By default the fleet is every session in this repository that ran `$spawn-orchestrator` or dispatched a worker, or keeps a `run.json` naming this repository, plus sessions that ended or settled within the last 12 hours.
- When the user names sessions ("watch trading-research, trading-ui and trading-worker"), pass them with `--sessions`.
- A session with no hook data yet is marked `no hook data yet`; running sessions load the hook from the settings file on their next event, so this clears by itself. Until then its questions and permission prompts are invisible.

## Start

1. Run `python3 fleet.py snapshot` and post the markdown table it prints.
2. Open the pane: `python3 fleet.py pane` (add the same `--repo`/`--sessions`). It splits a herdr or tmux pane below this one, sized to the table, running `watch` on it every minute. If it exits 3, give the user the command it printed to run in a terminal.
3. Arm the alert monitor: the `Monitor` tool with `python3 fleet.py watch` (same flags), `timeout_ms: 1800000`, description `orchestrator health`. Re-arm it every time it expires, without comment. A re-armed watch resumes from what the last one reported, so it stays silent until something changes; its first run ever lists every orchestrator once. The watch also raises a desktop notification (herdr, or `notify-send`) when an orchestrator starts needing the user, so the user hears about it without watching this session.

Do not schedule a recurring summary. The pane is the periodic view.

## The Table

When the user asks for status, run `python3 fleet.py snapshot` and post its markdown table as printed:

```text
**17:21 · trading · 3 orchestrators · 1 done or dead hidden**

| Health | Orchestrator | Running | Last finished | Pace | Note |
|---|---|--:|---|---|---|
| **needs you** | trading-research | 2 | 1h ago (1 in 2h) | QUANT-525 running 3h21m (usually 22m) | question: Use the :59 gate population? · 40m |
| **stalled** | trading-worker | 0 | 1d ago (0 in 2h) | — | idle, nothing running for 36h |
| ok | trading-portfolio | 1 | 3m ago (4 in 2h) | slower: last 4 took ~42m (usually 22m) | waiting on 1 worker |
```

Rows sort by health; a bold health is an alert. Dead and done orchestrators leave the table an hour after they change; the title counts them. The columns come from the workers' own files (Codex run directories, Opus records in the hook state):

- **Running:** workers running now.
- **Last finished:** how long since a worker last finished, and how many finished in the last 2 hours; a growing age with a low count is an orchestrator slowing down.
- **Pace:** this orchestrator's workers against its own usual worker time (the median over the last 7 days, before the last 2 hours), worst news first: `<issue> silent <age>` when a running worker has written nothing for 20 minutes (probably stuck); `<issue> running 3h21m (usually 22m)` when a running worker has taken at least twice the usual; then `faster:` or `slower: last 4 took ~42m (usually 22m)` when the workers that finished in the last 2 hours took at least 1.5× less or more than usual; otherwise `on pace`, or `—` without enough history. Orchestrators do different work, so pace never compares one orchestrator with another. Pace is not a health state and never alerts; mention it only when the user asks for status.

 **needs you** means the session is waiting for the user to type: an open question or a permission prompt, which the Note quotes. Blocked or parked work never makes an orchestrator need the user; for an orchestrator's blocked and parked issues, read its own report or dashboard.

When the user asks what is blocked, queued, or unattended, `run.json` issue states are a starting point, not the answer: they are written by hand and lag. Before calling work unattended, read the orchestrator's latest `waiting:` Note (the `Next:` line of its `EVERYTHING IS GOOD` block, or Haiku's summary of a message without one) and its last message; an orchestrator that names the issue and why it holds it is attending to it. Say "held by <orchestrator>: <reason>" instead of "nobody is working on it".

## Health

`fleet.py` classifies each orchestrator, first match wins:

| State | Meaning |
|---|---|
| `done` | `run.json` says the run is settled, or the orchestrator's last message ends with `EVERYTHING IS GOOD` and `Run complete` (or, without that block, Haiku judged it finished) and no worker or background task is running |
| `dead` | the session ended or its process exited |
| `needs you` | the session waits for the user to type: an open question (`AskUserQuestion`), a permission prompt (its own or a worker's), or a turn whose last message ends with a `NEEDS YOUR ATTENTION` block (or, without one, that Haiku judged to need the user), even while a background task runs; the Note says what. Alerts once open 10 minutes |
| `hung` | the session is busy, no worker is running, and its transcript has been silent for 20 minutes |
| `stalled` | the session is idle, no worker has run for 20 minutes, and no verdict explains it (Haiku failed or the session predates the hook) |
| `ok` | working, idle while its workers run, or idle with a last message that ends with `EVERYTHING IS GOOD` and `Next:` (or, without that block, that Haiku judged to be waiting on something other than the user); the Note says what |

## Act on a Monitor Event

Each Monitor line is one health change. Post it at once, in one line, then:

- **needs you:** quote the question, the permission prompt, the first numbered heading of its `NEEDS YOUR ATTENTION` block, or, without one, Haiku's one-line summary, and say which session to answer in. Answers must be given there: a message from this root carries no user authority.
- **stalled:** read the orchestrator's `state.md` and run directory, then tell the user what is stuck and offer options with a recommendation, as `$spawn-orchestrator` does for a stalled worker. A finished run also shows as stalled until it settles; say so when the ledger shows every issue terminal.
- **hung:** report it with the silent duration. Do not message a hung session; the user decides whether to interrupt it.
- **dead:** report the last update, the run directory, and the resume command `claude --resume <name>`.
- **ok / done:** post the change only. Leaving needs you for ok means the session started working again, not that the user answered: a finished worker or background job wakes it too. Say "back to working", never "answered".

Never resume, interrupt, rename, or restart another session yourself.

## Messages to Orchestrators

Use `SendMessage` only to give an orchestrator a fact it cannot see from its own run, and say what to verify:

- another orchestrator owns or is changing the same files or API;
- an issue it is waiting on was merged by another orchestrator;
- a shared resource (an exclusive test database, ports, the merge queue, disk) is contended by another orchestrator.

Write one short message with the evidence and the source (PR link, commit, run directory). Never ask an orchestrator for status, never relay the user's answers or approvals, and never tell it what to dispatch. It verifies the fact and decides itself.

## Guardrails

- Read-only on every other session's files.
- One line per health change and replies to the user; no other unprompted chat, no timers.
- If `fleet.py` reports a skipped or malformed file, mention it once with its path.
- When every orchestrator in scope is done, post a final table, stop the Monitor, close the pane, and say the fleet is done.
