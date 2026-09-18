# Dense tables design guide

A portable reference for compact rows, precise numeric alignment, quiet surfaces, and detail
on demand. It originated from a trading workbench, but its roles and examples apply to other
operational applications. The CSS is framework independent.

Treat the dimensions and palette as a baseline. Preserve the destination's existing fonts,
components, semantics, and supported accessibility scale. UI and data are font roles; no named
font family or font download is required.

Read the relevant sections when applying the skill:

- Typography and geometry: section 2.
- Semantic colors and alternative direction colors: section 3.
- Toolbar, columns, and numeric presentation: section 4.
- Page hierarchy, overflow, mobile behavior, and states: sections 5–7.
- Adaptable CSS recipe: section 8.
- Implementation brief and review checklist: section 9.

## 1. Visual character

- Use a neutral work surface with a restrained light or dark palette.
- Group information with alignment, proximity, and 1px rules. Keep table rows flat.
- Put the densest information inside tables and panels. Leave more space between major regions.
- Give text, numbers, and labels distinct typographic roles.
- Use color to communicate interaction, direction, state, and consequence.
- Keep repeated records visually predictable: stable columns, consistent precision, short labels.
- Reveal explanations and secondary properties in an inspection panel.

The density comes from reducing repeated chrome and vertical padding while preserving a clear
reading order. Small type is one ingredient; column design and progressive disclosure do most
of the work.

## 2. Baseline type and spacing scale

### Typography

| Role | Baseline | Application |
| --- | --- | --- |
| UI family | Destination application's UI font; generic sans-serif fallback | Names, controls, headings, prose |
| Data family | Destination application's data font; generic monospace fallback | Numbers, timestamps, identifiers, compact codes |
| Label | 10px | Table headings, metadata, chip labels |
| Table body | 11px | Compact table records |
| UI text | 12px | Controls, descriptions, panel titles |
| Small title | 13px | Empty-state titles and selected detail views |
| Summary value | 18px | Stat tiles |
| Page title | 24px | One primary page heading |
| Weights | 400 / 500 / 600 | Regular / medium / semibold |
| Base line height | 1.5 | Inherited by reference table text; individual controls can override it |
| Label tracking | 0.06em | General uppercase labels |
| Table-header tracking | 0.05em | Table headers |

Font families are intentionally left to the destination application. Preserve the UI and data
roles without introducing a particular typeface or a font download.

Table headers are uppercase, medium weight, and use the subdued `ink3` role. Text
headers use the UI face; columns explicitly marked numeric also apply the data face to their
headers. Body text is regular weight; primary record names can use medium weight.

Use `font-variant-numeric: tabular-nums` with the data face. Right-align quantities and measured
values, including their headers. Timestamps and identifiers may stay left-aligned even though
they use monospace. Let alignment reflect how a column is compared.

### Geometry

| Element | Baseline | Notes |
| --- | --- | --- |
| Comfortable data row | 28px | Default density |
| Compact data row | 23px | Same type size and columns |
| Header cell | 26px | Sticky inside the table scroller |
| Cell horizontal padding | 10px per side | Shared by headers and body |
| Cell vertical padding | 0 | Row height supplies the rhythm |
| Divider / frame border | 1px | Quiet horizontal rules |
| Table / control corner radius | 8px | The table uses the control radius |
| Larger frame radius | 12px | Optional outer framing |
| Standard / small / extra-small control | 28 / 24 / 20px | Desktop button heights |
| Filter chip | 22px high; 8px horizontal padding | Pill shape |
| Badge | 20px high; 7px horizontal padding | Pill shape |
| Toolbar padding | 6px vertical; 10px horizontal | 8px gap between groups |
| Toolbar trailing controls | 6px gap | Pushed to the right |
| Footer | 34px minimum; 5px vertical / 10px horizontal padding | Optional pagination |
| Panel body padding | 10px | Dense local grouping |
| Stat tile padding | 8px vertical; 10px horizontal | 2px internal gap |
| Page padding | 24px desktop; 16px mobile | Space outside the dense content |
| Major page-region gap | 24px | Do not apply this between table rows |

**Row heights are nominal, not hard clipping limits.** HTML table rows expand when content
requires it. A 24px button, two-line identifier, wrapped note, or mobile touch target can make
a compact row taller than 23px. Preserve usable content rather than forcing a fixed height.

For an ideal single-line table with 560px available for body rows, comfortable density fits 20
rows and compact density fits 24. This illustrates the density tradeoff; toolbars, headers,
footers, and taller cells consume additional space.

