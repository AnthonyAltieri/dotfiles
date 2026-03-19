use postgres::{Client, NoTls};
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags};
use serde_json::{json, Number, Value};
use sqlparser::ast::Statement;
use sqlparser::dialect::{PostgreSqlDialect, SQLiteDialect};
use sqlparser::parser::Parser;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const DEFAULT_MAX_ROWS: usize = 200;
const DEFAULT_TIMEOUT_MS: u64 = 5_000;
const DEFAULT_FORMAT: OutputFormat = OutputFormat::Json;
const HELP_TEXT: &str = "\
sql-read

Usage:
  sql-read safe-ro --engine postgres --dsn-env-var <ENV_VAR> [--file <PATH>] [--format json|table|tsv] [--max-rows <N>] [--timeout-ms <N>]
  sql-read safe-ro --engine sqlite --sqlite-db-path-env-var <ENV_VAR> [--file <PATH>] [--format json|table|tsv] [--max-rows <N>] [--timeout-ms <N>]
  sql-read query --engine postgres (--dsn-env-var <ENV_VAR> | --dsn <RAW_DSN>) [--file <PATH>] [--format json|table|tsv] [--max-rows <N>] [--timeout-ms <N>]
  sql-read query --engine sqlite (--sqlite-db-path-env-var <ENV_VAR> | --sqlite-db-path <RAW_PATH>) [--file <PATH>] [--format json|table|tsv] [--max-rows <N>] [--timeout-ms <N>]

Notes:
  safe-ro is the approval-friendly env-var-only path.
  query is the manual exception path.
  Query text is read from --file or stdin.
";

#[derive(Debug, PartialEq)]
pub enum CliError {
    Help(String),
    Message(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Subcommand {
    SafeRo,
    Query,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Engine {
    Postgres,
    Sqlite,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OutputFormat {
    Json,
    Table,
    Tsv,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct CliConfig {
    subcommand: Subcommand,
    engine: Engine,
    dsn_env_var: Option<String>,
    dsn: Option<String>,
    sqlite_db_path_env_var: Option<String>,
    sqlite_db_path: Option<String>,
    file: Option<PathBuf>,
    format: OutputFormat,
    max_rows: usize,
    timeout_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ExecutionPlan {
    engine: Engine,
    target: ResolvedTarget,
    query_text: String,
    format: OutputFormat,
    max_rows: usize,
    timeout_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum ResolvedTargetKind {
    PostgresDsn,
    SqlitePath,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ResolvedTarget {
    kind: ResolvedTargetKind,
    value: String,
    mode: &'static str,
    name: String,
    secrets: Vec<String>,
}

#[derive(Clone, Debug, PartialEq)]
struct QueryResult {
    engine: &'static str,
    target_mode: &'static str,
    target_name: String,
    columns: Vec<String>,
    rows: Vec<Vec<Value>>,
    truncated: bool,
    duration_ms: u64,
}

pub fn run_from_env() -> Result<String, CliError> {
    run_args(env::args(), None)
}

pub fn run_args<I, S>(args: I, stdin_override: Option<&str>) -> Result<String, CliError>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let args: Vec<String> = args.into_iter().map(Into::into).collect();
    let config = parse_cli(&args)?;
    let query_text =
        load_query(config.file.as_deref(), stdin_override).map_err(CliError::Message)?;
    let plan = resolve_plan(&config, query_text).map_err(CliError::Message)?;
    let result = execute_plan(&plan)
        .map_err(|err| CliError::Message(redact_error(&err, &plan.target.secrets)))?;
    render_output(&result, plan.format).map_err(CliError::Message)
}

fn parse_cli(args: &[String]) -> Result<CliConfig, CliError> {
    if args.len() <= 1 {
        return Err(CliError::Help(HELP_TEXT.to_string()));
    }

    let mut index = 1;
    if matches!(args[index].as_str(), "--help" | "-h" | "help") {
        return Err(CliError::Help(HELP_TEXT.to_string()));
    }

    let subcommand = match args[index].as_str() {
        "safe-ro" => Subcommand::SafeRo,
        "query" => Subcommand::Query,
        other => {
            return Err(CliError::Message(format!(
                "Unknown subcommand `{other}`. Expected `safe-ro` or `query`."
            )));
        }
    };
    index += 1;

    let mut engine = None;
    let mut dsn_env_var = None;
    let mut dsn = None;
    let mut sqlite_db_path_env_var = None;
    let mut sqlite_db_path = None;
    let mut file = None;
    let mut format = DEFAULT_FORMAT;
    let mut max_rows = DEFAULT_MAX_ROWS;
    let mut timeout_ms = DEFAULT_TIMEOUT_MS;

    while index < args.len() {
        let flag = args[index].as_str();
        match flag {
            "--help" | "-h" => return Err(CliError::Help(HELP_TEXT.to_string())),
            "--engine" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                engine = Some(parse_engine(value).map_err(CliError::Message)?);
            }
            "--dsn-env-var" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut dsn_env_var, value.to_string(), flag).map_err(CliError::Message)?;
            }
            "--dsn" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut dsn, value.to_string(), flag).map_err(CliError::Message)?;
            }
            "--sqlite-db-path-env-var" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut sqlite_db_path_env_var, value.to_string(), flag)
                    .map_err(CliError::Message)?;
            }
            "--sqlite-db-path" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut sqlite_db_path, value.to_string(), flag)
                    .map_err(CliError::Message)?;
            }
            "--file" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut file, PathBuf::from(value), flag).map_err(CliError::Message)?;
            }
            "--format" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                format = parse_format(value).map_err(CliError::Message)?;
            }
            "--max-rows" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                max_rows = value.parse::<usize>().map_err(|_| {
                    CliError::Message(format!(
                        "Invalid value `{value}` for {flag}. Expected a non-negative integer."
                    ))
                })?;
            }
            "--timeout-ms" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                timeout_ms = value.parse::<u64>().map_err(|_| {
                    CliError::Message(format!(
                        "Invalid value `{value}` for {flag}. Expected a non-negative integer."
                    ))
                })?;
            }
            other if other.starts_with("--") => {
                return Err(CliError::Message(format!("Unknown flag `{other}`.")));
            }
            other => {
                return Err(CliError::Message(format!(
                    "Unexpected positional argument `{other}`. Query text must come from --file or stdin."
                )));
            }
        }
        index += 1;
    }

    let engine =
        engine.ok_or_else(|| CliError::Message("Missing required flag `--engine`.".to_string()))?;

    Ok(CliConfig {
        subcommand,
        engine,
        dsn_env_var,
        dsn,
        sqlite_db_path_env_var,
        sqlite_db_path,
        file,
        format,
        max_rows,
        timeout_ms,
    })
}

