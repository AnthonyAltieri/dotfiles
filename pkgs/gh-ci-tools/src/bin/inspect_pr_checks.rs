use serde_json::{json, Value};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const FAILURE_CONCLUSIONS: &[&str] = &["failure", "cancelled", "timed_out", "action_required"];
const FAILURE_STATES: &[&str] = &["failure", "error", "cancelled", "timed_out", "action_required"];
const FAILURE_BUCKETS: &[&str] = &["fail"];
const FAILURE_MARKERS: &[&str] = &[
    "error",
    "fail",
    "failed",
    "traceback",
    "exception",
    "assert",
    "panic",
    "fatal",
    "timeout",
    "segmentation fault",
];
const PENDING_LOG_MARKERS: &[&str] = &[
    "still in progress",
    "log will be available when it is complete",
];
const DEFAULT_MAX_LINES: usize = 160;
const DEFAULT_CONTEXT_LINES: usize = 30;

#[derive(Debug, PartialEq, Eq)]
struct Args {
    repo: String,
    pr: Option<String>,
    max_lines: usize,
    context: usize,
    as_json: bool,
}

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("{err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<i32, String> {
    let args = parse_args(env::args().skip(1).collect())?;
    let repo_root = find_git_root(Path::new(&args.repo))?
        .ok_or_else(|| "Error: not inside a Git repository.".to_string())?;

    ensure_gh_available(&repo_root)?;
    let pr_value = resolve_pr(args.pr.as_deref(), &repo_root)?;
    let checks = fetch_checks(&pr_value, &repo_root)?;
    let failing: Vec<Value> = checks.into_iter().filter(is_failing).collect();

    if failing.is_empty() {
        println!("PR #{pr_value}: no failing checks detected.");
        return Ok(0);
    }

    let mut results = Vec::new();
    for check in failing {
        results.push(analyze_check(&check, &repo_root, args.max_lines.max(1), args.context.max(1)));
    }

    if args.as_json {
        println!(
            "{}",
            serde_json::to_string_pretty(&json!({ "pr": pr_value, "results": results }))
                .map_err(|err| err.to_string())?
        );
    } else {
        render_results(&pr_value, &results);
    }

    Ok(1)
}

fn parse_args(args: Vec<String>) -> Result<Args, String> {
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!("Usage: inspect-pr-checks [--repo path] [--pr number-or-url] [--max-lines n] [--context n] [--json]");
        std::process::exit(0);
    }

    let mut parsed = Args {
        repo: ".".to_string(),
        pr: None,
        max_lines: DEFAULT_MAX_LINES,
        context: DEFAULT_CONTEXT_LINES,
        as_json: false,
    };

    let mut index = 0usize;
    while index < args.len() {
        match args[index].as_str() {
            "--repo" => {
                parsed.repo = args
                    .get(index + 1)
                    .cloned()
                    .ok_or_else(|| "--repo requires a value".to_string())?;
                index += 2;
            }
            "--pr" => {
                parsed.pr = Some(
                    args.get(index + 1)
                        .cloned()
                        .ok_or_else(|| "--pr requires a value".to_string())?,
                );
                index += 2;
            }
            "--max-lines" => {
                parsed.max_lines = args
                    .get(index + 1)
                    .ok_or_else(|| "--max-lines requires a value".to_string())?
                    .parse::<usize>()
                    .map_err(|_| "--max-lines requires a number".to_string())?;
                index += 2;
            }
            "--context" => {
                parsed.context = args
                    .get(index + 1)
                    .ok_or_else(|| "--context requires a value".to_string())?
                    .parse::<usize>()
                    .map_err(|_| "--context requires a number".to_string())?;
                index += 2;
            }
            "--json" => {
                parsed.as_json = true;
                index += 1;
            }
            other => return Err(format!("Unknown option: {other}")),
        }
    }

    Ok(parsed)
}

fn find_git_root(start: &Path) -> Result<Option<PathBuf>, String> {
    let output = run_process("git", &["rev-parse", "--show-toplevel"], Some(start), None)?;
    if output.status != 0 {
        return Ok(None);
    }
    Ok(Some(PathBuf::from(
        String::from_utf8_lossy(&output.stdout).trim().to_string(),
    )))
}

