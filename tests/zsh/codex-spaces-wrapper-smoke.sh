#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$ROOT/home/.config/zsh/functions/codex-spaces-wrapper.zsh"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BIN_DIR="$TMPDIR/bin"
CURRENT_REPO="$TMPDIR/current-repo"
REPO_A="$TMPDIR/repo-a"
REPO_B="$TMPDIR/repo-b"
REPO_C="$TMPDIR/repo-collision"
REPO_D="$TMPDIR/repo-remote-collision"
SINGLE_TARGET="$TMPDIR/single-target"
MULTI_TARGET="$TMPDIR/multi-target"
FAKE_CODEX_LOG="$TMPDIR/fake-codex.log"
FAKE_SPACES_LOG="$TMPDIR/fake-spaces.log"
STDOUT_LOG="$TMPDIR/stdout.log"
STDERR_LOG="$TMPDIR/stderr.log"

mkdir -p "$BIN_DIR" "$CURRENT_REPO" "$REPO_A" "$REPO_B" "$REPO_C" "$REPO_D" "$SINGLE_TARGET" "$MULTI_TARGET"

cat >"$BIN_DIR/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_CODEX_LOG"
EOF
chmod +x "$BIN_DIR/codex"

cat >"$BIN_DIR/spaces" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$@" >"$FAKE_SPACES_LOG"

repos=()
if [[ "${1:-}" == "create" ]]; then
  shift
fi
while (($#)); do
  case "$1" in
    --json)
      shift
      ;;
    --base-dir)
      shift 2
      ;;
    --name|--branch)
      shift 2
      ;;
    *)
      repos+=("$1")
      shift
      ;;
  esac
done

