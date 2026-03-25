#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTAL_FEATURES="nix-command flakes"
FLAKE_REF="path:${SCRIPT_DIR}"

usage() {
  local exit_code="${1:-1}"
  cat >&2 <<'EOF'
Usage:
  ./bootstrap.sh install-dependencies
  ./bootstrap.sh <personal|work> [--dry-run] [--diff] [--overwrite]

Bootstrap is the supported macOS apply path for this repo.
It is safe to rerun after pulling changes or editing the flake.
Run it as your normal user. The script will prompt for sudo only for the
final darwin-rebuild switch step when a real apply needs root.

Flags:
  --dry-run  Build the target closure but do not switch or install missing prerequisites.
             Requires Nix to already be installed on the machine.
  --diff     Show a closure diff against the current system before switching.
  --overwrite
             Overwrite conflicting Home Manager managed files instead of creating
             `*.hm-backup` backups during activation. If `/etc/bashrc` or
             `/etc/zshrc` conflict, show a diff and prompt before replacing them.
  --help     Show this help text.
EOF
  exit "$exit_code"
}

COMMAND=""
ROLE=""
DRY_RUN=0
SHOW_DIFF=0
OVERWRITE=0
ETC_SHELL_CONFLICTS=()

darwin_config_name() {
  if (( OVERWRITE )); then
    printf '%s-overwrite\n' "$ROLE"
  else
    printf '%s\n' "$ROLE"
  fi
}

selected_apply_flags() {
  local flags=""

  if (( DRY_RUN )); then
    flags+=" --dry-run"
  fi
  if (( SHOW_DIFF )); then
    flags+=" --diff"
  fi
  if (( OVERWRITE )); then
    flags+=" --overwrite"
  fi

  printf '%s\n' "$flags"
}

selected_non_preview_flags() {
  local flags=""

  if (( OVERWRITE )); then
    flags+=" --overwrite"
  fi

  printf '%s\n' "$flags"
}

selected_diff_flags() {
  printf ' --diff%s\n' "$(selected_non_preview_flags)"
}

selected_dry_run_diff_flags() {
  printf ' --dry-run --diff%s\n' "$(selected_non_preview_flags)"
}

parse_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      install-dependencies)
        if [[ -n "$COMMAND" || -n "$ROLE" ]]; then
          echo "install-dependencies cannot be combined with another command or role." >&2
          usage 1
        fi
        COMMAND="install-dependencies"
        ;;
      personal|work)
        if [[ "$COMMAND" == "install-dependencies" || -n "$ROLE" ]]; then
          echo "Only one role may be specified." >&2
          usage 1
        fi
        COMMAND="apply"
        ROLE="$arg"
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --diff)
        SHOW_DIFF=1
        ;;
      --overwrite)
        OVERWRITE=1
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        echo "Unknown argument: $arg" >&2
        usage 1
        ;;
    esac
  done

  if [[ "$COMMAND" == "install-dependencies" ]]; then
    if (( DRY_RUN || SHOW_DIFF || OVERWRITE )); then
      echo "install-dependencies does not accept apply flags." >&2
      usage 1
    fi
    return
  fi

  if [[ "$ROLE" != "personal" && "$ROLE" != "work" ]]; then
    usage 1
  fi
}

require_darwin() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "bootstrap.sh currently supports macOS only." >&2
    exit 1
  fi
}

log() {
  printf '[bootstrap] %s\n' "$*"
}

normalize_root_home() {
  if [[ "$(id -u)" -eq 0 ]]; then
    export HOME=~root
  fi
}

load_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi

  local nix_daemon_profile="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  local nix_user_profile="$HOME/.nix-profile/etc/profile.d/nix.sh"

  if [[ -r "$nix_daemon_profile" ]]; then
    # shellcheck disable=SC1091
    source "$nix_daemon_profile"
  elif [[ -r "$nix_user_profile" ]]; then
    # shellcheck disable=SC1091
    source "$nix_user_profile"
  fi

  command -v nix >/dev/null 2>&1
}

ensure_nix() {
  if load_nix; then
    log "Nix is already available."
    return
  fi

  if (( DRY_RUN || SHOW_DIFF )); then
    local rerun_flags=""
    rerun_flags="$(selected_apply_flags)"

    cat >&2 <<EOF
Preview mode cannot continue until Nix is already installed.

Next steps:
  1. Run ./bootstrap.sh install-dependencies
  2. Then rerun ./bootstrap.sh ${ROLE}${rerun_flags}
EOF
    exit 1
  fi

  log "Installing Nix..."
  bash <(curl -fsSL https://nixos.org/nix/install) --daemon
  load_nix
}

load_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv)"
      break
    fi
  done

  command -v brew >/dev/null 2>&1
}

