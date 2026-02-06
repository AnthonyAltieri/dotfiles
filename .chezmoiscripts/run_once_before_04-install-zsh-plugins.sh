#!/bin/bash
set -euo pipefail

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/F-Sy-H" ]; then
    echo "Installing F-Sy-H..."
    git clone https://github.com/z-shell/F-Sy-H.git "$ZSH_CUSTOM/plugins/F-Sy-H"
fi
