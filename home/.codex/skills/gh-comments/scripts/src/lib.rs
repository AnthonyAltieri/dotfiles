use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};

pub const ROBOT_PREFIX: &str = "🤖 ";

pub struct CommandOutput {
    pub status: i32,
    pub stdout: Vec<u8>,
    pub stderr: String,
}

pub fn ensure_gh_authenticated() -> Result<(), String> {
    let output = run_command("gh", &["auth", "status"], None)?;
    if output.status != 0 {
        return Err("run `gh auth login` to authenticate the GitHub CLI".to_string());
    }
    Ok(())
}

pub fn gh_graphql_json(query: &str, fields: &[(&str, &str)]) -> Result<Value, String> {
    let mut args = vec![
        "api".to_string(),
        "graphql".to_string(),
        "-F".to_string(),
        "query=@-".to_string(),
    ];

    for (name, value) in fields {
        args.push("-F".to_string());
        args.push(format!("{name}={value}"));
    }

    run_json_command(
        "gh",
        &args.iter().map(String::as_str).collect::<Vec<&str>>(),
        Some(query),
    )
}

pub fn run_json_command(
    program: &str,
    args: &[&str],
    stdin: Option<&str>,
) -> Result<Value, String> {
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

pub fn run_command(
    program: &str,
    args: &[&str],
    stdin: Option<&str>,
) -> Result<CommandOutput, String> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

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

pub fn ensure_robot_prefix(body: &str) -> Result<String, String> {
    let trimmed = body.trim();
    if trimmed.is_empty() {
        return Err("Comment body is empty.".to_string());
    }
    if trimmed.starts_with('🤖') {
        return Ok(trimmed.to_string());
    }
    Ok(format!("{ROBOT_PREFIX}{trimmed}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ensure_robot_prefix_adds_prefix_once() {
        assert_eq!(
            ensure_robot_prefix("Addressed in abc123").expect("prefixed"),
            "🤖 Addressed in abc123"
        );
        assert_eq!(
            ensure_robot_prefix("🤖 Already prefixed").expect("unchanged"),
            "🤖 Already prefixed"
        );
    }

    #[test]
    fn ensure_robot_prefix_rejects_empty_body() {
        let error = ensure_robot_prefix("   ").expect_err("empty");
        assert_eq!(error, "Comment body is empty.");
    }
}
