#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/skills/claude/spawn-orchestrator/scripts"

# Unit tests for the headless Codex worker helper: event-stream status,
# auto-review denial extraction, and the resume thread-id guard. No Codex
# process is started; fixtures are trimmed from real codex-cli 0.153.4 output.
(cd "$SCRIPTS" && python3 -m unittest -q)

# The helper must at least parse and print usage without a codex binary.
python3 "$SCRIPTS/codex_worker.py" --help >/dev/null

echo "spawn-orchestrator worker smoke: ok"
