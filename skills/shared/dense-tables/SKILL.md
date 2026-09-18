---
name: dense-tables
description: Design and implement compact data tables and information-dense operational workbenches. Use for dense table layouts, dashboards, ledgers, record inspection, or transferring this presentation style to another application. Does not cover spreadsheet artifacts or backend query optimization.
metadata:
  short-description: Build compact, readable operational tables
---

# Dense tables

Build scannable tables with compact rows, stable numeric alignment, quiet surfaces, and detail
on demand. Increase the amount of useful information visible without obscuring actions or meaning.

## Fit the destination

- Inspect the existing table, design tokens, controls, responsive layout, and data states first.
- Preserve the application's framework, component library, palette, and typography unless the
  user requests changes. Reuse existing controls and formatting boundaries.
- Treat fonts as UI and data roles. Use the destination's fonts with generic fallbacks;
  do not prescribe, install, or download a named typeface.
- Match the requested deliverable: a design document stays a document; an implementation request
  gets working components. Keep business logic and unrelated screens outside a presentation task.

## Apply the style

Start with the compact scale below when the destination has no established density scale.
Read [the design guide](references/design-guide.md) when choosing exact spacing, light/dark
colors, table anatomy, scroll containment, or a framework-neutral CSS starting point.

| Element | Baseline |
| --- | --- |
| Body / header / UI text | 11px / 10px / 12px |
| Comfortable / compact row | 28px / 23px |
| Sticky header | 26px |
| Cell padding | 0 vertical, 10px horizontal |
| Rules / table corners | 1px / 8px |
| Mobile interactive targets | At least 44px |

These are starting dimensions, not clipping limits. Reduce redundant chrome and padding before
shrinking legible type. Let multi-line cells, buttons, zoom, and mobile targets expand rows.

- Place identity first, then state and context, comparable metrics, and trailing actions.
  Use short secondary identity text; move verbose properties into an inspection panel.
- Right-align numeric headers and cells. Use tabular digits, consistent metric precision,
  explicit units, and an unambiguous missing-value convention. Preserve exact domain values.
- Separate regions with alignment and quiet horizontal rules. Use flat rows and neutral hover
  treatment; distinguish focus, selection, and state without decorating every cell.
- Keep interaction, value direction, and operational status as separate semantic roles. Pair
  color with labels or glyphs. Map increasing values to domain meaning, not automatic success.
- Add search, counted facets, conditional Reset, density, and column visibility where useful.
  State whether counts refer to the loaded page or the full collection.
- Make table headers sticky inside bounded scroll regions. Keep wide tables inside their frame
  and preserve access to the last row and every action. Let mobile pages scroll naturally.
- Use row inspection to preserve context and an explicit link for full navigation. Support
  keyboard activation, visible focus, and focus restoration; embedded controls act independently.
- Preserve useful data during refreshes. Distinguish first load, empty collection, no matches,
  stale data, and recoverable errors using the application's existing data lifecycle.
- Where live values exist, animate only changed cells and honor reduced motion. Keep long
  explanations and uncommon controls available through progressive disclosure.

## Verify the result

For implementation work, inspect realistic long names, numeric precision, missing values,
multi-line cells, and row actions in both density modes. Check the supported themes, narrow and
short viewports, text zoom, keyboard inspection, and scroll reachability. Run the destination's
affected checks. For design-only work, supply concrete dimensions and interaction/state rules
without claiming runtime verification.

Report the delivered artifact or changed components, any deliberate departures from the baseline,
and the checks actually performed. This skill does not authorize publishing or deploying a UI.
