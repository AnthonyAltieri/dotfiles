# Motion vocabulary

Exact tokens from `kitlangton/visual-effect`. Apply these before inventing anything. Source files in parentheses. All springs are `motion/react` spring transitions.

The grammar is fixed: which state gets which role, which transition gets which motion, what overshoots and what does not. The values are the fallback for a dark, monospace host with no design system of its own. When the host has tokens, map each role below onto the host's semantic colors (its success, danger, warning, info, and muted roles) and keep the grammar.

## Palette as roles (`constants/colors.ts`, `theme.ts`)

| Role | Fallback value |
| --- | --- |
| idle node | `slate-600` |
| running node | `blue-500` |
| completed node | `green-700` |
| failed node | `#ef4444` |
| interrupted node | `orange-500` |
| death node | `#991b1b` with a 2px `rgba(220,38,38,0.4)` border |
| running glow | `rgba(100,200,255,0.2)`, box-shadow `0 0 24px rgba(59,130,246,0.2)` |
| death glow | `rgba(220,38,38,0.8)` |
| flash overlay | `rgba(255,255,255,0.8)` with `mix-blend-mode: overlay` |
| node border | `rgba(255,255,255,0.1)` |
| text primary / secondary / muted | `#ffffff` / `#a3a3a3` / `#525252` |
| card background | gradient `rgba(23,23,23,0.8)` to `rgba(23,23,23,0.4)`, border `rgba(64,64,64,0.5)` |
| header background | `rgba(38,38,38,0.5)` |
| highlight | bg `rgba(56,189,248,0.15)`, border `rgba(56,189,248,0.6)`, glow `0 0 10px rgba(56,189,248,0.3)` |
| store flash | bg `rgba(59,130,246,0.3)`, border `rgba(59,130,246,1)` |
| notification bubble | `#3b82f6` |
| failure bubble | `rgba(239,68,68,0.95)`, text `red-50` |

Color changes on state transitions take `0.1s easeInOut`; everything else uses a spring.

## Springs (`animations.ts`)

| Name | Settings | Used for |
| --- | --- | --- |
| `defaultSpring` (MotionConfig) | mass 1, stiffness 200, damping `2*sqrt(200)`, bounce 0 | app-wide default, critically damped |
| `springs.default` | stiffness 180, damping 25, mass 0.8 | opacity, border radius, content opacity |
| `springs.bouncy` | bounce 0.3, visualDuration 0.5 | result content entrance |
| `springs.nodeWidth` | stiffness 180, damping 25, mass 0.8, visualDuration 0.6, bounce 0.3 | node widening to fit a result |
| `springs.contentScale` | stiffness 260, damping 18, bounce 0.3, visualDuration 0.5 | pop on completion |
| `springs.failureBubble` | visualDuration 0.2, delay 0.05, bounce 0.3 | error bubble entrance |
| icon swap | stiffness 300, damping 20 | header icon, checkmark |
| highlight | bounce 0, visualDuration 0.2 | floating code highlight |
| stack card move | visualDuration 0.5, bounce 0 | finalizer cards sliding |

Universal enter/exit: `initial={{ scale: 0, filter: "blur(10px)" }}`, `animate={{ scale: 1, filter: "blur(0px)" }}`, exit mirrors initial. Wrap swaps in `AnimatePresence mode="popLayout"`.

Overshoot rule: only `springs.bouncy`, `springs.nodeWidth`, and `springs.contentScale` carry bounce, and only for a result arriving in a node. Everything that moves position, size, or a highlight is `bounce: 0`. Never use CSS `animate-bounce`, elastic keyframes, or a `cubic-bezier` whose y-values leave `[0, 1]`.

## Timing bounds

Sanity bounds for any new motion, taken from Impeccable's `animate` reference and matched against Visual Effect's tokens:

| Duration | Use | Visual Effect example |
| --- | --- | --- |
| 100 to 150ms | immediate feedback | state color change 0.1s, store flash in 0.1s |
| 150 to 300ms | routine state change | highlight move 0.2s, store settle 0.3s, icon swap |
| 300 to 500ms | layout, overlay, arrival | content pop 0.5s, stack slide 0.5s, value odometer 0.35s |
| 500 to 800ms | one authored focal moment | node width spring 0.6s, completion flash fade 1.0s |

