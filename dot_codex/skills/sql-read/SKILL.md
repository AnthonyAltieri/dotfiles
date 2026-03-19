---
name: sql-read
description: Use when a user needs live read-only Postgres or SQLite inspection; prefer the blanket-approvable `sql-read safe-ro` path, inspect schema first, and keep queries narrow.
metadata:
  short-description: Read Postgres or SQLite safely
---

# SQL Read

Use the bundled Rust helper to inspect Postgres or SQLite data in read-only mode.

Trigger this skill for:
- live schema inspection
- ad hoc read-only analysis queries
- fast table or column lookups when the answer lives in a database

Do not use it for:
- writes, migrations, or backfills
- admin tasks
- general interactive shell work

## Quick Start

1. Prefer the approval-friendly `safe-ro` path.
   - `cargo run --quiet --release --manifest-path "$CODEX_HOME/skills/sql-read/scripts/Cargo.toml" -- safe-ro --engine postgres --dsn-env-var PROD_READONLY_URL --file "$CODEX_HOME/skills/sql-read/assets/queries/postgres-schema-overview.sql"`
2. Use SQLite read-only via an env var, not a raw path, when you want the stable command surface.
   - `cargo run --quiet --release --manifest-path "$CODEX_HOME/skills/sql-read/scripts/Cargo.toml" -- safe-ro --engine sqlite --sqlite-db-path-env-var LOCAL_APP_DB --file "$CODEX_HOME/skills/sql-read/assets/queries/sqlite-schema-overview.sql"`
3. Use `query` only when the user is explicitly leaving the blanket-approved path.
   - `cargo run --quiet --release --manifest-path "$CODEX_HOME/skills/sql-read/scripts/Cargo.toml" -- query --engine postgres --dsn "$DATABASE_URL" --file /tmp/query.sql`

## Workflow

1. Start with schema inspection.
   - Use the bundled query templates in `assets/queries/`.
   - Load the relevant engine notes from `references/postgres.md` or `references/sqlite.md` only when needed.
2. Prefer `sql-read safe-ro`.
   - `safe-ro` accepts env-var targets only.
   - This is the only path meant for blanket approval.
3. Keep queries narrow.
   - Ask for aggregates, counts, or explicit filters before scanning large tables.
   - Add an explicit `limit` in the SQL unless the query is already aggregate-only.
4. Prefer JSON output.
   - Use `--format json` by default so the agent sees compact, structured rows.
   - Switch to `table` only when the user explicitly wants a human-readable table.
5. Escalate to `sql-read query` only when needed.
   - Use it when the user explicitly wants a raw DSN or raw SQLite path.
   - Even there, the helper still enforces read-only execution and rejects non-query statements.

## Output

Default JSON output is compact and stable:

```json
{"engine":"postgres","target":{"mode":"env-var","name":"PROD_READONLY_URL"},"columns":["id","email"],"rows":[[1,"a@example.com"]],"row_count":1,"truncated":false,"duration_ms":38}
```

## Bundled Resources

- `scripts/sql-read`
  - `safe-ro` is the approval-friendly, env-var-only path.
  - `query` is the manual exception path that still enforces read-only execution.
- `references/postgres.md`
  - Catalog-query patterns and Postgres-specific caveats.
- `references/sqlite.md`
  - SQLite schema-inspection patterns and read-only caveats.
- `assets/queries/`
  - Reusable schema-inspection and table-introspection query templates.

## Gotchas

- Rust is a control and safety tool here, not a speed win over `psql`.
- Blanket approval should target `sql-read safe-ro:*`, not `sql-read:*`.
- `safe-ro` accepts env vars only; do not add raw `--dsn` or raw `--sqlite-db-path` to the approval-friendly path.
- Read-only enforcement in the helper is defense-in-depth, not a substitute for least-privilege credentials.
- Postgres queries with duplicate column names are rejected; alias duplicate columns before running them.
