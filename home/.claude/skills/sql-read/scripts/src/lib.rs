use postgres::{Client, NoTls};
use rusqlite::types::ValueRef;
use rusqlite::{Connection, OpenFlags};
use serde::{Deserialize, Serialize};
use serde_json::{json, Number, Value};
use sqlparser::ast::Statement;
use sqlparser::dialect::{PostgreSqlDialect, SQLiteDialect};
use sqlparser::parser::Parser;
use std::collections::{BTreeMap, HashSet};
use std::env;
use std::fs;
use std::io::{self, Read};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const DEFAULT_MAX_ROWS: usize = 200;
const DEFAULT_TIMEOUT_MS: u64 = 5_000;
const DEFAULT_FORMAT: OutputFormat = OutputFormat::Json;
const TARGET_STORE_VERSION: u32 = 1;
const TARGET_STORE_FILE: &str = "targets.json";
const HELP_TEXT: &str = "\
sql-read

Usage:
  sql-read run --state-dir <DIR> --target <NAME> [--file <PATH>] [--format json|table|tsv] [--max-rows <N>] [--timeout-ms <N>]
  sql-read target upsert --state-dir <DIR> --name <NAME> --engine postgres (--dsn <RAW_DSN> | --dsn-env-var <ENV_VAR>)
  sql-read target upsert --state-dir <DIR> --name <NAME> --engine sqlite (--sqlite-db-path <RAW_PATH> | --sqlite-db-path-env-var <ENV_VAR>)
  sql-read target list --state-dir <DIR>
  sql-read target remove --state-dir <DIR> --name <NAME>

Notes:
  `run` is the only blanket-approvable execution path.
  Configure a named target first, then run read-only queries against it.
  Query text is read from --file or stdin.
";

