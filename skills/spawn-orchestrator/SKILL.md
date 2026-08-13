---
name: spawn-orchestrator
description: Orchestrate waves of spawned Codex sessions that each implement one unblocked issue from an epic or work list in an isolated git worktree or cloud task, open a PR to the base branch, report completion, and get archived. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel Codex sessions or waves over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one spawned Codex session per unblocked issue, each in its own isolated workspace, each ending in a PR and a completion report. This session stays the orchestrator — it plans waves, launches and monitors children, and never implements issues itself.

Do not use subagents for the implementation work: subagents share this session's workspace and sandbox, so parallel write-heavy work conflicts. Reserve subagents for read-heavy phases such as backlog triage or reviewing a finished child's diff. Spawn implementation children as separate sessions with `codex exec` in dedicated worktrees, or as cloud tasks.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue (URL or key) or an explicit issue list. Resolve children and relations through the connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before creating any worktree so every child starts from the current remote base.
- **Execution target:** local worktrees by default; Codex cloud tasks (`codex cloud exec --env <ENV>`) when the user asks for cloud or local capacity is exhausted.
- **Wave size:** 3 unless the user sets one; never exceed 5. The binding constraint is the user's review bandwidth and local resources, not compute.
- **Advancement:** discrete waves by default — launch the next wave only after every child in the current wave has reported and been archived. Use rolling refill (start one child per completed child) only when the user asks for it.

## Plan the Backlog

1. Resolve the epic's child issues and their relations.
2. An issue is eligible only when it is not blocked: no open blocking relation, not in a terminal state, and it passes the ownership and existing-work gates. Apply `$linear-claim-work` per issue to claim it before spawning; an issue that gate pauses on is reported, not spawned.
3. Partition eligible issues into waves with disjoint file ownership: no two concurrent children may own overlapping files or subsystems. Defer overlapping issues to later waves even when unblocked — merge conflicts cost more than parallelism saves.
4. Re-evaluate blocked and deferred issues after every completed wave; landed PRs may unblock them.

## Spawn a Wave (Local Worktrees)

For each issue in the wave:

1. Create an isolated worktree and branch off the fetched base:

   ```bash
   git worktree add "../<repo>-<issue-key>" -b "codex/<issue-key>-<slug>" "origin/<base>"
   ```

   Run the project's dependency install in the worktree when the child will need to build or test.

2. Compose a self-contained brief: the issue key and URL, the intended outcome and acceptance criteria, constraints and non-goals, the verification the child must run, and this done-when: changes verified, branch pushed, draft PR opened against the base branch, Linear issue updated, completion record written.

3. Launch the child headless in the background:

   ```bash
   codex exec --cd "../<repo>-<issue-key>" --sandbox workspace-write \
     --ask-for-approval never -o "../<repo>-<issue-key>/.orchestrator/result.md" \
     "<brief>"
   ```

4. Completion signaling: there is no built-in inter-session bus, so the brief must instruct the child to finish by appending one JSON line — `{"issue": "<key>", "session_id": "<id>", "pr_url": "<url>", "status": "pr-opened|blocked|failed"}` — to the orchestrator's status file (a path this session owns), with the `-o` last-message file as the fallback signal.

For cloud execution, replace steps 1–4 with `codex cloud exec --env <ENV> "<brief>"` per issue and poll `codex cloud list --json`; cloud tasks bring their own isolation and PR flow.

## Monitor and Advance

- Poll the status file and `-o` result files (or `codex cloud list --json`) between other work; do not busy-wait.
- When a child reports:
  1. Verify the claim — the PR exists, targets the base branch, and is a draft; the branch pushed; the Linear issue reflects reality. A child's "done" is a claim, not evidence.
  2. Archive the child's session: `codex archive <session-id>`.
  3. Remove the worktree only after its branch is pushed: `git worktree remove <path>`.
- Stalled or looping children: after a reasonable time budget, inspect the child's result file and session; resume it once with focused guidance (`codex exec resume <session-id>`) if the fix is obvious, otherwise stop it, mark the issue blocked with the evidence, and free the slot.
- When the wave is fully reported and archived, re-run backlog planning and launch the next wave if any issue is eligible. Stop when the backlog is drained, everything remaining is blocked, or the user's wave limit is reached.

## Guardrails

- Never merge PRs and never mark issues done on a child's claim alone — human review of each PR is the gate this workflow feeds, not a step it performs.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Children run `--ask-for-approval never`, so their sandbox must stay `workspace-write` inside their own worktree; never grant a child broader access to compensate for a failure.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every spawned session is archived or reported, every worktree removed or reported, and the status file location disclosed.

## Report

After each wave and at the end, return: the epic and base branch; a table of issue → session → branch → PR → status; issues deferred for overlap and issues blocked with evidence; sessions archived; worktrees removed or still live; and the recommended next action (review order for open PRs, or the next wave's plan).

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$ultragoal` may wrap the whole orchestration when the user wants it to survive interruptions; the goal's verifier is the backlog state plus open PRs, and this skill defines the loop.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
