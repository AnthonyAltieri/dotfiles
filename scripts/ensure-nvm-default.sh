#!/usr/bin/env bash
# Provision the user's default runtime without introducing another Node owner.
# nvm is sourced below and does not support nounset.
set -eo pipefail

if [[ -n "${DRY_RUN_CMD:-}" ]]; then
  echo 'Would ensure the nvm default Node version is installed'
  exit 0
fi

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
nvm_script="$NVM_DIR/nvm.sh"
if command -v brew >/dev/null 2>&1; then
  nvm_prefix="$(brew --prefix nvm 2>/dev/null || true)"
  if [[ -n "$nvm_prefix" && -s "$nvm_prefix/nvm.sh" ]]; then
    nvm_script="$nvm_prefix/nvm.sh"
  fi
fi

if [[ ! -s "$nvm_script" ]]; then
  echo 'Cannot provision Node: nvm is missing; check the Homebrew activation output' >&2
  exit 1
fi
source "$nvm_script" --no-use

if nvm use --silent default >/dev/null 2>&1; then
  node_version="$(node --version)"
  printf 'Using nvm default Node %s\n' "$node_version"
  exit 0
fi

if [[ -f "$NVM_DIR/alias/default" ]]; then
  # Resolve user aliases, stopping before nvm's cached LTS metadata. Passing
  # "default" to nvm install does not resolve it; resolving lts/* to a cached
  # version can leave default pointing at a newer, still missing release.
  selector=default
  seen='|'
  while [[ "$selector" != lts/* && -f "$NVM_DIR/alias/$selector" ]]; do
    if [[ "$seen" == *"|$selector|"* ]]; then
      echo 'Cannot provision Node: the nvm default alias contains a cycle' >&2
      exit 1
    fi
    seen="$seen$selector|"
    selector="$(cat "$NVM_DIR/alias/$selector")"
  done
  if [[ -z "$selector" || "$selector" == system ]]; then
    echo 'Cannot provision Node: the nvm default does not select an installable version' >&2
    exit 1
  fi
  printf 'Installing missing nvm default Node (%s)\n' "$selector"
  nvm install "$selector"
else
  echo 'Installing an LTS Node version as the nvm default'
  nvm install --lts
  nvm alias default "$(nvm current)"
fi

nvm use --silent default
node --version
