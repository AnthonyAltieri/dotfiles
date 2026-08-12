# Interface Design

Use this process only after the user selects a deepening candidate and asks to explore alternative interfaces. Use the architecture vocabulary and dependency categories loaded directly from `SKILL.md`.

## 1. Frame the Problem Space

Explain:

- the constraints every viable interface must satisfy;
- the dependencies and their categories;
- the invariants, ordering, error modes, and compatibility obligations callers must understand;
- a rough illustrative code sketch that grounds the constraints without presenting a preferred design.

Show this framing to the user before comparing designs.

## 2. Produce Independent Alternatives

When subagents are available, delegate three or more read-only design briefs in parallel. Give each the same source evidence, constraints, project domain vocabulary, and architecture vocabulary, but a distinct design pressure:

1. Minimize the interface to one to three high-leverage entry points.
2. Maximize flexibility for known extension cases without speculative abstraction.
3. Optimize the most common caller so the default path is trivial.
4. When relevant, design around ports and adapters for a real cross-seam dependency.

Subagents must not edit files or external state. Keep their drafts separate until all have returned.

If fewer than three subagent contexts are available, develop the same alternatives sequentially with distinct constraints and disclose the reduced independence. Do not present sequential self-generated variants as independent evidence.

Each alternative must include:

1. The interface: types, methods, parameters, invariants, ordering, and error modes.
2. A representative caller example.
3. The implementation hidden behind the seam.
4. The dependency and adapter strategy.
5. Tradeoffs in leverage, locality, migration cost, and testability.

## 3. Compare and Recommend

Present the alternatives sequentially, then compare their depth, locality, seam placement, caller burden, migration risk, and test surface. Recommend the strongest design and explain why. Propose a hybrid only when it preserves a coherent interface instead of accumulating features from every option.

Remain read-only. If the user chooses a design and requests implementation, return to `SKILL.md` and hand the agreed design to `$programming`.
