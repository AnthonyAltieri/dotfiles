use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::env;
use std::io::Write;
use std::process::{Command, Stdio};

const QUERY: &str = r#"query(
  $owner: String!,
  $repo: String!,
  $number: Int!,
  $commentsCursor: String,
  $reviewsCursor: String,
  $threadsCursor: String
) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      url
      title
      state
      comments(first: 100, after: $commentsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          body
          createdAt
          updatedAt
          author { login }
        }
      }
      reviews(first: 100, after: $reviewsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          state
          body
          submittedAt
          author { login }
        }
      }
      reviewThreads(first: 100, after: $threadsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          diffSide
          startLine
          startDiffSide
          originalLine
          originalStartLine
          resolvedBy { login }
          comments(first: 100) {
            nodes {
              id
              body
              createdAt
              updatedAt
              author { login }
            }
          }
        }
      }
    }
  }
}"#;

#[derive(Debug, PartialEq, Eq)]
enum OutputFormat {
    Json,
    Compact,
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
    let format = parse_args(env::args().skip(1).collect())?;
    ensure_gh_authenticated()?;
    let (owner, repo, number) = get_current_pr_ref()?;
    let result = fetch_all(&owner, &repo, number)?;

    match format {
        OutputFormat::Json => {
            println!(
                "{}",
                serde_json::to_string_pretty(&result).map_err(|err| err.to_string())?
            );
        }
        OutputFormat::Compact => {
            println!("{}", render_compact(&result)?);
        }
    }
    Ok(())
}

fn parse_args(args: Vec<String>) -> Result<OutputFormat, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!("Usage: fetch-comments [--format json|compact]");
        std::process::exit(0);
    }

    let mut format = OutputFormat::Json;
    let mut index = 0usize;
    while index < args.len() {
        match args[index].as_str() {
            "--format" => {
                let value = args
                    .get(index + 1)
                    .ok_or_else(|| "--format requires a value".to_string())?;
                format = match value.as_str() {
                    "json" => OutputFormat::Json,
                    "compact" => OutputFormat::Compact,
                    _ => return Err(format!("Unsupported format: {value}")),
                };
                index += 2;
            }
            other => return Err(format!("Unknown option: {other}")),
        }
    }

    Ok(format)
}

fn ensure_gh_authenticated() -> Result<(), String> {
    let output = run_command("gh", &["auth", "status"], None)?;
    if output.status != 0 {
        return Err("run `gh auth login` to authenticate the GitHub CLI".to_string());
    }
    Ok(())
}

fn get_current_pr_ref() -> Result<(String, String, i64), String> {
    let pr = gh_pr_view_json("number,headRepositoryOwner,headRepository")?;
    let owner = pr
        .pointer("/headRepositoryOwner/login")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing head repository owner login in gh pr view output.".to_string())?;
    let repo = pr
        .pointer("/headRepository/name")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing head repository name in gh pr view output.".to_string())?;
    let number = pr
        .get("number")
        .and_then(Value::as_i64)
        .ok_or_else(|| "Missing PR number in gh pr view output.".to_string())?;
    Ok((owner.to_string(), repo.to_string(), number))
}

fn gh_pr_view_json(fields: &str) -> Result<Value, String> {
    run_json_command("gh", &["pr", "view", "--json", fields], None)
}

