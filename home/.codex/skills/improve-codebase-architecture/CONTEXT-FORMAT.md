# CONTEXT.md Format

Use this reference only after the user explicitly authorizes creating or updating `CONTEXT.md`. Preserve an existing repository format when one exists; this is the fallback.

Record stable domain language, not implementation plans or a transcript of the design conversation. Make the smallest change that resolves the agreed ambiguity.

```markdown
# Domain Context

## <Domain area>

### <Canonical term>

<One concise definition in project language.>

- Invariants: <facts that must remain true>
- Relationships: <other canonical terms and how they relate>
- Avoid: <ambiguous or rejected names, only when useful>
```

Omit empty fields. Reuse existing headings and ordering when editing an established file. After writing, read the changed section back and confirm that it states the approved terminology without introducing an architecture decision the user did not authorize.
