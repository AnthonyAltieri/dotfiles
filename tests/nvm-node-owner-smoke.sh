#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/dotfiles-nvm-node-owner.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

BREWFILE="$(
  XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --impure --no-write-lock-file --raw \
    "path:${ROOT_DIR}#darwinConfigurations.personal.config.homebrew.brewfile"
)"

if ! rg -Fqx 'brew "nvm"' <<<"$BREWFILE"; then
  printf 'expected the generated Brewfile to install nvm\n' >&2
  exit 1
fi

PACKAGE_NAMES="$(
  XDG_CACHE_HOME="$TMP_DIR/nix-cache" nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --impure --no-write-lock-file --json \
    --apply 'packages: builtins.map (package: package.name or "") packages' \
    "path:${ROOT_DIR}#darwinConfigurations.personal.config.home-manager.users.${USER}.home.packages"
)"

if jq -e 'any(.[]; startswith("nodejs-"))' <<<"$PACKAGE_NAMES" >/dev/null; then
  printf 'expected nvm, not Home Manager, to own interactive Darwin Node versions\n' >&2
  exit 1
fi

FAKE_HOME="$TMP_DIR/home"
FAKE_BIN="$TMP_DIR/bin"
FAKE_NVM_PREFIX="$TMP_DIR/nvm"
NVM_CALLS="$TMP_DIR/nvm-calls"
NVMRC_PROJECT_ROOT="$TMP_DIR/nvmrc-project"
NVMRC_PROJECT="$NVMRC_PROJECT_ROOT/child"
NODE_VERSION_PROJECT_ROOT="$TMP_DIR/node-version-project"
NODE_VERSION_PROJECT="$NODE_VERSION_PROJECT_ROOT/child"

mkdir -p \
  "$FAKE_HOME/.config/zsh" \
  "$FAKE_BIN" \
  "$FAKE_NVM_PREFIX" \
  "$NVMRC_PROJECT" \
  "$NODE_VERSION_PROJECT"

: >"$FAKE_HOME/.config/zsh/config.zsh"
printf '20.19.5\n' >"$NVMRC_PROJECT_ROOT/.nvmrc"
printf '22.22.2\n' >"$NODE_VERSION_PROJECT_ROOT/.node-version"

cat >"$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--prefix" && "${2:-}" == "nvm" ]]; then
  printf '%s\n' "$TEST_NVM_PREFIX"
  exit 0
fi
exit 1
EOF
chmod +x "$FAKE_BIN/brew"

cat >"$FAKE_NVM_PREFIX/nvm.sh" <<'EOF'
nvm() {
  if [[ "${1:-}" != "use" ]]; then
    printf 'unexpected nvm command: %s\n' "$*" >&2
    return 1
  fi

  shift
  [[ "${1:-}" == "--silent" ]] && shift

  if (( $# == 0 )); then
    printf 'nvmrc:%s\n' "$(<../.nvmrc)" >>"$TEST_NVM_CALLS"
  else
    printf 'node-version:%s\n' "$1" >>"$TEST_NVM_CALLS"
  fi
}
EOF

HOME="$FAKE_HOME" \
PATH="$FAKE_BIN:/usr/bin:/bin" \
TEST_NVM_CALLS="$NVM_CALLS" \
TEST_NVM_PREFIX="$FAKE_NVM_PREFIX" \
zsh -f -c '
  cd "$1"
  source "$2"
  cd "$3"
' _ "$NVMRC_PROJECT" "$ROOT_DIR/home/.zshrc" "$NODE_VERSION_PROJECT"

EXPECTED_CALLS=$'nvmrc:20.19.5\nnode-version:22.22.2'
if [[ "$(<"$NVM_CALLS")" != "$EXPECTED_CALLS" ]]; then
  printf 'expected nvm to select both project version-file conventions\n' >&2
  printf 'actual calls:\n%s\n' "$(<"$NVM_CALLS")" >&2
  exit 1
fi

printf 'ok nvm owns Darwin Node selection for .nvmrc and .node-version projects\n'
