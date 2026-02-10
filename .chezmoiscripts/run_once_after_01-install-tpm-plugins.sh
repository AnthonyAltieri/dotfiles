#!/bin/bash
set -euo pipefail

if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
    echo "Installing TPM plugins..."
    "$HOME/.tmux/plugins/tpm/bin/install_plugins"
fi
