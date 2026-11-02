#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.warp import Resampling, reproject, transform_bounds
from rasterio.transform import from_bounds
from shapely.geometry import box

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

REGIONAL_MANIFEST = (
    ROOT / "Data" / "16_RegionalTiles"
    / "chester_world_manifest.json"
)

TERRAIN_DIR = (
    ROOT / "Data" / "09_RegionalTerrain"
)

TERRAIN_METADATA = (
    TERRAIN_DIR / "regional_3dep_tiles_metadata.json"
)

OUTPUT_DIR = (
    ROOT / "Data" / "09_RegionalTerrain"
    / "RobloxExtensionImport"
)

OUTPUT_MANIFEST = (
    OUTPUT_DIR / "roblox_regional_terrain_extension_manifest.json"
)

OUTPUT_CSV = (
    OUTPUT_DIR / "roblox_regional_terrain_extension_import.csv"
)

OUTPUT_INSTRUCTIONS = (
    OUTPUT_DIR / "IMPORT_INSTRUCTIONS.txt"
)

# ---------------------------------------------------------------------------
# LOCKED ROBLOX WORLD TRUTH
# ---------------------------------------------------------------------------
# Do not change these orientation rules.
#
#   North = -Z
#   South = +Z
#   East  = +X
#   West  = -X
#
# Existing Chester terrain is NOT regenerated. These are the exact outer
# bounds of the already-imported, orientation-correct Chester terrain rectangle.
# Every new terrain chunk is aligned to the same 4-stud terrain voxel lattice.
# ---------------------------------------------------------------------------

STUDS_PER_METER = 3.0

REGIONAL_CENTER_X_M = 6347.889
REGIONAL_CENTER_Z_M = 7201.973

OLD_GRID_MIN_X = -12848.0
OLD_GRID_MAX_X =  12848.0
OLD_GRID_MIN_Z = -15762.0
OLD_GRID_MAX_Z =  15762.0

VOXEL_STUDS = 4.0
MAX_CHUNK_STUDS = 16384.0

# Preserve the vertical mapping used by the existing imported Chester terrain.
# These are the locked Studio import values from the working terrain.
Y_POSITION_STUDS = 107.8
Y_SIZE_STUDS = 223.5

Y_BOTTOM_STUDS = Y_POSITION_STUDS - Y_SIZE_STUDS / 2.0
Y_TOP_STUDS = Y_POSITION_STUDS + Y_SIZE_STUDS / 2.0

ELEVATION_MIN_M = Y_BOTTOM_STUDS / STUDS_PER_METER
ELEVATION_MAX_M = Y_TOP_STUDS / STUDS_PER_METER

NODATA = -9999.0
TARGET_CRS = "EPSG:3857"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def ceil_steps(distance: float, step: float) -> int:
    if distance <= 0:
        return 0
    return int(math.ceil((distance - 1e-9) / step))


def extend_down(anchor: float, desired: float) -> float:
    return anchor - ceil_steps(anchor - desired, VOXEL_STUDS) * VOXEL_STUDS


def extend_up(anchor: float, desired: float) -> float:
    return anchor + ceil_steps(desired - anchor, VOXEL_STUDS) * VOXEL_STUDS


def split_interval(start: float, end: float):
    result = []
    cursor = start

    while cursor < end - 1e-6:
        next_value = min(cursor + MAX_CHUNK_STUDS, end)

        # Every interval must remain on the locked 4-stud voxel lattice.
        size = next_value - cursor
        if abs((size / VOXEL_STUDS) - round(size / VOXEL_STUDS)) > 1e-6:
            raise RuntimeError(
                f"Interval is not 4-stud aligned: {cursor}..{next_value}"
            )

        result.append((cursor, next_value))
        cursor = next_value

    return result


