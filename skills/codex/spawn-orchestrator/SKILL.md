---
name: spawn-orchestrator
description: Orchestrate waves of separate Codex app threads (tasks) that each implement one unblocked issue from an epic or work list in an isolated git worktree, open a PR to the base branch, message this thread on completion, and get archived. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel Codex sessions or waves over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one separate Codex app thread per unblocked issue, each in its own worktree, each ending in a PR and a completion message back to this thread. This thread stays the orchestrator — it plans waves, creates and monitors child threads, and never implements issues itself.

## Children Are App Threads

The children of this workflow are first-class Codex app threads (the app calls them tasks or sessions), created and driven with the app's thread tools:

- `create_thread` (`codex_app__create_thread`) — creates the child, with `environment.type = "worktree"` and the base branch as the starting state, and the child's brief as the initial prompt.
- `send_message_to_thread` — sends follow-up guidance to a child; children use the same tool to report back to this thread.
- `read_thread`, `list_threads` — inspect a silent child.
- `set_thread_archived` — archives a finished child.

Invoking this skill **is** the user's explicit request to create separate tasks, which is the condition `create_thread` requires. Do not ask again per child.

Subagents are fine in general — this thread may use them for backlog triage or reviewing a finished child's diff, and a child may use them inside its own worktree — but they are never the unit of orchestration. Every issue in a wave gets its own app thread created with `create_thread`, not a subagent (`spawn_agent`, "delegate to agents", custom agents under `.codex/agents/`): subagents run inside the parent thread's workspace and lifetime, so parallel implementation conflicts, the work does not surface as a separate reviewable task in the app, and they cannot be messaged or archived as threads. If the thread tools are unavailable in this context (find them through tool search first), stop and report that — never substitute subagents or headless `codex exec` for the child threads.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue (URL or key) or an explicit issue list. Resolve children and relations through the connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every child worktree starts from the current remote base.
- **Wave size:** 3 unless the user sets one; never exceed 5. The binding constraint is the user's review bandwidth, not compute.
- **Advancement:** discrete waves by default — start the next wave only after every child in the current wave has reported and been archived. Use rolling refill (create one child per completed child) only when the user asks for it.

## Plan the Backlog

1. Resolve the epic's child issues and their relations.
2. An issue is eligible only when it is not blocked: no open blocking relation, not in a terminal state, and it passes the ownership and existing-work gates. Apply `$linear-claim-work` per issue to claim it before spawning; an issue that gate pauses on is reported, not spawned.
3. Partition eligible issues into waves with disjoint file ownership: no two concurrent children may own overlapping files or subsystems. Defer overlapping issues to later waves even when unblocked — merge conflicts cost more than parallelism saves.
4. Re-evaluate blocked and deferred issues after every completed wave; landed PRs may unblock them.

## Spawn a Wave

For each issue in the wave, call `create_thread` with a worktree environment off the fetched base and a self-contained initial prompt containing:

- the issue key and URL, the intended outcome, and its acceptance criteria;
- constraints, non-goals, and the verification the child must run;
- the Worker Testing Guidance block below, verbatim;
- the branch to work on (`codex/<issue-key>-<slug>`) and the base branch to target;
- this thread's identity, and the done-when: changes verified under the testing policy, branch pushed, draft PR opened against the base branch, Linear issue updated, and a completion message sent to this thread with `send_message_to_thread` containing the issue key, PR URL, and status (`pr-opened`, `blocked`, or `failed`);
- the instruction to stay inside its own worktree and report — not absorb — any extra work it discovers.

Record each child's thread ID against its issue; give each child a title of `<issue-key> <slug>` so the user can find it in the app.

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
- If a child goes silent past a reasonable time budget, `read_thread` it; message it once with focused guidance if the fix is obvious, otherwise mark the issue blocked with the evidence, archive the child, and free the slot.
- When the wave is fully reported and archived, re-run backlog planning and start the next wave if any issue is eligible. Stop when the backlog is drained, everything remaining is blocked, or the user's wave limit is reached.

## Guardrails

- Never merge PRs and never mark issues done on a child's claim alone — human review of each PR is the gate this workflow feeds, not a step it performs.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every created thread is archived or reported, and any worktree the app does not clean up itself is reported.

## Report

After each wave and at the end, return: the epic and base branch; a table of issue → thread → branch → PR → status; issues deferred for overlap and issues blocked with evidence; threads archived; and the recommended next action (review order for open PRs, or the next wave's plan).

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$ultragoal` may wrap the whole orchestration when the user wants it to survive interruptions; the goal's verifier is the backlog state plus open PRs, and this skill defines the loop.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
