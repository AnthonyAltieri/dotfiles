# Orchestration And Locality

Use this reference to decide what stays local, what earns a function boundary, and how top-level logic should read.

## Contents

- [First Principles](#first-principles)
- [Keep One-Off Code Local](#keep-one-off-code-local)
- [Shape Entrypoints As Named Dataflow](#shape-entrypoints-as-named-dataflow)
- [Make Effects And Mutation Obvious](#make-effects-and-mutation-obvious)
- [Preserve Shape Under Telemetry](#preserve-shape-under-telemetry)
- [Handle Real Control Flow Honestly](#handle-real-control-flow-honestly)
- [TypeScript Example](#typescript-example)
- [Review](#review)

## First Principles

- Optimize code shape for comprehension, change safety, and visible causality.
- Keep useful facts near their use until a boundary provides real semantic compression.
- Use names to expose domain meaning, not to conceal readable mechanics.
- Treat function arguments as dataflow edges and returned values as new facts.
- Prefer immutable intermediate values so earlier facts remain stable and dependencies remain inspectable.

Extract only when semantic compression or isolation value exceeds indirection and context-reconstruction cost.

## Keep One-Off Code Local

- Use a well-named local binding as the first abstraction for a one-off transformation.
- Treat information-dense code as locally readable code whose details expose useful domain or data-shape information.
- Keep readable mappings, projections, object construction, and short predicates at the call site.
- Judge complexity by required mental simulation, not by line count.
- Extract a callback when its control flow or mechanics interrupts the caller's behavioral scan.

Keep code inline when:

- It has one call site and remains readable in its surrounding context.
- A local variable name supplies enough meaning.
- Its exact selection, mapping, or construction helps explain the behavior.
- A helper name would merely paraphrase the syntax or hide policy.
- Extraction would require passing most of the caller's context back into the helper.

Extract a function when:

- Its name compresses a stable domain concept, rule, or invariant.
- Multiple call sites perform the same operation for the same reason and should change together.
- Branching, state, failure modes, or algorithmic mechanics require independent reasoning.
- A boundary isolates framework, third-party, security, retry, resource, or serialization mechanics.
- A narrow contract has value beyond making the code separately testable.

Avoid helper confetti, premature deduplication of merely similar code, generic names that hide policy, and helpers that capture ambient mutable state.

## Shape Entrypoints As Named Dataflow

- Start by validating or extracting boundary input.
- Arrange statements in topological order: define each value before its consumers.
- Bind each meaningful intermediate result once and avoid reassignment by default.
- Pass domain inputs explicitly so the graph remains visible at each call.
- Name values with domain nouns and effects with precise verbs.
- Keep orchestration at one conceptual level without extracting every readable expression.
- Let branches and merges remain visible when they carry domain meaning.
- Avoid generic pipeline, step-runner, or builder abstractions that hide types, dependencies, or control flow.

Prefer this flow when the domain permits it:

`validated input -> queried facts -> derived values and decisions -> commands or mutation -> result`

## Make Effects And Mutation Obvious

- Distinguish queries that produce facts from commands that change state.
- Let external reads produce named nodes in the dataflow.
- Place writes and irreversible effects late when correctness and lifecycle permit.
- Group changes behind one explicit commit when they must succeed atomically.
- Signal mutation with verbs such as `apply`, `commit`, `save`, `append`, or `reserve`.
- Contain performance-motivated or algorithmic mutation inside one narrow function.
- Return a stable result instead of leaking partially mutated state.
- Preserve transaction, lock, and resource-lifetime correctness instead of rearranging effects for visual purity.

## Preserve Shape Under Telemetry

- Use one operation span around the entrypoint when a request-level scope is valuable.
- Add child spans around costly boundaries, retries, state transitions, or consequential decisions.
- Skip spans and logs for obvious pure transformations.
- Keep orchestration lexically flat with wrappers that return the step's value.
- Instrument stable adapters when repeated wrappers would dominate business logic.
- Add attributes when the relevant values become available.
- Record a failure at the boundary that owns it; avoid log-and-rethrow duplication.

## Handle Real Control Flow Honestly

- Run operations concurrently—for example with `Promise.all` or `asyncio.gather`—only when they are independent in data, ordering, capacity, cancellation, and failure semantics.
- Keep discriminated branches explicit; extract only branch bodies that interrupt the main scan.
- Model loops and state machines directly instead of forcing them into a fake linear pipeline.
- Keep named dataflow inside required transaction, lock, or framework callbacks.
- Allow local mutation when a stateful algorithm is clearer or measured performance requires it.
- Treat framework-required mutation, such as span attributes or response headers, as an explicit edge effect.

## TypeScript Example

```ts
const placeOrder = (ctx: PlaceOrderContext): Promise<PlacedOrder> =>
  ctx.telemetry.inSpan("order.place", async (span) => {
    const command = placeOrderCommandSchema.parse(ctx.request.body);
    const requestedSkus = [
      ...new Set(command.lines.map(({ sku }) => sku)),
    ];

    const [customer, inventory] = await Promise.all([
      ctx.customers.find(command.customerId),
      ctx.inventory.findMany(requestedSkus),
    ]);

    const quote = quoteFrom({ command, customer, inventory });
    const allocation = allocationFrom({ command, inventory });
    const order = orderFrom({ command, quote, allocation });

    await ctx.telemetry.inSpan("order.commit", () =>
      ctx.orders.commit({ order, allocation }),
    );

    span.setAttributes({ orderId: order.id });
    return order;
  });
```

Keep `requestedSkus` local because the one-off projection is useful and readable. Extract pricing and allocation because they encode domain rules that deserve names and independent reasoning.

Run the customer and inventory lookups in parallel only when their ordering, capacity, cancellation, and failure semantics are also independent; otherwise await them in the required order.

## Review

- Confirm that the entrypoint exposes the business sequence without requiring helper archaeology.
- Confirm that every helper earns its indirection through meaning, reuse, or isolation.
- Confirm that each dependency appears before and in the call that consumes it.
- Confirm that intermediate facts remain immutable unless mutation is deliberate and contained.
- Confirm that writes, mutation, and telemetry remain visible and correctly ordered.
- Remove any abstraction that shortens the file without making the behavior easier to understand.
