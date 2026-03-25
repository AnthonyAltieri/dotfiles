mod atlas_common;

use atlas_common::{
    copy_sqlite_db, detect_atlas_app_name, detect_tab_capable_app_name, get_bookmarks_path,
    get_history_path, tell_atlas,
};
use serde::Serialize;
use serde_json::Value;
use std::env;
use std::fs;
use std::process::{Command, Stdio};

const ROW_SEP: &str = "|||";
const CHROME_EPOCH_OFFSET_SECONDS: i64 = 11_644_473_600;
const DEFAULT_HISTORY_LIMIT: usize = 200;
const DEFAULT_BOOKMARK_LIMIT: usize = 200;

#[derive(Serialize)]
struct Tab {
    title: String,
    url: String,
    window_id: i64,
    tab_index: i64,
    is_active: bool,
}

#[derive(Serialize)]
struct HistoryRow {
    id: i64,
    url: String,
    title: String,
    last_visited_at: String,
}

#[derive(Serialize)]
struct Bookmark {
    id: String,
    name: String,
    url: String,
    date_added: String,
    folder: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
enum CommandKind {
    AppName,
    Tabs { json: bool },
    OpenTab { url: String },
    FocusTab { window_id: i64, tab_index: i64 },
    CloseTab { window_id: i64, tab_index: i64 },
    ReloadTab { window_id: i64, tab_index: i64 },
    History {
        search: Option<String>,
        limit: usize,
        today: bool,
        json: bool,
    },
    Bookmarks {
        search: Option<String>,
        limit: usize,
        json: bool,
    },
}

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("atlas error: {err}");
            std::process::exit(2);
        }
    }
}

fn run() -> Result<i32, String> {
    let args: Vec<String> = env::args().skip(1).collect();
    let command = parse_args(&args)?;

    match command {
        CommandKind::AppName => {
            println!("{}", detect_atlas_app_name()?);
            Ok(0)
        }
        CommandKind::Tabs { json } => {
            render_tabs(&get_tabs()?, json)?;
            Ok(0)
        }
        CommandKind::OpenTab { url } => {
            open_new_tab(&url)?;
            println!("Opened tab: {url}");
            Ok(0)
        }
        CommandKind::FocusTab {
            window_id,
            tab_index,
        } => {
            focus_tab(window_id, tab_index)?;
            println!("Focused window id {window_id}, tab {tab_index}");
            Ok(0)
        }
        CommandKind::CloseTab {
            window_id,
            tab_index,
        } => {
            close_tab(window_id, tab_index)?;
            println!("Closed window id {window_id}, tab {tab_index}");
            Ok(0)
        }
        CommandKind::ReloadTab {
            window_id,
            tab_index,
        } => {
            reload_tab(window_id, tab_index)?;
            println!("Reloaded window id {window_id}, tab {tab_index}");
            Ok(0)
        }
        CommandKind::History {
            search,
            limit,
            today,
            json,
        } => {
            render_history(&search_history(search.as_deref(), limit.max(1), today)?, json)?;
            Ok(0)
        }
        CommandKind::Bookmarks { search, limit, json } => {
            render_bookmarks(&get_bookmarks(limit.max(1), search.as_deref())?, json)?;
            Ok(0)
        }
    }
}

fn parse_args(args: &[String]) -> Result<CommandKind, String> {
    if args.is_empty() {
        print_usage();
        return Err("Missing command.".to_string());
    }
    if args[0] == "--help" || args[0] == "-h" {
        print_usage();
        std::process::exit(0);
    }

    match args[0].as_str() {
        "app-name" => Ok(CommandKind::AppName),
        "tabs" => Ok(CommandKind::Tabs {
            json: args.iter().any(|arg| arg == "--json"),
        }),
        "open-tab" => Ok(CommandKind::OpenTab {
            url: args.get(1).cloned().ok_or_else(|| "open-tab requires a URL".to_string())?,
        }),
        "focus-tab" => Ok(CommandKind::FocusTab {
            window_id: parse_i64(args.get(1), "focus-tab requires window_id")?,
            tab_index: parse_i64(args.get(2), "focus-tab requires tab_index")?,
        }),
        "close-tab" => Ok(CommandKind::CloseTab {
            window_id: parse_i64(args.get(1), "close-tab requires window_id")?,
            tab_index: parse_i64(args.get(2), "close-tab requires tab_index")?,
        }),
        "reload-tab" => Ok(CommandKind::ReloadTab {
            window_id: parse_i64(args.get(1), "reload-tab requires window_id")?,
            tab_index: parse_i64(args.get(2), "reload-tab requires tab_index")?,
        }),
        "history" => parse_history_args(&args[1..]),
        "bookmarks" => parse_bookmark_args(&args[1..]),
        other => Err(format!("Unknown command: {other}")),
    }
}