fn ensure_gh_available(repo_root: &Path) -> Result<(), String> {
    let version = run_process("gh", &["--version"], Some(repo_root), None)?;
    if version.status != 0 {
        return Err("Error: gh is not installed or not on PATH.".to_string());
    }
    let auth = run_process("gh", &["auth", "status"], Some(repo_root), None)?;
    if auth.status == 0 {
        return Ok(());
    }
    let message = combined_message(&auth);
    Err(if message.is_empty() {
        "Error: gh not authenticated.".to_string()
    } else {
        message
    })
}

fn resolve_pr(pr_value: Option<&str>, repo_root: &Path) -> Result<String, String> {
    if let Some(value) = pr_value {
        return Ok(value.to_string());
    }
    let result = run_process("gh", &["pr", "view", "--json", "number"], Some(repo_root), None)?;
    if result.status != 0 {
        let message = combined_message(&result);
        return Err(if message.is_empty() {
            "Error: unable to resolve PR.".to_string()
        } else {
            message
        });
    }

    let data: Value = serde_json::from_slice(&result.stdout).map_err(|_| "Error: unable to parse PR JSON.".to_string())?;
    data.get("number")
        .and_then(Value::as_i64)
        .map(|value| value.to_string())
        .ok_or_else(|| "Error: no PR number found.".to_string())
}

fn fetch_checks(pr_value: &str, repo_root: &Path) -> Result<Vec<Value>, String> {
    let primary_fields = "name,state,conclusion,detailsUrl,startedAt,completedAt";
    let mut result = run_process(
        "gh",
        &["pr", "checks", pr_value, "--json", primary_fields],
        Some(repo_root),
        None,
    )?;
    if result.status != 0 {
        let message = combined_message(&result);
        let available_fields = parse_available_fields(&message);
        if available_fields.is_empty() {
            return Err(if message.is_empty() {
                "Error: gh pr checks failed.".to_string()
            } else {
                message
            });
        }

        let fallback_fields = [
            "name",
            "state",
            "bucket",
            "link",
            "startedAt",
            "completedAt",
            "workflow",
        ];
        let selected_fields: Vec<&str> = fallback_fields
            .iter()
            .copied()
            .filter(|field| available_fields.iter().any(|value| value == field))
            .collect();
        if selected_fields.is_empty() {
            return Err("Error: no usable fields available for gh pr checks.".to_string());
        }

        result = run_process(
            "gh",
            &["pr", "checks", pr_value, "--json", &selected_fields.join(",")],
            Some(repo_root),
            None,
        )?;
        if result.status != 0 {
            let retry_message = combined_message(&result);
            return Err(if retry_message.is_empty() {
                "Error: gh pr checks failed.".to_string()
            } else {
                retry_message
            });
        }
    }

    let data: Value = serde_json::from_slice(&result.stdout).map_err(|_| "Error: unable to parse checks JSON.".to_string())?;
    data.as_array()
        .cloned()
        .ok_or_else(|| "Error: unexpected checks JSON shape.".to_string())
}

fn is_failing(check: &Value) -> bool {
    let conclusion = normalize_field(check.get("conclusion"));
    if FAILURE_CONCLUSIONS.iter().any(|value| *value == conclusion) {
        return true;
    }

    let state = normalize_field(check.get("state").or_else(|| check.get("status")));
    if FAILURE_STATES.iter().any(|value| *value == state) {
        return true;
    }

    let bucket = normalize_field(check.get("bucket"));
    FAILURE_BUCKETS.iter().any(|value| *value == bucket)
}

