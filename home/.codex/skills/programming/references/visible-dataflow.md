# Visible Dataflow

Use this reference when designing or reviewing code whose workflow should expose named-stage dataflow, including code currently obscured by nested expressions, fluent chains, or generic staged abstractions.

## Contents

- [Working Thesis](#working-thesis)
- [Research Position](#research-position)
- [Shape The Visible Dataflow](#shape-the-visible-dataflow)
- [Prefer Named Stages Over Chaining](#prefer-named-stages-over-chaining)
- [Represent Honest Topology](#represent-honest-topology)
- [Preserve Production Semantics](#preserve-production-semantics)
- [Examples](#examples)
- [Failure Patterns](#failure-patterns)

## Working Thesis

Make the happy-path value flow legible and every nonlinear semantic explicit.

Visible-dataflow application code exposes a topologically ordered sequence of domain-named facts, decisions, and commands. Each meaningful value is defined before its consumers. Stable facts are single-assignment by default. Effects remain visible as precisely named operations.

Prefer ordinary statements, descriptive immutable bindings, and explicit function arguments as the canonical notation:

```ts
const source = readSource();
const normalized = normalize(source);
const output = enrich(normalized, clock.now());
```

Visible dataflow is not method chaining. A chain keeps attention on one receiver; named-stage dataflow keeps attention on the facts produced and the dependencies consumed.

Treat visible dataflow as an orchestration motif, not a demand for pipe syntax and not a universal architecture:

> Make value flow visible; branch for alternatives; join independent facts; use a loop or machine for lifecycle; scope resources; gate effects.

Let the domain remain linear only while it is actually linear. Show forks, merges, cycles, state transitions, and ownership scopes instead of hiding them to preserve a chain.

## Research Position

Treat visible dataflow as an evidence-informed design judgment, not a scientifically proven universal optimum.

The strongest direct evidence supports these narrower claims:

- An explicit data-processing DSL helped 57 non-professional programmers reconstruct workflow structure more correctly than Python/Pandas, without making them faster or changing perceived difficulty. The DSL also changed several factors at once, so do not attribute the result to arrows alone.
- More locally linear API examples generally reduced response time in a 61-participant study, while correctness and subjective ratings changed little.
- Meaningful intermediate names helped most on harder expressions; meaningless temporaries sometimes hurt.
- Full, descriptive identifier names improved semantic defect-location time in studies of professional C# developers and Java developers.
- Explicit reactive dependencies outperformed callback-oriented Observer implementations for comprehension in one small student study.

The evidence also supplies important limits:

- A controlled study of 104 students found no overall comprehension or perceived-readability advantage for method chaining.
- Functional constructs and functional decomposition have context-dependent results; neither is inherently easier to understand.
- Comprehension studies measure different abilities—tracing, recall, defect finding, modification, or summarization—and their results do not freely generalize to production maintenance.
- Expert programmers read code nonlinearly. Optimize the program's dependency landmarks and reconstruction cost, not a fiction that eyes always move top to bottom.

Infer the motif from the combined evidence: make order, dependencies, domain names, and effects trustworthy in one local view. Prefer named, single-assignment stages; do not infer that maximum chaining or minimum line count is best.

## Shape The Visible Dataflow

- Start at the trust boundary. Parse external input into canonical domain values before the workflow uses it.
- Arrange statements in topological order. Define each fact before every command or decision that consumes it.
- Use domain nouns for facts and precise verbs for effects.
- Default to one named binding per meaningful transformation, even for a single-use value, when the name clarifies what the stage established.
- Bind a value when the name communicates a new fact, invariant, checkpoint, reuse point, or domain transition.
- Keep a direct expression when an extra name would only paraphrase obvious syntax.
- Preserve the dominant path in one local view. Extract only when meaning, reuse, branching, mechanics, effects, policy, or lifecycle repays navigation.
- Let a stage represent one conceptual operation, not necessarily one tiny function or one line.
- Keep stage contracts truthful. A name such as `validateOrder` must not also persist it, publish an event, and refresh a cache invisibly.
- Expose every material dependency as an input, a locally defined fact, or an enclosing ownership scope.
- Keep earlier facts stable. Prefer a new domain name over reassigning a generic accumulator through unrelated meanings.

Think of the workflow as a directed graph rendered in topological order. A simple chain is one useful graph shape, not the definition of good code.

## Prefer Named Stages Over Chaining

Default to named, single-assignment statements connected by ordinary function arguments. This shape makes each result inspectable, preserves earlier facts, exposes non-receiver dependencies, and gives decisions and effects their own visible lines.

Prefer:

```ts
const order = parseOrder(input);
const pricedOrder = priceOrder(order, priceBook);
const acceptedOrder = acceptOrder(pricedOrder, clock.now());
```

over:

```ts
const acceptedOrder = parseOrder(input)
  .price(priceBook)
  .accept(clock.now());
```

Use a method chain only as a constrained exception when an existing API requires it or when a single, compact, highly conventional collection expression would gain only invented names. Keep such a chain free of effects, semantic transitions, hidden dependencies, consequential evaluation behavior, and branch or failure policy. Break it immediately when a stage deserves a domain name or inspection point.

Do not create a generic stage runner, middleware chain, or builder merely to imitate the visual style. Such abstractions often erase types, dependencies, branch semantics, stack context, and lifecycle ownership. Plain statements are the canonical visible-dataflow notation.

Preserve a fluent interface when an established library uses one as a coherent internal domain language, but do not introduce one for application orchestration. Method chaining by itself is not fluency and not evidence of readable dataflow.

## Represent Honest Topology

| Domain topology | Prefer | Make explicit |
| --- | --- | --- |
| Sequence | Named immutable statements and ordinary function calls | Each produced fact, consumed dependency, and meaningful handoff |
| Fork and join | A visible tuple/record of facts or structured concurrency | Independence, capacity, cancellation, and aggregate failure |
| Exclusive choice | `if`, pattern matching, or a discriminated union | The condition, branch-specific result, and merge |
| Repetition | A loop, fold, recursion, or iterator suited to the algorithm | State, termination, short-circuiting, and mutation |
| Lifecycle | An explicit state machine or workflow | Legal transitions, retries, waits, cancellation, and terminal states |
| Resource scope | A context manager, transaction callback, or lexical scope | Owner, acquisition, cleanup, and values that may not escape |
| Distributed workflow | Durable orchestration, saga, or explicit event protocol | Idempotency, delivery, persistence, compensation, and observability |

Do not serialize independent work merely to preserve a linear picture. Do not run work concurrently merely because the syntax makes a fan-out compact.

Let the use case expose visible dataflow without automatically making every processing step a module, class, service, or deployment boundary. Follow Parnas: choose module boundaries around information-hiding decisions and reasons to change; keep workflow order in orchestration.

## Preserve Production Semantics

### Effects

- Keep pure transformations easy to compose and isolate commands as visible effect gates.
- Use query names for facts and command verbs such as `reserve`, `commit`, `append`, `publish`, or `send` for state changes.
- Do not hide required effects inside `map`, `filter`, lazy callbacks, property accessors, or constructors.
- Delay irreversible effects when real dependencies permit, but preserve transaction, lock, and resource correctness over visual purity.

### Failure

- Use `Result` or `Either` composition for expected domain outcomes that callers must handle.
- Distinguish short-circuiting bind from validation that must accumulate independent errors.
- Preserve exceptions and diagnostics for unexpected faults when replacing them with values would discard location or stack context.
- Do not model every infrastructure failure as a domain variant. Model only the distinctions that consumers use.

### Concurrency And Streaming

- Treat concurrency as a scoped fork/join with a lifecycle owner.
- Define cancellation and sibling-failure behavior before using `Promise.all`, `asyncio.gather`, goroutines, or equivalent tools.
- Define backpressure, buffering, scheduling, ordering, and shutdown for asynchronous streams.
- Remember that a source-level chain can be eager, lazy, fused, buffered, parallel, or sequential. Inspect the actual runtime contract.

### Resources And Transactions

- Place the resource or transaction owner outside every dependent stage.
- Do not return lazy work that depends on a resource whose scope has already ended.
- Do not mix transaction-bound and global database operations in one apparently atomic flow.
- Keep framework-required callbacks when they define the correct lifetime; arrange named dataflow inside them.

### Observability

- Add causal checkpoints at consequential boundaries, retries, state transitions, and expensive operations.
- Preserve trace context across async and service boundaries.
- Avoid logging every pure transformation; signals should explain decisions and effects, not narrate syntax.
- Break opaque async chains where a named checkpoint materially improves stack context or diagnosis.

### Performance

- Measure before replacing clear named-stage dataflow with mutation or a hand-written loop.
- Do not claim “zero-cost” composition without a language-, library-, and workload-specific basis.
- Account for intermediate collections, materialization, sorting, buffering, closure allocation, and abstraction overhead.
- Prefer an implementation with real fusion or laziness only when its resource and evaluation semantics remain correct.

## Examples

### Canonical named-stage orchestration

```ts
const command = placeOrderCommandSchema.parse(request.body);
const requestedSkus = requestedSkusFrom(command.lines);

const [customer, inventory] = await Promise.all([
  customers.find(command.customerId),
  inventoryStore.findMany(requestedSkus),
]);

const quote = quoteFrom({ command, customer, inventory });
const allocation = allocationFrom({ command, inventory });
const order = orderFrom({ command, quote, allocation });

await orders.commit({ order, allocation });
return order;
```

The statements expose a graph, not a literal one-value chain. The fork and join are visible. Names mark domain facts. The effect is an explicit command near the end.

### Name collection stages too

```ts
const positiveLines = command.lines.filter(({ quantity }) => quantity > 0);
const rawSkus = positiveLines.map(({ sku }) => sku);
const normalizedSkus = rawSkus.map((sku) => sku.trim());
const requestedSkus = normalizedSkus.filter((sku) => sku.length > 0);
```

Each stage remains locally visible and inspectable. The names describe what changed without requiring a custom staged abstraction.

### A semantic boundary that deserves a name

```ts
const normalizedLines = normalizeLines(command.lines);
const pricingInput = pricingInputFrom({ customer, normalizedLines });
const quote = quoteFrom(pricingInput);
```

Keep the names if `normalizedLines` and `pricingInput` are meaningful states with contracts worth inspecting. Inline them if the names merely restate trivial syntax.

### Expected failure as explicit stages and branches

```ts
const validation = validate(command);
if (!validation.ok) {
  return rejectedOrderResponse(validation.error);
}

const authorization = authorize(validation.value);
if (!authorization.ok) {
  return rejectedOrderResponse(authorization.error);
}

const reservation = reserveInventory(authorization.value);
if (!reservation.ok) {
  return rejectedOrderResponse(reservation.error);
}

return commitOrder(reservation.value);
```

The happy-path values are named while alternatives stay visible as branches. Use typed outcomes only when validation, authorization, and reservation failures are expected domain outcomes. Preserve ordinary exception handling for unexpected faults that require diagnostic context.

## Failure Patterns

- **Chain-first readability:** Keep extending a method chain even after named facts would make dependencies, semantic transitions, or inspection points clearer.
- **Stage-runner theater:** Split every line into a function and connect them with a generic runner while forcing readers to navigate elsewhere for obvious mechanics.
- **Helper confetti:** Treat one stage as one function even when the functions have no reusable or compressive meaning.
- **Mutable subject drift:** Reassign `result`, `data`, or `_` across unrelated domain meanings so earlier facts disappear.
- **Hidden commands:** Perform audit, persistence, or publication inside a transformation callback whose execution may be lazy, reordered, repeated, or elided.
- **False atomicity:** Present several distributed effects as one sequence without idempotency, compensation, or partial-failure handling.
- **False railway:** Render retry, polling, or backoff as `fetch -> validate -> save` while hiding waiting states and terminal outcomes.
- **Transaction escape:** Read within one transaction and write through an unrelated global connection.
- **Lazy resource escape:** Return a stream after closing the file, cursor, session, or subscription that evaluation needs.
- **Topology denial:** Encode a state machine, graph traversal, or feedback loop as a generic chain that obscures state and termination.
- **Step-per-module architecture:** Create one module or service per step even though the steps share the same hidden decision and must change together.