fn parse_history_args(args: &[String]) -> Result<CommandKind, String> {
    let mut search = None;
    let mut limit = DEFAULT_HISTORY_LIMIT;
    let mut today = false;
    let mut json = false;
    let mut index = 0usize;

    while index < args.len() {
        match args[index].as_str() {
            "--search" => {
                search = Some(
                    args.get(index + 1)
                        .cloned()
                        .ok_or_else(|| "--search requires a value".to_string())?,
                );
                index += 2;
            }
            "--limit" => {
                limit = parse_usize(args.get(index + 1), "--limit requires a value")?;
                index += 2;
            }
            "--today" => {
                today = true;
                index += 1;
            }
            "--json" => {
                json = true;
                index += 1;
            }
            "--help" | "-h" => {
                print_usage();
                std::process::exit(0);
            }
            other => return Err(format!("Unknown history option: {other}")),
        }
    }

    Ok(CommandKind::History {
        search,
        limit,
        today,
        json,
    })
}

fn parse_bookmark_args(args: &[String]) -> Result<CommandKind, String> {
    let mut search = None;
    let mut limit = DEFAULT_BOOKMARK_LIMIT;
    let mut json = false;
    let mut index = 0usize;

    while index < args.len() {
        match args[index].as_str() {
            "--search" => {
                search = Some(
                    args.get(index + 1)
                        .cloned()
                        .ok_or_else(|| "--search requires a value".to_string())?,
                );
                index += 2;
            }
            "--limit" => {
                limit = parse_usize(args.get(index + 1), "--limit requires a value")?;
                index += 2;
            }
            "--json" => {
                json = true;
                index += 1;
            }
            "--help" | "-h" => {
                print_usage();
                std::process::exit(0);
            }
            other => return Err(format!("Unknown bookmarks option: {other}")),
        }
    }

    Ok(CommandKind::Bookmarks { search, limit, json })
}

fn parse_i64(value: Option<&String>, message: &str) -> Result<i64, String> {
    value
        .ok_or_else(|| message.to_string())?
        .parse::<i64>()
        .map_err(|_| message.to_string())
}

fn parse_usize(value: Option<&String>, message: &str) -> Result<usize, String> {
    value
        .ok_or_else(|| message.to_string())?
        .parse::<usize>()
        .map_err(|_| message.to_string())
}

fn print_usage() {
    println!(
        "Control ChatGPT Atlas from the terminal.\n\nCommands:\n  app-name\n  tabs [--json]\n  open-tab <url>\n  focus-tab <window_id> <tab_index>\n  close-tab <window_id> <tab_index>\n  reload-tab <window_id> <tab_index>\n  history [--search text] [--limit n] [--today] [--json]\n  bookmarks [--search text] [--limit n] [--json]"
    );
}

fn get_tabs() -> Result<Vec<Tab>, String> {
    let tab_app = detect_tab_capable_app_name()?;
    let script_body = format!(
        "set tabList to {{}}\n\nrepeat with w in every window\n  set windowId to id of w\n  set tabIndex to 0\n  set activeIndex to active tab index of w\n  try\n    set winTabs to every tab of w\n    repeat with t in winTabs\n      set tabIndex to tabIndex + 1\n      set tabTitle to title of t\n      set tabURL to URL of t\n      set isActive to (tabIndex = activeIndex)\n      set end of tabList to {{tabTitle, tabURL, windowId, tabIndex, isActive}}\n    end repeat\n  end try\nend repeat\n\nset output to \"\"\nrepeat with tabInfo in tabList\n  set output to output & item 1 of tabInfo & \"{ROW_SEP}\" & item 2 of tabInfo & \"{ROW_SEP}\" & item 3 of tabInfo & \"{ROW_SEP}\" & item 4 of tabInfo & \"{ROW_SEP}\" & item 5 of tabInfo & \"\\n\"\nend repeat\n\nreturn output"
    );

    let raw = tell_atlas(&script_body, Some(&tab_app))?;
    if raw.is_empty() {
        return Ok(Vec::new());
    }

    let mut tabs = Vec::new();
    for line in raw.lines() {
        let parts: Vec<&str> = line.split(ROW_SEP).collect();
        if parts.len() != 5 {
            continue;
        }
        let window_id = match parts[2].parse::<i64>() {
            Ok(value) => value,
            Err(_) => continue,
        };
        let tab_index = match parts[3].parse::<i64>() {
            Ok(value) => value,
            Err(_) => continue,
        };
        tabs.push(Tab {
            title: parts[0].to_string(),
            url: parts[1].to_string(),
            window_id,
            tab_index,
            is_active: parts[4] == "true",
        });
    }

    Ok(tabs)
}

