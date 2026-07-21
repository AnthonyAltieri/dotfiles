---
name: improve-codebase-architecture
description: Conduct read-only, codebase-wide architecture discovery for deepening opportunities, tightly coupled module consolidation, test-surface improvement, and alternative interfaces for a selected candidate. Use when the user explicitly asks for architecture-wide analysis or deep-module design. Do not use for a localized implementation, general code review, or a passing mention of architecture; hand implementation to `$programming`.
---

# Improve Codebase Architecture

Find architectural friction and propose deepening opportunities: refactors that put useful behavior behind a smaller interface, improving leverage, locality, testability, and codebase navigation.

## Reference Routing

Read each matching reference directly from this section before doing that work. Do not depend on one reference to reveal another.

| Situation | Required reference |
| --- | --- |
| Every architecture discovery or design report | [Architecture language](LANGUAGE.md) |
| Classifying dependencies, seams, adapters, or test migration for a candidate | [Deepening](DEEPENING.md) |
| The user asks to compare alternative interfaces for a selected candidate | [Interface design](INTERFACE-DESIGN.md) |
| The user explicitly authorizes creating or updating `CONTEXT.md` | [CONTEXT.md format](CONTEXT-FORMAT.md) |
| The user explicitly authorizes recording an architecture decision | [ADR format](ADR-FORMAT.md) |

Use the architecture vocabulary in architecture reports. Do not export its preference for “seam” into unrelated programming guidance where trust, resource, network, or transaction “boundary” is the established term.

## Operating Contract

- Keep discovery, candidate analysis, and interface exploration read-only. Inspect source, tests, configuration, `CONTEXT.md`, and ADRs, but do not edit them during discovery.
- Treat `CONTEXT.md` and ADRs as canonical inputs when present. If either is absent, continue from source evidence and state the limitation instead of inventing project doctrine.
- Require explicit user authorization before creating or updating `CONTEXT.md`, an ADR, or any other documentation. Candidate selection alone is not write authorization.
- Do not change application code under this skill. Once the user selects a design and asks for implementation, hand the agreed design, constraints, and verification goals to `$programming`.
- Preserve repository instructions and existing public contracts. Mark proposals that require a contract or ADR change instead of hiding the conflict.

## Process

### 1. Ground the analysis

1. Read repository instructions and identify the requested architecture scope.
2. Locate and read the relevant parts of `CONTEXT.md` and `docs/adr/` when they exist.
3. Identify the current modules, callers, tests, and runtime seams in that scope.
4. Record important missing context and non-goals before drawing conclusions.

### 2. Explore read-only

When subagents are available, delegate bounded read-only exploration scopes. Give each subagent the repository instructions, architecture scope, relevant domain vocabulary, and a prohibition on edits or external mutations. Useful scopes include caller mapping, test-surface analysis, dependency/lifecycle mapping, and duplicated behavior.

If subagents are unavailable or capacity is limited, inspect the same scopes sequentially. State that the analysis had reduced independent coverage; do not pretend sequential self-analysis is independent review.

Explore organically and look for evidence that:

- understanding one domain concept requires bouncing between many shallow modules;
- duplicated implementations or leaked seams have begun to diverge;
- tests couple to internal helpers while integration behavior remains weakly covered;
- a pass-through module exposes nearly as much complexity as it hides;
- callers repeat policy that belongs behind one domain-named interface.

Apply the deletion test before recommending consolidation: if deleting the module merely redistributes its complexity across callers, it may be earning its keep. Do not treat fewer files or fewer types as an architectural improvement by itself.

### 3. Present candidates

Present a numbered, evidence-backed list. For each candidate include:

- **Files and modules** — the current implementation and representative callers or tests.
- **Problem** — the concrete friction, duplication, leakage, or shallow interface.
- **Deepening direction** — what behavior could move together, without proposing a final interface yet.
- **Benefits** — expected leverage, locality, and test-surface improvement.
- **Constraints and conflicts** — public contracts, dependencies, migrations, and relevant ADRs.

Use project domain terms from `CONTEXT.md` and architecture terms from `LANGUAGE.md`. Surface an ADR-conflicting candidate only when observed friction justifies reconsideration, and name the conflict. Ask which candidate the user wants to explore before designing interfaces or implementing code.

### 4. Explore a selected candidate

Clarify constraints, dependencies, invariants, error modes, ordering, and the tests that should survive the refactor. Load `DEEPENING.md` when seam or dependency strategy matters. If the user requests alternatives, follow `INTERFACE-DESIGN.md` and compare designs before recommending one.

During the conversation, propose domain-language or ADR changes when they would prevent future ambiguity, but do not write them without explicit authorization. When authorized, use the local format reference, preserve existing repository conventions, make the smallest useful documentation change, and read it back.

### 5. Hand off implementation

When the user asks to implement the chosen design, invoke `$programming`. Pass the selected candidate, agreed interface and invariants, affected contracts, migration constraints, test strategy, and unresolved decisions. Keep architecture discovery distinct from implementation and its verification.
