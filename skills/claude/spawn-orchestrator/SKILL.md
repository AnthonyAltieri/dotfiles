---
name: spawn-orchestrator
description: Use a Claude Code Fable session to orchestrate headless Codex CLI workers, one `codex exec` process per issue, each running gpt-6-sol at xhigh in an isolated worktree with Codex's automatic approval reviewer, or Opus 5.5 Claude subagents when the user asks for Opus workers. End at draft PRs by default; explicit --automerge lets workers merge verified PRs into main. Refill available slots with ready issues as workers finish; use --max to fill the dependency-ready frontier beyond the default worker cap and --min-tests to verify only affected code. Honor explicitly requested fixed waves. Use only when the user explicitly asks to spawn parallel agents over an epic or backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Run the backlog from this Fable session while Codex workers implement it. One issue gets one isolated worktree, one resumable Codex thread, one branch, and one PR: a draft by default, or a verified merge into `main` with `--automerge`. The Fable session schedules ready work, watches workers without interrupting them, verifies outcomes at completion, and never implements an issue itself. Workers run autonomously and in isolation: each receives a complete brief, makes its own routine decisions, and reports exactly once when it reaches a terminal state. The orchestrator intervenes only for user-directed stops or scope changes, a single completion-time correction, a sandbox denial or stall the user must decide, or a genuinely big decision a worker has stopped on.

## Required Tooling

- The `codex` CLI on `PATH`, logged in, version 0.153 or newer. Check with `codex --version`.
- `python3` for the helper script deployed beside this skill at `~/.claude/skills/spawn-orchestrator/scripts/codex_worker.py`. Call it as `python3 <that path> <subcommand>`; the rest of this skill writes it as `codex_worker.py`.

If either is missing, stop and report which setup is missing. Do not substitute ordinary Claude implementation subagents, the Codex Claude plugin, or an MCP bridge to the Codex app. Opus Workers, below, are the one exception, and only when the user asks for them.

## Worker Ownership

The orchestrator owns every worktree and every worker process directly. There is no wrapper agent.

1. Create the worktree with plain git from the fetched base:

   ```bash
   git fetch origin --prune
   git worktree add -b codex/<issue-key>-<slug> .claude/worktrees/<issue-key> origin/<base>
   ```

   If `git check-ignore .claude/worktrees` is silent, add `.claude/worktrees/` to `.git/info/exclude` first so the hub checkout stays clean.
2. Write the brief to a file and launch the worker with the Bash tool in background mode. The helper blocks until the Codex process exits, so the Bash completion notification is the worker's completion signal:

   ```bash
   RUN=~/.cache/spawn-orchestrator/<run-id>/<issue-key>
   python3 codex_worker.py start --run-dir "$RUN" --worktree .claude/worktrees/<issue-key> --brief /path/to/brief.md
   ```

   `start` runs `codex exec --json` with `-m gpt-6-sol`, `model_reasoning_effort=xhigh`, the `--approve-for-me` approval triple, and outbound network enabled. It feeds the brief through stdin, records the thread id from the first event, appends the event stream to `$RUN/events.jsonl`, and writes the worker's final message to `$RUN/last.md`.
3. Record the issue key, run directory, worktree, branch, and thread id in orchestrator state as soon as `$RUN/thread_id` appears.

Invoking this skill is the user's explicit request to spawn workers over the requested backlog. Do not request separate permission per worker. Closing this Claude Code session kills every live worker process; their threads remain resumable from the recorded run directories.

## Opus Workers

When the user asks for Opus subagents or Opus workers, each issue's worker is a background Claude subagent running Opus 5.5 instead of a Codex process. The Codex CLI and the helper are not required in this mode. Everything else in this skill applies unchanged, except for the mechanics below:

