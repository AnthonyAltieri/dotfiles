#!/bin/bash
set -euo pipefail

if [ ! -d "$HOME/.bun" ]; then
    echo "Installing bun (latest)..."
    curl -fsSL https://bun.sh/install | bash
fi
