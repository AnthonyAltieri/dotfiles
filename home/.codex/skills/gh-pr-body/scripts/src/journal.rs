use crate::github::{PullRequest, Repository};
use crate::image::ValidatedImage;
use crate::UploadedAttachment;
use serde::Serialize;
use std::fs;
use std::io::{Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use tempfile::{Builder, NamedTempFile};

pub struct RecoveryJournal {
    path: PathBuf,
}

impl RecoveryJournal {
    pub fn prepare(
        repository: &Repository,
        pull_request: &PullRequest,
        image: &ValidatedImage,
    ) -> Result<Self, String> {
        Self::prepare_with_sync(repository, pull_request, image, sync_parent_directory)
    }

    fn prepare_with_sync(
        repository: &Repository,
        pull_request: &PullRequest,
        image: &ValidatedImage,
        sync_parent: impl FnOnce(&Path) -> Result<(), String>,
    ) -> Result<Self, String> {
        let mut file = Builder::new()
            .prefix("gh-pr-image-recovery-")
            .suffix(".json")
            .tempfile_in(std::env::temp_dir())
            .map_err(|error| format!("Failed to create recovery journal: {error}"))?;
        let path = file.path().to_path_buf();
        write_json(
            &mut file,
            &JournalRecord {
                schema_version: 1,
                repository: repository.slug.as_string(),
                pull_request: pull_request.number,
                status: "upload_pending_or_unknown",
                attachment: Some(JournalAttachment::from_image(image)),
                note: Some(
                    "The journal was written before upload dispatch; if the process stopped, the remote outcome may be unknown.",
                ),
            },
        )?;
        file.keep()
            .map_err(|error| format!("Failed to retain recovery journal: {}", error.error))?;
        sync_parent(&path)?;
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn record_uploaded(
        &self,
        repository: &Repository,
        pull_request: &PullRequest,
        attachment: &UploadedAttachment,
    ) -> Result<(), String> {
        self.replace(&JournalRecord {
            schema_version: 1,
            repository: repository.slug.as_string(),
            pull_request: pull_request.number,
            status: "uploaded",
            attachment: Some(JournalAttachment::from_uploaded(attachment)),
            note: None,
        })
    }

    pub fn record_ambiguous(
        &self,
        repository: &Repository,
        pull_request: &PullRequest,
        image: &ValidatedImage,
    ) -> Result<(), String> {
        self.replace(&JournalRecord {
            schema_version: 1,
            repository: repository.slug.as_string(),
            pull_request: pull_request.number,
            status: "upload_outcome_ambiguous",
            attachment: Some(JournalAttachment::from_image(image)),
            note: Some(
                "The upload may have succeeded, but no validated attachment URL was received.",
            ),
        })
    }

    pub fn cleanup(&self) -> Result<(), String> {
        match fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(format!(
                "Failed to remove recovery journal `{}`: {error}",
                self.path.display()
            )),
        }
    }

    fn replace(&self, record: &JournalRecord<'_>) -> Result<(), String> {
        self.replace_with_sync(record, sync_parent_directory)
    }

    fn replace_with_sync(
        &self,
        record: &JournalRecord<'_>,
        sync_parent: impl FnOnce(&Path) -> Result<(), String>,
    ) -> Result<(), String> {
        let parent = self
            .path
            .parent()
            .ok_or_else(|| "Recovery journal has no parent directory.".to_string())?;
        let mut replacement = Builder::new()
            .prefix(".gh-pr-image-recovery-")
            .tempfile_in(parent)
            .map_err(|error| format!("Failed to update recovery journal: {error}"))?;
        write_json(&mut replacement, record)?;
        replacement
            .persist(&self.path)
            .map_err(|error| format!("Failed to persist recovery journal: {}", error.error))?;
        sync_parent(&self.path)
    }
}

#[derive(Serialize)]
struct JournalRecord<'a> {
    schema_version: u32,
    repository: String,
    pull_request: u64,
    status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    attachment: Option<JournalAttachment<'a>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<&'static str>,
}

#[derive(Serialize)]
struct JournalAttachment<'a> {
    sha256: &'a str,
    name: &'a str,
    media_type: &'a str,
    alt: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    url: Option<&'a str>,
}

impl<'a> JournalAttachment<'a> {
    fn from_image(image: &'a ValidatedImage) -> Self {
        Self {
            sha256: &image.sha256,
            name: &image.name,
            media_type: image.media_type,
            alt: &image.alt,
            url: None,
        }
    }

    fn from_uploaded(attachment: &'a UploadedAttachment) -> Self {
        Self {
            sha256: &attachment.sha256,
            name: &attachment.name,
            media_type: &attachment.media_type,
            alt: &attachment.alt,
            url: Some(&attachment.url),
        }
    }
}

