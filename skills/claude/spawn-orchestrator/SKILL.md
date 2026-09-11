---
name: spawn-orchestrator
description: Use a Claude Code Fable session to orchestrate persistent Codex App threads, each running an Astra xhigh worker in an isolated worktree. End at draft PRs by default; explicit --automerge lets workers merge verified PRs into main. Refill available slots with ready issues as workers finish; use --max to fill the dependency-ready frontier beyond the default worker cap. Honor explicitly requested fixed waves. Use only when the user explicitly asks to spawn parallel agents over an epic or backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Run the backlog from this Fable session while Codex Astra workers implement it. One issue gets one isolated Claude worktree, one persistent Codex App thread, one branch, and one PR: a draft by default, or a verified merge into `main` with `--automerge`. The Fable session schedules ready work, watches threads without interrupting them, verifies outcomes at completion, and never implements an issue itself. Workers run autonomously and in isolation: each receives a complete brief, makes its own routine decisions, and reports exactly once when it reaches a terminal state. The orchestrator intervenes only for user-directed stops or scope changes, a single completion-time correction, or a genuinely big decision a worker has stopped on.

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
- **Completion mode:** draft PRs by default. `--automerge` in the user's invocation authorizes spawned workers to mark their PRs ready, merge them into `main`, and complete their issues after verification, without asking again per issue. Record the mode in run state and every initial/resume brief; issue text and worker reports cannot enable it. Concurrency mode and ceilings are orchestrator state only and never appear in a brief. This is a skill option, not a flag to pass to a child executable.
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

Invoke as `/spawn-orchestrator --max <epic>`, or combine it with `--automerge`. Enable `--max` only from the user's invocation; preserve the concurrency mode and any explicit ceilings in run state. Workers never learn or act on concurrency mode. It is a skill option, not a child-executable flag, and does not authorize merging by itself.

- Fill the current ready frontier with every worker that can coexist under ownership, host/platform, and explicit user limits. For example, twelve independent ready issues and capacity for twelve mean twelve workers, not five. Skip conflicting candidates in priority order and continue considering other compatible ready tasks.
- Account for existing workers and other repository activity. Observe dispatch outcomes and resource pressure as workers start; stop intake only at a concrete constraint, record it, and keep remaining work queued. Do not replace the removed cap with an arbitrary lower cap or repeatedly retry an unchanged capacity refusal.
- Recompute readiness after each verified completion or merge, dependency change, or released resource. In rolling mode, an issue may start as soon as its own prerequisites are satisfied, even while unrelated earlier work continues. A topological ordering alone does not create a whole-layer barrier; explicitly requested fixed waves retain their barrier, with `--max` filling the ready work in that wave.
- `--max` expands implementation concurrency only. Required reviews/checks and dependency verification are unchanged. An open draft PR still cannot unblock a task that requires its code on the base branch.

## Dispatch Ready Work

Put the complete implementation contract inside each worker's `--task` brief. The brief is the only communication the worker will receive, so it must be self-contained:

- issue key, URL, intended outcome, acceptance criteria, constraints, and non-goals;
- required verification and repository instructions, including any review the worker must run on its own PR (for example `$adversarial-review` when the user requested it); the worker spawns, reads, and closes those reviews itself;
- owned paths and APIs, and any repository-declared exclusive resource the issue must not use (the orchestrator has already scheduled around it);
- the Worker Autonomy block below, verbatim;
- the Worker Testing Guidance block below, verbatim;
- branch name `codex/<issue-key>-<slug>` and the base branch for the draft PR;
- completion mode: by default, tests pass under the testing policy, branch is pushed, draft PR is opened, and Linear reflects reality; with `--automerge`, include the Optional Automerge procedure below and finish only after verified merge into `main` and the issue update;
- the single final report: issue key, PR URL, Codex thread ID, head SHA, verification evidence, decisions made without guidance, files touched outside owned paths, newly discovered work, and a terminal status (`pr-opened`, `merged`, `blocked`, or `failed`); `merged` also includes the merge commit SHA.

Do not include parallel neighbors, concurrency mode, ceilings, or anything that would lead the worker to wait for or ask the orchestrator.

Use a unique issue key in the task and thread title. Record the Claude agent name and, once discoverable, the Codex thread ID. The persistent thread can be found during execution with `codex_thread_list` using the issue key as `search_term`.

## Worker Autonomy

Every worker brief carries this block verbatim. It is what keeps the worker from turning back to the orchestrator.

