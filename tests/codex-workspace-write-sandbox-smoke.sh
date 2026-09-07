#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t codex-sandbox-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# The merge script needs tomli-w, which the flake supplies to the activation
# step; locally, fall back to a nix shell when python3 lacks it.
if python3 -c 'import tomli_w' 2> /dev/null; then
  PYTHON=(python3)
else
  PYTHON=(
    nix shell --impure
    --expr 'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.python3.withPackages (p: [ p.tomli-w ])'
    --command python3
  )
fi

CONFIG="$WORK/config.toml"
cat > "$CONFIG" <<'TOML'
model = "gpt-6-astra"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
writable_roots = ["/home/tester/local-only"]

[mcp_servers.linear]
url = "https://mcp.linear.app/mcp"
TOML
chmod 600 "$CONFIG"

"${PYTHON[@]}" "$ROOT/scripts/merge-codex-workspace-write-sandbox.py" "$CONFIG" \
  '{"network_access": true, "writable_roots": ["/home/tester/.cache/bazel", "/var/run/docker.sock", "/home/tester/local-only"]}'

"${PYTHON[@]}" - "$CONFIG" <<'PY'
import os
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    config = tomllib.load(config_file)

assert config["model"] == "gpt-6-astra"
assert config["sandbox_mode"] == "workspace-write"
assert config["mcp_servers"]["linear"]["url"] == "https://mcp.linear.app/mcp"
assert config["sandbox_workspace_write"]["network_access"] is True
assert config["sandbox_workspace_write"]["writable_roots"] == [
    "/home/tester/local-only",
    "/home/tester/.cache/bazel",
    "/var/run/docker.sock",
]
assert os.stat(sys.argv[1]).st_mode & 0o777 == 0o600
PY

# Re-running is idempotent: no duplicate roots.
"${PYTHON[@]}" "$ROOT/scripts/merge-codex-workspace-write-sandbox.py" "$CONFIG" \
  '{"writable_roots": ["/var/run/docker.sock"]}'
if [[ "$(grep -c 'docker.sock' "$CONFIG")" != "1" ]]; then
  echo "Expected a single docker.sock root after re-merge" >&2
  exit 1
fi

# A missing config is created with only the declared keys.
"${PYTHON[@]}" "$ROOT/scripts/merge-codex-workspace-write-sandbox.py" "$WORK/fresh/config.toml" \
  '{"network_access": false, "writable_roots": []}'
grep -Fq 'network_access = false' "$WORK/fresh/config.toml"

# Relative roots are rejected: resolution against the home directory is the
# Nix module's job, so the script refuses to guess.
cp "$CONFIG" "$WORK/original.toml"
if "${PYTHON[@]}" "$ROOT/scripts/merge-codex-workspace-write-sandbox.py" "$CONFIG" \
  '{"writable_roots": [".cache/bazel"]}' > "$WORK/stdout" 2> "$WORK/stderr"
then
  echo "Expected a relative writable root to fail" >&2
  exit 1
fi
cmp "$WORK/original.toml" "$CONFIG"

echo "Codex workspace-write sandbox merge smoke test passed."