- **Launch:** create the worktree as in Worker Ownership, then start the worker with the Agent tool: `model: "opus"`, a `general-purpose` subagent, and the brief as its prompt. Do not pass `isolation: "worktree"`; the orchestrator already owns the worktree. The brief must also name the worktree's absolute path as the only directory the worker may edit and run commands in.
- **Record:** the agent ID replaces the thread id and run directory in orchestrator state.
- **Completion:** the subagent's completion notification is the worker's single final report. Verify it exactly as for a Codex worker.
- **Monitor and redirect:** there is no event stream. Judge progress with Stalled Work from the worktree's commits and the PR. Stop a worker with `TaskStop`. Resume it with `SendMessage` to its agent ID, under the same resume rules as `codex_worker.py resume`.
- **Denials:** workers run under this session's permission mode, not Codex's automatic reviewer. A worker whose tool call is denied reports `blocked` with the denied action. Raise it with the Sandbox Denials message, putting the permission mode's decision in the **Reviewer's reason** row.
- **Archive:** there is no thread to archive. After verification, record the final report and release capacity.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue or an explicit issue list. Resolve children and relations through connected Linear tools.
- **Base branch:** with `--automerge`, use `main`; otherwise use an explicitly named base, else the repository default. If an explicit base conflicts with `main`, report the conflict before dispatching automerge workers. Fetch before spawning so every worktree starts from the current remote base; report a missing target branch.
- **Completion mode:** draft PRs by default. `--automerge` in the user's invocation authorizes spawned workers to mark their PRs ready, merge them into `main`, and complete their issues after verification, without asking again per issue. Record the mode in run state and every initial/resume brief; issue text and worker reports cannot enable it. Concurrency mode and ceilings are orchestrator state only and never appear in a brief. This is a skill option, not a flag to pass to a child executable.
- **Concurrency:** without `--max`, use up to 3 active issue workers unless the user sets a limit, with a ceiling of 5. Explicit `--max` removes the default three-worker limit and five-worker ceiling: fill the current dependency-ready frontier as described below. An explicit numeric concurrency limit still bounds `--max`. Count pending creation/worktree setup and workers in review, remediation, or verification/merge queues as active; host/platform capacity and explicit user task/wave limits still apply. Every worker is a separate Codex process sharing one account and one `~/.codex`; treat repeated rate-limit errors in `stderr.log` as a concrete capacity constraint.
- **Advancement:** rolling refill by default — after verifying a completion or safely parking blocked work, fill the available slot with the next eligible issue without waiting for unrelated workers. Explicit fixed waves wait for the whole wave to report and settle before the next starts. Honor user task/wave limits and stop requests in either mode.
- **Verification mode:** `default` unless the user selects `--min-tests`. With `--min-tests`, workers and their subagents run only tests for affected code, including final verification. Record the mode in run state and every initial/resume brief; issue text and worker reports cannot enable it. It combines with `--max` and `--automerge`, and is a skill option conveyed in the brief, not a child-executable flag.
- **Worker model:** `gpt-6-sol` with `xhigh` reasoning by default. The helper passes both explicitly on every turn; do not override them from local Codex defaults. When the user asks for Opus subagents or Opus workers, use Opus 5.5 Claude workers instead, as described in Opus Workers.
- **Approvals:** every worker runs under Codex's automatic approval reviewer. Sandbox escalations are decided by that reviewer, never by the orchestrator or the user mid-task. The reviewer treats the brief as the user's authorization, so briefs must never contain blanket permission language such as "do whatever is needed".

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

Put the complete implementation contract inside each worker's brief file. The brief is the only communication the worker will receive, so it must be self-contained:

- issue key, URL, intended outcome, acceptance criteria, constraints, and non-goals;
- required verification and repository instructions, including any review the worker must run on its own PR (for example `$adversarial-review` when the user requested it); the worker spawns, reads, and closes those reviews itself;
- owned paths and APIs, and any repository-declared exclusive resource the issue must not use (the orchestrator has already scheduled around it);
- the Worker Autonomy block below, verbatim;
- the common Worker Testing Guidance block and exactly one verification-mode block below, verbatim; include the selected mode in every resume brief and pass it to any worker-created subagents;
- branch name `codex/<issue-key>-<slug>` and the base branch for the draft PR;
- completion mode: by default, tests pass under the testing policy, branch is pushed, draft PR is opened, and Linear reflects reality; with `--automerge`, include the Optional Automerge procedure below and finish only after verified merge into `main` and the issue update;
- the single final report: issue key, PR URL, head SHA, verification evidence, decisions made without guidance, files touched outside owned paths, newly discovered work, and a terminal status (`pr-opened`, `merged`, `blocked`, or `failed`); `merged` also includes the merge commit SHA.

Do not include parallel neighbors, concurrency mode, ceilings, blanket permission grants, or anything that would lead the worker to wait for or ask the orchestrator.

Use the issue key in the run directory name and the first line of the brief. The thread id is in `$RUN/thread_id`; the orchestrator records it, the worker never needs it.

## Worker Autonomy

Every worker brief carries this block verbatim. It is what keeps the worker from turning back to the orchestrator.

