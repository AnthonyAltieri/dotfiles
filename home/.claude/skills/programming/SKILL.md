---
name: programming
description: Use when writing, refactoring, debugging, or reviewing application code that should validate boundaries before typing them, encode invariants in the type system, prefer simple composition over abstraction, keep observability high-signal, and test only the critical behavior that needs ossifying.
metadata:
  short-description: Write simpler, safer application code
---

# Programming

Use this skill for substantive application code changes. It defines code-shaping defaults, not repo workflow. Planning, task tracking, verification, and git rules stay in the caller's global instructions.

Trigger this skill for:
- writing or refactoring business logic
- reshaping data models, state machines, or error flows
- boundary-heavy work: APIs, CLI input, env vars, queues, persistence, files, third-party responses
- code review where design quality matters more than syntax

## Decision Order

1. Make the problem smaller.
2. Validate boundaries before values enter the type system.
3. Encode invariants and future failure modes in types.
4. Compose small explicit functions.
5. Add only the observability and tests that buy safety.

## Non-Negotiables

- Internal application code past the boundary is strongly typed.
- Boundary data is untrusted until parsed with a runtime schema such as `zod` or `pydantic`.
- Prefer discriminated unions and exhaustive matching over ad hoc flags and open-ended strings.
- Prefer composition over inheritance.
- Prefer pure functions for complicated logic unless mutation is required for a real performance reason.
- Top-level business logic should read clearly enough that the callsite feels like pseudocode.
- Less code is better once correctness, clarity, and invariants are preserved.
- Before and after editing, ask: can this be simpler and more readable?

## Boundaries

Treat these as boundaries unless proven otherwise:
- HTTP requests and responses
- CLI args and env vars
- DB rows owned by another system or schema
- queue and event payloads
- cache or local-storage payloads
- third-party SDK and API results
- feature flag payloads
- deserialized files

Rules:
- Parse once at the edge.
- Convert immediately into internal types.
- Keep boundary schemas out of deep business logic.
- Keep validation failures explicit and close to the entrypoint.

## Types And Errors

- Make illegal states unrepresentable.
- Model state transitions explicitly.
- Prefer closed sets of variants so new cases surface as compile errors.
- Prefer explicit result or error types for expected failures; reserve exceptions for truly exceptional paths.
- If a test exists only because the type system cannot rule something out, improve the type model first.

## Composition And Abstraction

- Reach for one more plain function before one more abstraction.
- Hide mechanics, not meaning.
- Avoid helper layers that erase domain language.
- Pass structured values instead of long parameter lists when it improves readability.
- Keep mutation localized and obvious.
- If a class does not own meaningful state or lifecycle, it is probably just a namespace in disguise.

## Observability

- The right observability beats more observability.
- Instrument state changes, decision points, retries, and failure boundaries.
- Prefer structured events over chatty string logs.
- Do not add logs whose only job is to narrate obvious control flow.
- In hot paths, every log line must justify its cost.

## Tests

- Fewer tests are better than more shallow tests.
- Every critical path, business invariant, and regression-prone rule must be tested.
- Prefer a small number of durable tests that lock logic in place.
- Prefer the type system when it can give the same guarantee more cheaply and permanently.
- Test behavior and contracts, not incidental structure.
- Add integration tests at boundaries; keep domain logic fast and direct to unit test.

## Language Notes

- TypeScript: read `references/typescript.md` for defaults on unions, literals, files, classes, and validation.
- Python: read `references/python.md` for boundary validation and type-model guidance.

## Review Pass

Before finishing, ask:
- Did I validate every untrusted input at the boundary?
- Can any branch, state, or error be expressed better in types?
- Did I add abstraction where composition would be clearer?
- Are the top-level business functions easy to scan?
- Are logs high-signal and sparse?
- Are tests covering critical behavior rather than type holes?
- Can I delete code and keep the same guarantees?
