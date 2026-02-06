#!/bin/bash
set -euo pipefail

if ! command -v pnpm &>/dev/null; then
    echo "Installing pnpm (latest)..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
fi