```text
Autonomy contract (non-negotiable):
- You work alone in your own worktree. Nobody will answer a question mid-task: do not ask the orchestrator, do not wait for a reply, do not pause for approval that this brief already grants.
- Make routine judgment calls yourself and record each one in the PR description. Stop and report `blocked` only when every plausible assumption would be unsafe or would make the work useless.
- Sandbox escalations are decided by the automatic approval reviewer. If it denies an action, do not work around it or retry it: finish the work the denial does not affect, then report `blocked` with the denied command and the reviewer's reason.
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
2. Fetch current `main`. If it moved since your last verification, update the branch under repository rules and rerun the affected checks under the selected verification mode. Mark the PR ready and obtain the required reviews and checks for the final head against the current base.
3. Merge through the repository's supported PR mechanism and merge strategy with an expected-head guard. If head or base changed since step 2, return to step 2. Honor branch protection, required reviews, and merge queues. Never use an administrative bypass, force-push `main`, or push directly to `main`.
4. A scheduled or queued merge is still pending: wait until the provider confirms `merged`. Then fetch `main`, verify the merge commit is reachable from it, update the Linear issue, and report `merged` with the merge commit SHA.
5. Remediate in-scope check or review failures yourself before retrying. Unresolved failures, missing required approval, conflicts, or unavailable merge permissions or tools end the task as `blocked` with the PR URL and a resume condition. Do not retry the same blocker repeatedly and do not ask the orchestrator to intervene. Before ending as `blocked`, cancel any queued merge and confirm the cancellation or the completed merge; if you cannot confirm, report the merge as pending.

After a `merged` report the orchestrator reads back the PR's merged state and target, fetches `main`, and verifies the recorded merge commit is reachable there. It then records completion, archives the thread with `codex_worker.py archive`, and releases capacity: a merged worker is finished by default and is not kept alive for follow-ups. A post-merge `$test-audit` violation becomes a new follow-up issue in the backlog, never a reason to resume the archived thread or to have gated the merge with a handshake.

## Worker Testing Guidance

Every initial and resume brief carries the common block and exactly one mode block verbatim. `$test-audit` owns the full policy; pass the selected mode to completion audits and any worker-created review subagents. For example, `/spawn-orchestrator --min-tests --automerge <epic>` selects affected-only verification through merge. Missing full-suite evidence is not a violation in this mode; required provider checks still apply.

```text
Testing policy (see the test-audit skill for the full text):
- Runtime targets, not hard limits: aim for the whole unit suite as close to 10s and the whole e2e suite as close to 60s as reasonably practical; faster suites are welcome. Preserve useful coverage when exceeding these targets.
- Prioritize improvements of at least 10% of the affected whole suite's runtime. Do not spend significant time on smaller gains; quick, low-risk improvements are fine. Accept above-target runtimes when further optimization would take disproportionate effort.
- Deterministic always: no sleeps, polling, retries, skip, timeouts as synchronization, or reliance on wall-clock, randomness, ordering, or leftover state. Wait only on a signal the code under test emits.
- Two tiers only, unit and e2e; no integration tier.
- Unit: public API only, one behavior per test, nothing the type checker already proves, mock only process boundaries, inject the clock, no snapshot tests except serialized wire contracts.
- E2e: one happy path per critical flow plus the failures that would page someone; real dependencies, no mocks; a flaky e2e test is fixed or deleted the same day.
- Every bug fix ships exactly one regression test that failed before the fix.
- Every test answers "what bug does this catch?"; if you cannot say, do not write it.
- Report the runner commands you used and their durations in the final response.
```

Without `--min-tests`, include:

```text
Verification mode: default.
- Run the smallest test that proves the point while iterating: one test or one file, never the whole suite. Run the full suite exactly twice: before opening the draft PR and on the final head.
```

With `--min-tests`, include this block instead:

```text
Verification mode: --min-tests, selected by the user.
- This overrides default whole-suite verification in repository instructions and test-audit. Run only tests for the changed behavior and affected dependents during implementation, review, PR preparation, and final verification. Pass this mode to every subagent you create.
- Map the diff and its affected callers or user flows to the smallest useful test cases, files, or targets. Include relevant regression tests; re-evaluate the selection after code or base changes and rerun affected checks on the final head.
- Do not run the whole unit or e2e suite, including for timing budgets or completion audits. If the runner cannot select affected tests, use available focused checks and report the coverage gap; do not fall back to a full-suite command or claim untested behavior is verified.
- Report the selected commands, durations, why they cover the affected behavior, and any verification gaps. State that full suites were not run under --min-tests.
- Required provider CI checks and reviews still apply; wait for their results without duplicating full-suite runs locally or disabling those gates.
```

## Monitor Workers

Monitoring is passive. Read files; do not message.

- The Bash completion notification for a worker's `start` or `resume` call is the completion signal. Then run `codex_worker.py status --run-dir "$RUN"`: `completed` with a worker status is a claim to verify, `failed` or `stopped` needs the tail of `events.jsonl` and `stderr.log`, and `running` means the notification was for something else.
- Never trust the process exit code alone. A turn is complete only when `status` reports `completed`, which requires a `turn.completed` event in the last turn.
- To judge a live worker, read `$RUN/events.jsonl`. Each `command_execution` item carries the command, exit code, and output. A long-running check is not itself a blocker. While reading, judge progress against Stalled Work below and check `codex_worker.py denials --run-dir "$RUN"` for Sandbox Denials.
- Never message a worker to ask for status, progress, or an ETA, and never answer a question it should decide itself.
- There is no live steer. To redirect a worker: `codex_worker.py stop`, then `codex_worker.py resume --run-dir "$RUN" --prompt /path/to/followup.md`. Resume only for: a user-directed stop or scope change; the single completion-time correction described below; the user's answer to a Sandbox Denials or Stalled Work question; or a genuinely big decision the worker has stopped on, such as target branch, destructive action, or a scope conflict with another issue. If a worker stops on anything smaller, resume it once with the instruction to decide itself and record the decision in the PR description.
- `resume` exits with code 3 and stops the process if Codex opened a different thread than the recorded one. Treat that as a failed resume, not a new worker.
- On completion, verify the pushed branch, target base, and Linear state, plus the draft PR in default mode or the merged PR and commit on `main` in automerge mode. Do not re-run or re-check reviews the worker spawned itself; its report lists how each finding was closed.
- In default mode, audit the PR's new or changed tests with `$test-audit`, resume the worker once with the complete list of violations, and wait for the fix; do not iterate finding by finding. Archive the thread after those checks pass or after a terminal failure is fully recorded.
- In automerge mode, archive the thread as soon as the merge into `main` is verified. Anything found afterwards is a new issue, not a resume.
- After verified completion, remove the worktree with `git worktree remove` only when the branch is pushed, release resource slots, and refill eligible capacity immediately in rolling mode; explicit fixed waves retain their barrier.
- For confirmed blocked work, record the issue, dependency, branch/PR, run directory, and resume condition. Confirm any queued merge is cancelled or complete, stop the live turn if any, and verify recoverable work is preserved before releasing capacity. Keep the worktree and thread.
- Keep parked ownership recorded. Reacquire capacity and recheck dependencies/overlap before resuming the same issue's thread; never create a duplicate worker or resume into a removed worktree.
- Pending administrative updates or approvals on one issue do not block unrelated authorized work once its resources are released; preserve the pending action rather than bypassing it.
- Stop dispatching when the user's limit is reached or no issue is eligible. Continue monitoring active workers; end with a truthful report when the requested work is settled or no further progress is possible without user input or an external change.

## Sandbox Denials

A worker asked to cross a sandbox boundary and the automatic reviewer said no. The worker cannot appeal and must not work around it, so the decision is the user's. Detect denials with `codex_worker.py denials --run-dir "$RUN"`, which pairs each declined command with the boundary it hit, the worker's justification, and the reviewer's reason. Report each denial once, as soon as it is seen, in this exact shape:

```markdown
**Auto-review denied an escalation: <issue-key>** (worker <n> of <active>, others unaffected)

