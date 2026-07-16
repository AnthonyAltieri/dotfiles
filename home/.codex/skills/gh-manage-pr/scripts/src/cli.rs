use crate::body::validate_alt as validate_body_alt;
use crate::github::RepositorySlug;
use std::path::PathBuf;

pub const HELP: &str = "Usage: gh-pr-image add <image> --alt <text> [--pr <number|url|branch>] [-R <owner/repo>]\n\nUploads one PNG, JPEG, or GIF to a same-repository GitHub pull request and adds it to the managed Screenshots section.";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AddConfig {
    pub image: PathBuf,
    pub alt: String,
    pub repository: Option<RepositorySlug>,
    pub pull_request: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParsedArgs {
    Add(AddConfig),
    Help,
}

pub fn parse_args(args: Vec<String>) -> Result<ParsedArgs, String> {
    if args.is_empty() || args.iter().any(|value| value == "--help" || value == "-h") {
        return Ok(ParsedArgs::Help);
    }
    if args.first().map(String::as_str) != Some("add") {
        return Err("Expected the `add` subcommand.".to_string());
    }

    let mut image = None;
    let mut alt = None;
    let mut repository = None;
    let mut pull_request = None;
    let mut positional_only = false;
    let mut index = 1usize;

    while index < args.len() {
        let argument = &args[index];
        if !positional_only {
            match argument.as_str() {
                "--" => {
                    positional_only = true;
                    index += 1;
                    continue;
                }
                "--alt" => {
                    let value = option_value(&args, index, "--alt")?;
                    if alt.replace(validate_alt(value)?).is_some() {
                        return Err("Pass --alt only once.".to_string());
                    }
                    index += 2;
                    continue;
                }
                "-R" | "--repo" => {
                    let value = option_value(&args, index, argument)?;
                    if repository.replace(RepositorySlug::parse(value)?).is_some() {
                        return Err("Pass -R/--repo only once.".to_string());
                    }
                    index += 2;
                    continue;
                }
                "--pr" => {
                    let value = option_value(&args, index, "--pr")?;
                    if value.is_empty() || value.chars().any(char::is_control) {
                        return Err("--pr must be a non-empty single-line value.".to_string());
                    }
                    if pull_request.replace(value.to_string()).is_some() {
                        return Err("Pass --pr only once.".to_string());
                    }
                    index += 2;
                    continue;
                }
                value if value.starts_with('-') => {
                    return Err(format!("Unknown option: {value}"));
                }
                _ => {}
            }
        }

        if image.replace(PathBuf::from(argument)).is_some() {
            return Err("Pass exactly one image.".to_string());
        }
        index += 1;
    }

    Ok(ParsedArgs::Add(AddConfig {
        image: image.ok_or_else(|| "An image path is required.".to_string())?,
        alt: alt.ok_or_else(|| "--alt is required.".to_string())?,
        repository,
        pull_request,
    }))
}

fn option_value<'a>(args: &'a [String], index: usize, option: &str) -> Result<&'a str, String> {
    args.get(index + 1)
        .map(String::as_str)
        .ok_or_else(|| format!("{option} requires a value."))
}

fn validate_alt(value: &str) -> Result<String, String> {
    if value.trim().is_empty() {
        return Err("--alt must not be empty.".to_string());
    }
    if value.chars().any(char::is_control) {
        return Err("--alt must be a single line without control characters.".to_string());
    }
    validate_body_alt(value)?;
    Ok(value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_add_command() {
        let parsed = parse_args(vec![
            "add".to_string(),
            "screen shot.png".to_string(),
            "--alt".to_string(),
            "Settings dialog".to_string(),
            "--pr".to_string(),
            "123".to_string(),
            "-R".to_string(),
            "owner/repo".to_string(),
        ])
        .expect("arguments");

        assert_eq!(
            parsed,
            ParsedArgs::Add(AddConfig {
                image: PathBuf::from("screen shot.png"),
                alt: "Settings dialog".to_string(),
                repository: Some(RepositorySlug::parse("owner/repo").expect("repo")),
                pull_request: Some("123".to_string()),
            })
        );
    }

    #[test]
    fn rejects_missing_alt_and_multiple_images() {
        let missing =
            parse_args(vec!["add".to_string(), "shot.png".to_string()]).expect_err("missing alt");
        assert_eq!(missing, "--alt is required.");

        let multiple = parse_args(vec![
            "add".to_string(),
            "one.png".to_string(),
            "two.png".to_string(),
            "--alt".to_string(),
            "Screenshot".to_string(),
        ])
        .expect_err("multiple images");
        assert_eq!(multiple, "Pass exactly one image.");
    }

    #[test]
    fn rejects_multiline_alt_text() {
        let error = parse_args(vec![
            "add".to_string(),
            "shot.png".to_string(),
            "--alt".to_string(),
            "line one\nline two".to_string(),
        ])
        .expect_err("multiline alt");
        assert!(error.contains("single line"));
    }

    #[test]
    fn rejects_reserved_block_markers_in_alt_text() {
        for marker in ["<!-- gh-pr-image:begin -->", "<!-- gh-pr-image:end -->"] {
            let error = parse_args(vec![
                "add".to_string(),
                "shot.png".to_string(),
                "--alt".to_string(),
                format!("Preview {marker}"),
            ])
            .expect_err(marker);
            assert!(error.contains("reserved block markers"), "{error}");
        }
    }
}