```text
Autonomy contract (non-negotiable):
- You work alone in your own worktree. Nobody will answer a question mid-task: do not ask the orchestrator, do not wait for a reply, do not pause for approval that this brief already grants.
- Make routine judgment calls yourself and record each one in the PR description. Stop and report `blocked` only when every plausible assumption would be unsafe or would make the work useless.
- Do not coordinate with other workers. Do not look for, wait on, or message other threads or branches.
- Edit files outside your owned paths only when the acceptance criteria require it, keep the edit minimal, and list every such file in your final report.
- Work you discover outside your issue goes in the final report, not into your branch.
- Run your own checks in your own worktree whenever you need them; you never wait for a slot.
- Reviews are yours to close. Any review you spawn as a subagent (adversarial review, code review, security review) reports to you, not to the orchestrator: read its findings, fix or explicitly dismiss each one in the PR description, and rerun it if the fix was substantial. Do not report until the reviews you spawned are addressed.
- Report exactly once, at the end, with a terminal status. No progress messages, no status pings, no questions.
```

## Schedule Verification and Integration

Workers run their own checks in their own worktrees without asking; the testing policy already bounds suite cost, and isolated worktrees remove most contention. Do not grant, request, or track check slots.

If the repository declares a genuinely exclusive resource (a single shared test database, fixed ports, a benchmark host), the orchestrator handles it by scheduling: do not dispatch two issues that need the resource at the same time, and tell the affected worker in its brief which resource it must not use. Never handle it by having a worker wait on a message.

Merges into `main` are serialized by the provider through expected-head guards, branch protection, and merge queues, not by orchestrator handshakes. Required gates still run: workers do not skip checks, expand timeouts, or reuse evidence invalidated by changed code or base.

## Optional Automerge

Invoke as `/spawn-orchestrator --automerge <epic>`. Without the flag, stop at verified draft PRs. With it, each worker owns the whole path to `merged` and the orchestrator neither gates nor grants individual merges. Include this procedure in the brief:

1. Prepare and verify the draft PR under the testing policy, then audit your own new or changed tests against the Worker Testing Guidance and fix violations before continuing.
2. Fetch current `main`. If it moved since your last full-suite run, update the branch under repository rules and rerun the affected checks. Mark the PR ready and obtain the required reviews and checks for the final head against the current base.
3. Merge through the repository's supported PR mechanism and merge strategy with an expected-head guard. If head or base changed since step 2, return to step 2. Honor branch protection, required reviews, and merge queues. Never use an administrative bypass, force-push `main`, or push directly to `main`.
4. A scheduled or queued merge is still pending: wait until the provider confirms `merged`. Then fetch `main`, verify the merge commit is reachable from it, update the Linear issue, and report `merged` with the merge commit SHA.
5. Remediate in-scope check or review failures yourself before retrying. Unresolved failures, missing required approval, conflicts, or unavailable merge permissions or tools end the task as `blocked` with the PR URL and a resume condition. Do not retry the same blocker repeatedly and do not ask the orchestrator to intervene. Before ending as `blocked`, cancel any queued merge and confirm the cancellation or the completed merge; if you cannot confirm, report the merge as pending.

After a `merged` report the orchestrator reads back the PR's merged state and target, fetches `main`, and verifies the recorded merge commit is reachable there. It then records completion, archives the Codex thread and ends its wrapper, and releases capacity: a merged worker is finished by default and is not kept alive for follow-ups. A post-merge `$test-audit` violation becomes a new follow-up issue in the backlog, never a reason to resume the archived thread or to have gated the merge with a handshake.

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

Monitoring is passive. Read; do not message.