def regional_world_bounds_studs(manifest):
    origin = manifest["origin_epsg3857"]
    size = manifest["world_size_m"]

    # Local world coordinates are 0..world_size from the new regional origin.
    # WorldPlacement keeps Chester in the same Roblox coordinates:
    #
    #   X = (localX - CENTER_X_M) * S
    #   Z = -(localZ - CENTER_Z_M) * S
    #
    desired_min_x = (
        (0.0 - REGIONAL_CENTER_X_M)
        * STUDS_PER_METER
    )

    desired_max_x = (
        (float(size["width"]) - REGIONAL_CENTER_X_M)
        * STUDS_PER_METER
    )

    # local Z=world depth is north, and north is Roblox -Z.
    desired_min_z = (
        -(float(size["depth"]) - REGIONAL_CENTER_Z_M)
        * STUDS_PER_METER
    )

    # local Z=0 is south, and south is Roblox +Z.
    desired_max_z = (
        -(0.0 - REGIONAL_CENTER_Z_M)
        * STUDS_PER_METER
    )

    return {
        "origin_x": float(origin["x"]),
        "origin_z": float(origin["z"]),
        "desired_min_x": desired_min_x,
        "desired_max_x": desired_max_x,
        "desired_min_z": desired_min_z,
        "desired_max_z": desired_max_z,
    }


def build_extension_rectangles(bounds):
    # Extend from the exact old Chester terrain lattice, not from zero.
    new_min_x = extend_down(
        OLD_GRID_MIN_X,
        bounds["desired_min_x"],
    )
    new_max_x = extend_up(
        OLD_GRID_MAX_X,
        bounds["desired_max_x"],
    )
    new_min_z = extend_down(
        OLD_GRID_MIN_Z,
        bounds["desired_min_z"],
    )
    new_max_z = extend_up(
        OLD_GRID_MAX_Z,
        bounds["desired_max_z"],
    )

    chunks = []

    def add_chunk(kind, index, x0, x1, z0, z1):
        if x1 <= x0 or z1 <= z0:
            return

        chunks.append({
            "kind": kind,
            "index": index,
            "min_x": x0,
            "max_x": x1,
            "min_z": z0,
            "max_z": z1,
        })

    # West and east strips span the whole expanded Z range and therefore own
    # the four outer corner areas.
    if new_min_x < OLD_GRID_MIN_X:
        for i, (z0, z1) in enumerate(
            split_interval(new_min_z, new_max_z),
            start=1,
        ):
            add_chunk(
                "west",
                i,
                new_min_x,
                OLD_GRID_MIN_X,
                z0,
                z1,
            )

    if new_max_x > OLD_GRID_MAX_X:
        for i, (z0, z1) in enumerate(
            split_interval(new_min_z, new_max_z),
            start=1,
        ):
            add_chunk(
                "east",
                i,
                OLD_GRID_MAX_X,
                new_max_x,
                z0,
                z1,
            )

    # North/south strips only span the old central X extent so they don't
    # overlap the west/east strips.
    if new_min_z < OLD_GRID_MIN_Z:
        for i, (x0, x1) in enumerate(
            split_interval(OLD_GRID_MIN_X, OLD_GRID_MAX_X),
            start=1,
        ):
            add_chunk(
                "north",
                i,
                x0,
                x1,
                new_min_z,
                OLD_GRID_MIN_Z,
            )

    if new_max_z > OLD_GRID_MAX_Z:
        for i, (x0, x1) in enumerate(
            split_interval(OLD_GRID_MIN_X, OLD_GRID_MAX_X),
            start=1,
        ):
            add_chunk(
                "south",
                i,
                x0,
                x1,
                OLD_GRID_MAX_Z,
                new_max_z,
            )

    return chunks, {
        "min_x": new_min_x,
        "max_x": new_max_x,
        "min_z": new_min_z,
        "max_z": new_max_z,
    }


def resolve_terrain_file(tile):
    filename = tile.get("filename")
    if not filename:
        return None

    path = TERRAIN_DIR / filename
    if path.is_file():
        return path

    original = tile.get("original_source_path")
    if original:
        original_path = Path(original)
        if original_path.is_file():
            return original_path

    return None