ensure_homebrew() {
  if load_homebrew; then
    log "Homebrew is already available."
    return
  fi

  if (( DRY_RUN )); then
    log "Homebrew is not installed. Dry-run will not install it automatically."
    return
  fi

  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_homebrew
}

build_system_closure() {
  local config_name
  config_name="$(darwin_config_name)"

  nix --extra-experimental-features "$EXPERIMENTAL_FEATURES" \
    build "${FLAKE_REF}#darwinConfigurations.${config_name}.system" \
    --no-link \
    --print-out-paths | tail -n 1
}

show_closure_diff() {
  local system_path="$1"
  local current_system="/run/current-system"

  if [[ ! -e "$current_system" ]]; then
    if (( DRY_RUN )); then
      cat >&2 <<EOF
[bootstrap] Cannot show a closure diff because there is no active nix-darwin system at $current_system.

This usually means this machine has not completed its first nix-darwin switch yet, so there is no baseline generation to compare against.

Next steps:
  1. Run ./bootstrap.sh ${ROLE}$(selected_non_preview_flags)
  2. Then rerun ./bootstrap.sh ${ROLE}$(selected_apply_flags)
EOF
    else
      cat >&2 <<EOF
[bootstrap] Cannot show a closure diff because there is no active nix-darwin system at $current_system.

This looks like the first nix-darwin apply on this machine. Bootstrap will continue without a diff and activate the new generation.

After this finishes, rerun ./bootstrap.sh ${ROLE}$(selected_diff_flags) or ./bootstrap.sh ${ROLE}$(selected_dry_run_diff_flags) to compare future changes against the active system.
EOF
    fi
    return
  fi

  log "Diffing $current_system -> $system_path"
  nix --extra-experimental-features "$EXPERIMENTAL_FEATURES" \
    store diff-closures "$current_system" "$system_path"
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo -- "$@"
  fi
}

generated_etc_shell_file() {
  local system_path="$1"
  local live_file="$2"
  printf '%s/etc/%s\n' "$system_path" "${live_file##*/}"
}

etc_shell_file_is_managed_link() {
  local live_file="$1"
  local managed_target="/etc/static/${live_file##*/}"

  [[ -L "$live_file" && "$(readlink -- "$live_file")" == "$managed_target" ]]
}

detect_etc_shell_conflicts() {
  local system_path="$1"
  local generated_file=""
  local live_file=""
  local etc_name=""

  ETC_SHELL_CONFLICTS=()

  for etc_name in bashrc zshrc; do
    generated_file="$system_path/etc/$etc_name"
    live_file="/etc/$etc_name"

    if etc_shell_file_is_managed_link "$live_file"; then
      continue
    fi

    if [[ -e "$generated_file" && -e "$live_file" ]] && ! cmp -s "$live_file" "$generated_file"; then
      ETC_SHELL_CONFLICTS+=("$live_file")
    fi
  done
}

prompt_for_etc_shell_overwrites() {
  local system_path="$1"
  local live_file=""
  local generated_file=""
  local response=""
  local diff_status=0

  for live_file in "${ETC_SHELL_CONFLICTS[@]}"; do
    generated_file="$(generated_etc_shell_file "$system_path" "$live_file")"

    cat >&2 <<EOF

[bootstrap] Diff for $live_file:
EOF
    if diff -u "$live_file" "$generated_file"; then
      :
    else
      diff_status=$?
      if (( diff_status > 1 )); then
        echo "[bootstrap] Failed to diff $live_file against the generated configuration." >&2
        exit 1
      fi
    fi

    printf '[bootstrap] Overwrite %s during activation? [y/N] ' "$live_file" >&2
    if ! IFS= read -r response; then
      echo >&2
      echo "[bootstrap] No response received. Aborting before changing /etc." >&2
      exit 1
    fi

    case "$response" in
      y|Y|yes|YES)
        ;;
      *)
        echo "[bootstrap] Aborting at user request. No /etc shell files were changed." >&2
        exit 1
        ;;
    esac
  done
}