- Use Claude's agent notifications and `ListAgents` for the outer wrapper's lifecycle.
- Use `codex_thread_list` and `codex_thread_read` for authoritative Codex status and turn IDs. A wrapper's completion message is a claim, not proof.
- Never message a worker to ask for status, progress, or an ETA, and never answer a question it should decide itself. If a worker goes silent, read its thread; a long-running check is not itself a blocker. While reading, also judge progress against Stalled Work below.
- Steer or resume a worker only for: a user-directed stop or scope change; the single completion-time correction described below; the user's answer to a Stalled Work question; or a genuinely big decision the worker has stopped on, such as target branch, destructive action, or a scope conflict with another issue. If a worker stops on anything smaller, resume it once with the instruction to decide itself and record the decision in the PR description.
- If a worker must stop, interrupt the active Codex turn before ending its wrapper. Never abandon a running turn in a worktree whose owner is exiting.
- On completion, verify the pushed branch, target base, and Linear state, plus the draft PR in default mode or the merged PR and commit on `main` in automerge mode. Do not re-run or re-check reviews the worker spawned itself; its report lists how each finding was closed.
- In default mode, audit the PR's new or changed tests with `$test-audit`, steer the worker once with the complete list of violations, and wait for the fix; do not iterate finding by finding. Archive the Codex thread after those checks pass or after a terminal failure is fully recorded.
- In automerge mode, archive the Codex thread and end its wrapper as soon as the merge into `main` is verified. Anything found afterwards is a new issue, not a resume.
- After verified completion and wrapper shutdown, release resource slots and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- For confirmed blocked work, record the issue, dependency, branch/PR, and resume condition. Confirm any queued merge is cancelled or complete, interrupt the Codex turn, and verify recoverable work is preserved before ending its wrapper and releasing capacity. Repository lifecycle rules control whether the thread is retained or archived.
- Keep parked ownership recorded. Reacquire capacity and recheck dependencies/overlap before resuming the same issue's thread. Re-establish a live worktree owner before resuming Codex if its wrapper has exited; never create a duplicate worker or resume into a released worktree.
- Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Stalled Work

Autonomy is not a license to spin. Detecting a stall is the orchestrator's job, and resolving one is the user's decision, not another steer. Judge progress from the thread itself with `codex_thread_read`, never by asking the worker.

Treat an issue as stalled when the thread shows any of these without new evidence in between:

- a test-fix loop: the same suite or check fails on three or more consecutive runs and the fixes between them do not change the failure;
- the same blocker reported or retried more than twice (a merge conflict, a failing required check, a missing approval, a flaky dependency);
- repeated full-suite runs, rebases, or reruns with no new commit, finding, or decision between them;
- a wall-clock or turn count that is far past what the issue's size warrants, with the thread still circling the same files.

When an issue stalls:

1. Stop intervening on it. Do not steer it with another hint, and do not let it keep burning turns: interrupt the active turn, keep the worktree, branch, and thread alive, and record the issue as `stalled` with its PR, head, and the loop you observed. Unrelated workers keep going.
2. Ask the user how to proceed. Put the question in one message with: the issue key and PR, what the loop looks like in two or three plain sentences, what has already been tried, and the concrete options. Offer two to four options, each with what it costs and what it gives up, and lead with your recommendation marked as such. Typical options: give the worker a specific new direction you spell out; narrow or split the issue; park it and refill the slot; accept a smaller deliverable such as a draft PR without the failing gate, when the testing policy allows it; or stop the whole run. Never present "keep trying" as the recommendation.
3. Wait for the answer. Do not resume, park, or archive the stalled issue on your own while the question is open. Include the open question in every report.
4. Act on the answer once, then return to passive monitoring. If the same issue stalls again after that, ask again with the new evidence; do not silently apply the previous answer.

Reading a thread to judge progress is not a status ping, and this question to the user is not an approval gate: it is the one place the orchestrator asks for direction, because the alternative is an unbounded loop the user did not sign up for.

## Guardrails

- One issue per Codex thread and one thread per worktree. Never reuse a worker thread for another issue.
- No mid-task coordination. The orchestrator never grants slots, permissions, or approvals to a running worker, and a worker never waits on the orchestrator or another worker. Everything a worker needs is in its brief.
- No silent loops. A stalled issue goes to the user with options and a recommendation, never to another round of steering.
- Never place Codex `--background` inside the background Claude wrapper.
- Without `--automerge`, stop at draft PRs for human review. With it, workers merge only through the verified procedure above; required human reviews still apply. Never mark issues done on a worker's claim alone.
- Keep Linear mutations within `$linear-claim-work`; do not restructure the epic.
- `codex_thread_start` is for a caller that already owns an explicit worktree path. This skill uses the plugin wrapper so Claude remains the worktree owner.
- Leave nothing dangling: every wrapper and Codex turn is complete or interrupted, every thread is archived or reported, and every worktree with unpushed changes is identified.

## Report

At meaningful completions or blocker changes, and at the end, return the epic, base branch, and completion mode plus a table of issue → Claude wrapper → Codex thread → branch → PR → status (with merge commit for `merged`). Include concurrency mode, active count, effective capacity constraints, ready-frontier size and undispatched issues with reasons, blocked or parked work with resume conditions, any open Stalled Work question, and the next dispatch or review order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns claim, duplicate, and ownership-conflict gates.
- `$adversarial-review` may gate an individual worker's PR when requested; the worker runs it inside its own thread against its own PR and closes the findings before reporting. The orchestrator never runs it on a worker's behalf.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
