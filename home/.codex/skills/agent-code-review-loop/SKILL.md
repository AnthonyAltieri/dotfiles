---
name: agent-code-review-loop
description: Use only when explicitly invoked for an expensive multi-agent code review and iterative fix loop. Reviews the current branch, PR, commit range, file list, or requested target for consistency problems, race conditions, missing static type safety, and inconsistent style or naming, then fixes verified issues one at a time with tests, commits, and push.
---

# Agent Code Review Loop

Run this workflow only because the user explicitly invoked it.

## Inputs

- Target: use the user's invocation text or arguments after the skill name, or the current branch diff against the default base branch when omitted.
- Default limit: fix at most 3 issues per invocation unless the user explicitly asks for a different limit.
- Default base: prefer the PR base branch. If there is no PR, infer the repository default branch.

## Preflight

1. Confirm repository state with `git status --short`.
2. Identify the current branch, upstream, base branch, and PR if one exists.
3. If unrelated user changes are present, continue only when the fix can be isolated safely. Never overwrite or stage unrelated changes.
4. If the branch is detached, has no remote, or cannot be pushed safely, run the review and fix steps but stop before commit/push and report the blocker.
5. Identify targeted test, lint, typecheck, and format commands from project docs and config.
6. Define the review target precisely: PR diff, branch diff, commit range, file list, or user-supplied scope.

## Review Fan-Out

Spawn four read-only reviewer subagents in parallel. Give each reviewer the target, base, success criteria, and this instruction: do not edit files, do not run destructive commands, and return only concise findings with evidence.

Review lanes:

1. Consistency reviewer: find inconsistent behavior, contracts, state transitions, data modeling, abstractions, or duplicated-but-diverging implementations.
2. Race/reliability reviewer: find async, concurrent, lifecycle, transaction, locking, cache, retry, cleanup, idempotency, or time-of-check/time-of-use risks.
3. Type-safety reviewer: find places that could be statically typesafe but are not, including `any`, unsafe casts, untyped boundaries, unchecked JSON/env/config inputs, missing discriminated unions, missing exhaustiveness, and avoidable runtime-only invariants.
4. Style/naming reviewer: find concrete inconsistencies in names, file layout, public APIs, test names, and local style that materially hurt maintainability. Avoid subjective nits.

Each subagent must return findings in this shape:

```markdown
## Findings
- Severity: blocker | important | minor
- Category: consistency | race | type-safety | style-naming
- Location: file:line
- Evidence: exact code behavior or command output
- Why it matters: concrete failure, maintenance risk, or invariant gap
- Suggested fix: minimal safe change
- Verification: test/lint/typecheck/manual command that proves the fix
```

Reject findings that lack file references, concrete evidence, or a plausible verification path.

## Synthesis

1. Wait for all reviewers.
2. Deduplicate findings and rank by severity, confidence, user impact, and fix size.
3. Prefer correctness, race, and type-safety issues over style-only findings.
4. Keep style/naming fixes only when they remove real inconsistency; do not churn unrelated files.
5. Pick one issue at a time. Do not batch unrelated fixes into one commit.

## Fix Loop

For each selected issue:

1. Reproduce or pin the defect when useful.
   - Add a focused failing test first when the issue is behavioral and testable.
   - For type-safety issues, prefer typecheck/lint failures or compile-time assertions.
   - For style/naming issues, use existing lint/format checks when available; otherwise document why no test is useful.
2. Implement the minimal correct fix.
3. Run targeted verification.
   - Run the new or existing focused test.
   - Run targeted lint/typecheck/format for touched files when configured.
   - Run broader checks only when the change crosses shared contracts or targeted checks are insufficient.
4. Inspect the diff and ensure it contains only the intended fix.
5. Stage only files and hunks relevant to the selected fix.
6. Commit with a descriptive message that explains the problem, the solution, verification performed, and any important context.
7. Push the branch. If push requires a first upstream and the target branch is clearly safe, set the upstream while pushing. Otherwise stop and report the blocker.

Stop immediately if commit or push is blocked by permissions, network, CI policy, branch protection, or unrelated local changes.

## Re-Review

After each pushed fix, use a fresh reviewer subagent or targeted review pass to verify:

- the chosen finding is resolved,
- no new blocker or important regression was introduced,
- verification evidence matches the claim.

Continue until the max fix limit is reached, no verified important findings remain, or a blocker requires user input.

## Final Report

Return:

- Review target and base.
- Subagents spawned and scope of each.
- Findings fixed, with commits and push target.
- Verification commands and outcomes.
- Remaining findings, grouped by severity, with recommended next invocation scope.
