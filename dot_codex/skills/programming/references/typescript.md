# TypeScript Defaults

Use these defaults when the task is TypeScript or TSX.

## Boundaries

- Use `zod` or an equivalent runtime schema at boundaries.
- Parse `unknown` into validated input types before it reaches application logic.
- Keep transport DTOs separate from richer internal domain types when they differ.
- Prefer schema-derived types or explicit internal models over hand-maintained duplicate interfaces.

## Types And Control Flow

- Use string literal unions and `as const` objects instead of enums.
- Prefer discriminated unions over boolean flags and loosely related optional fields.
- Use exhaustive `switch` statements with a `never` check when variants must stay closed.
- Prefer `unknown` at boundaries and `never` at impossible states; avoid `any`.
- Use `satisfies` when it preserves literal precision without widening.
- Model expected failures with result shapes or unions before throwing.

## Design

- Name files in lowercase kebab-case.
- Prefer plain objects and functions over classes.
- Use a class only when an instance truly owns mutable state, resources, or lifecycle.
- Keep orchestration functions shallow and domain-named; move mechanics into helpers.

## Compact Pattern

```ts
const paymentStatus = {
  pending: "pending",
  settled: "settled",
  failed: "failed",
} as const;

type PaymentStatus = (typeof paymentStatus)[keyof typeof paymentStatus];

type ChargeResult =
  | { kind: "ok"; receiptId: string }
  | { kind: "retryable-error"; reason: string }
  | { kind: "fatal-error"; reason: string };

function handleChargeResult(result: ChargeResult): string {
  switch (result.kind) {
    case "ok":
      return result.receiptId;
    case "retryable-error":
    case "fatal-error":
      return result.reason;
    default: {
      const exhaustive: never = result;
      return exhaustive;
    }
  }
}
```
