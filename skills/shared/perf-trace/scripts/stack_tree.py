#!/usr/bin/env python3
"""Fold collapsed stack samples into an indented duration tree.

Input is the collapsed format every common profiler can emit, one stack per
line, root first, frames separated by `;`, then a sample count:

    main;load;read_parquet 120
    main;score;evaluate 300

Sources: `py-spy record --format raw`, `perf script | stackcollapse-perf.pl`,
`samply` / `cargo flamegraph` collapsed output, or any folded-stacks file.

Each node prints its time (samples / rate), its share of the selected root,
and its frame. Children are sorted by time, and nodes below --min-pct are
dropped so the tree stays readable.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from typing import Iterable, TextIO

LINE = re.compile(r"^(?P<stack>.*\S)\s+(?P<count>\d+)$")


@dataclass
class Node:
    samples: int = 0
    children: dict[str, "Node"] = field(default_factory=dict)


def parse(lines: Iterable[str]) -> Node:
    root = Node()
    for raw in lines:
        match = LINE.match(raw.strip())
        if not match:
            continue
        count = int(match["count"])
        root.samples += count
        node = root
        for frame in match["stack"].split(";"):
            node = node.children.setdefault(frame, Node())
            node.samples += count
    return root


def focus(root: Node, pattern: str | None) -> tuple[str, Node]:
    """Return the first node, breadth first, whose frame contains `pattern`."""
    if not pattern:
        return "all samples", root
    queue = list(root.children.items())
    while queue:
        frame, node = queue.pop(0)
        if pattern in frame:
            return frame, node
        queue.extend(node.children.items())
    raise SystemExit(f"no frame contains {pattern!r}")


def render(label: str, top: Node, rate: float, min_pct: float, max_depth: int, out: TextIO) -> None:
    def line(prefix: str, frame: str, node: Node) -> str:
        seconds = node.samples / rate
        pct = 100.0 * node.samples / top.samples if top.samples else 0.0
        return f"{seconds:9.1f}s {pct:5.1f}%  {prefix}{frame}"

    def walk(node: Node, indent: str, depth: int) -> None:
        if depth >= max_depth:
            return
        kept = [
            (frame, child)
            for frame, child in sorted(node.children.items(), key=lambda item: -item[1].samples)
            if top.samples and 100.0 * child.samples / top.samples >= min_pct
        ]
        for index, (frame, child) in enumerate(kept):
            last = index == len(kept) - 1
            print(line(indent + ("└─ " if last else "├─ "), frame, child), file=out)
            walk(child, indent + ("   " if last else "│  "), depth + 1)

    print(line("", label, top), file=out)
    walk(top, "", 0)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", default="-", help="collapsed stacks file, or - for stdin")
    parser.add_argument("--rate", type=float, default=100.0, help="samples per second the profiler used")
    parser.add_argument("--focus", help="root the tree at the first frame containing this text")
    parser.add_argument("--min-pct", type=float, default=1.0, help="hide nodes below this share")
    parser.add_argument("--depth", type=int, default=12, help="maximum depth below the root")
    args = parser.parse_args(argv)

    stream = sys.stdin if args.path == "-" else open(args.path, encoding="utf-8", errors="replace")
    with stream:
        root = parse(stream)
    if root.samples == 0:
        print("no samples found", file=sys.stderr)
        return 1
    label, top = focus(root, args.focus)
    render(label, top, args.rate, args.min_pct, args.depth, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
