#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$ROOT/home/.config/zsh/config.zsh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BIN_DIR="$TMPDIR/bin"
HOME_DIR="$TMPDIR/home"

mkdir -p "$BIN_DIR" "$HOME_DIR"

cat >"$BIN_DIR/nvim" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN_DIR/nvim"

actual="$(
  HOME="$HOME_DIR" \
  PATH="$BIN_DIR:/usr/bin:/bin" \
  zsh -fc 'source "$1"; alias vim' _ "$CONFIG"
)"

if [[ "$actual" != "vim=nvim" ]]; then
  echo "expected vim alias to resolve to nvim" >&2
  echo "actual: $actual" >&2
  exit 1
fi
