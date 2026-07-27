# Visible Dataflow Forward-Test Evidence

Date: 2026-07-22

This document preserves fresh-context behavioral evidence for the independently deployed Codex and Claude copies of the shared `programming` skill. It is outside both skill directories and is not part of their required context or Home Manager managed copies.

## Method

Each run used a fresh subagent context with no conversation history. The prompt named only the selected skill path and a realistic refactoring task; it did not disclose the intended style, rubric, earlier findings, or another run's output. The subagents were read-only.

The runs exercise the repository's two skill surfaces through the same agent runtime. They validate the contents and routing of each copy, not model-specific differences between Codex and Claude runtimes.

Initial mirrored candidate:

- `SKILL.md`: `6225061b98e2635bea4029b1ac9b37ec129e9f8ed85302a1de2adf46b61b3127`
- `references/visible-dataflow.md`: `875cc5df3a20df7e0c38de5e50a51d582d74769f78d324599939451d5d278b12`

After the initial Claude-surface run changed behavior, both `SKILL.md` copies were tightened to define transaction, lock, resource, concurrency, retry, and effect-ordering boundaries as behavior that a behavior-preserving refactor must retain. Rerun candidate:

- `SKILL.md`: `8086246702f2a516afcf145be1207cfde1e30da7680a551b3a9f818e083439bc`
- `references/visible-dataflow.md`: `875cc5df3a20df7e0c38de5e50a51d582d74769f78d324599939451d5d278b12`

After rebasing onto the latest `origin/main`, the required-reference routing incorporated upstream's concern-based selection language. Upstream-integrated candidate:

- `SKILL.md`: `6f7036d7577b6a952376c44078b0b6953d44174c5099c4e6a97ea06776151488`
- `references/visible-dataflow.md`: `875cc5df3a20df7e0c38de5e50a51d582d74769f78d324599939451d5d278b12`

For each candidate, the Codex and Claude files had matching hashes.

## Shared Prompt

The only per-surface difference was the exact value substituted for `<surface>`:

- Codex: `/Users/anthonyaltieri/.codex/worktrees/da95/dotfiles/home/.codex`
- Claude: `/Users/anthonyaltieri/.codex/worktrees/da95/dotfiles/home/.claude`

~~~~text
Use `$programming` at `<surface>/skills/programming/SKILL.md` to refactor the TypeScript function below for maintainability and production correctness. Preserve its behavior and public return contract. Assume the named collaborators and pure helper functions already exist with the implied types. The transaction query builder is an established library API. Do not edit files or inspect unrelated repository content. Return the revised function followed by a concise rationale.

```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(
        request.lines
          .filter(({ quantity }) => quantity > 0)
          .map(normalizeLine)
          .map(({ sku }) => sku),
      ),
    ]);

    const authorization = authorizeOrder(
      priceOrder(
        orderFrom(request, customer, inventory),
        deps.priceBook,
      ),
      deps.clock.now(),
    );

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    let attempt = 0;
    while (attempt < 3) {
      const reservation = await deps.inventory.reserve(authorization.value);
      if (reservation.ok) {
        const savedOrder = await tx.orders
          .insert(orderRecordFrom(authorization.value, reservation.value))
          .returningAll()
          .executeTakeFirstOrThrow();
        await deps.events.publish(orderPlacedFrom(savedOrder));
        return { ok: true, value: savedOrder };
      }

      if (!reservation.retryable) {
        return { ok: false, error: reservation.error };
      }

      attempt += 1;
      await deps.clock.sleep(attempt * 100);
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```
~~~~

## Rubric

A run passes only when every criterion passes:

1. **Visible stages:** split meaningful collection and domain transformations into descriptive, immutable bindings connected through ordinary function arguments.
2. **Honest topology:** preserve the explicit fork/join, authorization branch, retry loop, and terminal outcomes.
3. **Behavioral boundaries:** preserve transaction scope, concurrency, retry behavior, and publication timing because the prompt requires behavior preservation.
4. **Failure semantics:** preserve the non-retryable exit, three reservation attempts, and the existing 100/200/300 ms waits, including the final wait before exhaustion.
5. **Constrained chaining:** retain the established fluent transaction query-builder API while avoiding new application-orchestration chains.
6. **Scope discipline:** report suspected production issues separately instead of silently implementing a semantic change.

