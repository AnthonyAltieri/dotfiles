# Python Defaults

Apply for Python; defer to deliberate repository conventions.

- Parse boundaries with the canonical model; use Pydantic only when the project standardizes on it.
- Prefer `Literal`, tagged unions, `TypedDict`, dataclasses, typed models, or domain types over implicit dictionary contracts.
- Use `NewType` only after runtime parsing; it is a static distinction, not validation. Reuse canonical constructors and validators.
- Close tagged state/result variants with `typing.assert_never` on Python 3.11+, or `typing_extensions.assert_never` on supported older versions, and rely on the configured type checker for exhaustiveness.
