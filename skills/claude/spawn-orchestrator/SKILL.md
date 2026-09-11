---
name: spawn-orchestrator
description: Use a Claude Code Fable session to orchestrate persistent Codex App threads, each running an Astra xhigh worker in an isolated worktree and ending in a draft PR. Refill available slots with ready issues as workers finish; honor explicitly requested fixed waves. Use only when the user explicitly asks to spawn parallel agents over an epic or backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Run the backlog from this Fable session while Codex Astra workers implement it. One issue gets one isolated Claude worktree, one persistent Codex App thread, one branch, and one draft PR. The Fable session schedules ready work, monitors threads, verifies outcomes, and never implements an issue itself.

## Required Integration

This workflow requires both managed integrations:

- OpenAI's `codex@openai-codex` Claude plugin, including the `codex:codex-rescue` subagent.
- The `codex-threads` MCP server, whose tools list, read, resume, steer, interrupt, rename, archive, and unarchive app-server threads.

Find lazy-loaded MCP tools before dispatching workers. If either integration is unavailable, stop and report which setup is missing. Do not substitute ordinary Claude implementation subagents, headless `codex exec`, or a direct MCP thread without worktree ownership.

## Worker Ownership

Create each worker with Claude's `Agent` tool using this shape:

```text
Agent(
  subagent_type: "codex:codex-rescue",
  isolation: "worktree",
  run_in_background: true,
  description: "<issue-key> <slug>",
  prompt: "--wait --fresh --model gpt-6-astra --effort xhigh --task \"<self-contained brief>\""
)
```

The outer Claude `Agent` owns the worktree and stays alive in the background. The inner Codex call must use `--wait`, never `--background`: ending the thin Claude wrapper early can terminate its Codex child and release its worktree. Codex creates a persistent app-server thread, so the work remains visible and resumable in the Codex App after the wrapper reports.

Invoking this skill is the user's explicit request to spawn workers over the requested backlog. Do not request separate permission per worker.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue or an explicit issue list. Resolve children and relations through connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every worktree starts from the current remote base.
- **Concurrency:** up to 3 active issue workers unless the user sets a lower or higher limit; never exceed 5. Include workers in review, remediation, or a verification queue. Reduce intake when host resources or the user's review backlog cannot support it.
- **Advancement:** rolling refill by default — after verifying a completion or safely parking blocked work, fill the available slot with the next eligible issue without waiting for unrelated workers. Explicit fixed waves wait for the whole wave to report and settle before the next starts. Honor user task/wave limits and stop requests in either mode.
- **Worker model:** always `gpt-6-astra` with `xhigh` reasoning. Do not silently inherit either value from local Codex defaults.

## Plan the Backlog

1. Resolve the requested issues and their blocking relations. Track each worker's owned paths and APIs, stage, resource needs, and blockers, including other active repository tasks such as a test-suite audit.
2. An eligible issue is non-terminal and has no open blocking relation. Refresh dependencies and existing-work ownership before every dispatch, then claim through `$linear-claim-work`. An open PR or a worker's completion message does not satisfy a dependency that requires merged code; verify the required result on the base branch. Resume an existing issue's worker instead of creating a duplicate.
3. Choose ready issues with disjoint owned files and no conflicting API decisions. Sharing a crate or subsystem alone does not require serialization. An independently scoped design document may proceed alongside implementation; its dependent code still waits for the reviewed decision. Do not invent additional work outside the requested backlog to fill slots.
4. Prefer work that removes a blocker on the shortest path to the user's requested outcome. Start ready design decisions early when they unlock several later changes; use spare capacity for independent fixes. Readiness alone is not a reason to postpone critical design behind peripheral cleanup.
5. Re-evaluate the queue after a verified completion, merge, newly discovered blocker, or ownership change. If capacity is idle, name the concrete dependency, overlap, resource, or user-limit reason.

## Dispatch Ready Work

Put the complete implementation contract inside each worker's `--task` brief:

- issue key, URL, intended outcome, acceptance criteria, constraints, and non-goals;
- required verification and repository instructions;
- owned paths and APIs, current parallel neighbors, and any host-resource or exclusive verification slot it must wait for;
- the Worker Testing Guidance block below, verbatim;
- branch name `codex/<issue-key>-<slug>` and the base branch for the draft PR;
- done-when: tests pass under the testing policy, branch is pushed, draft PR is opened, Linear reflects reality, and the final response contains issue key, PR URL, Codex thread ID, and status (`pr-opened`, `blocked`, or `failed`);
- stay inside the assigned worktree and report newly discovered work instead of expanding scope.

