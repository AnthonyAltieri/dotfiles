---
name: generate-sprite-sheets
description: Generate or edit detailed game sprite sheets with the imagegen skill while limiting every image-generation or edit batch to at most four distinct frames. Use for character animation sheets, directional movement sheets, equipment layers, effects, tiles, or other aligned raster frame sets that need consistency, transparency, pivots, exact dimensions, and deterministic final assembly.
---

# Generate Sprite Sheets

Create sprite sheets through small, high-detail imagegen batches, then validate and assemble them deterministically.

## Required dependency

Read and follow the installed `imagegen` skill before any image generation or editing. This skill
orchestrates imagegen; it does not replace its tool, transparency, reference-image, inspection, or
save-path rules.

## Hard batch limit

- Request at most four distinct sprite frames in one imagegen call.
- Apply the same limit to edits, corrections, variants, and directional derivations.
- Never ask imagegen for a complete sheet containing more than four frames, even when the final
  sheet is small or the user asks to do it in one call.
- Split larger work into ordered batches before generating. A 64-frame sheet requires at least 16
  imagegen calls.
- Default to one facing and one animation mode per batch. Do not mix unrelated actions or camera
  angles merely to fill four slots.

## Workflow

1. Lock the final contract before prompting:
   - frame width and height;
   - rows, columns, frame order, and animation ranges;
   - camera angle, facing order, scale, silhouette, ground/pivot point, and padding;
   - palette, lighting, outline, transparency, and immutable reference details.
2. Enumerate every frame and partition the ordered list into batches of one to four. Prefer four
   consecutive frames from the same facing/action.
3. Prepare one guide canvas or reference crop per batch when alignment matters. Label every input
   image's role exactly as required by imagegen.
4. Use a 2x2 row-major layout for four frames by default. Use 1x1, 2x1, or 3x1 only when fewer
   frames materially benefit from that layout. Require equal cells, generous internal padding, no
   labels, no grid decoration, and no extra frames.
5. Repeat the complete invariants in every imagegen prompt. Identify each frame by cell and exact
   action phase. For transparent sprites, use imagegen's built-in-first chroma-key workflow and its
   installed removal helper.
6. Inspect every batch with `view_image` before assembly. Reject and regenerate a batch when it has
   an extra/missing frame, inconsistent scale, changed identity, clipped pixels, incorrect facing,
   mixed cell sizes, background leakage, or pivot drift. Do not repair a structurally wrong batch
   by stretching it into place.
7. Normalize only accepted batches to RGBA. Preserve hard pixel edges for pixel art. Use nearest
   resampling only when the source is already pixel-aligned; otherwise choose a deliberate
   high-quality downsample and inspect the result at native scale.
8. Write a manifest and run `scripts/assemble_sprite_sheet.py`. A manifest batch must declare no
   more than four source cells; the script rejects larger batches and incomplete/duplicate targets.
9. Inspect the assembled transparent sheet and a temporary reference composite at native scale and
   enlarged nearest-neighbor scale. Do not add review composites to the project unless requested.
10. Validate exact dimensions, mode, alpha, per-frame occupancy, frame order, silhouette, pivot
    stability, and animation wrapping before integrating the sheet.

## Prompt skeleton

```text
Use case: stylized-concept
Asset type: <sprite or equipment-layer> batch <N> of <total>
Input images: <roles>
Primary request: create exactly <1-4> frames, no more
Frame cells (row-major): 1) <phase>; 2) <phase>; 3) <phase>; 4) <phase>
Style/medium: <pixel art / painted raster / etc.>
Composition/framing: <layout>; equal cells; fixed scale; fixed pivot; generous padding
Constraints: preserve <identity and alignment invariants>; no labels; no grid decoration; no extra frames
Avoid: cropping, pose duplication, perspective drift, silhouette drift, background variation
```

For chroma-key output, append the exact flat-background constraints from the imagegen skill.

## Assembly manifest

Use paths relative to the manifest unless absolute paths are required:

```json
{
  "frame_width": 48,
  "frame_height": 96,
  "columns": 8,
  "rows": 8,
  "resample": "nearest",
  "require_transparency": true,
  "batches": [
    {
      "path": "batch-01.png",
      "frame_count": 4,
      "layout_columns": 2,
      "layout_rows": 2,
      "targets": [0, 1, 2, 3]
    }
  ]
}
```

`targets` are zero-based row-major cells in the final sheet. Include every target exactly once.
Run with the same Pillow-capable Python environment used for imagegen post-processing:

```bash
python3 scripts/assemble_sprite_sheet.py manifest.json --out final-sheet.png
```

## Completion report

Report the final sheet path, exact contract, batch count, imagegen prompts, assembly manifest path,
validation results, and whether temporary composites or rejected batches were retained.
