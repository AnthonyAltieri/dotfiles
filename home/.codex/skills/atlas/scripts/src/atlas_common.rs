use serde_json::Value;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

pub const ATLAS_APP_NAME: &str = "ChatGPT Atlas";

fn local_state_path() -> PathBuf {
    let mut path = PathBuf::from(env::var("HOME").unwrap_or_else(|_| "~".to_string()));
    path.push("Library");
    path.push("Application Support");
    path.push("com.openai.atlas");
    path.push("browser-data");
    path.push("host");
    path.push("Local State");
    path
}

pub fn detect_atlas_app_name() -> Result<String, String> {
    if is_app_installed(ATLAS_APP_NAME) {
        return Ok(ATLAS_APP_NAME.to_string());
    }
    Err("Could not find ChatGPT Atlas. Install the ChatGPT Atlas app.".to_string())
}

pub fn detect_tab_capable_app_name() -> Result<String, String> {
    let app_name = detect_atlas_app_name()?;
    if is_tab_capable(&app_name)? {
        Ok(app_name)
    } else {
        Err("ChatGPT Atlas is installed but does not appear to expose window/tab scripting.".to_string())
    }
}

pub fn tell_atlas(script_body: &str, app_name: Option<&str>) -> Result<String, String> {
    let target_app = app_name
        .map(|value| value.to_string())
        .unwrap_or(detect_atlas_app_name()?);
    let script = format!("tell application \"{target_app}\"\n{script_body}\nend tell");
    run_applescript(&script)
}

pub fn get_history_path() -> Result<PathBuf, String> {
    Ok(get_active_profile_path()?.join("History"))
}

pub fn get_bookmarks_path() -> Result<PathBuf, String> {
    Ok(get_active_profile_path()?.join("Bookmarks"))
}

pub fn copy_sqlite_db(path: &Path) -> Result<PathBuf, String> {
    if !path.exists() {
        return Err(format!("SQLite database not found at: {}", path.display()));
    }

    let mut tmp_dir = env::temp_dir();
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|err| err.to_string())?
        .as_millis();
    tmp_dir.push(format!("atlas-db-{stamp}-{}", std::process::id()));
    fs::create_dir_all(&tmp_dir).map_err(|err| err.to_string())?;

    let destination = tmp_dir.join(
        path.file_name()
            .ok_or_else(|| "Atlas database path is missing a filename.".to_string())?,
    );
    fs::copy(path, &destination).map_err(|err| err.to_string())?;
    Ok(destination)
}

fn is_app_installed(app_name: &str) -> bool {
    app_bundle_paths(app_name)
        .iter()
        .any(|candidate| candidate.exists())
}

fn app_bundle_paths(app_name: &str) -> Vec<PathBuf> {
    let home = env::var("HOME").unwrap_or_default();
    vec![
        PathBuf::from("/Applications").join(format!("{app_name}.app")),
        PathBuf::from(home)
            .join("Applications")
            .join(format!("{app_name}.app")),
    ]
}

fn read_local_state() -> Result<Value, String> {
    let path = local_state_path();
    let text = fs::read_to_string(&path)
        .map_err(|_| format!("Local State file not found at: {}", path.display()))?;
    serde_json::from_str(&text)
        .map_err(|_| format!("Failed to parse Local State JSON at: {}", path.display()))
}

fn get_active_profile_path() -> Result<PathBuf, String> {
    let local_state = read_local_state()?;
    let host_root = local_state_path()
        .parent()
        .ok_or_else(|| "Unable to determine Atlas host root.".to_string())?
        .to_path_buf();

    if let Some(last_used) = local_state
        .pointer("/profile/last_used")
        .and_then(|value| value.as_str())
    {
        let candidate = host_root.join(last_used);
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    let default_profile = host_root.join("Default");
    if default_profile.exists() {
        return Ok(default_profile);
    }

    Err(format!(
        "Unable to resolve an Atlas profile directory under: {}",
        host_root.display()
    ))
}

fn run_applescript(script: &str) -> Result<String, String> {
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| format!("osascript is not available on PATH; Atlas control requires macOS ({err})"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let hint = applescript_hint(&stderr);
        if let Some(hint) = hint {
            return Err(format!("AppleScript failed: {stderr} (Hint: {hint})"));
        }
        return Err(format!("AppleScript failed: {stderr}"));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn applescript_hint(stderr: &str) -> Option<&'static str> {
    let lower = stderr.to_ascii_lowercase();
    if stderr.contains("-1743") || lower.contains("not authorized") || lower.contains("not permitted") {
        return Some(
            "Grant Automation permission in System Settings > Privacy & Security > Automation, and allow your terminal to control ChatGPT Atlas.",
        );
    }
    None
}

fn is_tab_capable(app_name: &str) -> Result<bool, String> {
    let probe = format!("tell application \"{app_name}\" to get count of windows");
    let output = Command::new("osascript")
        .arg("-e")
        .arg(probe)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| err.to_string())?;

    if output.status.success() {
        return Ok(true);
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if let Some(hint) = applescript_hint(&stderr) {
        return Err(format!("AppleScript probe failed: {stderr} (Hint: {hint})"));
    }
    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn applescript_hint_detects_permission_errors() {
        assert!(applescript_hint("Not authorized to send Apple events to ChatGPT Atlas (-1743)").is_some());
        assert!(applescript_hint("generic failure").is_none());
    }

    #[test]
    fn copy_sqlite_db_creates_a_temp_copy() {
        let mut source = env::temp_dir();
        source.push(format!("atlas-source-{}.db", std::process::id()));
        let mut file = fs::File::create(&source).expect("create source db");
        writeln!(file, "sqlite").expect("write source db");

        let copied = copy_sqlite_db(&source).expect("copy db");
        assert!(copied.exists());
        assert_ne!(copied, source);
        assert_eq!(
            fs::read_to_string(&copied).expect("read copy"),
            "sqlite\n"
        );

        let _ = fs::remove_file(source);
        let _ = fs::remove_file(&copied);
        if let Some(parent) = copied.parent() {
            let _ = fs::remove_dir(parent);
        }
    }
}