Use a unique issue key in the task and thread title. Record the Claude agent name and, once discoverable, the Codex thread ID. The persistent thread can be found during execution with `codex_thread_list` using the issue key as `search_term`.

## Schedule Verification and Integration

Keep the ready-work queue separate from the heavy-check queue. On a shared host, grant one exclusive slot for full suites, provider benchmarks, or other checks that contend for shared state or substantial CPU/RAM. Coordinate that slot with other active repository tasks. Independent hosts may run checks concurrently where repository rules permit; serialize final merges to each base branch when merging is authorized.

While a worker holds that slot, other workers may design, edit, review, and run focused checks within the remaining resource budget. Pause only conflicting or resource-heavy operations, not every task. Required gates still run: do not skip checks, expand timeouts, or reuse evidence invalidated by changed code or base. Refresh the base and repeat the required affected checks and reviews before final integration when it advances.

## Worker Testing Guidance

Every worker brief carries this block verbatim so each fresh worker context receives the testing policy. `$test-audit` owns the full policy; this is its condensed form.

```text
Testing policy (non-negotiable; see the test-audit skill for the full text):
- Budgets are hard and never raised: whole unit suite < 10s, whole e2e suite < 60s. Over budget means delete or merge tests, never add retries or bump timeouts.
- Run the smallest test that proves the point while iterating: one test or one file, never the whole suite. Run the full suite exactly twice: before opening the draft PR and on the final head.
- Deterministic always: no sleeps, polling, retries, skip, timeouts as synchronization, or reliance on wall-clock, randomness, ordering, or leftover state. Wait only on a signal the code under test emits.
- Two tiers only, unit and e2e; no integration tier.
- Unit: public API only, one behavior per test, nothing the type checker already proves, mock only process boundaries, inject the clock, no snapshot tests except serialized wire contracts.
- E2e: one happy path per critical flow plus the failures that would page someone; real dependencies, no mocks; a flaky e2e test is fixed or deleted the same day.
- Every bug fix ships exactly one regression test that failed before the fix.
- Every test answers "what bug does this catch?"; if you cannot say, do not write it.
- Report the runner commands you used and the suite times in the final response.
```

## Monitor Threads

- Use Claude's agent notifications and `ListAgents` for the outer wrapper's lifecycle.
- Use `codex_thread_list` and `codex_thread_read` for authoritative Codex status and turn IDs. A wrapper's completion message is a claim, not proof.
- When an active worker needs focused correction, call `codex_thread_steer` with the current thread and turn IDs. Use `SendMessage` only for wrapper-level guidance.
- If a worker must stop, interrupt the active Codex turn before ending its wrapper. Never abandon a running turn in a worktree whose owner is exiting.
- On completion, verify the draft PR, pushed branch, target base, and Linear state. Audit the PR's new or changed tests with `$test-audit`; on a policy violation, steer the worker to fix it before archiving. Archive the Codex thread only after those checks pass or after a terminal failure is fully recorded.
- After verified completion and wrapper shutdown, release resource slots and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- If a worker goes silent, inspect it before deciding it is blocked; a long-running check is not itself a blocker. For confirmed blocked work, record the issue, dependency, branch/PR, and resume condition. Interrupt the Codex turn and verify recoverable work is preserved before ending its wrapper and releasing capacity. Repository lifecycle rules control whether the thread is retained or archived.
- Keep parked ownership recorded. Reacquire capacity and recheck dependencies/overlap before resuming the same issue's thread. Re-establish a live worktree owner before resuming Codex if its wrapper has exited; never create a duplicate worker or resume into a released worktree.
- Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Guardrails

- One issue per Codex thread and one thread per worktree. Never reuse a worker thread for another issue.
- Never place Codex `--background` inside the background Claude wrapper.
- Never merge PRs or mark an issue done on a worker's claim alone.
- Keep Linear mutations within `$linear-claim-work`; do not restructure the epic.
- `codex_thread_start` is for a caller that already owns an explicit worktree path. This skill uses the plugin wrapper so Claude remains the worktree owner.
- Leave nothing dangling: every wrapper and Codex turn is complete or interrupted, every thread is archived or reported, and every worktree with unpushed changes is identified.

## Report

At meaningful completions or blocker changes, and at the end, return the epic and base branch plus a table of issue → Claude wrapper → Codex thread → branch → PR → status. Include active versus available slots, the heavy-check owner, ready work waiting and why, blocked or parked work with resume conditions, and the next dispatch or review order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns claim, duplicate, and ownership-conflict gates.
- `$adversarial-review` may gate an individual worker's PR when requested; run it against that PR, not the whole wave.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
