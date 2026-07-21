#!/usr/bin/env bash

set -euo pipefail
umask 077

if [[ "$#" -lt 3 ]]; then
  echo "Usage: $0 <jq> <destination-file> <legacy-file>..." >&2
  exit 2
fi

jq_bin="$1"
destination_file="$2"
shift 2
legacy_files=("$@")
destination_dir="$(dirname "$destination_file")"
migration_file="${destination_file}.migration.tmp"
next_file="${destination_file}.migration.next"

cleanup() {
  rm -f "$migration_file" "$next_file"
}
trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p "$destination_dir"
chmod 700 "$destination_dir"
cleanup

if [[ -f "$destination_file" ]]; then
  cp "$destination_file" "$migration_file"
else
  printf '%s\n' '{"version":1,"targets":{}}' > "$migration_file"
fi
chmod 600 "$migration_file"

for legacy_file in "${legacy_files[@]}"; do
  [[ -f "$legacy_file" ]] || continue

  "$jq_bin" -e \
    '.version == 1 and ((.targets | type) == "object")' \
    "$legacy_file" >/dev/null \
    || fail "Legacy SQL Read state is invalid; reconcile it manually before applying the profile."

  "$jq_bin" -e \
    '.version == 1 and ((.targets | type) == "object")' \
    "$migration_file" >/dev/null \
    || fail "Current SQL Read state is invalid; reconcile it manually before applying the profile."

  "$jq_bin" -e -n \
    --slurpfile current "$migration_file" \
    --slurpfile legacy "$legacy_file" \
    '[
      $legacy[0].targets
      | to_entries[]
      | .key as $key
      | select(
          ($current[0].targets | has($key))
          and $current[0].targets[$key] != .value
        )
    ] | length == 0' >/dev/null \
    || fail "Conflicting SQL Read target definitions exist; reconcile them manually before applying the profile."

  "$jq_bin" -n \
    --slurpfile current "$migration_file" \
    --slurpfile legacy "$legacy_file" \
    '$current[0] | .targets += $legacy[0].targets' \
    > "$next_file" \
    || fail "Failed to merge legacy SQL Read state."
  chmod 600 "$next_file"
  mv -f "$next_file" "$migration_file"
done

mv -f "$migration_file" "$destination_file"
chmod 600 "$destination_file"
