---
name: animated-docs
description: Build interactive, animated explainers for technical concepts inside a docs site, in the style of Visual Effect (effect.kitlangton.com). The real code runs; every tracked entity is a state-machine node that animates through its states; a data-model panel animates each change; hovering a node highlights the code that made it. Use for "animated docs", "interactive explainer", "visualize how X executes", or "show how the data model changes when the user does Y". Skip for static diagrams, data charts, and decorative motion.
metadata:
  short-description: Interactive animated explainers for docs
---

# Animated Docs

Build an explainer card the reader can run, interrupt, and reset. The card shows the entities of a concept as nodes, the data they touch as a live panel, and the code that produced them, all wired to one another. The pattern is distilled from Kit Langton's Visual Effect repo, so the references cite the source file for each rule. The quality bar borrows from Paul Bakaus's Impeccable: motion explains state, one authored moment per surface, verify in bounded passes, and a docs page is a Read surface where the card must never hijack the reading.

## What a card is

One card teaches one concept. From top to bottom:

1. **Header**: a single control button that cycles play, stop, reset, plus the concept name and a one-line imperative description.
2. **Config panel** (optional): a segmented control that changes both the code snippet and the program that runs.
3. **Data-model panel** (optional): named values or rows; each change animates as a diff.
4. **Node row**: input nodes, an arrow, a result node. Each node is a 64px square that changes color, shape, and content with its state.
5. **Progress surface** (optional): a scrolling timeline for schedules, or a card stack for ordered cleanup.
6. **Code block**: the snippet the reader should walk away with. Hovering a node floats a highlight over the substring that created it.

## Before you build: the card brief

Write eight lines before any code. Put them in the ticket or PR description, not in a commit. Assert the likely reading from the request and the codebase; ask only when two scenes fit equally or the lesson itself is unclear.

```
LESSON:   the one sentence the reader should be able to say afterwards
SCENE:    one of the seven in references/scene-catalog.md
BEAT:     the single state transition that carries the lesson, and how it is made legible
STORY:    the concrete scenario, its result values, its failure text
ENTITIES: node name -> code substring, one per node
DATA:     stores shown, their initial values, which fields change on which step
ENDINGS:  every way a run can end (success, failure, interrupt, exhausted schedule)
RANGES:   node count, longest result string, longest store value, mobile width
HOST:     framework, mount mechanism, one sentence recording the site's actual palette, type, radius, and surface treatment
```

The BEAT is the card's authored moment. Everything else is supporting feedback and stays quiet.

## Quick start

1. Read `references/scene-catalog.md`, pick the scene, write the card brief.
2. Read `references/architecture.md` and build the model layer first: one observable per entity, a store per piece of data model, one composed program that runs the real code.
3. Build the scene from the layout above, then apply `references/motion-vocabulary.md`. Read its "Lint reconciliation" section before styling if the host has a design system or a design linter.
4. Verify in two bounded passes as described below.

## Invariants

- **The real code runs; the view only watches.** The composed program is the library or product code under explanation, wrapped so state transitions are observable. Never hand-script the animation timeline. If the real code hits I/O, replace only the I/O boundary with a stub that has jittered delays. Source: `VisualEffect.ts`, `examples/helpers.ts`.
- **Pacing is declared, never faked.** Slowing down is allowed only on a stubbed boundary the story names as a wait (a fetch, a delivery, a lock). Never insert a delay into the real computation, and never hold a finished state back to stage a flourish. The one exception is an ordered progress surface such as a cleanup stack, where each step may hold for a fixed beat so the order can be read; say so in the brief.
- **State is a closed union with a transition table.** Every entity has `idle | running | completed | failed | interrupted | death` or a domain equivalent. Reject invalid transitions and log them in development. Derive every color, icon, and animation from state plus the previous state; store nothing visual in the model. Expose the state on the DOM as `data-state` so verification can assert it.
- **One control, total reset.** The header button runs when idle, interrupts when running, and resets when terminal. Reset cascades to child entities, cancels the fiber or abort controller, clears timers, and restores every store to its initial value.
- **Still at rest.** Nothing moves until the reader acts. No autoplay, no ambient loops, no entrance choreography on scroll. The header star sits still when idle; the running loops stop the moment the run ends. A docs page is for reading, and a card that moves on its own steals the page.
- **Every visible thing maps to code.** Each node name appears in the highlight map with the substring it corresponds to. If a config option changes the program, it changes the snippet and the highlight target too.
- **Runs differ, outcomes teach.** Use jittered delays so a second run looks alive, but choose ranges so the BEAT lands: a race the reader can lose either way, a timeout that fails the first attempt and succeeds the second, a retry whose failures are legible. Provide a deterministic mode (injected `random` and `now`) for tests and screenshots.
- **Data changes animate as diffs.** A value swaps with an odometer slide, a row enters or exits through `AnimatePresence`, a changed container flashes then settles. Never re-render the whole panel.
- **Overshoot only on arrival.** A result landing in a node may overshoot with a spring of bounce 0.3 or less. Every other motion is critically damped: highlights, layout moves, stack slides, panel flashes, height and radius changes. No CSS bounce or elastic curves anywhere. Exits are faster than entrances.
- **Inherit the host; keep the grammar.** The state colors, springs, and per-state recipes are the grammar and stay fixed as roles. Palette values, type, radius, and surface treatment come from the host site when it has a design system. Monospace is for code, node labels, and values; descriptions and prose use the host's body face. Emoji are result data, never icons; icons are drawn from one icon set at one stroke weight.
- **Motion is cheap, reduced motion keeps meaning.** Under `prefers-reduced-motion`, drop jitter, shake, glitch, flash, and the shimmer, and keep color, icon, and content changes so every state is still legible. Use GPU hints on animated containers, cap blur at 2px and glow at 8px, and cancel every timer and animation on unmount and reset. Sound is off by default and never carries meaning.
- **Copy is imperative and unpunctuated.** Descriptions start with a verb and end without a period: "Race two effects and return the first successful one". A fictional story may joke in its failure text. A card about the product's own code shows the real error type and message, and the recovery if there is one.

