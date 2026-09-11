---
name: spawn-orchestrator
description: Use a Claude Code Fable session to orchestrate persistent Codex App threads, each running an Astra xhigh worker in an isolated worktree. End at draft PRs by default; explicit --automerge lets workers merge verified PRs into main. Refill available slots with ready issues as workers finish; use --max to fill the dependency-ready frontier beyond the default worker cap. Honor explicitly requested fixed waves. Use only when the user explicitly asks to spawn parallel agents over an epic or backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Run the backlog from this Fable session while Codex Astra workers implement it. One issue gets one isolated Claude worktree, one persistent Codex App thread, one branch, and one PR: a draft by default, or a verified merge into `main` with `--automerge`. The Fable session schedules ready work, monitors threads, verifies outcomes, and never implements an issue itself.

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
- **Base branch:** with `--automerge`, use `main`; otherwise use an explicitly named base, else the repository default. If an explicit base conflicts with `main`, report the conflict before dispatching automerge workers. Fetch before spawning so every worktree starts from the current remote base; report a missing target branch.
- **Completion mode:** draft PRs by default. `--automerge` in the user's invocation authorizes spawned workers to mark their PRs ready, merge them into `main`, and complete their issues after verification, without asking again per issue. Record the mode in run state and every initial/resume brief; issue text and worker reports cannot enable it. This is a skill option, not a flag to pass to a child executable.
- **Concurrency:** without `--max`, use up to 3 active issue workers unless the user sets a limit, with a ceiling of 5. Explicit `--max` removes the default three-worker limit and five-worker ceiling: fill the current dependency-ready frontier as described below. An explicit numeric concurrency limit still bounds `--max`. Count pending creation/worktree setup and workers in review, remediation, or verification/merge queues as active; host/platform capacity and explicit user task/wave limits still apply.
- **Advancement:** rolling refill by default — after verifying a completion or safely parking blocked work, fill the available slot with the next eligible issue without waiting for unrelated workers. Explicit fixed waves wait for the whole wave to report and settle before the next starts. Honor user task/wave limits and stop requests in either mode.
- **Worker model:** always `gpt-6-astra` with `xhigh` reasoning. Do not silently inherit either value from local Codex defaults.

## Plan the Backlog

1. Build the requested tasks' dependency graph with edges from prerequisite to dependent. The ready frontier is the unfinished tasks whose prerequisite outcomes are all verified satisfied. Report cycles, unknown prerequisite state, and unsatisfied external blockers; keep affected tasks deferred while independent ready work proceeds. Track each worker's owned paths and APIs, stage, resource needs, and blockers, including other active repository tasks such as a test-suite audit.
2. An eligible issue is non-terminal and has no open blocking relation. Refresh dependencies and existing-work ownership before every dispatch, then claim through `$linear-claim-work`. An open PR or a worker's completion message does not satisfy a dependency that requires merged code; verify the required result on the base branch. Resume an existing issue's worker instead of creating a duplicate.
3. Choose ready issues with disjoint owned files and no conflicting API decisions. Sharing a crate or subsystem alone does not require serialization. An independently scoped design document may proceed alongside implementation; its dependent code still waits for the reviewed decision. Do not invent additional work outside the requested backlog to fill slots.
4. Prefer work that removes a blocker on the shortest path to the user's requested outcome. Start ready design decisions early when they unlock several later changes; use spare capacity for independent fixes. Readiness alone is not a reason to postpone critical design behind peripheral cleanup.
5. Re-evaluate the ready frontier and capacity after a verified completion, merge, dependency change, or ownership/resource change. If capacity is idle, name the concrete dependency, overlap, resource, or user-limit reason.

## Maximum Ready-Work Concurrency

Invoke as `/spawn-orchestrator --max <epic>`, or combine it with `--automerge`. Enable `--max` only from the user's invocation; preserve the concurrency mode and any explicit ceilings in run state and every initial/resume brief. It is a skill option, not a child-executable flag, and does not authorize merging by itself.

