# SQLite Notes

Configure a named SQLite target with an environment variable whose value was arranged out of band:

```bash
sql-read target upsert --name local-app --engine sqlite --sqlite-db-path-env-var LOCAL_APP_DB
```

Pass only the variable name. Do not put the database path in command text, and do not assume an `export` from a separate tool call will persist. Target setup is outside the blanket-approved surface.

## Good starting queries

- Schema overview:
  - `assets/queries/sqlite-schema-overview.sql`
- Inspect a table definition:
  - `assets/queries/sqlite-table-ddl.sql`

## Querying guidance

- Start with `sqlite_schema` to understand tables, views, and indexes before reading data.
- Keep queries narrow and add `limit` when reading raw rows.
- Prefer `json` output unless the user explicitly wants a table.
- Execute through the stored target: `sql-read run --target local-app --file <query.sql> --format json`.

## Caveats

- The helper opens SQLite databases read-only; it does not create missing files.
- SQLite timeout handling is best-effort and mainly protects against blocked reads rather than every long-running query shape.
- Keep the query guard conservative. If a pattern looks mutation-adjacent, stop and rewrite it as a plain read query.
- Raw SQLite path arguments are not supported. If the environment variable is unavailable to the helper process, ask the user to provide it through an out-of-band launch or secret-management mechanism.
