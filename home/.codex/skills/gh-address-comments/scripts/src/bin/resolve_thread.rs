use gh_address_comments_tools::{ensure_gh_authenticated, gh_graphql_json};
use serde_json::{json, Value};
use std::env;

const MUTATION: &str = r#"mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread {
      id
      isResolved
    }
  }
}"#;

#[derive(Debug, PartialEq, Eq)]
struct Config {
    thread_id: String,
}

fn main() {
    match run() {
        Ok(()) => {}
        Err(err) => {
            eprintln!("{err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<(), String> {
    let config = parse_args(env::args().skip(1).collect())?;
    ensure_gh_authenticated()?;
    let response = gh_graphql_json(MUTATION, &[("threadId", &config.thread_id)])?;

    println!(
        "{}",
        serde_json::to_string_pretty(&extract_resolve_result(&response, &config.thread_id)?)
            .map_err(|err| err.to_string())?
    );
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!("Usage: resolve-thread --thread-id <ID>");
        std::process::exit(0);
    }

    let mut thread_id = None;
    let mut index = 0usize;
    while index < args.len() {
        match args[index].as_str() {
            "--thread-id" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "--thread-id requires a value".to_string())?;
                thread_id = Some(value.to_string());
                index += 2;
            }
            other => return Err(format!("Unknown option: {other}")),
        }
    }

    Ok(Config {
        thread_id: thread_id.ok_or_else(|| "--thread-id is required".to_string())?,
    })
}

fn extract_resolve_result(response: &Value, thread_id: &str) -> Result<Value, String> {
    if response
        .get("errors")
        .and_then(Value::as_array)
        .map(|items| !items.is_empty())
        == Some(true)
    {
        return Err(format!(
            "GitHub GraphQL errors:\n{}",
            serde_json::to_string_pretty(response.get("errors").unwrap())
                .map_err(|err| err.to_string())?
        ));
    }

    let thread = response
        .pointer("/data/resolveReviewThread/thread")
        .ok_or_else(|| "Missing thread in GitHub GraphQL resolve response.".to_string())?;
    let resolved = thread
        .get("isResolved")
        .and_then(Value::as_bool)
        .ok_or_else(|| {
            "Missing thread resolution state in GitHub GraphQL resolve response.".to_string()
        })?;

    Ok(json!({
        "thread_id": thread_id,
        "resolved": resolved,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_args_reads_thread_id() {
        let config =
            parse_args(vec!["--thread-id".to_string(), "thread-1".to_string()]).expect("config");
        assert_eq!(config.thread_id, "thread-1");
    }

    #[test]
    fn extract_resolve_result_reads_resolution_state() {
        let response = json!({
            "data": {
                "resolveReviewThread": {
                    "thread": {
                        "id": "thread-1",
                        "isResolved": true
                    }
                }
            }
        });

        let result = extract_resolve_result(&response, "thread-1").expect("result");
        assert_eq!(
            result.pointer("/resolved").and_then(Value::as_bool),
            Some(true)
        );
    }
}
