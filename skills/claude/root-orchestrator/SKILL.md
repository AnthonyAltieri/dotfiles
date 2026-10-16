---
name: root-orchestrator
description: Watch every spawn-orchestrator session working on this repository from one named Claude Code session. Post a health-grouped summary every 10 minutes, raise stalled, hung, or dead orchestrators within a minute, collect their open decisions, and tell orchestrators about conflicts they cannot see. Use when the user asks for a root orchestrator, an orchestrator of orchestrators, or one view over several orchestrator sessions; do not use to implement, dispatch, or merge work.
---

# Root Orchestrator

One named session watches the orchestrators working on this repository, the way an orchestrator watches its workers: passively, from files, without asking for status. It never implements, dispatches, claims, merges, or decides for another orchestrator. Each orchestrator owns its workers, ledger, and decisions; the root sees across them.

## Required Tooling

The helper `fleet.py` is deployed beside this skill at `~/.claude/skills/root-orchestrator/scripts/fleet.py`; the rest of this skill writes it as `fleet.py`. It reads the session registry (`~/.claude/sessions/*.json`), each orchestrator's `run.json`, and worker activity files. It writes nothing.

## Name Gate

Run `python3 fleet.py whoami` first. If it exits non-zero, reply `Name this session first: /rename <name>, then run me again.` and stop. Every orchestrator must be named the same way; `$spawn-orchestrator` enforces it.

## Scope

- By default the fleet is every orchestrator whose `run.json` names this repository (`repoPath`), plus runs settled within the last 12 hours.
- When the user names sessions ("watch trading-research, trading-ui and trading-worker"), pass them with `--sessions`; a named session with no `run.json` shows as `no-ledger`.
- An orchestrator appears only after its `run_state.py init`. A session started before that requirement shows as `no-ledger` until it runs `$spawn-orchestrator` again.

## Start

1. Run `python3 fleet.py snapshot` and post the result in a code block. Follow it with one line naming any `no-ledger` sessions and why.
2. Arm the stall monitor: the `Monitor` tool with `python3 fleet.py watch` (add the same `--repo`/`--sessions` you used), `timeout_ms: 1800000`, description `orchestrator health`. Re-arm it every time it expires.
3. Schedule the summary: `CronCreate` with cron `*/10 * * * *` and the prompt `Root orchestrator: post the fleet summary.` Recurring jobs expire after 7 days; re-create it when it does and say so once.

## The 10-Minute Summary

On each cron fire, run `python3 fleet.py snapshot` and post its output as printed, a markdown table with one row per orchestrator, most urgent first:

```text
**17:21 · trading · 4 orchestrators**

| Health | Orchestrator | Run | Running | Done | Blocked | Queued | Needs you | Note |
|---|---|---|--:|--:|--:|--:|--:|---|
| **needs you** | trading-research | discovery | 2 | 8 | 1 | 3 | 1 | answer in trading-research: 4. QUANT-444 decision · open 40m |
| **stalled** | trading-worker | i5-worker | 0 | 3 | 1 | 1 | 0 | nothing moved for 36h |
| ok | trading-portfolio | portfolio-v1 | 1 | 47 | 2 | 3 | 0 | moved 0m ago |
```

Rows sort by health: dead, hung, needs you, drift, stalled, no ledger, ok, done; a bold health is an alert. **Needs you** counts only questions the user must answer by typing in that orchestrator's session. **Blocked** counts issues waiting on anything else (another issue, CI, a third party, an action the user takes elsewhere); it never makes an orchestrator need the user. Post the table every fire, even when nothing changed; add commentary only about changes since the last summary.

## Health

`fleet.py` classifies each orchestrator, first match wins:

| State | Meaning |
|---|---|
| `settled` | `run.json` says the run is settled |
| `dead` | the session is gone or its process exited, run not settled |
| `hung` | the session shows busy, but its transcript has been silent for 20 minutes |
| `needs-you` | the orchestrator has open questions the user must answer in its session; alerts once the oldest is 30 minutes old. Blocked work never counts. |
| `drift` | `run.json` still says an issue is running 20 minutes after its Codex worker exited |
| `stalled` | running or queued work, nothing has moved for 20 minutes, and no open decision explains it |
| `ok` | otherwise |

Progress is the newest of the orchestrator's `lastProgressAt`, `updatedAt` (or the file's write time, if later), any Codex worker's `events.jsonl`, and any Opus subagent transcript of that session.

## Act on a Monitor Event

Each Monitor line is one health change. Post it at once, in one line, then:

- **needs-you:** list the open decisions with their numbers and the recommendation from the orchestrator's page or report, and say which session to answer in. Answers must be given in that session: a message from this root carries no user authority there.
- **stalled:** read the orchestrator's `state.md`, run directory, and page, then tell the user what is stuck and offer options with a recommendation, as `$spawn-orchestrator` does for a stalled worker. Message the orchestrator only with evidence it may lack (below).
- **drift:** the orchestrator has not recorded what its worker finished. Message it once with the issue and exit time from `fleet.py` and ask it to verify the result and record it with `run_state.py`; say so in the next summary. Do not message it again for the same issue.
- **hung:** report it with the silent duration. Do not message a hung session; the user decides whether to interrupt it.
- **dead:** report the last update, the run directory, and the resume command `claude --resume <name>`.
- **ok / settled:** post the change only.

Never resume, interrupt, rename, or restart another session yourself.

## Messages to Orchestrators

Use `SendMessage` only to give an orchestrator a fact it cannot see from its own run or has missed, and say what to verify:

- another orchestrator owns or is changing the same files or API;
- an issue it is waiting on was merged by another orchestrator;
- a shared resource (an exclusive test database, ports, the merge queue, disk) is contended by another orchestrator;
- one of its Codex workers exited 20 minutes ago and its `run.json` still says running (drift).

Write one short message with the evidence and the source (`trading-portfolio's run.json`, PR link, commit). Never ask an orchestrator for status, never relay the user's answers or approvals, and never tell it what to dispatch. It verifies the fact and decides itself.

## Guardrails

- Read-only on every other session's files.
- One summary per cron fire, one line per health change; no other unprompted chat.
- If `fleet.py` reports a skipped or malformed file, mention it once with its path.
- When every orchestrator in scope is settled, post a final summary, delete the cron job, stop the Monitor, and say the fleet is done.