fn analyze_check(check: &Value, repo_root: &Path, max_lines: usize, context: usize) -> Value {
    let url = check
        .get("detailsUrl")
        .or_else(|| check.get("link"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let run_id = extract_run_id(&url);
    let job_id = extract_job_id(&url);
    let mut base = json!({
        "name": check.get("name").cloned().unwrap_or(Value::String(String::new())),
        "detailsUrl": url,
        "runId": run_id.clone(),
        "jobId": job_id.clone(),
    });

    let Some(run_id) = run_id else {
        base["status"] = Value::String("external".to_string());
        base["note"] = Value::String("No GitHub Actions run id detected in detailsUrl.".to_string());
        return base;
    };

    let metadata = fetch_run_metadata(&run_id, repo_root).ok();
    let (log_text, log_error, log_status) = fetch_check_log(&run_id, job_id.as_deref(), repo_root);

    match log_status.as_str() {
        "pending" => {
            base["status"] = Value::String("log_pending".to_string());
            base["note"] = Value::String(log_error.unwrap_or_else(|| "Logs are not available yet.".to_string()));
            if let Some(metadata) = metadata {
                base["run"] = metadata;
            }
        }
        "error" => {
            base["status"] = Value::String("log_unavailable".to_string());
            base["error"] = Value::String(log_error.unwrap_or_else(|| "Unknown log error.".to_string()));
            if let Some(metadata) = metadata {
                base["run"] = metadata;
            }
        }
        _ => {
            let snippet = extract_failure_snippet(log_text.as_deref().unwrap_or_default(), max_lines, context);
            base["status"] = Value::String("ok".to_string());
            base["run"] = metadata.unwrap_or_else(|| json!({}));
            base["logSnippet"] = Value::String(snippet);
            base["logTail"] = Value::String(tail_lines(log_text.as_deref().unwrap_or_default(), max_lines));
        }
    }

    base
}

fn extract_run_id(url: &str) -> Option<String> {
    extract_numeric_segment(url, "/actions/runs/").or_else(|| extract_numeric_segment(url, "/runs/"))
}

fn extract_job_id(url: &str) -> Option<String> {
    extract_numeric_segment(url, "/actions/runs/")
        .and_then(|_| extract_numeric_segment(url, "/job/"))
        .or_else(|| extract_numeric_segment(url, "/job/"))
}

fn extract_numeric_segment(url: &str, marker: &str) -> Option<String> {
    let index = url.find(marker)?;
    let digits: String = url[index + marker.len()..]
        .chars()
        .take_while(|ch| ch.is_ascii_digit())
        .collect();
    if digits.is_empty() {
        None
    } else {
        Some(digits)
    }
}

fn fetch_run_metadata(run_id: &str, repo_root: &Path) -> Result<Value, String> {
    let fields = "conclusion,status,workflowName,name,event,headBranch,headSha,url";
    let result = run_process("gh", &["run", "view", run_id, "--json", fields], Some(repo_root), None)?;
    if result.status != 0 {
        return Err(String::new());
    }
    serde_json::from_slice(&result.stdout).map_err(|_| String::new())
}

fn fetch_check_log(run_id: &str, job_id: Option<&str>, repo_root: &Path) -> (Option<String>, Option<String>, String) {
    let (log_text, log_error) = fetch_run_log(run_id, repo_root);
    if log_error.is_none() {
        return (log_text, None, "ok".to_string());
    }

    let run_error = log_error.unwrap_or_default();
    if is_log_pending_message(&run_error) {
        if let Some(job_id) = job_id {
            let (job_log, job_error) = fetch_job_log(job_id, repo_root);
            if job_error.is_none() {
                return (job_log, None, "ok".to_string());
            }
            let job_error = job_error.unwrap_or_default();
            if is_log_pending_message(&job_error) {
                return (None, Some(job_error), "pending".to_string());
            }
            return (None, Some(job_error), "error".to_string());
        }
        return (None, Some(run_error), "pending".to_string());
    }

    (None, Some(run_error), "error".to_string())
}

fn fetch_run_log(run_id: &str, repo_root: &Path) -> (Option<String>, Option<String>) {
    match run_process("gh", &["run", "view", run_id, "--log"], Some(repo_root), None) {
        Ok(result) if result.status == 0 => (
            Some(String::from_utf8_lossy(&result.stdout).to_string()),
            None,
        ),
        Ok(result) => {
            let message = combined_message(&result);
            (None, Some(if message.is_empty() { "gh run view failed".to_string() } else { message }))
        }
        Err(err) => (None, Some(err)),
    }
}

fn fetch_job_log(job_id: &str, repo_root: &Path) -> (Option<String>, Option<String>) {
    let Some(repo_slug) = fetch_repo_slug(repo_root) else {
        return (None, Some("Error: unable to resolve repository name for job logs.".to_string()));
    };
    let endpoint = format!("/repos/{repo_slug}/actions/jobs/{job_id}/logs");
    match run_process("gh", &["api", &endpoint], Some(repo_root), None) {
        Ok(result) if result.status == 0 => {
            if result.stdout.starts_with(b"PK") {
                return (None, Some("Job logs returned a zip archive; unable to parse.".to_string()));
            }
            (
                Some(String::from_utf8_lossy(&result.stdout).to_string()),
                None,
            )
        }
        Ok(result) => {
            let message = combined_message(&result);
            (None, Some(if message.is_empty() { "gh api job logs failed".to_string() } else { message }))
        }
        Err(err) => (None, Some(err)),
    }
}

fn fetch_repo_slug(repo_root: &Path) -> Option<String> {
    let result = run_process("gh", &["repo", "view", "--json", "nameWithOwner"], Some(repo_root), None).ok()?;
    if result.status != 0 {
        return None;
    }
    let data: Value = serde_json::from_slice(&result.stdout).ok()?;
    data.get("nameWithOwner").and_then(Value::as_str).map(|value| value.to_string())
}

fn normalize_field(value: Option<&Value>) -> String {
    value
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_ascii_lowercase()
}

fn parse_available_fields(message: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut collecting = false;
    for line in message.lines() {
        if line.contains("Available fields:") {
            collecting = true;
            continue;
        }
        if !collecting {
            continue;
        }
        let field = line.trim();
        if !field.is_empty() {
            fields.push(field.to_string());
        }
    }
    fields
}

fn is_log_pending_message(message: &str) -> bool {
    let lowered = message.to_ascii_lowercase();
    PENDING_LOG_MARKERS.iter().any(|marker| lowered.contains(marker))
}

fn extract_failure_snippet(log_text: &str, max_lines: usize, context: usize) -> String {
    let lines: Vec<&str> = log_text.lines().collect();
    if lines.is_empty() {
        return String::new();
    }

    if let Some(marker_index) = find_failure_index(&lines) {
        let start = marker_index.saturating_sub(context);
        let end = usize::min(lines.len(), marker_index + context);
        let mut window: Vec<&str> = lines[start..end].to_vec();
        if window.len() > max_lines {
            window = window[window.len() - max_lines..].to_vec();
        }
        return window.join("\n");
    }

    lines[lines.len().saturating_sub(max_lines)..].join("\n")
}

fn find_failure_index(lines: &[&str]) -> Option<usize> {
    for (index, line) in lines.iter().enumerate().rev() {
        let lowered = line.to_ascii_lowercase();
        if FAILURE_MARKERS.iter().any(|marker| lowered.contains(marker)) {
            return Some(index);
        }
    }
    None
}

fn tail_lines(text: &str, max_lines: usize) -> String {
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(max_lines)..].join("\n")
}

fn render_results(pr_number: &str, results: &[Value]) {
    println!("PR #{pr_number}: {} failing checks analyzed.", results.len());
    for result in results {
        println!("{}", "-".repeat(60));
        println!(
            "Check: {}",
            result.get("name").and_then(Value::as_str).unwrap_or_default()
        );
        if let Some(details) = result.get("detailsUrl").and_then(Value::as_str).filter(|value| !value.is_empty()) {
            println!("Details: {details}");
        }
        if let Some(run_id) = result.get("runId").and_then(Value::as_str) {
            println!("Run ID: {run_id}");
        }
        if let Some(job_id) = result.get("jobId").and_then(Value::as_str) {
            println!("Job ID: {job_id}");
        }
        println!(
            "Status: {}",
            result.get("status").and_then(Value::as_str).unwrap_or("unknown")
        );

        if let Some(run_meta) = result.get("run").and_then(Value::as_object) {
            let branch = run_meta.get("headBranch").and_then(Value::as_str).unwrap_or_default();
            let sha = run_meta
                .get("headSha")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .chars()
                .take(12)
                .collect::<String>();
            let workflow = run_meta
                .get("workflowName")
                .or_else(|| run_meta.get("name"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            let conclusion = run_meta
                .get("conclusion")
                .or_else(|| run_meta.get("status"))
                .and_then(Value::as_str)
                .unwrap_or_default();
            if !workflow.is_empty() || !conclusion.is_empty() {
                println!("Workflow: {workflow} ({conclusion})");
            }
            if !branch.is_empty() || !sha.is_empty() {
                println!("Branch/SHA: {branch} {sha}");
            }
            if let Some(url) = run_meta.get("url").and_then(Value::as_str) {
                println!("Run URL: {url}");
            }
        }

        if let Some(note) = result.get("note").and_then(Value::as_str) {
            println!("Note: {note}");
        }
        if let Some(error) = result.get("error").and_then(Value::as_str) {
            println!("Error fetching logs: {error}");
            continue;
        }
        if let Some(snippet) = result.get("logSnippet").and_then(Value::as_str).filter(|value| !value.is_empty()) {
            println!("Failure snippet:");
            for line in snippet.lines() {
                println!("  {line}");
            }
        } else {
            println!("No snippet available.");
        }
    }
    println!("{}", "-".repeat(60));
}

struct ProcessOutput {
    status: i32,
    stdout: Vec<u8>,
    stderr: String,
}

fn run_process(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    stdin: Option<&str>,
) -> Result<ProcessOutput, String> {
    let mut command = Command::new(program);
    command.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    if stdin.is_some() {
        command.stdin(Stdio::piped());
    }

    let mut child = command.spawn().map_err(|err| err.to_string())?;
    if let Some(stdin_text) = stdin {
        use std::io::Write;
        let mut handle = child
            .stdin
            .take()
            .ok_or_else(|| "Failed to open stdin for child process.".to_string())?;
        handle
            .write_all(stdin_text.as_bytes())
            .map_err(|err| err.to_string())?;
    }
    let output = child.wait_with_output().map_err(|err| err.to_string())?;
    Ok(ProcessOutput {
        status: output.status.code().unwrap_or(1),
        stdout: output.stdout,
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

fn combined_message(output: &ProcessOutput) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = output.stderr.trim().to_string();
    if stdout.is_empty() {
        stderr
    } else if stderr.is_empty() {
        stdout
    } else {
        format!("{stderr}\n{stdout}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_args_reads_common_flags() {
        let args = vec![
            "--repo".to_string(),
            "repo".to_string(),
            "--pr".to_string(),
            "123".to_string(),
            "--max-lines".to_string(),
            "80".to_string(),
            "--context".to_string(),
            "12".to_string(),
            "--json".to_string(),
        ];

        assert_eq!(
            parse_args(args).expect("parsed args"),
            Args {
                repo: "repo".to_string(),
                pr: Some("123".to_string()),
                max_lines: 80,
                context: 12,
                as_json: true,
            }
        );
    }

    #[test]
    fn detects_failing_checks_from_state_or_conclusion() {
        assert!(is_failing(&json!({ "state": "FAILURE" })));
        assert!(is_failing(&json!({ "conclusion": "timed_out" })));
        assert!(!is_failing(&json!({ "state": "SUCCESS" })));
    }

    #[test]
    fn extracts_run_and_job_ids_from_github_actions_urls() {
        let url = "https://github.com/org/repo/actions/runs/123456789/job/987654321";
        assert_eq!(extract_run_id(url), Some("123456789".to_string()));
        assert_eq!(extract_job_id(url), Some("987654321".to_string()));
    }

    #[test]
    fn parses_available_fields_from_cli_error_message() {
        let message = "unknown JSON field\nAvailable fields:\nname\nstate\nbucket\n";
        assert_eq!(
            parse_available_fields(message),
            vec!["name".to_string(), "state".to_string(), "bucket".to_string()]
        );
    }

    #[test]
    fn pending_log_message_detection_is_case_insensitive() {
        assert!(is_log_pending_message("Log will be available when it is complete"));
        assert!(!is_log_pending_message("hard failure"));
    }

    #[test]
    fn extracts_failure_snippet_around_latest_marker() {
        let log = "setup\nerror: first failure\nmid\npanic: second failure\ncleanup";
        let snippet = extract_failure_snippet(log, 10, 1);
        assert_eq!(snippet, "mid\npanic: second failure");
    }
}