def open_sources(metadata):
    records = []
    missing = []

    for tile in metadata.get("tiles", []):
        path = resolve_terrain_file(tile)
        if path is None:
            missing.append(tile.get("filename", "<unnamed>"))
            continue

        src = rasterio.open(path)

        try:
            bounds_3857 = transform_bounds(
                src.crs,
                TARGET_CRS,
                *src.bounds,
                densify_pts=21,
            )
        except Exception:
            src.close()
            raise

        records.append({
            "path": path,
            "src": src,
            "bounds": box(*bounds_3857),
        })

    if missing:
        for name in missing:
            print(f"Missing terrain raster: {name}")
        raise RuntimeError(
            f"Could not resolve {len(missing)} terrain raster(s)."
        )

    return records


def close_sources(records):
    for record in records:
        try:
            record["src"].close()
        except Exception:
            pass


def chunk_to_epsg3857(chunk, regional_bounds):
    # Final handed Roblox -> regional local meters -> EPSG:3857.
    #
    # X east is unchanged:
    #   localX = X/S + CENTER_X
    #
    # North is -Z:
    #   localZ = CENTER_Z - Z/S
    #
    # Because raster rows are north-up, max source Y corresponds to min Roblox Z.
    min_east_m = (
        chunk["min_x"] / STUDS_PER_METER
        + REGIONAL_CENTER_X_M
    )
    max_east_m = (
        chunk["max_x"] / STUDS_PER_METER
        + REGIONAL_CENTER_X_M
    )

    min_north_m = (
        REGIONAL_CENTER_Z_M
        - chunk["max_z"] / STUDS_PER_METER
    )
    max_north_m = (
        REGIONAL_CENTER_Z_M
        - chunk["min_z"] / STUDS_PER_METER
    )

    return (
        regional_bounds["origin_x"] + min_east_m,
        regional_bounds["origin_z"] + min_north_m,
        regional_bounds["origin_x"] + max_east_m,
        regional_bounds["origin_z"] + max_north_m,
    )


