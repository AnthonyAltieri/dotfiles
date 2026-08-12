# Code Review Lenses

Use these lenses only for a code candidate. They supplement the full falsification mandate and required finding schema in `SKILL.md`; they never turn a reviewer into an implementer or relax fresh-context, read-only, snapshot, evidence, or re-review requirements.

## Packet Additions

Include the canonical base, exact diff or path set, relevant surrounding implementation, repository instructions, and raw focused test, lint, typecheck, or build results. Do not include implementer reasoning or suspected findings.

## Secondary Lenses

Assign different secondary lenses to reduce correlated blind spots. Every reviewer still looks for any material defect.

1. **Consistency and contracts:** inconsistent behavior, domain models, state transitions, duplicated-but-diverging implementations, compatibility drift, and violations of established repository patterns.
2. **Race and reliability:** concurrency, lifecycle, transactions, locking, caches, retries, cleanup, idempotency, time-of-check/time-of-use, partial failure, and error recovery.
3. **Type and boundary safety:** unsafe casts, unchecked deserialization, unvalidated JSON/env/config, missing exhaustiveness, primitive replacement of canonical domain types, and runtime-only invariants that fit the language's type system.
4. **Naming and maintainability:** concrete naming, file-layout, public-interface, or test-structure inconsistencies that obscure behavior or increase maintenance risk. Exclude subjective nits.

When capacity permits, assign one reviewer per lens. With only two available fresh contexts, combine lenses while keeping each reviewer's full mandate. Never reduce the base requirement below two valid independent reports.

## Code-Specific Evidence

- Name the exact file and line or symbol.
- Explain a realistic input, sequence, state, or caller that fails.
- Tie the claim to source, a canonical contract, or raw verifier output.
- Suggest a focused reproduction or verification command when useful, but do not run it if it would mutate the candidate or shared state.
- Map severity to the base schema's `critical`, `major`, or `minor`; do not invent a separate gate vocabulary.

After synthesis, use `$programming` for authorized fixes. Re-freeze the full candidate and run fresh reviews after every accepted change. Treat staging, committing, pushing, and pull-request changes as a separate publishing workflow that requires explicit authorization.
