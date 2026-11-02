#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from rasterio.transform import from_bounds
from rasterio.warp import Resampling, reproject, transform_bounds
from shapely.geometry import box

ROOT = Path(r"E:\ChesterWorld")

EXT_DIR = (
    ROOT / "Data" / "09_RegionalTerrain"
    / "RobloxExtensionImport"
)
EXT_MANIFEST = (
    EXT_DIR / "roblox_regional_terrain_extension_manifest.json"
)

TERRAIN_DIR = ROOT / "Data" / "09_RegionalTerrain"
TERRAIN_METADATA = (
    TERRAIN_DIR / "regional_3dep_tiles_metadata.json"
)

OUT_DIR = EXT_DIR / "StudioCompat"
OUT_MANIFEST = OUT_DIR / "studio_compat_manifest.json"
OUT_INSTRUCTIONS = OUT_DIR / "IMPORT_STUDIO_COMPAT.txt"

TARGET_CRS = "EPSG:3857"
STUDS_PER_METER = 3.0
VOXEL_STUDS = 4.0
NODATA = -9999.0

# Locked from the already validated Chester terrain workflow.
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973
Y_POSITION = 107.8
Y_SIZE = 223.5

Y_BOTTOM_STUDS = Y_POSITION - Y_SIZE / 2.0
Y_TOP_STUDS = Y_POSITION + Y_SIZE / 2.0
ELEV_MIN_M = Y_BOTTOM_STUDS / STUDS_PER_METER
ELEV_MAX_M = Y_TOP_STUDS / STUDS_PER_METER


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


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

    for tile in metadata.get("tiles", []):
        path = resolve_terrain_file(tile)
        if path is None:
            continue

        src = rasterio.open(path)
        b = transform_bounds(
            src.crs,
            TARGET_CRS,
            *src.bounds,
            densify_pts=21,
        )
        records.append({
            "src": src,
            "path": path,
            "bounds": box(*b),
        })

    if not records:
        raise RuntimeError("No regional terrain source rasters found.")

    return records


def close_sources(records):
    for r in records:
        try:
            r["src"].close()
        except Exception:
            pass


def chunk_to_epsg3857(bounds, region_origin):
    min_x = bounds["min_x"]
    max_x = bounds["max_x"]
    min_z = bounds["min_z"]
    max_z = bounds["max_z"]

    min_east_m = min_x / STUDS_PER_METER + CENTER_X_M
    max_east_m = max_x / STUDS_PER_METER + CENTER_X_M

    min_north_m = CENTER_Z_M - max_z / STUDS_PER_METER
    max_north_m = CENTER_Z_M - min_z / STUDS_PER_METER

    return (
        region_origin["x"] + min_east_m,
        region_origin["z"] + min_north_m,
        region_origin["x"] + max_east_m,
        region_origin["z"] + max_north_m,
    )


def make_compat_bounds(item):
    """
    Studio is currently rejecting extension images where neither axis is 4096
    pixels. Keep the same 4-stud scale and overlap neighboring extension terrain
    with real DEM data instead of stretching.

    North/south leftovers: expand X to 4096 px, anchored at original max X.
    West/east leftovers: expand Z to 4096 px, anchored at original max Z.
    """
    b = dict(item["roblox_bounds"])
    pw = int(item["pixel_width"])
    ph = int(item["pixel_height"])

    if pw == 4096 or ph == 4096:
        return None

    kind = item.get("kind", "")

    if kind in {"north", "south"}:
        new_width_studs = 4096 * VOXEL_STUDS
        b["min_x"] = b["max_x"] - new_width_studs
    elif kind in {"west", "east"}:
        new_depth_studs = 4096 * VOXEL_STUDS
        b["min_z"] = b["max_z"] - new_depth_studs
    else:
        # Generic fallback: expand the larger pixel dimension to 4096.
        if pw >= ph:
            b["min_x"] = b["max_x"] - 4096 * VOXEL_STUDS
        else:
            b["min_z"] = b["max_z"] - 4096 * VOXEL_STUDS

    return b


