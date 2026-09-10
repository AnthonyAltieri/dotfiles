#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/clean-bootstrap-backups.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_HOME="$TMP_DIR/home"
GCROOT_DIR="$FAKE_HOME/.local/state/home-manager/gcroots/current-home"
STORE_TREE="$TMP_DIR/store/home-manager-files"

# Mimic the real layout: current-home/home-files is a symlink into the store.
mkdir -p "$GCROOT_DIR" "$STORE_TREE/.config/nvim"
printf 'managed zshrc\n' > "$STORE_TREE/.zshrc"
printf 'managed init\n' > "$STORE_TREE/.config/nvim/init.lua"
ln -s "$STORE_TREE" "$GCROOT_DIR/home-files"

# Backups of managed paths: one file, one directory.
mkdir -p "$FAKE_HOME/.config"
printf 'old zshrc\n' > "$FAKE_HOME/.zshrc.hm-backup"
mkdir -p "$FAKE_HOME/.config/nvim.hm-backup"
printf 'old init\n' > "$FAKE_HOME/.config/nvim.hm-backup/init.lua"

# Decoys that must survive: an unmanaged .hm-backup and the codex rules
# restore seed, neither of which appears in the home-files tree.
printf 'not managed\n' > "$FAKE_HOME/unrelated.hm-backup"
mkdir -p "$FAKE_HOME/.codex/rules"
printf 'seed\n' > "$FAKE_HOME/.codex/rules/default.rules.hm-backup"

dry_run_output="$(HOME="$FAKE_HOME" bash "$SCRIPT" --dry-run)"

if ! grep -q "Would remove $FAKE_HOME/.zshrc.hm-backup" <<<"$dry_run_output"; then
  echo "dry-run did not list the managed file backup" >&2
  exit 1
fi
if ! grep -q "Would remove $FAKE_HOME/.config/nvim.hm-backup" <<<"$dry_run_output"; then
  echo "dry-run did not list the managed directory backup" >&2
  exit 1
fi
if grep -q 'unrelated.hm-backup' <<<"$dry_run_output"; then
  echo "dry-run listed an unmanaged backup" >&2
  exit 1
fi
if [[ ! -f "$FAKE_HOME/.zshrc.hm-backup" ]]; then
  echo "dry-run removed a file" >&2
  exit 1
fi

# Without --include-etc the script never touches /etc or invokes sudo, so a
# real deletion pass is safe regardless of this machine's /etc state.
HOME="$FAKE_HOME" bash "$SCRIPT" >/dev/null

if [[ -e "$FAKE_HOME/.zshrc.hm-backup" || -e "$FAKE_HOME/.config/nvim.hm-backup" ]]; then
  echo "managed backups were not removed" >&2
  exit 1
fi
if [[ ! -f "$FAKE_HOME/unrelated.hm-backup" ]]; then
  echo "unmanaged backup was removed" >&2
  exit 1
fi
if [[ ! -f "$FAKE_HOME/.codex/rules/default.rules.hm-backup" ]]; then
  echo "codex rules restore seed was removed" >&2
  exit 1
fi
empty_output="$(HOME="$FAKE_HOME" bash "$SCRIPT")"
if ! grep -q 'No bootstrap backup files found' <<<"$empty_output"; then
  echo "second run did not report a clean state" >&2
  exit 1
fi

echo "ok clean-bootstrap-backups removes managed backups and spares decoys"
