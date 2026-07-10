---
name: programming
description: Write, refactor, debug, and review application code with validated boundaries, canonical domain types, explicit dependency lifetimes, pseudocode-like orchestration, local code over gratuitous helpers, deliberate effects and observability, and minimal critical-path tests. Use for substantive business logic, data modeling, state and error flows, API/CLI/env/queue/persistence/file/third-party boundaries, and design-focused code review.
---

# Programming

Use this skill to shape application code. Follow the caller's instructions for planning, task tracking, verification, and git workflow.

## Operating Contract

- Inspect the repository before designing. Find its canonical domain types, schemas, constructors, factories, composition roots, lifecycle owners, error conventions, and test patterns.
- Preserve existing behavior, public contracts, and canonical domain language unless the task explicitly changes them.
- Reuse an appropriate existing validation, type, dependency-construction, or error-modeling path instead of creating a parallel system.
- Make the smallest change that preserves correctness, clarity, and invariants.
- Keep the solution proportional to the requested behavior. Do not invent lifecycle managers, telemetry APIs, dependency containers, result frameworks, or adjacent infrastructure when direct composition or existing hooks suffice.
- Match the requested fidelity. For a sketch, review, or proposal, show only the decisive code and assumptions; mention hardening concerns separately instead of implementing them.
- Treat possible edge cases as risks to assess, not automatic authorization to build adjacent behavior.
- For a sketch, review, or proposal without necessary repository context, use narrow placeholders for existing infrastructure instead of fabricating it. For implementation, inspect further or surface the missing context instead of committing an invented seam.
- Treat these rules as defaults beneath explicit task requirements and established contracts. Surface a material conflict instead of silently forcing a preference.

## Required References

Read every matching reference completely before designing, editing, debugging, or reviewing. Read multiple references when multiple rows match.

For every substantive application-code task, the orchestration row matches. Expect the dependency-lifetime row to match most tasks; skip it only for a pure leaf transformation or type-only change that constructs, shares, and owns no dependency or resource.

| Situation | Required reference | Focus |
| --- | --- | --- |
| Any substantive application-code implementation, refactor, bug fix, debugging or diagnosis, or design review | [Orchestration and locality](references/orchestration-and-locality.md) | Default code shape, locality, dataflow, and effects |
| Most substantive application tasks, including entrypoints, framework wiring, dependency use or construction, ambient config, stateful collaborators, resources, or cleanup | [Dependency lifetimes](references/dependency-lifetimes.md) | Construction, sharing, scoping, ownership, and cleanup |
| TypeScript or TSX is in scope | [TypeScript defaults](references/typescript.md) | TypeScript validation, brands, inference, literals, unions, and files |
| Python is in scope | [Python defaults](references/python.md) | Python boundary validation and type modeling |

## Decision Order

1. Understand the existing contract and domain language.
2. Make the problem smaller.
3. Establish trust at every boundary.
4. Decide who owns each dependency and how long it lives.
5. Encode domain invariants and expected failures in types.
6. Arrange the workflow as explicit dataflow and commands.
7. Add only the observability and tests that buy meaningful safety.
8. Delete incidental structure that does not improve those guarantees.

## Trust And Domain Modeling

- Treat external and deserialized values as untrusted until parsed.
- Include HTTP input, CLI arguments, environment values, cross-schema database rows, queues, events, caches, local storage, files, feature flags, and third-party results.
- Parse once at each trust transition with the repository's canonical runtime schema, parser, constructor, or guard.
- Convert parsed values immediately into canonical internal domain types.
- Keep transport schemas and DTOs out of deep business logic.
- Keep validation failures explicit and close to the boundary.
- Make illegal states unrepresentable.
- Reuse existing branded, opaque, and nominal types with their canonical construction path.
- Do not replace a canonical domain type with a primitive alias, duplicate schema, parallel helper type, or unsafe cast.
- Introduce a branded or otherwise constrained type when it prevents a concrete confusion or preserves an invariant across a meaningful boundary, and when it fits the repository's modeling approach.
- Prefer discriminated unions, closed variants, explicit state transitions, and exhaustive matching over flags, loosely related optionals, and open-ended strings.
- Follow the repository's result or error convention for expected failures. Reserve exceptions for paths callers cannot reasonably handle as ordinary control flow.
- Prefer inference inside trusted code. Do not confuse strong typing with annotation ceremony.

## Structure, Ownership, And Effects

- Make top-level business workflows read like pseudocode: a topologically ordered sequence of domain-named values and commands.
- Prefer named, single-assignment intermediate values over nested expressions and mutable accumulator state.
- Make dependencies visible through inputs and outputs.
- Keep one-use logic inline when it remains locally understandable and information-dense.
- Extract a function only when reuse, branching, invariants, semantic compression, effects, or lifecycle justify the indirection.
- Hide mechanics, not meaning. Avoid helper layers that erase domain language.
- Prefer plain functions and objects. Use a class when an instance owns meaningful mutable state, resources, or lifecycle.
- Give every constructed dependency an explicit identity-sharing scope and lifecycle owner.
- Keep calculations pure when practical; localize commands, I/O, and mutation so their ordering and ownership remain obvious.
- Delay mutation and irreversible effects as far as real dependencies allow.
- Allow mutation when it expresses the domain operation, satisfies an external API, materially improves performance, or is the clearest language-specific choice.
- Do not force a compute-then-commit shape when an effect's result is genuinely required by a later step.

## Observability

- Add or change telemetry only when the task owns it or changed behavior would make existing instrumentation incorrect. Preserve it otherwise and report material gaps during review.
- When instrumentation is in scope, cover semantic state changes, consequential decisions, retries, external failure boundaries, and expensive operations.
- Prefer structured events and meaningful spans over chatty string narration.
- Preserve trace and correlation context across asynchronous and external boundaries.
- Avoid secrets, sensitive payloads, uncontrolled cardinality, and logs that merely restate obvious control flow.
- Make every hot-path signal justify its cost.

## Tests

- When implementing changed behavior, add the minimum sufficient tests for critical paths, business invariants, boundary contracts, and regression-prone behavior. During review or diagnosis, report missing coverage without changing it unless requested.
- Prefer durable behavior and contract tests over tests coupled to helper layout or incidental implementation.
- Test boundary integrations where parsing, serialization, persistence, or third-party behavior can fail.
- Prefer a compile-time guarantee when it fully replaces a representability test; do not use types as a substitute for runtime or semantic verification.
- Do not expand test scope to hypothetical lifecycle or failure permutations that the change does not own.
- When asked for test seams, identify injectable boundaries without producing a test matrix unless requested.

## Review Pass

Before finishing, verify:

- Parse every untrusted value before treating it as a domain value.
- Reuse canonical schemas, types, constructors, and ownership paths.
- Give every dependency the correct owner, lifetime, and cleanup boundary.
- Make the main workflow readable as named data dependencies and explicit commands.
- Make every extracted helper pay for its indirection.
- Keep effects and mutation localized and visible.
- Keep telemetry sparse and meaningful.
- Test critical behavior rather than type holes or helper structure.
- Remove code or abstraction that does not preserve a useful guarantee.
