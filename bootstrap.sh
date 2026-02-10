#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install Homebrew if missing (macOS)
if [[ "$(uname)" == "Darwin" ]] && ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install chezmoi if missing
if ! command -v chezmoi &>/dev/null; then
    brew install chezmoi
fi

# Initialize chezmoi with this repo as source and apply
chezmoi init --source "$SCRIPT_DIR" --apply --verbose
