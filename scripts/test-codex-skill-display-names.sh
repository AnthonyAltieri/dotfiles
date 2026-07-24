#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

unquote_yaml_scalar() {
  local value="$1"

  if [[ "$value" == \"*\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  elif [[ "$value" == \'*\' ]]; then
    value="${value#\'}"
    value="${value%\'}"
  fi

  printf '%s\n' "$value"
}

checked=0
failures=0

while IFS= read -r metadata_file; do
  skill_dir="${metadata_file%/agents/openai.yaml}"
  skill_file="$skill_dir/SKILL.md"

  if [[ ! -f "$skill_file" ]]; then
    printf 'Missing sibling SKILL.md for %s\n' "$metadata_file" >&2
    failures=$((failures + 1))
    continue
  fi

  skill_name="$(
    awk '
      NR == 1 && $0 == "---" {
        in_frontmatter = 1
        next
      }
      in_frontmatter && $0 == "---" {
        exit
      }
      in_frontmatter && /^name:[[:space:]]*/ {
        sub(/^name:[[:space:]]*/, "")
        print
        exit
      }
    ' "$skill_file"
  )"

  display_name="$(
    awk '
      /^interface:[[:space:]]*$/ {
        in_interface = 1
        next
      }
      in_interface && /^[^[:space:]]/ {
        exit
      }
      in_interface && /^  display_name:[[:space:]]*/ {
        sub(/^  display_name:[[:space:]]*/, "")
        print
        exit
      }
    ' "$metadata_file"
  )"

  skill_name="$(unquote_yaml_scalar "$skill_name")"
  display_name="$(unquote_yaml_scalar "$display_name")"
  checked=$((checked + 1))

  if [[ -z "$skill_name" ]]; then
    printf 'Missing frontmatter name in %s\n' "$skill_file" >&2
    failures=$((failures + 1))
  elif [[ -z "$display_name" ]]; then
    printf 'Missing interface.display_name in %s\n' "$metadata_file" >&2
    failures=$((failures + 1))
  elif [[ "$display_name" != "$skill_name" ]]; then
    printf 'Display name mismatch in %s: expected %s, got %s\n' \
      "$metadata_file" "$skill_name" "$display_name" >&2
    failures=$((failures + 1))
  fi
done < <(find home/.codex/skills -type f -path '*/agents/openai.yaml' -print | sort)

if (( failures > 0 )); then
  exit 1
fi

printf 'Codex skill display names match canonical names (%d checked).\n' "$checked"
