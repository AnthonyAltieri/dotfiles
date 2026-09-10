# Postgres Notes

Configure a named Postgres target with an environment variable whose value was arranged out of band:

```bash
sql-read target upsert --name prod-readonly --engine postgres --dsn-env-var PROD_READONLY_URL
```

Pass only the variable name. Do not put a DSN in command text, and do not assume an `export` from a separate tool call will persist. Target setup is outside the blanket-approved surface.

## Good starting queries

- Schema overview:
  - `assets/queries/postgres-schema-overview.sql`
- Column details for a known table:
  - `assets/queries/postgres-table-columns.sql`

## Catalog patterns

- List non-system tables:
  - Query `information_schema.tables`
  - Exclude `pg_catalog` and `information_schema`
- List columns:
  - Query `information_schema.columns`
  - Order by `ordinal_position`
- Check indexes:
  - Query `pg_indexes`
- Estimate row counts:
  - Query `pg_class.reltuples` for cheap estimates when exact `count(*)` would be expensive

## Querying guidance

- Start with schema discovery before data reads.
- Prefer `limit`, exact predicates, or aggregates over wide scans.
- Alias duplicate columns; the helper rejects duplicate output names on Postgres.
- Use `json` output unless the user explicitly asks for a table.
- Execute through the stored target: `sql-read run --target prod-readonly --file <query.sql> --format json`.

## Caveats

- The helper forces a read-only transaction and statement timeout, but that is still not a substitute for a read-only role.
- `SELECT ... FOR UPDATE` and other locking or write-adjacent reads should be considered out of scope.
- Raw DSN arguments are not supported. If the environment variable is unavailable to the helper process, ask the user to provide it through an out-of-band launch or secret-management mechanism.
