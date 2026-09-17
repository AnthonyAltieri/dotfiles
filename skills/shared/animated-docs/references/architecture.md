# Architecture

Distilled from `kitlangton/visual-effect`. File names in parentheses point at the source of each rule. Sketches are React plus `motion/react` and use generic names; swap in the host site's types.

## 1. Observable model, not React state

Every tracked thing is a plain class that owns its state and a listener set. React subscribes through `useSyncExternalStore`. The model never imports React components, and components never mutate model fields directly. (`VisualEffect.ts`, `VisualRef.ts`, `VisualScope.ts`)

```ts
export type NodeState<A, E> =
  | { type: "idle" }
  | { type: "running" }
  | { type: "completed"; result: A }
  | { type: "failed"; error: E }
  | { type: "interrupted" }
  | { type: "death"; error: unknown }

const VALID_TRANSITIONS: Record<NodeState<unknown, unknown>["type"], Set<string>> = {
  idle: new Set(["running", "idle"]),
  running: new Set(["completed", "failed", "interrupted", "death", "idle", "running"]),
  completed: new Set(["idle", "running", "completed"]),
  failed: new Set(["failed", "idle", "running"]),
  interrupted: new Set(["interrupted", "idle", "running"]),
  death: new Set(["death", "idle", "running"]),
}

class Observable {
  private listeners = new Set<() => void>()
  subscribe(listener: () => void) {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }
  protected emit() {
    for (const l of this.listeners) l()
  }
}
```

Hooks are granular so a node re-renders only for its own state (`VisualEffect.ts` bottom):

```ts
export function useNodeState<A, E>(node: VisualNode<A, E>) {
  return useSyncExternalStore(node.subscribe.bind(node), () => node.state)
}
```

Track transitions with a previous-state ref so one-shot animations fire on the edge, not the level (`hooks/useStateTransition.ts`):

```ts
export function useStateTransition(state: { type: string }) {
  const prev = useRef(state.type)
  useEffect(() => { prev.current = state.type }, [state.type])
  return {
    justStarted: prev.current !== "running" && state.type === "running",
    justCompleted: prev.current !== "completed" && state.type === "completed",
    justFailed: prev.current !== "failed" && state.type === "failed",
  }
}
```

## 2. The entity wrapper runs the real code

`VisualNode` wraps a real unit of work. Calling `.program` returns the same work with transitions attached. Composed programs are built from the children's `.program`, so running the parent lights up the children in the order and concurrency the real library decides. (`VisualEffect.ts`)

Rules carried over from the source:

- **Terminal states short-circuit.** If a node is already completed, `.program` returns its cached result; if failed, the cached failure. A parent that reruns does not re-execute finished children.
- **Parent-child registration.** When a child's program runs inside a parent, it registers itself with the parent through context (an Effect service in the original; React-free DI in any port). `reset()` on the parent resets registered children first, then clears the set.
- **Reset guard.** `isResetting` suppresses transitions while the fiber or promise is being cancelled, so a late `interrupted` does not overwrite `idle`.
- **Interrupt optimistically.** `interrupt()` sets `interrupted` immediately for the UI and then cancels the underlying work.
- **Timing.** When `showTimer` is on, record `startTime` on entering `running` and `endTime` on leaving it. The label under the node shows elapsed milliseconds.
- **Notifications.** A node can publish a short message with an optional icon and a duration (default 2s). The view shows it as a bubble above the node. Use it for mid-run facts such as "attempt 3" or "cache hit".

Promise-based sketch for hosts without Effect:

```ts
class VisualNode<A, E = unknown> extends Observable {
  state: NodeState<A, E> = { type: "idle" }
  private controller: AbortController | null = null
  private children = new Set<VisualNode<unknown, unknown>>()
  private isResetting = false

  constructor(public name: string, private work: (signal: AbortSignal) => Promise<A>, public showTimer = false) { super() }

  program = async (signal?: AbortSignal): Promise<A> => {
    if (this.state.type === "completed") return this.state.result
    if (this.state.type === "failed") throw this.state.error
    this.controller = new AbortController()
    const linked = signal ? anySignal([signal, this.controller.signal]) : this.controller.signal
    this.setState({ type: "running" })
    try {
      const result = await this.work(linked)
      this.setState({ type: "completed", result })
      return result
    } catch (error) {
      if (linked.aborted) { this.setState({ type: "interrupted" }); throw error }
      if (isDefect(error)) { this.setState({ type: "death", error }); throw error }
      this.setState({ type: "failed", error: error as E })
      throw error
    }
  }

  run() { return this.program().catch(() => {}) }
  interrupt() { if (this.state.type === "running") { this.setState({ type: "interrupted" }); this.controller?.abort() } }
  reset() {
    this.isResetting = true
    try { for (const c of this.children) c.reset(); this.children.clear(); this.controller?.abort() }
    finally { this.isResetting = false }
    this.setState({ type: "idle" })
  }

  private setState(next: NodeState<A, E>) {
    if (this.isResetting) return
    if (!VALID_TRANSITIONS[this.state.type].has(next.type)) {
      if (process.env.NODE_ENV === "development") console.warn(`invalid ${this.state.type} -> ${next.type} on ${this.name}`)
      return
    }
    this.state = next
    this.emit()
  }
}
```