def build_image(item, compat_bounds, region_origin, sources):
    size_x = compat_bounds["max_x"] - compat_bounds["min_x"]
    size_z = compat_bounds["max_z"] - compat_bounds["min_z"]

    width = int(round(size_x / VOXEL_STUDS))
    height = int(round(size_z / VOXEL_STUDS))

    if width > 4096 or height > 4096:
        raise RuntimeError(f"Compat image too large: {width}x{height}")

    epsg_bounds = chunk_to_epsg3857(
        compat_bounds,
        region_origin,
    )

    dst_transform = from_bounds(
        *epsg_bounds,
        width,
        height,
    )

    elev = np.full(
        (height, width),
        NODATA,
        dtype="float32",
    )

    target_box = box(*epsg_bounds)

    for record in sources:
        if not record["bounds"].intersects(target_box):
            continue

        temp = np.full(
            (height, width),
            NODATA,
            dtype="float32",
        )

        src = record["src"]

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

        valid = np.isfinite(temp) & (temp != NODATA)
        write = valid & (elev == NODATA)
        elev[write] = temp[write]

    valid = np.isfinite(elev) & (elev != NODATA)
    elev[~valid] = ELEV_MIN_M
    elev = np.clip(elev, ELEV_MIN_M, ELEV_MAX_M)

    normalized = (
        (elev - ELEV_MIN_M)
        / (ELEV_MAX_M - ELEV_MIN_M)
    )

    pixels = np.rint(
        normalized * 65535.0
    ).astype(np.uint16)

    original_stem = Path(item["image"]).stem
    filename = f"{original_stem}_STUDIO_COMPAT_{width}x{height}.png"
    path = OUT_DIR / filename

    Image.fromarray(pixels, mode="I;16").save(path)

    return {
        "replaces": item["image"],
        "image": filename,
        "kind": item.get("kind"),
        "pixel_width": width,
        "pixel_height": height,
        "position": {
            "x": (compat_bounds["min_x"] + compat_bounds["max_x"]) / 2.0,
            "y": Y_POSITION,
            "z": (compat_bounds["min_z"] + compat_bounds["max_z"]) / 2.0,
        },
        "size": {
            "x": size_x,
            "y": Y_SIZE,
            "z": size_z,
        },
        "roblox_bounds": compat_bounds,
        "note": (
            "Same 4-stud/pixel scale. Extra area is real DEM overlap with "
            "neighboring extension terrain; no stretching."
        ),
    }


def main():
    print("=" * 80)
    print("CHESTERWORLD STUDIO TERRAIN COMPATIBILITY REBUILD")
    print("=" * 80)

    if not EXT_MANIFEST.exists():
        raise SystemExit(f"Missing extension manifest: {EXT_MANIFEST}")

    if not TERRAIN_METADATA.exists():
        raise SystemExit(f"Missing terrain metadata: {TERRAIN_METADATA}")

    ext = load_json(EXT_MANIFEST)
    terrain = load_json(TERRAIN_METADATA)

    region_manifest = load_json(
        ROOT / "Data" / "16_RegionalTiles" / "chester_world_manifest.json"
    )
    region_origin = region_manifest["origin_epsg3857"]

    offenders = []
    for item in ext.get("chunks", []):
        pw = int(item["pixel_width"])
        ph = int(item["pixel_height"])
        if pw != 4096 and ph != 4096:
            offenders.append(item)

    print(f"Chunks needing Studio-compat rebuild: {len(offenders)}")

    if not offenders:
        print("Nothing to rebuild.")
        return

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sources = open_sources(terrain)

    results = []

    try:
        for i, item in enumerate(offenders, start=1):
            bounds = make_compat_bounds(item)
            rebuilt = build_image(
                item,
                bounds,
                region_origin,
                sources,
            )
            results.append(rebuilt)

            p = rebuilt["position"]
            s = rebuilt["size"]

            print(
                f"[{i:02d}/{len(offenders):02d}] "
                f"{rebuilt['replaces']} -> {rebuilt['image']}"
            )
            print(
                f"    Position X={p['x']:.1f} Y={p['y']:.1f} Z={p['z']:.1f}"
            )
            print(
                f"    Size     X={s['x']:.1f} Y={s['y']:.1f} Z={s['z']:.1f}"
            )

    finally:
        close_sources(sources)

    save_json(
        OUT_MANIFEST,
        {
            "purpose": "Roblox Studio terrain importer compatibility",
            "orientation": "North=-Z; images already handed",
            "scale": "1 pixel = 4 studs",
            "chunks": results,
        },
    )

    lines = [
        "CHESTERWORLD — STUDIO COMPAT HEIGHTMAPS",
        "=" * 76,
        "",
        "Use these ONLY instead of the original files named under 'Replaces'.",
        "Already imported good chunks do not need to be re-imported.",
        "",
        "Do not flip these images.",
        "Keep Y Position = 107.8 and Y Size = 223.5.",
        "",
    ]

    for i, r in enumerate(results, start=1):
        p = r["position"]
        s = r["size"]
        lines += [
            f"{i:02d}. Replaces: {r['replaces']}",
            f"    Image:    {r['image']}",
            f"    Position: X={p['x']:.1f}, Y={p['y']:.1f}, Z={p['z']:.1f}",
            f"    Size:     X={s['x']:.1f}, Y={s['y']:.1f}, Z={s['z']:.1f}",
            f"    Pixels:   {r['pixel_width']} x {r['pixel_height']}",
            "",
        ]

    OUT_INSTRUCTIONS.write_text("\n".join(lines), encoding="utf-8")

    print()
    print("=" * 80)
    print("STUDIO COMPAT FILES READY")
    print("=" * 80)
    print(f"Output: {OUT_DIR}")
    print(f"Instructions: {OUT_INSTRUCTIONS}")
    print("Already-good imported chunks stay in place.")
    print("=" * 80)


if __name__ == "__main__":
    main()
