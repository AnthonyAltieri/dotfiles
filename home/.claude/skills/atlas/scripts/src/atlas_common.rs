use serde_json::Value;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const ATLAS_APP_NAME: &str = "ChatGPT Atlas";

pub struct TemporarySqliteCopy {
    path: PathBuf,
    _directory: TemporaryDirectory,
}

impl TemporarySqliteCopy {
    pub fn path(&self) -> &Path {
        &self.path
    }
}

struct TemporaryDirectory {
    path: PathBuf,
}

impl TemporaryDirectory {
    fn create() -> Result<Self, String> {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|err| err.to_string())?
            .as_nanos();

        for _ in 0..100 {
            let sequence = COUNTER.fetch_add(1, Ordering::Relaxed);
            let path = env::temp_dir().join(format!(
                "atlas-db-{stamp}-{}-{sequence}",
                std::process::id()
            ));
            let mut builder = fs::DirBuilder::new();
            #[cfg(unix)]
            {
                use std::os::unix::fs::DirBuilderExt;
                builder.mode(0o700);
            }
            match builder.create(&path) {
                Ok(()) => return Ok(Self { path }),
                Err(err) if err.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(err) => return Err(err.to_string()),
            }
        }

        Err("Could not create a unique temporary directory for Atlas data.".to_string())
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TemporaryDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

fn atlas_host_roots() -> Vec<PathBuf> {
    atlas_host_roots_from(Path::new(&env::var("HOME").unwrap_or_default()))
}

fn atlas_host_roots_from(home: &Path) -> Vec<PathBuf> {
    let application_support = home.join("Library").join("Application Support");
    ["com.openai.atlas", "com.openai.atlas.beta"]
        .iter()
        .map(|bundle_id| {
            application_support
                .join(bundle_id)
                .join("browser-data/host")
        })
        .collect()
}

fn active_host_root() -> Result<PathBuf, String> {
    select_active_host_root(
        env::var_os("ATLAS_DATA_ROOT").map(PathBuf::from),
        atlas_host_roots(),
    )
}

fn select_active_host_root(
    configured_root: Option<PathBuf>,
    candidate_roots: Vec<PathBuf>,
) -> Result<PathBuf, String> {
    if let Some(configured_root) = configured_root {
        if !configured_root.is_absolute() {
            return Err("ATLAS_DATA_ROOT must be an absolute path.".to_string());
        }
        if configured_root.join("Local State").is_file() {
            return Ok(configured_root);
        }
        return Err(format!(
            "ATLAS_DATA_ROOT does not contain Local State: {}",
            configured_root.display()
        ));
    }

    candidate_roots
        .into_iter()
        .filter(|root| root.join("Local State").is_file())
        .max_by_key(|root| {
            fs::metadata(root.join("Local State"))
                .and_then(|metadata| metadata.modified())
                .unwrap_or(UNIX_EPOCH)
        })
        .ok_or_else(|| {
            "Could not find Atlas browser data. Checked stable and beta profile roots.".to_string()
        })
}

fn local_state_path() -> Result<PathBuf, String> {
    Ok(active_host_root()?.join("Local State"))
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
        Err(
            "ChatGPT Atlas is installed but does not appear to expose window/tab scripting."
                .to_string(),
        )
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

pub fn copy_sqlite_db(path: &Path) -> Result<TemporarySqliteCopy, String> {
    if !path.exists() {
        return Err(format!("SQLite database not found at: {}", path.display()));
    }

    copy_sqlite_db_into(path, TemporaryDirectory::create()?)
}

fn copy_sqlite_db_into(
    path: &Path,
    directory: TemporaryDirectory,
) -> Result<TemporarySqliteCopy, String> {
    let destination = directory.path().join(
        path.file_name()
            .ok_or_else(|| "Atlas database path is missing a filename.".to_string())?,
    );
    let mut source = fs::File::open(path).map_err(|err| err.to_string())?;
    let mut target = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&destination)
        .map_err(|err| err.to_string())?;
    io::copy(&mut source, &mut target).map_err(|err| err.to_string())?;
    Ok(TemporarySqliteCopy {
        path: destination,
        _directory: directory,
    })
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
    let path = local_state_path()?;
    let text = fs::read_to_string(&path)
        .map_err(|_| format!("Local State file not found at: {}", path.display()))?;
    serde_json::from_str(&text)
        .map_err(|_| format!("Failed to parse Local State JSON at: {}", path.display()))
}

fn get_active_profile_path() -> Result<PathBuf, String> {
    let local_state = read_local_state()?;
    let host_root = local_state_path()?
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
        .map_err(|err| {
            format!("osascript is not available on PATH; Atlas control requires macOS ({err})")
        })?;

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
    if stderr.contains("-1743")
        || lower.contains("not authorized")
        || lower.contains("not permitted")
    {
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
    use std::thread;
    use std::time::Duration;

    #[test]
    fn applescript_hint_detects_permission_errors() {
        assert!(
            applescript_hint("Not authorized to send Apple events to ChatGPT Atlas (-1743)")
                .is_some()
        );
        assert!(applescript_hint("generic failure").is_none());
    }

    #[test]
    fn copy_sqlite_db_creates_a_temp_copy() {
        let mut source = env::temp_dir();
        source.push(format!("atlas-source-{}.db", std::process::id()));
        let mut file = fs::File::create(&source).expect("create source db");
        writeln!(file, "sqlite").expect("write source db");

        let copied = copy_sqlite_db(&source).expect("copy db");
        let copied_path = copied.path().to_path_buf();
        assert!(copied_path.exists());
        assert_ne!(copied_path, source);
        assert_eq!(
            fs::read_to_string(&copied_path).expect("read copy"),
            "sqlite\n"
        );

        let _ = fs::remove_file(source);
        drop(copied);
        assert!(!copied_path.exists());
    }

    #[test]
    fn copy_sqlite_db_cleans_up_after_copy_failure() {
        let source_directory = TemporaryDirectory::create().expect("source directory");
        let copy_directory = TemporaryDirectory::create().expect("copy directory");
        let copy_path = copy_directory.path().to_path_buf();

        assert!(copy_sqlite_db_into(source_directory.path(), copy_directory).is_err());
        assert!(!copy_path.exists());
    }

    #[test]
    fn selects_stable_beta_and_absolute_override_roots() {
        let home = TemporaryDirectory::create().expect("home");
        let roots = atlas_host_roots_from(home.path());
        let stable = roots[0].clone();
        let beta = roots[1].clone();

        fs::create_dir_all(&stable).expect("stable root");
        fs::write(stable.join("Local State"), "{}").expect("stable state");
        assert_eq!(
            select_active_host_root(None, roots.clone()).expect("stable selection"),
            stable
        );

        thread::sleep(Duration::from_millis(10));
        fs::create_dir_all(&beta).expect("beta root");
        fs::write(beta.join("Local State"), "{}").expect("beta state");
        assert_eq!(
            select_active_host_root(None, roots).expect("newer selection"),
            beta
        );

        let override_root = home.path().join("override");
        fs::create_dir_all(&override_root).expect("override root");
        fs::write(override_root.join("Local State"), "{}").expect("override state");
        assert_eq!(
            select_active_host_root(Some(override_root.clone()), Vec::new())
                .expect("override selection"),
            override_root
        );
        assert!(select_active_host_root(Some(PathBuf::from("relative")), Vec::new()).is_err());
        assert!(select_active_host_root(Some(home.path().join("missing")), Vec::new()).is_err());
    }
}
