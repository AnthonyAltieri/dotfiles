#!/usr/bin/env bash

# Every source the agent managed-copies activation step copies from must be part of the
# activation package's closure. A source that is only a path string into the flake's
# source tree carries no store dependency, so activating from a fresh checkout or
# worktree (where that tree was never realized) fails with `cp: cannot stat`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-personal-linux}"
NIX=(nix --extra-experimental-features 'nix-command flakes')

fail() {
  echo "$1" >&2
  exit 1
}

activation="$("${NIX[@]}" build --impure --no-link --print-out-paths \
  "$ROOT#homeConfigurations.${CONFIG}.activationPackage")"
closure="$(nix-store -qR "$activation")"

manifest="$(grep -- '-dotfiles-agent-managed-copies.tsv$' <<< "$closure" || true)"
[[ -n "$manifest" ]] || fail "Expected the managed-copies manifest in the ${CONFIG} activation closure"

missing=()
while IFS=$'\t' read -r target _kind _executable source; do
  [[ -n "$target" ]] || continue
  # The store object is the first three path components: /nix/store/<hash>-<name>.
  store_object="$(cut -d/ -f1-4 <<< "$source")"
  grep -Fxq "$store_object" <<< "$closure" || missing+=("$target <- $source")
done < "$manifest"

if ((${#missing[@]})); then
  printf 'Managed copy sources outside the activation closure:\n' >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "All $(grep -c . "$manifest") managed copy sources are in the ${CONFIG} activation closure"