When the concept is Effect, Zio, Rx, XState, or another library with its own fibers and cancellation, wrap with that library's primitives instead and let it own interruption. Do not reimplement the library's semantics in the wrapper.

## 3. Stores hold the data model

A store is the observable that answers "show how the data model changes". It mirrors a real piece of state (a `Ref`, a reducer's store, a database row) and records a `justChanged` pulse for 50ms after each write so the view can flash. (`VisualRef.ts`, `display/RefDisplay.tsx`)

```ts
class VisualStore<A> extends Observable {
  private current: A
  justChanged = false
  private pulse: ReturnType<typeof setTimeout> | null = null
  constructor(public name: string, private initial: A) { super(); this.current = initial }
  get value() { return this.current }
  set(next: A) {
    if (Object.is(next, this.current)) return
    this.current = next
    this.justChanged = true
    if (this.pulse) clearTimeout(this.pulse)
    this.pulse = setTimeout(() => { this.justChanged = false; this.emit() }, 50)
    this.emit()
  }
  update(fn: (a: A) => A) { this.set(fn(this.current)); return this.current }
  reset() { if (this.pulse) clearTimeout(this.pulse); this.current = this.initial; this.justChanged = false; this.emit() }
}
```

Two ways to feed it, in order of preference:

1. **Route real writes through it.** The composed program calls `store.update(...)` where the real code would update state. The original does this with `Ref.updateAndGet` wrapped so the ref write and the visual write are one step.
2. **Subscribe to the real store.** If the product exposes a subscribe API (Redux, Zustand, XState actor, a database change feed), subscribe and mirror each change into `VisualStore.set`.

For records and lists, keep a `VisualStore<Record<string, unknown>>` or `VisualStore<Array<Row>>` and let the panel diff by key. Rows need stable ids so `AnimatePresence` can animate enter and exit per row.

## 4. Scene contract

One component renders every card so all cards share layout and behavior. Props from `display/EffectExample.tsx`, renamed generically:

```ts
interface ExplainerProps<A, E> {
  id: string                          // deep-link id, matches the manifest
  name: string                        // "Effect.race"
  variant?: string                    // "exponential" shown muted after the name
  description: ReactNode              // imperative, no trailing period
  code: string                        // the snippet to teach
  nodes: Array<VisualNode<unknown, unknown>>   // input nodes, left to right
  resultNode?: VisualNode<A, E>       // right of the arrow; drives the header button
  highlightMap: Record<string, { text: string } | undefined>  // node.name -> substring of `code`
  configPanel?: ReactNode             // segmented control that changes code and program
  stores?: Array<VisualStore<unknown>>
  timeline?: boolean                  // schedule timeline under the nodes
  stack?: VisualStack                 // LIFO cleanup cards under the nodes
}
```

Layout order inside the card: header, config panel, store panel, node row, timeline or stack, code block. Each section is separated by a 1px border in the card's border color. A single-node card omits the arrow and result.

### DOM contract

Every rendered piece of model state carries a data attribute so tests, the headless script, and the finish reviewer can assert on the DOM instead of reading pixels:

| Element | Attributes |
| --- | --- |
| card root | `data-explainer="<id>"` |
| node wrapper | `data-node="<name>" data-state="idle|running|completed|failed|interrupted|death"` |
| header button | `data-control="run|stop|reset"` reflecting what a click would do now |
| store pill or row | `data-store="<name>" data-changed="true|false"` |
| stack card | `data-finalizer="<name>" data-state="pending|running|completed"` |

Set them from the same state the animations derive from. Nothing else may write them.

### Static fallback

The card is client-only, but the page must read without it. Render the header text, the description, and the code block on the server as plain markup, and let the client component replace that region when it mounts. A reader with scripts off, a crawler, and a reader whose script failed all see the concept name, the description, and the snippet. Never ship a card whose content sits at opacity 0 until a script reveals it.

```tsx
// server component or MDX
<ExplainerShell id="effect-race" name="Effect.race" description="Race two effects and return the first successful one" code={code}>
  <ClientExplainer id="effect-race" />   {/* dynamic(..., { ssr: false }); replaces the shell's body on mount */}
</ExplainerShell>
```

### Content ranges

Decide these in the brief's RANGES line and enforce them in the scene component:

- **Nodes per row:** five inputs plus the result at desktop. Inputs wrap to a second row on narrow widths; the arrow and result stay on the last row. More than five means the scene should aggregate (one `writers` node with a count) or split into two cards.
- **Result width:** the node widens to `scrollWidth + 24`, capped at 200px. Longer strings truncate with an ellipsis and carry the full text in `title`. Prefer a renderer that summarizes (`[5]`, `72°`) over a long string.
- **Store values:** a pill holds one line. Records render one pill per field; lists render one row per id with the same enter and exit motion. A value longer than 24 characters wraps inside the pill; the pill never grows past the card width.
- **Failure text:** one line, 200px max width in the bubble, full text on hover.
- **Mobile:** the card fills the column, nodes wrap, the code block soft-wraps, the highlight still measures from the wrapped rects.

The header button (`HeaderView.tsx`) is the only control:

```ts
const onClick = () => {
  if (state.type === "running") node.interrupt()
  else if (isTerminal(state)) { node.reset(); stores.forEach(s => s.reset()) }
  else node.run()
}
```

Icon at rest is a four-point star that spins while running. On hover it becomes play, stop, or reset according to state. The button's background is the state color. Holding Option/Alt while hovering turns it into a copy-link button for the card's deep link; keep this if the site has per-card routes.

## 5. Code block and hover highlight

The code block is syntax-highlighted (`prism-react-renderer`, `oneDark`) with no background so it sits on the card. When the snippet changes because of a config option, unchanged lines stay and new lines blur in through `AnimatePresence mode="popLayout"` keyed by line content. (`CodeBlock.tsx`)

Hover linking (`feedback/FloatingHighlight.tsx`, `display/EffectExample.tsx`):

1. Each node wrapper sets `hoveredNode = node.name` on enter and `null` on leave.
2. Show the highlight immediately, hide it 500ms after leave so moving between nodes does not flicker.
3. Look up `highlightMap[hoveredNode].text`, walk the `<pre>` text nodes with a `TreeWalker`, find the substring, build a `Range`, union its `getClientRects()`, and position one absolutely placed `motion.div` over it with 8px horizontal and 6px vertical padding.
4. Position and size are springs; opacity animates linearly and drives a blur from 4px to 0.

Highlight targets must be exact substrings of the snippet. When several nodes share the same code (five concurrent `increment` calls), they can share the same target.

## 6. Example file template

One file per card, named by concept (`effect-race.tsx`, `ref-update-and-get.tsx`). Memoize every node so re-renders do not recreate them. (`examples/*.tsx`, `hooks/useVisualEffects.ts`)

```tsx
"use client"
export function RaceExplainer({ id, metadata }: ExplainerComponentProps) {
  const { tortoise, achilles } = useVisualNodes({
    tortoise: () => loadEmoji("🐢"),
    achilles: () => loadEmoji("🏃‍♂️"),
  })
  const winner = useMemo(() => new VisualNode("winner", signal => race([tortoise.program, achilles.program], signal)), [tortoise, achilles])

  const code = `const tortoise = runFast("tortoise")
const achilles = runFast("achilles")

const winner = Effect.race(tortoise, achilles)`

  const highlightMap = useMemo(() => ({
    tortoise: { text: 'runFast("tortoise")' },
    achilles: { text: 'runFast("achilles")' },
    winner: { text: "Effect.race(tortoise, achilles)" },
  }), [])

  return <Explainer id={id} name={metadata.name} description={metadata.description} code={code}
    nodes={useMemo(() => [tortoise, achilles], [tortoise, achilles])} resultNode={winner} highlightMap={highlightMap} />
}
```

Manifest entry (`lib/examples-manifest.ts`), the single source of order and sections:

```ts
{ id: "effect-race", name: "Effect.race", description: "Race two effects and return the result of the first successful one", section: "concurrency" }
```

Results render through a small renderer protocol so a node can show an emoji, a number, a temperature, or an array summary without the node knowing the type (`renderers/RenderableResult.ts`): any object with `render(): ReactNode`. The node widens to `scrollWidth + 24` when the rendered result overflows 48px.

## 7. Delays and determinism

Delays live only in stubbed I/O boundaries the story names as a wait. The real computation under explanation runs at its real speed. The exception is an ordered progress surface (the cleanup stack holds each finalizer 800ms so the order reads); declare that hold in the brief's BEAT line.

Stub I/O with jittered delays so each run differs (`examples/helpers.ts`):

```ts
export const getDelay = (min: number, max: number, random = Math.random) => Math.floor(random() * (max - min + 1)) + min
```

Typical ranges: 500 to 900ms for a fetch, 1500 to 2000ms for something that should time out against a 1s limit, 400 to 800ms for a retry attempt. Attempt counters live in module scope and are reset in the composed program's `ensuring`/`finally`, so "first attempt fails, second succeeds" survives a reset.

Inject `random` and `now` from a context or module-level setter so tests and screenshot scripts can pin them. Never sleep in tests; drive the model directly and assert transitions.

## 8. Host integration

- **Client-only mount.** Motion values and `window` listeners break SSR. In Next.js wrap the app content in `dynamic(() => import(...), { ssr: false })`; in Astro use `client:only="react"`; in Docusaurus wrap in `<BrowserOnly>`. (`app/ClientAppContent.tsx`)
- **Routes.** The original renders every card on one page and treats `/<id>` as a scroll target, so running cards keep state while the URL changes. Prefer that over remounting per route.
- **Fonts and theme.** Monospace throughout, near-black background, neutral card gradients. Inherit the host's tokens if it has them.
- **Sound.** Optional. If added, gate every cue behind a mute flag that defaults to off and expose one toggle in the page header.

## 9. Headless verification recipe

Drive the built site with Chrome's remote debugging port and Node's built-in `WebSocket`, no extra dependencies. The script navigates, finds the card by its `data-explainer` id, clicks its header button, captures three screenshots, and asserts the DOM contract at each capture so a screenshot cannot lie about the state it claims to show. Run it once at 1400px and once at 390px.

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --remote-debugging-port=9222 --user-data-dir=/tmp/explainer-profile about:blank &
sleep 3 && node verify-explainer.mjs && kill %1
```

```js
// verify-explainer.mjs
const target = (await (await fetch("http://127.0.0.1:9222/json/list")).json()).find(t => t.type === "page")
const ws = new WebSocket(target.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.onmessage = e => { const m = JSON.parse(e.data); pending.get(m.id)?.(m); pending.delete(m.id) }
const send = (method, params = {}) => new Promise(r => { pending.set(++id, r); ws.send(JSON.stringify({ id, method, params })) })
await new Promise(r => (ws.onopen = r))
const sleep = ms => new Promise(r => setTimeout(r, ms))
const shot = async name => { const { result } = await send("Page.captureScreenshot", { format: "png" }); (await import("node:fs")).writeFileSync(`/tmp/${name}.png`, Buffer.from(result.data, "base64")) }
const [, url = "http://localhost:3000/effect-race", id = "effect-race", width = "1400"] = process.argv
const card = `[data-explainer="${id}"]`
const states = async () => (await send("Runtime.evaluate", { expression: `JSON.stringify([...document.querySelectorAll('${card} [data-node]')].map(n => [n.dataset.node, n.dataset.state]))`, returnByValue: true })).result.result.value
const expect = (cond, msg) => { if (!cond) { console.error("INVALID EVIDENCE:", msg); process.exit(1) } }
await send("Page.enable"); await send("Emulation.setDeviceMetricsOverride", { width: Number(width), height: 1100, deviceScaleFactor: 1, mobile: Number(width) < 600 })
await send("Page.navigate", { url }); await sleep(6000)
expect((await send("Runtime.evaluate", { expression: `!!document.querySelector('${card}')`, returnByValue: true })).result.result.value, `card ${id} not found`)
let s = JSON.parse(await states()); expect(s.every(([, st]) => st === "idle"), `idle capture has non-idle nodes: ${JSON.stringify(s)}`)
await shot(`idle-${width}`)
await send("Runtime.evaluate", { expression: `(() => { const b = document.querySelector('${card} [data-control="run"]'); b.scrollIntoView({ block: 'center' }); b.click() })()` })
await sleep(350); s = JSON.parse(await states()); expect(s.some(([, st]) => st === "running"), `running capture shows no running node: ${JSON.stringify(s)}`)
await shot(`running-${width}`)
await sleep(2500); s = JSON.parse(await states()); expect(s.every(([, st]) => st !== "running"), `done capture still running: ${JSON.stringify(s)}`)
await shot(`done-${width}`)
console.log("states at done:", s)
ws.close(); process.exit(0)
```

Expected: idle nodes are slate with a star, running nodes are blue pills with a shimmer, the completed result is green with content, losers of a race are orange with a warning icon. A non-zero exit means the capture set is invalid and must be retaken after the cause is fixed; never review from a capture whose asserted state failed.
