pub mod body;
pub mod cli;
pub mod github;
pub mod image;
pub mod journal;
pub mod user_attachments;

use crate::body::{add_attachment, find_attachment, validate_alt, BodyAttachment};
use crate::cli::AddConfig;
use crate::github::GhClient;
use crate::image::load_image;
use crate::journal::RecoveryJournal;
use crate::user_attachments::{UploadError, UserAttachmentsClient};
use serde::Serialize;
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct UploadedAttachment {
    pub sha256: String,
    pub name: String,
    pub media_type: String,
    pub alt: String,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RunOutput {
    pub pull_request_url: String,
    pub markdown: String,
    pub warning: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorKind {
    Usage,
    Runtime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppError {
    kind: ErrorKind,
    message: String,
}

impl AppError {
    pub fn kind(&self) -> ErrorKind {
        self.kind
    }

    fn runtime(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Runtime,
            message: message.into(),
        }
    }

    fn usage(message: impl Into<String>) -> Self {
        Self {
            kind: ErrorKind::Usage,
            message: message.into(),
        }
    }
}

impl fmt::Display for AppError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

pub fn add_image_to_pr(
    config: &AddConfig,
    github: &GhClient,
    uploader: &UserAttachmentsClient,
) -> Result<RunOutput, AppError> {
    validate_alt(&config.alt).map_err(AppError::usage)?;
    let image = load_image(&config.image, &config.alt).map_err(AppError::usage)?;
    let (repository_slug, pull_request_number) = github
        .resolve_target(config.repository.as_ref(), config.pull_request.as_deref())
        .map_err(AppError::runtime)?;
    let (repository, pull_request) = github
        .preflight(repository_slug, pull_request_number)
        .map_err(AppError::runtime)?;

    if let Some(existing) =
        find_attachment(&pull_request.body, &image.sha256).map_err(AppError::runtime)?
    {
        return Ok(RunOutput {
            pull_request_url: pull_request.url,
            markdown: markdown(&existing.alt, &existing.url),
            warning: None,
        });
    }

    let token = github.token().map_err(AppError::runtime)?;
    let journal =
        RecoveryJournal::prepare(&repository, &pull_request, &image).map_err(AppError::runtime)?;
    eprintln!("Recovery journal: {}", journal.path().display());

    let uploaded_url = match uploader.upload(
        repository.database_id,
        &image.name,
        image.media_type,
        &image.bytes,
        &token,
    ) {
        Ok(url) => url,
        Err(error @ (UploadError::NotSent(_) | UploadError::Rejected(_))) => {
            if let Err(cleanup_error) = journal.cleanup() {
                return Err(AppError::runtime(format!(
                    "{error}\nThe unused recovery journal could not be removed: {cleanup_error}"
                )));
            }
            return Err(AppError::runtime(error.to_string()));
        }
        Err(error) => {
            let journal_error = error.is_ambiguous().then(|| {
                journal
                    .record_ambiguous(&repository, &pull_request, &image)
                    .err()
            });
            return Err(ambiguous_upload_error(
                error,
                &journal,
                journal_error.flatten(),
            ));
        }
    };

    let uploaded = UploadedAttachment {
        sha256: image.sha256,
        name: image.name,
        media_type: image.media_type.to_string(),
        alt: image.alt,
        url: uploaded_url,
    };
    if let Err(error) = journal.record_uploaded(&repository, &pull_request, &uploaded) {
        return Err(recovery_error(
            format!(
                "The attachment upload succeeded, but its URL could not be persisted to the recovery journal: {error}"
            ),
            &journal,
            &uploaded,
        ));
    }

    let latest_body = github
        .body(&repository.slug, pull_request.number)
        .map_err(|error| recovery_error(error, &journal, &uploaded))?;
    let change = add_attachment(
        &latest_body,
        BodyAttachment {
            sha256: uploaded.sha256.clone(),
            alt: uploaded.alt.clone(),
            url: uploaded.url.clone(),
        },
    )
    .map_err(|error| recovery_error(error, &journal, &uploaded))?;

    if change.already_present {
        return Ok(RunOutput {
            pull_request_url: pull_request.url,
            markdown: change.markdown,
            warning: Some(format!(
                "Another process added the same image first. The unused uploaded URL is recorded at `{}`.",
                journal.path().display()
            )),
        });
    }

    let patch_result = github.patch_body(&repository.slug, pull_request.number, &change.body);
    let verified_body = github
        .body(&repository.slug, pull_request.number)
        .map_err(|error| recovery_error(error, &journal, &uploaded))?;
    let verified = find_attachment(&verified_body, &uploaded.sha256)
        .map_err(|error| recovery_error(error, &journal, &uploaded))?
        .is_some_and(|entry| entry.url == uploaded.url && entry.alt == uploaded.alt);

    if !verified {
        let patch_detail = patch_result
            .err()
            .map(|error| format!(" Patch command error: {error}"))
            .unwrap_or_default();
        return Err(recovery_error(
            format!("PR body verification failed.{patch_detail}"),
            &journal,
            &uploaded,
        ));
    }

    let cleanup_warning = journal.cleanup().err().map(|error| {
        format!("The PR body was verified, but the recovery journal could not be removed: {error}")
    });
    let patch_warning = patch_result.err().map(|error| {
        format!("The PATCH command reported an error, but the verification read found the exact managed entry: {error}")
    });
    Ok(RunOutput {
        pull_request_url: pull_request.url,
        markdown: change.markdown,
        warning: join_warnings(patch_warning, cleanup_warning),
    })
}

fn ambiguous_upload_error(
    error: UploadError,
    journal: &RecoveryJournal,
    journal_error: Option<String>,
) -> AppError {
    let journal_detail = journal_error
        .map(|journal_error| format!(" The journal could not be updated: {journal_error}"))
        .unwrap_or_default();
    AppError::runtime(format!(
        "{error}\nRecovery journal retained at `{}`.{journal_detail}",
        journal.path().display()
    ))
}

fn join_warnings(first: Option<String>, second: Option<String>) -> Option<String> {
    match (first, second) {
        (Some(first), Some(second)) => Some(format!("{first}\n{second}")),
        (Some(warning), None) | (None, Some(warning)) => Some(warning),
        (None, None) => None,
    }
}

fn recovery_error(
    message: impl Into<String>,
    journal: &RecoveryJournal,
    attachment: &UploadedAttachment,
) -> AppError {
    AppError::runtime(format!(
        "{}\nRecovery journal retained at `{}`. Ready-to-paste Markdown:\n{}",
        message.into(),
        journal.path().display(),
        markdown(&attachment.alt, &attachment.url)
    ))
}

fn markdown(alt: &str, url: &str) -> String {
    let escaped = alt
        .replace('\\', "\\\\")
        .replace('[', "\\[")
        .replace(']', "\\]");
    format!("![{escaped}]({url})")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::cli::AddConfig;
    use crate::github::{PullRequest, Repository, RepositorySlug};
    use crate::image::ValidatedImage;
    use sha2::{Digest, Sha256};
    use std::fs;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::path::{Path, PathBuf};
    use std::thread;
    use tempfile::tempdir;

    #[cfg(unix)]
    #[test]
    fn full_workflow_uploads_patches_and_is_idempotent() {
        let fixture = Fixture::new(true, false, "PUBLIC");
        let (endpoint, server) = upload_server();
        let uploader = UserAttachmentsClient::testing(&endpoint);
        let config = fixture.config();

        let first = add_image_to_pr(&config, &fixture.github, &uploader).expect("first run");
        assert_eq!(
            first.markdown,
            "![Settings](https://github.com/user-attachments/assets/test-asset)"
        );
        assert_eq!(first.warning, None);
        let request = server.join().expect("upload server");
        assert!(request.ends_with(&fixture.image_bytes));

        let second = add_image_to_pr(&config, &fixture.github, &uploader).expect("second run");
        assert_eq!(second.markdown, first.markdown);
        let log = fs::read_to_string(&fixture.log).expect("log");
        assert_eq!(log.matches("auth token --hostname github.com").count(), 1);
        assert_eq!(log.matches("--method PATCH").count(), 1);

        let body = fs::read_to_string(&fixture.body).expect("body");
        assert!(body.starts_with("Intro\n\n<!-- gh-pr-image:begin -->"));
        assert!(body.contains(&format!("gh-pr-image:sha256:{}", fixture.digest)));
    }

    #[cfg(unix)]
    #[test]
    fn unsupported_prs_fail_before_token_or_upload() {
        for (viewer_can_update, cross_repository, visibility, expected) in [
            (false, false, "PUBLIC", "cannot update this PR"),
            (true, true, "PUBLIC", "same-repository"),
            (true, false, "PRIVATE", "only public repositories"),
            (true, false, "INTERNAL", "only public repositories"),
        ] {
            let fixture = Fixture::new(viewer_can_update, cross_repository, visibility);
            let uploader = UserAttachmentsClient::testing("http://127.0.0.1:9/upload");
            let error = add_image_to_pr(&fixture.config(), &fixture.github, &uploader)
                .expect_err("preflight failure");
            assert!(error.to_string().contains(expected), "{error}");

            let log = fs::read_to_string(&fixture.log).expect("log");
            assert!(!log.contains("auth token"));
            assert!(!log.contains("--method PATCH"));
            assert_eq!(fs::read_to_string(&fixture.body).expect("body"), "Intro");
        }
    }

    #[cfg(unix)]
    #[test]
    fn invalid_local_inputs_fail_before_any_github_call() {
        let fixture = Fixture::new(true, false, "PUBLIC");
        let mut config = fixture.config();
        config.image = fixture.image.with_file_name("missing.png");
        let uploader = UserAttachmentsClient::testing("http://127.0.0.1:9/upload");

        let error = add_image_to_pr(&config, &fixture.github, &uploader)
            .expect_err("local validation failure");
        assert_eq!(error.kind(), ErrorKind::Usage);
        assert!(error.to_string().contains("Failed to inspect image"));
        assert_eq!(fs::read_to_string(&fixture.log).expect("log"), "");

        config.image = fixture.image.clone();
        config.alt = "Preview <!-- gh-pr-image:begin -->".to_string();
        let error = add_image_to_pr(&config, &fixture.github, &uploader)
            .expect_err("reserved marker failure");
        assert_eq!(error.kind(), ErrorKind::Usage);
        assert!(error.to_string().contains("reserved block markers"));
        assert_eq!(fs::read_to_string(&fixture.log).expect("log"), "");
    }

    #[cfg(unix)]
    #[test]
    fn journal_failures_preserve_upload_outcomes_and_known_urls() {
        let repository = Repository {
            slug: RepositorySlug::parse("owner/repo").expect("repo"),
            database_id: 7,
        };
        let pull_request = PullRequest {
            number: 42,
            url: "https://github.com/owner/repo/pull/42".to_string(),
            body: String::new(),
        };
        let image = ValidatedImage {
            name: "screen.png".to_string(),
            media_type: "image/png",
            bytes: b"png".to_vec(),
            sha256: "a".repeat(64),
            alt: "Settings".to_string(),
        };
        let uploaded = UploadedAttachment {
            sha256: image.sha256.clone(),
            name: image.name.clone(),
            media_type: image.media_type.to_string(),
            alt: image.alt.clone(),
            url: "https://github.com/user-attachments/assets/known-url".to_string(),
        };

        let uploaded_journal =
            RecoveryJournal::prepare(&repository, &pull_request, &image).expect("journal");
        let uploaded_path = uploaded_journal.path().to_path_buf();
        fs::remove_file(&uploaded_path).expect("remove journal");
        fs::create_dir(&uploaded_path).expect("block replacement");
        let persistence_error = uploaded_journal
            .record_uploaded(&repository, &pull_request, &uploaded)
            .expect_err("journal persistence failure");
        let error = recovery_error(
            format!("The upload succeeded, but journaling failed: {persistence_error}"),
            &uploaded_journal,
            &uploaded,
        );
        assert!(error.to_string().contains(&uploaded.url));
        assert!(error.to_string().contains("Ready-to-paste Markdown"));
        fs::remove_dir(uploaded_path).expect("cleanup directory");

        let ambiguous_journal =
            RecoveryJournal::prepare(&repository, &pull_request, &image).expect("journal");
        let ambiguous_path = ambiguous_journal.path().to_path_buf();
        fs::remove_file(&ambiguous_path).expect("remove journal");
        fs::create_dir(&ambiguous_path).expect("block replacement");
        let persistence_error = ambiguous_journal
            .record_ambiguous(&repository, &pull_request, &image)
            .expect_err("journal ambiguity failure");
        let error = ambiguous_upload_error(
            UploadError::Ambiguous("transport failure"),
            &ambiguous_journal,
            Some(persistence_error.clone()),
        );
        assert!(error.to_string().contains("outcome is ambiguous"));
        assert!(error.to_string().contains(&persistence_error));
        fs::remove_dir(ambiguous_path).expect("cleanup directory");
    }

    #[cfg(unix)]
    struct Fixture {
        _directory: tempfile::TempDir,
        github: GhClient,
        image: PathBuf,
        body: PathBuf,
        log: PathBuf,
        digest: String,
        image_bytes: Vec<u8>,
    }

    #[cfg(unix)]
    impl Fixture {
        fn new(viewer_can_update: bool, cross_repository: bool, visibility: &str) -> Self {
            use std::os::unix::fs::PermissionsExt;

            let directory = tempdir().expect("tempdir");
            let image = directory.path().join("screen.png");
            let body = directory.path().join("body.txt");
            let log = directory.path().join("calls.log");
            let program = directory.path().join("gh");
            let image_bytes = b"\x89PNG\r\n\x1a\ntest-image".to_vec();
            let digest = format!("{:x}", Sha256::digest(&image_bytes));
            fs::write(&image, &image_bytes).expect("image");
            fs::write(&body, "Intro").expect("body");
            fs::write(&log, "").expect("log");

            let script =
                fake_gh_script(&body, &log, viewer_can_update, cross_repository, visibility);
            fs::write(&program, script).expect("script");
            let mut permissions = fs::metadata(&program).expect("metadata").permissions();
            permissions.set_mode(0o700);
            fs::set_permissions(&program, permissions).expect("permissions");

            Self {
                github: GhClient::new(&program),
                _directory: directory,
                image,
                body,
                log,
                digest,
                image_bytes,
            }
        }

        fn config(&self) -> AddConfig {
            AddConfig {
                image: self.image.clone(),
                alt: "Settings".to_string(),
                repository: Some(RepositorySlug::parse("owner/repo").expect("repo")),
                pull_request: Some("https://github.com/owner/repo/pull/42".to_string()),
            }
        }
    }

    #[cfg(unix)]
    fn fake_gh_script(
        body: &Path,
        log: &Path,
        viewer_can_update: bool,
        cross_repository: bool,
        visibility: &str,
    ) -> String {
        assert!(!body.to_string_lossy().contains('\''));
        assert!(!log.to_string_lossy().contains('\''));
        format!(
            r#"#!/bin/sh
set -eu
BODY='{body}'
LOG='{log}'
printf '%s\n' "$*" >> "$LOG"

if [ "$GH_HOST" != "github.com" ]; then
  printf 'gh command was not pinned to github.com: %s\n' "$GH_HOST" >&2
  exit 1
fi

if [ "$1" = "api" ]; then
  HOST_PINNED=false
  PREVIOUS=''
  for ARGUMENT in "$@"; do
    if [ "$PREVIOUS" = "--hostname" ] && [ "$ARGUMENT" = "github.com" ]; then
      HOST_PINNED=true
    fi
    PREVIOUS=$ARGUMENT
  done
  if [ "$HOST_PINNED" != true ]; then
    printf 'api call was not pinned to github.com: %s\n' "$*" >&2
    exit 1
  fi
fi

if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  BODY_JSON=$(jq -Rs . < "$BODY")
  printf '{{"data":{{"repository":{{"visibility":"{visibility}","pullRequest":{{"body":%s,"isCrossRepository":{cross_repository},"number":42,"url":"https://github.com/owner/repo/pull/42","viewerCanUpdate":{viewer_can_update},"viewerCannotUpdateReasons":["NOT_AUTHOR"]}}}}}}}}\n' "$BODY_JSON"
elif [ "$1" = "api" ] && [ "$2" = "repos/owner/repo" ]; then
  printf '{{"id":123}}\n'
elif [ "$1" = "auth" ] && [ "$2" = "token" ]; then
  printf 'test-token\n'
elif [ "$1" = "api" ] && [ "$2" = "repos/owner/repo/pulls/42" ] && [ "${{3:-}}" = "--method" ]; then
  jq -r .body > "$BODY"
  printf '{{}}\n'
elif [ "$1" = "api" ] && [ "$2" = "repos/owner/repo/pulls/42" ]; then
  jq -Rs '{{body: .}}' "$BODY"
else
  printf 'unexpected fake gh command: %s\n' "$*" >&2
  exit 1
fi
"#,
            body = body.display(),
            log = log.display(),
            visibility = visibility,
        )
    }

    #[cfg(unix)]
    fn upload_server() -> (String, thread::JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("listen");
        let address = listener.local_addr().expect("address");
        let handle = thread::spawn(move || {
            let (mut stream, _) = listener.accept().expect("accept");
            let mut request = Vec::new();
            let mut buffer = [0u8; 4096];
            loop {
                let count = stream.read(&mut buffer).expect("read");
                if count == 0 {
                    break;
                }
                request.extend_from_slice(&buffer[..count]);
                if let Some(header_end) =
                    request.windows(4).position(|window| window == b"\r\n\r\n")
                {
                    let headers = String::from_utf8_lossy(&request[..header_end]);
                    let content_length = headers
                        .lines()
                        .find_map(|line| {
                            line.to_ascii_lowercase()
                                .strip_prefix("content-length: ")
                                .and_then(|value| value.parse::<usize>().ok())
                        })
                        .unwrap_or(0);
                    if request.len() >= header_end + 4 + content_length {
                        break;
                    }
                }
            }
            let body = r#"{"url":"https://github.com/user-attachments/assets/test-asset"}"#;
            let response = format!(
                "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            stream.write_all(response.as_bytes()).expect("response");
            request
        });
        (format!("http://{address}/user-attachments/assets"), handle)
    }
}
