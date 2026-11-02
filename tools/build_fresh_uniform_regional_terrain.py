#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import zlib
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import from_bounds
from rasterio.warp import Resampling, reproject, transform_bounds
from shapely.geometry import box

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

REGIONAL_MANIFEST = (
    ROOT / "Data" / "16_RegionalTiles"
    / "chester_world_manifest.json"
)

TERRAIN_DIR = ROOT / "Data" / "09_RegionalTerrain"
TERRAIN_METADATA = (
    TERRAIN_DIR / "regional_3dep_tiles_metadata.json"
)

OUT_DIR = (
    TERRAIN_DIR / "RobloxFreshUniformImport"
)
OUT_MANIFEST = (
    OUT_DIR / "roblox_uniform_terrain_manifest.json"
)
OUT_CSV = (
    OUT_DIR / "roblox_uniform_terrain_import.csv"
)
OUT_INSTRUCTIONS = (
    OUT_DIR / "IMPORT_ALL_9.txt"
)

TARGET_CRS = "EPSG:3857"

# ---------------------------------------------------------------------------
# LOCKED CHESTERWORLD / ROBLOX TRUTH
# ---------------------------------------------------------------------------
STUDS_PER_METER = 3.0

CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973

# Existing Chester vertical mapping. Keep it unchanged so roads/buildings
# remain on the same world elevation scale.
Y_POSITION = 107.8
Y_SIZE = 223.5

Y_BOTTOM_STUDS = Y_POSITION - Y_SIZE / 2.0
Y_TOP_STUDS = Y_POSITION + Y_SIZE / 2.0

ELEV_MIN_M = Y_BOTTOM_STUDS / STUDS_PER_METER
ELEV_MAX_M = Y_TOP_STUDS / STUDS_PER_METER

NODATA = -9999.0

# One uniform 3x3 grid. Every chunk is full Roblox max terrain import width:
#
#   4096 pixels * 4 studs/pixel = 16384 studs
#
# The full grid therefore spans:
#   X -24576 .. +24576
#   Z -24576 .. +24576
#
# This fully contains the 13.1 km x 13.4 km regional playable world.
PIXELS = 4096
STUDS_PER_PIXEL = 4.0
CHUNK_STUDS = PIXELS * STUDS_PER_PIXEL

GRID_MIN = -24576.0
GRID_MAX = 24576.0

X_INTERVALS = [
    (-24576.0, -8192.0, "west"),
    (-8192.0, 8192.0, "center"),
    (8192.0, 24576.0, "east"),
]

Z_INTERVALS = [
    (-24576.0, -8192.0, "north"),
    (-8192.0, 8192.0, "center"),
    (8192.0, 24576.0, "south"),
]


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2),
        encoding="utf-8",
    )


def resolve_terrain_file(tile):
    filename = tile.get("filename")

    if filename:
        p = TERRAIN_DIR / filename
        if p.is_file():
            return p

    original = tile.get("original_source_path")
    if original:
        p = Path(original)
        if p.is_file():
            return p

    return None


def open_sources(metadata):
    records = []
    missing = []

    for tile in metadata.get("tiles", []):
        path = resolve_terrain_file(tile)

        if path is None:
            missing.append(
                tile.get("filename", "<unnamed>")
            )
            continue

        src = rasterio.open(path)

        try:
            b = transform_bounds(
                src.crs,
                TARGET_CRS,
                *src.bounds,
                densify_pts=21,
            )
        except Exception:
            src.close()
            raise

        records.append({
            "src": src,
            "path": path,
            "bounds": box(*b),
        })

    if missing:
        print()
        print("Missing terrain rasters:")
        for name in missing:
            print(f"  - {name}")

        raise RuntimeError(
            f"Could not resolve {len(missing)} regional terrain raster(s)."
        )

    if not records:
        raise RuntimeError(
            "No regional terrain source rasters found."
        )

    return records


