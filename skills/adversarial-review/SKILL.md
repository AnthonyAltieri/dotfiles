---
name: adversarial-review
description: Run an independent falsification gate with two or more fresh-context, read-only reviewers that try to find concrete bugs, regressions, unmet requirements, unsafe assumptions, and verification gaps. Use only when the user explicitly invokes adversarial-review or asks for an adversarial review of a plan, artifact, diff, or completed task, including when paired with ultragoal.
disable-model-invocation: true
---

# Adversarial Review

Run this workflow only because the user explicitly requested it. Review is an attempt to disprove a candidate, never proof that it is correct. Normal tests, static checks, CI, domain verifiers, and required human approval remain separate evidence.

## Operating Modes

- **Integrated gate** (default when the user asks to do a task and adversarially review it): review the final candidate before declaring the task complete.
- **Candidate review:** review existing work and report without changing it unless the user also requested fixes.
- **Preflight review:** review an expensive plan, specification, migration, or decision before execution. Add this only when requested or when an early defect would be unusually costly or irreversible.

Any change to reviewed content, the acceptance contract, or a behaviorally relevant baseline makes earlier verdicts stale. Re-review always runs in fresh contexts against the full current candidate, not merely the last patch.

## Conditional References

Read each matching reference completely; references specialize this workflow without weakening its invariants.

| Situation | Required reference |
| --- | --- |
| The candidate includes application code, tests, configuration that changes runtime behavior, or a code-focused plan | [Code review lenses](references/code-review-lenses.md) |
| The user explicitly pairs this review with ultragoal | [Ultragoal composition](references/ultragoal-composition.md) |

## Roles

- The **orchestrator** defines the target, freezes the candidate, builds neutral review packets, waits for every reviewer, and validates the returned findings. It may also be the implementer or fixer, but can never supply a reviewer verdict or waive an unresolved material claim.
- **Reviewers** — at least two, each in an isolated fresh context with no shared conversation history — only inspect and report. They never edit, fix, commit, push, or operate goal or task state, and never see another reviewer's output before both have returned. Discard and replace the report of any reviewer that mutates the candidate, shared external state, or Git state.
- The **implementer or fixer** changes the candidate and runs its normal verification.

## Freeze the Candidate

Before spawning reviewers:

1. State the objective, acceptance criteria, constraints, and non-goals.
2. Identify the exact candidate and baseline. For Git work, record the base, task-owned paths, and task-owned untracked files.
3. Bind a snapshot identifier to the complete reviewed content: an immutable commit, staged tree, artifact version, or deterministic digest manifest over every reviewed artifact, acceptance-contract input, and behaviorally relevant baseline. A label, branch name, dirty status, or path list alone is not a snapshot.
4. Separate unrelated dirty work from the review scope.
5. Pause candidate mutations until all reviewers have returned — subagents share the live filesystem even when their conversation contexts are isolated.

If complete content binding or scope separation is impossible, return `inconclusive` rather than review the wrong target. Do not create a commit merely to manufacture a snapshot unless the parent workflow already authorizes that commit.

## Neutral Review Packet

Give each reviewer the same minimum sufficient evidence:

- the objective and observable acceptance criteria;
- the snapshot identifier and exact diff, artifact, or path set;
- the canonical baseline, specification, invariants, and repository instructions needed to judge it;
- the task's constraints and non-goals;
- raw verifier commands and results when available;
- permission boundaries for inspection and diagnostic commands.

Exclude implementer reasoning, self-assessment, worklog narrative, suspected bugs, expected answers, and other reviewers' findings. Interpret "review only the diff" as "review only neutral evidence" — a reviewer may still need the surrounding implementation, original artifact, or canonical specification to detect omissions and semantic drift.

## Run Reviews

Run reviewers in parallel when capacity permits; otherwise sequentially without sharing outputs. Give every reviewer the full falsification mandate — assume the candidate contains defects and exhaustively seek concrete reasons it fails the stated objective — plus a distinct secondary lens to reduce correlated blind spots without narrowing scope. For code candidates, select lenses from [Code review lenses](references/code-review-lenses.md). For other targets, default to:

