use std::collections::HashSet;

const BEGIN_MARKER: &str = "<!-- gh-pr-image:begin -->";
const END_MARKER: &str = "<!-- gh-pr-image:end -->";
const HEADING: &str = "## Screenshots";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BodyAttachment {
    pub sha256: String,
    pub alt: String,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BodyChange {
    pub body: String,
    pub markdown: String,
    pub already_present: bool,
}

pub fn find_attachment(body: &str, sha256: &str) -> Result<Option<BodyAttachment>, String> {
    let managed = parse_managed_body(body)?;
    Ok(managed.and_then(|block| {
        block
            .entries
            .into_iter()
            .find(|entry| entry.sha256 == sha256)
    }))
}

pub fn add_attachment(body: &str, attachment: BodyAttachment) -> Result<BodyChange, String> {
    validate_digest(&attachment.sha256)?;
    validate_alt(&attachment.alt)?;
    validate_attachment_url(&attachment.url)?;

    let markdown = markdown_for(&attachment);
    if let Some(mut managed) = parse_managed_body(body)? {
        if let Some(existing) = managed
            .entries
            .iter()
            .find(|entry| entry.sha256 == attachment.sha256)
        {
            return Ok(BodyChange {
                body: body.to_string(),
                markdown: markdown_for(existing),
                already_present: true,
            });
        }

        managed.entries.push(attachment);
        let mut updated = String::with_capacity(body.len() + markdown.len() + 128);
        updated.push_str(&body[..managed.begin]);
        updated.push_str(&render_block(&managed.entries));
        updated.push_str(&body[managed.end..]);
        return Ok(BodyChange {
            body: updated,
            markdown,
            already_present: false,
        });
    }

    let mut updated = body.to_string();
    if !updated.is_empty() {
        if updated.ends_with("\n\n") {
        } else if updated.ends_with('\n') {
            updated.push('\n');
        } else {
            updated.push_str("\n\n");
        }
    }
    updated.push_str(&render_block(&[attachment]));
    Ok(BodyChange {
        body: updated,
        markdown,
        already_present: false,
    })
}

pub fn validate_attachment_url(value: &str) -> Result<(), String> {
    let uri: ureq::http::Uri = value
        .parse()
        .map_err(|_| "Attachment URL is not a valid URI.".to_string())?;
    if uri.scheme_str() != Some("https")
        || uri.authority().map(|value| value.as_str()) != Some("github.com")
    {
        return Err(
            "Attachment URL must use https://github.com without userinfo or a port.".to_string(),
        );
    }
    if uri
        .path_and_query()
        .and_then(|path_and_query| path_and_query.query())
        .is_some()
        || value.contains('#')
    {
        return Err("Attachment URL must not contain a query or fragment.".to_string());
    }

    let path = uri.path();
    let prefix = "/user-attachments/assets/";
    let identifier = path
        .strip_prefix(prefix)
        .filter(|identifier| !identifier.is_empty())
        .ok_or_else(|| "Attachment URL has an unexpected path.".to_string())?;
    if identifier.contains('/')
        || identifier.contains('%')
        || identifier == "."
        || identifier == ".."
        || identifier.len() > 200
        || !identifier
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
    {
        return Err("Attachment URL has an invalid asset identifier.".to_string());
    }
    Ok(())
}

fn parse_managed_body(body: &str) -> Result<Option<ManagedBlock>, String> {
    let begins: Vec<_> = body
        .match_indices(BEGIN_MARKER)
        .map(|(index, _)| index)
        .collect();
    let ends: Vec<_> = body
        .match_indices(END_MARKER)
        .map(|(index, _)| index)
        .collect();
    if begins.is_empty() && ends.is_empty() {
        return Ok(None);
    }
    if begins.len() != 1 || ends.len() != 1 || begins[0] >= ends[0] {
        return Err("PR body has malformed or duplicated gh-pr-image markers.".to_string());
    }

    let end = ends[0] + END_MARKER.len();
    let block = &body[begins[0]..end];
    let lines: Vec<&str> = block.lines().collect();
    if lines.len() < 3
        || lines[0] != BEGIN_MARKER
        || lines[1] != HEADING
        || lines.last() != Some(&END_MARKER)
    {
        return Err("PR body has a malformed gh-pr-image block.".to_string());
    }

    let mut entries = Vec::new();
    let mut seen = HashSet::new();
    let mut index = 2usize;
    while index < lines.len() - 1 {
        if lines[index].is_empty() {
            index += 1;
            continue;
        }
        let digest = lines[index]
            .strip_prefix("<!-- gh-pr-image:sha256:")
            .and_then(|value| value.strip_suffix(" -->"))
            .ok_or_else(|| "PR body has a malformed gh-pr-image entry marker.".to_string())?;
        validate_digest(digest)?;
        if !seen.insert(digest.to_string()) {
            return Err("PR body contains a duplicated gh-pr-image digest.".to_string());
        }
        let markdown = lines
            .get(index + 1)
            .ok_or_else(|| "PR body has an incomplete gh-pr-image entry.".to_string())?;
        let closing = lines
            .get(index + 2)
            .ok_or_else(|| "PR body has an incomplete gh-pr-image entry.".to_string())?;
        if *closing != format!("<!-- /gh-pr-image:sha256:{digest} -->") {
            return Err("PR body has a mismatched gh-pr-image entry marker.".to_string());
        }
        let (alt, url) = parse_markdown(markdown)?;
        validate_attachment_url(&url)?;
        entries.push(BodyAttachment {
            sha256: digest.to_string(),
            alt,
            url,
        });
        index += 3;
    }

    Ok(Some(ManagedBlock {
        begin: begins[0],
        end,
        entries,
    }))
}

fn parse_markdown(value: &str) -> Result<(String, String), String> {
    let rest = value
        .strip_prefix("![")
        .and_then(|value| value.strip_suffix(')'))
        .ok_or_else(|| "PR body has malformed gh-pr-image Markdown.".to_string())?;
    let separator = rest
        .rfind("](")
        .ok_or_else(|| "PR body has malformed gh-pr-image Markdown.".to_string())?;
    let alt = unescape_alt(&rest[..separator])?;
    let url = rest[separator + 2..].to_string();
    Ok((alt, url))
}

fn markdown_for(attachment: &BodyAttachment) -> String {
    format!("![{}]({})", escape_alt(&attachment.alt), attachment.url)
}

fn render_block(entries: &[BodyAttachment]) -> String {
    let mut block = format!("{BEGIN_MARKER}\n{HEADING}\n");
    for entry in entries {
        block.push('\n');
        block.push_str(&format!(
            "<!-- gh-pr-image:sha256:{} -->\n{}\n<!-- /gh-pr-image:sha256:{} -->\n",
            entry.sha256,
            markdown_for(entry),
            entry.sha256
        ));
    }
    block.push_str(END_MARKER);
    block
}

fn validate_digest(value: &str) -> Result<(), String> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err("gh-pr-image digest must be 64 lowercase hexadecimal characters.".to_string());
    }
    Ok(())
}