Exit faster than entrance. Long feedback reads as latency. CSS fallback easing when no motion library is allowed: `cubic-bezier(0.16, 1, 0.3, 1)` for arrivals, `ease-out` for exits.

## Node (`effect/EffectNode.tsx`, `effect/useEffectMotion.ts`, `effect/nodeVariants.ts`, `effect/EffectOverlay.tsx`, `effect/EffectContent.tsx`)

Static per-state properties live in variants; dynamic ones are motion values. Base size 64x64, radius 8, label 8px below at 0.75rem weight 500 muted, brightening to secondary when not idle.

**Idle**: scale 1, opacity 0.6, slate, white four-point star at half size.

**Running**:
- scale 0.95, opacity 1, blue.
- height springs to `64 * 0.4` (a pill), radius to 15, content hidden. On exit height returns to 64; Visual Effect uses bounce 0.5 here, the overshoot rule caps a size change at 0.
- jitter loop on `requestAnimationFrame`: rotation `±(0.5 + rand*4)` degrees, x `±(0.5 + rand*1.5)` px, y `±(0.1 + rand*0.6)` px, each step 100 to 200ms with `circInOut` rotation and `easeInOut` offsets. Blur is derived from rotation velocity, capped at 2px.
- border pulse: inset 1px `rgba(100,200,255,0.8)` with opacity `[1, 0.3, 1]` over 1.5s, infinite.
- glow pulse: intensity `[1, 5, 1]` over 0.5s, infinite, rendered as box-shadow (never `drop-shadow`), capped at 8px.
- shimmer: six full-height gradient bars at 200% width, `transparent 40% → white 0.5 at 50% → transparent 60%`, `blur(4px)`, `mix-blend-mode: lighten`, translating x from -66% to 50% over 0.8s with delays 0, 0.2 … 1.0, infinite, ease `[0.5, 0, 0.1, 1]`.
- header star spins 360° per 1s `circInOut`, infinite; header button has a radial blue glow scaling `[1, 1.3, 1]` and fading `[0.5, 0, 0.5]` over 2s.

**Just started or just completed**: white flash overlay to 0.6 in 20ms `circOut`, then linear to 0 over 1s.

**Completed**: green, scale 1, opacity 1. Content pops: `contentScale` set to 0 then animates `[1.3, 1]` with `springs.contentScale`; content enters from `opacity 0, scale 0.5, blur 10px` with `springs.bouncy` at stiffness 260 damping 18. Width springs to `scrollWidth + 24` when content exceeds 48px.

**Failed**: red, skull icon. Shake 6 times: x and y `(rand - 0.5) * 8` px, rotation `(rand - 0.5) * 8` degrees, 80ms each, then 300ms `easeOut` return. Failure bubble above the node with the error message, shown 1.5s then hidden unless hovered; hovering a failed node shows it again. Bubble itself shakes 4 times at intensity 4 after a 100ms delay and settles at y -5.

**Interrupted**: orange, warning octagon icon arriving with a spring; Visual Effect uses bounce 0.5, cap it at 0.3 like any other arrival.

**Death**: `#991b1b`, red skull, `contrast(1.2) brightness(0.8)` filter. Glitch: three quick pulses (scale `1 + rand*0.2`, glow `rand*10`) with 20 to 70ms holds and 50 to 150ms pauses, then a subtle loop setting glow between 3 and 7 every 300 to 800ms on idle callbacks.

Performance: `contain: layout style paint`, `willChange: transform, filter`, `transform: translateZ(0)` on the node container.

Reduced motion (`prefers-reduced-motion: reduce`): skip jitter, shake, glitch, flash, the shimmer sweep, the header star spin, and the notification float. Keep the color change, the icon swap, the result content appearing, the store value swap (as an opacity crossfade without the y travel), and the store flash. Every state must still be distinguishable at a glance. Reduced means fewer and gentler, not none.

At rest: an idle card has no running animation at all. The chevrons on an empty stack placeholder and the header glow only animate while their state is running. Never autoplay a run on mount or on scroll.

## Header button (`HeaderView.tsx`)