fn next_value<'a>(args: &'a [String], index: &mut usize, flag: &str) -> Result<&'a str, String> {
    *index += 1;
    args.get(*index)
        .map(|value| value.as_str())
        .ok_or_else(|| format!("Missing value for {flag}."))
}

fn parse_engine(value: &str) -> Result<Engine, String> {
    match value {
        "postgres" => Ok(Engine::Postgres),
        "sqlite" => Ok(Engine::Sqlite),
        _ => Err(format!(
            "Unsupported engine `{value}`. Expected `postgres` or `sqlite`."
        )),
    }
}

fn parse_format(value: &str) -> Result<OutputFormat, String> {
    match value {
        "json" => Ok(OutputFormat::Json),
        "table" => Ok(OutputFormat::Table),
        "tsv" => Ok(OutputFormat::Tsv),
        _ => Err(format!(
            "Unsupported format `{value}`. Expected `json`, `table`, or `tsv`."
        )),
    }
}

fn set_once<T>(slot: &mut Option<T>, value: T, flag: &str) -> Result<(), String> {
    if slot.is_some() {
        return Err(format!("Flag `{flag}` was provided more than once."));
    }
    *slot = Some(value);
    Ok(())
}

fn load_query(file: Option<&Path>, stdin_override: Option<&str>) -> Result<String, String> {
    let query = match file {
        Some(path) => fs::read_to_string(path)
            .map_err(|err| format!("Failed to read query file `{}`: {err}", path.display()))?,
        None => match stdin_override {
            Some(value) => value.to_string(),
            None => {
                let mut buffer = String::new();
                io::stdin()
                    .read_to_string(&mut buffer)
                    .map_err(|err| format!("Failed to read stdin: {err}"))?;
                buffer
            }
        },
    };

    if query.trim().is_empty() {
        return Err("Query input is empty. Pass --file or pipe a SQL query on stdin.".to_string());
    }

    Ok(query)
}