fn write_json(file: &mut NamedTempFile, record: &JournalRecord<'_>) -> Result<(), String> {
    file.as_file_mut()
        .set_len(0)
        .map_err(|error| format!("Failed to truncate recovery journal: {error}"))?;
    file.seek(SeekFrom::Start(0))
        .map_err(|error| format!("Failed to seek recovery journal: {error}"))?;
    serde_json::to_writer_pretty(&mut *file, record)
        .map_err(|error| format!("Failed to serialize recovery journal: {error}"))?;
    file.write_all(b"\n")
        .map_err(|error| format!("Failed to write recovery journal: {error}"))?;
    file.flush()
        .map_err(|error| format!("Failed to flush recovery journal: {error}"))?;
    file.as_file()
        .sync_all()
        .map_err(|error| format!("Failed to sync recovery journal: {error}"))
}

fn sync_parent_directory(path: &Path) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| "Recovery journal has no parent directory.".to_string())?;
    let directory = fs::File::open(parent).map_err(|error| {
        format!(
            "Failed to open recovery journal directory `{}`: {error}",
            parent.display()
        )
    })?;
    directory.sync_all().map_err(|error| {
        format!(
            "Failed to sync recovery journal directory `{}`: {error}",
            parent.display()
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::github::RepositorySlug;
    use serde_json::Value;
    use std::cell::Cell;

    fn context() -> (Repository, PullRequest, ValidatedImage) {
        (
            Repository {
                slug: RepositorySlug::parse("owner/repo").expect("repo"),
                database_id: 7,
            },
            PullRequest {
                number: 42,
                url: "https://github.com/owner/repo/pull/42".to_string(),
                body: String::new(),
            },
            ValidatedImage {
                name: "screen.png".to_string(),
                media_type: "image/png",
                bytes: b"png".to_vec(),
                sha256: "a".repeat(64),
                alt: "Settings".to_string(),
            },
        )
    }

    #[test]
    fn persists_uploaded_attachment_and_cleans_up() {
        let (repository, pull_request, image) = context();
        let journal =
            RecoveryJournal::prepare(&repository, &pull_request, &image).expect("journal");
        let pending: Value =
            serde_json::from_slice(&fs::read(journal.path()).expect("read")).expect("json");
        assert_eq!(
            pending.pointer("/status").and_then(Value::as_str),
            Some("upload_pending_or_unknown")
        );
        assert_eq!(
            pending
                .pointer("/attachment/sha256")
                .and_then(Value::as_str),
            Some(image.sha256.as_str())
        );
        let attachment = UploadedAttachment {
            sha256: "a".repeat(64),
            name: "screen.png".to_string(),
            media_type: "image/png".to_string(),
            alt: "Settings".to_string(),
            url: "https://github.com/user-attachments/assets/abc".to_string(),
        };
        journal
            .record_uploaded(&repository, &pull_request, &attachment)
            .expect("record");

        let value: Value =
            serde_json::from_slice(&fs::read(journal.path()).expect("read")).expect("json");
        assert_eq!(
            value.pointer("/status").and_then(Value::as_str),
            Some("uploaded")
        );
        assert_eq!(
            value.pointer("/attachment/url").and_then(Value::as_str),
            Some(attachment.url.as_str())
        );

        journal.cleanup().expect("cleanup");
        assert!(!journal.path().exists());
    }

    #[test]
    fn syncs_parent_after_retaining_and_replacing_journal() {
        let (repository, pull_request, image) = context();
        let retain_syncs = Cell::new(0);
        let journal =
            RecoveryJournal::prepare_with_sync(&repository, &pull_request, &image, |path| {
                let value: Value = serde_json::from_slice(&fs::read(path).expect("read retained"))
                    .expect("retained json");
                assert_eq!(
                    value.pointer("/status").and_then(Value::as_str),
                    Some("upload_pending_or_unknown")
                );
                retain_syncs.set(retain_syncs.get() + 1);
                Ok(())
            })
            .expect("journal");
        assert_eq!(retain_syncs.get(), 1);

        let attachment = UploadedAttachment {
            sha256: "a".repeat(64),
            name: "screen.png".to_string(),
            media_type: "image/png".to_string(),
            alt: "Settings".to_string(),
            url: "https://github.com/user-attachments/assets/abc".to_string(),
        };
        let replacement_syncs = Cell::new(0);
        journal
            .replace_with_sync(
                &JournalRecord {
                    schema_version: 1,
                    repository: repository.slug.as_string(),
                    pull_request: pull_request.number,
                    status: "uploaded",
                    attachment: Some(JournalAttachment::from_uploaded(&attachment)),
                    note: None,
                },
                |path| {
                    let value: Value =
                        serde_json::from_slice(&fs::read(path).expect("read replacement"))
                            .expect("replacement json");
                    assert_eq!(
                        value.pointer("/attachment/url").and_then(Value::as_str),
                        Some(attachment.url.as_str())
                    );
                    replacement_syncs.set(replacement_syncs.get() + 1);
                    Ok(())
                },
            )
            .expect("replace");
        assert_eq!(replacement_syncs.get(), 1);

        journal.cleanup().expect("cleanup");
    }

    #[cfg(unix)]
    #[test]
    fn journal_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;

        let (repository, pull_request, image) = context();
        let journal =
            RecoveryJournal::prepare(&repository, &pull_request, &image).expect("journal");
        let mode = fs::metadata(journal.path())
            .expect("metadata")
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        journal.cleanup().expect("cleanup");
    }
}
