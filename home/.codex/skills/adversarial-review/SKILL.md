---
name: adversarial-review
description: Run an independent falsification gate with two or more fresh-context, read-only reviewers that try to find concrete bugs, regressions, unmet requirements, unsafe assumptions, and verification gaps. Use only when the user explicitly invokes `$adversarial-review` or asks for an adversarial review of a plan, artifact, diff, or completed task, including when paired with `$ultragoal`.
---

# Adversarial Review

Run this workflow only because the user explicitly requested it. Treat review as an attempt to disprove a candidate, not as proof that it is correct. Keep normal tests, static checks, CI, domain verifiers, and required human approval as separate evidence.

## Operating Modes

- **Integrated gate:** when invoked as part of doing a task, review the candidate before declaring the task complete. Let the task implementer or a separate fixer remediate accepted findings.
- **Candidate review:** when given existing work, review and report without changing it unless the user also requested fixes.
- **Preflight review:** when the target is an expensive plan, specification, migration, or decision, review that artifact before execution.
- **Re-review:** after any change to reviewed content, review the new candidate in fresh contexts. Never reuse a verdict from an older snapshot.

Default to an integrated final-candidate gate when the user asks to do a task and adversarially review it. Add a preflight review only when the user requests one or when an early defect would make later work unusually costly or irreversible.

## Conditional References

Read each matching reference completely before assembling review packets or reviewers. These references specialize this workflow; they do not weaken its snapshot, independence, read-only, evidence, or re-review requirements.

| Situation | Required reference |
| --- | --- |
| The candidate includes application code, tests, configuration that changes runtime behavior, or a code-focused plan | [Code review lenses](references/code-review-lenses.md) |
| The user explicitly pairs `$adversarial-review` with `$ultragoal` | [Ultragoal composition](references/ultragoal-composition.md) |

## Keep Roles Separate

- The orchestrator defines the target, freezes the candidate, creates neutral review packets, waits for every reviewer, and validates the returned findings.
- The implementer or fixer changes the candidate and runs its normal verification. The orchestrator may also be the implementer or fixer, but cannot supply an independent reviewer verdict or waive an unresolved material claim.
- Use at least two reviewer subagents. Reviewers only inspect and report; they never edit, fix, commit, push, or operate goal state.
- Do not let the implementer masquerade as an independent reviewer. Do not substitute the orchestrator's self-review for a fresh-context reviewer.
- Do not show one reviewer another reviewer's output before both have returned.
- Discard and replace any report from a reviewer that mutates the candidate, shared external state, Git state, or goal lifecycle.

## Freeze the Candidate

Before spawning reviewers:

1. State the objective, acceptance criteria, constraints, and non-goals.
2. Identify the exact candidate and baseline. For Git work, record the base, task-owned paths, and task-owned untracked files. For other work, record every reviewed artifact and relevant baseline input.
3. Bind the snapshot identifier to the complete reviewed content. Use an immutable commit, staged tree, or artifact version, or compute a deterministic digest manifest over every reviewed tracked and untracked artifact, acceptance-contract input, and behaviorally relevant baseline. A label, branch name, dirty status, or path list alone is not a snapshot. If complete content binding is impossible, return `inconclusive`.
4. Separate unrelated dirty work from the review scope. If that cannot be done reliably, return `inconclusive` rather than review the wrong target.
5. Pause candidate mutations until all reviewers have returned. All subagents share the live filesystem even when their conversation contexts are isolated.

Do not create a commit merely to manufacture a snapshot unless the parent workflow already authorizes that commit.

## Build a Neutral Review Packet

Give each reviewer the same minimum sufficient evidence:

- the objective and observable acceptance criteria;
- the snapshot identifier and exact diff, artifact, or path set;
- the canonical baseline, specification, invariants, and repository instructions needed to judge it;
- the task's constraints and non-goals;
- raw verifier commands and results when available;
- permission boundaries for inspection and diagnostic commands.

Exclude:

- implementer reasoning, chain of thought, self-assessment, or claims that the work is correct;
- worklog narrative that is not itself a canonical requirement;
- suspected bugs, expected answers, proposed conclusions, and other reviewers' findings.

Interpret “review only the diff” as “review only neutral evidence.” A reviewer may need the surrounding implementation, original artifact, or canonical specification to detect omissions and semantic drift.

## Run Independent Reviews

Spawn at least two reviewers with isolated conversation contexts, normally with `fork_turns="none"`. Run them in parallel when capacity permits; otherwise run them sequentially without sharing outputs.

Give both reviewers the full falsification mandate: assume the candidate contains defects and exhaustively seek concrete reasons it fails the stated objective. Use different secondary lenses to reduce correlated blind spots without narrowing either reviewer's scope. For code candidates, select lenses from [Code review lenses](references/code-review-lenses.md). For other targets, default to:

1. **Local semantics:** edge inputs, state transitions, lifetimes, concurrency, cleanup, error paths, and misleadingly plausible implementation details.
2. **System boundaries:** omitted requirements, compatibility, integration, security, performance, operational behavior, and ways the verifier can be bypassed or weakened.

Require reviewers to remain read-only. Permit only safe inspection and bounded diagnostic commands that do not mutate the candidate or shared external state. Have reviewers propose a reproduction command for the orchestrator when running it could change files, install dependencies, consume substantial resources, or interfere with the other review.

Use a prompt shaped like:

