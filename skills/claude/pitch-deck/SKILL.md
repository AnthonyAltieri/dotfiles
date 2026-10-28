---
name: pitch-deck
description: Build a startup's business plan and investor pitch deck with the founder, from their thesis to a reviewed, published deck. Covers a plan artifact with sourced numbers, bottom-up market sizing, simulated investor panels that critique and score until they reach 8+/10, a style chosen from five variations before the full build, a Slides artifact, and sourcing, voice and founder-slide passes. Use when the user asks for a pitch deck, seed deck, investor deck, business plan, or an investor or VC panel review of either; do not use for a single slide tweak on a finished deck or for non-investor presentations.
---

# Pitch Deck

Take a founder from thesis to a deck that a panel of simulated investors, founders and designers scores at 8 or higher. The founder owns the thesis and every decision. Panels find weaknesses, but they never set direction.

## Standing rules

- **The founder's thesis wins.** Write it in the founder's own words at intake and check every panel round against it. Panels drift toward familiar categories and add jargon. When a panel's ask would change the thesis, the category or the product's name, bring it to the founder as a decision. Never apply it quietly.
- **No unsourced numbers** on the plan, the deck, mockups or charts. Every number either has a source (a URL with its access date, a filing, or a measurement) or is labelled as an assumption or "not yet measured". If neither is possible, remove it. Never invent an illustrative figure. Recompute every piece of arithmetic shown on a slide.
- **No overclaiming.** Avoid "safe", "prove", "guarantee", "only", and "never X" claims that one demo could break. A heading must not claim more than its body supports. Name the real audience ("for teams on OpenTelemetry"), not "every team".
- **Ask decisions in chat**, not in a multi-question form. Number each decision, letter its options, mark the recommended one, and give each option a two-column pros/cons table. The founder replies with codes like `1A 2B`.
- **Record every founder decision in memory** with its date, and don't raise it again unless new evidence appears.
- **Read the live artifact before every publish**, and merge in any edits the founder made in the editor. Always give the artifact link in the update.
- **Send one consolidated update per round:** what changed (a before/after table), the scores, and the links. Don't post a status message for each reviewer.
- **Personas are simulations.** Base each one on public sources. Never invent quotes, and never paste confidential plan text into a web search.

## Phases

### 0. Intake

1. Get a brain dump from the founder: the problem, the insight, the product, the customers, the traction, and the founder's background.
2. Write the thesis line in the founder's own words and confirm it.
3. List the facts with their sources, and the open questions.
4. Ask about a brand palette. If there's none yet, use grayscale.
5. Create a memory file for the founder's decisions.

### 1. Business plan artifact

Before writing any file, run the Artifact `quickstart` (intent `document`, or `other` for an HTML page).

- **Structure:** section by section, thesis-led, in three parts:
  - the story (Sequoia order: problem, solution, why now, market, competition, product, business model, team);
  - the economics;
  - the bets: the riskiest assumptions, each with its cheapest disproof, then the roadmap.
- **Status chips:** each section carries one: `measured/sourced`, `draft` or `founder to decide`.
- **Founder decisions appendix:** an appendix listing the open choices. Strip it from the text panels see.
- **Sources section** at the end.

**Checkpoint:** the founder confirms the thesis and answers the first round of open decisions.

### 2. Research (parallel background agents)

Each claim gets a cited URL and its access date.

- **Competitors and pricing:** published price lists, plus a worked comparison for one typical customer.
- **Market counts:** public filings and industry datasets, by segment.
- **Why now:** dated events in the domain.
- **Other areas,** such as legal or IP questions the founder raises (for example invention assignment in their state): one agent each.

### 3. Market sizing

Size the market bottom-up, for each segment: number of customers × units per customer per period × price. Label each input sourced or assumed.

- Use the standard terms: TAM, SAM, target.
- The headline is the solid core number. Expansion is shown separately, dashed and labelled.
- Don't count products that aren't named or built.
- State the one assumption that drives the size, in plain words.
- Put the method on an appendix slide.

### 4. Investor panels on the plan

**Panel make-up.** Five personas per panel, chosen for relevance: the sector's lead investors, a top-tier generalist firm, and the investors of any second buyer. Show the founder a "why this investor" table first.

**Each panelist** is a background agent running on the strongest model. It does two things:

1. **Profile.** Research the person in 6–12 public sources and save a profile: theses, portfolio conflicts, what makes them say yes, what makes them pass, and the URLs.
2. **Critique**, covering:
   - a verdict and a score from 1 to 10;
   - what is strong (at most 4 points);
   - what breaks it, ranked (at most 6);
   - required changes, by section;
   - questions for the founder (at most 5);
   - "what would make this a 9".

   Settled founder decisions are treated as given. A gap only the founder can fill isn't marked down. Each reply to the orchestrator is at most 150 words; the detail goes in their file.

