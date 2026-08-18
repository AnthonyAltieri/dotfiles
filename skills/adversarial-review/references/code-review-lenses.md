# Code Review Lenses

Use these lenses only for a code candidate. They supplement the falsification mandate, review contract, and finding schema in `SKILL.md`; they never turn a reviewer into an implementer or relax fresh-context, read-only, snapshot, reproduction, or re-review requirements.

## Packet Additions

Include the canonical base, exact diff or path set, relevant surrounding implementation, repository instructions, the review contract (acceptance criteria, threat model, non-goals, invariants by family), and the verification agent's raw lint, typecheck, test, and build results. Do not include implementer reasoning or suspected findings.

## Secondary Lenses

Assign different secondary lenses to reduce correlated blind spots. Every reviewer still looks for any material defect.

1. **Contracts and consistency:** unmet acceptance criteria, inconsistent domain models or state transitions, duplicated-but-diverging implementations, compatibility drift, violations of established repository patterns.
2. **Race and reliability:** concurrency, lifecycle, transactions, locking, caches, retries, cleanup, idempotency, partial failure, and recovery — within the threat model. Time-of-check/time-of-use against actors the threat model trusts is a hardening suggestion, not a finding.
3. **Type and boundary safety:** unsafe casts, unchecked deserialization, unvalidated JSON/env/config, missing exhaustiveness, primitive replacement of canonical domain types, runtime-only invariants that fit the type system.
4. **Proportionality:** code that defends against threats outside the contract, hand-rolled low-level mechanics (raw descriptors, `dir_fd`, `fcntl`, manual atomicity) where a standard primitive suffices, and modules or tests whose size is out of proportion to the requirement. Report these as material when they create the surface that other findings live in.

With two reviewers, pair lenses 1+4 and 2+3.

## Code-Specific Evidence

- Name the exact file and line or symbol.
- Give a realistic input, sequence, state, or caller that fails, as a failing test sketch or command the fixer can land directly.
- Tie the claim to an acceptance criterion, invariant, or raw verifier output.
- Map severity to `critical`, `major`, or `minor`; do not invent a separate vocabulary.

After synthesis, use `$programming` for authorized fixes. Staging, committing, pushing, and pull-request changes are a separate publishing workflow that requires explicit authorization.