#[derive(Debug, PartialEq)]
pub enum CliError {
    Help(String),
    Message(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Engine {
    Postgres,
    Sqlite,
}

impl Engine {
    fn as_str(self) -> &'static str {
        match self {
            Engine::Postgres => "postgres",
            Engine::Sqlite => "sqlite",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum OutputFormat {
    Json,
    Table,
    Tsv,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum Command {
    Run(RunConfig),
    Target(TargetCommand),
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct RunConfig {
    state_dir: PathBuf,
    target: String,
    file: Option<PathBuf>,
    format: OutputFormat,
    max_rows: usize,
    timeout_ms: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum TargetCommand {
    Upsert(UpsertConfig),
    List(ListConfig),
    Remove(RemoveConfig),
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct UpsertConfig {
    state_dir: PathBuf,
    name: String,
    engine: Engine,
    dsn_env_var: Option<String>,
    dsn: Option<String>,
    sqlite_db_path_env_var: Option<String>,
    sqlite_db_path: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ListConfig {
    state_dir: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct RemoveConfig {
    state_dir: PathBuf,
    name: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct ExecutionPlan {
    engine: Engine,
    target_name: String,
    target_value: String,
    query_text: String,
    format: OutputFormat,
    max_rows: usize,
    timeout_ms: u64,
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

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
struct TargetStore {
    version: u32,
    targets: BTreeMap<String, StoredTarget>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
struct StoredTarget {
    engine: Engine,
    value: String,
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
    let command = parse_cli(&args)?;

    match command {
        Command::Run(config) => {
            let query_text =
                load_query(config.file.as_deref(), stdin_override).map_err(CliError::Message)?;
            let plan = resolve_run_plan(&config, query_text).map_err(CliError::Message)?;
            let result = execute_plan(&plan)
                .map_err(|err| CliError::Message(redact_error(&err, &plan.secrets)))?;
            render_output(&result, plan.format).map_err(CliError::Message)
        }
        Command::Target(command) => execute_target_command(&command).map_err(CliError::Message),
    }
}

fn parse_cli(args: &[String]) -> Result<Command, CliError> {
    if args.len() <= 1 {
        return Err(CliError::Help(HELP_TEXT.to_string()));
    }

    match args[1].as_str() {
        "--help" | "-h" | "help" => Err(CliError::Help(HELP_TEXT.to_string())),
        "run" => parse_run_command(args),
        "target" => parse_target_command(args),
        "safe-ro" | "query" => Err(CliError::Message(migration_message(args[1].as_str()))),
        other => Err(CliError::Message(format!(
            "Unknown subcommand `{other}`. Expected `run` or `target`."
        ))),
    }
}

fn parse_run_command(args: &[String]) -> Result<Command, CliError> {
    let mut state_dir = None;
    let mut target = None;
    let mut file = None;
    let mut format = DEFAULT_FORMAT;
    let mut max_rows = DEFAULT_MAX_ROWS;
    let mut timeout_ms = DEFAULT_TIMEOUT_MS;
    let mut index = 2;

    while index < args.len() {
        let flag = args[index].as_str();
        match flag {
            "--help" | "-h" => return Err(CliError::Help(HELP_TEXT.to_string())),
            "--state-dir" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut state_dir, PathBuf::from(value), flag).map_err(CliError::Message)?;
            }
            "--target" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                let normalized = normalize_target_name(value).map_err(CliError::Message)?;
                set_once(&mut target, normalized, flag).map_err(CliError::Message)?;
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
                max_rows = parse_usize_flag(value, flag).map_err(CliError::Message)?;
            }
            "--timeout-ms" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                timeout_ms = parse_u64_flag(value, flag).map_err(CliError::Message)?;
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

    Ok(Command::Run(RunConfig {
        state_dir: state_dir.ok_or_else(|| {
            CliError::Message("`run` requires `--state-dir`.".to_string())
        })?,
        target: target.ok_or_else(|| CliError::Message("`run` requires `--target`.".to_string()))?,
        file,
        format,
        max_rows,
        timeout_ms,
    }))
}

fn parse_target_command(args: &[String]) -> Result<Command, CliError> {
    if args.len() <= 2 {
        return Err(CliError::Message(
            "Missing target subcommand. Expected `upsert`, `list`, or `remove`.".to_string(),
        ));
    }

    match args[2].as_str() {
        "--help" | "-h" | "help" => Err(CliError::Help(HELP_TEXT.to_string())),
        "upsert" => parse_target_upsert(args),
        "list" => parse_target_list(args),
        "remove" => parse_target_remove(args),
        other => Err(CliError::Message(format!(
            "Unknown target subcommand `{other}`. Expected `upsert`, `list`, or `remove`."
        ))),
    }
}

fn parse_target_upsert(args: &[String]) -> Result<Command, CliError> {
    let mut state_dir = None;
    let mut name = None;
    let mut engine = None;
    let mut dsn_env_var = None;
    let mut dsn = None;
    let mut sqlite_db_path_env_var = None;
    let mut sqlite_db_path = None;
    let mut index = 3;

    while index < args.len() {
        let flag = args[index].as_str();
        match flag {
            "--help" | "-h" => return Err(CliError::Help(HELP_TEXT.to_string())),
            "--state-dir" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut state_dir, PathBuf::from(value), flag).map_err(CliError::Message)?;
            }
            "--name" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                let normalized = normalize_target_name(value).map_err(CliError::Message)?;
                set_once(&mut name, normalized, flag).map_err(CliError::Message)?;
            }
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
            other if other.starts_with("--") => {
                return Err(CliError::Message(format!("Unknown flag `{other}`.")));
            }
            other => {
                return Err(CliError::Message(format!(
                    "Unexpected positional argument `{other}`."
                )));
            }
        }
        index += 1;
    }

    let engine = engine.ok_or_else(|| {
        CliError::Message("`target upsert` requires `--engine`.".to_string())
    })?;

    Ok(Command::Target(TargetCommand::Upsert(UpsertConfig {
        state_dir: state_dir.ok_or_else(|| {
            CliError::Message("`target upsert` requires `--state-dir`.".to_string())
        })?,
        name: name.ok_or_else(|| {
            CliError::Message("`target upsert` requires `--name`.".to_string())
        })?,
        engine,
        dsn_env_var,
        dsn,
        sqlite_db_path_env_var,
        sqlite_db_path,
    })))
}

fn parse_target_list(args: &[String]) -> Result<Command, CliError> {
    let mut state_dir = None;
    let mut index = 3;

    while index < args.len() {
        let flag = args[index].as_str();
        match flag {
            "--help" | "-h" => return Err(CliError::Help(HELP_TEXT.to_string())),
            "--state-dir" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut state_dir, PathBuf::from(value), flag).map_err(CliError::Message)?;
            }
            other if other.starts_with("--") => {
                return Err(CliError::Message(format!("Unknown flag `{other}`.")));
            }
            other => {
                return Err(CliError::Message(format!(
                    "Unexpected positional argument `{other}`."
                )));
            }
        }
        index += 1;
    }

    Ok(Command::Target(TargetCommand::List(ListConfig {
        state_dir: state_dir.ok_or_else(|| {
            CliError::Message("`target list` requires `--state-dir`.".to_string())
        })?,
    })))
}

fn parse_target_remove(args: &[String]) -> Result<Command, CliError> {
    let mut state_dir = None;
    let mut name = None;
    let mut index = 3;

    while index < args.len() {
        let flag = args[index].as_str();
        match flag {
            "--help" | "-h" => return Err(CliError::Help(HELP_TEXT.to_string())),
            "--state-dir" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                set_once(&mut state_dir, PathBuf::from(value), flag).map_err(CliError::Message)?;
            }
            "--name" => {
                let value = next_value(args, &mut index, flag).map_err(CliError::Message)?;
                let normalized = normalize_target_name(value).map_err(CliError::Message)?;
                set_once(&mut name, normalized, flag).map_err(CliError::Message)?;
            }
            other if other.starts_with("--") => {
                return Err(CliError::Message(format!("Unknown flag `{other}`.")));
            }
            other => {
                return Err(CliError::Message(format!(
                    "Unexpected positional argument `{other}`."
                )));
            }
        }
        index += 1;
    }

    Ok(Command::Target(TargetCommand::Remove(RemoveConfig {
        state_dir: state_dir.ok_or_else(|| {
            CliError::Message("`target remove` requires `--state-dir`.".to_string())
        })?,
        name: name.ok_or_else(|| {
            CliError::Message("`target remove` requires `--name`.".to_string())
        })?,
    })))
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

fn parse_usize_flag(value: &str, flag: &str) -> Result<usize, String> {
    value.parse::<usize>().map_err(|_| {
        format!("Invalid value `{value}` for {flag}. Expected a non-negative integer.")
    })
}

fn parse_u64_flag(value: &str, flag: &str) -> Result<u64, String> {
    value.parse::<u64>().map_err(|_| {
        format!("Invalid value `{value}` for {flag}. Expected a non-negative integer.")
    })
}

fn set_once<T>(slot: &mut Option<T>, value: T, flag: &str) -> Result<(), String> {
    if slot.is_some() {
        return Err(format!("Flag `{flag}` was provided more than once."));
    }
    *slot = Some(value);
    Ok(())
}

fn normalize_target_name(value: &str) -> Result<String, String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err("Target names must not be empty.".to_string());
    }
    Ok(trimmed.to_string())
}

fn migration_message(subcommand: &str) -> String {
    format!(
        "Subcommand `{subcommand}` was removed. Configure a named target with `sql-read target upsert --state-dir <dir> --name <target> ...`, then execute queries with `sql-read run --state-dir <dir> --target <name> [--file <path>]`."
    )
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

fn resolve_run_plan(config: &RunConfig, query_text: String) -> Result<ExecutionPlan, String> {
    let store = load_target_store_or_default(&config.state_dir)?;
    let targets_file = target_store_path(&config.state_dir);
    let target = store.targets.get(&config.target).ok_or_else(|| {
        format!(
            "Target `{}` not found in `{}`. Create it with `sql-read target upsert --state-dir {} --name {} ...`.",
            config.target,
            targets_file.display(),
            config.state_dir.display(),
            config.target
        )
    })?;
    validate_query(target.engine, &query_text)?;

    Ok(ExecutionPlan {
        engine: target.engine,
        target_name: config.target.clone(),
        target_value: target.value.clone(),
        query_text,
        format: config.format,
        max_rows: config.max_rows,
        timeout_ms: config.timeout_ms,
        secrets: vec![target.value.clone()],
    })
}

fn execute_target_command(command: &TargetCommand) -> Result<String, String> {
    match command {
        TargetCommand::Upsert(config) => upsert_target(config),
        TargetCommand::List(config) => list_targets(config),
        TargetCommand::Remove(config) => remove_target(config),
    }
}

fn upsert_target(config: &UpsertConfig) -> Result<String, String> {
    let target = resolve_upsert_target(config)?;
    let mut store = load_target_store_or_default(&config.state_dir)?;
    store.targets.insert(config.name.clone(), target);
    write_target_store(&config.state_dir, &store)?;

    Ok(json!({
        "action": "upsert",
        "name": config.name,
        "engine": config.engine.as_str(),
    })
    .to_string())
}

fn list_targets(config: &ListConfig) -> Result<String, String> {
    let store = load_target_store_or_default(&config.state_dir)?;
    let targets: Vec<Value> = store
        .targets
        .iter()
        .map(|(name, target)| {
            json!({
                "name": name,
                "engine": target.engine.as_str(),
            })
        })
        .collect();

    Ok(json!({ "targets": targets }).to_string())
}

fn remove_target(config: &RemoveConfig) -> Result<String, String> {
    let mut store = load_target_store_or_default(&config.state_dir)?;
    let path = target_store_path(&config.state_dir);

    if store.targets.remove(&config.name).is_none() {
        return Err(format!(
            "Target `{}` not found in `{}`.",
            config.name,
            path.display()
        ));
    }

    write_target_store(&config.state_dir, &store)?;

    Ok(json!({
        "action": "remove",
        "name": config.name,
        "removed": true,
    })
    .to_string())
}

fn resolve_upsert_target(config: &UpsertConfig) -> Result<StoredTarget, String> {
    match config.engine {
        Engine::Postgres => {
            if config.sqlite_db_path.is_some() || config.sqlite_db_path_env_var.is_some() {
                return Err(
                    "`target upsert --engine postgres` only accepts `--dsn` or `--dsn-env-var`."
                        .to_string(),
                );
            }
            match (config.dsn_env_var.as_deref(), config.dsn.as_deref()) {
                (Some(_), Some(_)) => Err(
                    "`target upsert --engine postgres` accepts either `--dsn` or `--dsn-env-var`, not both."
                        .to_string(),
                ),
                (None, None) => Err(
                    "`target upsert --engine postgres` requires `--dsn` or `--dsn-env-var`."
                        .to_string(),
                ),
                (Some(env_name), None) => Ok(StoredTarget {
                    engine: Engine::Postgres,
                    value: read_env_var(env_name)?,
                }),
                (None, Some(value)) => Ok(StoredTarget {
                    engine: Engine::Postgres,
                    value: normalize_non_empty_value(value, "--dsn")?,
                }),
            }
        }
        Engine::Sqlite => {
            if config.dsn.is_some() || config.dsn_env_var.is_some() {
                return Err(
                    "`target upsert --engine sqlite` only accepts `--sqlite-db-path` or `--sqlite-db-path-env-var`."
                        .to_string(),
                );
            }
            match (
                config.sqlite_db_path_env_var.as_deref(),
                config.sqlite_db_path.as_deref(),
            ) {
                (Some(_), Some(_)) => Err(
                    "`target upsert --engine sqlite` accepts either `--sqlite-db-path` or `--sqlite-db-path-env-var`, not both."
                        .to_string(),
                ),
                (None, None) => Err(
                    "`target upsert --engine sqlite` requires `--sqlite-db-path` or `--sqlite-db-path-env-var`."
                        .to_string(),
                ),
                (Some(env_name), None) => Ok(StoredTarget {
                    engine: Engine::Sqlite,
                    value: read_env_var(env_name)?,
                }),
                (None, Some(value)) => Ok(StoredTarget {
                    engine: Engine::Sqlite,
                    value: normalize_non_empty_value(value, "--sqlite-db-path")?,
                }),
            }
        }
    }
}

fn normalize_non_empty_value(value: &str, flag: &str) -> Result<String, String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(format!("Value for `{flag}` must not be empty."));
    }
    Ok(trimmed.to_string())
}

fn read_env_var(name: &str) -> Result<String, String> {
    let value = env::var(name).map_err(|_| format!("Environment variable `{name}` is not set."))?;
    if value.trim().is_empty() {
        return Err(format!("Environment variable `{name}` is empty."));
    }
    Ok(value)
}

fn target_store_path(state_dir: &Path) -> PathBuf {
    state_dir.join(TARGET_STORE_FILE)
}

fn load_target_store_or_default(state_dir: &Path) -> Result<TargetStore, String> {
    let path = target_store_path(state_dir);
    if !path.exists() {
        return Ok(TargetStore {
            version: TARGET_STORE_VERSION,
            targets: BTreeMap::new(),
        });
    }

    let content = fs::read_to_string(&path)
        .map_err(|err| format!("Failed to read target store `{}`: {err}", path.display()))?;
    let store: TargetStore = serde_json::from_str(&content)
        .map_err(|err| format!("Failed to parse target store `{}`: {err}", path.display()))?;

    if store.version != TARGET_STORE_VERSION {
        return Err(format!(
            "Unsupported target store version `{}` in `{}`.",
            store.version,
            path.display()
        ));
    }

    Ok(store)
}

fn write_target_store(state_dir: &Path, store: &TargetStore) -> Result<(), String> {
    fs::create_dir_all(state_dir)
        .map_err(|err| format!("Failed to create state dir `{}`: {err}", state_dir.display()))?;
    set_permissions(state_dir, 0o700)?;

    let path = target_store_path(state_dir);
    let tmp_path = state_dir.join(format!("{TARGET_STORE_FILE}.tmp"));
    let mut rendered = serde_json::to_vec_pretty(store)
        .map_err(|err| format!("Failed to serialize target store: {err}"))?;
    rendered.push(b'\n');

    fs::write(&tmp_path, rendered)
        .map_err(|err| format!("Failed to write target store `{}`: {err}", tmp_path.display()))?;
    set_permissions(&tmp_path, 0o600)?;
    fs::rename(&tmp_path, &path).map_err(|err| {
        format!(
            "Failed to replace target store `{}` with `{}`: {err}",
            path.display(),
            tmp_path.display()
        )
    })?;
    set_permissions(&path, 0o600)?;

    Ok(())
}

fn set_permissions(path: &Path, mode: u32) -> Result<(), String> {
    #[cfg(unix)]
    {
        let permissions = fs::Permissions::from_mode(mode);
        fs::set_permissions(path, permissions)
            .map_err(|err| format!("Failed to set permissions on `{}`: {err}", path.display()))?;
    }

    #[cfg(not(unix))]
    {
        let _ = (path, mode);
    }

    Ok(())
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
    match plan.engine {
        Engine::Postgres => execute_postgres(plan),
        Engine::Sqlite => execute_sqlite(plan),
    }
}

fn execute_postgres(plan: &ExecutionPlan) -> Result<QueryResult, String> {
    let start = Instant::now();
    let mut client = Client::connect(&plan.target_value, NoTls)
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
        &plan.target_value,
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
        target_mode: "named-target",
        target_name: plan.target_name.clone(),
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
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn target_upsert_writes_expected_store_shape() {
        let state_dir = temp_state_dir("shape");
        let db_path = sqlite_fixture_db();

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "local-app",
                "--engine",
                "sqlite",
                "--sqlite-db-path",
                &db_path,
            ]),
            None,
        )
        .expect("upsert");

        let content =
            fs::read_to_string(target_store_path(Path::new(&state_dir))).expect("read store");
        let parsed: Value = serde_json::from_str(&content).expect("json");

        assert_eq!(
            parsed.pointer("/version").and_then(Value::as_u64),
            Some(TARGET_STORE_VERSION as u64)
        );
        assert_eq!(
            parsed
                .pointer("/targets/local-app/engine")
                .and_then(Value::as_str),
            Some("sqlite")
        );
        assert_eq!(
            parsed
                .pointer("/targets/local-app/value")
                .and_then(Value::as_str),
            Some(db_path.as_str())
        );

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    fn target_upsert_env_var_persists_value_and_run_works_without_env() {
        let state_dir = temp_state_dir("persist");
        let db_path = sqlite_fixture_db();
        let env_name = "SQL_READ_TARGET_SQLITE_DB";
        env::set_var(env_name, &db_path);

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "local",
                "--engine",
                "sqlite",
                "--sqlite-db-path-env-var",
                env_name,
            ]),
            None,
        )
        .expect("upsert");
        env::remove_var(env_name);

