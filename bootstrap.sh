#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_homebrew() {
    if command -v brew &>/dev/null; then
        eval "$(brew shellenv)"
        return
    fi

    local brew_bin=""

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
        brew_bin="/opt/homebrew/bin/brew"
    elif [[ -x "/usr/local/bin/brew" ]]; then
        brew_bin="/usr/local/bin/brew"
    fi

    if [[ -n "$brew_bin" ]]; then
        eval "$("$brew_bin" shellenv)"
    fi
}

# Install Homebrew if missing (macOS)
if [[ "$(uname)" == "Darwin" ]] && ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

load_homebrew

# Install chezmoi if missing
if ! command -v chezmoi &>/dev/null; then
    brew install chezmoi
fi

# Initialize chezmoi with this repo as source and apply
echo "Applying dotfiles..."
chezmoi init --source "$SCRIPT_DIR" --apply --verbose --force
echo "Done."
