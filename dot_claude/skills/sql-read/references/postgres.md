# Postgres Notes

Use `sql-read safe-ro --engine postgres --dsn-env-var ...` whenever possible.

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

## Caveats

- The helper forces a read-only transaction and statement timeout, but that is still not a substitute for a read-only role.
- `SELECT ... FOR UPDATE` and other locking or write-adjacent reads should be considered out of scope.
- Keep raw DSNs on the manual `query` path only. `safe-ro` should stay env-var-only.
