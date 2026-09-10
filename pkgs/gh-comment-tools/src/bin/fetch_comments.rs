use gh_address_comments_tools::{ensure_gh_authenticated, gh_graphql_json, run_json_command};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::env;

const QUERY: &str = r#"query(
  $owner: String!,
  $repo: String!,
  $number: Int!,
  $commentsCursor: String,
  $reviewsCursor: String,
  $threadsCursor: String,
  $includeComments: Boolean!,
  $includeReviews: Boolean!,
  $includeThreads: Boolean!
) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      url
      title
      state
      comments(first: 100, after: $commentsCursor) @include(if: $includeComments) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          body
          createdAt
          updatedAt
          author { login }
        }
      }
      reviews(first: 100, after: $reviewsCursor) @include(if: $includeReviews) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          state
          body
          submittedAt
          author { login }
        }
      }
      reviewThreads(first: 100, after: $threadsCursor) @include(if: $includeThreads) {
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

#[derive(Debug, PartialEq, Eq)]
struct Config {
    format: OutputFormat,
    include_resolved: bool,
}

#[derive(Debug, Default)]
struct ConnectionState {
    values: Vec<Value>,
    cursor: Option<String>,
    done: bool,
}

impl ConnectionState {
    fn ingest(&mut self, connection: &Value, label: &str) -> Result<(), String> {
        if self.done {
            return Ok(());
        }
        let nodes = connection
            .get("nodes")
            .and_then(Value::as_array)
            .ok_or_else(|| format!("Missing {label} nodes in GraphQL payload."))?;
        self.values.extend(nodes.iter().cloned());
        match next_cursor(connection.get("pageInfo")) {
            Some(cursor) => self.cursor = Some(cursor),
            None => self.done = true,
        }
        Ok(())
    }
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
    let (owner, repo, number) = get_current_pr_ref()?;
    let mut result = fetch_all(&owner, &repo, number)?;
    filter_review_threads(&mut result, config.include_resolved)?;

    match config.format {
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

fn parse_args(args: Vec<String>) -> Result<Config, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!("Usage: fetch-comments [--format json|compact] [--include-resolved|--all]");
        std::process::exit(0);
    }

    let mut format = OutputFormat::Json;
    let mut include_resolved = false;
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
            "--include-resolved" | "--all" => {
                include_resolved = true;
                index += 1;
            }
            other => return Err(format!("Unknown option: {other}")),
        }
    }

    Ok(Config {
        format,
        include_resolved,
    })
}

fn get_current_pr_ref() -> Result<(String, String, i64), String> {
    let pr = gh_pr_view_json("number,url")?;
    let number = pr
        .get("number")
        .and_then(Value::as_i64)
        .ok_or_else(|| "Missing PR number in gh pr view output.".to_string())?;
    let url = pr
        .get("url")
        .and_then(Value::as_str)
        .ok_or_else(|| "Missing PR URL in gh pr view output.".to_string())?;
    let (owner, repo) = parse_pull_request_url(url, number)?;
    Ok((owner, repo, number))
}

fn parse_pull_request_url(url: &str, expected_number: i64) -> Result<(String, String), String> {
    let path = url
        .split_once("://")
        .map(|(_, remainder)| remainder)
        .unwrap_or(url)
        .split_once('/')
        .map(|(_, path)| path)
        .ok_or_else(|| format!("Invalid pull request URL: {url}"))?;
    let segments: Vec<&str> = path.trim_matches('/').split('/').collect();
    if segments.len() < 4 || segments[2] != "pull" {
        return Err(format!("Invalid pull request URL: {url}"));
    }
    let url_number = segments[3]
        .parse::<i64>()
        .map_err(|_| format!("Invalid pull request number in URL: {url}"))?;
    if url_number != expected_number {
        return Err(format!(
            "PR number mismatch: gh returned {expected_number}, but URL contains {url_number}."
        ));
    }
    Ok((segments[0].to_string(), segments[1].to_string()))
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
    include_comments: bool,
    include_reviews: bool,
    include_threads: bool,
) -> Result<Value, String> {
    let mut fields = vec![
        ("owner".to_string(), owner.to_string()),
        ("repo".to_string(), repo.to_string()),
        ("number".to_string(), number.to_string()),
        ("includeComments".to_string(), include_comments.to_string()),
        ("includeReviews".to_string(), include_reviews.to_string()),
        ("includeThreads".to_string(), include_threads.to_string()),
    ];

    for (label, cursor) in [
        ("commentsCursor", comments_cursor),
        ("reviewsCursor", reviews_cursor),
        ("threadsCursor", threads_cursor),
    ] {
        if let Some(cursor) = cursor {
            fields.push((label.to_string(), cursor.to_string()));
        }
    }

    let borrowed_fields: Vec<(&str, &str)> = fields
        .iter()
        .map(|(name, value)| (name.as_str(), value.as_str()))
        .collect();
    gh_graphql_json(QUERY, &borrowed_fields)
}

