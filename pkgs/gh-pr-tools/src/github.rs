use serde_json::{json, Value};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const GITHUB_HOST: &str = "github.com";

const PR_PREFLIGHT_QUERY: &str = r#"query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    visibility
    pullRequest(number: $number) {
      body
      isCrossRepository
      number
      url
      viewerCanUpdate
      viewerCannotUpdateReasons
    }
  }
}"#;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RepositorySlug {
    pub owner: String,
    pub name: String,
}

impl RepositorySlug {
    pub fn parse(value: &str) -> Result<Self, String> {
        let mut parts = value.split('/');
        let owner = parts.next().unwrap_or_default();
        let name = parts.next().unwrap_or_default();
        if parts.next().is_some() || !valid_repo_component(owner) || !valid_repo_component(name) {
            return Err("Repository must be in owner/name form.".to_string());
        }
        Ok(Self {
            owner: owner.to_string(),
            name: name.to_string(),
        })
    }

    pub fn as_string(&self) -> String {
        format!("{}/{}", self.owner, self.name)
    }

    fn as_github_selector(&self) -> String {
        format!("{GITHUB_HOST}/{}", self.as_string())
    }

    fn same_repository(&self, other: &Self) -> bool {
        self.owner.eq_ignore_ascii_case(&other.owner) && self.name.eq_ignore_ascii_case(&other.name)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Repository {
    pub slug: RepositorySlug,
    pub database_id: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PullRequest {
    pub number: u64,
    pub url: String,
    pub body: String,
}

pub struct SecretToken(String);

impl SecretToken {
    pub(crate) fn new(value: String) -> Result<Self, String> {
        if value.is_empty() || !value.is_ascii() || value.chars().any(char::is_control) {
            return Err("`gh auth token` returned an invalid token.".to_string());
        }
        Ok(Self(value))
    }

    pub(crate) fn expose(&self) -> &str {
        &self.0
    }
}

pub struct GhClient {
    program: PathBuf,
}

impl GhClient {
    pub fn new(program: impl AsRef<Path>) -> Self {
        Self {
            program: program.as_ref().to_path_buf(),
        }
    }

    pub fn resolve_target(
        &self,
        repository: Option<&RepositorySlug>,
        selector: Option<&str>,
    ) -> Result<(RepositorySlug, u64), String> {
        let selector_url = selector
            .and_then(|value| parse_pr_url(value).transpose())
            .transpose()?;
        let url_repository = selector_url.as_ref().map(|(repository, _)| repository);
        if let (Some(requested), Some(from_url)) = (repository, url_repository) {
            if !requested.same_repository(from_url) {
                return Err("-R/--repo does not match the repository in --pr URL.".to_string());
            }
        }

        let repository = if let Some(from_url) = url_repository {
            from_url.clone()
        } else if let Some(requested) = repository {
            self.canonical_repository(Some(requested))?
        } else {
            self.canonical_repository(None)?
        };

        if let Some((_, number)) = selector_url {
            return Ok((repository, number));
        }

        let mut args = vec!["pr".to_string(), "view".to_string()];
        if let Some(selector) = selector {
            args.push(selector.to_string());
        }
        args.extend([
            "-R".to_string(),
            repository.as_github_selector(),
            "--json".to_string(),
            "number,url".to_string(),
        ]);
        let response = self.run_json(&args, None)?;
        let number = response
            .get("number")
            .and_then(Value::as_u64)
            .ok_or_else(|| "GitHub PR response is missing a numeric number.".to_string())?;
        let url = response
            .get("url")
            .and_then(Value::as_str)
            .ok_or_else(|| "GitHub PR response is missing its URL.".to_string())?;
        let (url_repository, url_number) = parse_pr_url(url)?
            .ok_or_else(|| "GitHub PR response returned a non-github.com URL.".to_string())?;
        if !repository.same_repository(&url_repository) || number != url_number {
            return Err("GitHub PR response does not match the requested repository.".to_string());
        }
        Ok((repository, number))
    }

    pub fn preflight(
        &self,
        repository: RepositorySlug,
        number: u64,
    ) -> Result<(Repository, PullRequest), String> {
        let args = vec![
            "api".to_string(),
            "graphql".to_string(),
            "-f".to_string(),
            format!("query={PR_PREFLIGHT_QUERY}"),
            "-F".to_string(),
            format!("owner={}", repository.owner),
            "-F".to_string(),
            format!("name={}", repository.name),
            "-F".to_string(),
            format!("number={number}"),
            "--hostname".to_string(),
            GITHUB_HOST.to_string(),
        ];
        let response = self.run_json(&args, None)?;
        reject_graphql_errors(&response)?;
        let repository_value = response
            .pointer("/data/repository")
            .ok_or_else(|| "GitHub GraphQL response is missing the repository.".to_string())?;
        if repository_value.get("visibility").and_then(Value::as_str) != Some("PUBLIC") {
            return Err(
                "gh-pr-image currently supports only public repositories; no image was uploaded."
                    .to_string(),
            );
        }
        let pull_request = repository_value
            .get("pullRequest")
            .ok_or_else(|| "GitHub GraphQL response is missing the pull request.".to_string())?;
        if pull_request
            .get("isCrossRepository")
            .and_then(Value::as_bool)
            != Some(false)
        {
            return Err(
                "gh-pr-image currently supports only same-repository pull requests; no image was uploaded."
                    .to_string(),
            );
        }
        if pull_request.get("viewerCanUpdate").and_then(Value::as_bool) != Some(true) {
            let reasons = pull_request
                .get("viewerCannotUpdateReasons")
                .and_then(Value::as_array)
                .map(|items| {
                    items
                        .iter()
                        .filter_map(Value::as_str)
                        .filter(|value| {
                            !value.is_empty()
                                && value
                                    .bytes()
                                    .all(|byte| byte.is_ascii_uppercase() || byte == b'_')
                        })
                        .collect::<Vec<_>>()
                        .join(", ")
                })
                .filter(|value| !value.is_empty());
            return Err(match reasons {
                Some(reasons) => format!(
                    "GitHub reports that the current viewer cannot update this PR ({reasons}); no image was uploaded."
                ),
                None => "GitHub reports that the current viewer cannot update this PR; no image was uploaded."
                    .to_string(),
            });
        }

        let returned_number = pull_request
            .get("number")
            .and_then(Value::as_u64)
            .ok_or_else(|| "GitHub GraphQL response is missing the PR number.".to_string())?;
        let url = pull_request
            .get("url")
            .and_then(Value::as_str)
            .ok_or_else(|| "GitHub GraphQL response is missing the PR URL.".to_string())?;
        let (url_repository, url_number) = parse_pr_url(url)?
            .ok_or_else(|| "GitHub returned a non-github.com PR URL.".to_string())?;
        if returned_number != number
            || url_number != number
            || !repository.same_repository(&url_repository)
        {
            return Err("GitHub GraphQL PR context does not match the requested PR.".to_string());
        }

        let repo_response = self.run_json(
            &[
                "api".to_string(),
                format!("repos/{}", repository.as_string()),
                "--hostname".to_string(),
                GITHUB_HOST.to_string(),
            ],
            None,
        )?;
        let database_id = repo_response
            .get("id")
            .and_then(Value::as_u64)
            .ok_or_else(|| "GitHub repository response is missing its numeric ID.".to_string())?;

        Ok((
            Repository {
                slug: repository,
                database_id,
            },
            PullRequest {
                number,
                url: url.to_string(),
                body: parse_required_body(pull_request, "GitHub GraphQL response")?,
            },
        ))
    }

    pub fn token(&self) -> Result<SecretToken, String> {
        let output = self.run(
            &[
                "auth".to_string(),
                "token".to_string(),
                "--hostname".to_string(),
                GITHUB_HOST.to_string(),
            ],
            None,
        )?;
        let token = String::from_utf8(output.stdout)
            .map_err(|_| "`gh auth token` returned non-UTF-8 output.".to_string())?;
        SecretToken::new(token.trim().to_string())
    }

    pub fn body(&self, repository: &RepositorySlug, number: u64) -> Result<String, String> {
        let response = self.run_json(
            &[
                "api".to_string(),
                format!("repos/{}/pulls/{number}", repository.as_string()),
                "--hostname".to_string(),
                GITHUB_HOST.to_string(),
            ],
            None,
        )?;
        parse_nullable_body(&response, "GitHub pull request response")
    }

    pub fn patch_body(
        &self,
        repository: &RepositorySlug,
        number: u64,
        body: &str,
    ) -> Result<(), String> {
        let input = serde_json::to_vec(&json!({ "body": body }))
            .map_err(|error| format!("Failed to serialize PR body: {error}"))?;
        self.run_json(
            &[
                "api".to_string(),
                format!("repos/{}/pulls/{number}", repository.as_string()),
                "--method".to_string(),
                "PATCH".to_string(),
                "--input".to_string(),
                "-".to_string(),
                "--hostname".to_string(),
                GITHUB_HOST.to_string(),
            ],
            Some(&input),
        )?;
        Ok(())
    }

    fn canonical_repository(
        &self,
        requested: Option<&RepositorySlug>,
    ) -> Result<RepositorySlug, String> {
        let mut args = vec!["repo".to_string(), "view".to_string()];
        if let Some(requested) = requested {
            args.push(requested.as_github_selector());
        }
        args.extend(["--json".to_string(), "nameWithOwner,url".to_string()]);
        let response = self.run_json(&args, None)?;
        let name = response
            .get("nameWithOwner")
            .and_then(Value::as_str)
            .ok_or_else(|| "GitHub repository response is missing nameWithOwner.".to_string())?;
        let canonical = RepositorySlug::parse(name)?;
        let url = response
            .get("url")
            .and_then(Value::as_str)
            .ok_or_else(|| "GitHub repository response is missing its URL.".to_string())?;
        let url_repository = parse_repository_url(url)?;
        if !canonical.same_repository(&url_repository)
            || !requested
                .map(|value| value.same_repository(&canonical))
                .unwrap_or(true)
        {
            return Err(
                "GitHub repository response does not match the requested repository.".to_string(),
            );
        }
        Ok(canonical)
    }

    fn run_json(&self, args: &[String], stdin: Option<&[u8]>) -> Result<Value, String> {
        let output = self.run(args, stdin)?;
        serde_json::from_slice(&output.stdout)
            .map_err(|error| format!("GitHub CLI returned malformed JSON: {error}"))
    }

    fn run(&self, args: &[String], stdin: Option<&[u8]>) -> Result<CommandOutput, String> {
        let mut command = Command::new(&self.program);
        command
            .args(args)
            .env("GH_HOST", GITHUB_HOST)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if stdin.is_some() {
            command.stdin(Stdio::piped());
        }

        let mut child = command.spawn().map_err(|error| {
            format!(
                "Failed to run `{}`: {error}. Install and authenticate GitHub CLI first.",
                self.program.display()
            )
        })?;
        if let Some(input) = stdin {
            child
                .stdin
                .take()
                .ok_or_else(|| "Failed to open GitHub CLI stdin.".to_string())?
                .write_all(input)
                .map_err(|error| format!("Failed to write GitHub CLI stdin: {error}"))?;
        }
        let output = child
            .wait_with_output()
            .map_err(|error| format!("Failed to wait for GitHub CLI: {error}"))?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let detail = stderr.trim();
            return Err(if detail.is_empty() {
                "GitHub CLI command failed.".to_string()
            } else {
                format!("GitHub CLI command failed: {detail}")
            });
        }
        Ok(CommandOutput {
            stdout: output.stdout,
        })
    }
}

struct CommandOutput {
    stdout: Vec<u8>,
}

fn reject_graphql_errors(value: &Value) -> Result<(), String> {
    match value.get("errors") {
        None => Ok(()),
        Some(Value::Array(errors)) if errors.is_empty() => Ok(()),
        Some(Value::Array(_)) => Err("GitHub GraphQL preflight returned errors.".to_string()),
        Some(_) => Err("GitHub GraphQL preflight returned a malformed errors field.".to_string()),
    }
}

fn parse_required_body(value: &Value, context: &str) -> Result<String, String> {
    match value.get("body") {
        Some(Value::String(body)) => Ok(body.clone()),
        Some(_) => Err(format!("{context} contains a non-string PR body.")),
        None => Err(format!("{context} is missing the PR body field.")),
    }
}

fn parse_nullable_body(value: &Value, context: &str) -> Result<String, String> {
    match value.get("body") {
        Some(Value::String(body)) => Ok(body.clone()),
        Some(Value::Null) => Ok(String::new()),
        Some(_) => Err(format!("{context} contains a non-string PR body.")),
        None => Err(format!("{context} is missing the PR body field.")),
    }
}

fn parse_pr_url(value: &str) -> Result<Option<(RepositorySlug, u64)>, String> {
    if !value.contains("://") {
        return Ok(None);
    }
    let uri: ureq::http::Uri = value
        .parse()
        .map_err(|_| "--pr URL is invalid.".to_string())?;
    if uri.scheme_str() != Some("https")
        || uri.authority().map(|value| value.as_str()) != Some("github.com")
        || uri
            .path_and_query()
            .and_then(|path_and_query| path_and_query.query())
            .is_some()
        || value.contains('#')
    {
        return Err("--pr URL must be an https://github.com pull request URL.".to_string());
    }
    let parts: Vec<_> = uri.path().trim_matches('/').split('/').collect();
    if parts.len() != 4 || parts[2] != "pull" {
        return Err(
            "--pr URL must be in https://github.com/owner/repo/pull/number form.".to_string(),
        );
    }
    let repository = RepositorySlug::parse(&format!("{}/{}", parts[0], parts[1]))?;
    let number = parts[3]
        .parse::<u64>()
        .ok()
        .filter(|value| *value > 0)
        .ok_or_else(|| "--pr URL contains an invalid PR number.".to_string())?;
    Ok(Some((repository, number)))
}

fn parse_repository_url(value: &str) -> Result<RepositorySlug, String> {
    let uri: ureq::http::Uri = value
        .parse()
        .map_err(|_| "GitHub repository URL is invalid.".to_string())?;
    if uri.scheme_str() != Some("https")
        || uri.authority().map(|value| value.as_str()) != Some("github.com")
        || uri
            .path_and_query()
            .and_then(|path_and_query| path_and_query.query())
            .is_some()
        || value.contains('#')
    {
        return Err("Only github.com repositories are supported.".to_string());
    }
    RepositorySlug::parse(uri.path().trim_matches('/'))
}

fn valid_repo_component(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 100
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.'))
        && value != "."
        && value != ".."
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_and_compares_repository_names() {
        let repository = RepositorySlug::parse("Owner/repo.name").expect("repository");
        assert_eq!(repository.as_string(), "Owner/repo.name");
        assert_eq!(
            repository.as_github_selector(),
            "github.com/Owner/repo.name"
        );
        assert!(repository
            .same_repository(&RepositorySlug::parse("owner/REPO.NAME").expect("same repository")));
        assert!(RepositorySlug::parse("owner/repo/extra").is_err());
    }

    #[test]
    fn strictly_parses_pull_request_urls() {
        let (repository, number) = parse_pr_url("https://github.com/owner/repo/pull/42")
            .expect("parse")
            .expect("url");
        assert_eq!(repository.as_string(), "owner/repo");
        assert_eq!(number, 42);
        assert!(parse_pr_url("https://evil.example/owner/repo/pull/42").is_err());
        assert!(parse_pr_url("https://github.com/owner/repo/pull/42/files").is_err());
        assert_eq!(parse_pr_url("feature-branch").expect("branch"), None);
    }

    #[test]
    fn accepts_only_string_or_null_pr_bodies() {
        assert_eq!(
            parse_nullable_body(&json!({ "body": "Details" }), "response").expect("body"),
            "Details"
        );
        assert_eq!(
            parse_nullable_body(&json!({ "body": null }), "response").expect("null body"),
            ""
        );
        assert!(parse_nullable_body(&json!({}), "response").is_err());
        assert!(parse_nullable_body(&json!({ "body": 42 }), "response").is_err());
    }

    #[test]
    fn graph_ql_preflight_rejects_schema_invalid_fields() {
        assert_eq!(
            parse_required_body(&json!({ "body": "Details" }), "response").expect("required body"),
            "Details"
        );
        assert!(parse_required_body(&json!({ "body": null }), "response").is_err());
        assert!(parse_required_body(&json!({}), "response").is_err());
        assert!(reject_graphql_errors(&json!({})).is_ok());
        assert!(reject_graphql_errors(&json!({ "errors": [] })).is_ok());
        assert!(reject_graphql_errors(&json!({ "errors": [{ "message": "no" }] })).is_err());
        assert!(reject_graphql_errors(&json!({ "errors": null })).is_err());
        assert!(reject_graphql_errors(&json!({ "errors": "invalid" })).is_err());
    }
}