## 3. Palette and semantic roles

The reference palette uses Catppuccin Latte for light and Macchiato for dark. Map its semantic
roles onto an established palette when one exists; use these values when that visual direction
is requested or the destination needs a starting palette.

| Role | Light | Dark | Meaning |
| --- | --- | --- | --- |
| `ground` | `#e6e9ef` | `#181926` | Page canvas |
| `surface` | `#eff1f5` | `#24273a` | Table and panel background |
| `raised` | `#dce0e8` | `#363a4f` | Hovered rows and raised controls |
| `line` | `#ccd0da` | `#363a4f` | Hairline separators |
| `lineStrong` | `#bcc0cc` | `#494d64` | Stronger control boundaries |
| `ink` | `#4c4f69` | `#cad3f5` | Primary text |
| `ink2` | `#6c6f85` | `#a5adcb` | Secondary text |
| `ink3` | `#8c8fa1` | `#8087a2` | Quiet labels and metadata |
| `accent` | `#1e66f5` | `#8aadf4` | Interaction and focus |
| `accentInk` | `#eff1f5` | `#181926` | Text on primary controls |
| `selection` | `rgba(30,102,245,.14)` | `rgba(138,173,244,.18)` | Selected background wash |
| `up` | `#40a02b` | `#a6da95` | Positive financial direction |
| `down` | `#d20f39` | `#ed8796` | Negative financial direction |
| `good` | `#40a02b` | `#a6da95` | Healthy state |
| `warn` | `#df8e1d` | `#eed49f` | Warning state |
| `serious` | `#fe640b` | `#f5a97f` | Elevated severity |
| `critical` | `#d20f39` | `#ed8796` | Critical state or dangerous consequence |

Keep direction and operational status as separate tokens even when their default colors match.
An increasing metric is not necessarily a healthy metric in another domain: increased latency,
for example, should not inherit a “good” meaning from a positive number.

An alternative blue/orange financial-direction palette uses: light `#1e66f5` / `#fe640b`, dark
`#8aadf4` / `#f5a97f`. This changes money roles independently of status and danger. Retain arrows
and labels so meaning survives either palette.

Keep table surfaces flat. Supporting panels may use a slight tint and small shadow; keep that
treatment at the panel level. For example, quiet PAPER badges are outlined, while LIVE badges
have a critical-color fill and a visible label. In another application, reserve an
equivalent strong treatment for a similarly consequential mode.

## 4. Table anatomy

```text
┌────────────────────────────────────────────────────────────────────────┐
│ Optional tabs with counts                                               │
├────────────────────────────────────────────────────────────────────────┤
│ Search…   State: All 128   Owner: All 8   Reset    [Density] [Columns]    │
├────────────────────────────────────────────────────────────────────────┤
│ RECORD              STATE           UPDATED          COUNT    CHANGE   │
│ Primary name        ● Healthy       09:42:16          1,280    ▲ 2.4%   │
│ Another name        ⚠ Delayed       09:41:08            964    ▼ 0.8%   │
│ …                                                                      │
├────────────────────────────────────────────────────────────────────────┤
│ 50 rows on this page                               [Previous] [Next]    │
└────────────────────────────────────────────────────────────────────────┘
                                      Row inspection → side sheet
```

This is a domain-neutral schematic, not a screenshot. The record names and data are illustrative.

### Toolbar

Place free-text search first, then useful facets, then Reset when constraints are active. Push
density and column visibility to the trailing edge. The reference search field grows from 200px
to a maximum of 16rem; groups wrap when needed.

Inactive facet chips use a dashed border. Active chips use a solid border and selection wash.
Show counts beside the labels, and make the scope of counts explicit. If tab and facet counts
reflect the loaded page, state that in the footer.

### Columns and cells

Use this portable column order as a starting point:

1. Primary identity: a readable name, with an optional subdued ID below it.
2. State and category: short, labeled, easy to compare down the column.
3. Context: owner, source, version, timestamp, or domain equivalent.
4. Comparable metrics: right-aligned, with consistent units and precision.
5. Explicit actions: a small, stable group at the trailing edge.

Start with natural table layout, full width, and a 48rem minimum for a wide comparison table.
Choose the actual minimum for the destination's columns and data; preserve readable columns
rather than widening the entire document.

Keep cells on one line by default. Allow intentionally verbose columns, such as notes, to wrap.
Use a second line sparingly for identity context. For long prose, show a short summary and put
the full value in inspection. If you truncate important content, provide a keyboard-accessible
way to read the complete value.

