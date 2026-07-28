# Orchestration And Locality

Use to decide what stays local, what earns a function boundary, and how top-level logic should read. Optimize for comprehension, change safety, and visible causality.

## Keep One-Off Code Local

Treat arguments as dataflow edges and returned values as facts. Keep useful, immutable facts near their use until a boundary provides more semantic compression or isolation than indirection and context reconstruction cost.

| Keep local when | Extract when |
| --- | --- |
| One call site remains readable and a local binding supplies enough meaning. | A name compresses a stable domain concept, rule, or invariant. |
| Mapping, projection, construction, or a short predicate exposes useful policy or data shape. | Same-reason reuse should change together. |
| A helper would paraphrase syntax, hide policy, or require most caller context. | Branching, state, failure, or algorithmic mechanics need separate reasoning. |
|  | A boundary isolates framework, third-party, security, retry, resource, or serialization mechanics, or offers a valuable narrow contract. |

Judge complexity by required mental simulation, not line count. Extract callbacks whose control flow interrupts the caller's behavioral scan; testability alone does not earn extraction. Avoid helper confetti, premature deduplication of merely similar code, generic names that hide policy, and ambient mutable capture.

## Shape Entrypoints As Named Dataflow

- Validate or extract boundary input first. Define immutable facts in dependency order and pass them explicitly.
- Name facts with domain nouns and effects with precise verbs. Let visible branches and merges carry domain meaning.
- Keep orchestration at one conceptual level without extracting readable mechanics. Avoid generic runners, middleware chains, or builders that hide types, dependencies, or control flow.

Prefer, when the domain permits:

`validated input -> queried facts -> derived values and decisions -> commands or mutation -> result`

## Make Effects And Mutation Obvious

- Distinguish queries that produce facts from commands that change state; let external reads produce named facts.
- Delay writes and irreversible effects when correctness and lifecycle permit. Group changes behind one explicit commit when they must be atomic.
- Signal mutation with precise verbs; contain algorithmic or performance-motivated mutation in one narrow function and return a stable result without leaking partially mutated state.
- Never rearrange transaction, lock, or resource-lifetime boundaries for visual purity.

## Preserve Shape Under Telemetry

- Use one entrypoint span when request-level scope matters; add child spans only for costly boundaries, retries, state transitions, or consequential decisions.
- Keep orchestration flat with value-returning wrappers; instrument stable adapters when repeated wrappers would dominate business logic.
- Add attributes when values become available. Record failure at its owning boundary; avoid log-and-rethrow duplication.
- Skip telemetry for obvious pure transformations.

## Handle Real Control Flow Honestly

- Run work concurrently only when independent in data, ordering, capacity, cancellation, and failure semantics.
- Keep discriminated branches explicit; extract only branch bodies that interrupt the main scan.
- Model loops and state machines directly instead of forcing a linear sequence.
- Keep named dataflow inside required transaction, lock, resource, or framework callbacks.
- Allow contained local mutation when a stateful algorithm is clearer or measured performance requires it; treat framework-required mutation, such as span attributes or response headers, as an explicit edge effect.

## Example

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

Keep the useful projection local, extract domain rules, and parallelize reads only when all five independence conditions hold.

## Review

Can a reader follow the business sequence without helper archaeology, hidden effects, mutable facts, or reconstructed context?
