# Scene catalog

Every card in `kitlangton/visual-effect` is one of the scenes below. Pick the scene first, then the story, then the code snippet. A request usually names the scene indirectly; the mapping table translates.

## Mapping a request to a scene

| The request says | Scene |
| --- | --- |
| "what does X return", "what happens when X fails", one operation in isolation | 1. Single node |
| "combine", "run these together", "sequential vs parallel", "collect results" | 2. Pipeline |
| "first one wins", "cancel the others", "fastest response" | 3. Race |
| "fallback", "timeout", "retry", "recover", "what if it fails" | 4. Recovery |
| "every N seconds", "keep retrying with backoff", "poll until" | 5. Schedule |
| "how the data model changes when the user does Y", "shared state", "concurrent writers", "what the store looks like after each step" | 6. Data model |
| "cleanup order", "resource lifecycle", "acquire and release", "teardown" | 7. Lifecycle stack |

Scenes compose. A retry with backoff is Recovery plus Schedule. A cart checkout that writes to a store then hits a flaky payment API is Data model plus Recovery.

Every scene lists its teaching beat and its endings. The beat is the one transition the card is built to make legible; it goes in the brief's BEAT line and nothing else may animate at the same instant. The endings go in the brief's ENDINGS line and each must be reachable in verification.

## 1. Single node

One node, no arrow. Teaches a constructor or a primitive: succeed, fail, die, sleep, sync, promise.

- Teaching beat: the node lands on its terminal color and icon. Hold nothing; the color is the lesson.
- Endings: completed, failed, or death. Interrupt is possible during the delay.

- Entities: one node named for the value it produces (`value`, `error`, `death`).
- Driver: the primitive itself, often with a 500 to 900ms delay so the running state is visible.
- Snippet: one line, `const value = Effect.succeed(42)`.
- Story: keep it literal. The teaching is the color and icon the node lands on.

## 2. Pipeline

Inputs left, arrow, result right. Teaches combining independent work: `all`, `forEach`, `validate`, `partition`.

- Teaching beat: the order and overlap in which the inputs turn blue. Sequential lights them one at a time, unbounded lights them all at once, numbered lights two at a time. The result turns green only after the last input.
- Endings: all inputs completed and the result green; one input failed and the rest interrupted (short-circuit); every input finished and the result red (accumulate); reader interrupt.

- Entities: three to five input nodes plus one result node.
- Driver: the combinator over the inputs' programs. The result node's content is a summary renderer of the inputs' results (an array length, a list of temperatures).
- Config panel: a segmented control for the variable the concept is about. Visual Effect's `Effect.all` offers `sequential | numbered | unbounded`; changing it rewrites the snippet, changes the program's options, and resets the result node. The highlight target for the result moves to the option text (`concurrency: 2`).
- Story: several cities' weather, several files to read. Inputs should be interchangeable so the reader watches order and concurrency, not content.
- Failure variants: short-circuit (one input fails red, the rest turn orange as they are interrupted) versus accumulate (all inputs finish, the result is red with every error).

## 3. Race

Pipeline layout where losers end orange. Teaches cancellation as a first-class outcome.

- Teaching beat: the moment the first input turns green and the others snap to orange in the same frame. Make sure nothing else animates at that instant.
- Endings: one winner and the rest interrupted; every input failed and the result red; reader interrupt turns all of them orange.

- Entities: two to four inputs with overlapping delay ranges so any of them can win, one `winner` node.
- Driver: the library's race primitive. Interruption of losers must come from the library, not from the wrapper.
- Story: tortoise and Achilles, cat and dog and mouse. Emoji results make the winner legible at a glance.
- Check: run it several times and confirm each input wins sometimes. If one always wins, widen the jitter.

## 4. Recovery

Pipeline layout where the input fails and the result recovers, or the input hangs and the result times out.

- Teaching beat: the result turns red or green while the input is still visibly in the state that caused it. For timeout, the result goes red while the input is still running and the input then turns orange. For retry, the input flashes red and returns to blue while the result stays blue.
- Endings: recovered on a later attempt; gave up after the schedule and the result red; timed out and the input interrupted; reader interrupt.

- Entities: one or two inputs plus a result.
- Driver: `orElse`, `timeout`, `retry`, `eventually`, `firstSuccessOf`, or the product's equivalent.
- Attempt counter: module-scope counter reset in the composed program's `finally`. First attempt slow (1500 to 2000ms against a 1s timeout) so the reader sees a red result; second attempt fast (400 to 700ms) so the next run succeeds. Rotate the failure message through a short list so reruns stay fresh.
- Story: pizza delivery that arrives cold, a parallel-parking attempt that takes four tries. The failure text is part of the teaching, so make it read like a real error a person would say out loud.

## 5. Schedule

Recovery or single-node layout plus the timeline. Teaches repeats and backoff.