```text
Act as one of multiple independent adversarial reviewers. Assume the candidate is wrong.
Try to falsify it against the supplied objective, acceptance criteria, canonical references,
and snapshot. Find concrete failure mechanisms, not praise or stylistic preferences.

Do not edit files, implement fixes, mutate Git, install dependencies, or inspect implementer
reasoning. Do not call goal-lifecycle tools. Return the required verdict and finding schema,
including an explicit coverage summary and any limitations.
```

## Require Evidence-Backed Findings

Each reviewer must return:

```markdown
## Adversarial Review
- Snapshot: <stable identifier>
- Verdict: material-findings | clean | inconclusive

### Findings
- ID: <stable reviewer-local ID>
- Severity: critical | major | minor
- Confidence: high | medium | low
- Location: <file:line, artifact section, or exact locus>
- Claim: <specific defect or unmet requirement>
- Failure scenario: <realistic input, sequence, or counterexample>
- Evidence: <source facts, command output, or proposed reproduction>
- Verification gap: <why current checks do not catch it>
- Repair direction: <optional; concise and non-implementing>

### Coverage
- Inspected: <areas and invariants examined>
- Limitations: <missing context, commands not run, or uncertainty>
```

Use verdicts precisely:

- `material-findings`: at least one credible critical or major finding exists.
- `clean`: no material finding was found within the stated scope; this is not a correctness guarantee.
- `inconclusive`: the snapshot, context, access, or coverage was insufficient. This never passes the gate.

Reject praise, generic concern, subjective style preference, and claims without a concrete failure mechanism. Treat minor findings as non-blocking unless they combine into a material acceptance or maintenance risk.

## Synthesize and Validate

Wait for every reviewer before changing the candidate. Then:

1. Confirm that every verdict names the same current snapshot.
2. Recompute or recheck the snapshot identifier against the live candidate. Discard all verdicts if the candidate or acceptance contract drifted during review.
3. Deduplicate findings while preserving independent corroboration.
4. Check each finding against source, requirements, and focused reproduction evidence when feasible.
5. Record a disposition: `accepted`, `rejected-with-evidence`, or `requires-user-decision`.
6. Rank accepted findings by severity, user impact, confidence, and repair scope.
7. Do not blindly apply reviewer suggestions. Reviewer assertions are leads; evidence decides.
8. Do not expand task authority to address a finding. Surface fixes that require a new product choice, irreversible action, public write, or unrelated scope.

If reviewers disagree, resolve the claim through source evidence or reproduction. A clearly documented rejection does not block the gate; an unresolved material claim makes the result inconclusive.

When the orchestrator also implemented or fixed the candidate, reject a critical or major finding only with direct reproduction evidence or an unambiguous canonical requirement. If the disposition depends on subjective interpretation, use a fresh adjudicator when available; otherwise record `requires-user-decision` and keep the gate inconclusive.

After triage and any diagnostic verification, recompute the complete content-bound snapshot immediately before deciding the gate state. If it differs from the reviewed snapshot, discard every verdict and restart review against the new candidate.

Set the consolidated gate state independently from the raw reviewer verdicts:

- `failed`: at least one critical or major finding is accepted.
- `inconclusive`: fewer than two valid fresh-context reports completed, any material claim remains unresolved, any report is inconclusive, or the snapshot cannot be confirmed unchanged.
- `passed`: at least two conclusive independent reports cover the same unchanged snapshot, no critical or major finding is accepted or unresolved, and the candidate's normal verifiers pass on that snapshot.

## Remediate and Re-review

For an integrated gate or explicit fix request:

1. Let the implementer or a separate fixer apply accepted findings. Reviewers remain read-only.
2. Run focused verification for each fix, then rerun the candidate's primary and supporting verifiers.
3. Freeze and identify the updated candidate.
4. Treat every change to reviewed content, the acceptance contract, or a behaviorally relevant baseline as making all earlier verdicts stale.
5. Spawn fresh-context reviewers against the full current candidate, not merely the last patch, and repeat until no unresolved material finding remains.

If the same defect class recurs across two review rounds, stop patching symptoms and re-plan the implementation, acceptance contract, or verifier. Do not impose a round limit that silently converts known defects into success. If safe progress cannot continue, report the current review as inconclusive with the smallest next action.

For review-only requests, stop after synthesis and return the ledger without modifying the candidate.

## Handle Degraded Conditions Honestly

- If fewer than two reviewer contexts are immediately available, wait or run reviewers sequentially. If two fresh contexts cannot be obtained, return `inconclusive`.
- If subagent isolation is unavailable, return `inconclusive`; never silently substitute self-review.
- If the candidate changes during review, discard the stale verdicts and start again from a frozen snapshot.
- If essential acceptance criteria or canonical references are missing, infer only when the choice cannot materially change the result; otherwise ask for the missing decision.
- Keep security review, architecture review, CI diagnosis, fuzzing, sanitizers, and human review as complementary workflows when their specialized evidence matters.

## Final Report

Return:

- objective, scope, baseline, and current snapshot identifier;
- reviewer count, context-isolation method, and secondary lenses;
- each finding and its evidence-backed disposition;
- fixes made by the implementer or fixer, if authorized;
- primary and supporting verifier commands and outcomes;
- final gate state: `passed`, `failed`, or `inconclusive`;
- remaining limitations and risks.

Report `passed` only when the current snapshot satisfies the clean-gate conditions. Never summarize an inconclusive or stale review as approval.
