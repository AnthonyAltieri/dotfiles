---
name: spawn-orchestrator
description: Orchestrate waves of background Claude subagents that each implement one unblocked issue from an epic or work list in an isolated git worktree, open a PR to the base branch, and report back to this session. Use only when the user explicitly invokes spawn-orchestrator or asks to spawn parallel agents or waves over a backlog; do not use for single-task delegation or read-only fan-out.
---

# Spawn Orchestrator

Work a backlog in parallel: one background subagent per unblocked issue, each in its own worktree, each ending in a PR and a completion report back to this session. This session stays the orchestrator — it plans waves, spawns and monitors children, and never implements issues itself.

## Children Are Worktree Subagents

The children of this workflow are background subagents created with the `Agent` tool:

- Spawn with `isolation: "worktree"` so each child works on an isolated copy of the repo, and put the child's full brief in `prompt`. Children run in the background; their completion arrives as a task notification.
- `SendMessage` — send follow-up guidance to a child by its agent name; the child's final report and any interim messages come back the same way.
- `ListAgents` — enumerate live children when checking on a silent one.

Invoking this skill **is** the user's explicit request to spawn parallel agents; do not ask again per child.

One issue per child, always. Never batch multiple issues into one subagent, and never implement an issue inline in the orchestrator's own context — inline work serializes the wave, bloats this session's context, and produces no separately reviewable unit. Never fabricate or predict a pending child's result; wait for its notification. If the `Agent` tool or worktree isolation is unavailable in this context, stop and report that — do not substitute sequential in-context implementation.

## Inputs and Defaults

- **Work source:** a Linear epic/parent issue (URL or key) or an explicit issue list. Resolve children and relations through the connected Linear tools.
- **Base branch:** an explicitly named base, else the repository default. Fetch before spawning so every child worktree starts from the current remote base.
- **Wave size:** 3 unless the user sets one; never exceed 5. The binding constraint is the user's review bandwidth, not compute.
- **Advancement:** discrete waves by default — start the next wave only after every child in the current wave has reported. Use rolling refill (spawn one child per completed child) only when the user asks for it.

## Plan the Backlog

1. Resolve the epic's child issues and their relations.
2. An issue is eligible only when it is not blocked: no open blocking relation, not in a terminal state, and it passes the ownership and existing-work gates. Apply `$linear-claim-work` per issue to claim it before spawning; an issue that gate pauses on is reported, not spawned.
3. Partition eligible issues into waves with disjoint file ownership: no two concurrent children may own overlapping files or subsystems. Defer overlapping issues to later waves even when unblocked — merge conflicts cost more than parallelism saves.
4. Re-evaluate blocked and deferred issues after every completed wave; landed PRs may unblock them.

## Spawn a Wave

For each issue in the wave, call `Agent` with `isolation: "worktree"` and a self-contained brief containing:

- the issue key and URL, the intended outcome, and its acceptance criteria;
- constraints, non-goals, and the verification the child must run;
- the branch to create (`claude/<issue-key>-<slug>`) and the base branch to target;
- the done-when: changes verified with the repo's gates, branch pushed, draft PR opened against the base branch, Linear issue updated, and a final report containing the issue key, PR URL, and status (`pr-opened`, `blocked`, or `failed`);
- the instruction to stay inside its own worktree and report — not absorb — any extra work it discovers.

Use a short `description` of `<issue-key> <slug>` so the child is identifiable in `ListAgents` and notifications, and record each child's agent name against its issue.

## Monitor and Advance

- When a child's completion notification arrives:
  1. Verify the claim — the PR exists, targets the base branch, and is a draft; the branch pushed; the Linear issue reflects reality. A child's "done" is a claim, not evidence; check with `gh pr view` and the Linear tools, or delegate the diff review to a fresh subagent.
  2. Record the outcome and free the slot. There is nothing to archive — a reported child is finished, and its PR is the durable artifact.
- If a child goes silent past a reasonable time budget, check it with `ListAgents` and message it once with focused guidance via `SendMessage` if the fix is obvious; otherwise mark the issue blocked with the evidence and free the slot.
- When the wave is fully reported, re-run backlog planning and start the next wave if any issue is eligible. Stop when the backlog is drained, everything remaining is blocked, or the user's wave limit is reached.

## Guardrails

- Never merge PRs and never mark issues done on a child's claim alone — human review of each PR is the gate this workflow feeds, not a step it performs.
- One issue per child; a child that discovers extra work reports it for triage instead of expanding scope.
- Keep Linear mutations minimal and within `$linear-claim-work` rules; the orchestrator does not restructure the epic.
- Leave nothing dangling: at the end, every spawned child is reported or accounted for, and any worktree left with unpushed changes is reported (clean worktrees are removed automatically).

## Report

After each wave and at the end, return: the epic and base branch; a table of issue → child agent → branch → PR → status; issues deferred for overlap and issues blocked with evidence; and the recommended next action (review order for open PRs, or the next wave's plan).

## Composition

- `$linear-claim-work` owns the claim, duplicate, and ownership-conflict gates per issue.
- `$adversarial-review` may gate an individual child's PR when the user requests it; run it against that child's diff, not the whole wave.