prepare_etc_shell_backups() {
  local live_file=""
  local backup_file=""
  local -a existing_backups=()

  for live_file in "${ETC_SHELL_CONFLICTS[@]}"; do
    backup_file="${live_file}.before-nix-darwin"
    if [[ -e "$backup_file" ]]; then
      existing_backups+=("$backup_file")
    fi
  done

  if (( ${#existing_backups[@]} == 0 )); then
    return 0
  fi

  cat >&2 <<EOF
[bootstrap] Cannot auto-back up /etc shell files because backup targets already exist:
EOF
  printf '  %s\n' "${existing_backups[@]}" >&2
  cat >&2 <<EOF

Move or remove those backups, then rerun bootstrap.
EOF
  exit 1
}

backup_etc_shell_conflicts() {
  local live_file=""
  local backup_file=""

  prepare_etc_shell_backups

  for live_file in "${ETC_SHELL_CONFLICTS[@]}"; do
    backup_file="${live_file}.before-nix-darwin"
    log "Backing up $live_file to $backup_file before activation."
    run_as_root mv "$live_file" "$backup_file"
  done
}

remove_etc_shell_conflicts_for_overwrite() {
  local live_file=""

  for live_file in "${ETC_SHELL_CONFLICTS[@]}"; do
    log "Removing $live_file so nix-darwin can install the generated replacement without creating a .before-nix-darwin backup."
    run_as_root rm -f "$live_file"
  done
}

preflight_etc_shell_conflicts() {
  local system_path="$1"
  local generated_dir="$system_path/etc"

  detect_etc_shell_conflicts "$system_path"

  if (( ${#ETC_SHELL_CONFLICTS[@]} == 0 )); then
    return 0
  fi

  cat >&2 <<EOF
[bootstrap] nix-darwin will not overwrite existing /etc shell files whose contents differ from the generated configuration.

The following files already exist with non-generated content and would be replaced:
EOF
  printf '  %s\n' "${ETC_SHELL_CONFLICTS[@]}" >&2

  if (( OVERWRITE )); then
    cat >&2 <<EOF

Overwrite mode is enabled, so bootstrap will show a diff for each conflicting file and ask for confirmation before replacing it.
If you decline any prompt, bootstrap will abort without changing /etc.
EOF
    prompt_for_etc_shell_overwrites "$system_path"
    remove_etc_shell_conflicts_for_overwrite
  else
    cat >&2 <<EOF

Bootstrap will back up each conflicting file to *.before-nix-darwin and continue automatically.
EOF
    backup_etc_shell_conflicts
  fi

  cat >&2 <<EOF

Bootstrap will prompt for sudo again only for the final darwin-rebuild switch step.
The generated replacements already exist in:
  $generated_dir
EOF
}

switch_darwin_role() {
  local system_path="$1"
  local config_name
  config_name="$(darwin_config_name)"

  log "Applying Darwin role: $ROLE"
  if [[ "$(id -u)" -eq 0 ]]; then
    "$system_path/sw/bin/darwin-rebuild" switch --flake "${FLAKE_REF}#${config_name}"
  else
    sudo -- "$system_path/sw/bin/darwin-rebuild" switch --flake "${FLAKE_REF}#${config_name}"
  fi
}

parse_args "$@"
require_darwin
normalize_root_home

if [[ "$COMMAND" == "install-dependencies" ]]; then
  ensure_nix
  ensure_homebrew
  log "Dependencies installed."
  exit 0
fi

ensure_nix
ensure_homebrew

SYSTEM_PATH="$(build_system_closure)"

if [[ -z "$SYSTEM_PATH" ]]; then
  echo "Failed to build the Darwin system closure." >&2
  exit 1
fi

log "Built Darwin closure for $ROLE: $SYSTEM_PATH"

if (( OVERWRITE )); then
  log "Overwrite mode enabled. Home Manager will replace conflicting managed files without creating .hm-backup copies."
fi

if (( SHOW_DIFF )); then
  show_closure_diff "$SYSTEM_PATH"
fi

if (( DRY_RUN )); then
  log "Dry-run complete. No changes were applied."
  if ! load_homebrew; then
    log "Homebrew is not installed. A non-dry-run apply would install it before switching."
  fi
  exit 0
fi

preflight_etc_shell_conflicts "$SYSTEM_PATH"
switch_darwin_role "$SYSTEM_PATH"
log "Done."
