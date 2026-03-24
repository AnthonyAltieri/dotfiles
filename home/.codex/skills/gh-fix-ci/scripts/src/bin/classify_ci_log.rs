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

    let mut counts = [0usize; 5];
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

fn render_json(bucket: &str, counts: &[usize; 5], matches: &[MatchRecord]) -> String {
    let mut json = String::new();
    json.push_str("{\"bucket\":\"");
    json.push_str(bucket);
    json.push_str("\",\"counts\":{");

    for (index, bucket_pattern) in BUCKETS.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        json.push('"');
        json.push_str(bucket_pattern.bucket);
        json.push_str("\":");
        json.push_str(&counts[index].to_string());
    }

    json.push_str("},\"matches\":[");

    for (index, item) in matches.iter().enumerate() {
        if index > 0 {
            json.push(',');
        }
        json.push_str("{\"line\":");
        json.push_str(&item.line.to_string());
        json.push_str(",\"marker\":\"");
        json.push_str(&escape_json(item.marker));
        json.push_str("\",\"snippet\":\"");
        json.push_str(&escape_json(&item.snippet));
        json.push_str("\"}");
    }

    json.push_str("]}");
    json
}

fn escape_json(value: &str) -> String {
    let mut escaped = String::new();
    for ch in value.chars() {
        match ch {
            '\\' => escaped.push_str("\\\\"),
            '"' => escaped.push_str("\\\""),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            _ => escaped.push(ch),
        }
    }
    escaped
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
        assert_eq!(json.pointer("/counts/build").and_then(Value::as_u64), Some(2));
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
