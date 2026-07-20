use gh_address_comments_tools::{ensure_gh_authenticated, ensure_robot_prefix, gh_graphql_json};
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;

const MUTATION: &str = r#"mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId,
    body: $body
  }) {
    comment {
      id
      body
    }
  }
}"#;

#[derive(Debug, PartialEq, Eq)]
struct Config {
    thread_id: String,
    body: Option<String>,
    body_file: Option<PathBuf>,
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
    let body = load_body(&config)?;
    let prefixed_body = ensure_robot_prefix(&body)?;
    ensure_gh_authenticated()?;
    let response = gh_graphql_json(
        MUTATION,
        &[("threadId", &config.thread_id), ("body", &prefixed_body)],
    )?;

    println!(
        "{}",
        serde_json::to_string_pretty(&extract_reply_result(
            &response,
            &config.thread_id,
            &prefixed_body
        )?)
        .map_err(|err| err.to_string())?
    );
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!(
            "Usage: create-thread-reply --thread-id <ID> [--body <TEXT> | --body-file <PATH>]"
        );
        std::process::exit(0);
    }

    let mut thread_id = None;
    let mut body = None;
    let mut body_file = None;
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
            "--body" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "--body requires a value".to_string())?;
                body = Some(value.to_string());
                index += 2;
            }
            "--body-file" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "--body-file requires a value".to_string())?;
                body_file = Some(PathBuf::from(value));
                index += 2;
            }
            other => return Err(format!("Unknown option: {other}")),
        }
    }

    let thread_id = thread_id.ok_or_else(|| "--thread-id is required".to_string())?;
    if body.is_some() && body_file.is_some() {
        return Err("Pass either --body or --body-file, not both.".to_string());
    }

    Ok(Config {
        thread_id,
        body,
        body_file,
    })
}

fn load_body(config: &Config) -> Result<String, String> {
    if let Some(body) = &config.body {
        return Ok(body.clone());
    }
    if let Some(path) = &config.body_file {
        return fs::read_to_string(path)
            .map_err(|err| format!("Failed to read reply body file `{}`: {err}", path.display()));
    }

    let mut buffer = String::new();
    io::stdin()
        .read_to_string(&mut buffer)
        .map_err(|err| format!("Failed to read stdin: {err}"))?;
    Ok(buffer)
}

fn extract_reply_result(response: &Value, thread_id: &str, body: &str) -> Result<Value, String> {
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

    let comment = response
        .pointer("/data/addPullRequestReviewThreadReply/comment")
        .ok_or_else(|| "Missing comment in GitHub GraphQL reply response.".to_string())?;
    let comment_id = comment
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing comment id in GitHub GraphQL reply response.".to_string())?;

    Ok(json!({
        "thread_id": thread_id,
        "comment_id": comment_id,
        "body": body,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parse_args_supports_body_flag() {
        let config = parse_args(vec![
            "--thread-id".to_string(),
            "thread-1".to_string(),
            "--body".to_string(),
            "Addressed in abc123".to_string(),
        ])
        .expect("config");

        assert_eq!(config.thread_id, "thread-1");
        assert_eq!(config.body.as_deref(), Some("Addressed in abc123"));
        assert_eq!(config.body_file, None);
    }

    #[test]
    fn load_body_reads_file_when_requested() {
        let mut path = env::temp_dir();
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time")
            .as_nanos();
        path.push(format!("gh-address-comments-reply-{unique}.txt"));
        fs::write(&path, "Addressed in abc123").expect("write");

        let config = Config {
            thread_id: "thread-1".to_string(),
            body: None,
            body_file: Some(path.clone()),
        };

        let body = load_body(&config).expect("body");
        assert_eq!(body, "Addressed in abc123");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn extract_reply_result_returns_compact_json() {
        let response = json!({
            "data": {
                "addPullRequestReviewThreadReply": {
                    "comment": {
                        "id": "comment-1",
                        "body": "🤖 Addressed in abc123"
                    }
                }
            }
        });

        let result =
            extract_reply_result(&response, "thread-1", "🤖 Addressed in abc123").expect("result");
        assert_eq!(
            result.pointer("/comment_id").and_then(Value::as_str),
            Some("comment-1")
        );
        assert_eq!(
            result.pointer("/body").and_then(Value::as_str),
            Some("🤖 Addressed in abc123")
        );
    }
}
