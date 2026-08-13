---
name: spawn-orchestrator
description: Orchestrate waves of spawned Codex app sessions that each implement one unblocked issue from an epic or work list in an isolated git worktree, open a PR to the base branch, message this session on completion, and get archived. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel Codex sessions or waves over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one spawned Codex session per unblocked issue, each in its own worktree, each ending in a PR and a completion message back to this session. This session stays the orchestrator — it plans waves, starts and monitors child sessions, and never implements issues itself.

Children are app sessions: start each one directly ("start a session"), and have it message this session when done. Do not use subagents for the implementation work — subagents share this session's workspace, so parallel write-heavy work conflicts. Reserve subagents for read-heavy phases such as backlog triage or reviewing a finished child's diff.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue (URL or key) or an explicit issue list. Resolve children and relations through the connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every child starts from the current remote base.
- **Wave size:** 3 unless the user sets one; never exceed 5. The binding constraint is the user's review bandwidth, not compute.
- **Advancement:** discrete waves by default — start the next wave only after every child in the current wave has reported and been archived. Use rolling refill (start one child per completed child) only when the user asks for it.

## Plan the Backlog

1. Resolve the epic's child issues and their relations.
2. An issue is eligible only when it is not blocked: no open blocking relation, not in a terminal state, and it passes the ownership and existing-work gates. Apply `$linear-claim-work` per issue to claim it before spawning; an issue that gate pauses on is reported, not spawned.
3. Partition eligible issues into waves with disjoint file ownership: no two concurrent children may own overlapping files or subsystems. Defer overlapping issues to later waves even when unblocked — merge conflicts cost more than parallelism saves.
4. Re-evaluate blocked and deferred issues after every completed wave; landed PRs may unblock them.

## Spawn a Wave

For each issue in the wave, start a new session in its own worktree off the fetched base, with a self-contained brief containing:

- the issue key and URL, the intended outcome, and its acceptance criteria;
- constraints, non-goals, and the verification the child must run;
- the branch to work on (`codex/<issue-key>-<slug>`) and the base branch to target;
- this done-when: changes verified, branch pushed, draft PR opened against the base branch, Linear issue updated, and a completion message sent to this session containing the issue key, PR URL, and status (`pr-opened`, `blocked`, or `failed`);
- the instruction to stay inside its own worktree and report — not absorb — any extra work it discovers.

## Monitor and Advance

- When a child messages completion:
  1. Verify the claim — the PR exists, targets the base branch, and is a draft; the branch pushed; the Linear issue reflects reality. A child's "done" is a claim, not evidence.
  2. Archive the child session.
- If a child goes silent past a reasonable time budget, check its session directly; message it once with focused guidance if the fix is obvious, otherwise stop it, mark the issue blocked with the evidence, and free the slot.
- When the wave is fully reported and archived, re-run backlog planning and start the next wave if any issue is eligible. Stop when the backlog is drained, everything remaining is blocked, or the user's wave limit is reached.

## Guardrails

- Never merge PRs and never mark issues done on a child's claim alone — human review of each PR is the gate this workflow feeds, not a step it performs.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every spawned session is archived or reported, and any worktree the app does not clean up itself is reported.

## Report

After each wave and at the end, return: the epic and base branch; a table of issue → session → branch → PR → status; issues deferred for overlap and issues blocked with evidence; sessions archived; and the recommended next action (review order for open PRs, or the next wave's plan).

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$ultragoal` may wrap the whole orchestration when the user wants it to survive interruptions; the goal's verifier is the backlog state plus open PRs, and this skill defines the loop.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
