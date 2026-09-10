use serde_json::json;
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, Read};

#[derive(Default)]
struct GroupStats {
    unresolved: usize,
    blocking: usize,
    threads: Vec<ThreadRecord>,
}

#[derive(Clone)]
struct ThreadRecord {
    thread_id: String,
    reviewer: String,
    review_state: String,
    line: String,
    preview: String,
}

fn main() {
    match run() {
        Ok(()) => {}
        Err(err) => {
            eprintln!("{err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<(), String> {
    let input = read_input()?;
    println!("{}", summarize_compact_threads(&input)?);
    Ok(())
}

fn summarize_compact_threads(input: &str) -> Result<String, String> {
    let mut groups: BTreeMap<String, GroupStats> = BTreeMap::new();
    let mut total_threads = 0usize;

    for (index, line) in input.lines().enumerate() {
        if index == 0 || line.trim().is_empty() {
            continue;
        }

        let columns: Vec<&str> = line.split('\t').collect();
        if columns.len() < 9 {
            return Err(format!("Invalid compact thread row: {line}"));
        }

        let path = columns[1].trim();
        let is_resolved = columns[2].trim() == "true";
        let is_outdated = columns[3].trim() == "true";
        if is_resolved || is_outdated {
            continue;
        }

        let review_state = columns[6].trim();
        let group = groups.entry(path.to_string()).or_default();
        group.unresolved += 1;
        if review_state == "CHANGES_REQUESTED" {
            group.blocking += 1;
        }
        group.threads.push(ThreadRecord {
            thread_id: columns[0].trim().to_string(),
            reviewer: columns[5].trim().to_string(),
            review_state: review_state.to_string(),
            line: columns[4].trim().to_string(),
            preview: columns[8].trim().to_string(),
        });
        total_threads += 1;
    }

    if total_threads == 0 {
        return Err("No unresolved compact thread rows found in input.".to_string());
    }

    let by_path: Vec<serde_json::Value> = groups
        .iter()
        .map(|(path, stats)| {
            let threads: Vec<serde_json::Value> = stats
                .threads
                .iter()
                .map(|thread| {
                    json!({
                        "thread_id": thread.thread_id,
                        "reviewer": thread.reviewer,
                        "review_state": thread.review_state,
                        "line": thread.line,
                        "preview": thread.preview,
                    })
                })
                .collect();

            json!({
                "path": path,
                "unresolved": stats.unresolved,
                "blocking": stats.blocking,
                "threads": threads,
            })
        })
        .collect();

    Ok(json!({
        "thread_count": total_threads,
        "by_path": by_path,
    })
    .to_string())
}

fn read_input() -> Result<String, String> {
    let mut args = env::args().skip(1);
    if let Some(path) = args.next() {
        return fs::read_to_string(path).map_err(|err| err.to_string());
    }

    let mut buffer = String::new();
    io::stdin()
        .read_to_string(&mut buffer)
        .map_err(|err| err.to_string())?;
    Ok(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn summarizes_unresolved_threads_by_path() {
        let input = concat!(
            "thread_id\tpath\tis_resolved\tis_outdated\tline\treviewer\treview_state\tcomment_count\tpreview\n",
            "1\tsrc/app.ts\tfalse\tfalse\t42\talice\tCHANGES_REQUESTED\t2\tNeeds a null check\n",
            "2\tsrc/app.ts\ttrue\tfalse\t43\tbob\tCOMMENTED\t1\tAlready fixed\n",
            "3\tsrc/lib.ts\tfalse\ttrue\t9\tcara\tCOMMENTED\t1\tOutdated thread\n"
        );

        let output = summarize_compact_threads(input).expect("summary");
        let json: Value = serde_json::from_str(&output).expect("valid json");

        assert_eq!(json.get("thread_count").and_then(Value::as_u64), Some(1));
        assert_eq!(
            json.pointer("/by_path/0/path").and_then(Value::as_str),
            Some("src/app.ts")
        );
        assert_eq!(
            json.pointer("/by_path/0/blocking").and_then(Value::as_u64),
            Some(1)
        );
    }

    #[test]
    fn errors_on_invalid_compact_rows() {
        let input = "thread_id\tpath\tis_resolved\nbroken-row";
        let error = summarize_compact_threads(input).expect_err("invalid row");
        assert!(error.contains("Invalid compact thread row"));
    }
}