Use horizontal row separators without default zebra striping. Hover uses `raised`; a selected
record can use `selection`. Distinguish selection from opening an inspector, and expose the
appropriate expanded or selected state to assistive technology.

### Numbers

- Align a numeric column's header and body to the right.
- Use the data font and tabular digits so updates do not disturb comparison.
- Keep precision consistent within a metric, while preserving domain-required precision.
- Show units where the user can understand every value without guessing.
- Pair financial direction with a glyph and text: `▲ $4,182`, `▼ $1,940`.
- Distinguish missing, unavailable, and zero. Choose a consistent convention, such as an explicit
  “Unavailable” label, that fits the domain.
- Keep primary values legible; use subdued text for genuinely secondary information.

## 5. Information density beyond the table

Keep page identity and the primary action above the working area. When a detail view needs
metrics, a chart, and a ledger, arrange compact summary metrics first, chart with evidence next,
then a tabbed ledger or detail region. Omit regions the task does not need.

Use summary tiles for the few metrics that orient the user. Each tile has a label, value,
optional delta against a **named comparison**, and optional context. “+2.4% vs yesterday” is
more useful than an unexplained “+2.4%.” Keep the individual-record evidence in the table.

Put verbose explanations, raw identifiers, settings, and secondary actions in a sheet or
disclosure. A useful inspection-sheet baseline is full width on narrow screens and a 28rem
cap from a 640px viewport; adjust it for the actual content.

Transfer the same hierarchy to other domains: jobs and execution traces, orders and line
items, incidents and event timelines, or experiments and measurements.

## 6. Scrolling and responsive behavior

For a viewport-filling desktop workbench, keep navigation and page identity visible while
route content scrolls internally. A table owns its own horizontal and vertical overflow.
Its header stays sticky at the top of that local scroll region.

The reference scroller uses `overflow: auto`, `min-height: 13rem`, and
`max-height: min(60vh, 32rem)`. Fill layouts can override the height cap. Use `min-width: 0`
and `min-height: 0` along the relevant flex/grid containment chain so the content can shrink
and scroll inside its allocated region.

Below 768px, document scrolling remains available. Use a 320px containment floor where appropriate;
buttons have at least 44px targets, and inputs/selects have a minimum 44px height with 16px
text. These mobile rules intentionally take precedence over desktop density. Wide comparison
tables scroll horizontally inside their frame rather than widening the whole document.

For a port, check that the last row and every action remain reachable in a short viewport,
at text zoom, and on a narrow screen. Raise the type scale where the destination audience
needs it, then let rows expand. Check text contrast in both themes, especially subdued small
labels; density depends on legibility as well as the number of visible rows.

## 7. Interaction and changing data

| Situation | Behavior to carry over |
| --- | --- |
| Inspect a row | Open a sheet; preserve the table's context and scroll position |
| Navigate to a record | Provide a separate explicit link |
| Keyboard use | Visible focus; Enter/Space activation for interactive rows; restore focus after inspection |
| Embedded action | Activating its button/link must not also open the row inspector |
| Sort | Keep the control in the header; show direction and expose `aria-sort` |
| Select a ledger event | Synchronize the relevant chart/evidence when the destination has linked views |
| First load | Use skeletons with the same table geometry |
| No records | Explain how to create or obtain the first record |
| No matches | Preserve the controls and offer Clear filters |
| Refresh failure | Preserve last good data and show a recoverable inline error |
| Stale data | Label the age or coverage explicitly |
| Changed live value | Flash only that value: 500ms directional wash, then 1s fade |
| Reduced motion | Update the value without the flash animation |

Wire keyboard inspection and selection to the destination's components. Loading, stale-data,
and recovery states must follow the existing data lifecycle. Skip live-value animation on
mount and when the value has not changed.

For a new application, put meaningful view state—filters, sorting, tab, pagination—in the URL
when views need to be shareable. Treat density and column visibility as presentation preferences.
Move filtering and pagination to the server as the collection grows beyond a practical client
working set. Treat server-side filtering as a separate implementation decision when it exceeds
the presentation task. Do not imply a global count when only a page has been loaded.

## 8. Portable CSS starting point

This recipe translates the reference table's visual core into ordinary CSS. It is a starting point,
not an exported component: map font roles to existing typography, set `data-theme` from your
application's light/dark preference, and implement the toolbar, formatting, selection, keyboard,
and inspection behavior in your existing stack. Resolve the initial theme from the OS when the
user has no explicit preference.