fn resolve_plan(config: &CliConfig, query_text: String) -> Result<ExecutionPlan, String> {
    validate_query(config.engine, &query_text)?;
    let target = resolve_target(config)?;

    Ok(ExecutionPlan {
        engine: config.engine,
        target,
        query_text,
        format: config.format,
        max_rows: config.max_rows,
        timeout_ms: config.timeout_ms,
    })
}

fn resolve_target(config: &CliConfig) -> Result<ResolvedTarget, String> {
    match (config.subcommand, config.engine) {
        (Subcommand::SafeRo, Engine::Postgres) => {
            if config.dsn.is_some()
                || config.sqlite_db_path.is_some()
                || config.sqlite_db_path_env_var.is_some()
            {
                return Err("`safe-ro --engine postgres` only accepts `--dsn-env-var`.".to_string());
            }
            let env_name = config.dsn_env_var.as_deref().ok_or_else(|| {
                "`safe-ro --engine postgres` requires `--dsn-env-var`.".to_string()
            })?;
            let value = read_env_var(env_name)?;
            Ok(ResolvedTarget {
                kind: ResolvedTargetKind::PostgresDsn,
                value: value.clone(),
                mode: "env-var",
                name: env_name.to_string(),
                secrets: vec![value],
            })
        }
        (Subcommand::SafeRo, Engine::Sqlite) => {
            if config.dsn.is_some()
                || config.dsn_env_var.is_some()
                || config.sqlite_db_path.is_some()
            {
                return Err(
                    "`safe-ro --engine sqlite` only accepts `--sqlite-db-path-env-var`."
                        .to_string(),
                );
            }
            let env_name = config.sqlite_db_path_env_var.as_deref().ok_or_else(|| {
                "`safe-ro --engine sqlite` requires `--sqlite-db-path-env-var`.".to_string()
            })?;
            let value = read_env_var(env_name)?;
            Ok(ResolvedTarget {
                kind: ResolvedTargetKind::SqlitePath,
                value: value.clone(),
                mode: "env-var",
                name: env_name.to_string(),
                secrets: vec![value],
            })
        }
        (Subcommand::Query, Engine::Postgres) => {
            if config.sqlite_db_path.is_some() || config.sqlite_db_path_env_var.is_some() {
                return Err(
                    "`query --engine postgres` only accepts Postgres target flags.".to_string(),
                );
            }
            match (config.dsn_env_var.as_deref(), config.dsn.as_deref()) {
                (Some(_), Some(_)) => Err(
                    "`query --engine postgres` accepts either `--dsn-env-var` or `--dsn`, not both."
                        .to_string(),
                ),
                (None, None) => Err(
                    "`query --engine postgres` requires `--dsn-env-var` or `--dsn`.".to_string(),
                ),
                (Some(env_name), None) => {
                    let value = read_env_var(env_name)?;
                    Ok(ResolvedTarget {
                        kind: ResolvedTargetKind::PostgresDsn,
                        value: value.clone(),
                        mode: "env-var",
                        name: env_name.to_string(),
                        secrets: vec![value],
                    })
                }
                (None, Some(value)) => Ok(ResolvedTarget {
                    kind: ResolvedTargetKind::PostgresDsn,
                    value: value.to_string(),
                    mode: "raw",
                    name: "provided".to_string(),
                    secrets: vec![value.to_string()],
                }),
            }
        }
        (Subcommand::Query, Engine::Sqlite) => {
            if config.dsn.is_some() || config.dsn_env_var.is_some() {
                return Err("`query --engine sqlite` only accepts SQLite target flags.".to_string());
            }
            match (
                config.sqlite_db_path_env_var.as_deref(),
                config.sqlite_db_path.as_deref(),
            ) {
                (Some(_), Some(_)) => Err(
                    "`query --engine sqlite` accepts either `--sqlite-db-path-env-var` or `--sqlite-db-path`, not both."
                        .to_string(),
                ),
                (None, None) => Err(
                    "`query --engine sqlite` requires `--sqlite-db-path-env-var` or `--sqlite-db-path`."
                        .to_string(),
                ),
                (Some(env_name), None) => {
                    let value = read_env_var(env_name)?;
                    Ok(ResolvedTarget {
                        kind: ResolvedTargetKind::SqlitePath,
                        value: value.clone(),
                        mode: "env-var",
                        name: env_name.to_string(),
                        secrets: vec![value],
                    })
                }
                (None, Some(value)) => Ok(ResolvedTarget {
                    kind: ResolvedTargetKind::SqlitePath,
                    value: value.to_string(),
                    mode: "raw",
                    name: "provided".to_string(),
                    secrets: vec![value.to_string()],
                }),
            }
        }
    }
}

