---
name: programming
description: Write, refactor, debug, or review substantive application code involving business logic, data/state/error modeling, API/CLI/environment/queue/persistence/file/third-party boundaries, or design-focused code review. Apply validated boundaries, canonical domain types, explicit dependency lifetimes, visible orchestration, local code over gratuitous helpers, deliberate effects/observability, and minimal critical-path tests.
---

# Programming

Follow the caller's planning, task-tracking, verification, and git instructions.

## Contract

- Before designing, inspect the repository's canonical domain types, schemas, constructors/factories, composition roots, lifecycle owners, error conventions, and test patterns.
- Unless explicitly changed, preserve behavior—especially transaction, lock, resource, concurrency, retry, and effect-ordering boundaries—public contracts, and canonical domain language. Report suspected defects separately.
- Reuse canonical validation, type, dependency-construction, and error-modeling paths. Make the smallest proportional change that preserves correctness, clarity, and invariants.
- Treat edge cases as risks, not authority for adjacent work. Do not invent lifecycle managers, telemetry APIs, dependency containers, result frameworks, or infrastructure when direct composition or existing hooks suffice.
- For sketches, reviews, and proposals, show only decisive code and assumptions; mention hardening separately. Without repository context, use narrow placeholders for existing infrastructure. For implementation, inspect further or surface the gap instead of inventing a seam.
- Explicit requirements and established contracts override these defaults; surface material conflicts.

## Required References

Before designing, editing, debugging, or reviewing, read every matching reference completely; combine matches. Substantive work alone selects none.

| Situation | Reference | Focus |
| --- | --- | --- |
| Task changes or evaluates multi-step or branching workflows, effect order, helper extraction, composition, or orchestration readability. Skip leaf transforms, isolated local fixes, and type/schema-only work without control-flow or locality decisions. | [Orchestration and locality](references/orchestration-and-locality.md) | Locality, explicit dataflow, commands, proportional extraction |
| Task changes or evaluates nested expressions, collection transformations, fluent chains, staged abstractions, or value-flow visibility | [Visible dataflow](references/visible-dataflow.md) | Named stages, honest topology, evidence, production semantics |
| Task constructs, shares, scopes, caches, or cleans up dependencies/resources; changes entrypoints or composition roots; or involves ambient config or stateful collaborators. Skip when no dependency, resource, configuration, or stateful-collaborator concern exists. | [Dependency lifetimes](references/dependency-lifetimes.md) | Construction, identity, sharing, ownership, cleanup |
| TypeScript or TSX is in scope | [TypeScript defaults](references/typescript.md) | Validation, brands, inference, literals, unions, files |
| Python is in scope | [Python defaults](references/python.md) | Boundary validation, type modeling |

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

- Treat external or deserialized values as untrusted, including HTTP input, CLI arguments, environment values, cross-schema database rows, queues/events, caches/local storage, files, feature flags, and third-party results. At each trust transition, parse once through the canonical runtime schema, parser, constructor, or guard.
- Immediately convert parsed values to canonical internal domain types. Keep transport schemas/DTOs out of deep business logic and validation failures explicit near the boundary.
- Make illegal states unrepresentable. Reuse branded, opaque, or nominal types through canonical construction; never replace canonical types with primitive aliases, duplicate schemas, parallel helper types, or unsafe casts.
- Add constrained types only when they fit the repository and either prevent concrete confusion or preserve an invariant across a meaningful boundary. Prefer discriminated unions, closed variants, explicit state transitions, and exhaustive matching over flags, loosely related optionals, or open strings.
- Follow repository result/error conventions for expected failures; reserve exceptions for paths callers cannot reasonably handle as ordinary control flow.
- Prefer inference in trusted code; avoid annotation ceremony.

## Structure, Ownership, And Effects

- Make top-level workflows read like pseudocode: topologically ordered, domain-named values and commands. Prefer named, single-assignment intermediates and ordinary calls over chains, nesting, or mutable accumulators; expose dependencies through inputs and outputs.
- Keep one-use logic inline while locally clear and dense. Extract only for reuse, branching, invariants, semantic compression, effects, or lifecycle. Hide mechanics, not domain meaning.
- Prefer plain functions and objects; use classes when instances own meaningful mutable state, resources, or lifecycle.
- Give every constructed dependency an explicit identity-sharing scope, lifecycle owner, and cleanup boundary.
- Keep calculations pure when practical; localize commands, I/O, and mutation so ordering and ownership stay obvious.
- Delay mutation and irreversible effects as far as dependencies allow. Permit mutation when it expresses a domain operation, satisfies an external API, materially improves performance, or is the clearest language-specific choice. Do not force compute-then-commit when a later step requires an effect's result.

## Observability

- Add or change telemetry only when the task owns it or changed behavior invalidates existing instrumentation; otherwise preserve it and report material review gaps.
- When in scope, cover semantic state changes, consequential decisions, retries, external failure boundaries, and expensive operations. Prefer structured events and meaningful spans over chatty narration. Preserve trace/correlation context across asynchronous and external boundaries.
- Exclude secrets, sensitive payloads, uncontrolled cardinality, obvious-flow narration, and hot-path signals that do not justify their cost.

## Tests

- For implemented behavior changes, add the minimum sufficient tests for critical paths, business invariants, boundary contracts, and regression-prone behavior. During review or diagnosis, report missing coverage without changing it unless requested.
- Don’t add configurability solely to make tests convenient. Introduce a dependency seam only when the dependency represents meaningful behavior that may vary; otherwise test through the real boundary.
- Prefer durable behavior/contract tests over helper-layout coupling. Test integrations where parsing, serialization, persistence, or third-party behavior can fail.
- Prefer compile-time guarantees when they fully replace representability tests; types never replace runtime or semantic verification.
- Do not expand test scope to hypothetical lifecycle/failure permutations the change does not own. When asked for test seams, identify injectable boundaries without adding a test matrix unless requested.

## Review Pass

Before finishing, verify every untrusted value is parsed before domain use and canonical paths are reused; dependency owners, lifetimes, and cleanup; visible workflows and justified helpers; effects and mutation are localized and visible; sparse, safe telemetry; critical-behavior tests; and no abstraction without a useful guarantee.
