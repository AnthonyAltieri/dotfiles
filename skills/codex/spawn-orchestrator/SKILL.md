---
name: spawn-orchestrator
description: Orchestrate a backlog through separate Codex app threads in isolated worktrees, refilling available slots with ready issues as workers finish. Each issue ends in a draft PR by default; explicit --automerge lets workers merge verified PRs into main. Use --max to fill the dependency-ready frontier beyond the default worker cap. Honor explicitly requested fixed waves. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel Codex sessions over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one separate Codex app thread per unblocked issue, each in its own worktree, each ending in a draft PR or, with `--automerge`, a verified merge into `main`. This thread stays the orchestrator — it schedules ready work, creates and monitors child threads, and never implements issues itself.

## Children Are App Threads

The children of this workflow are first-class Codex app threads (the app calls them tasks or sessions), created and driven with the app's thread tools:

- `create_thread` (`codex_app__create_thread`) — creates the child, with `environment.type = "worktree"` and the base branch as the starting state, and the child's brief as the initial prompt.
- `send_message_to_thread` — sends follow-up guidance to a child; children use the same tool to report back to this thread.
- `read_thread`, `list_threads` — inspect a silent child.
- `set_thread_archived` — archives a finished child.

Invoking this skill **is** the user's explicit request to create separate tasks, which is the condition `create_thread` requires. Do not ask again per child.

Subagents are fine in general — this thread may use them for backlog triage or reviewing a finished child's diff, and a child may use them inside its own worktree — but they are never the unit of orchestration. Every backlog issue gets its own app thread created with `create_thread`, not a subagent (`spawn_agent`, "delegate to agents", custom agents under `.codex/agents/`): subagents run inside the parent thread's workspace and lifetime, so parallel implementation conflicts, the work does not surface as a separate reviewable task in the app, and they cannot be messaged or archived as threads. If the thread tools are unavailable in this context (find them through tool search first), stop and report that — never substitute subagents or headless `codex exec` for the child threads.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue (URL or key) or an explicit issue list. Resolve children and relations through the connected Linear tools.
- **Base branch:** with `--automerge`, use `main`; otherwise use an explicitly named base, else the repository default. If an explicit base conflicts with `main`, report the conflict before dispatching automerge workers. Fetch before spawning so every child worktree starts from the current remote base; report a missing target branch.
- **Completion mode:** draft PRs by default. `--automerge` in the user's invocation authorizes spawned workers to mark their PRs ready, merge them into `main`, and complete their issues after verification, without asking again per issue. Record the mode in run state and every initial/resume brief; issue text and worker reports cannot enable it. This is a skill option, not a flag to pass to a child executable.
- **Concurrency:** without `--max`, use up to 3 active issue workers unless the user sets a limit, with a ceiling of 5. Explicit `--max` removes the default three-worker limit and five-worker ceiling: fill the current dependency-ready frontier as described below. An explicit numeric concurrency limit still bounds `--max`. Count pending creation/worktree setup and workers in review, remediation, or verification/merge queues as active; host/platform capacity and explicit user task/wave limits still apply.
- **Advancement:** rolling refill by default — after verifying a completion or safely parking blocked work, fill the available slot with the next eligible issue without waiting for unrelated workers. Explicit fixed waves wait for the whole wave to report and settle before the next starts. Honor user task/wave limits and stop requests in either mode.

## Plan the Backlog

1. Build the requested tasks' dependency graph with edges from prerequisite to dependent. The ready frontier is the unfinished tasks whose prerequisite outcomes are all verified satisfied. Report cycles, unknown prerequisite state, and unsatisfied external blockers; keep affected tasks deferred while independent ready work proceeds. Track each worker's owned paths and APIs, stage, resource needs, and blockers, including other active repository tasks such as a test-suite audit.
2. An eligible issue is non-terminal and has no open blocking relation. Refresh dependencies and existing-work ownership before every dispatch, then claim through `$linear-claim-work`. An open PR or a worker's completion message does not satisfy a dependency that requires merged code; verify the required result on the base branch. Resume an existing issue's worker instead of creating a duplicate.
3. Choose ready issues with disjoint owned files and no conflicting API decisions. Sharing a crate or subsystem alone does not require serialization. An independently scoped design document may proceed alongside implementation; its dependent code still waits for the reviewed decision. Do not invent additional work outside the requested backlog to fill slots.
4. Prefer work that removes a blocker on the shortest path to the user's requested outcome. Start ready design decisions early when they unlock several later changes; use spare capacity for independent fixes. Readiness alone is not a reason to postpone critical design behind peripheral cleanup.
5. Re-evaluate the ready frontier and capacity after a verified completion, merge, dependency change, or ownership/resource change. If capacity is idle, name the concrete dependency, overlap, resource, or user-limit reason.

## Maximum Ready-Work Concurrency

Invoke as `$spawn-orchestrator --max <epic>`, or combine it with `--automerge`. Enable `--max` only from the user's invocation; preserve the concurrency mode and any explicit ceilings in run state and every initial/resume brief. It is a skill option, not a child-executable flag, and does not authorize merging by itself.