fn read_env_var(name: &str) -> Result<String, String> {
    let value = env::var(name).map_err(|_| format!("Environment variable `{name}` is not set."))?;
    if value.trim().is_empty() {
        return Err(format!("Environment variable `{name}` is empty."));
    }
    Ok(value)
}

fn validate_query(engine: Engine, query_text: &str) -> Result<(), String> {
    let statements = match engine {
        Engine::Postgres => {
            let dialect = PostgreSqlDialect {};
            Parser::parse_sql(&dialect, query_text)
        }
        Engine::Sqlite => {
            let dialect = SQLiteDialect {};
            Parser::parse_sql(&dialect, query_text)
        }
    }
    .map_err(|err| format!("Failed to parse SQL: {err}"))?;

    if statements.len() != 1 {
        return Err("Only a single read query is allowed.".to_string());
    }

    match &statements[0] {
        Statement::Query(_) => Ok(()),
        _ => Err(
            "Only read queries (`SELECT`, `WITH ... SELECT`, or `VALUES`) are allowed.".to_string(),
        ),
    }
}

fn execute_plan(plan: &ExecutionPlan) -> Result<QueryResult, String> {
    match plan.target.kind {
        ResolvedTargetKind::PostgresDsn => execute_postgres(plan),
        ResolvedTargetKind::SqlitePath => execute_sqlite(plan),
    }
}

fn execute_postgres(plan: &ExecutionPlan) -> Result<QueryResult, String> {
    let start = Instant::now();
    let mut client = Client::connect(&plan.target.value, NoTls)
        .map_err(|err| format!("Failed to connect to Postgres: {err}"))?;
    let mut transaction = client
        .transaction()
        .map_err(|err| format!("Failed to start Postgres transaction: {err}"))?;
    transaction
        .batch_execute("SET TRANSACTION READ ONLY")
        .map_err(|err| format!("Failed to force Postgres read-only mode: {err}"))?;
    transaction
        .batch_execute(&format!(
            "SET LOCAL statement_timeout = {}",
            plan.timeout_ms
        ))
        .map_err(|err| format!("Failed to apply Postgres statement timeout: {err}"))?;

    let normalized_query = normalize_query(&plan.query_text);
    let statement = transaction
        .prepare(&normalized_query)
        .map_err(|err| format!("Failed to prepare Postgres query: {err}"))?;
    let columns: Vec<String> = statement
        .columns()
        .iter()
        .map(|column| column.name().to_string())
        .collect();
    ensure_unique_columns(&columns)?;

    let wrapped_query = wrap_postgres_query(&normalized_query, &columns, plan.max_rows + 1);
    let rows = transaction
        .query(&wrapped_query, &[])
        .map_err(|err| format!("Postgres query failed: {err}"))?;

    let mut values = Vec::with_capacity(rows.len());
    for row in rows {
        let value: Value = row.get(0);
        match value {
            Value::Array(items) => values.push(items),
            _ => {
                return Err(
                    "Postgres helper expected each row to serialize as a JSON array.".to_string(),
                )
            }
        }
    }

    transaction
        .rollback()
        .map_err(|err| format!("Failed to roll back Postgres transaction: {err}"))?;

    Ok(finalize_result(
        "postgres",
        plan,
        columns,
        values,
        start.elapsed(),
    ))
}