```css
:root {
  color-scheme: light;
  --ground: #e6e9ef;
  --surface: #eff1f5;
  --raised: #dce0e8;
  --line: #ccd0da;
  --ink: #4c4f69;
  --ink-secondary: #6c6f85;
  --ink-muted: #8c8fa1;
  --accent: #1e66f5;
  --selection: rgba(30, 102, 245, 0.14);
  --ui-font: ui-sans-serif, system-ui, sans-serif;
  --data-font: ui-monospace, monospace;
}

:root[data-theme="dark"] {
  color-scheme: dark;
  --ground: #181926;
  --surface: #24273a;
  --raised: #363a4f;
  --line: #363a4f;
  --ink: #cad3f5;
  --ink-secondary: #a5adcb;
  --ink-muted: #8087a2;
  --accent: #8aadf4;
  --selection: rgba(138, 173, 244, 0.18);
}

.table-frame,
.table-frame * {
  box-sizing: border-box;
}

.table-frame {
  min-width: 0;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--surface);
  color: var(--ink);
  contain: paint;
}

.table-scroll {
  overflow: auto;
  min-height: 13rem;
  max-height: min(60vh, 32rem);
}

.dense-table {
  width: 100%;
  min-width: 48rem;
  border-collapse: collapse;
  font-family: var(--ui-font);
  font-size: 11px;
  line-height: 1.5;
}

.dense-table th,
.dense-table td {
  padding: 0 10px;
  border-bottom: 1px solid var(--line);
  text-align: left;
  white-space: nowrap;
}

.dense-table th {
  position: sticky;
  top: 0;
  z-index: 1;
  height: 26px;
  background: var(--surface);
  color: var(--ink-muted);
  font-size: 10px;
  font-weight: 500;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.dense-table td { height: 28px; }
[data-density="compact"] .dense-table td { height: 23px; }
.dense-table tbody tr:hover { background: var(--raised); }
.dense-table tbody tr[data-selected="true"] { background: var(--selection); }

.dense-table [data-align="numeric"] {
  text-align: right;
  font-family: var(--data-font);
  font-variant-numeric: tabular-nums;
}

.dense-table tbody tr:focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: -2px;
}

.table-frame :is(button, a, input, select):focus-visible {
  outline: 2px solid var(--accent);
  outline-offset: 1px;
}

@media (max-width: 767px) {
  .table-frame :is(button, .row-action) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 44px;
    min-height: 44px;
  }
  .table-frame :is(input, select) {
    min-height: 44px;
    font-size: 16px;
  }
}
```

Apply `data-density="comfortable"` or `"compact"` to `.table-frame`; put `.dense-table` inside
`.table-scroll`. Use a semantic `<table>` with an accessible name and `<th scope="col">`.
Add `data-align="numeric"` to both the header and each cell of a numeric column. Only make rows
focusable when they perform an action; preserve ordinary links and buttons inside cells.

## 9. Copyable implementation brief

> Apply a dense operational workbench style to this application. Preserve its existing UI and
> data fonts, using tabular digits for data. Start with 11px table text, 10px uppercase headers,
> 28px comfortable rows, 23px compact rows, and 10px horizontal cell padding. Use neutral light
> and dark surfaces, 1px horizontal rules, and 8px table corners. Keep page-level spacing generous
> enough to separate regions while keeping repeated records compact. Right-align comparable
> numbers and their headers. Use color for interaction, direction, status, and danger, always
> with a visible label or glyph. Include search, counted facets, conditional Reset, density,
> column visibility, and clearly scoped pagination. Keep table headers sticky inside a bounded
> scroller. Row inspection should preserve context; navigation should be explicit. Put secondary
> details in an inspection panel. Maintain keyboard access, visible focus, readable states, and
> 44px mobile targets. Adapt domain labels and metrics to this application and implement these
> rules using its existing framework and components.

### Transfer review checklist

- [ ] A realistic table is scannable by identity, state, and metric without opening each record.
- [ ] Text and numeric columns align consistently; units and missing values are unambiguous.
- [ ] Both density modes work with real names, badges, buttons, and long values.
- [ ] Hover, focus, selection, status, and value direction remain distinguishable.
- [ ] The toolbar stays usable at narrow widths, and wide tables scroll within their frame.
- [ ] Inspection opens and closes by keyboard and returns focus to the invoking control or row.
- [ ] Loading, empty, no-match, stale, and error states preserve useful context.
- [ ] Both themes, text zoom, short viewports, and mobile targets have been checked.
- [ ] Live updates preserve layout and honor reduced motion where applicable.