        let output = run_args(
            args(&[
                "sql-read",
                "run",
                "--state-dir",
                &state_dir,
                "--target",
                "local",
            ]),
            Some("select id, name from widgets order by id"),
        )
        .expect("run");
        let parsed: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            parsed.pointer("/target/mode").and_then(Value::as_str),
            Some("named-target")
        );
        assert_eq!(
            parsed.pointer("/target/name").and_then(Value::as_str),
            Some("local")
        );
        assert_eq!(
            parsed.pointer("/row_count").and_then(Value::as_u64),
            Some(2)
        );

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    fn target_list_redacts_values() {
        let state_dir = temp_state_dir("list");
        let dsn = "postgresql://reader:secret@db.example/app";

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "prod-readonly",
                "--engine",
                "postgres",
                "--dsn",
                dsn,
            ]),
            None,
        )
        .expect("upsert");

        let output = run_args(
            args(&["sql-read", "target", "list", "--state-dir", &state_dir]),
            None,
        )
        .expect("list");
        let parsed: Value = serde_json::from_str(&output).expect("json");

        assert!(!output.contains(dsn));
        assert_eq!(
            parsed.pointer("/targets/0/name").and_then(Value::as_str),
            Some("prod-readonly")
        );
        assert_eq!(
            parsed.pointer("/targets/0/engine").and_then(Value::as_str),
            Some("postgres")
        );

        cleanup_path(&state_dir);
    }

    #[test]
    fn target_remove_deletes_named_target_only() {
        let state_dir = temp_state_dir("remove");
        let db_path = sqlite_fixture_db();

        for name in ["first", "second"] {
            run_args(
                args(&[
                    "sql-read",
                    "target",
                    "upsert",
                    "--state-dir",
                    &state_dir,
                    "--name",
                    name,
                    "--engine",
                    "sqlite",
                    "--sqlite-db-path",
                    &db_path,
                ]),
                None,
            )
            .expect("upsert");
        }

        run_args(
            args(&[
                "sql-read",
                "target",
                "remove",
                "--state-dir",
                &state_dir,
                "--name",
                "first",
            ]),
            None,
        )
        .expect("remove");

        let output = run_args(
            args(&["sql-read", "target", "list", "--state-dir", &state_dir]),
            None,
        )
        .expect("list");
        let parsed: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            parsed.pointer("/targets/0/name").and_then(Value::as_str),
            Some("second")
        );
        assert!(parsed.pointer("/targets/1").is_none());

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    fn run_reports_missing_target_clearly() {
        let state_dir = temp_state_dir("missing");
        let error = run_args(
            args(&[
                "sql-read",
                "run",
                "--state-dir",
                &state_dir,
                "--target",
                "missing",
            ]),
            Some("select 1"),
        )
        .expect_err("missing target");

        match error {
            CliError::Message(message) => {
                assert!(message.contains("Target `missing` not found"));
                assert!(message.contains("target upsert"));
            }
            other => panic!("unexpected error: {other:?}"),
        }

        cleanup_path(&state_dir);
    }

    #[test]
    fn run_executes_select_against_stored_sqlite_target() {
        let state_dir = temp_state_dir("sqlite-run");
        let db_path = sqlite_fixture_db();

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "local-app",
                "--engine",
                "sqlite",
                "--sqlite-db-path",
                &db_path,
            ]),
            None,
        )
        .expect("upsert");

        let output = run_args(
            args(&[
                "sql-read",
                "run",
                "--state-dir",
                &state_dir,
                "--target",
                "local-app",
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
            parsed.pointer("/rows/1/1").and_then(Value::as_str),
            Some("beta")
        );

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    fn run_rejects_write_statement_before_execution() {
        let state_dir = temp_state_dir("reject-write");
        let db_path = sqlite_fixture_db();

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "local-app",
                "--engine",
                "sqlite",
                "--sqlite-db-path",
                &db_path,
            ]),
            None,
        )
        .expect("upsert");

        let error = run_args(
            args(&[
                "sql-read",
                "run",
                "--state-dir",
                &state_dir,
                "--target",
                "local-app",
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

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    #[cfg(unix)]
    fn target_store_uses_restrictive_permissions() {
        let state_dir = temp_state_dir("perms");
        let db_path = sqlite_fixture_db();

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "local-app",
                "--engine",
                "sqlite",
                "--sqlite-db-path",
                &db_path,
            ]),
            None,
        )
        .expect("upsert");

        let state_mode = fs::metadata(&state_dir)
            .expect("state metadata")
            .permissions()
            .mode()
            & 0o777;
        let file_mode = fs::metadata(target_store_path(Path::new(&state_dir)))
            .expect("file metadata")
            .permissions()
            .mode()
            & 0o777;

        assert_eq!(state_mode, 0o700);
        assert_eq!(file_mode, 0o600);

        cleanup_path(&db_path);
        cleanup_path(&state_dir);
    }

    #[test]
    fn old_safe_ro_and_query_commands_return_migration_errors() {
        for legacy in ["safe-ro", "query"] {
            let error = run_args(args(&["sql-read", legacy]), None).expect_err("legacy command");
            match error {
                CliError::Message(message) => {
                    assert!(message.contains("was removed"));
                    assert!(message.contains("target upsert"));
                    assert!(message.contains("run --state-dir"));
                }
                other => panic!("unexpected error: {other:?}"),
            }
        }
    }

    #[test]
    #[ignore = "requires SQL_READ_TEST_POSTGRES_DSN"]
    fn postgres_run_uses_named_target() {
        let state_dir = temp_state_dir("postgres");
        let dsn = env::var("SQL_READ_TEST_POSTGRES_DSN").expect("test dsn");

        run_args(
            args(&[
                "sql-read",
                "target",
                "upsert",
                "--state-dir",
                &state_dir,
                "--name",
                "prod-readonly",
                "--engine",
                "postgres",
                "--dsn",
                &dsn,
            ]),
            None,
        )
        .expect("upsert");

        let output = run_args(
            args(&[
                "sql-read",
                "run",
                "--state-dir",
                &state_dir,
                "--target",
                "prod-readonly",
            ]),
            Some("select 1 as value"),
        )
        .expect("run");
        let parsed: Value = serde_json::from_str(&output).expect("json");

        assert_eq!(
            parsed.pointer("/row_count").and_then(Value::as_u64),
            Some(1)
        );

        cleanup_path(&state_dir);
    }

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    fn sqlite_fixture_db() -> String {
        let mut path = env::temp_dir();
        path.push(format!("sql-read-{}.sqlite", unique_suffix()));

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

    fn temp_state_dir(label: &str) -> String {
        let mut path = env::temp_dir();
        path.push(format!("sql-read-state-{label}-{}", unique_suffix()));
        path.to_string_lossy().into_owned()
    }

    fn unique_suffix() -> String {
        static COUNTER: AtomicU64 = AtomicU64::new(0);

        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time")
            .as_nanos();
        let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);

        format!("{nanos}-{sequence}")
    }

    fn cleanup_path(path: &str) {
        let target = Path::new(path);
        if target.is_dir() {
            let _ = fs::remove_dir_all(target);
        } else {
            let _ = fs::remove_file(target);
        }
    }
}
