---
name: agent-code-review-loop
description: Deprecated compatibility alias for the former Codex multi-agent code review and fix loop. Use only when the user explicitly invokes `$agent-code-review-loop`; route code review to `$adversarial-review`, authorized fixes to `$programming`, and publishing to a separately requested Git workflow.
---

# Agent Code Review Loop (Deprecated)

Tell the user this Codex-only alias is deprecated and name the composed skills being used. Treat explicit invocation of this alias as an explicit request for a code-focused `$adversarial-review` of the supplied target.

## Route

1. Resolve the target from the invocation: an explicit file set, commit range, pull request, branch diff, or the current branch against its canonical base.
2. Run `$adversarial-review` as the owner of the fresh-context, read-only review gate. Load its code-review lenses and preserve all snapshot, neutral-packet, independence, evidence, drift, and re-review invariants.
3. If the user asked to fix accepted findings, use `$programming` for one minimal verified fix at a time, then return to `$adversarial-review` with a newly frozen full candidate.
4. Report the current gate state, verification evidence, accepted and rejected findings, fixes made, and remaining risks.

## Guardrails

- Do not use this alias's retired four-reviewer workflow as a separate source of truth. The current adversarial-review contract controls reviewer count, roles, verdicts, and gate state.
- Do not commit, push, create or update a pull request, reply to review threads, or otherwise publish automatically. Perform Git or GitHub mutations only through an explicitly requested publishing workflow.
- Do not stage unrelated work or broaden fix authority beyond the reviewed task.