pub(crate) fn validate_alt(value: &str) -> Result<(), String> {
    if value.trim().is_empty() || value.chars().any(char::is_control) {
        return Err("gh-pr-image alt text must be a non-empty single line.".to_string());
    }
    if value.contains(BEGIN_MARKER) || value.contains(END_MARKER) {
        return Err("gh-pr-image alt text must not contain reserved block markers.".to_string());
    }
    Ok(())
}

fn escape_alt(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('[', "\\[")
        .replace(']', "\\]")
}

fn unescape_alt(value: &str) -> Result<String, String> {
    let mut output = String::new();
    let mut chars = value.chars();
    while let Some(character) = chars.next() {
        if character != '\\' {
            output.push(character);
            continue;
        }
        let escaped = chars
            .next()
            .ok_or_else(|| "PR body has malformed escaped alt text.".to_string())?;
        if !matches!(escaped, '\\' | '[' | ']') {
            return Err("PR body has unsupported escaped alt text.".to_string());
        }
        output.push(escaped);
    }
    validate_alt(&output)?;
    Ok(output)
}

struct ManagedBlock {
    begin: usize,
    end: usize,
    entries: Vec<BodyAttachment>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn attachment(digest: char) -> BodyAttachment {
        BodyAttachment {
            sha256: digest.to_string().repeat(64),
            alt: "Settings [dialog]".to_string(),
            url: "https://github.com/user-attachments/assets/abc-123".to_string(),
        }
    }