40x40, radius 6, background is the state color. Icons swap through `AnimatePresence mode="popLayout"` entering with `scale 0, rotate -180, blur 10px` and exiting with `rotate 180`. Hover scales 1.05, press 0.95. Rest icon: four-point star. Hover icon: play when idle, stop when running, counter-clockwise arrow when terminal. Option/Alt plus hover: link icon, indigo `#6366f1`, then a checkmark on `#4f46e5` for 1.5s after copying.

## Store panel (`display/RefDisplay.tsx`)

A pill with the store name in secondary text, a 1px vertical divider, and the value in monospace semibold white.

- On change: background to store flash blue and border to solid blue with `visualDuration 0.1, bounce 0`, then back to `rgba(38,38,38,0.8)` and `rgba(64,64,64,0.5)` with `visualDuration 0.3` once `justChanged` clears (50ms).
- Value swaps through `AnimatePresence mode="popLayout" initial={false}` keyed by `String(value)`: in from `y -8, opacity 0, blur 4px`, out to `y 8, opacity 0, blur 4px`, 350ms `easeOut`. This is the odometer.

For records, render one pill per field and flash only fields that changed. For lists, render one row per id with the same enter/exit and let `popLayout` slide the rest.

## Card stack (`scope/ScopeStack.tsx`, `scope/FinalizerCard.tsx`)

For ordered work such as LIFO cleanup. Container 88px tall with a dashed placeholder and the label `FINALIZERS` flanked by chevrons pulsing opacity `[0.2, 1, 0.2]` over 2s staggered 0.15s.

- Cards are 200px min width, 52px tall, absolutely positioned with `layoutId`.
- Pending cards stack left: `x = index * 35 + 16`. The running card centers and scales 1.05 at z 20. Completed cards stack right in reverse.
- Card enter: `opacity 0, scale 1.2, blur 4px` to normal with `visualDuration 0.3, bounce 0.3`. Exit: `scale 0.8, blur 4px`.
- Colors: pending `neutral-800` on `neutral-700` border; running `blue-900` on `blue-500`; completed `green-900` on `green-500`.
- Running: radial blue pulse over the card `[0, 0.3, 0]` over 2s and over the checkbox `[1, 1.3, 1]` over 1.5s.
- Completed: checkmark rotates in from -180 with stiffness 300 damping 20; a radial green flash fades from 0.8 to 0 while scaling to 1.05 over 0.6s.
- Each step in the original holds 800ms so the reader can follow the order.

## Timeline (`ScheduleTimeline.tsx`)

For repeats and retries. 50px tall, 3px lines, 12px dots, 100 px per second.

- Starts when the result node enters running; the cursor moves each frame from a 50px start offset.
- Segments alternate by the base node's state: blue while running, neutral gap otherwise. The active segment is brighter and springs to the inactive shade when it ends (`visualDuration 0.5, bounce 0.4`). Each running segment opens with a dot scaling in with bounce 0.4.
- Tick marks every 50px in `neutral-800`.
- When the cursor passes 80% of the width the timeline scrolls left.
- On reset everything fades out over 300ms and clears.

## Floating code highlight (`feedback/FloatingHighlight.tsx`)

One absolutely positioned `motion.div` at radius 6. x, y, width, and height are springs (`bounce 0, visualDuration 0.2`); scale springs `stiffness 300, damping 20` from 0.9 to 1; opacity animates linearly and maps to blur 4px to 0. Padding 8px horizontal, 6px vertical around the measured text rects. Hide after a 500ms grace period when the pointer leaves.

## Bubbles (`feedback/NotificationBubble.tsx`, `feedback/FailureBubble.tsx`)

Both sit at `bottom: 100%` centered above the node with a downward arrow.

- Notification: blue, `text-xl`, optional icon. Enters from `opacity 0, scale 0, y 50, blur 10px` with `visualDuration 0.3, bounce 0.1`. Floats between y 0 and y -12 every 0.8s `easeInOut`. Hidden while a failure bubble shows.
- Failure: red, `text-sm` bold, max width 200px, enters with `springs.failureBubble` from `y 20, scale 0.8, blur 5px`.

## Code block (`CodeBlock.tsx`)

