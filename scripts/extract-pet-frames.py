#!/usr/bin/env python3
"""Extract the existing fatfish animation frames from their canonical RGBA sheet.

Requires Pillow. Run from any directory:
  python scripts/extract-pet-frames.py --backup-dir /path/to/original-frame-backup
  python scripts/extract-pet-frames.py --verify-only

The source is a sibling checkout by default; use --source to override its path.
No background removal, resizing, recoloring, or image generation is performed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from PIL import Image


PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = (
    PROJECT.parent
    / "大肥鱼皮肤源码"
    / "deepseek-fat-fish-codex-pet-main"
    / "deepseek-fat-fish"
    / "spritesheet.webp"
)
SOURCE_SHA256 = "77a048aef03f310ef33ffd38916c9da3495851a100266dd6bfbdc25502dca6ed"
CELL = (192, 208)
SHEET_SIZE = (1536, 2288)
# Zero-based (row, number of consecutive columns). The mappings were confirmed
# by RGB matching all 88 tiles against the old frames' remaining opaque pixels.
STATES = {"idle": (0, 6), "hover": (4, 5), "working": (7, 6), "success": (8, 6)}


def alpha_stats(image: Image.Image) -> dict[str, int]:
    red, green, blue, alpha = image.split()
    histogram = alpha.histogram()
    white = sum(
        a >= 240 and min(r, g, b) >= 185 and max(r, g, b) - min(r, g, b) <= 50
        for r, g, b, a in zip(
            red.tobytes(), green.tobytes(), blue.tobytes(), alpha.tobytes()
        )
    )
    return {
        "transparent_pixels": histogram[0],
        "soft_edge_pixels": sum(histogram[1:255]),
        "opaque_pixels": histogram[255],
        "opaque_white_pixels": white,
    }


def canonical_frames(source: Path) -> dict[str, Image.Image]:
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError("Source hash differs from the audited fatfish RGBA sheet; refusing to substitute another character or revision.")
    with Image.open(source) as original:
        if original.size != SHEET_SIZE or original.mode != "RGBA":
            raise ValueError(f"Expected RGBA sheet {SHEET_SIZE}, got {original.mode} {original.size}")
        sheet = original.copy()
    frames = {}
    for state, (row, count) in STATES.items():
        for column in range(count):
            name = f"fatfish-{state}-{column}.webp"
            frame = sheet.crop(
                (column * CELL[0], row * CELL[1], (column + 1) * CELL[0], (row + 1) * CELL[1])
            )
            if alpha_stats(frame)["soft_edge_pixels"] == 0:
                raise ValueError(f"Canonical frame unexpectedly lost soft transparency: {name}")
            frames[name] = frame
    return frames


def verify(folder: Path, frames: dict[str, Image.Image]) -> dict:
    report = {"source_sha256": SOURCE_SHA256, "size": list(CELL), "frames": len(frames), "exact_rgba_match": True, "states": {}}
    for state, (_, count) in STATES.items():
        expected_names = {f"fatfish-{state}-{i}.webp" for i in range(count)}
        actual_names = {p.name for p in folder.glob(f"fatfish-{state}-*.webp")}
        if actual_names != expected_names:
            raise ValueError(f"Unexpected frame set for {state}: {sorted(actual_names)}")
        stats = []
        for name in sorted(expected_names):
            with Image.open(folder / name) as encoded:
                if encoded.format != "WEBP" or getattr(encoded, "n_frames", 1) != 1:
                    raise ValueError(f"Expected a single-frame WebP: {name}")
                actual = encoded.convert("RGBA")
            expected = frames[name]
            if actual.size != CELL or actual.tobytes() != expected.tobytes():
                raise ValueError(f"Pixels differ from the canonical RGBA tile: {name}")
            stats.append(alpha_stats(actual))
        report["states"][state] = {
            "count": count,
            "soft_edge_pixels_min_max": [min(s["soft_edge_pixels"] for s in stats), max(s["soft_edge_pixels"] for s in stats)],
            "opaque_white_pixels_min_max": [min(s["opaque_white_pixels"] for s in stats), max(s["opaque_white_pixels"] for s in stats)],
        }
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--backup-dir", type=Path, help="Required when extracting. Existing backup files are kept unchanged.")
    parser.add_argument("--verify-only", action="store_true", help="Check the installed frames without writing or backing up files.")
    args = parser.parse_args()
    if not args.verify_only and args.backup_dir is None:
        parser.error("--backup-dir is required before replacing any frames")

    destination = PROJECT / "Resources" / "pet"
    frames = canonical_frames(args.source.expanduser().resolve())
    if args.verify_only:
        print(json.dumps(verify(destination, frames), ensure_ascii=False, indent=2))
        return

    backup = args.backup_dir.expanduser().resolve()
    if backup == destination.resolve() or destination.resolve() in backup.parents:
        raise ValueError("Backup must be outside Resources/pet")
    for state, (_, count) in STATES.items():
        existing = {p.name for p in destination.glob(f"fatfish-{state}-*.webp")}
        expected = {f"fatfish-{state}-{i}.webp" for i in range(count)}
        if existing != expected:
            raise ValueError(f"Refusing to replace an unexpected {state} frame set")

    # Encode and validate the complete replacement set before touching old files.
    with tempfile.TemporaryDirectory(prefix=".fatfish-rgba-", dir=destination) as staging:
        staged = Path(staging)
        for name, frame in frames.items():
            frame.save(staged / name, "WEBP", lossless=True, quality=100, method=6, exact=True)
        verify(staged, frames)
        backup.mkdir(parents=True, exist_ok=True)
        for name in frames:
            if not (backup / name).exists():
                shutil.copy2(destination / name, backup / name)
        for name in frames:
            os.replace(staged / name, destination / name)

    report = verify(destination, frames)
    report["backup_dir"] = str(backup)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