fn execute_sqlite(plan: &ExecutionPlan) -> Result<QueryResult, String> {
    let start = Instant::now();
    let connection = Connection::open_with_flags(
        &plan.target.value,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )
    .map_err(|err| format!("Failed to open SQLite database: {err}"))?;
    connection
        .busy_timeout(Duration::from_millis(plan.timeout_ms))
        .map_err(|err| format!("Failed to apply SQLite timeout: {err}"))?;

    let normalized_query = normalize_query(&plan.query_text);
    let mut statement = connection
        .prepare(&normalized_query)
        .map_err(|err| format!("Failed to prepare SQLite query: {err}"))?;
    let columns: Vec<String> = statement
        .column_names()
        .iter()
        .map(|name| name.to_string())
        .collect();

    let mut rows = statement
        .query([])
        .map_err(|err| format!("SQLite query failed: {err}"))?;
    let mut values = Vec::new();

    while let Some(row) = rows
        .next()
        .map_err(|err| format!("SQLite query failed: {err}"))?
    {
        if values.len() > plan.max_rows {
            break;
        }

        let mut rendered_row = Vec::with_capacity(columns.len());
        for index in 0..columns.len() {
            let value = row
                .get_ref(index)
                .map(sqlite_value_to_json)
                .map_err(|err| format!("Failed to read SQLite value: {err}"))?;
            rendered_row.push(value);
        }
        values.push(rendered_row);
    }

    Ok(finalize_result(
        "sqlite",
        plan,
        columns,
        values,
        start.elapsed(),
    ))
}

fn finalize_result(
    engine: &'static str,
    plan: &ExecutionPlan,
    columns: Vec<String>,
    mut rows: Vec<Vec<Value>>,
    duration: Duration,
) -> QueryResult {
    let truncated = rows.len() > plan.max_rows;
    if truncated {
        rows.truncate(plan.max_rows);
    }

    QueryResult {
        engine,
        target_mode: plan.target.mode,
        target_name: plan.target.name.clone(),
        columns,
        rows,
        truncated,
        duration_ms: duration.as_millis() as u64,
    }
}

fn normalize_query(query_text: &str) -> String {
    query_text.trim().trim_end_matches(';').trim().to_string()
}

fn ensure_unique_columns(columns: &[String]) -> Result<(), String> {
    let mut seen = HashSet::new();
    for name in columns {
        if !seen.insert(name.as_str()) {
            return Err(
                "Postgres queries with duplicate column names are not supported. Alias duplicate columns before running the helper."
                    .to_string(),
            );
        }
    }
    Ok(())
}

fn wrap_postgres_query(query: &str, columns: &[String], limit: usize) -> String {
    let mut json_args = String::new();
    for (index, column) in columns.iter().enumerate() {
        if index > 0 {
            json_args.push_str(", ");
        }
        json_args.push_str("to_jsonb(_sql_read_row.");
        json_args.push_str(&quote_pg_identifier(column));
        json_args.push(')');
    }

    format!("select json_build_array({json_args}) from ({query}) as _sql_read_row limit {limit}")
}

fn quote_pg_identifier(identifier: &str) -> String {
    let escaped = identifier.replace('"', "\"\"");
    format!("\"{escaped}\"")
}

fn sqlite_value_to_json(value: ValueRef<'_>) -> Value {
    match value {
        ValueRef::Null => Value::Null,
        ValueRef::Integer(number) => Value::Number(Number::from(number)),
        ValueRef::Real(number) => Number::from_f64(number)
            .map(Value::Number)
            .unwrap_or(Value::Null),
        ValueRef::Text(text) => Value::String(String::from_utf8_lossy(text).into_owned()),
        ValueRef::Blob(bytes) => Value::String(to_hex(bytes)),
    }
}

fn to_hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(hex_digit(byte >> 4));
        out.push(hex_digit(byte & 0x0f));
    }
    out
}

fn hex_digit(value: u8) -> char {
    match value {
        0..=9 => (b'0' + value) as char,
        _ => (b'a' + (value - 10)) as char,
    }
}

fn render_output(result: &QueryResult, format: OutputFormat) -> Result<String, String> {
    match format {
        OutputFormat::Json => Ok(render_json(result)),
        OutputFormat::Table => render_table(result),
        OutputFormat::Tsv => render_tsv(result),
    }
}

fn render_json(result: &QueryResult) -> String {
    json!({
        "engine": result.engine,
        "target": {
            "mode": result.target_mode,
            "name": result.target_name,
        },
        "columns": result.columns,
        "rows": result.rows,
        "row_count": result.rows.len(),
        "truncated": result.truncated,
        "duration_ms": result.duration_ms,
    })
    .to_string()
}

