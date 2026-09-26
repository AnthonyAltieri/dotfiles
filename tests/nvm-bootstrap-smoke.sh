#!/usr/bin/env bash
# Unit checks at the activation/third-party package-manager boundary.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An absent activation is a no-op, reproducing bootstrap's previous behavior.
XDG_CACHE_HOME="$WORK/cache" nix --extra-experimental-features 'nix-command flakes' \
  eval --impure --no-write-lock-file --raw \
  --apply 'entries: if entries ? dotfilesNvmDefault then entries.dotfilesNvmDefault.data else ""' \
  "path:$ROOT#darwinConfigurations.personal.config.home-manager.users.${USER}.home.activation" \
  > "$WORK/activation.sh"
mkdir -p "$WORK/bin" "$WORK/nvm"
cat > "$WORK/bin/brew" <<'BREW'
#!/usr/bin/env bash
[[ "$*" == '--prefix nvm' ]] || exit 1
printf '%s\n' "$TEST_NVM_PREFIX"
BREW
chmod +x "$WORK/bin/brew"

# nvm is a sourced third-party package manager. This fixture records its
# public commands without downloading Node or touching the caller's runtime.
cat > "$WORK/nvm/nvm.sh" <<'NVM'
[[ "${1:-}" == '--no-use' ]] || exit 1
mkdir -p "$NVM_DIR/alias" "$NVM_DIR/bin"
nvm() {
  case "$1" in
    use)
      [[ -f "$NVM_DIR/installed" ]] || return 3
      export PATH="$NVM_DIR/bin:$PATH"
      ;;
    install)
      shift
      printf '%s\n' "$*" >> "$NVM_DIR/downloads"
      [[ "${TEST_INSTALL_FAILURE:-0}" == 0 ]] || return 19
      case "$*" in 'lts/jod'|'--lts') ;; *) return 3 ;; esac
      printf '#!/bin/sh\nprintf "v22.1.0\n"\n' > "$NVM_DIR/bin/node"
      chmod +x "$NVM_DIR/bin/node"
      touch "$NVM_DIR/installed"
      export PATH="$NVM_DIR/bin:$PATH"
      ;;
    current) printf 'v22.1.0\n' ;;
    alias)
      [[ "$2" == default ]] || return 1
      printf '%s\n' "$3" > "$NVM_DIR/alias/default"
      ;;
    *) printf 'unexpected nvm command: %s\n' "$*" >&2; return 1 ;;
  esac
}
NVM

run_activation() {
  env HOME="$case_home" NVM_DIR="$case_home/.nvm" \
    PATH="$WORK/bin:/usr/bin:/bin" TEST_NVM_PREFIX="$WORK/nvm" \
    DRY_RUN_CMD="${dry_run:-}" TEST_INSTALL_FAILURE="${install_failure:-0}" \
    bash "$WORK/activation.sh"
}

cases="${1:-missing-lts installed fresh dry-run failure}"
for scenario in $cases; do
  case_home="$WORK/$scenario"
  mkdir -p "$case_home/.nvm/alias/lts"
  printf 'lts/jod\n' > "$case_home/.nvm/alias/default"
  # Cached LTS metadata must not pin the install to an obsolete release.
  printf 'v22.0.0\n' > "$case_home/.nvm/alias/lts/jod"
  dry_run=''
  install_failure=0
  case "$scenario" in
    missing-lts)
      run_activation
      if [[ ! -f "$case_home/.nvm/installed" ]]; then
        echo "bootstrap left nvm's default runtime missing" >&2
        exit 1
      fi
      [[ "$(cat "$case_home/.nvm/downloads")" == lts/jod ]]
      [[ "$(cat "$case_home/.nvm/alias/default")" == lts/jod ]]
      ;;
    installed)
      mkdir -p "$case_home/.nvm/bin"
      printf '#!/bin/sh\nprintf "v22.0.0\n"\n' > "$case_home/.nvm/bin/node"
      chmod +x "$case_home/.nvm/bin/node"
      touch "$case_home/.nvm/installed"
      run_activation
      [[ ! -e "$case_home/.nvm/downloads" ]]
      [[ "$(cat "$case_home/.nvm/alias/default")" == lts/jod ]]
      ;;
    fresh)
      rm "$case_home/.nvm/alias/default"
      run_activation
      [[ "$(cat "$case_home/.nvm/downloads")" == --lts ]]
      [[ "$(cat "$case_home/.nvm/alias/default")" == v22.1.0 ]]
      ;;
    dry-run)
      dry_run=echo
      run_activation
      [[ ! -e "$case_home/.nvm/bin" ]]
      [[ ! -e "$case_home/.nvm/downloads" ]]
      ;;
    failure)
      install_failure=1
      if run_activation; then
        echo 'bootstrap accepted a failed Node installation' >&2
        exit 1
      fi
      [[ ! -e "$case_home/.nvm/installed" ]]
      [[ "$(cat "$case_home/.nvm/alias/default")" == lts/jod ]]
      ;;
    *) echo "unknown scenario: $scenario" >&2; exit 2 ;;
  esac
  printf 'ok nvm bootstrap %s\n' "$scenario"
done