fn gh_api_graphql(
    owner: &str,
    repo: &str,
    number: i64,
    comments_cursor: Option<&str>,
    reviews_cursor: Option<&str>,
    threads_cursor: Option<&str>,
) -> Result<Value, String> {
    let mut args = vec![
        "api".to_string(),
        "graphql".to_string(),
        "-F".to_string(),
        "query=@-".to_string(),
        "-F".to_string(),
        format!("owner={owner}"),
        "-F".to_string(),
        format!("repo={repo}"),
        "-F".to_string(),
        format!("number={number}"),
    ];

    for (label, cursor) in [
        ("commentsCursor", comments_cursor),
        ("reviewsCursor", reviews_cursor),
        ("threadsCursor", threads_cursor),
    ] {
        if let Some(cursor) = cursor {
            args.push("-F".to_string());
            args.push(format!("{label}={cursor}"));
        }
    }

    let output = run_command(
        "gh",
        &args.iter().map(String::as_str).collect::<Vec<&str>>(),
        Some(QUERY),
    )?;
    if output.status != 0 {
        return Err(format!(
            "Command failed: gh {}\n{}",
            args.join(" "),
            output.stderr.trim()
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|err| err.to_string())
}

fn fetch_all(owner: &str, repo: &str, number: i64) -> Result<Value, String> {
    let mut conversation_comments = Vec::new();
    let mut reviews = Vec::new();
    let mut review_threads = Vec::new();
    let mut comments_cursor: Option<String> = None;
    let mut reviews_cursor: Option<String> = None;
    let mut threads_cursor: Option<String> = None;
    let mut pr_meta: Option<Value> = None;

    loop {
        let payload = gh_api_graphql(
            owner,
            repo,
            number,
            comments_cursor.as_deref(),
            reviews_cursor.as_deref(),
            threads_cursor.as_deref(),
        )?;

        if payload.get("errors").and_then(Value::as_array).map(|items| !items.is_empty()) == Some(true) {
            return Err(format!(
                "GitHub GraphQL errors:\n{}",
                serde_json::to_string_pretty(payload.get("errors").unwrap()).map_err(|err| err.to_string())?
            ));
        }

        let pr = payload
            .pointer("/data/repository/pullRequest")
            .ok_or_else(|| "Missing pullRequest in GraphQL payload.".to_string())?;

        if pr_meta.is_none() {
            pr_meta = Some(json!({
                "number": pr.get("number").cloned().unwrap_or(Value::Null),
                "url": pr.get("url").cloned().unwrap_or(Value::Null),
                "title": pr.get("title").cloned().unwrap_or(Value::Null),
                "state": pr.get("state").cloned().unwrap_or(Value::Null),
                "owner": owner,
                "repo": repo,
            }));
        }

        let comments = pr
            .pointer("/comments/nodes")
            .and_then(Value::as_array)
            .ok_or_else(|| "Missing comment nodes in GraphQL payload.".to_string())?;
        let review_values = pr
            .pointer("/reviews/nodes")
            .and_then(Value::as_array)
            .ok_or_else(|| "Missing review nodes in GraphQL payload.".to_string())?;
        let thread_values = pr
            .pointer("/reviewThreads/nodes")
            .and_then(Value::as_array)
            .ok_or_else(|| "Missing review thread nodes in GraphQL payload.".to_string())?;

        conversation_comments.extend(comments.iter().cloned());
        reviews.extend(review_values.iter().cloned());
        review_threads.extend(thread_values.iter().cloned());

        comments_cursor = next_cursor(pr.pointer("/comments/pageInfo"));
        reviews_cursor = next_cursor(pr.pointer("/reviews/pageInfo"));
        threads_cursor = next_cursor(pr.pointer("/reviewThreads/pageInfo"));

        if comments_cursor.is_none() && reviews_cursor.is_none() && threads_cursor.is_none() {
            break;
        }
    }

    Ok(json!({
        "pull_request": pr_meta.ok_or_else(|| "No PR metadata returned from GraphQL.".to_string())?,
        "conversation_comments": conversation_comments,
        "reviews": reviews,
        "review_threads": review_threads,
    }))
}

fn render_compact(result: &Value) -> Result<String, String> {
    let reviews = result
        .get("reviews")
        .and_then(Value::as_array)
        .ok_or_else(|| "Missing reviews array in result.".to_string())?;
    let mut review_states = BTreeMap::new();
    for review in reviews {
        if let (Some(author), Some(state)) = (
            review.pointer("/author/login").and_then(Value::as_str),
            review.get("state").and_then(Value::as_str),
        ) {
            review_states.insert(author.to_string(), state.to_string());
        }
    }

    let mut lines = vec![[
        "thread_id",
        "path",
        "is_resolved",
        "is_outdated",
        "line",
        "reviewer",
        "review_state",
        "comment_count",
        "preview",
    ]
    .join("\t")];

    let threads = result
        .get("review_threads")
        .and_then(Value::as_array)
        .ok_or_else(|| "Missing review_threads array in result.".to_string())?;

    for thread in threads {
        let comments = thread
            .pointer("/comments/nodes")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let preview = comments
            .first()
            .and_then(|comment| comment.get("body"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        let reviewer = comments
            .last()
            .and_then(|comment| comment.pointer("/author/login"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let review_state = review_states.get(&reviewer).cloned().unwrap_or_default();

        lines.push(
            vec![
                sanitize(thread.get("id")),
                sanitize(thread.get("path")),
                bool_string(thread.get("isResolved")),
                bool_string(thread.get("isOutdated")),
                sanitize(thread.get("line")),
                sanitize(Some(&Value::String(reviewer))),
                sanitize(Some(&Value::String(review_state))),
                comments.len().to_string(),
                sanitize(Some(&Value::String(preview.chars().take(160).collect()))),
            ]
            .join("\t"),
        );
    }

    Ok(lines.join("\n"))
}

fn next_cursor(page_info: Option<&Value>) -> Option<String> {
    let page_info = page_info?;
    if page_info.get("hasNextPage").and_then(Value::as_bool) != Some(true) {
        return None;
    }
    page_info
        .get("endCursor")
        .and_then(Value::as_str)
        .map(|value| value.to_string())
}

fn bool_string(value: Option<&Value>) -> String {
    if value.and_then(Value::as_bool) == Some(true) {
        "true".to_string()
    } else {
        "false".to_string()
    }
}

fn sanitize(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(text)) => text.replace('\t', " ").replace('\n', " ").trim().to_string(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Bool(boolean)) => boolean.to_string(),
        _ => String::new(),
    }
}

fn run_json_command(program: &str, args: &[&str], stdin: Option<&str>) -> Result<Value, String> {
    let output = run_command(program, args, stdin)?;
    if output.status != 0 {
        return Err(format!(
            "Command failed: {program} {}\n{}",
            args.join(" "),
            output.stderr.trim()
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|err| err.to_string())
}

struct CommandOutput {
    status: i32,
    stdout: Vec<u8>,
    stderr: String,
}

fn run_command(program: &str, args: &[&str], stdin: Option<&str>) -> Result<CommandOutput, String> {
    let mut command = Command::new(program);
    command.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());

    if stdin.is_some() {
        command.stdin(Stdio::piped());
    }

    let mut child = command.spawn().map_err(|err| err.to_string())?;
    if let Some(stdin_text) = stdin {
        let mut handle = child
            .stdin
            .take()
            .ok_or_else(|| "Failed to open stdin for child process.".to_string())?;
        handle
            .write_all(stdin_text.as_bytes())
            .map_err(|err| err.to_string())?;
    }
    let output = child.wait_with_output().map_err(|err| err.to_string())?;
    Ok(CommandOutput {
        status: output.status.code().unwrap_or(1),
        stdout: output.stdout,
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_args_supports_compact_output() {
        let args = vec!["--format".to_string(), "compact".to_string()];
        assert_eq!(parse_args(args).expect("parsed args"), OutputFormat::Compact);
    }

    #[test]
    fn render_compact_flattens_thread_metadata() {
        let payload = json!({
            "reviews": [
                {
                    "author": { "login": "alice" },
                    "state": "CHANGES_REQUESTED"
                }
            ],
            "review_threads": [
                {
                    "id": "thread-1",
                    "path": "src/app.ts",
                    "isResolved": false,
                    "isOutdated": false,
                    "line": 42,
                    "comments": {
                        "nodes": [
                            {
                                "body": "Needs\tcleanup\nsoon",
                                "author": { "login": "bob" }
                            },
                            {
                                "body": "ack",
                                "author": { "login": "alice" }
                            }
                        ]
                    }
                }
            ]
        });

        let output = render_compact(&payload).expect("compact output");
        assert_eq!(
            output,
            concat!(
                "thread_id\tpath\tis_resolved\tis_outdated\tline\treviewer\treview_state\tcomment_count\tpreview\n",
                "thread-1\tsrc/app.ts\tfalse\tfalse\t42\talice\tCHANGES_REQUESTED\t2\tNeeds cleanup soon"
            )
        );
    }

    #[test]
    fn next_cursor_respects_has_next_page() {
        assert_eq!(
            next_cursor(Some(&json!({ "hasNextPage": true, "endCursor": "abc" }))),
            Some("abc".to_string())
        );
        assert_eq!(
            next_cursor(Some(&json!({ "hasNextPage": false, "endCursor": "abc" }))),
            None
        );
    }

    #[test]
    fn sanitize_replaces_tabs_and_newlines() {
        assert_eq!(
            sanitize(Some(&Value::String("one\ttwo\nthree".to_string()))),
            "one two three"
        );
    }
}
