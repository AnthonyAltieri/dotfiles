use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Take};
use std::path::Path;

pub const MAX_IMAGE_BYTES: usize = 10_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidatedImage {
    pub name: String,
    pub media_type: &'static str,
    pub bytes: Vec<u8>,
    pub sha256: String,
    pub alt: String,
}

pub fn load_image(path: &Path, alt: &str) -> Result<ValidatedImage, String> {
    let path_metadata = fs::symlink_metadata(path)
        .map_err(|error| format!("Failed to inspect image `{}`: {error}", path.display()))?;
    if path_metadata.file_type().is_symlink() || !path_metadata.is_file() {
        return Err(format!(
            "Image `{}` must be a regular, non-symlink file.",
            path.display()
        ));
    }
    if path_metadata.len() > MAX_IMAGE_BYTES as u64 {
        return Err(format!(
            "Image `{}` exceeds the 10 MB limit.",
            path.display()
        ));
    }

    let name = path
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.is_empty() && !value.chars().any(char::is_control))
        .ok_or_else(|| "Image filename must be valid single-line UTF-8.".to_string())?
        .to_string();

    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NOFOLLOW);
    }
    let file = options
        .open(path)
        .map_err(|error| format!("Failed to open image `{}`: {error}", path.display()))?;
    if !file
        .metadata()
        .map_err(|error| format!("Failed to inspect open image: {error}"))?
        .is_file()
    {
        return Err("Image changed while it was being validated.".to_string());
    }

    let mut bytes = Vec::with_capacity(path_metadata.len() as usize);
    let mut limited: Take<File> = file.take((MAX_IMAGE_BYTES + 1) as u64);
    limited
        .read_to_end(&mut bytes)
        .map_err(|error| format!("Failed to read image `{}`: {error}", path.display()))?;
    if bytes.len() > MAX_IMAGE_BYTES {
        return Err(format!(
            "Image `{}` exceeds the 10 MB limit.",
            path.display()
        ));
    }
    if bytes.is_empty() {
        return Err("Image must not be empty.".to_string());
    }

    let extension = path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .ok_or_else(|| "Image must have a .png, .jpg, .jpeg, or .gif extension.".to_string())?;
    let media_type = detect_media_type(&bytes)
        .ok_or_else(|| "Image signature is not a supported PNG, JPEG, or GIF.".to_string())?;
    let extension_matches = matches!(
        (extension.as_str(), media_type),
        ("png", "image/png")
            | ("jpg", "image/jpeg")
            | ("jpeg", "image/jpeg")
            | ("gif", "image/gif")
    );
    if !extension_matches {
        return Err("Image extension does not match its file signature.".to_string());
    }

    let sha256 = format!("{:x}", Sha256::digest(&bytes));
    Ok(ValidatedImage {
        name,
        media_type,
        bytes,
        sha256,
        alt: alt.to_string(),
    })
}

fn detect_media_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some("image/png");
    }
    if bytes.starts_with(&[0xff, 0xd8, 0xff]) && bytes.ends_with(&[0xff, 0xd9]) {
        return Some("image/jpeg");
    }
    if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        return Some("image/gif");
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::tempdir;

    #[test]
    fn validates_png_and_hashes_exact_bytes() {
        let directory = tempdir().expect("tempdir");
        let path = directory.path().join("screen.png");
        let bytes = b"\x89PNG\r\n\x1a\ncontent";
        fs::write(&path, bytes).expect("write png");

        let image = load_image(&path, "Settings").expect("image");
        assert_eq!(image.media_type, "image/png");
        assert_eq!(image.bytes, bytes);
        assert_eq!(image.sha256, format!("{:x}", Sha256::digest(bytes)));
    }

    #[test]
    fn rejects_mismatched_extension() {
        let directory = tempdir().expect("tempdir");
        let path = directory.path().join("screen.jpg");
        fs::write(&path, b"\x89PNG\r\n\x1a\ncontent").expect("write png");

        let error = load_image(&path, "Settings").expect_err("mismatch");
        assert!(error.contains("extension"));
    }

    #[test]
    fn rejects_files_over_the_limit_without_reading_them_all() {
        let directory = tempdir().expect("tempdir");
        let path = directory.path().join("large.png");
        let mut file = File::create(&path).expect("create");
        file.write_all(b"\x89PNG\r\n\x1a\n").expect("header");
        file.set_len((MAX_IMAGE_BYTES + 1) as u64).expect("extend");

        let error = load_image(&path, "Large").expect_err("too large");
        assert!(error.contains("10 MB"));
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symlinks() {
        use std::os::unix::fs::symlink;

        let directory = tempdir().expect("tempdir");
        let target = directory.path().join("target.png");
        let link = directory.path().join("link.png");
        fs::write(&target, b"\x89PNG\r\n\x1a\ncontent").expect("write");
        symlink(&target, &link).expect("symlink");

        let error = load_image(&link, "Link").expect_err("symlink");
        assert!(error.contains("non-symlink"));
    }
}
