---
name: adversarial-review
description: Run an independent falsification gate with fresh-context, read-only reviewers that try to find concrete failures of the stated acceptance criteria under the stated threat model. Use only when the user explicitly invokes adversarial-review or asks for an adversarial review of a plan, artifact, diff, or completed task, including when paired with ultragoal.
disable-model-invocation: true
---

# Adversarial Review

Run this workflow only because the user explicitly requested it. Review is an attempt to disprove a candidate against a fixed contract; it is never proof of correctness, and it is never a license to expand the contract. Normal tests, static checks, CI, and required human approval remain separate evidence.

## Operating Modes

- **Integrated gate** (default when the user asks to do a task and adversarially review it): review the final candidate before declaring the task complete.
- **Candidate review:** review existing work and report without changing it unless the user also requested fixes.
- **Preflight review:** review a plan, specification, or migration before execution. Use only when requested or when an early defect would be unusually costly or irreversible.

## Roles

- The **orchestrator** fixes the review contract, freezes the candidate, builds neutral packets, waits for every reviewer, and dispositions findings. It may also be the implementer or fixer, but never supplies a reviewer verdict or waives an unresolved material claim.
- **Reviewers** run in isolated fresh contexts with no shared conversation history. They only inspect and report: never edit, fix, commit, push, run expensive suites, or operate goal/task state, and never see another reviewer's output before both have returned. Discard the report of any reviewer that mutates the candidate, shared state, or Git.
- The **verification agent** (may be the orchestrator) is the only party that runs the full affected lint/type/test/build gate. Reviewers run only bounded, targeted diagnostics.
- The **fixer** changes the candidate and runs targeted verification for each fix.

## Review Contract

Findings are judged against a contract, not against everything a reviewer can imagine. Before any review, write down:

- **Objective and acceptance criteria**, each mapped to the test or check that demonstrates it.
- **Threat model:** which inputs, actors, files, stores, and peers are trusted versus untrusted, and which failure classes are in scope (for example: hostile HTTP input in scope; hostile local user and TOCTOU on a process-owned directory out of scope).
- **Non-goals** and constraints.
- **Invariants** the change must preserve, named by abstraction family (descriptor ownership, lease clock, schema authority, claim token, and so on).

Take these from the ticket when it has them. When it does not, derive a provisional contract from the ticket, repository conventions, and existing code, state it in the packet as provisional, and let disputes about it become `requires-user-decision` rather than silently expanding scope. A reviewer who wants a stronger threat model reports that as a hardening suggestion, not as a defect.

## Stage 0: Cheap Pass

Run the expensive gate only on a candidate that has already survived a cheap one.

1. The implementer completes the `$programming` review pass against the contract's invariants and runs targeted lint, typecheck, and tests for the touched files.
2. The orchestrator spawns **one** fresh-context smoke reviewer with the neutral packet and the diff. The smoke reviewer reports only critical or major failures of the contract, runs no suites, and is bounded to a short pass.
3. Fix accepted smoke findings with targeted tests, then repeat step 2 at most once more.

The smoke reviewer never counts toward the gate. If a smoke pass still yields material findings after two iterations, treat that as the redesign trigger below before entering the full gate.

## Freeze the Candidate

Before spawning gate reviewers:

1. Bind a snapshot identifier to the complete reviewed content: an immutable commit, staged tree, artifact version, or deterministic digest manifest over every reviewed artifact and contract input. A branch name, label, or path list is not a snapshot.
2. Record the base, task-owned paths, and task-owned untracked files; separate unrelated dirty work from scope.
3. Have the verification agent run the full affected gate once on this snapshot and record raw results in the packet.
4. Pause candidate mutations until every reviewer has returned — subagents share the live filesystem.

If content binding or scope separation is impossible, return `inconclusive` rather than review the wrong target. Do not create a commit merely to manufacture a snapshot unless the parent workflow already authorizes it.

## Neutral Review Packet

Give each reviewer the same minimum sufficient evidence: the review contract; the snapshot identifier and exact diff, artifact, or path set; the canonical baseline, specification, and repository instructions needed to judge it; raw verifier commands and results; and permission boundaries for inspection commands.

Exclude implementer reasoning, self-assessment, worklog narrative, suspected bugs, expected answers, and other reviewers' findings. "Review only the diff" means "review only neutral evidence" — a reviewer may still read surrounding implementation to detect omissions and semantic drift.

## Run Reviews

Default to two gate reviewers; use three only when the candidate spans several trust boundaries or the user asks. Run them in parallel when capacity permits, otherwise sequentially without sharing outputs. Give each the full falsification mandate plus a distinct secondary lens (for code, from [Code review lenses](references/code-review-lenses.md); otherwise local semantics versus system boundaries).

Permit only safe inspection and bounded diagnostics. A reproduction that could change files, install dependencies, or consume substantial resources is proposed to the orchestrator, not run.

Prompt shape:

```text
Act as one of several independent adversarial reviewers. Assume the candidate is wrong.
Try to falsify it against the supplied acceptance criteria and invariants, under the supplied
threat model and non-goals. Find concrete failure mechanisms with a reproduction, not praise,
style, or generic concern. Anything that fails only under a stronger threat model than the one
supplied is a hardening suggestion, reported separately and never as a defect.

Do not edit files, fix, mutate Git, install dependencies, run full test suites, or read
implementer reasoning. Return the required verdict and finding schema with a coverage summary.
```

## Require Reproducible Findings

Each reviewer returns:

```markdown
## Adversarial Review
- Snapshot: <stable identifier>
- Verdict: material-findings | clean | inconclusive

### Findings
- ID: <reviewer-local ID>
- Severity: critical | major | minor
- Confidence: high | medium | low
- Location: <file:line, artifact section, or exact locus>
- Contract basis: <acceptance criterion or invariant violated; threat-model assumption relied on>
- Family: <abstraction family, e.g. descriptor ownership, lease clock, schema authority>
- Claim: <specific defect or unmet requirement>
- Reproduction: <failing test sketch, exact command, or concrete input sequence>
- Verification gap: <why current checks do not catch it>
- Repair direction: <optional; concise and non-implementing>

### Hardening suggestions
- <out-of-threat-model observations, one line each; non-blocking>

### Coverage
- Inspected: <areas and invariants examined>
- Limitations: <missing context, commands not run, uncertainty>
```

Verdicts: `material-findings` means at least one credible critical or major finding; `clean` means none was found within scope (not a correctness guarantee); `inconclusive` means snapshot, context, access, or coverage was insufficient and never passes the gate.

A critical or major finding without a contract basis and a concrete reproduction is not material. Reject praise, style preference, generic concern, and threat-model expansion dressed as a defect.

## Synthesize and Gate

After every reviewer has returned:

1. Confirm every verdict names the same snapshot and recheck it against the live candidate. Drift discards all verdicts.
2. Deduplicate findings, preserving independent corroboration.
3. Disposition each finding with evidence: `accepted`, `rejected-with-evidence`, `out-of-scope-hardening` (real, but outside the threat model or non-goals — record it as follow-up work, do not remediate in this candidate), or `requires-user-decision`. Reviewer assertions are leads; evidence decides. When the orchestrator also implemented the candidate, reject a material finding only with direct reproduction evidence or an unambiguous canonical requirement.
4. **Failing test first.** For each accepted critical or major finding the fixer lands the reproduction as a failing regression test before changing behavior. A finding for which no failing test or exact reproduction can be produced is downgraded to minor unless the orchestrator records why it is untestable and the user accepts it.
5. **Redesign trigger.** Tag each accepted finding with its family. A second accepted finding in the same family — across reviewers or rounds — stops patching: re-plan the abstraction, contract, or verifier before any further fix. Do not patch a third time.
6. Do not expand task authority to address a finding. Surface fixes that require a new product choice, irreversible action, public write, or unrelated scope.

Gate state:

- `failed`: at least one critical or major finding is accepted.
- `inconclusive`: fewer than two valid fresh-context gate reports, any material claim unresolved, any report inconclusive, or the snapshot cannot be confirmed unchanged.
- `passed`: at least two conclusive independent gate reports cover the same unchanged snapshot, no material finding is accepted or unresolved, and the verification agent's full gate passes on that snapshot.

## Remediate and Re-review

For an integrated gate or explicit fix request:

1. The fixer applies accepted findings — failing test, then fix — and runs targeted verification for each.
2. Re-freeze the candidate. Re-review runs in fresh contexts but is **scoped to the remediation**: the packet carries the delta since the last reviewed snapshot, the finding ledger, and the specific invariants that were violated. Two reviewers, each with the delta and the ledger; they may read the whole candidate but are asked to falsify the fixes and their neighbors, not to re-audit the entire diff.
3. When remediation introduced a new abstraction, touched files outside the original finding loci, or is the second round, add one whole-candidate reviewer at the final head.
4. The verification agent runs the full affected gate once on the final head, not on every intermediate head.
5. Expect at most one ordinary remediation round; log every extra round and its cause in the final report.

For review-only requests, stop after synthesis and return the ledger.

## Degraded Conditions

- If two fresh reviewer contexts cannot be obtained, return `inconclusive`; never substitute self-review.
- If acceptance criteria or canonical references are missing, infer only when the choice cannot materially change the result; otherwise ask.
- Security review, architecture review, CI diagnosis, fuzzing, and human review remain complementary when their specialized evidence matters.

## Final Report

Return: the review contract used (and whether it was provisional); scope, baseline, and final snapshot; reviewer count, isolation method, and lenses; each finding with disposition, family, and its regression test; hardening suggestions filed as follow-ups; verifier commands and outcomes; the gate state; remaining limitations; and process metrics — implementation minutes, review minutes, findings by disposition, remediation rounds, and whether the redesign trigger fired.

Record evidence in the PR description, PR comments, or Linear comments against the final reviewed SHA. Do not add evidence-only commits to the candidate.

Report `passed` only when the current snapshot satisfies the clean-gate conditions. Never summarize an inconclusive or stale review as approval.