- Fill the current ready frontier with every worker that can coexist under ownership, host/platform, and explicit user limits. For example, twelve independent ready issues and capacity for twelve mean twelve workers, not five. Skip conflicting candidates in priority order and continue considering other compatible ready tasks.
- Account for existing workers and other repository activity. Observe dispatch outcomes and resource pressure as workers start; stop intake only at a concrete constraint, record it, and keep remaining work queued. Do not replace the removed cap with an arbitrary lower cap or repeatedly retry an unchanged capacity refusal.
- Recompute readiness after each verified completion or merge, dependency change, or released resource. In rolling mode, an issue may start as soon as its own prerequisites are satisfied, even while unrelated earlier work continues. A topological ordering alone does not create a whole-layer barrier; explicitly requested fixed waves retain their barrier, with `--max` filling the ready work in that wave.
- `--max` expands implementation concurrency only. Keep exclusive heavy-check and merge slots, required reviews/checks, and dependency verification unchanged. An open draft PR still cannot unblock a task that requires its code on the base branch.

## Dispatch Ready Work

For each eligible issue admitted by the selected concurrency mode and current capacity, call `create_thread` with a worktree environment off the freshly fetched base and a self-contained initial prompt containing:

- the issue key and URL, the intended outcome, and its acceptance criteria;
- constraints, non-goals, and the verification the child must run;
- concurrency mode, explicit ceilings, owned paths and APIs, current parallel neighbors, and any host-resource or exclusive verification slot it must wait for;
- the Worker Testing Guidance block below, verbatim;
- the branch to work on (`codex/<issue-key>-<slug>`) and the base branch to target;
- this thread's identity and the completion mode: by default, changes verified under the testing policy, branch pushed, draft PR opened against the base branch, and Linear issue updated; with `--automerge`, include the Optional Automerge procedure below and finish only after verified merge into `main` and the issue update;
- report through `send_message_to_thread` with the issue key, PR URL, head SHA, verification evidence, and status (`pr-opened`, `merge-ready`, `merged`, `blocked`, or `failed`); `merge-ready` is a progress event, not completion, and `merged` also includes the merge commit SHA;
- the instruction to stay inside its own worktree and report — not absorb — any extra work it discovers.

Record each child's thread ID against its issue; give each child a title of `<issue-key> <slug>` so the user can find it in the app.

## Schedule Verification and Integration

Keep the ready-work queue separate from the heavy-check queue. On a shared host, grant one exclusive slot for full suites, provider benchmarks, or other checks that contend for shared state or substantial CPU/RAM. Coordinate that slot with other active repository tasks. Independent hosts may run checks concurrently where repository rules permit; serialize final merges to each base branch when merging is authorized.

While a worker holds that slot, other workers may design, edit, review, and run focused checks within the remaining resource budget. Pause only conflicting or resource-heavy operations, not every task. Required gates still run: do not skip checks, expand timeouts, or reuse evidence invalidated by changed code or base. Refresh the base and repeat the required affected checks and reviews before final integration when it advances.

## Optional Automerge

Invoke as `$spawn-orchestrator --automerge <epic>`. Without the flag, stop at verified draft PRs. With it, each worker performs its own PR merge under an orchestrator-owned merge slot for `main`:

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

## Monitor and Advance

- When a child messages `merge-ready`, follow Optional Automerge when enabled; otherwise keep the default draft-PR endpoint. Do not archive or free the worker on `merge-ready`.
- When a child messages completion:
  1. Verify the claim — in default mode the PR exists, targets the base branch, and is a draft; in automerge mode verify the merged PR and commit on `main` as above. Confirm the branch was pushed and Linear reflects reality. A child's "done" is a claim, not evidence.
  2. In default mode, audit the PR's new or changed tests with `$test-audit`; on a policy violation, message the child once with the specific finding and wait for the fix before archiving. In automerge mode, confirm that the pre-merge audit covers the merged head.
  3. Archive the child with `set_thread_archived`.
  4. Release its resource slots and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- If a child goes silent, inspect it before deciding it is blocked; a long-running check is not itself a blocker. For confirmed blocked work, record the issue, dependency, branch/PR, and resume condition; apply Optional Automerge cancellation/ownership rules when enabled, ensure execution has stopped, and preserve recoverable work before releasing its slot. Keep its ownership recorded even while parked. Resume it only after capacity and dependency/overlap checks pass again; do not start a second worker for that issue.
- Repository lifecycle rules control whether a parked thread is retained or archived. Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Guardrails

- Without `--automerge`, stop at draft PRs for human review. With it, workers merge only through the verified procedure above; required human reviews still apply. Never mark issues done on a child's claim alone.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every created thread is archived or reported, and any worktree the app does not clean up itself is reported.

## Report

At meaningful completions or blocker changes, and at the end, return: the epic, base branch, and completion mode; a table of issue → thread → branch → PR → status (with merge commit for `merged`); concurrency mode, active count, and effective capacity constraints; ready-frontier size and undispatched issues with reasons; heavy-check and merge-slot owners; blocked or parked work with resume conditions; and the next dispatch, review, or merge order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$ultragoal` may wrap the whole orchestration when the user wants it to survive interruptions; the goal's verifier is the backlog state plus verified draft PRs or, with `--automerge`, verified merges into `main`, and this skill defines the loop.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