fn open_new_tab(url: &str) -> Result<(), String> {
    let script_body = format!(
        "activate\ndelay 0.1\nopen location \"{}\"\n\nactivate",
        escape_applescript_string(url)
    );
    tell_atlas(&script_body, None).map(|_| ())
}

fn focus_tab(window_id: i64, tab_index: i64) -> Result<(), String> {
    let tab_app = detect_tab_capable_app_name()?;
    let script_body = format!(
        "activate\nset _wnd to first window whose id is {window_id}\nset index of _wnd to 1\nset active tab index of _wnd to {tab_index}\nreturn true"
    );
    tell_atlas(&script_body, Some(&tab_app)).map(|_| ())
}

fn close_tab(window_id: i64, tab_index: i64) -> Result<(), String> {
    let tab_app = detect_tab_capable_app_name()?;
    let script_body = format!(
        "set _wnd to first window whose id is {window_id}\ntell _wnd\n  close tab {tab_index}\nend tell"
    );
    tell_atlas(&script_body, Some(&tab_app)).map(|_| ())
}

fn reload_tab(window_id: i64, tab_index: i64) -> Result<(), String> {
    let tab_app = detect_tab_capable_app_name()?;
    let script_body = format!(
        "set _wnd to first window whose id is {window_id}\ntell _wnd\n  reload tab {tab_index}\nend tell"
    );
    tell_atlas(&script_body, Some(&tab_app)).map(|_| ())
}

fn search_history(search_text: Option<&str>, limit: usize, today: bool) -> Result<Vec<HistoryRow>, String> {
    let history_path = get_history_path()?;
    let db_copy = copy_sqlite_db(&history_path)?;
    let query = history_query(search_text, limit, today)?;

    let output = Command::new("sqlite3")
        .arg("-readonly")
        .arg("-separator")
        .arg("\t")
        .arg(db_copy)
        .arg(query)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| format!("sqlite3 is not available on PATH ({err})"))?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }

    let mut rows = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let columns: Vec<&str> = line.split('\t').collect();
        if columns.len() < 4 {
            continue;
        }
        rows.push(HistoryRow {
            id: columns[0].parse::<i64>().unwrap_or_default(),
            url: columns[1].to_string(),
            title: columns[2].to_string(),
            last_visited_at: columns[3].to_string(),
        });
    }
    Ok(rows)
}

fn history_query(search_text: Option<&str>, limit: usize, today: bool) -> Result<String, String> {
    let mut conditions: Vec<String> = Vec::new();

    if let Some(text) = search_text {
        for term in text.split_whitespace() {
            let escaped = escape_sql_literal(term);
            conditions.push(format!("(url LIKE '%{escaped}%' OR title LIKE '%{escaped}%')"));
        }
    }

    if today {
        let (start, end) = chrome_time_bounds_today()?;
        conditions.push(format!("last_visit_time >= {start}"));
        conditions.push(format!("last_visit_time < {end}"));
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("\nWHERE {}", conditions.join(" AND "))
    };

    Ok(format!(
        "WITH filtered AS (\n  SELECT id, url, title, last_visit_time\n  FROM urls{where_clause}\n),\nranked AS (\n  SELECT\n    id,\n    url,\n    title,\n    last_visit_time,\n    ROW_NUMBER() OVER (\n      PARTITION BY url\n      ORDER BY last_visit_time DESC, id DESC\n    ) AS rn\n  FROM filtered\n)\nSELECT\n  id,\n  url,\n  title,\n  datetime(last_visit_time / 1000000 + (strftime('%s', '1601-01-01')), 'unixepoch', 'localtime') AS lastVisitedAt\nFROM ranked\nWHERE rn = 1\nORDER BY last_visit_time DESC\nLIMIT {limit};"
    ))
}

