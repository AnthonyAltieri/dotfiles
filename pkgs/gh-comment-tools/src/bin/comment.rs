use gh_address_comments_tools::{
    ensure_gh_authenticated, ensure_robot_prefix, gh_graphql_json, run_json_command,
};
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::path::PathBuf;

const MUTATION: &str = r#"mutation($subjectId: ID!, $body: String!) {
  addComment(input: {
    subjectId: $subjectId,
    body: $body
  }) {
    commentEdge {
      node {
        id
        body
        url
      }
    }
  }
}"#;

#[derive(Debug, PartialEq, Eq)]
struct Config {
    pr: Option<String>,
    body: Option<String>,
    body_file: Option<PathBuf>,
}

#[derive(Debug, PartialEq, Eq)]
struct PullRequestTarget {
    id: String,
    number: i64,
    url: String,
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
    let pull_request = get_pull_request_target(config.pr.as_deref())?;
    let response = gh_graphql_json(
        MUTATION,
        &[("subjectId", &pull_request.id), ("body", &prefixed_body)],
    )?;

    println!(
        "{}",
        serde_json::to_string_pretty(&extract_comment_result(
            &response,
            &pull_request,
            &prefixed_body
        )?)
        .map_err(|err| err.to_string())?
    );
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!(
            "Usage: create-comment [--pr <NUMBER|URL|BRANCH>] [--body <TEXT> | --body-file <PATH>]"
        );
        std::process::exit(0);
    }

    let mut pr = None;
    let mut body = None;
    let mut body_file = None;
    let mut index = 0usize;

    while index < args.len() {
        match args[index].as_str() {
            "--pr" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "--pr requires a value".to_string())?;
                pr = Some(value.to_string());
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

    if body.is_some() && body_file.is_some() {
        return Err("Pass either --body or --body-file, not both.".to_string());
    }

    Ok(Config {
        pr,
        body,
        body_file,
    })
}

fn load_body(config: &Config) -> Result<String, String> {
    if let Some(body) = &config.body {
        return Ok(body.clone());
    }
    if let Some(path) = &config.body_file {
        return fs::read_to_string(path).map_err(|err| {
            format!(
                "Failed to read comment body file `{}`: {err}",
                path.display()
            )
        });
    }

    let mut buffer = String::new();
    io::stdin()
        .read_to_string(&mut buffer)
        .map_err(|err| format!("Failed to read stdin: {err}"))?;
    Ok(buffer)
}

fn get_pull_request_target(pr: Option<&str>) -> Result<PullRequestTarget, String> {
    let mut args = vec!["pr", "view"];
    if let Some(pr) = pr {
        args.push(pr);
    }
    args.extend(["--json", "id,number,url"]);

    let payload = run_json_command("gh", &args, None)?;
    let id = payload
        .get("id")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing pull request node id in gh pr view output.".to_string())?;
    let number = payload
        .get("number")
        .and_then(Value::as_i64)
        .ok_or_else(|| "Missing pull request number in gh pr view output.".to_string())?;
    let url = payload
        .get("url")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing pull request URL in gh pr view output.".to_string())?;

    Ok(PullRequestTarget {
        id: id.to_string(),
        number,
        url: url.to_string(),
    })
}

fn extract_comment_result(
    response: &Value,
    pull_request: &PullRequestTarget,
    body: &str,
) -> Result<Value, String> {
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
        .pointer("/data/addComment/commentEdge/node")
        .ok_or_else(|| "Missing comment in GitHub GraphQL create-comment response.".to_string())?;
    let comment_id = comment.get("id").and_then(Value::as_str).ok_or_else(|| {
        "Missing comment id in GitHub GraphQL create-comment response.".to_string()
    })?;
    let comment_url = comment.get("url").and_then(Value::as_str).ok_or_else(|| {
        "Missing comment URL in GitHub GraphQL create-comment response.".to_string()
    })?;

    Ok(json!({
        "pull_request": {
            "number": pull_request.number,
            "url": pull_request.url,
        },
        "comment_id": comment_id,
        "comment_url": comment_url,
        "body": body,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn parse_args_supports_pr_and_body() {
        let config = parse_args(vec![
            "--pr".to_string(),
            "13".to_string(),
            "--body".to_string(),
            "FROM CODEX: synced".to_string(),
        ])
        .expect("config");

        assert_eq!(config.pr.as_deref(), Some("13"));
        assert_eq!(config.body.as_deref(), Some("FROM CODEX: synced"));
        assert_eq!(config.body_file, None);
    }

    #[test]
    fn load_body_reads_file_when_requested() {
        let mut path = env::temp_dir();
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time")
            .as_nanos();
        path.push(format!("gh-address-comments-comment-{unique}.txt"));
        fs::write(&path, "FROM CODEX: synced").expect("write");

        let config = Config {
            pr: None,
            body: None,
            body_file: Some(path.clone()),
        };

        let body = load_body(&config).expect("body");
        assert_eq!(body, "FROM CODEX: synced");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn extract_comment_result_returns_compact_json() {
        let pull_request = PullRequestTarget {
            id: "PR_123".to_string(),
            number: 13,
            url: "https://github.com/example/repo/pull/13".to_string(),
        };
        let response = json!({
            "data": {
                "addComment": {
                    "commentEdge": {
                        "node": {
                            "id": "comment-1",
                            "body": "🤖 FROM CODEX: synced",
                            "url": "https://github.com/example/repo/pull/13#issuecomment-1"
                        }
                    }
                }
            }
        });

        let result = extract_comment_result(&response, &pull_request, "🤖 FROM CODEX: synced")
            .expect("result");
        assert_eq!(
            result.pointer("/comment_id").and_then(Value::as_str),
            Some("comment-1")
        );
        assert_eq!(
            result.pointer("/comment_url").and_then(Value::as_str),
            Some("https://github.com/example/repo/pull/13#issuecomment-1")
        );
        assert_eq!(
            result.pointer("/body").and_then(Value::as_str),
            Some("🤖 FROM CODEX: synced")
        );
    }
}
