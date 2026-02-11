#!/bin/bash
set -euo pipefail

if ! command -v tsgo &>/dev/null; then
    echo "Installing tsgo (TypeScript native LSP)..."
    npm install -g @typescript/native-preview
fi
