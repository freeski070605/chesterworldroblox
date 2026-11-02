#!/usr/bin/env python3
"""
ChesterWorld DEM -> Roblox heightmap converter (RECENTERED).

Why this version exists:
- The Terrain Editor can reject very large selections far from the origin.
- We recenter all Chester coordinates around the DEM/world center.
- We use 3.0 studs per meter so the full ~10.5 km Chester terrain footprint
  fits inside a compact ~31.5k-stud Z span.

The script writes:
  terrain_import/*.png
  terrain_import/terrain_import_manifest.json
  terrain_import/IMPORT_INSTRUCTIONS.txt
  src/shared/WorldPlacement.lua

WorldPlacement.lua is consumed by TileBuilder.lua so roads/buildings use the
same recentering transform as the terrain.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

try:
    import rasterio
    from rasterio.merge import merge
except ImportError as exc:
    raise SystemExit(
        "Missing rasterio.\n"
        "Install with:\n"
        "  py -m pip install rasterio pillow\n"
    ) from exc


DEFAULT_ROOT = Path(r"E:\ChesterWorld")
DEFAULT_PROJECT = Path(r"E:\code\chesterworld-roblox")

STUDS_PER_METER = 3.0
ROBLOX_STUDS_PER_HEIGHTMAP_PIXEL = 4.0
TARGET_RES_M = ROBLOX_STUDS_PER_HEIGHTMAP_PIXEL / STUDS_PER_METER
MAX_PX = 4096
NODATA_SENTINEL = -99999.0


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean_output(directory: Path):
    directory.mkdir(parents=True, exist_ok=True)
    for path in directory.glob("chester_height_*.png"):
        path.unlink()
    for name in ("terrain_import_manifest.json", "IMPORT_INSTRUCTIONS.txt"):
        path = directory / name
        if path.exists():
            path.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--project", type=Path, default=DEFAULT_PROJECT)
    parser.add_argument("--max-px", type=int, default=MAX_PX)
    parser.add_argument("--flip-z", action=argparse.BooleanOptionalAction, default=True)
    args = parser.parse_args()

    terrain_dir = args.root / "Data" / "09_Terrain" / "Tiles"
    world_manifest_path = (
        args.root / "Data" / "16_UnityTiles" / "chester_world_manifest.json"
    )
    output_dir = args.project / "terrain_import"
    placement_path = args.project / "src" / "shared" / "WorldPlacement.lua"

    if not terrain_dir.exists():
        raise SystemExit(f"Terrain directory not found: {terrain_dir}")
    if not world_manifest_path.exists():
        raise SystemExit(f"World manifest not found: {world_manifest_path}")

    world_manifest = load_json(world_manifest_path)
    origin = world_manifest.get("origin_epsg3857") or {}
    origin_x = float(origin["x"])
    origin_z = float(origin["z"])

    tif_paths = sorted(terrain_dir.glob("chester_dem_*.tif"))
    if not tif_paths:
        raise SystemExit(f"No Chester DEM tiles found in {terrain_dir}")

    print("============================================")
    print("CHESTERWORLD -> ROBLOX TERRAIN (RECENTERED)")
    print("============================================")
    print(f"DEM tiles:            {len(tif_paths)}")
    print(f"Studs per meter:      {STUDS_PER_METER}")
    print(f"Target DEM res:       {TARGET_RES_M:.6f} m/pixel")
    print(f"Roblox scale:         4 studs/pixel")
    print(f"Chunk max:            {args.max_px} px")
    print()

    datasets = [rasterio.open(path) for path in tif_paths]
    try:
        crs_values = {str(ds.crs) for ds in datasets}
        if len(crs_values) != 1:
            raise RuntimeError(f"DEM tiles have multiple CRSs: {crs_values}")

        mosaic, transform = merge(
            datasets,
            res=TARGET_RES_M,
            nodata=NODATA_SENTINEL,
            dtype="float32",
            method="first",
        )
    finally:
        for ds in datasets:
            ds.close()

    dem = mosaic[0]
    valid = np.isfinite(dem) & (dem > NODATA_SENTINEL + 1)
    if not np.any(valid):
        raise RuntimeError("No valid DEM elevation pixels found.")

    min_elev = float(np.min(dem[valid]))
    max_elev = float(np.max(dem[valid]))
    dem = np.where(valid, dem, min_elev).astype(np.float32)

    height, width = dem.shape

    # Mosaic world-edge coordinates.
    left_x = transform.c
    right_x = transform.c + width * transform.a
    top_y = transform.f
    bottom_y = transform.f + height * transform.e

    local_min_x_m = min(left_x, right_x) - origin_x
    local_max_x_m = max(left_x, right_x) - origin_x
    local_min_z_m = min(top_y, bottom_y) - origin_z
    local_max_z_m = max(top_y, bottom_y) - origin_z

    center_x_m = (local_min_x_m + local_max_x_m) / 2.0
    center_z_m = (local_min_z_m + local_max_z_m) / 2.0

    world_width_studs = (local_max_x_m - local_min_x_m) * STUDS_PER_METER
    world_depth_studs = (local_max_z_m - local_min_z_m) * STUDS_PER_METER

    elevation_range_m = max(max_elev - min_elev, 0.01)
    y_size_studs = elevation_range_m * STUDS_PER_METER
    y_center_studs = ((min_elev + max_elev) / 2.0) * STUDS_PER_METER

    chunk_rows = math.ceil(height / args.max_px)
    chunk_cols = math.ceil(width / args.max_px)

    print(f"Mosaic:               {width} x {height} px")
    print(f"World center meters:  X={center_x_m:.3f} Z={center_z_m:.3f}")
    print(f"World footprint:      {world_width_studs:.1f} x {world_depth_studs:.1f} studs")
    print(f"Elevation:            {min_elev:.3f} .. {max_elev:.3f} m")
    print(f"Output chunk grid:    {chunk_cols} x {chunk_rows}")
    print()

    # Write shared placement transform for the Roblox world builder.
    placement_path.parent.mkdir(parents=True, exist_ok=True)
    placement_path.write_text(
        "return {\n"
        f"    STUDS_PER_METER = {STUDS_PER_METER:.6f},\n"
        f"    CENTER_X_M = {center_x_m:.6f},\n"
        f"    CENTER_Z_M = {center_z_m:.6f},\n"
        "}\n",
        encoding="utf-8",
    )

    clean_output(output_dir)

    normalized = np.clip((dem - min_elev) / elevation_range_m, 0.0, 1.0)
    encoded_all = np.round(1 + normalized * 65534.0).astype(np.uint16)

    chunks = []

    for chunk_row in range(chunk_rows):
        row0 = chunk_row * args.max_px
        row1 = min(row0 + args.max_px, height)

        for chunk_col in range(chunk_cols):
            col0 = chunk_col * args.max_px
            col1 = min(col0 + args.max_px, width)

            chunk = encoded_all[row0:row1, col0:col1]
            if args.flip_z:
                chunk = np.flipud(chunk)

            filename = f"chester_height_r{chunk_row:02d}_c{chunk_col:02d}.png"
            Image.fromarray(chunk).save(output_dir / filename)

            c_left = transform.c + col0 * transform.a
            c_right = transform.c + col1 * transform.a
            c_top = transform.f + row0 * transform.e
            c_bottom = transform.f + row1 * transform.e

            c_min_x_m = min(c_left, c_right) - origin_x
            c_max_x_m = max(c_left, c_right) - origin_x
            c_min_z_m = min(c_top, c_bottom) - origin_z
            c_max_z_m = max(c_top, c_bottom) - origin_z

            px_width = col1 - col0
            px_height = row1 - row0

            size_x_studs = px_width * 4.0
            size_z_studs = px_height * 4.0

            center_x_studs = (
                ((c_min_x_m + c_max_x_m) / 2.0 - center_x_m)
                * STUDS_PER_METER
            )
            center_z_studs = (
                ((c_min_z_m + c_max_z_m) / 2.0 - center_z_m)
                * STUDS_PER_METER
            )

            chunks.append(
                {
                    "file": filename,
                    "pixels": {"width": px_width, "height": px_height},
                    "roblox_selection": {
                        "size_studs": {
                            "x": size_x_studs,
                            "y": y_size_studs,
                            "z": size_z_studs,
                        },
                        "position_studs": {
                            "x": center_x_studs,
                            "y": y_center_studs,
                            "z": center_z_studs,
                        },
                    },
                }
            )

            print(
                f"{filename}: {px_width}x{px_height} | "
                f"Size=({size_x_studs:.1f}, {y_size_studs:.1f}, {size_z_studs:.1f}) | "
                f"Pos=({center_x_studs:.1f}, {y_center_studs:.1f}, {center_z_studs:.1f})"
            )

    manifest = {
        "version": 2,
        "recentered": True,
        "studs_per_meter": STUDS_PER_METER,
        "world_center_local_m": {"x": center_x_m, "z": center_z_m},
        "world_footprint_studs": {
            "width": world_width_studs,
            "depth": world_depth_studs,
        },
        "global_elevation_m": {"min": min_elev, "max": max_elev},
        "global_y_mapping_studs": {
            "size": y_size_studs,
            "position": y_center_studs,
        },
        "chunks": chunks,
    }

    (output_dir / "terrain_import_manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )

    lines = [
        "CHESTERWORLD ROBLOX TERRAIN IMPORT — RECENTERED",
        "=" * 72,
        "",
        "Use Terrain Editor -> Create -> Import.",
        "Import each heightmap using the exact Size and Position below.",
        "All Chester coordinates are now centered around Roblox X=0, Z=0.",
        "",
    ]

    for i, item in enumerate(chunks, 1):
        s = item["roblox_selection"]["size_studs"]
        p = item["roblox_selection"]["position_studs"]
        lines += [
            f"{i}. {item['file']}",
            f"   SIZE     X={s['x']:.3f}  Y={s['y']:.3f}  Z={s['z']:.3f}",
            f"   POSITION X={p['x']:.3f}  Y={p['y']:.3f}  Z={p['z']:.3f}",
            "",
        ]

    (output_dir / "IMPORT_INSTRUCTIONS.txt").write_text(
        "\n".join(lines), encoding="utf-8"
    )

    print()
    print("============================================")
    print("RECENTERED TERRAIN EXPORT COMPLETE")
    print("============================================")
    print(f"WorldPlacement: {placement_path}")
    print(f"Terrain output: {output_dir}")
    print(f"Heightmaps:     {len(chunks)}")


if __name__ == "__main__":
    main()