    #[test]
    fn appends_and_reuses_a_managed_attachment() {
        let first = add_attachment("Intro", attachment('a')).expect("first");
        assert!(first
            .body
            .starts_with("Intro\n\n<!-- gh-pr-image:begin -->"));
        assert!(first.body.contains("![Settings \\[dialog\\]]"));

        let second = add_attachment(&first.body, attachment('a')).expect("second");
        assert!(second.already_present);
        assert_eq!(second.body, first.body);
    }

    #[test]
    fn rejects_reserved_block_markers_in_alt_text() {
        for marker in [BEGIN_MARKER, END_MARKER] {
            let mut candidate = attachment('a');
            candidate.alt = format!("Preview {marker}");

            let error = add_attachment("Intro", candidate).expect_err(marker);
            assert!(error.contains("reserved block markers"), "{error}");
        }
    }

    #[test]
    fn preserves_markdown_punctuation_in_alt_text() {
        let mut candidate = attachment('a');
        candidate.alt = "Settings [dialog] (*dark* mode)".to_string();

        let change = add_attachment("Intro", candidate.clone()).expect("add attachment");
        let parsed = find_attachment(&change.body, &candidate.sha256)
            .expect("parse managed block")
            .expect("find attachment");

        assert_eq!(parsed.alt, candidate.alt);
    }

    #[test]
    fn preserves_text_outside_an_existing_block() {
        let first = add_attachment("Before\n\nAfter", attachment('a')).expect("first");
        let with_suffix = format!("{}\n\nSuffix", first.body);
        let second = add_attachment(&with_suffix, attachment('b')).expect("second");
        assert!(second.body.starts_with("Before\n\nAfter\n\n"));
        assert!(second.body.ends_with("\n\nSuffix"));
    }

    #[test]
    fn rejects_hostile_existing_urls_and_duplicate_markers() {
        let body = format!(
            "{BEGIN_MARKER}\n{HEADING}\n\n<!-- gh-pr-image:sha256:{} -->\n![Alt](https://evil.example/user-attachments/assets/id)\n<!-- /gh-pr-image:sha256:{} -->\n{END_MARKER}",
            "a".repeat(64),
            "a".repeat(64)
        );
        assert!(find_attachment(&body, &"a".repeat(64))
            .expect_err("hostile URL")
            .contains("github.com"));

        let duplicated = format!("{BEGIN_MARKER}\n{BEGIN_MARKER}\n{END_MARKER}");
        assert!(find_attachment(&duplicated, &"a".repeat(64))
            .expect_err("duplicate")
            .contains("duplicated"));
    }

    #[test]
    fn strictly_validates_native_attachment_urls() {
        assert!(
            validate_attachment_url("https://github.com/user-attachments/assets/abc_123-def")
                .is_ok()
        );
        for invalid in [
            "http://github.com/user-attachments/assets/id",
            "https://user@github.com/user-attachments/assets/id",
            "https://github.com:443/user-attachments/assets/id",
            "https://github.com/user-attachments/assets/id/more",
            "https://github.com/user-attachments/assets/%2Fetc",
            "https://github.com/user-attachments/assets/id?download=1",
        ] {
            assert!(validate_attachment_url(invalid).is_err(), "{invalid}");
        }
    }
}
