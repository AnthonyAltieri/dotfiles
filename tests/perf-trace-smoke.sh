#!/usr/bin/env bash
# Smoke test for skills/shared/perf-trace/scripts/stack_tree.py.
#
# Bugs this catches: samples not summed into parent frames, children not
# sorted by time, --focus not re-rooting shares at the chosen frame, and
# --min-pct not hiding small nodes.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/shared/perf-trace/scripts/stack_tree.py"

fail() {
  echo "$1" >&2
  exit 1
}

stacks='<module> (job.py:9);main (job.py:5);load (job.py:2) 50
<module> (job.py:9);main (job.py:6);score (job.py:3);evaluate (model.py:10) 140
<module> (job.py:9);main (job.py:6);score (job.py:3);fit (model.py:20) 10
<module> (job.py:9);main (job.py:6);score (job.py:3);log (job.py:4) 1'

out="$(printf '%s\n' "$stacks" | python3 "$SCRIPT" --rate 50 --focus score)"
expected='      3.0s 100.0%  score (job.py:3)
      2.8s  92.7%  ├─ evaluate (model.py:10)
      0.2s   6.6%  └─ fit (model.py:20)'
[[ "$out" == "$expected" ]] || fail "Unexpected focused tree:
$out"

out="$(printf '%s\n' "$stacks" | python3 "$SCRIPT" --rate 50 --min-pct 30 | sed -n 1,3p)"
expected='      4.0s 100.0%  all samples
      4.0s 100.0%  └─ <module> (job.py:9)
      3.0s  75.1%     └─ main (job.py:6)'
[[ "$out" == "$expected" ]] || fail "Unexpected whole tree:
$out"

echo "perf-trace smoke: ok"
