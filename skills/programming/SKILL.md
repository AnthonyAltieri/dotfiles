---
name: programming
description: Write, refactor, debug, or review substantive application code. Use for business logic, data/state/error modeling, API/CLI/environment/queue/persistence/file/third-party boundaries, and design-focused code review; skip for trivial mechanical edits.
---

# Programming

Follow the caller's planning, task-tracking, verification, and git instructions.

## Contract

- Before designing, learn how the repository already does things: its canonical domain types, schemas, constructors and factories, composition roots, lifecycle owners, error conventions, and test patterns.
- Preserve existing behavior, public contracts, and canonical domain language unless the task explicitly changes them. Be especially careful with transaction, lock, resource, concurrency, retry, and effect-ordering boundaries. If you suspect a defect, report it separately instead of silently fixing it.
- Reuse the canonical paths for validation, types, dependency construction, and error modeling rather than creating parallel ones. Make the smallest change proportional to the task that preserves correctness, clarity, and invariants.
- An edge case is a risk to handle, not a license to expand into adjacent work. Do not invent infrastructure — lifecycle managers, telemetry APIs, dependency containers, result frameworks — when direct composition or an existing hook suffices.
- In sketches, reviews, and proposals, show only the decisive code and assumptions; mention hardening separately. When repository context is missing, sketches may use narrow placeholders for existing infrastructure, but implementation must inspect further or surface the gap instead of inventing a seam.
- Explicit requirements and established contracts override these defaults; surface material conflicts.

## Required References

Read every matching reference completely before designing, editing, debugging, or reviewing; combine all matches. If no situation matches, read none — work being substantive does not by itself select a reference.

| Situation | Reference | Focus |
| --- | --- | --- |
| The task changes or evaluates a multi-step or branching workflow: effect order, helper extraction, composition, or orchestration readability. Skip for leaf transforms, isolated local fixes, and type/schema-only work with no control-flow or locality decision. | [Orchestration and locality](references/orchestration-and-locality.md) | Locality, explicit dataflow, commands, proportional extraction |
| The task changes or evaluates nested expressions, collection transformations, fluent chains, staged abstractions, or value-flow visibility. | [Visible dataflow](references/visible-dataflow.md) | Named stages, honest topology, production semantics |
| The task constructs, shares, scopes, caches, or cleans up dependencies or resources; changes entrypoints or composition roots; or involves ambient config or stateful collaborators. Skip when no such concern exists. | [Dependency lifetimes](references/dependency-lifetimes.md) | Construction, identity, sharing, ownership, cleanup |
| TypeScript or TSX is in scope. | [TypeScript defaults](references/typescript.md) | Validation, brands, inference, literals, unions, files |
| Python is in scope. | [Python defaults](references/python.md) | Boundary validation, type modeling |

## Decision Order

1. Understand the contract and domain language.
2. Shrink the problem.
3. Establish trust at each boundary.
4. Assign dependency owners and lifetimes.
5. Encode invariants and expected failures in types.
6. Arrange explicit dataflow and commands.
7. Add only valuable observability and tests.
8. Remove structure that preserves no guarantee.

## Trust And Domain Modeling

- Treat every external or deserialized value as untrusted: HTTP input, CLI arguments, environment values, cross-schema database rows, queue/event payloads, caches, local storage, files, feature flags, and third-party results. Parse each one exactly once, at the trust transition, through the canonical runtime schema, parser, constructor, or guard.
- Convert parsed values to canonical internal domain types immediately. Keep transport schemas and DTOs out of deep business logic, and keep validation failures explicit and near the boundary.
- Make illegal states unrepresentable. Reuse branded, opaque, or nominal types through their canonical construction; never replace canonical types with primitive aliases, duplicate schemas, parallel helper types, or unsafe casts.
- Add a constrained type only when it fits the repository and either prevents a concrete confusion or preserves an invariant across a meaningful boundary. Prefer discriminated unions, closed variants, explicit state transitions, and exhaustive matching to flags, loosely related optionals, or open strings.
- Follow the repository's result/error conventions for expected failures. Reserve exceptions for faults that callers cannot reasonably handle as ordinary control flow.
- Prefer inference in trusted code; avoid annotation ceremony.

## Structure, Ownership, And Effects

- Make top-level workflows read like pseudocode: domain-named values and commands in dependency order. Prefer named single-assignment intermediates and ordinary calls to chains, nesting, or mutable accumulators, and expose dependencies through inputs and outputs.
- Keep one-use logic inline while it stays locally clear and dense. Extract only when a boundary earns its cost — reuse, branching, an invariant, semantic compression, effects, or lifecycle. A good helper hides mechanics, not domain meaning.
- Prefer plain functions and objects. Use a class when instances own meaningful mutable state, resources, or lifecycle.
- Give every constructed dependency an explicit identity-sharing scope, lifecycle owner, and cleanup boundary.
- Keep calculations pure when practical. Localize commands, I/O, and mutation so their ordering and ownership stay obvious.
- Delay mutation and irreversible effects as late as dependencies allow. Mutation is fine when it expresses a domain operation, satisfies an external API, materially improves performance, or is the clearest idiom in the language. Do not force a compute-then-commit shape when a later step needs an effect's result.

## Observability

- Add or change telemetry only when the task owns it or changed behavior invalidates existing instrumentation. Otherwise preserve what exists and report material gaps during review.
- When telemetry is in scope, cover semantic state changes, consequential decisions, retries, external failure boundaries, and expensive operations. Prefer structured events and meaningful spans to chatty narration, and preserve trace/correlation context across asynchronous and external boundaries.
- Exclude secrets, sensitive payloads, uncontrolled cardinality, narration of obvious flow, and hot-path signals that do not justify their cost.

## Tests

- For implemented behavior changes, add the minimum sufficient tests for critical paths, business invariants, boundary contracts, and regression-prone behavior. During review or diagnosis, report missing coverage without changing it unless asked.
- Do not add configurability solely to make tests convenient. Introduce a dependency seam only when the dependency represents meaningful behavior that may vary; otherwise test through the real boundary.
- Prefer durable behavior and contract tests to tests coupled to helper layout. Test integrations where parsing, serialization, persistence, or third-party behavior can fail.
- Prefer compile-time guarantees when they fully replace representability tests; types never replace runtime or semantic verification.
- Do not expand test scope to hypothetical lifecycle or failure permutations the change does not own. When asked for test seams, identify injectable boundaries without adding a test matrix unless requested.

## Review Pass

Before finishing, verify:

- every untrusted value is parsed before domain use, through canonical paths;
- every dependency has an owner, lifetime, and cleanup boundary;
- workflows are visible and each helper is justified — name the guarantee it preserves, and if it forwards most of its context while preserving no independent invariant, collapse it into its caller or lifecycle owner;
- effects and mutation are localized and visible;
- telemetry is sparse and safe;
- critical behavior is tested;
- no abstraction remains without a useful guarantee.
