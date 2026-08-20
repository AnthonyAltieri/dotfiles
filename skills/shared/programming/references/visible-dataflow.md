# Visible Dataflow

Use when designing or reviewing workflows that should expose named-stage dataflow, including nested expressions, fluent chains, collection transformations, staged abstractions, and other value-flow concerns.

Contents: [Thesis](#thesis) · [Shape](#shape-visible-dataflow) · [Chaining](#prefer-named-stages-to-chaining) · [Topology](#represent-honest-topology) · [Semantics](#preserve-production-semantics) · [Examples](#examples) · [Failures](#failure-patterns)

## Thesis

Make happy-path value flow legible and nonlinear semantics explicit. Render workflows as topologically ordered graphs of domain-named, single-assignment facts, decisions, and commands linked by ordinary statements and explicit arguments.

Named-stage dataflow centers produced facts and consumed dependencies; chaining centers one receiver. Treat it as an orchestration motif, not pipe syntax or a universal architecture.

> Make value flow visible; branch for alternatives; join independent facts; use loops or state machines for lifecycle; scope resources; gate effects.

Keep the domain linear only while it is linear. Expose forks, merges, cycles, transitions, and ownership scopes instead of hiding them to preserve a chain.

Evidence for these preferences is directional, not universal: optimize trustworthy dependency landmarks, order, domain names, effects, and reconstruction cost—not chaining or minimum line count.

## Shape Visible Dataflow

- Arrange facts in dependency order; use domain nouns for values and precise verbs for effects.
- Bind a value when its name establishes a fact, invariant, checkpoint, reuse point, or domain transition; keep direct expressions when a name would only paraphrase syntax.
- Preserve the dominant path locally. Extract only when meaning, reuse, branching, mechanics, effects, policy, or lifecycle repays navigation.
- Let each stage represent one conceptual operation, not necessarily one line or tiny function.
- Keep stage contracts truthful: `validateOrder` must not also persist, publish, and refresh a cache invisibly.
- Expose material dependencies as inputs, local facts, or enclosing ownership scopes.
- Preserve earlier facts; prefer a new domain name to reassigning a generic accumulator across meanings.

Think of the workflow as a directed graph rendered in topological order. A chain is one possible graph shape, not the definition of good code.

## Prefer Named Stages To Chaining

Prefer:

```ts
const order = parseOrder(input);
const pricedOrder = priceOrder({ order, priceBook });
const acceptedOrder = acceptOrder({ pricedOrder, at: clock.now() });
```

over:

```ts
const acceptedOrder = parseOrder(input)
  .price(priceBook)
  .accept(clock.now());
```

Use a chain only when an established API requires it or a compact, conventional collection expression would gain only invented names. Keep it free of effects, semantic transitions, hidden dependencies, consequential evaluation behavior, and branch/failure policy; break it when a stage deserves a domain name or inspection point.

Preserve a coherent fluent library interface, but do not introduce generic stage runners, middleware chains, or builders for application orchestration. Chaining alone is neither fluency nor readable dataflow.

## Represent Honest Topology

| Topology | Prefer | Expose |
| --- | --- | --- |
| Sequence | Named immutable statements and ordinary calls | Produced facts, dependencies, handoffs |
| Fork/join | Visible tuples/records or structured concurrency | Independence, capacity, cancellation, aggregate failure |
| Exclusive choice | `if`, pattern matching, discriminated unions | Condition, branch result, merge |
| Repetition | Suitable loop, fold, recursion, or iterator | State, termination, short-circuiting, mutation |
| Lifecycle | Explicit state machine or workflow | Transitions, retries, waits, cancellation, terminal states |
| Resource scope | Context manager, transaction callback, lexical scope | Owner, acquisition, cleanup, escape rules |
| Distributed workflow | Durable orchestration, saga, event protocol | Idempotency, delivery, persistence, compensation, observability |

Do not serialize independent work or add concurrency merely for visual linearity or compact syntax. Keep workflow order in orchestration, but choose module/service boundaries around hidden decisions and reasons to change—not one boundary per step.

## Preserve Production Semantics

### Effects And Failure

- Compose pure transformations and isolate commands behind visible effect gates. Use query names for facts and command verbs such as `reserve`, `commit`, `append`, `publish`, or `send`.
- Do not hide effects inside `map`, `filter`, lazy callbacks, accessors, or constructors. Delay irreversible effects when dependencies permit, but preserve transaction, lock, and resource correctness.
- Use `Result`/`Either` for expected domain outcomes callers handle; distinguish short-circuiting bind from validation that accumulates independent errors.
- Preserve exceptions and diagnostics for unexpected faults. Model infrastructure failures as domain variants only when consumers use the distinction.

### Concurrency, Streaming, And Resources

- Treat concurrency as a scoped fork/join with a lifecycle owner; define cancellation and sibling-failure behavior before using `Promise.all`, `asyncio.gather`, goroutines, or equivalents.
- For asynchronous streams, define backpressure, buffering, scheduling, ordering, and shutdown. Inspect whether source-level chains are eager, lazy, fused, buffered, parallel, or sequential.
- Place resource/transaction owners outside all dependent stages. Do not return lazy work after its resource scope ends or mix transaction-bound and global database operations in one apparently atomic flow.
- Keep framework callbacks that define correct lifetimes; arrange named stages inside them.

### Observability And Performance

- Add checkpoints at consequential boundaries, retries, transitions, and expensive operations; preserve trace context across asynchronous/service boundaries.
- Avoid narrating pure syntax. Break opaque asynchronous chains only when a named checkpoint materially improves stack context or diagnosis.
- Measure before replacing clear stages with mutation or hand-written loops. Never claim “zero-cost” composition without language-, library-, and workload-specific evidence.
- Account for intermediate collections, materialization, sorting, buffering, closures, and abstraction overhead. Use fusion or laziness only when evaluation and resource semantics remain correct.

## Examples

### Canonical Orchestration

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

This exposes the fork/join, domain facts, and final command without pretending the graph is a one-value chain.

### Expected Failure

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

Keep alternatives as visible branches; use typed outcomes only for expected failures and retain diagnostic exceptions for unexpected faults.

## Failure Patterns

- **Chain-first readability:** extend a chain after named facts would clarify dependencies, transitions, or inspection points.
- **Stage-runner theater / helper confetti:** split readable mechanics into tiny functions and a generic runner, forcing navigation without semantic compression.
- **Mutable subject drift:** reassign `result`, `data`, or `_` across meanings so earlier facts disappear.
- **Hidden commands:** perform audit, persistence, or publication in callbacks that may be lazy, reordered, repeated, or elided.
- **False atomicity / false railway:** present several distributed effects as one sequence without idempotency, compensation, or partial-failure handling, or hide retries, waits, and terminal states behind a linear sequence.
- **Transaction or resource escape:** mix transaction/global operations or return lazy work after closing its file, cursor, session, or subscription.
- **Topology denial:** encode a state machine, traversal, or feedback loop as a generic chain that hides state and termination.
- **Step-per-module architecture:** create one module or service per step although the steps share a hidden decision and change together.