## Composition boundaries

- Use `programming` for the model layer, the wrapping of real code, and any state or error modeling; this skill supplies the visualization contract.
- Use `frontend-design` only when the host site has no design system; otherwise inherit the site's tokens and keep this skill's node and motion vocabulary.
- If the host repo has Impeccable installed (`.impeccable/`, or `impeccable` in a skills directory), run its detector on the card files during verification and read `references/motion-vocabulary.md` "Lint reconciliation" for the findings that are earned and the ones to fix. Do not run its redesign commands on a card; the card's look is this skill's.
- Use `dataviz` if the panel becomes a chart of numbers. A data-model panel here is a live view of values and rows, not a plot.
- Run copy through `unslop`; write descriptions in the style rules above and `technical-writing` for any surrounding prose.

## Host integration

- Detect the docs framework first: Next.js, Docusaurus, Astro, Nextra, or plain MDX. Render the description and the code block on the server so the page reads without JavaScript, then mount the interactive card client-side over it. Motion values and `window` are unavailable during SSR.
- Record the HOST line of the brief from the site's real tokens: CSS custom properties, the loaded fonts, the card and border treatment on neighboring components. Read them from the code and computed styles, not from a guess.
- Reuse an existing `motion` (Framer Motion successor) dependency; add it if absent. Do not add a second animation library. If the host forbids a JS motion library, express the grammar in CSS with `cubic-bezier(0.16, 1, 0.3, 1)` for arrivals and the timing table in the motion vocabulary.
- Put explainers where the site keeps interactive components, one file per card, registered in a manifest with `id`, `name`, `variant`, `description`, `section`. Deep links resolve by `id`.
- When the concept is the product's own code, import the real module into the card so the docs cannot drift from behavior.

## Verification

Two bounded passes. Build the whole card, inspect once, fix everything the inspection shows in one batch, confirm with one more round, then stop.

**Pass one, batched:**

- Typecheck and lint the new files with the host repo's tools.
- Run the site and drive it headless with the recipe in `references/architecture.md`. Capture idle, about 300ms after clicking run, and after completion, at desktop and mobile widths. The script asserts `data-state` on every node at each capture and fails if the running capture shows no running node; a screenshot that does not show what its name claims is invalid evidence and forces a recapture.
- Click run, stop, then reset twice in a row. No console warnings about invalid transitions, no leaked intervals, every store back at its initial value.
- Toggle `prefers-reduced-motion` and confirm each state is still distinguishable by color and content alone.
- Hover each node and confirm the highlight lands on the intended substring.
- Feed the RANGES line: the longest result string, the largest store value, the maximum node count, at mobile width. Nothing overflows or clips.
- If Impeccable is installed, run its detector on the card files.

**Finish review:** hand the card brief, the captures, and the card source to a fresh agent with no build context. It answers six checks and returns one of `ship` or `fix` on its first line with at most six ordered fixes: the BEAT is the most legible moment in the running capture; every node maps to a substring that exists in the snippet; reset restores every store; the card is still at rest; the palette and type match the HOST line; every ENDINGS entry is reachable. Apply the fixes as one batch, recapture, and stop.

## References

- `references/architecture.md`: observable model, entity wrapper, store, scene contract, control logic, code highlight, DOM contract, static fallback, content ranges, manifest, deterministic mode, headless verification.
- `references/motion-vocabulary.md`: palette as roles with fallback values, springs, timing bounds, per-state recipes, reduced-motion behavior, and lint reconciliation.
- `references/scene-catalog.md`: the scene types with their teaching beats and endings, how to map a request to one, and how to choose a story.