**Loop:**

1. Wait for every panelist.
2. Combine the changes they agree on, and list the conflicts.
3. Bring any change to the thesis, and every conflict, to the founder as a decision.
4. Revise the plan.
5. Write `changes-rN.md` and a plain-text export of the plan.
6. Resume the same agents with SendMessage. Each says what was addressed, re-scores, and pushes back on changes made for other panelists.

Stop when everyone is at 8 or above, or escalate to the founder. When a new topic is folded in, add a panel for it and have the earlier panelists re-score.

### 5. Deck outline

Aim for about 12 main slides plus an appendix. A typical order:

1. Problem.
2. Insight and the thesis line.
3. One concrete example, walked through end to end.
4. How it works, as one drawn diagram.
5. What the product outputs.
6. Why now.
7. Competition: a claim as the headline, answering "why not X?".
8. Business model.
9. Market.
10. Founder.
11. The ask, with milestones on a timeline spaced by real time.

The appendix holds trust and security, the risks, the market method and anything else the panels wanted off the main slides. Expected rebuttals go in the speaker notes.

**Checkpoint:** the founder approves the outline and the slide count.

### 6. Choose the style first

Build 3–4 representative slides (title, diagram, numbers, founder) in five clearly different styles side by side, using the `design-variations` and `artifact-design` skills. Then:

1. The founder picks one or combines them.
2. Confirm the combination on the same 3–4 slides.
3. Only then build every slide.

Don't build the full deck before a style is chosen.

### 7. Build the deck

1. Run the Artifact `quickstart` with intent `slides`, then use the Slides type: one `<section>` per slide file, with speaker notes in `<aside>`.
2. Render every slide to PNG, plus a contact sheet, with a local Playwright script.
3. Check the editor's limits before publishing:
   - at most about 24 absolutely positioned children per container;
   - no nested-div layout tricks, which the editor flattens;
   - at most about 200 elements per slide;
   - text at 24px or larger;
   - no `<style>` blocks or margins;
   - SVG labels written as `<p>` elements.

   If a complex diagram breaks, show 3–4 diagram patterns side by side (swimlane, loop, gates, sequence) and let the founder pick.

### 8. Deck panel

**Panel make-up:**

- 3 investors from the plan panels;
- 2 founders;
- 2 people with a strong design or presentation background.

**What they review:** the PNGs, starting with the contact sheet.

**Their brief:**

- a score;
- the flow;
- fixes per slide;
- whether sequential information is easy to follow;
- the single biggest change.

**Their bar:** short, clear, and built on tried-and-true patterns: one idea and one big number per slide, the example before the product's verdict, and timelines spaced by real time.

**Weak slides:** build three versions of each and have the panel pick one and score each version.

**After the panel passes,** every later change the founder asks for also goes back through the panel, and the loop continues until it scores high again.

### 9. Sourcing pass (before the first deck panel, and again before sharing)

Trace every number on the slides, in the notes and in the mockups back to the plan or a source.

- Remove it, or label it "not yet measured", if it can't be traced.
- Mockup data may use only numbers that appear in the plan.
- Recompute every piece of arithmetic shown.

### 10. Voice pass (on the slides and the speaker notes)

Apply the `unslop` skill. Show a table with one row per line: slide, current text, the AI tell, the rewrite. Tells to remove:

- "X, not Y";
- "isn't new; what's new";
- colon-reveal triplets;
- aphorism couplets;
- pairs of rhetorical questions;
- closing lines that restate the headline;
- slogan subheads;
- "only X" superlatives;
- stock words.

The founder may keep one tagline they chose. Run this pass after every panel round: panels introduce these tells themselves.

### 11. Founder slide

Use the founder's own angle and brain dump, not a narrative you've invented.

- **Headings:** plain facts as subheads, with one fact a reader can check.
- **Metrics:** each appears once, as evidence.
- **Avoid:** self-applied labels ("10x engineer"); making a recent role sound long-running; any mention of a future funding round at a current employer.
- **Commitment:** say when the founder goes full time.
- **Charts:** redraw them from real data (for example the GitHub API) with honest labels: partial periods, scope and start markers. Never paste a screenshot carrying another site's branding.

## Done when

- Every panel scores the plan and the deck at 8 or above, and the founder has decided every conflict.
- The sourcing and voice passes are clean on the slides and the notes.
- Placeholders that only the founder can fill are listed for them.
- The deck is published with its link, and can be downloaded as PPTX or PDF from the Slides type.
