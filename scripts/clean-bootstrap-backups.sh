#!/usr/bin/env bash

# Remove the backup files a non-overwrite bootstrap run leaves behind:
#   - <managed-path>.hm-backup copies Home Manager creates next to every
#     managed file it had to replace (backupFileExtension = "hm-backup");
#   - /etc/{bashrc,zshrc}.before-nix-darwin copies bootstrap creates before
#     nix-darwin activation. These also block the next conflicting bootstrap,
#     which refuses to overwrite an existing backup.
#
# Candidates are derived from the active Home Manager generation's
# home-files tree, so only backups of paths this repo manages are touched.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/clean-bootstrap-backups.sh [--dry-run] [--include-etc]

  --dry-run      List the backup files that would be removed without
                 removing anything. Never invokes sudo.
  --include-etc  Also remove /etc/{bashrc,zshrc}.before-nix-darwin, which
                 requires sudo. Without this flag /etc is never touched;
                 existing /etc backups are only reported.
EOF
}

log() {
  printf '[clean-bootstrap-backups] %s\n' "$1"
}

DRY_RUN=0
INCLUDE_ETC=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=1
      ;;
    --include-etc)
      INCLUDE_ETC=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

HOME_FILES_TREE="$HOME/.local/state/home-manager/gcroots/current-home/home-files"
if [[ ! -e "$HOME_FILES_TREE" ]]; then
  log "No active Home Manager generation found at $HOME_FILES_TREE."
  log "Run bootstrap first; without an applied generation there is nothing to clean."
  exit 1
fi

home_backups=()
while IFS= read -r -d '' managed_path; do
  relative_path="${managed_path#"$HOME_FILES_TREE"/}"
  backup_path="$HOME/$relative_path.hm-backup"
  if [[ -e "$backup_path" || -L "$backup_path" ]]; then
    home_backups+=("$backup_path")
  fi
done < <(find -L "$HOME_FILES_TREE" -mindepth 1 -print0)

etc_backups=()
for etc_backup in /etc/bashrc.before-nix-darwin /etc/zshrc.before-nix-darwin; do
  if [[ -e "$etc_backup" ]]; then
    etc_backups+=("$etc_backup")
  fi
done

if (( ! INCLUDE_ETC )) && (( ${#etc_backups[@]} > 0 )); then
  for etc_backup in "${etc_backups[@]}"; do
    log "Leaving $etc_backup in place (rerun with --include-etc to remove it)."
  done
  etc_backups=()
fi

if (( ${#home_backups[@]} == 0 && ${#etc_backups[@]} == 0 )); then
  log "No bootstrap backup files found."
  exit 0
fi

for backup_path in ${home_backups[@]+"${home_backups[@]}"} ${etc_backups[@]+"${etc_backups[@]}"}; do
  if (( DRY_RUN )); then
    log "Would remove $backup_path"
  else
    log "Removing $backup_path"
  fi
done

if (( DRY_RUN )); then
  exit 0
fi

for backup_path in ${home_backups[@]+"${home_backups[@]}"}; do
  rm -rf "$backup_path"
done

if (( ${#etc_backups[@]} > 0 )); then
  log "Removing /etc backups requires sudo."
  sudo rm -f "${etc_backups[@]}"
fi

log "Done."
