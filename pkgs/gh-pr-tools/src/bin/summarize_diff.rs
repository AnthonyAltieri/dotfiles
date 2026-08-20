use serde_json::json;
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, Read};

#[derive(Default)]
struct GroupStats {
    file_count: usize,
    change_units: usize,
    files: Vec<String>,
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
    println!("{}", summarize_input(&input)?);
    Ok(())
}

fn summarize_input(input: &str) -> Result<String, String> {
    let mut groups: BTreeMap<String, GroupStats> = BTreeMap::new();
    let mut total_files = 0usize;
    let mut total_insertions = 0usize;
    let mut total_deletions = 0usize;

    for line in input.lines() {
        if line.contains("files changed") {
            let (insertions, deletions) = parse_summary_line(line);
            total_insertions = insertions;
            total_deletions = deletions;
            continue;
        }

        if !line.contains('|') {
            continue;
        }

        let mut parts = line.splitn(2, '|');
        let path = parts.next().unwrap_or_default().trim();
        let stats = parts.next().unwrap_or_default();
        if path.is_empty() || path.ends_with("changed") {
            continue;
        }

        let change_units = stats.chars().filter(|ch| *ch == '+' || *ch == '-').count();
        let group_name = top_level_group(path);

        let group = groups.entry(group_name).or_default();
        group.file_count += 1;
        group.change_units += change_units;
        group.files.push(path.to_string());

        total_files += 1;
    }

    if total_files == 0 {
        return Err("No diffstat file entries found in input.".to_string());
    }

    let sections: Vec<serde_json::Value> = groups
        .iter()
        .map(|(name, stats)| {
            json!({
                "name": name,
                "file_count": stats.file_count,
                "change_units": stats.change_units,
                "files": stats.files,
            })
        })
        .collect();

    Ok(json!({
        "total_files": total_files,
        "insertions": total_insertions,
        "deletions": total_deletions,
        "sections": sections,
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

fn top_level_group(path: &str) -> String {
    path.split('/')
        .next()
        .filter(|segment| !segment.is_empty())
        .unwrap_or("(root)")
        .to_string()
}

fn parse_summary_line(line: &str) -> (usize, usize) {
    let mut insertions = 0usize;
    let mut deletions = 0usize;

    for section in line.split(',') {
        let trimmed = section.trim();
        if trimmed.contains("insertion") {
            insertions = leading_number(trimmed);
        } else if trimmed.contains("deletion") {
            deletions = leading_number(trimmed);
        }
    }

    (insertions, deletions)
}

fn leading_number(value: &str) -> usize {
    let digits: String = value.chars().take_while(|ch| ch.is_ascii_digit()).collect();
    digits.parse().unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summarizes_diffstat_into_grouped_json() {
        let input =
            " src/lib.rs | 4 ++--\n README.md | 2 +-\n 2 files changed, 3 insertions(+), 3 deletions(-)\n";
        let summary = summarize_input(input).expect("summary");
        let parsed: serde_json::Value = serde_json::from_str(&summary).expect("valid json");

        assert_eq!(
            parsed,
            json!({
                "total_files": 2,
                "insertions": 3,
                "deletions": 3,
                "sections": [
                    {
                        "name": "README.md",
                        "file_count": 1,
                        "change_units": 2,
                        "files": ["README.md"],
                    },
                    {
                        "name": "src",
                        "file_count": 1,
                        "change_units": 4,
                        "files": ["src/lib.rs"],
                    },
                ],
            })
        );
    }

    #[test]
    fn returns_error_when_no_file_entries_exist() {
        let error = summarize_input("1 file changed, 2 insertions(+)").expect_err("missing rows");
        assert_eq!(error, "No diffstat file entries found in input.");
    }

    #[test]
    fn parses_summary_line_with_missing_deletions() {
        assert_eq!(
            parse_summary_line("1 file changed, 4 insertions(+)"),
            (4, 0)
        );
    }
}
