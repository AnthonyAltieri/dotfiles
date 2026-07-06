#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DETECTOR="${ROOT_DIR}/scripts/detect-berkeley-mono-font.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_detects() {
  local expected="$1"
  local font_dir="$2"
  local actual

  actual="$(bash "$DETECTOR" "$font_dir")"
  if [ "$actual" != "$expected" ]; then
    echo "Expected '$expected' from $font_dir, got '$actual'" >&2
    exit 1
  fi
}

mkdir -p "$TMP_DIR/compact" "$TMP_DIR/spaced" "$TMP_DIR/fallback" "$TMP_DIR/empty"

touch "$TMP_DIR/compact/BerkeleyMono-Bold.otf"
touch "$TMP_DIR/compact/BerkeleyMono-Regular.otf"
assert_detects "BerkeleyMono" "$TMP_DIR/compact"

touch "$TMP_DIR/spaced/Berkeley Mono Regular.ttf"
assert_detects "Berkeley Mono" "$TMP_DIR/spaced"

touch "$TMP_DIR/fallback/BerkeleyMono-Bold-Oblique.otf"
assert_detects "BerkeleyMono" "$TMP_DIR/fallback"

if output="$(bash "$DETECTOR" "$TMP_DIR/empty")"; then
  echo "Expected no Berkeley Mono match, got '$output'" >&2
  exit 1
fi

echo "ok ghostty Berkeley Mono font detection"
