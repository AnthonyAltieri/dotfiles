# Python Defaults

Use these defaults when the task is Python. Follow established repository conventions when they make a different deliberate choice.

- Validate boundary data with the repository's canonical parser or model; use `pydantic` when the project already standardizes on it.
- Convert parsed values into canonical internal domain types before business logic.
- Prefer `Literal`, tagged unions, `TypedDict`, dataclasses, typed models, or explicit domain types over dict-shaped implicit contracts.
- Use `NewType` only after runtime parsing; treat it as a static distinction, not runtime validation.
- Reuse existing domain constructors and validators instead of recreating types or relying on unchecked casts.
- Represent closed state-machine or result variants with tagged types, terminate `match` with `typing.assert_never` on Python 3.11+ or `typing_extensions.assert_never` on supported older versions, and rely on the configured type checker for exhaustiveness.