fn fetch_all(owner: &str, repo: &str, number: i64) -> Result<Value, String> {
    let mut conversation_comments = ConnectionState::default();
    let mut reviews = ConnectionState::default();
    let mut review_threads = ConnectionState::default();
    let mut pr_meta: Option<Value> = None;

    loop {
        let payload = gh_api_graphql(
            owner,
            repo,
            number,
            conversation_comments.cursor.as_deref(),
            reviews.cursor.as_deref(),
            review_threads.cursor.as_deref(),
            !conversation_comments.done,
            !reviews.done,
            !review_threads.done,
        )?;

        if payload
            .get("errors")
            .and_then(Value::as_array)
            .map(|items| !items.is_empty())
            == Some(true)
        {
            return Err(format!(
                "GitHub GraphQL errors:\n{}",
                serde_json::to_string_pretty(payload.get("errors").unwrap())
                    .map_err(|err| err.to_string())?
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

        if !conversation_comments.done {
            conversation_comments.ingest(
                pr.get("comments")
                    .ok_or_else(|| "Missing comments connection in GraphQL payload.".to_string())?,
                "comment",
            )?;
        }
        if !reviews.done {
            reviews.ingest(
                pr.get("reviews")
                    .ok_or_else(|| "Missing reviews connection in GraphQL payload.".to_string())?,
                "review",
            )?;
        }
        if !review_threads.done {
            review_threads.ingest(
                pr.get("reviewThreads").ok_or_else(|| {
                    "Missing reviewThreads connection in GraphQL payload.".to_string()
                })?,
                "review thread",
            )?;
        }

        if conversation_comments.done && reviews.done && review_threads.done {
            break;
        }
    }

    Ok(json!({
        "pull_request": pr_meta.ok_or_else(|| "No PR metadata returned from GraphQL.".to_string())?,
        "conversation_comments": conversation_comments.values,
        "reviews": reviews.values,
        "review_threads": review_threads.values,
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

fn filter_review_threads(result: &mut Value, include_resolved: bool) -> Result<(), String> {
    if include_resolved {
        return Ok(());
    }
    let threads = result
        .get_mut("review_threads")
        .and_then(Value::as_array_mut)
        .ok_or_else(|| "Missing review_threads array in result.".to_string())?;
    threads.retain(|thread| thread.get("isResolved").and_then(Value::as_bool) != Some(true));
    Ok(())
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
        Some(Value::String(text)) => text
            .replace('\t', " ")
            .replace('\n', " ")
            .trim()
            .to_string(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Bool(boolean)) => boolean.to_string(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_args_supports_compact_output() {
        let args = vec!["--format".to_string(), "compact".to_string()];
        assert_eq!(
            parse_args(args).expect("parsed args"),
            Config {
                format: OutputFormat::Compact,
                include_resolved: false,
            }
        );
    }

    #[test]
    fn parse_args_supports_resolved_threads() {
        assert_eq!(
            parse_args(vec!["--all".to_string()]).expect("parsed args"),
            Config {
                format: OutputFormat::Json,
                include_resolved: true,
            }
        );
    }

    #[test]
    fn pull_request_url_uses_base_repository() {
        assert_eq!(
            parse_pull_request_url("https://github.com/base-owner/base-repo/pull/42", 42)
                .expect("parsed URL"),
            ("base-owner".to_string(), "base-repo".to_string())
        );
    }

    #[test]
    fn filter_review_threads_excludes_resolved_by_default() {
        let mut payload = json!({
            "review_threads": [
                { "id": "open", "isResolved": false },
                { "id": "closed", "isResolved": true }
            ]
        });
        filter_review_threads(&mut payload, false).expect("filtered threads");
        assert_eq!(
            payload["review_threads"],
            json!([{ "id": "open", "isResolved": false }])
        );
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
    fn connection_state_handles_asymmetric_page_counts_without_restarting() {
        fn page(id: &str, next: Option<&str>) -> Value {
            json!({
                "nodes": [{ "id": id }],
                "pageInfo": {
                    "hasNextPage": next.is_some(),
                    "endCursor": next,
                }
            })
        }

        let mut comments = ConnectionState::default();
        let mut reviews = ConnectionState::default();
        let mut threads = ConnectionState::default();

        comments
            .ingest(&page("comment-1", Some("c1")), "comment")
            .unwrap();
        reviews.ingest(&page("review-1", None), "review").unwrap();
        threads
            .ingest(&page("thread-1", Some("t1")), "thread")
            .unwrap();

        comments
            .ingest(&page("comment-2", None), "comment")
            .unwrap();
        reviews
            .ingest(&page("review-1-repeated", None), "review")
            .unwrap();
        threads
            .ingest(&page("thread-2", Some("t2")), "thread")
            .unwrap();

        comments
            .ingest(&page("comment-2-repeated", None), "comment")
            .unwrap();
        reviews
            .ingest(&page("review-1-repeated", None), "review")
            .unwrap();
        threads.ingest(&page("thread-3", None), "thread").unwrap();

        assert_eq!(comments.values.len(), 2);
        assert_eq!(reviews.values.len(), 1);
        assert_eq!(threads.values.len(), 3);
        assert!(comments.done && reviews.done && threads.done);
    }

    #[test]
    fn sanitize_replaces_tabs_and_newlines() {
        assert_eq!(
            sanitize(Some(&Value::String("one\ttwo\nthree".to_string()))),
            "one two three"
        );
    }
}
