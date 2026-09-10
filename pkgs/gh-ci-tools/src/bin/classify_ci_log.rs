use serde_json::json;
use std::env;
use std::fs;
use std::io::{self, Read};

const CONTEXT_LINES: usize = 2;
const MAX_MATCHES: usize = 6;

struct BucketPattern {
    bucket: &'static str,
    patterns: &'static [&'static str],
}

const BUCKETS: &[BucketPattern] = &[
    BucketPattern {
        bucket: "build",
        patterns: &[
            "error[e",
            "compilation failed",
            "module not found",
            "cannot find",
            "undefined reference",
            "build failed",
        ],
    },
    BucketPattern {
        bucket: "test",
        patterns: &[
            "assert",
            "assertionerror",
            "test failed",
            "panic",
            "expected:",
            "received:",
        ],
    },
    BucketPattern {
        bucket: "lint",
        patterns: &["lint", "eslint", "ruff", "clippy", "prettier", "formatting"],
    },
    BucketPattern {
        bucket: "config",
        patterns: &[
            "workflow",
            "invalid yaml",
            "invalid config",
            "missing secret",
            "could not resolve action",
            "permission denied",
        ],
    },
    BucketPattern {
        bucket: "environment",
        patterns: &[
            "timed out",
            "timeout",
            "network",
            "dns",
            "econnreset",
            "out of memory",
            "oom",
            "killed",
        ],
    },
];

#[derive(Clone)]
struct MatchRecord {
    bucket: &'static str,
    marker: &'static str,
    line: usize,
    snippet: String,
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
    println!("{}", classify_log(&input)?);
    Ok(())
}

fn classify_log(input: &str) -> Result<String, String> {
    let lines: Vec<&str> = input.lines().collect();
    if lines.is_empty() {
        return Err("CI log input is empty.".to_string());
    }

    let mut counts = vec![0usize; BUCKETS.len()];
    let mut matches: Vec<MatchRecord> = Vec::new();

    for (index, line) in lines.iter().enumerate() {
        let lowered = line.to_ascii_lowercase();
        for (bucket_index, bucket) in BUCKETS.iter().enumerate() {
            for pattern in bucket.patterns {
                if lowered.contains(pattern) {
                    counts[bucket_index] += 1;
                    if matches.len() < MAX_MATCHES {
                        matches.push(MatchRecord {
                            bucket: bucket.bucket,
                            marker: pattern,
                            line: index + 1,
                            snippet: context_window(&lines, index),
                        });
                    }
                    break;
                }
            }
        }
    }

    let (selected_bucket, selected_count) = counts
        .iter()
        .enumerate()
        .max_by_key(|(_, count)| *count)
        .map(|(index, count)| (BUCKETS[index].bucket, *count))
        .ok_or_else(|| "Unable to classify CI log.".to_string())?;

    let bucket = if selected_count == 0 {
        "unknown"
    } else {
        selected_bucket
    };

    let bucket_matches: Vec<MatchRecord> = matches
        .into_iter()
        .filter(|record| record.bucket == bucket || bucket == "unknown")
        .collect();

    Ok(render_json(bucket, &counts, &bucket_matches))
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

fn context_window(lines: &[&str], center: usize) -> String {
    let start = center.saturating_sub(CONTEXT_LINES);
    let end = usize::min(lines.len(), center + CONTEXT_LINES + 1);
    lines[start..end].join("\\n")
}

fn render_json(bucket: &str, counts: &[usize], matches: &[MatchRecord]) -> String {
    let counts_by_bucket: serde_json::Map<String, serde_json::Value> = BUCKETS
        .iter()
        .zip(counts)
        .map(|(bucket_pattern, count)| (bucket_pattern.bucket.to_string(), json!(count)))
        .collect();

    let match_records: Vec<serde_json::Value> = matches
        .iter()
        .map(|item| {
            json!({
                "line": item.line,
                "marker": item.marker,
                "snippet": item.snippet,
            })
        })
        .collect();

    json!({
        "bucket": bucket,
        "counts": counts_by_bucket,
        "matches": match_records,
    })
    .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn classifies_build_logs_and_keeps_failure_matches() {
        let output = classify_log(
            "Compiling app\nerror[E0425]: cannot find value `x` in this scope\nBuild failed\n",
        )
        .expect("classification");
        let json: Value = serde_json::from_str(&output).expect("valid json");

        assert_eq!(json.get("bucket").and_then(Value::as_str), Some("build"));
        assert_eq!(
            json.pointer("/counts/build").and_then(Value::as_u64),
            Some(2)
        );
        assert_eq!(
            json.pointer("/matches/0/marker").and_then(Value::as_str),
            Some("error[e")
        );
    }

    #[test]
    fn returns_unknown_when_no_markers_match() {
        let output = classify_log("all green\nnothing suspicious here\n").expect("classification");
        let json: Value = serde_json::from_str(&output).expect("valid json");

        assert_eq!(json.get("bucket").and_then(Value::as_str), Some("unknown"));
        assert_eq!(
            json.get("matches")
                .and_then(Value::as_array)
                .map(|items| items.is_empty()),
            Some(true)
        );
    }

    #[test]
    fn context_window_includes_neighboring_lines() {
        let lines = vec!["one", "two", "three", "four", "five"];
        assert_eq!(context_window(&lines, 2), "one\\ntwo\\nthree\\nfour\\nfive");
    }
}
