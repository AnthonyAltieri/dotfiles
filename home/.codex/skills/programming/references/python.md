# Python Defaults

Use these defaults when the task is Python.

- Validate boundary data with `pydantic` or an equivalent parsing model before internal use.
- Prefer `Literal`, tagged unions, `TypedDict`, dataclasses, or explicit domain types over dict-shaped implicit contracts.
- Use `match` and closed variants when state machines or result kinds need to stay exhaustive.
- Prefer return-value or result modeling for expected failures instead of exception-driven control flow.
- Keep business logic as functions over typed values; use classes for real stateful collaborators, resources, or lifecycle.
- Keep mutation localized; favor pure transformations when performance does not require in-place updates.