def close_sources(records):
    for record in records:
        try:
            record["src"].close()
        except Exception:
            pass


def roblox_bounds_to_epsg3857(
    min_x,
    min_z,
    max_x,
    max_z,
    origin,
):
    # Locked world transform:
    #
    #   Roblox X = (localX - CENTER_X_M) * S
    #   Roblox Z = -(localZ - CENTER_Z_M) * S
    #
    # Therefore:
    #
    #   localX = RobloxX / S + CENTER_X_M
    #   localZ = CENTER_Z_M - RobloxZ / S
    #
    # Raster row zero is north / maximum EPSG:3857 Y, which maps to minimum
    # Roblox Z. No later image flip is required.

    min_local_x = (
        min_x / STUDS_PER_METER
        + CENTER_X_M
    )
    max_local_x = (
        max_x / STUDS_PER_METER
        + CENTER_X_M
    )

    min_local_z = (
        CENTER_Z_M
        - max_z / STUDS_PER_METER
    )
    max_local_z = (
        CENTER_Z_M
        - min_z / STUDS_PER_METER
    )

    return (
        float(origin["x"]) + min_local_x,
        float(origin["z"]) + min_local_z,
        float(origin["x"]) + max_local_x,
        float(origin["z"]) + max_local_z,
    )


def png_ihdr(path: Path):
    """
    Read PNG IHDR directly so we verify what Studio will see:
      width, height, bit_depth, color_type
    """
    data = path.read_bytes()

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(
            f"Not a valid PNG: {path}"
        )

    length = struct.unpack(">I", data[8:12])[0]
    chunk_type = data[12:16]

    if chunk_type != b"IHDR" or length != 13:
        raise RuntimeError(
            f"Unexpected PNG header: {path}"
        )

    ihdr = data[16:29]
    width, height, bit_depth, color_type, _, _, _ = (
        struct.unpack(">IIBBBBB", ihdr)
    )

    return {
        "width": width,
        "height": height,
        "bit_depth": bit_depth,
        "color_type": color_type,
    }