1. **Local semantics:** edge inputs, state transitions, lifetimes, concurrency, cleanup, error paths, and misleadingly plausible implementation details.
2. **System boundaries:** omitted requirements, compatibility, integration, security, performance, operational behavior, and ways the verifier can be bypassed or weakened.

Permit only safe inspection and bounded diagnostic commands. A reproduction that could change files, install dependencies, consume substantial resources, or interfere with the other review is proposed to the orchestrator, not run.

Use a prompt shaped like:

```text
Act as one of multiple independent adversarial reviewers. Assume the candidate is wrong.
Try to falsify it against the supplied objective, acceptance criteria, canonical references,
and snapshot. Find concrete failure mechanisms, not praise or stylistic preferences.

Do not edit files, implement fixes, mutate Git, install dependencies, or inspect implementer
reasoning. Do not call goal- or task-lifecycle tools. Return the required verdict and finding
schema, including an explicit coverage summary and any limitations.
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

## Synthesize and Gate

After every reviewer has returned:

1. Confirm every verdict names the same snapshot, then recheck that identifier against the live candidate. Drift discards all verdicts and restarts review against the new candidate.
2. Deduplicate findings while preserving independent corroboration.
3. Check each finding against source, requirements, and focused reproduction evidence when feasible; record `accepted`, `rejected-with-evidence`, or `requires-user-decision`. Reviewer assertions are leads; evidence decides.
4. When the orchestrator also implemented or fixed the candidate, reject a critical or major finding only with direct reproduction evidence or an unambiguous canonical requirement. If the disposition depends on subjective interpretation, use a fresh adjudicator when available; otherwise record `requires-user-decision`.
5. Do not expand task authority to address a finding. Surface fixes that require a new product choice, irreversible action, public write, or unrelated scope.

A clearly documented rejection does not block the gate; an unresolved material claim does. Set the consolidated gate state:

- `failed`: at least one critical or major finding is accepted.
- `inconclusive`: fewer than two valid fresh-context reports completed, any material claim remains unresolved, any report is inconclusive, or the snapshot cannot be confirmed unchanged.
- `passed`: at least two conclusive independent reports cover the same unchanged snapshot, no critical or major finding is accepted or unresolved, and the candidate's normal verifiers pass on that snapshot.

## Remediate and Re-review

For an integrated gate or explicit fix request:

1. Let the implementer or fixer apply accepted findings, run focused verification for each fix, then rerun the candidate's primary and supporting verifiers.
2. Freeze the updated candidate and spawn fresh-context reviewers against it; repeat until no unresolved material finding remains.
3. If the same defect class recurs across two review rounds, stop patching symptoms and re-plan the implementation, acceptance contract, or verifier. Do not impose a round limit that silently converts known defects into success. If safe progress cannot continue, report the review as inconclusive with the smallest next action.

For review-only requests, stop after synthesis and return the ledger without modifying the candidate.

## Degraded Conditions

- If two fresh reviewer contexts cannot be obtained, or subagent isolation is unavailable, return `inconclusive`; never silently substitute self-review.
- If essential acceptance criteria or canonical references are missing, infer only when the choice cannot materially change the result; otherwise ask for the missing decision.
- Keep security review, architecture review, CI diagnosis, fuzzing, sanitizers, and human review as complementary workflows when their specialized evidence matters.

## Final Report

Return: objective, scope, baseline, and current snapshot identifier; reviewer count, isolation method, and secondary lenses; each finding and its evidence-backed disposition; fixes made by the implementer or fixer, if authorized; verifier commands and outcomes; the final gate state (`passed`, `failed`, or `inconclusive`); and remaining limitations and risks.

Report `passed` only when the current snapshot satisfies the clean-gate conditions. Never summarize an inconclusive or stale review as approval.
