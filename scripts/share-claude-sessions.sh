#!/usr/bin/env bash
# Makes extra Claude config directories share conversation history with the
# primary one, so `claude --resume` in any account sees every session.
#
# Shared (symlinked to the primary): transcripts, rewind checkpoints, session
# todos and plans, prompt history and the paste cache it refers to. Logins,
# settings and running-process state (`sessions/`) stay per account.
#
# Anything a secondary directory already had is merged into the primary (the
# primary's copy wins on a name clash) and the original is kept beside it as
# `<name>.pre-shared-<timestamp>`. Re-running is a no-op.

set -euo pipefail
umask 077

if [[ "$#" -lt 2 ]]; then
  echo "Usage: $0 <primary-claude-dir> <secondary-claude-dir>..." >&2
  exit 2
fi

primary="$1"
shift
shared_dirs=(projects file-history todos plans paste-cache)
shared_files=(history.jsonl)
stamp="$(date +%Y%m%d%H%M%S)"

# Copies files from $1 into $2 that $2 does not already have.
merge_missing() {
  local from="$1" into="$2" relative
  while IFS= read -r -d '' relative; do
    if [[ ! -e "$into/$relative" ]]; then
      mkdir -p "$(dirname "$into/$relative")"
      cp -p "$from/$relative" "$into/$relative"
    fi
  done < <(cd "$from" && find . -type f -print0)
}

share() {
  local kind="$1" name="$2" root="$3"
  local source="$primary/$name" link="$root/$name"

  if [[ -L "$link" && "$(readlink "$link")" == "$source" ]]; then
    return
  fi

  if [[ "$kind" == "dir" ]]; then
    mkdir -p "$source"
  elif [[ ! -e "$source" ]]; then
    : > "$source"
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    if [[ -d "$link" && ! -L "$link" ]]; then
      merge_missing "$link" "$source"
    elif [[ -f "$link" && ! -L "$link" ]]; then
      cat "$link" >> "$source"
    fi
    mv "$link" "$link.pre-shared-$stamp"
  fi

  ln -s "$source" "$link"
}

mkdir -p "$primary"
for root in "$@"; do
  [[ "$root" != "$primary" ]] || continue
  mkdir -p "$root"
  for name in "${shared_dirs[@]}"; do share dir "$name" "$root"; done
  for name in "${shared_files[@]}"; do share file "$name" "$root"; done
done
