---
name: spawn-orchestrator
description: Use a Claude Code Fable session to orchestrate waves of persistent Codex App threads, each running a Sol xhigh implementation worker in an isolated git worktree and ending in a draft PR. Use only when the user explicitly asks to spawn parallel agents or waves over an epic or backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Run the backlog from this Fable session while Codex Sol workers implement it. One issue gets one isolated Claude worktree, one persistent Codex App thread, one branch, and one draft PR. The Fable session plans waves, monitors threads, verifies outcomes, and never implements an issue itself.

## Required Integration

This workflow requires both managed integrations:

- OpenAI's `codex@openai-codex` Claude plugin, including the `codex:codex-rescue` subagent.
- The `codex-threads` MCP server, whose tools list, read, resume, steer, interrupt, rename, archive, and unarchive app-server threads.

Find lazy-loaded MCP tools before the first wave. If either integration is unavailable, stop and report which setup is missing. Do not substitute ordinary Claude implementation subagents, headless `codex exec`, or a direct MCP thread without worktree ownership.

## Worker Ownership

Create each worker with Claude's `Agent` tool using this shape:

```text
Agent(
  subagent_type: "codex:codex-rescue",
  isolation: "worktree",
  run_in_background: true,
  description: "<issue-key> <slug>",
  prompt: "--wait --fresh --model gpt-5.6-sol --effort xhigh --task \"<self-contained brief>\""
)
```

The outer Claude `Agent` owns the worktree and stays alive in the background. The inner Codex call must use `--wait`, never `--background`: ending the thin Claude wrapper early can terminate its Codex child and release its worktree. Codex creates a persistent app-server thread, so the work remains visible and resumable in the Codex App after the wrapper reports.

Invoking this skill is the user's explicit request to spawn the wave. Do not request separate permission per worker.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue or an explicit issue list. Resolve children and relations through connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every worktree starts from the current remote base.
- **Wave size:** 3 unless the user sets one; never exceed 5.
- **Advancement:** discrete waves by default. Refill a slot immediately only when the user requests rolling execution.
- **Worker model:** always `gpt-5.6-sol` with `xhigh` reasoning. Do not silently inherit either value from local Codex defaults.

## Plan the Backlog

1. Resolve the epic's children and blocking relations.
2. Claim each candidate through `$linear-claim-work`. An issue is eligible only when it is unblocked, non-terminal, and passes the ownership and existing-work gates.
3. Partition eligible issues into waves with disjoint file or subsystem ownership. Defer overlapping issues even when their dependency graph permits concurrency.
4. Re-evaluate blocked and deferred issues after every completed wave.

## Spawn a Wave

Put the complete implementation contract inside each worker's `--task` brief:

- issue key, URL, intended outcome, acceptance criteria, constraints, and non-goals;
- required verification and repository instructions;
- branch name `codex/<issue-key>-<slug>` and the base branch for the draft PR;
- done-when: tests pass, branch is pushed, draft PR is opened, Linear reflects reality, and the final response contains issue key, PR URL, Codex thread ID, and status (`pr-opened`, `blocked`, or `failed`);
- stay inside the assigned worktree and report newly discovered work instead of expanding scope.

Use a unique issue key in the task and thread title. Record the Claude agent name and, once discoverable, the Codex thread ID. The persistent thread can be found during execution with `codex_thread_list` using the issue key as `search_term`.

## Monitor Threads

- Use Claude's agent notifications and `ListAgents` for the outer wrapper's lifecycle.
- Use `codex_thread_list` and `codex_thread_read` for authoritative Codex status and turn IDs. A wrapper's completion message is a claim, not proof.
- When an active worker needs focused correction, call `codex_thread_steer` with the current thread and turn IDs. Use `SendMessage` only for wrapper-level guidance.
- If a worker must stop, interrupt the active Codex turn before ending its wrapper. Never abandon a running turn in a worktree whose owner is exiting.
- On completion, verify the draft PR, pushed branch, target base, and Linear state. Archive the Codex thread only after those checks pass or after a terminal failure is fully recorded.
- When the wave is fully reported and archived, re-plan and start the next eligible wave.

## Guardrails

- One issue per Codex thread and one thread per worktree. Never reuse a worker thread for another issue.
- Never place Codex `--background` inside the background Claude wrapper.
- Never merge PRs or mark an issue done on a worker's claim alone.
- Keep Linear mutations within `$linear-claim-work`; do not restructure the epic.
- `codex_thread_start` is for a caller that already owns an explicit worktree path. This skill uses the plugin wrapper so Claude remains the worktree owner.
- Leave nothing dangling: every wrapper and Codex turn is complete or interrupted, every thread is archived or reported, and every worktree with unpushed changes is identified.

## Report

After each wave and at the end, return the epic and base branch plus a table of issue → Claude wrapper → Codex thread → branch → PR → status. Include deferred overlaps, blocked issues with evidence, archived thread IDs, and the recommended review order or next wave.

## Composition

- `$linear-claim-work` owns claim, duplicate, and ownership-conflict gates.
- `$adversarial-review` may gate an individual worker's PR when requested; run it against that PR, not the whole wave.