## Results

| Run | Candidate | Visible stages | Honest topology | Behavioral boundaries | Failure semantics | Constrained chaining | Scope discipline | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Initial Codex surface | Initial | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Initial Claude surface | Initial | Pass | Pass | **Fail** | Pass | Pass | **Fail** | **Fail** |
| Codex surface rerun | Tightened | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Claude surface rerun | Tightened | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Codex surface integration rerun | Upstream-integrated | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Claude surface integration rerun | Upstream-integrated | Pass | Pass | Pass | Pass | Pass | Pass | Pass |

The initial Claude-surface response moved database transaction ownership from the whole workflow to the insert and moved publication after commit. Both changes violated the explicit behavior-preservation contract. The tightened shared instruction corrected that failure in both fresh reruns.

## Raw Outputs

### Initial Codex Surface — Pass

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const orderableLines = request.lines.filter(
      ({ quantity }) => quantity > 0,
    );
    const normalizedLines = orderableLines.map(normalizeLine);
    const requestedSkus = normalizedLines.map(({ sku }) => sku);

    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(requestedSkus),
    ]);

    const order = orderFrom(request, customer, inventory);
    const pricedOrder = priceOrder(order, deps.priceBook);
    const authorization = authorizeOrder(
      pricedOrder,
      deps.clock.now(),
    );

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    const reservationAttemptLimit = 3;
    const reservationBackoffMs = 100;

    for (
      let attempt = 1;
      attempt <= reservationAttemptLimit;
      attempt += 1
    ) {
      const reservation = await deps.inventory.reserve(
        authorization.value,
      );

      if (!reservation.ok) {
        if (!reservation.retryable) {
          return { ok: false, error: reservation.error };
        }

        await deps.clock.sleep(attempt * reservationBackoffMs);
        continue;
      }

      const orderRecord = orderRecordFrom(
        authorization.value,
        reservation.value,
      );
      const savedOrder = await tx.orders
        .insert(orderRecord)
        .returningAll()
        .executeTakeFirstOrThrow();
      const orderPlaced = orderPlacedFrom(savedOrder);

      await deps.events.publish(orderPlaced);

      return { ok: true, value: savedOrder };
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```

The refactor exposes each domain transition as an immutable, named value and replaces mutable retry state with a bounded loop. It deliberately preserves the established transaction scope, effect ordering, three reservation attempts, and existing backoff calls—including the final retryable failure—so behavior and the `PlaceOrderResult` contract remain unchanged.
~~~~

### Initial Claude Surface — Fail

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  const positiveQuantityLines = request.lines.filter(
    ({ quantity }) => quantity > 0,
  );
  const normalizedLines = positiveQuantityLines.map(normalizeLine);
  const requestedSkus = normalizedLines.map(({ sku }) => sku);

  const [customer, inventory] = await Promise.all([
    deps.customers.find(request.customerId),
    deps.inventory.findMany(requestedSkus),
  ]);

  const order = orderFrom(request, customer, inventory);
  const pricedOrder = priceOrder(order, deps.priceBook);
  const authorizationTime = deps.clock.now();
  const authorization = authorizeOrder(pricedOrder, authorizationTime);

  if (!authorization.ok) {
    return { ok: false, error: authorization.error };
  }

  for (let attemptNumber = 1; attemptNumber <= 3; attemptNumber += 1) {
    const reservation = await deps.inventory.reserve(authorization.value);

    if (!reservation.ok) {
      if (!reservation.retryable) {
        return { ok: false, error: reservation.error };
      }

      // Preserve the existing 100 ms, 200 ms, and 300 ms waits.
      await deps.clock.sleep(attemptNumber * 100);
      continue;
    }

    const orderRecord = orderRecordFrom(
      authorization.value,
      reservation.value,
    );

    const savedOrder = await deps.db.transaction((tx) =>
      tx.orders
        .insert(orderRecord)
        .returningAll()
        .executeTakeFirstOrThrow(),
    );

    const orderPlaced = orderPlacedFrom(savedOrder);
    await deps.events.publish(orderPlaced);

    return { ok: true, value: savedOrder };
  }

  return { ok: false, error: reservationAttemptsExhausted() };
}
```

Named immutable stages expose the value flow while preserving filtering, retry count, backoff, and result variants. The transaction now covers only its actual dependent database write, avoiding an open transaction during remote reads, retries, and sleeps; publication occurs after commit so an event cannot describe an uncommitted order.

The shown collaborators still cannot make reservation, persistence, and publication atomic. Full crash-safe correctness would require existing compensation/idempotency support and a transactional outbox.
~~~~

### Codex Surface Rerun — Pass

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const positiveLines = request.lines.filter(
      ({ quantity }) => quantity > 0,
    );
    const normalizedLines = positiveLines.map(normalizeLine);
    const requestedSkus = normalizedLines.map(({ sku }) => sku);

    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(requestedSkus),
    ]);

    const order = orderFrom(request, customer, inventory);
    const pricedOrder = priceOrder(order, deps.priceBook);
    const authorization = authorizeOrder(
      pricedOrder,
      deps.clock.now(),
    );

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    for (let attempt = 1; attempt <= 3; attempt += 1) {
      const reservation = await deps.inventory.reserve(
        authorization.value,
      );

      if (reservation.ok) {
        const orderRecord = orderRecordFrom(
          authorization.value,
          reservation.value,
        );
        const savedOrder = await tx.orders
          .insert(orderRecord)
          .returningAll()
          .executeTakeFirstOrThrow();
        const orderPlaced = orderPlacedFrom(savedOrder);

        await deps.events.publish(orderPlaced);
        return { ok: true, value: savedOrder };
      }

      if (!reservation.retryable) {
        return { ok: false, error: reservation.error };
      }

      const retryDelayMs = attempt * 100;
      await deps.clock.sleep(retryDelayMs);
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```

The refactor names each meaningful domain stage, keeps the established query-builder chain intact, and makes the retry lifecycle explicit. It preserves concurrency, transaction scope, effect ordering, three reservation attempts, and the existing `100/200/300 ms` sleeps—including the final sleep before exhaustion.
~~~~

### Claude Surface Rerun — Pass

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const positiveQuantityLines = request.lines.filter(
      ({ quantity }) => quantity > 0,
    );
    const normalizedLines = positiveQuantityLines.map(normalizeLine);
    const requestedSkus = normalizedLines.map(({ sku }) => sku);

    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(requestedSkus),
    ]);

    const order = orderFrom(request, customer, inventory);
    const pricedOrder = priceOrder(order, deps.priceBook);
    const authorizationTime = deps.clock.now();
    const authorization = authorizeOrder(pricedOrder, authorizationTime);

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    const authorizedOrder = authorization.value;
    const maximumReservationAttempts = 3;
    const retryDelayMilliseconds = 100;

    for (
      let attempt = 1;
      attempt <= maximumReservationAttempts;
      attempt += 1
    ) {
      const reservation = await deps.inventory.reserve(authorizedOrder);

      if (!reservation.ok) {
        if (!reservation.retryable) {
          return { ok: false, error: reservation.error };
        }

        await deps.clock.sleep(attempt * retryDelayMilliseconds);
        continue;
      }

      const orderRecord = orderRecordFrom(
        authorizedOrder,
        reservation.value,
      );
      const savedOrder = await tx.orders
        .insert(orderRecord)
        .returningAll()
        .executeTakeFirstOrThrow();
      const orderPlaced = orderPlacedFrom(savedOrder);

      await deps.events.publish(orderPlaced);
      return { ok: true, value: savedOrder };
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```

The refactor exposes each domain transition as an immutable named value, keeps the established query-builder chain intact, and makes retry state and constants explicit. It preserves the original concurrency, transaction/effect ordering, three attempts, and even the final 300 ms sleep before exhaustion.

One production caveat remains intentionally unchanged: publishing inside the transaction can emit an event before commit, while inventory reservation is outside the database transaction. Solving those partial-failure risks would require an outbox or compensation contract and would change behavior.
~~~~

### Codex Surface Integration Rerun — Pass

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const positiveLines = request.lines.filter(
      ({ quantity }) => quantity > 0,
    );
    const normalizedLines = positiveLines.map(normalizeLine);
    const requestedSkus = normalizedLines.map(({ sku }) => sku);

    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(requestedSkus),
    ]);

    const order = orderFrom(request, customer, inventory);
    const pricedOrder = priceOrder(order, deps.priceBook);
    const authorizationTime = deps.clock.now();
    const authorization = authorizeOrder(pricedOrder, authorizationTime);

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    const authorizedOrder = authorization.value;
    const maximumReservationAttempts = 3;

    for (
      let reservationAttempt = 1;
      reservationAttempt <= maximumReservationAttempts;
      reservationAttempt += 1
    ) {
      const reservation = await deps.inventory.reserve(authorizedOrder);

      if (!reservation.ok) {
        if (!reservation.retryable) {
          return { ok: false, error: reservation.error };
        }

        const retryDelayMs = reservationAttempt * 100;
        await deps.clock.sleep(retryDelayMs);
        continue;
      }

      const orderRecord = orderRecordFrom(
        authorizedOrder,
        reservation.value,
      );
      const savedOrder = await tx.orders
        .insert(orderRecord)
        .returningAll()
        .executeTakeFirstOrThrow();

      const orderPlaced = orderPlacedFrom(savedOrder);
      await deps.events.publish(orderPlaced);

      return { ok: true, value: savedOrder };
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```

The refactor exposes normalization, pricing, authorization, persistence, and publication as named stages while retaining the transaction scope, concurrency, effect order, three reservation attempts, and existing 100/200/300 ms sleeps. The established query-builder chain remains intact.

One production caveat is deliberately unchanged: inventory reservation and event publication appear external to the database transaction, so partial failures may require an outbox or compensation strategy if those collaborators are not transaction-aware.
~~~~

### Claude Surface Integration Rerun — Pass

~~~~markdown
```ts
async function placeOrder(
  request: PlaceOrderRequest,
  deps: PlaceOrderDependencies,
): Promise<PlaceOrderResult> {
  return deps.db.transaction(async (tx) => {
    const positiveLines = request.lines.filter(
      ({ quantity }) => quantity > 0,
    );
    const normalizedLines = positiveLines.map(normalizeLine);
    const requestedSkus = normalizedLines.map(({ sku }) => sku);

    const [customer, inventory] = await Promise.all([
      deps.customers.find(request.customerId),
      deps.inventory.findMany(requestedSkus),
    ]);

    const order = orderFrom(request, customer, inventory);
    const pricedOrder = priceOrder(order, deps.priceBook);
    const authorization = authorizeOrder(
      pricedOrder,
      deps.clock.now(),
    );

    if (!authorization.ok) {
      return { ok: false, error: authorization.error };
    }

    const authorizedOrder = authorization.value;
    const maximumReservationAttempts = 3;
    const retryDelayMilliseconds = 100;

    for (
      let attempt = 1;
      attempt <= maximumReservationAttempts;
      attempt += 1
    ) {
      const reservation = await deps.inventory.reserve(authorizedOrder);

      if (!reservation.ok) {
        if (!reservation.retryable) {
          return { ok: false, error: reservation.error };
        }

        await deps.clock.sleep(attempt * retryDelayMilliseconds);
        continue;
      }

      const orderRecord = orderRecordFrom(
        authorizedOrder,
        reservation.value,
      );
      const savedOrder = await tx.orders
        .insert(orderRecord)
        .returningAll()
        .executeTakeFirstOrThrow();

      const orderPlaced = orderPlacedFrom(savedOrder);
      await deps.events.publish(orderPlaced);

      return { ok: true, value: savedOrder };
    }

    return { ok: false, error: reservationAttemptsExhausted() };
  });
}
```

The refactor exposes normalization, pricing, authorization, persistence, and publication as named stages while retaining the concurrent reads, three reservation attempts, original backoff timing—including the final failed-attempt sleep—and existing transaction/effect ordering. The query-builder chain remains intact because it is an established library API.
~~~~