def build_heightmap(chunk, regional_bounds, sources):
    size_x = chunk["max_x"] - chunk["min_x"]
    size_z = chunk["max_z"] - chunk["min_z"]

    width = int(round(size_x / VOXEL_STUDS))
    height = int(round(size_z / VOXEL_STUDS))

    if width <= 0 or height <= 0:
        raise RuntimeError("Invalid terrain chunk dimensions.")

    if width > 4096 or height > 4096:
        raise RuntimeError(
            f"Terrain chunk exceeds 4096 px: {width}x{height}"
        )

    epsg_bounds = chunk_to_epsg3857(
        chunk,
        regional_bounds,
    )

    dst_transform = from_bounds(
        *epsg_bounds,
        width,
        height,
    )

    elevation = np.full(
        (height, width),
        NODATA,
        dtype="float32",
    )

    source_count = 0

    for record in sources:
        if not record["bounds"].intersects(box(*epsg_bounds)):
            continue

        src = record["src"]

        temp = np.full(
            (height, width),
            NODATA,
            dtype="float32",
        )

        reproject(
            source=rasterio.band(src, 1),
            destination=temp,
            src_transform=src.transform,
            src_crs=src.crs,
            src_nodata=src.nodata,
            dst_transform=dst_transform,
            dst_crs=TARGET_CRS,
            dst_nodata=NODATA,
            resampling=Resampling.bilinear,
            num_threads=2,
        )

        valid = (
            np.isfinite(temp)
            & (temp != NODATA)
        )

        write_mask = (
            valid
            & (elevation == NODATA)
        )

        if np.any(write_mask):
            elevation[write_mask] = temp[write_mask]
            source_count += 1

    valid = (
        np.isfinite(elevation)
        & (elevation != NODATA)
    )

    valid_count = int(np.count_nonzero(valid))
    total_count = int(elevation.size)

    # Outside the playable regional geography the staged DEM intentionally
    # contains NODATA. Import it at the same locked bottom elevation instead of
    # inventing terrain above the city.
    elevation[~valid] = ELEVATION_MIN_M

    raw_min = float(np.min(elevation))
    raw_max = float(np.max(elevation))

    below = int(
        np.count_nonzero(elevation < ELEVATION_MIN_M)
    )
    above = int(
        np.count_nonzero(elevation > ELEVATION_MAX_M)
    )

    # Do not alter Chester's established vertical scale.
    elevation = np.clip(
        elevation,
        ELEVATION_MIN_M,
        ELEVATION_MAX_M,
    )

    normalized = (
        (elevation - ELEVATION_MIN_M)
        / (ELEVATION_MAX_M - ELEVATION_MIN_M)
    )

    pixels = np.rint(
        normalized * 65535.0
    ).astype(np.uint16)

    # IMPORTANT:
    # Rasterio arrays are north-up: row 0 = maximum EPSG:3857 northing.
    # In the locked Roblox world north is -Z, and the top row of the imported
    # heightmap belongs at the chunk's minimum Z. Therefore this output is
    # ALREADY HANDED. Do not vertically flip it again.
    filename = (
        f"regional_{chunk['kind']}_{chunk['index']:02d}"
        f"_{width}x{height}.png"
    )

    output_path = OUTPUT_DIR / filename

    image = Image.fromarray(
        pixels,
        mode="I;16",
    )
    image.save(output_path)

    return {
        "image": filename,
        "kind": chunk["kind"],
        "index": chunk["index"],
        "pixel_width": width,
        "pixel_height": height,
        "valid_dem_pixels": valid_count,
        "total_pixels": total_count,
        "dem_coverage_percent": round(
            valid_count * 100.0 / total_count,
            4,
        ),
        "raw_min_elevation_m": round(raw_min, 4),
        "raw_max_elevation_m": round(raw_max, 4),
        "pixels_clamped_below_locked_range": below,
        "pixels_clamped_above_locked_range": above,
        "position": {
            "x": round(
                (chunk["min_x"] + chunk["max_x"]) / 2.0,
                3,
            ),
            "y": Y_POSITION_STUDS,
            "z": round(
                (chunk["min_z"] + chunk["max_z"]) / 2.0,
                3,
            ),
        },
        "size": {
            "x": round(size_x, 3),
            "y": Y_SIZE_STUDS,
            "z": round(size_z, 3),
        },
        "roblox_bounds": {
            "min_x": chunk["min_x"],
            "max_x": chunk["max_x"],
            "min_z": chunk["min_z"],
            "max_z": chunk["max_z"],
        },
        "source_bounds_epsg3857": {
            "min_x": round(epsg_bounds[0], 3),
            "min_y": round(epsg_bounds[1], 3),
            "max_x": round(epsg_bounds[2], 3),
            "max_y": round(epsg_bounds[3], 3),
        },
        "source_rasters_used": source_count,
    }


def write_csv(entries):
    import csv

    fields = [
        "image",
        "kind",
        "pixel_width",
        "pixel_height",
        "position_x",
        "position_y",
        "position_z",
        "size_x",
        "size_y",
        "size_z",
        "dem_coverage_percent",
        "raw_min_elevation_m",
        "raw_max_elevation_m",
    ]

    with OUTPUT_CSV.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as f:
        writer = csv.DictWriter(
            f,
            fieldnames=fields,
        )
        writer.writeheader()

        for item in entries:
            writer.writerow({
                "image": item["image"],
                "kind": item["kind"],
                "pixel_width": item["pixel_width"],
                "pixel_height": item["pixel_height"],
                "position_x": item["position"]["x"],
                "position_y": item["position"]["y"],
                "position_z": item["position"]["z"],
                "size_x": item["size"]["x"],
                "size_y": item["size"]["y"],
                "size_z": item["size"]["z"],
                "dem_coverage_percent": item["dem_coverage_percent"],
                "raw_min_elevation_m": item["raw_min_elevation_m"],
                "raw_max_elevation_m": item["raw_max_elevation_m"],
            })


