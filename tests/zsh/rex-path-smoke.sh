#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home/.config/zsh" "$WORK/bin" "$WORK/rex bin"
: >"$WORK/home/.config/zsh/config.zsh"

# A brew stub that knows no packages keeps .zshrc from touching the real one.
printf '#!/usr/bin/env bash\nexit 1\n' >"$WORK/bin/brew"
chmod +x "$WORK/bin/brew"

# nix-darwin resets PATH before .zshrc runs, so start from a PATH without
# REX_BIN_DIR and check that .zshrc puts it first, exactly once.
HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" REX_BIN_DIR="$WORK/rex bin" \
  zsh -efc '
    source "$1"
    [[ "${path[1]}" == "$REX_BIN_DIR" ]]
    (( ${path[2,-1][(Ie)$REX_BIN_DIR]} == 0 ))
  ' _ "$ROOT/home/.zshrc"

# Outside Rex, .zshrc must not add an empty PATH entry.
HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" \
  zsh -efc '
    unset REX_BIN_DIR
    source "$1"
    (( ${path[(Ie)]} == 0 ))
  ' _ "$ROOT/home/.zshrc"

printf '%s\n' 'Rex PATH smoke test passed.'
