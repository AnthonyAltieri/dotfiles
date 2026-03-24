# SQLite Notes

Use `sql-read safe-ro --engine sqlite --sqlite-db-path-env-var ...` whenever possible.

## Good starting queries

- Schema overview:
  - `assets/queries/sqlite-schema-overview.sql`
- Inspect a table definition:
  - `assets/queries/sqlite-table-ddl.sql`

## Querying guidance

- Start with `sqlite_schema` to understand tables, views, and indexes before reading data.
- Keep queries narrow and add `limit` when reading raw rows.
- Prefer `json` output unless the user explicitly wants a table.
- Use the manual `query` subcommand only when the user explicitly wants a raw file path.

## Caveats

- The helper opens SQLite databases read-only; it does not create missing files.
- SQLite timeout handling is best-effort and mainly protects against blocked reads rather than every long-running query shape.
- Keep the query guard conservative. If a pattern looks mutation-adjacent, stop and rewrite it as a plain read query.
