#!/usr/bin/env python3
r"""
ChesterWorld terrain orientation correction.

The original recentered heightmaps were written with a vertical np.flipud()
before Roblox import. ChesterWorld's vector coordinate system is already:

    +X = east
    -X = west
    +Z = north
    -Z = south

This tool flips each CURRENT terrain-import PNG vertically one more time,
which restores the original GIS raster row orientation without changing
chunk positions, world scale, or elevation normalization.

It NEVER overwrites the existing terrain_import folder.

Input:
    E:\code\chesterworld-roblox\terrain_import

Output:
    E:\code\chesterworld-roblox\terrain_import_corrected
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image, ImageOps

PROJECT = Path(r"E:\code\chesterworld-roblox")
SOURCE = PROJECT / "terrain_import"
OUTPUT = PROJECT / "terrain_import_corrected"


def main():
    if not SOURCE.exists():
        raise SystemExit(f"Missing source terrain folder: {SOURCE}")

    manifest_path = SOURCE / "terrain_import_manifest.json"
    instructions_path = SOURCE / "IMPORT_INSTRUCTIONS.txt"

    if not manifest_path.exists():
        raise SystemExit(f"Missing terrain manifest: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    pngs = sorted(SOURCE.glob("chester_height_*.png"))
    if not pngs:
        raise SystemExit(f"No Chester terrain PNGs found in {SOURCE}")

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True, exist_ok=True)

    print("============================================")
    print("CHESTERWORLD TRUE ORIENTATION FIX")
    print("============================================")
    print("True axes:")
    print("  NORTH = +Z")
    print("  SOUTH = -Z")
    print("  EAST  = +X")
    print("  WEST  = -X")
    print()
    print(f"Source: {SOURCE}")
    print(f"Output: {OUTPUT}")
    print()

    for src in pngs:
        with Image.open(src) as image:
            corrected = ImageOps.flip(image)
            corrected.save(OUTPUT / src.name)
        print(f"Corrected: {src.name}")

    corrected_manifest = dict(manifest)
    corrected_manifest["orientation_corrected"] = True
    corrected_manifest["geographic_axes"] = {
        "north": "+Z",
        "south": "-Z",
        "east": "+X",
        "west": "-X",
    }
    corrected_manifest["flip_z"] = False
    corrected_manifest["orientation_note"] = (
        "PNG vertical flip from the earlier converter has been undone. "
        "Chunk size/position values are unchanged."
    )

    (OUTPUT / "terrain_import_manifest.json").write_text(
        json.dumps(corrected_manifest, indent=2),
        encoding="utf-8",
    )

    if instructions_path.exists():
        original = instructions_path.read_text(encoding="utf-8")
    else:
        original = ""

    header = """CHESTERWORLD TRUE GEOGRAPHIC ORIENTATION
========================================================================
NORTH = +Z
SOUTH = -Z
EAST  = +X
WEST  = -X

These corrected PNGs use the SAME Roblox Size and Position values as the
previous recentered terrain import. Only the image's north/south raster
orientation was corrected.

IMPORTANT:
1. Clear the currently imported Roblox terrain.
2. Reimport these corrected PNGs.
3. Use the exact same Size / Position values below.

"""
    (OUTPUT / "IMPORT_INSTRUCTIONS.txt").write_text(
        header + original,
        encoding="utf-8",
    )

    print()
    print("============================================")
    print("CORRECTION COMPLETE")
    print("============================================")
    print(f"Corrected heightmaps: {len(pngs)}")
    print(f"Import from: {OUTPUT}")


if __name__ == "__main__":
    main()
