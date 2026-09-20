#!/usr/bin/env bash
# Unit tests of the bootstrap CLI, mocking only external process boundaries.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home" "$TMP_DIR/closure/sw/bin"
export TEST_LOG="$TMP_DIR/commands" TEST_CLOSURE="$TMP_DIR/closure"

cat > "$TMP_DIR/bin/boundary" <<'EOF'
#!/bin/bash
set -euo pipefail
command_name="${0##*/}"
case "$command_name" in
  uname)
    if [[ "$1" == "-s" ]]; then echo "$TEST_OS"; else echo "$TEST_ARCH"; fi
    ;;
  id)
    if [[ "$1" == "-u" ]]; then echo "${TEST_UID:-1000}"; else echo dotfiles; fi
    ;;
  nix)
    printf 'nix %s\n' "$*" >> "$TEST_LOG"
    if [[ "$3" == build ]]; then
      [[ "${TEST_BUILD_FAIL:-0}" == 0 ]] || exit 42
      echo "$TEST_CLOSURE"
    fi
    ;;
  brew|curl|sudo)
    printf '%s %s\n' "$command_name" "$*" >> "$TEST_LOG"
    [[ "$TEST_OS" == Darwin ]] || exit 43
    ;;
esac
EOF
chmod +x "$TMP_DIR/bin/boundary"
for command_name in uname id nix brew curl sudo; do
  ln -s boundary "$TMP_DIR/bin/$command_name"
done
cat > "$TEST_CLOSURE/activate" <<'EOF'
#!/bin/bash
printf 'activate backup=%s\n' "${HOME_MANAGER_BACKUP_EXT:-unset}" >> "$TEST_LOG"
exit "${TEST_ACTIVATE_FAIL:-0}"
EOF
chmod +x "$TEST_CLOSURE/activate"

run_bootstrap() {
  : > "$TEST_LOG"
  env PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" \
    XDG_STATE_HOME="$TMP_DIR/state" NIX_STATE_DIR="$TMP_DIR/nix-state" \
    USER=dotfiles LOGNAME=dotfiles TEST_OS="${TEST_OS:-Linux}" \
    TEST_ARCH="${TEST_ARCH:-x86_64}" \
    bash "$ROOT_DIR/bootstrap.sh" "$@" > "$TMP_DIR/output" 2>&1
}

assert_contains() {
  if ! grep -Fq -- "$2" "$1"; then
    printf 'Expected %s in %s\n' "$2" "$1" >&2
    cat "$1" >&2
    exit 1
  fi
}

assert_no_activation() {
  if grep -Eq '^(activate|brew|curl|sudo) ' "$TEST_LOG"; then
    cat "$TEST_LOG" >&2
    echo 'Unexpected activation or prerequisite installation' >&2
    exit 1
  fi
}

# Wrong CPU/role selection would build or install a different user's profile.
for role in personal work; do
  for arch in x86_64 aarch64; do
    suffix=linux
    [[ "$arch" != aarch64 ]] || suffix=aarch64-linux
    TEST_ARCH="$arch" run_bootstrap "$role" --dry-run
    assert_contains "$TEST_LOG" "#homeConfigurations.$role-$suffix.activationPackage --impure --no-link"
    assert_no_activation
  done
done
echo 'ok Linux role/architecture selection and dry-run isolation'

run_bootstrap personal
assert_contains "$TEST_LOG" 'activate backup=hm-backup'
HOME_MANAGER_BACKUP_EXT=inherited run_bootstrap work --overwrite
assert_contains "$TEST_LOG" '#homeConfigurations.work-linux-overwrite.activationPackage'
assert_contains "$TEST_LOG" 'activate backup=unset'
echo 'ok backup and overwrite activation policies'

run_bootstrap personal --diff --dry-run
assert_contains "$TMP_DIR/output" 'No active Home Manager generation'
assert_no_activation
mkdir -p "$TMP_DIR/state/home-manager/gcroots"
ln -s "$TEST_CLOSURE" "$TMP_DIR/state/home-manager/gcroots/current-home"
run_bootstrap personal --diff --dry-run
assert_contains "$TEST_LOG" "store diff-closures $TMP_DIR/state/home-manager/gcroots/current-home $TEST_CLOSURE"
assert_no_activation
echo 'ok closure diff and first-generation handling'

run_bootstrap install-dependencies
[[ ! -s "$TEST_LOG" ]]
echo 'ok installed Nix needs no Linux prerequisites or Homebrew'

if TEST_BUILD_FAIL=1 run_bootstrap personal; then
  echo 'Expected build failure to stop bootstrap' >&2
  exit 1
fi
assert_no_activation
if TEST_ACTIVATE_FAIL=44 run_bootstrap personal; then
  echo 'Expected activation failure to propagate' >&2
  exit 1
fi
echo 'ok failed builds prevent activation and failed activation propagates'

if TEST_ARCH=riscv64 run_bootstrap personal; then
  echo 'Expected unsupported architecture to fail' >&2
  exit 1
fi
assert_contains "$TMP_DIR/output" 'Unsupported Linux architecture'
[[ ! -s "$TEST_LOG" ]]
if TEST_UID=0 run_bootstrap personal; then
  echo 'Expected root invocation to fail before mutation' >&2
  exit 1
fi
assert_contains "$TMP_DIR/output" 'without sudo'
[[ ! -s "$TEST_LOG" ]]
echo 'ok unsupported architecture and root fail before mutation'

TEST_OS=Darwin run_bootstrap personal --overwrite --dry-run
assert_contains "$TEST_LOG" '#darwinConfigurations.personal-overwrite.system --impure --no-link'
assert_no_activation
echo 'ok macOS retains its Darwin preview path'