fn render_table(result: &QueryResult) -> Result<String, String> {
    let string_rows = stringify_rows(&result.rows)?;
    let mut widths: Vec<usize> = result.columns.iter().map(|column| column.len()).collect();

    for row in &string_rows {
        for (index, value) in row.iter().enumerate() {
            if let Some(width) = widths.get_mut(index) {
                *width = (*width).max(value.len());
            }
        }
    }

    let header = join_table_row(&result.columns, &widths);
    let separator = widths
        .iter()
        .map(|width| format!("| {:-<1$} ", "", *width))
        .collect::<Vec<_>>()
        .join("")
        + "|";

    let mut lines = vec![header, separator];
    for row in string_rows {
        lines.push(join_table_row(&row, &widths));
    }

    Ok(lines.join("\n"))
}

fn join_table_row(values: &[String], widths: &[usize]) -> String {
    let mut line = String::new();
    for (index, value) in values.iter().enumerate() {
        let width = widths.get(index).copied().unwrap_or(value.len());
        line.push_str("| ");
        line.push_str(value);
        for _ in value.len()..width {
            line.push(' ');
        }
        line.push(' ');
    }
    line.push('|');
    line
}

fn render_tsv(result: &QueryResult) -> Result<String, String> {
    let string_rows = stringify_rows(&result.rows)?;
    let mut lines = Vec::with_capacity(string_rows.len() + 1);
    lines.push(result.columns.join("\t"));
    for row in string_rows {
        lines.push(row.join("\t"));
    }
    Ok(lines.join("\n"))
}

fn stringify_rows(rows: &[Vec<Value>]) -> Result<Vec<Vec<String>>, String> {
    rows.iter()
        .map(|row| row.iter().map(stringify_value).collect())
        .collect()
}

fn stringify_value(value: &Value) -> Result<String, String> {
    let rendered = match value {
        Value::Null => "null".to_string(),
        Value::Bool(boolean) => boolean.to_string(),
        Value::Number(number) => number.to_string(),
        Value::String(text) => text.clone(),
        Value::Array(_) | Value::Object(_) => serde_json::to_string(value)
            .map_err(|err| format!("Failed to render nested JSON value: {err}"))?,
    };

    Ok(rendered
        .replace('\t', " ")
        .replace('\n', "\\n")
        .replace('\r', "\\r"))
}