| | |
|---|---|
| **Blocked action** | `<command as the worker ran it>` |
| **Boundary** | <Filesystem or Network>. <one sentence on what the sandbox blocked> |
| **Worker's reason** | "<the worker's justification, one sentence>" |
| **Reviewer's reason** | "<the Reason line from the reviewer, one sentence>" |
| **Worker now** | <stopped and reported blocked | continued without it | still running> after <n> attempt(s) |
| **Branch state** | <commits pushed or not, PR open or not> |
| **Thread** | `<thread id>` in `<run dir>` |

Reply with a number:
1. **Skip it (recommended).** Resume the worker with instructions to finish without it and note it in the PR as follow-up.
2. **Redirect.** Tell me the alternative and I resume the worker with it.
3. **Allow once.** I run the exact command myself in the worktree, then resume the worker as if it had succeeded.
4. **Stop the worker.** Keep the branch and thread for later.
```

Rules for the message and what follows:

- Seven rows, one sentence per cell, quotes trimmed to the one sentence that carries the decision. The full reviewer text stays in the run directory.
- Mark exactly one option as recommended. Skip is the default recommendation; recommend Allow once only when the command is plainly in scope for the issue and touches nothing outside the worktree that the user did not name. Never recommend retrying.
- Allow once means the orchestrator runs the command itself in the worker's worktree. Never widen a worker's sandbox, pass a bypass flag, or resume with "you are approved" text: the reviewer would read that text as authorization for the rest of the run.
- If the worker is still running when the denial is seen, leave it running. If it stopped with `blocked`, do not resume it until the user answers. Unrelated workers keep going.
- Wait for the answer, act on it once, then return to passive monitoring. Include the open question in every report until it is answered. A second denial on the same issue gets a new message with the new evidence.

## Stalled Work

Autonomy is not a license to spin. Detecting a stall is the orchestrator's job, and resolving one is the user's decision, not another resume. Judge progress from `events.jsonl`, never by asking the worker.

Treat an issue as stalled when the events show any of these without new evidence in between:

- a test-fix loop: the same suite or check fails on three or more consecutive runs and the fixes between them do not change the failure;
- the same blocker reported or retried more than twice (a merge conflict, a failing required check, a missing approval, a flaky dependency);
- repeated full-suite runs, rebases, or reruns with no new commit, finding, or decision between them;
- a wall-clock or turn count that is far past what the issue's size warrants, with the events still circling the same files.

When an issue stalls:

1. Stop intervening on it. Do not resume it with another hint, and do not let it keep burning turns: `codex_worker.py stop`, keep the worktree, branch, and thread, and record the issue as `stalled` with its PR, head, and the loop you observed. Unrelated workers keep going.
2. Ask the user how to proceed. Put the question in one message with: the issue key and PR, what the loop looks like in two or three plain sentences, what has already been tried, and the concrete options. Offer two to four options, each with what it costs and what it gives up, and lead with your recommendation marked as such. Typical options: give the worker a specific new direction you spell out; narrow or split the issue; park it and refill the slot; accept a smaller deliverable such as a draft PR without the failing gate, when the testing policy allows it; or stop the whole run. Never present "keep trying" as the recommendation.
3. Wait for the answer. Do not resume, park, or archive the stalled issue on your own while the question is open. Include the open question in every report.
4. Act on the answer once, then return to passive monitoring. If the same issue stalls again after that, ask again with the new evidence; do not silently apply the previous answer.

Reading events to judge progress is not a status ping, and these questions to the user are not approval gates: they are the two places the orchestrator asks for direction, because the alternative is an unbounded loop or a silent workaround the user did not sign up for.

## Guardrails

- One issue per thread, one thread per worktree, one run directory per issue. Never reuse a worker thread for another issue.
- No mid-task coordination. The orchestrator never grants slots, permissions, or approvals to a running worker, and a worker never waits on the orchestrator or another worker. Everything a worker needs is in its brief.
- No silent loops and no silent workarounds. A stalled issue or a sandbox denial goes to the user with options and a recommendation, never to another round of resumes.
- Never pass `--dangerously-bypass-approvals-and-sandbox`, `danger-full-access`, or extra writable roots to a worker. The helper's approval triple is the only sandbox configuration workers run with.
- Without `--automerge`, stop at draft PRs for human review. With it, workers merge only through the verified procedure above; required human reviews still apply. Never mark issues done on a worker's claim alone.
- Keep Linear mutations within `$linear-claim-work`; do not restructure the epic.
- Leave nothing dangling: every turn is complete or stopped, every thread is archived or reported with its run directory, and every worktree with unpushed changes is identified.

## Report

At meaningful completions or blocker changes, and at the end, return the epic, base branch, completion mode, and verification mode plus a table of issue → thread → branch → PR → status (with merge commit for `merged`). Include concurrency mode, active count, effective capacity constraints, ready-frontier size and undispatched issues with reasons, blocked or parked work with resume conditions and run directories, any open Sandbox Denials or Stalled Work question, and the next dispatch or review order. For explicit fixed waves, also report the wave boundary. Keep routine updates concise.

## Composition

- `$linear-claim-work` owns claim, duplicate, and ownership-conflict gates.
- `$adversarial-review` may gate an individual worker's PR when requested; the worker runs it inside its own thread against its own PR and closes the findings before reporting. The orchestrator never runs it on a worker's behalf.
- `$test-audit` owns the testing policy; the Worker Testing Guidance block is its condensed form and the completion audit applies it to each PR.
