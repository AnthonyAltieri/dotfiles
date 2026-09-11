---
name: spawn-orchestrator
description: Orchestrate a backlog through separate Codex app threads in isolated worktrees, refilling available slots with ready issues as workers finish. Each issue ends in a draft PR and a verified report. Honor explicitly requested fixed waves. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel Codex sessions over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one separate Codex app thread per unblocked issue, each in its own worktree, each ending in a PR and a completion message back to this thread. This thread stays the orchestrator — it schedules ready work, creates and monitors child threads, and never implements issues itself.

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
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every child worktree starts from the current remote base.
- **Concurrency:** up to 3 active issue workers unless the user sets a lower or higher limit; never exceed 5. Include workers in review, remediation, or a verification queue. Reduce intake when host resources or the user's review backlog cannot support it.
- **Advancement:** rolling refill by default — after verifying a completion or safely parking blocked work, fill the available slot with the next eligible issue without waiting for unrelated workers. Explicit fixed waves wait for the whole wave to report and settle before the next starts. Honor user task/wave limits and stop requests in either mode.

## Plan the Backlog

1. Resolve the requested issues and their blocking relations. Track each worker's owned paths and APIs, stage, resource needs, and blockers, including other active repository tasks such as a test-suite audit.
2. An eligible issue is non-terminal and has no open blocking relation. Refresh dependencies and existing-work ownership before every dispatch, then claim through `$linear-claim-work`. An open PR or a worker's completion message does not satisfy a dependency that requires merged code; verify the required result on the base branch. Resume an existing issue's worker instead of creating a duplicate.
3. Choose ready issues with disjoint owned files and no conflicting API decisions. Sharing a crate or subsystem alone does not require serialization. An independently scoped design document may proceed alongside implementation; its dependent code still waits for the reviewed decision. Do not invent additional work outside the requested backlog to fill slots.
4. Prefer work that removes a blocker on the shortest path to the user's requested outcome. Start ready design decisions early when they unlock several later changes; use spare capacity for independent fixes. Readiness alone is not a reason to postpone critical design behind peripheral cleanup.
5. Re-evaluate the queue after a verified completion, merge, newly discovered blocker, or ownership change. If capacity is idle, name the concrete dependency, overlap, resource, or user-limit reason.

## Dispatch Ready Work

For each eligible issue that fits the concurrency limit, call `create_thread` with a worktree environment off the freshly fetched base and a self-contained initial prompt containing:

- the issue key and URL, the intended outcome, and its acceptance criteria;
- constraints, non-goals, and the verification the child must run;
- owned paths and APIs, current parallel neighbors, and any host-resource or exclusive verification slot it must wait for;
- the Worker Testing Guidance block below, verbatim;
- the branch to work on (`codex/<issue-key>-<slug>`) and the base branch to target;
- this thread's identity, and the done-when: changes verified under the testing policy, branch pushed, draft PR opened against the base branch, Linear issue updated, and a completion message sent to this thread with `send_message_to_thread` containing the issue key, PR URL, and status (`pr-opened`, `blocked`, or `failed`);
- the instruction to stay inside its own worktree and report — not absorb — any extra work it discovers.

Record each child's thread ID against its issue; give each child a title of `<issue-key> <slug>` so the user can find it in the app.

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

## Monitor and Advance

- When a child messages completion:
  1. Verify the claim — the PR exists, targets the base branch, and is a draft; the branch pushed; the Linear issue reflects reality. A child's "done" is a claim, not evidence.
  2. Audit the PR's new or changed tests with `$test-audit`; on a policy violation, message the child once with the specific finding and wait for the fix before archiving.
  3. Archive the child with `set_thread_archived`.
  4. Release its resource slots and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- If a child goes silent, inspect it before deciding it is blocked; a long-running check is not itself a blocker. For confirmed blocked work, record the issue, dependency, branch/PR, and resume condition; ensure execution has stopped and preserve recoverable work before releasing its slot. Keep its ownership recorded even while parked. Resume it only after capacity and dependency/overlap checks pass again; do not start a second worker for that issue.
- Repository lifecycle rules control whether a parked thread is retained or archived. Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Guardrails

- Never merge PRs and never mark issues done on a child's claim alone — human review of each PR is the gate this workflow feeds, not a step it performs.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every created thread is archived or reported, and any worktree the app does not clean up itself is reported.

## Report

At meaningful completions or blocker changes, and at the end, return: the epic and base branch; a table of issue → thread → branch → PR → status; active versus available slots; heavy-check owner; ready work waiting and why; blocked or parked work with resume conditions; and the next dispatch or review order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$ultragoal` may wrap the whole orchestration when the user wants it to survive interruptions; the goal's verifier is the backlog state plus open PRs, and this skill defines the loop.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
