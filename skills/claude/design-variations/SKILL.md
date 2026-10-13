---
name: design-variations
description: Design an app's screens with the user by showing five very different variations per screen in a Claude artifact artboard, letting the user pick and combine them, and recording each decision until the screen set is settled. Then hand off to implementation with tickets that link the artifacts and carry screenshots so the build can match them pixel for pixel. Use when the user asks to design screens, a mobile or desktop version, or a flow "with variations" or "with an artboard"; do not use for a single small UI tweak or for implementing an already-chosen design.
---

# Design Variations

Run a screen-by-screen design session. For each screen the user sees five clearly different options side by side, picks or combines them by letter, and moves on. The chosen designs become the source of truth for implementation.

## Before the First Screen

1. Read the existing app enough to know its data, navigation, design tokens, and the screens to cover. For a new platform version (for example mobile from desktop), list the desktop screens and propose the screen order. Start with the shell or home screen, because later screens reuse its navigation.
2. Load the artifact design guidance (`artifact-design`) before writing the first artboard.
3. Use real data shapes and realistic values from the app, never lorem ipsum. Use the app's existing tokens, fonts, and component vocabulary unless the user asks for a new direction.

## Each Screen

1. Build one artifact per screen: an artboard with five variations labeled **A** to **E**, at the target viewport (for example 390×844 for mobile), side by side, each with a one-line caption saying what makes it different.
2. Make the five genuinely different: layout, information hierarchy, navigation pattern, and density, not five color swaps. At least one should be conservative and one should be bold.
3. Make them interactive where the interaction is the design question (tabs, sheets, toggles, expanding rows). Avoid scroll and overflow bugs: each variation scrolls inside its own frame and nothing clips.
4. Ask one short question: which to keep, and what to take from the others.
5. Apply the answer literally. The user often combines ("A but the chart from C", "B, and when you click it, A", "A, C and D swappable"); build the combined version in the same artifact as a new **Chosen** frame and show only the changed screen. Answer comparison questions ("what's the difference between A and E?") in two or three sentences tied to what the user sees.
6. When the user approves ("ok that's good", "next screen"), record the decision and move to the next screen without asking for confirmation again.

## Decision Log

Keep a running log in the conversation and at the top of the final summary: for each screen, the artifact link, the chosen variation or combination, and any behavior the user added in words (data sources, states, icons, "since you added to watchlist"). New requirements the user mentions mid-session (a new API, a new data field) go in the log as backend work.

## Hand-off to Implementation

When the user asks for tickets or implementation:

1. File one ticket per screen, plus separate tickets for shared shells, components, and any backend work from the log. Each screen ticket includes the artifact link, a screenshot of the **Chosen** frame, the decisions from the log, and this acceptance criterion: the rendered page matches the artifact at the same viewport, apart from bugs the ticket names.
2. Mark the shell as blocking the screens that use it.
3. Hand the tickets to `$spawn-orchestrator` when the user asks to implement them. Frontend workers compare the rendered page with the artifact and attach both screenshots to the PR.

## Guardrails

- Never show fewer than five variations for a new screen unless the user asks for fewer.
- Do not implement code during the design session unless the user asks.
- Keep each artifact for its screen; update it in place instead of creating a new artifact per round.