def build_chunk(
    row_name,
    col_name,
    min_x,
    min_z,
    max_x,
    max_z,
    origin,
    sources,
):
    epsg_bounds = roblox_bounds_to_epsg3857(
        min_x,
        min_z,
        max_x,
        max_z,
        origin,
    )

    dst_transform = from_bounds(
        *epsg_bounds,
        PIXELS,
        PIXELS,
    )

    elevation = np.full(
        (PIXELS, PIXELS),
        NODATA,
        dtype="float32",
    )

    target_box = box(*epsg_bounds)
    source_count = 0

    for record in sources:
        if not record["bounds"].intersects(
            target_box
        ):
            continue

        src = record["src"]

        temp = np.full(
            (PIXELS, PIXELS),
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

        write = (
            valid
            & (elevation == NODATA)
        )

        if np.any(write):
            elevation[write] = temp[write]
            source_count += 1

    valid = (
        np.isfinite(elevation)
        & (elevation != NODATA)
    )

    valid_count = int(
        np.count_nonzero(valid)
    )
    total_count = int(elevation.size)

    # Outside the available regional DEM, keep terrain at the same locked
    # bottom elevation instead of inventing slopes or changing scale.
    elevation[~valid] = ELEV_MIN_M

    raw_min = float(np.min(elevation))
    raw_max = float(np.max(elevation))

    below = int(
        np.count_nonzero(
            elevation < ELEV_MIN_M
        )
    )
    above = int(
        np.count_nonzero(
            elevation > ELEV_MAX_M
        )
    )

    elevation = np.clip(
        elevation,
        ELEV_MIN_M,
        ELEV_MAX_M,
    )

    normalized = (
        (elevation - ELEV_MIN_M)
        / (ELEV_MAX_M - ELEV_MIN_M)
    )

    pixels = np.rint(
        normalized * 65535.0
    ).astype(np.uint16)

    filename = (
        f"regional_full_{row_name}_{col_name}"
        f"_4096x4096.png"
    )
    path = OUT_DIR / filename

    Image.fromarray(
        pixels,
        mode="I;16",
    ).save(path)

    header = png_ihdr(path)

    # Roblox needs 16-bit grayscale.
    if (
        header["width"] != PIXELS
        or header["height"] != PIXELS
        or header["bit_depth"] != 16
        or header["color_type"] != 0
    ):
        raise RuntimeError(
            f"PNG verification failed for {path.name}: {header}"
        )

    position_x = (min_x + max_x) / 2.0
    position_z = (min_z + max_z) / 2.0

    return {
        "image": filename,
        "row": row_name,
        "column": col_name,
        "pixel_width": PIXELS,
        "pixel_height": PIXELS,
        "png_bit_depth": header["bit_depth"],
        "png_color_type": header["color_type"],
        "position": {
            "x": position_x,
            "y": Y_POSITION,
            "z": position_z,
        },
        "size": {
            "x": CHUNK_STUDS,
            "y": Y_SIZE,
            "z": CHUNK_STUDS,
        },
        "roblox_bounds": {
            "min_x": min_x,
            "min_z": min_z,
            "max_x": max_x,
            "max_z": max_z,
        },
        "source_bounds_epsg3857": {
            "min_x": round(epsg_bounds[0], 3),
            "min_y": round(epsg_bounds[1], 3),
            "max_x": round(epsg_bounds[2], 3),
            "max_y": round(epsg_bounds[3], 3),
        },
        "valid_dem_pixels": valid_count,
        "total_pixels": total_count,
        "dem_coverage_percent": round(
            valid_count * 100.0 / total_count,
            4,
        ),
        "source_rasters_used": source_count,
        "raw_min_elevation_m": round(
            raw_min,
            4,
        ),
        "raw_max_elevation_m": round(
            raw_max,
            4,
        ),
        "pixels_clipped_below": below,
        "pixels_clipped_above": above,
    }


def write_csv(entries):
    import csv

    fields = [
        "image",
        "row",
        "column",
        "position_x",
        "position_y",
        "position_z",
        "size_x",
        "size_y",
        "size_z",
        "pixels",
        "bit_depth",
        "color_type",
        "dem_coverage_percent",
    ]

    with OUT_CSV.open(
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
            p = item["position"]
            s = item["size"]

            writer.writerow({
                "image": item["image"],
                "row": item["row"],
                "column": item["column"],
                "position_x": p["x"],
                "position_y": p["y"],
                "position_z": p["z"],
                "size_x": s["x"],
                "size_y": s["y"],
                "size_z": s["z"],
                "pixels": "4096x4096",
                "bit_depth": item["png_bit_depth"],
                "color_type": item["png_color_type"],
                "dem_coverage_percent": (
                    item["dem_coverage_percent"]
                ),
            })


def write_instructions(entries):
    lines = [
        "CHESTERWORLD — FRESH UNIFORM REGIONAL TERRAIN IMPORT",
        "=" * 80,
        "",
        "This REPLACES the existing Roblox terrain with one uniform 3x3 grid.",
        "",
        "GRID:",
        "  9 total heightmaps",
        "  every image = 4096 x 4096 pixels",
        "  every X/Z Size = 16384 x 16384 studs",
        "  1 pixel = 4 studs",
        "  all PNGs verified as 16-bit grayscale",
        "",
        "LOCKED ORIENTATION:",
        "  North = -Z",
        "  South = +Z",
        "  East  = +X",
        "  West  = -X",
        "",
        "LOCKED VERTICAL MAPPING:",
        "  Y Position = 107.8",
        "  Y Size     = 223.5",
        "",
        "DO NOT FLIP ANY PNG.",
        "",
        "------------------------------------------------------------",
        "BEFORE IMPORT",
        "------------------------------------------------------------",
        "",
        "1. SAVE A BACKUP COPY OF THE ROBLOX PLACE.",
        "2. In Studio open View > Command Bar.",
        "3. Clear ONLY terrain with:",
        "",
        "   workspace.Terrain:Clear()",
        "",
        "4. Leave Rojo/vector code alone.",
        "5. Import all 9 images below.",
        "",
        "------------------------------------------------------------",
        "IMPORT ORDER — NORTH TO SOUTH, WEST TO EAST",
        "------------------------------------------------------------",
        "",
    ]

    for i, item in enumerate(
        entries,
        start=1,
    ):
        p = item["position"]
        s = item["size"]

        lines.extend([
            f"{i:02d}. {item['image']}",
            (
                f"    Position: "
                f"X={p['x']:.1f}, "
                f"Y={p['y']:.1f}, "
                f"Z={p['z']:.1f}"
            ),
            (
                f"    Size:     "
                f"X={s['x']:.1f}, "
                f"Y={s['y']:.1f}, "
                f"Z={s['z']:.1f}"
            ),
            (
                "    Pixels:   4096 x 4096 "
                "(16-bit grayscale)"
            ),
            (
                f"    DEM data: "
                f"{item['dem_coverage_percent']:.2f}%"
            ),
            "",
        ])

    lines.extend([
        "------------------------------------------------------------",
        "AFTER ALL 9 IMPORTS",
        "------------------------------------------------------------",
        "",
        "1. SAVE THE PLACE.",
        "2. If regional WorldPlacement is not active yet, run:",
        "",
        r"   cd E:\code\chesterworld-roblox",
        r"   powershell -ExecutionPolicy Bypass -File .\activate_regional_world.ps1",
        "",
        "3. Let Rojo sync.",
        "4. Press Play.",
        "",
        "FIRST VALIDATION:",
        "  - X/debug return still goes to 9th & Kerlin.",
        "  - 8th -> 9th at Kerlin: right goes toward Parker.",
        "  - Facing east on 9th near Barclay: Chester High is left.",
        "  - Then fly Chester -> Parkside -> Upland -> Brookhaven.",
        "  - There should be continuous terrain through the entire corridor.",
        "",
        "Do not use any old Chester terrain PNGs or extension-strip PNGs",
        "after this fresh import.",
        "=" * 80,
    ])

    OUT_INSTRUCTIONS.write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def main():
    print("=" * 84)
    print("CHESTERWORLD FRESH UNIFORM REGIONAL TERRAIN BUILDER")
    print("=" * 84)

    if not REGIONAL_MANIFEST.exists():
        raise SystemExit(
            f"Missing regional manifest: {REGIONAL_MANIFEST}"
        )

    if not TERRAIN_METADATA.exists():
        raise SystemExit(
            f"Missing terrain metadata: {TERRAIN_METADATA}"
        )

    OUT_DIR.mkdir(
        parents=True,
        exist_ok=True,
    )

    manifest = load_json(
        REGIONAL_MANIFEST
    )
    metadata = load_json(
        TERRAIN_METADATA
    )
    origin = manifest[
        "origin_epsg3857"
    ]

    world_size = manifest[
        "world_size_m"
    ]

    desired_min_x = (
        -CENTER_X_M
        * STUDS_PER_METER
    )
    desired_max_x = (
        (
            float(world_size["width"])
            - CENTER_X_M
        )
        * STUDS_PER_METER
    )
    desired_min_z = -(
        (
            float(world_size["depth"])
            - CENTER_Z_M
        )
        * STUDS_PER_METER
    )
    desired_max_z = (
        CENTER_Z_M
        * STUDS_PER_METER
    )

    print()
    print("Regional playable Roblox bounds:")
    print(
        f"  X {desired_min_x:.1f}"
        f" .. {desired_max_x:.1f}"
    )
    print(
        f"  Z {desired_min_z:.1f}"
        f" .. {desired_max_z:.1f}"
    )
    print()
    print("Uniform terrain grid bounds:")
    print(
        f"  X {GRID_MIN:.1f}"
        f" .. {GRID_MAX:.1f}"
    )
    print(
        f"  Z {GRID_MIN:.1f}"
        f" .. {GRID_MAX:.1f}"
    )

    if (
        desired_min_x < GRID_MIN
        or desired_max_x > GRID_MAX
        or desired_min_z < GRID_MIN
        or desired_max_z > GRID_MAX
    ):
        raise RuntimeError(
            "Regional world does not fit inside the planned 3x3 terrain grid."
        )

    sources = open_sources(metadata)

    entries = []

    try:
        total = 9
        index = 0

        for (
            min_z,
            max_z,
            row_name,
        ) in Z_INTERVALS:
            for (
                min_x,
                max_x,
                col_name,
            ) in X_INTERVALS:
                index += 1

                print()
                print(
                    f"[{index:02d}/{total:02d}] "
                    f"{row_name} / {col_name}"
                )

                item = build_chunk(
                    row_name,
                    col_name,
                    min_x,
                    min_z,
                    max_x,
                    max_z,
                    origin,
                    sources,
                )

                entries.append(item)

                print(
                    f"    {item['image']}"
                )
                print(
                    "    PNG verified: "
                    f"{item['pixel_width']}x"
                    f"{item['pixel_height']}, "
                    f"{item['png_bit_depth']}-bit, "
                    f"color type "
                    f"{item['png_color_type']}"
                )
                print(
                    f"    DEM coverage: "
                    f"{item['dem_coverage_percent']:.2f}%"
                )

    finally:
        close_sources(sources)

    output = {
        "world": "ChesterWorld Regional",
        "strategy": (
            "fresh full replacement; uniform 3x3 Roblox terrain grid"
        ),
        "orientation": {
            "north": "-Z",
            "south": "+Z",
            "east": "+X",
            "west": "-X",
            "images_already_handed": True,
        },
        "grid": {
            "rows": 3,
            "columns": 3,
            "chunks": 9,
            "chunk_pixels": 4096,
            "chunk_studs": 16384,
            "grid_min_x": GRID_MIN,
            "grid_max_x": GRID_MAX,
            "grid_min_z": GRID_MIN,
            "grid_max_z": GRID_MAX,
        },
        "vertical": {
            "position_y": Y_POSITION,
            "size_y": Y_SIZE,
            "elevation_min_m": ELEV_MIN_M,
            "elevation_max_m": ELEV_MAX_M,
        },
        "worldplacement": {
            "center_x_m": CENTER_X_M,
            "center_z_m": CENTER_Z_M,
        },
        "chunks": entries,
    }

    save_json(
        OUT_MANIFEST,
        output,
    )

    write_csv(entries)
    write_instructions(entries)

    below = sum(
        item["pixels_clipped_below"]
        for item in entries
    )
    above = sum(
        item["pixels_clipped_above"]
        for item in entries
    )

    print()
    print("=" * 84)
    print("FRESH UNIFORM REGIONAL TERRAIN READY")
    print("=" * 84)
    print("Heightmaps: 9")
    print("Every image: 4096 x 4096")
    print("Every X/Z Size: 16384 x 16384 studs")
    print(
        f"Y Position / Size: "
        f"{Y_POSITION} / {Y_SIZE}"
    )
    print(
        f"Pixels clipped below locked range: "
        f"{below:,}"
    )
    print(
        f"Pixels clipped above locked range: "
        f"{above:,}"
    )
    print(f"Output: {OUT_DIR}")
    print(f"Instructions: {OUT_INSTRUCTIONS}")
    print(f"CSV: {OUT_CSV}")
    print(f"Manifest: {OUT_MANIFEST}")
    print()
    print(
        "All PNGs were verified from their IHDR as "
        "4096x4096, 16-bit grayscale."
    )
    print(
        "Do NOT flip them. North is already -Z."
    )
    print("=" * 84)


if __name__ == "__main__":
    main()