fn redact_error(message: &str, secrets: &[String]) -> String {
    let mut redacted = message.to_string();
    for secret in secrets {
        if !secret.is_empty() {
            redacted = redacted.replace(secret, "[REDACTED]");
        }
    }
    redacted
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn safe_ro_postgres_requires_env_var_only() {
        let error = parse_cli(&args(&[
            "sql-read",
            "safe-ro",
            "--engine",
            "postgres",
            "--dsn",
            "postgres://localhost/test",
        ]))
        .expect("cli parse");
        let result = resolve_plan(&error, "select 1".to_string());

        assert_eq!(
            result.expect_err("should reject"),
            "`safe-ro --engine postgres` only accepts `--dsn-env-var`."
        );
    }

    #[test]
    fn query_postgres_accepts_raw_dsn() {
        let config = parse_cli(&args(&[
            "sql-read",
            "query",
            "--engine",
            "postgres",
            "--dsn",
            "postgres://writer",
        ]))
        .expect("cli parse");
        let plan = resolve_plan(&config, "select 1".to_string()).expect("plan");

        assert_eq!(plan.target.mode, "raw");
        assert_eq!(plan.target.name, "provided");
    }

    #[test]
    fn safe_ro_sqlite_requires_env_var() {
        let config =
            parse_cli(&args(&["sql-read", "safe-ro", "--engine", "sqlite"])).expect("cli parse");
        let error = resolve_plan(&config, "select 1".to_string()).expect_err("should reject");

        assert_eq!(
            error,
            "`safe-ro --engine sqlite` requires `--sqlite-db-path-env-var`."
        );
    }

    #[test]
    fn rejects_multiple_statements() {
        let error =
            validate_query(Engine::Postgres, "select 1; select 2;").expect_err("should reject");
        assert_eq!(error, "Only a single read query is allowed.");
    }

    #[test]
    fn rejects_non_read_statement() {
        let error =
            validate_query(Engine::Postgres, "delete from widgets;").expect_err("should reject");
        assert_eq!(
            error,
            "Only read queries (`SELECT`, `WITH ... SELECT`, or `VALUES`) are allowed."
        );
    }

    #[test]
    fn redacts_raw_secrets_from_errors() {
        let message = redact_error(
            "Failed to connect to postgres://user:secret@db.example/app",
            &[String::from("postgres://user:secret@db.example/app")],
        );

        assert_eq!(message, "Failed to connect to [REDACTED]");
    }

    #[test]
    fn render_json_reports_truncation_and_row_count() {
        let rendered = render_json(&QueryResult {
            engine: "sqlite",
            target_mode: "env-var",
            target_name: "LOCAL_DB".to_string(),
            columns: vec!["id".to_string()],
            rows: vec![vec![Value::Number(Number::from(1))]],
            truncated: true,
            duration_ms: 12,
        });
        let parsed: Value = serde_json::from_str(&rendered).expect("json");

        assert_eq!(
            parsed.pointer("/row_count").and_then(Value::as_u64),
            Some(1)
        );
        assert_eq!(
            parsed.pointer("/truncated").and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            parsed.pointer("/target/name").and_then(Value::as_str),
            Some("LOCAL_DB")
        );
    }

    #[test]
    fn sqlite_safe_ro_executes_select_and_returns_json() {
        let path = sqlite_fixture_db();
        let env_name = "SQL_READ_TEST_SQLITE_DB_SELECT";
        env::set_var(env_name, &path);

        let output = run_args(
            args(&[
                "sql-read",
                "safe-ro",
                "--engine",
                "sqlite",
                "--sqlite-db-path-env-var",
                env_name,
            ]),
            Some("select id, name from widgets order by id"),
        )
        .expect("run");

        let parsed: Value = serde_json::from_str(&output).expect("json");
        assert_eq!(
            parsed.pointer("/engine").and_then(Value::as_str),
            Some("sqlite")
        );
        assert_eq!(
            parsed.pointer("/row_count").and_then(Value::as_u64),
            Some(2)
        );
        assert_eq!(
            parsed.pointer("/rows/0/1").and_then(Value::as_str),
            Some("alpha")
        );

        let _ = fs::remove_file(path);
        env::remove_var(env_name);
    }

    #[test]
    fn sqlite_safe_ro_rejects_write_statement_before_execution() {
        let path = sqlite_fixture_db();
        let env_name = "SQL_READ_TEST_SQLITE_DB_WRITE";
        env::set_var(env_name, &path);

        let error = run_args(
            args(&[
                "sql-read",
                "safe-ro",
                "--engine",
                "sqlite",
                "--sqlite-db-path-env-var",
                env_name,
            ]),
            Some("update widgets set name = 'oops'"),
        )
        .expect_err("should reject");

        assert_eq!(
            error,
            CliError::Message(
                "Only read queries (`SELECT`, `WITH ... SELECT`, or `VALUES`) are allowed."
                    .to_string()
            )
        );

        let _ = fs::remove_file(path);
        env::remove_var(env_name);
    }

    #[test]
    #[ignore = "requires SQL_READ_TEST_POSTGRES_DSN"]
    fn postgres_query_runs_in_read_only_mode() {
        let dsn = env::var("SQL_READ_TEST_POSTGRES_DSN").expect("test dsn");
        let output = run_args(
            args(&["sql-read", "query", "--engine", "postgres", "--dsn", &dsn]),
            Some("select 1 as value"),
        )
        .expect("run");
        let parsed: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            parsed.pointer("/row_count").and_then(Value::as_u64),
            Some(1)
        );
    }

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    fn sqlite_fixture_db() -> String {
        let mut path = env::temp_dir();
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time")
            .as_nanos();
        path.push(format!("sql-read-{unique}.sqlite"));

        let connection = Connection::open(&path).expect("create sqlite db");
        connection
            .execute_batch(
                "
                create table widgets (
                  id integer primary key,
                  name text not null
                );
                insert into widgets (name) values ('alpha');
                insert into widgets (name) values ('beta');
                ",
            )
            .expect("seed sqlite db");
        drop(connection);

        path.to_string_lossy().into_owned()
    }
}