if ((${#repos[@]} == 1)); then
  printf '{"workspace_dir":"%s","repos":[{"repo_name":"%s","worktree_path":"%s"}]}\n' \
    "$MULTI_TARGET" \
    "$(basename "${repos[0]}")" \
    "$SINGLE_TARGET"
  exit 0
fi

printf '{"workspace_dir":"%s","repos":[{"repo_name":"%s","worktree_path":"%s"},{"repo_name":"%s","worktree_path":"%s"}]}\n' \
  "$MULTI_TARGET" \
  "$(basename "${repos[0]}")" \
  "$TMPDIR/unused-a" \
  "$(basename "${repos[1]}")" \
  "$TMPDIR/unused-b"
EOF
chmod +x "$BIN_DIR/spaces"

cat >"$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

repo="${FAKE_CURRENT_REPO:-}"
if (($# >= 2)) && [[ "$1" == "-C" ]]; then
  repo="$2"
  shift 2
fi

case "$1" in
  rev-parse)
    if [[ "${2:-}" == "--show-toplevel" ]]; then
      [[ -n "$repo" && -d "$repo" ]] || exit 128
      cd "$repo"
      pwd
      exit 0
    fi
    ;;
  show-ref)
    if [[ "${2:-}" == "--verify" && "${3:-}" == "--quiet" ]]; then
      branch_name="${4#refs/heads/}"
      if grep -Fxq -- "$branch_name" "$repo/.fake-local-branches" 2>/dev/null; then
        exit 0
      fi
      exit 1
    fi
    ;;
  for-each-ref)
    cat "$repo/.fake-remote-branches" 2>/dev/null || true
    exit 0
    ;;
esac

echo "unexpected git invocation: $*" >&2
exit 99
EOF
chmod +x "$BIN_DIR/git"

run_wrapper() {
  : >"$FAKE_CODEX_LOG"
  : >"$FAKE_SPACES_LOG"
  : >"$STDOUT_LOG"
  : >"$STDERR_LOG"

  FAKE_CURRENT_REPO="$CURRENT_REPO" \
  FAKE_CODEX_LOG="$FAKE_CODEX_LOG" \
  FAKE_SPACES_LOG="$FAKE_SPACES_LOG" \
  SINGLE_TARGET="$SINGLE_TARGET" \
  MULTI_TARGET="$MULTI_TARGET" \
  TMPDIR="$TMPDIR" \
  PATH="$BIN_DIR:$PATH" \
  zsh -fc 'source "$1"; shift; codex "$@"' _ "$WRAPPER" "$@" >"$STDOUT_LOG" 2>"$STDERR_LOG"
}

assert_lines() {
  local file="$1"
  shift
  local -a expected=("$@")
  local -a actual=()

  if [[ -s "$file" ]]; then
    mapfile -t actual <"$file"
  fi

  if [[ "${actual[*]-}" != "${expected[*]-}" ]]; then
    echo "unexpected file contents for $file" >&2
    echo "expected:" >&2
    printf '  %s\n' "${expected[@]}" >&2
    echo "actual:" >&2
    printf '  %s\n' "${actual[@]}" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local needle="$2"

  grep -Fq -- "$needle" "$file" || {
    echo "expected to find '$needle' in $file" >&2
    cat "$file" >&2
    exit 1
  }
}

printf '%s\n' 'taken-local' >"$REPO_C/.fake-local-branches"
printf '%s\n' 'origin/taken-remote' >"$REPO_D/.fake-remote-branches"

run_wrapper --name passthrough
assert_lines "$FAKE_SPACES_LOG"
assert_lines "$FAKE_CODEX_LOG" --name passthrough

run_wrapper --spaces
assert_lines "$FAKE_SPACES_LOG" create --json "$CURRENT_REPO"
assert_lines "$FAKE_CODEX_LOG" -C "$SINGLE_TARGET"

run_wrapper --spaces "$REPO_A" "$REPO_B"
assert_lines "$FAKE_SPACES_LOG" create --json "$REPO_A" "$REPO_B"
assert_lines "$FAKE_CODEX_LOG" -C "$MULTI_TARGET"

run_wrapper --spaces "$REPO_A" --name api-cleanup
assert_lines "$FAKE_SPACES_LOG" create --json --name api-cleanup --branch api-cleanup "$REPO_A"
assert_lines "$FAKE_CODEX_LOG" -C "$SINGLE_TARGET"

run_wrapper --name api-cleanup --spaces "$REPO_A"
assert_lines "$FAKE_SPACES_LOG" create --json --name api-cleanup --branch api-cleanup "$REPO_A"
assert_lines "$FAKE_CODEX_LOG" -C "$SINGLE_TARGET"

run_wrapper --spaces "$REPO_A" -- --model gpt-5.4
assert_lines "$FAKE_SPACES_LOG" create --json "$REPO_A"
assert_lines "$FAKE_CODEX_LOG" -C "$SINGLE_TARGET" --model gpt-5.4

if run_wrapper --spaces "$REPO_C" --name taken-local; then
  echo "expected local branch collision to fail" >&2
  exit 1
fi
assert_lines "$FAKE_SPACES_LOG"
assert_contains "$STDERR_LOG" 'branch name already exists: taken-local'
assert_contains "$STDERR_LOG" "$REPO_C"

if run_wrapper --spaces "$REPO_D" --name taken-remote; then
  echo "expected remote branch collision to fail" >&2
  exit 1
fi
assert_lines "$FAKE_SPACES_LOG"
assert_contains "$STDERR_LOG" 'branch name already exists: taken-remote'
assert_contains "$STDERR_LOG" "$REPO_D"

if run_wrapper --spaces "$REPO_A" --model gpt-5.4; then
  echo "expected unsupported pre--- flag to fail" >&2
  exit 1
fi
assert_lines "$FAKE_SPACES_LOG"
assert_contains "$STDERR_LOG" 'unsupported wrapper argument before `--`: --model'
assert_contains "$STDERR_LOG" 'usage: codex [--name <workspace-name>] --spaces'

echo "Codex spaces wrapper smoke test passed"
