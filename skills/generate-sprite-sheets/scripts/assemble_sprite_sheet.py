#!/usr/bin/env python3
"""Assemble reviewed sprite batches while enforcing a four-frame maximum."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from PIL import Image
except ImportError as error:
    raise SystemExit(
        "Pillow is required; use the same Python environment as imagegen post-processing"
    ) from error


MAX_FRAMES_PER_BATCH = 4
RESAMPLING = {
    "nearest": Image.Resampling.NEAREST,
    "lanczos": Image.Resampling.LANCZOS,
}


def positive_int(value: Any, field: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{field} must be a positive integer")
    return value


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read manifest: {error}") from error
    if not isinstance(value, dict):
        raise ValueError("manifest root must be an object")
    return value


def assemble(manifest_path: Path, output_path: Path) -> None:
    manifest = load_manifest(manifest_path)
    frame_width = positive_int(manifest.get("frame_width"), "frame_width")
    frame_height = positive_int(manifest.get("frame_height"), "frame_height")
    columns = positive_int(manifest.get("columns"), "columns")
    rows = positive_int(manifest.get("rows"), "rows")
    frame_total = columns * rows

    resample_name = manifest.get("resample", "nearest")
    if resample_name not in RESAMPLING:
        raise ValueError("resample must be 'nearest' or 'lanczos'")
    require_transparency = manifest.get("require_transparency", True)
    if not isinstance(require_transparency, bool):
        raise ValueError("require_transparency must be a boolean")

    batches = manifest.get("batches")
    if not isinstance(batches, list) or not batches:
        raise ValueError("batches must be a non-empty array")

    manifest_directory = manifest_path.parent
    output = Image.new(
        "RGBA", (columns * frame_width, rows * frame_height), (0, 0, 0, 0)
    )
    populated_targets: set[int] = set()

    for batch_index, batch in enumerate(batches):
        label = f"batches[{batch_index}]"
        if not isinstance(batch, dict):
            raise ValueError(f"{label} must be an object")
        frame_count = positive_int(batch.get("frame_count"), f"{label}.frame_count")
        if frame_count > MAX_FRAMES_PER_BATCH:
            raise ValueError(
                f"{label}.frame_count is {frame_count}; maximum is {MAX_FRAMES_PER_BATCH}"
            )
        layout_columns = positive_int(
            batch.get("layout_columns"), f"{label}.layout_columns"
        )
        layout_rows = positive_int(batch.get("layout_rows"), f"{label}.layout_rows")
        if layout_columns * layout_rows < frame_count:
            raise ValueError(f"{label} layout has fewer cells than frame_count")
        if layout_columns * layout_rows > MAX_FRAMES_PER_BATCH:
            raise ValueError(
                f"{label} layout contains more than {MAX_FRAMES_PER_BATCH} cells"
            )

        targets = batch.get("targets")
        if not isinstance(targets, list) or len(targets) != frame_count:
            raise ValueError(f"{label}.targets must contain exactly frame_count integers")
        if any(not isinstance(target, int) or isinstance(target, bool) for target in targets):
            raise ValueError(f"{label}.targets must contain integers")
        if len(set(targets)) != len(targets):
            raise ValueError(f"{label}.targets must not contain duplicates")
        for target in targets:
            if target < 0 or target >= frame_total:
                raise ValueError(f"{label} target {target} is outside the final sheet")
            if target in populated_targets:
                raise ValueError(f"final target {target} is populated more than once")

        raw_path = batch.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            raise ValueError(f"{label}.path must be a non-empty string")
        batch_path = Path(raw_path)
        if not batch_path.is_absolute():
            batch_path = manifest_directory / batch_path
        try:
            source = Image.open(batch_path)
            source.load()
        except OSError as error:
            raise ValueError(f"could not open {label} image {batch_path}: {error}") from error
        if require_transparency and source.mode not in ("RGBA", "LA"):
            raise ValueError(f"{label} must carry an alpha channel")
        source = source.convert("RGBA")
        if source.width % layout_columns or source.height % layout_rows:
            raise ValueError(f"{label} dimensions do not divide evenly across its layout")

        source_frame_width = source.width // layout_columns
        source_frame_height = source.height // layout_rows
        for source_index, target in enumerate(targets):
            source_column = source_index % layout_columns
            source_row = source_index // layout_columns
            frame = source.crop(
                (
                    source_column * source_frame_width,
                    source_row * source_frame_height,
                    (source_column + 1) * source_frame_width,
                    (source_row + 1) * source_frame_height,
                )
            )
            if require_transparency:
                alpha_extrema = frame.getchannel("A").getextrema()
                if alpha_extrema == (255, 255):
                    raise ValueError(f"{label} source frame {source_index} has no transparency")
                if alpha_extrema == (0, 0):
                    raise ValueError(f"{label} source frame {source_index} is empty")
            frame = frame.resize(
                (frame_width, frame_height), RESAMPLING[resample_name]
            )
            target_column = target % columns
            target_row = target // columns
            output.alpha_composite(
                frame, (target_column * frame_width, target_row * frame_height)
            )
            populated_targets.add(target)

    missing_targets = sorted(set(range(frame_total)) - populated_targets)
    if missing_targets:
        preview = ", ".join(str(target) for target in missing_targets[:8])
        suffix = "..." if len(missing_targets) > 8 else ""
        raise ValueError(f"final sheet is missing targets: {preview}{suffix}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output.save(output_path, format="PNG", optimize=True)
    print(
        f"wrote {output_path} ({output.width}x{output.height}, "
        f"{frame_total} frames, max {MAX_FRAMES_PER_BATCH} per batch)"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    try:
        assemble(args.manifest, args.out)
    except ValueError as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