fn get_bookmarks(limit: usize, search_text: Option<&str>) -> Result<Vec<Bookmark>, String> {
    let bookmarks_path = get_bookmarks_path()?;
    let text = fs::read_to_string(&bookmarks_path)
        .map_err(|err| format!("Failed to read bookmarks at {} ({err})", bookmarks_path.display()))?;
    let data: Value = serde_json::from_str(&text)
        .map_err(|err| format!("Failed to parse bookmarks JSON at {} ({err})", bookmarks_path.display()))?;

    let mut bookmarks = Vec::new();
    for (folder_name, key) in [
        ("Bookmarks Bar", "bookmark_bar"),
        ("Other Bookmarks", "other"),
        ("Synced Bookmarks", "synced"),
    ] {
        if let Some(root) = data.pointer(&format!("/roots/{key}")) {
            collect_bookmarks(root, folder_name, &mut bookmarks);
        }
    }

    if let Some(search) = search_text {
        let lowered = search.to_ascii_lowercase();
        bookmarks.retain(|bookmark| {
            bookmark.name.to_ascii_lowercase().contains(&lowered)
                || bookmark.url.to_ascii_lowercase().contains(&lowered)
                || bookmark
                    .folder
                    .as_deref()
                    .unwrap_or_default()
                    .to_ascii_lowercase()
                    .contains(&lowered)
        });
    }

    bookmarks.truncate(limit);
    Ok(bookmarks)
}

fn collect_bookmarks(node: &Value, folder: &str, output: &mut Vec<Bookmark>) {
    if node.get("type").and_then(|value| value.as_str()) == Some("url") {
        if let Some(url) = node.get("url").and_then(|value| value.as_str()) {
            output.push(Bookmark {
                id: node
                    .get("id")
                    .and_then(|value| value.as_str())
                    .unwrap_or_default()
                    .to_string(),
                name: node
                    .get("name")
                    .and_then(|value| value.as_str())
                    .unwrap_or("Untitled")
                    .to_string(),
                url: url.to_string(),
                date_added: chrome_microseconds_to_iso_date(
                    node.get("date_added").and_then(|value| value.as_str()),
                ),
                folder: if folder.is_empty() {
                    None
                } else {
                    Some(folder.to_string())
                },
            });
        }
    }

    let next_folder = node
        .get("name")
        .and_then(|value| value.as_str())
        .filter(|value| !value.is_empty())
        .unwrap_or(folder)
        .to_string();

    if let Some(children) = node.get("children").and_then(|value| value.as_array()) {
        for child in children {
            collect_bookmarks(child, &next_folder, output);
        }
    }
}

fn render_tabs(tabs: &[Tab], json: bool) -> Result<(), String> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(tabs).map_err(|err| err.to_string())?
        );
        return Ok(());
    }

    let rows: Vec<Vec<String>> = tabs
        .iter()
        .map(|tab| {
            vec![
                if tab.is_active { "*" } else { " " }.to_string(),
                tab.window_id.to_string(),
                tab.tab_index.to_string(),
                tab.title.clone(),
                tab.url.clone(),
            ]
        })
        .collect();
    print_table(&rows, &["A", "window_id", "tab", "title", "url"]);
    Ok(())
}

fn render_history(rows: &[HistoryRow], json: bool) -> Result<(), String> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(rows).map_err(|err| err.to_string())?
        );
        return Ok(());
    }

    let table: Vec<Vec<String>> = rows
        .iter()
        .map(|row| vec![row.last_visited_at.clone(), row.title.clone(), row.url.clone()])
        .collect();
    print_table(&table, &["last_visited_at", "title", "url"]);
    Ok(())
}

fn render_bookmarks(rows: &[Bookmark], json: bool) -> Result<(), String> {
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(rows).map_err(|err| err.to_string())?
        );
        return Ok(());
    }

    let table: Vec<Vec<String>> = rows
        .iter()
        .map(|row| {
            vec![
                row.folder.clone().unwrap_or_default(),
                row.name.clone(),
                row.url.clone(),
                row.date_added.clone(),
            ]
        })
        .collect();
    print_table(&table, &["folder", "name", "url", "date_added"]);
    Ok(())
}

fn print_table(rows: &[Vec<String>], headers: &[&str]) {
    let mut widths: Vec<usize> = headers.iter().map(|header| header.len()).collect();
    for row in rows {
        for (index, cell) in row.iter().enumerate() {
            if let Some(width) = widths.get_mut(index) {
                *width = (*width).max(cell.len());
            }
        }
    }

    let format_row = |row: &[String]| -> String {
        row.iter()
            .enumerate()
            .map(|(index, cell)| format!("{cell:<width$}", width = widths[index]))
            .collect::<Vec<String>>()
            .join("  ")
    };

    let header_row: Vec<String> = headers.iter().map(|value| value.to_string()).collect();
    println!("{}", format_row(&header_row));
    println!(
        "{}",
        format_row(
            &widths
                .iter()
                .map(|width| "-".repeat(*width))
                .collect::<Vec<String>>()
        )
    );
    for row in rows {
        println!("{}", format_row(row));
    }
}