def write_instructions(entries, expanded_bounds):
    lines = [
        "CHESTERWORLD REGIONAL TERRAIN EXTENSION",
        "=" * 72,
        "",
        "These PNGs EXTEND the existing Chester terrain.",
        "DO NOT delete or re-import the four existing Chester terrain chunks.",
        "",
        "LOCKED ORIENTATION:",
        "  North = -Z",
        "  South = +Z",
        "  East  = +X",
        "  West  = -X",
        "",
        "The PNGs are ALREADY in the final handed orientation.",
        "DO NOT run make_roblox_handed_terrain.py on these files.",
        "DO NOT flip them vertically.",
        "",
        "For every image below, use Roblox Studio Terrain Editor > Import",
        "and enter the exact Position and Size shown.",
        "",
        "Use the SAME terrain material/import material you used for the",
        "existing Chester heightmaps.",
        "",
        "Expanded terrain bounds:",
        f"  X {expanded_bounds['min_x']:.1f} .. {expanded_bounds['max_x']:.1f}",
        f"  Z {expanded_bounds['min_z']:.1f} .. {expanded_bounds['max_z']:.1f}",
        "",
    ]

    for i, item in enumerate(entries, start=1):
        p = item["position"]
        s = item["size"]

        lines.extend([
            f"{i:02d}. {item['image']}",
            (
                f"    Position: "
                f"X={p['x']}, Y={p['y']}, Z={p['z']}"
            ),
            (
                f"    Size:     "
                f"X={s['x']}, Y={s['y']}, Z={s['z']}"
            ),
            (
                f"    Pixels:   "
                f"{item['pixel_width']} x {item['pixel_height']}"
            ),
            (
                f"    DEM data: "
                f"{item['dem_coverage_percent']:.2f}% "
                "(remaining pixels intentionally import at locked bottom)"
            ),
            "",
        ])

    lines.extend([
        "=" * 72,
        "AFTER ALL EXTENSION CHUNKS ARE IMPORTED:",
        "",
        "Run from PowerShell:",
        "",
        r"  cd E:\code\chesterworld-roblox",
        r"  powershell -ExecutionPolicy Bypass -File .\activate_regional_world.ps1",
        "",
        "Then let Rojo sync and press Play.",
        "",
        "First validation:",
        "  1. X/debug return still lands at 9th & Kerlin.",
        "  2. 8th -> 9th on Kerlin, right turn goes toward Parker.",
        "  3. Facing east on 9th near Barclay, Chester High is on the left.",
        "  4. Fly outward and confirm terrain continues into the new towns.",
        "=" * 72,
    ])

    OUTPUT_INSTRUCTIONS.write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def main():
    print("=" * 84)
    print("CHESTERWORLD REGIONAL ROBLOX TERRAIN EXTENSION BUILDER")
    print("=" * 84)

    if not REGIONAL_MANIFEST.exists():
        raise SystemExit(
            f"Missing regional manifest: {REGIONAL_MANIFEST}"
        )

    if not TERRAIN_METADATA.exists():
        raise SystemExit(
            f"Missing regional terrain metadata: {TERRAIN_METADATA}"
        )

    OUTPUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    manifest = load_json(REGIONAL_MANIFEST)
    metadata = load_json(TERRAIN_METADATA)

    regional_bounds = regional_world_bounds_studs(
        manifest
    )

    chunks, expanded_bounds = (
        build_extension_rectangles(
            regional_bounds
        )
    )

    print()
    print("Desired regional Roblox bounds:")
    print(
        f"  X {regional_bounds['desired_min_x']:.1f}"
        f" .. {regional_bounds['desired_max_x']:.1f}"
    )
    print(
        f"  Z {regional_bounds['desired_min_z']:.1f}"
        f" .. {regional_bounds['desired_max_z']:.1f}"
    )

    print()
    print("Locked existing Chester terrain bounds:")
    print(
        f"  X {OLD_GRID_MIN_X:.1f} .. {OLD_GRID_MAX_X:.1f}"
    )
    print(
        f"  Z {OLD_GRID_MIN_Z:.1f} .. {OLD_GRID_MAX_Z:.1f}"
    )

    print()
    print("Voxel-aligned expanded terrain bounds:")
    print(
        f"  X {expanded_bounds['min_x']:.1f}"
        f" .. {expanded_bounds['max_x']:.1f}"
    )
    print(
        f"  Z {expanded_bounds['min_z']:.1f}"
        f" .. {expanded_bounds['max_z']:.1f}"
    )

    print()
    print(
        f"New extension chunks to build: {len(chunks)}"
    )

    sources = open_sources(metadata)

    try:
        entries = []

        for i, chunk in enumerate(
            chunks,
            start=1,
        ):
            size_x = chunk["max_x"] - chunk["min_x"]
            size_z = chunk["max_z"] - chunk["min_z"]

            print(
                f"[{i:02d}/{len(chunks):02d}] "
                f"{chunk['kind']} "
                f"{size_x:.0f} x {size_z:.0f} studs"
            )

            entry = build_heightmap(
                chunk,
                regional_bounds,
                sources,
            )
            entries.append(entry)

            print(
                f"    {entry['image']} | "
                f"{entry['pixel_width']}x"
                f"{entry['pixel_height']} | "
                f"DEM {entry['dem_coverage_percent']:.2f}%"
            )

    finally:
        close_sources(sources)

    output = {
        "world": "ChesterWorld Regional",
        "strategy": (
            "extension-only; existing Chester terrain remains untouched"
        ),
        "orientation": {
            "north": "-Z",
            "south": "+Z",
            "east": "+X",
            "west": "-X",
            "images_are_already_handed": True,
        },
        "studs_per_meter": STUDS_PER_METER,
        "voxel_studs": VOXEL_STUDS,
        "locked_vertical_import": {
            "position_y": Y_POSITION_STUDS,
            "size_y": Y_SIZE_STUDS,
            "elevation_min_m": ELEVATION_MIN_M,
            "elevation_max_m": ELEVATION_MAX_M,
        },
        "existing_chester_bounds": {
            "min_x": OLD_GRID_MIN_X,
            "max_x": OLD_GRID_MAX_X,
            "min_z": OLD_GRID_MIN_Z,
            "max_z": OLD_GRID_MAX_Z,
        },
        "expanded_bounds": expanded_bounds,
        "regional_worldplacement": {
            "center_x_m": REGIONAL_CENTER_X_M,
            "center_z_m": REGIONAL_CENTER_Z_M,
        },
        "chunks": entries,
    }

    save_json(
        OUTPUT_MANIFEST,
        output,
    )

    write_csv(entries)
    write_instructions(
        entries,
        expanded_bounds,
    )

    clamped_above = sum(
        item["pixels_clamped_above_locked_range"]
        for item in entries
    )
    clamped_below = sum(
        item["pixels_clamped_below_locked_range"]
        for item in entries
    )

    print()
    print("=" * 84)
    print("REGIONAL ROBLOX TERRAIN EXTENSION READY")
    print("=" * 84)
    print(f"New heightmaps: {len(entries)}")
    print(f"Output: {OUTPUT_DIR}")
    print(
        f"Locked Y import: Position={Y_POSITION_STUDS}, "
        f"Size={Y_SIZE_STUDS}"
    )
    print(
        f"Pixels clipped above locked Chester height range: "
        f"{clamped_above:,}"
    )
    print(
        f"Pixels clipped below locked Chester height range: "
        f"{clamped_below:,}"
    )
    print()
    print(f"Instructions: {OUTPUT_INSTRUCTIONS}")
    print(f"Import CSV:    {OUTPUT_CSV}")
    print(f"Manifest:      {OUTPUT_MANIFEST}")
    print()
    print("DO NOT flip these PNGs. They are already North=-Z.")
    print("=" * 84)


if __name__ == "__main__":
    main()