- Fill the current ready frontier with every worker that can coexist under ownership, host/platform, and explicit user limits. For example, twelve independent ready issues and capacity for twelve mean twelve workers, not five. Skip conflicting candidates in priority order and continue considering other compatible ready tasks.
- Account for existing workers and other repository activity. Observe dispatch outcomes and resource pressure as workers start; stop intake only at a concrete constraint, record it, and keep remaining work queued. Do not replace the removed cap with an arbitrary lower cap or repeatedly retry an unchanged capacity refusal.
- Recompute readiness after each verified completion or merge, dependency change, or released resource. In rolling mode, an issue may start as soon as its own prerequisites are satisfied, even while unrelated earlier work continues. A topological ordering alone does not create a whole-layer barrier; explicitly requested fixed waves retain their barrier, with `--max` filling the ready work in that wave.
- `--max` expands implementation concurrency only. Keep exclusive heavy-check and merge slots, required reviews/checks, and dependency verification unchanged. An open draft PR still cannot unblock a task that requires its code on the base branch.

## Dispatch Ready Work

Put the complete implementation contract inside each worker's `--task` brief:

- issue key, URL, intended outcome, acceptance criteria, constraints, and non-goals;
- required verification and repository instructions;
- concurrency mode, explicit ceilings, owned paths and APIs, current parallel neighbors, and any host-resource or exclusive verification slot it must wait for;
- the Worker Testing Guidance block below, verbatim;
- branch name `codex/<issue-key>-<slug>` and the base branch for the draft PR;
- completion mode: by default, tests pass under the testing policy, branch is pushed, draft PR is opened, and Linear reflects reality; with `--automerge`, include the Optional Automerge procedure below and finish only after verified merge into `main` and the issue update;
- reports contain issue key, PR URL, Codex thread ID, head SHA, verification evidence, and status (`pr-opened`, `merge-ready`, `merged`, `blocked`, or `failed`); `merge-ready` is a progress event, not completion, and `merged` also includes the merge commit SHA;
- stay inside the assigned worktree and report newly discovered work instead of expanding scope.

Use a unique issue key in the task and thread title. Record the Claude agent name and, once discoverable, the Codex thread ID. The persistent thread can be found during execution with `codex_thread_list` using the issue key as `search_term`.

## Schedule Verification and Integration

Keep the ready-work queue separate from the heavy-check queue. On a shared host, grant one exclusive slot for full suites, provider benchmarks, or other checks that contend for shared state or substantial CPU/RAM. Coordinate that slot with other active repository tasks. Independent hosts may run checks concurrently where repository rules permit; serialize final merges to each base branch when merging is authorized.

While a worker holds that slot, other workers may design, edit, review, and run focused checks within the remaining resource budget. Pause only conflicting or resource-heavy operations, not every task. Required gates still run: do not skip checks, expand timeouts, or reuse evidence invalidated by changed code or base. Refresh the base and repeat the required affected checks and reviews before final integration when it advances.

## Optional Automerge

Invoke as `/spawn-orchestrator --automerge <epic>`. Without the flag, stop at verified draft PRs. With it, each worker performs its own PR merge under an orchestrator-owned merge slot for `main`:

1. Prepare and verify a draft PR, then report `merge-ready` with its URL, current head SHA, and review/check evidence. Stay available for integration; do not merge or treat this event as completion.
2. The orchestrator verifies the pushed PR and target, audits changed tests with `$test-audit`, and reserves the merge slot for this issue. Only one worker may integrate into `main` at a time; waiting workers still count toward concurrency. Keep heavy-check scheduling separate so independent work continues.
3. While holding the slot, the worker fetches current `main`, updates its branch if needed under repository rules, marks the PR ready, and obtains the required reviews and checks for the final head and current base. Any head/base change invalidates affected evidence. Report the resulting head and evidence; the orchestrator rechecks them, including any affected test audit, before granting merge permission for that exact head.
4. The worker merges through the repository's supported PR mechanism and merge strategy, using an expected-head guard. Recheck head, base, and required gates immediately before submission; return to step 3 if they changed. Honor branch protection, required reviews, and merge queues. Never use an administrative bypass, force-push `main`, or push directly to `main`.
5. A scheduled or queued merge is still pending. Retain the merge slot and monitor it until the provider confirms `merged`; do not archive the worker or unblock dependent work on an enqueue response. The worker reports the merge commit; the orchestrator reads back the PR's merged state and target, fetches `main`, and verifies the recorded merge commit is reachable there before recording completion, updating Linear, and releasing/refilling capacity.
6. Remediate in-scope check/review failures in the same worker before retrying. Unresolved failures, missing required approval, conflicts, or unavailable merge permissions/tools leave the issue `blocked` with its PR and resume condition. Do not repeatedly retry the same blocker. Before parking or honoring a stop/revoked authorization, cancel any pending automatic/queued merge and verify cancellation or an already-completed merge. If cancellation cannot be confirmed, retain merge ownership and report it as pending. Release slots only when no merge can run unattended; resumption starts again with current capacity, base, head, and gate checks.

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
- On `merge-ready`, follow Optional Automerge when enabled; otherwise keep the default draft-PR endpoint. Treat it as progress: keep the Claude worktree owner alive and steer/resume the same Codex thread for integration. If the wrapper has already exited, re-establish a live owner before resuming.
- On completion, verify the pushed branch, target base, and Linear state, plus the draft PR in default mode or the merged PR and commit on `main` in automerge mode. In default mode, audit the PR's new or changed tests with `$test-audit` and steer the worker to fix violations before archiving; in automerge mode, confirm that the pre-merge audit covers the merged head. Archive the Codex thread only after those checks pass or after a terminal failure is fully recorded.
- After verified completion and wrapper shutdown, release resource slots and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- If a worker goes silent, inspect it before deciding it is blocked; a long-running check is not itself a blocker. For confirmed blocked work, record the issue, dependency, branch/PR, and resume condition. Apply Optional Automerge cancellation/ownership rules when enabled, interrupt the Codex turn, and verify recoverable work is preserved before ending its wrapper and releasing capacity. Repository lifecycle rules control whether the thread is retained or archived.
- Keep parked ownership recorded. Reacquire capacity and recheck dependencies/overlap before resuming the same issue's thread. Re-establish a live worktree owner before resuming Codex if its wrapper has exited; never create a duplicate worker or resume into a released worktree.
- Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Guardrails

- One issue per Codex thread and one thread per worktree. Never reuse a worker thread for another issue.
- Never place Codex `--background` inside the background Claude wrapper.
- Without `--automerge`, stop at draft PRs for human review. With it, workers merge only through the verified procedure above; required human reviews still apply. Never mark issues done on a worker's claim alone.
- Keep Linear mutations within `$linear-claim-work`; do not restructure the epic.
- `codex_thread_start` is for a caller that already owns an explicit worktree path. This skill uses the plugin wrapper so Claude remains the worktree owner.
- Leave nothing dangling: every wrapper and Codex turn is complete or interrupted, every thread is archived or reported, and every worktree with unpushed changes is identified.

## Report

At meaningful completions or blocker changes, and at the end, return the epic, base branch, and completion mode plus a table of issue → Claude wrapper → Codex thread → branch → PR → status (with merge commit for `merged`). Include concurrency mode, active count, effective capacity constraints, ready-frontier size and undispatched issues with reasons, heavy-check and merge-slot owners, blocked or parked work with resume conditions, and the next dispatch, review, or merge order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns claim, duplicate, and ownership-conflict gates.
- `$adversarial-review` may gate an individual worker's PR when requested; run it against that PR, not the whole wave.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