fn escape_applescript_string(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn escape_sql_literal(value: &str) -> String {
    value.replace('\'', "''")
}

fn chrome_microseconds_to_iso_date(value: Option<&str>) -> String {
    let Some(value) = value else {
        return "unknown".to_string();
    };
    let Ok(timestamp) = value.parse::<i64>() else {
        return "unknown".to_string();
    };

    let unix_seconds = timestamp / 1_000_000 - CHROME_EPOCH_OFFSET_SECONDS;
    local_date_from_unix_seconds(unix_seconds).unwrap_or_else(|| "unknown".to_string())
}

fn chrome_time_bounds_today() -> Result<(i64, i64), String> {
    let start = local_day_start_unix_seconds(0)?;
    let end = local_day_start_unix_seconds(1)?;
    Ok((
        chrome_time_from_unix_seconds(start),
        chrome_time_from_unix_seconds(end),
    ))
}

fn chrome_time_from_unix_seconds(unix_seconds: i64) -> i64 {
    (unix_seconds + CHROME_EPOCH_OFFSET_SECONDS) * 1_000_000
}

fn local_date_from_unix_seconds(unix_seconds: i64) -> Option<String> {
    let output = Command::new("/bin/date")
        .arg("-r")
        .arg(unix_seconds.to_string())
        .arg("+%Y-%m-%d")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let date = String::from_utf8(output.stdout).ok()?;
    let trimmed = date.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn local_day_start_unix_seconds(days_from_today: i64) -> Result<i64, String> {
    let mut command = Command::new("/bin/date");
    if days_from_today != 0 {
        command.arg(format!("-v{days_from_today:+}d"));
    }

    let output = command
        .arg("-v0H")
        .arg("-v0M")
        .arg("-v0S")
        .arg("+%s")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| format!("failed to calculate local day bounds: {err}"))?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }

    let stdout = String::from_utf8(output.stdout)
        .map_err(|err| format!("failed to parse local day bounds: {err}"))?;
    stdout
        .trim()
        .parse::<i64>()
        .map_err(|err| format!("failed to parse local day bounds: {err}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_args_supports_tabs_and_history_commands() {
        assert_eq!(
            parse_args(&["tabs".to_string(), "--json".to_string()]).expect("tabs args"),
            CommandKind::Tabs { json: true }
        );
        assert_eq!(
            parse_args(&[
                "history".to_string(),
                "--search".to_string(),
                "atlas".to_string(),
                "--limit".to_string(),
                "25".to_string(),
                "--json".to_string(),
            ])
            .expect("history args"),
            CommandKind::History {
                search: Some("atlas".to_string()),
                limit: 25,
                today: false,
                json: true,
            }
        );
    }

    #[test]
    fn history_query_includes_search_terms_and_limit() {
        let query = history_query(Some("atlas chat"), 25, false).expect("query");
        assert!(query.contains("url LIKE '%atlas%'"));
        assert!(query.contains("title LIKE '%chat%'"));
        assert!(query.contains("LIMIT 25"));
    }

    #[test]
    fn collect_bookmarks_flattens_nested_folders() {
        let node = json!({
            "name": "Bookmarks Bar",
            "children": [
                {
                    "type": "url",
                    "id": "1",
                    "name": "Atlas",
                    "url": "https://chatgpt.com",
                    "date_added": "13217451500000000"
                },
                {
                    "name": "Nested",
                    "children": [
                        {
                            "type": "url",
                            "id": "2",
                            "name": "Docs",
                            "url": "https://example.com/docs",
                            "date_added": "13217451500000000"
                        }
                    ]
                }
            ]
        });

        let mut bookmarks = Vec::new();
        collect_bookmarks(&node, "Bookmarks Bar", &mut bookmarks);

        assert_eq!(bookmarks.len(), 2);
        assert_eq!(bookmarks[0].folder.as_deref(), Some("Bookmarks Bar"));
        assert_eq!(bookmarks[1].folder.as_deref(), Some("Nested"));
    }

    #[test]
    fn escape_helpers_and_invalid_dates_are_stable() {
        assert_eq!(escape_applescript_string("a\"b\\c"), "a\\\"b\\\\c");
        assert_eq!(escape_sql_literal("O'Reilly"), "O''Reilly");
        assert_eq!(chrome_microseconds_to_iso_date(None), "unknown");
        assert_eq!(chrome_microseconds_to_iso_date(Some("not-a-number")), "unknown");
    }
}