`prism-react-renderer` with `oneDark`, transparent background, line height 1.6, `pre-wrap`. Lines are `motion.div`s keyed by index plus content. When the snippet changes, lines that already existed stay; new lines enter from `opacity 0, blur 6px, height 0` and removed lines exit the same way, spring `visualDuration 0.1, bounce 0`.

## Segmented control (`ui/SegmentedControl.tsx`)

Container `neutral-800/50`, radius 8, 4px padding, 1px `neutral-700/30` border. The active indicator is a single sliding pill measured from the active button's rect. Changing a value resets the card's result node so the reader sees the new variant from idle.

## Lint reconciliation

Visual Effect's defaults were designed for a standalone dark site. A docs host with a design system, or with a design linter such as Impeccable's detector, will flag several of them. This table says what each finding means for a card and what to do. Apply it whenever the HOST line of the brief records a design system; on a systemless dark host the fallback values stand.

| Finding (Impeccable rule) | Where Visual Effect has it | Decision |
| --- | --- | --- |
| `dark-glow`: colored blurred shadow on a dark background | running node `0 0 24px rgba(59,130,246,0.2)`, death glow, highlight glow, failure bubble | On a systemed host drop the glows and use the host's elevation shadow. Keep the running border pulse; it carries the state. On the fallback theme the running glow is allowed because it is tied to live state and stops when the run ends. |
| `radial-halo`, `radial-spotlight-glow`: chromatic radial gradient as decoration | header button pulse, stack card running pulse | Keep only while `running`, never at rest. On a systemed host replace with a border or background pulse in the host's info color. |
| `pulsing-dot`: pulsing indicator | running border pulse, glow pulse, empty-stack chevrons | Earned: the pulse is bound to a genuinely live state and stops when it ends. Confirm no pulse survives into a terminal state. |
| `bounce-easing` | `bounce: 0.3` springs | Springs are not CSS bounce curves and the detector does not see them, but the craft rule stands: overshoot only on result arrival, `bounce: 0` elsewhere. |
| `layout-transition`: animating width or height | node height 64 to 25.6 while running, node width growing to fit a result | Bounded exception: the node is 64px, `contain: layout style paint` scopes reflow, and the shape change is the running state's signature. Do not extend the pattern to panels or the card; animate those with transforms or `grid-template-rows`. |
| `gpt-thin-border-wide-shadow`: hairline border plus wide diffuse shadow | the card: 1px border and `shadow-2xl` | Pick one. On a systemed host use the host's card treatment. On the fallback theme keep the border and drop the shadow; the card sits in a docs column, not on a hero. |
| `ai-color-palette`: cyan on dark | highlight `rgba(56,189,248,…)`, running `blue-500` | On a systemed host the highlight and running role take the host's info or accent color. On the fallback theme keep blue for running and use the same blue, not sky, for the highlight. |
| `nested-cards` | store pills, stack cards, config panel inside the card | Sections are separated by 1px rules, not nested cards. Pills and stack cards are the content of their section and the only bordered elements inside it. Do not add a card around the node row or the code block. |
| Monospace as costume (craft floor) | the whole site in mono | Mono for code, node labels, values, failure text. Name and description in the host's body face. |
| Emoji as icons (craft floor) | none; Visual Effect uses Phosphor for icons | Keep it that way. Emoji appear only as result data or store values. Star, skull, warning, play, stop, and reset are drawn icons from one set at one weight. |
| `kicker-above-heading`, `tracked-caps` | `CONCURRENCY` and `FINALIZERS` labels | These are control labels beside a control, not kickers above a heading. Keep them small, keep them beside, and never add a tracked label above the card title. |
| `overused-font` | Inter for OG images only | Take the host's faces. Do not introduce Inter, Geist, or Space Grotesk for the card. |
| Pure black background (craft floor) | `neutral-950` page | The card owns its own surface only; the page ground is the host's. On the fallback theme tint the card gradient toward the host ground rather than pure black. |

When the detector is available (`npx impeccable detect <card files>`), run it once in verification pass one. Fix every finding that is not in this table. For findings in the table marked earned or bounded, record the reason in the PR description in one line each; do not add ignore rules to the host's config without asking.