- Teaching beat: the shape of the timeline. Spaced repeats show equal gaps; exponential backoff shows gaps that widen. The reader should be able to name the schedule from the timeline alone.
- Endings: the schedule completes and the result green; the base fails permanently and the result red; reader interrupt, which leaves the timeline frozen for reading until reset.

- Entities: one base node and one result node wrapping it with a schedule.
- Driver: `repeat(Schedule.spaced(...))`, `retry(Schedule.exponential(...))`, or the product's scheduler.
- Timeline: blue segments while the base node runs, gaps between. Backoff is visible as widening gaps.
- Notifications: publish a short message on each attempt ("📞 Unknown Caller") so the bubble above the node narrates the loop without a log panel.

## 6. Data model

The scene for "show how the data model changes when these interactions are made". A store panel sits above the nodes; the nodes are the actions; each action's run writes through the store and the panel animates the diff.

- Teaching beat: the store flashing at the exact moment a node's action runs, and nothing else changing. For concurrent writers, the counter arriving out of node order. For a user flow, the fields that flash on each step.
- Endings: the flow completes and the store holds its final shape; an action fails and the store shows the last consistent value; reader interrupt mid-flow, which leaves a partial state the reader can inspect until reset.

Layout:

- Store panel: one pill per store, or one pill per field for a record, or one row per id for a list. Fields that did not change do not flash.
- Node row: one node per action. For concurrent writers the nodes are identical actions (`increment1..5`); for a user flow they are the distinct interactions (`addItem`, `applyCoupon`, `checkout`). The result node runs them in the order or concurrency the concept teaches.
- Snippet: the reducer or the effect that performs the writes, with the store construction visible (`const counter = yield* Ref.make(0)`).

Driver rules:

- Route real writes through the store so the value in the panel is the value the code computed. Do not compute a separate "display" value.
- For a user flow, the composed program is the sequence of actions with jittered delays between them, or a button per action when the reader should choose the order. If actions are buttons, each button is still a node so its state shows.
- For concurrency teaching, run identical writers with `concurrency: "unbounded"` and let the reader watch the counter climb out of order. Each writer's result node shows the value it observed, which teaches read-after-write.
- Reset restores every store to its initial value and every node to idle in one click.

Diff animation, from the motion vocabulary: container flashes blue for 100ms then settles over 300ms; the value swaps with an odometer slide; rows enter from above and exit below through `AnimatePresence mode="popLayout"`.

Sketch for a record store:

```tsx
const cart = useMemo(() => new VisualStore("cart", { items: 0, total: 0, coupon: null as string | null }), [])
const { addItem, applyCoupon, checkout } = useVisualNodes({
  addItem: () => step(600, 900, () => cart.update(c => ({ ...c, items: c.items + 1, total: c.total + 12 }))),
  applyCoupon: () => step(400, 700, () => cart.update(c => ({ ...c, coupon: "SAVE10", total: Math.round(c.total * 0.9) }))),
  checkout: () => step(800, 1200, () => cart.update(c => ({ ...c, items: 0, total: 0, coupon: null }))),
})
const flow = useMemo(() => new VisualNode("flow", async signal => { await addItem.program(signal); await addItem.program(signal); await applyCoupon.program(signal); await checkout.program(signal); return "✅" }), [addItem, applyCoupon, checkout])
```

The panel renders `items`, `total`, and `coupon` as three pills. Running the flow flashes `items` and `total` twice, then `coupon` and `total`, then all three.

## 7. Lifecycle stack

Pipeline layout plus the card stack. Teaches acquire and release, finalizer order, and scope.

- Teaching beat: the stack running in reverse. The last card added moves to the center first. Each running card holds for a fixed beat so the order reads.
- Endings: all finalizers completed and the result green; the use step failed and the finalizers still ran; reader interrupt during use, which still runs the finalizers.

- Entities: an `acquire` node, a `use` node, a `release` node or a stack of finalizers, one result.
- Driver: `acquireRelease`, `addFinalizer`, `ensuring`, or the product's resource API. The stack model records finalizers as they register (pending, left), runs them in reverse (running, centered, 800ms hold), and parks them completed (right).
- Story: open a database, take a lock, then release in reverse. Name finalizers with the resource they close so the LIFO order reads as a sentence.

## Choosing a story

- Pick a scenario a person would recognize in one glance and where the outcome is a short string or an emoji. Weather temperatures, animals racing, pizza delivery, parking attempts, phone notifications.
- Make the failure text funny or specific, never generic. "STARVED TO DEATH!" teaches timeout better than "Error". Jokes belong to fictional stories. When the card explains the product's own code, the bubble shows the real error type and message, and the recovery if there is one; money, data loss, and access are never joked about.
- Descriptions are imperative, start with a verb, and have no trailing punctuation: "Accumulate validation errors instead of failing fast".
- Node names are the variable names in the snippet, lowercase, one word where possible. The reader should be able to point at a node and find its line.
- When the concept is the product's own code, the story is the product's real vocabulary. Use the actual entity names, the actual store shape, and the actual reducer, imported from the codebase.
