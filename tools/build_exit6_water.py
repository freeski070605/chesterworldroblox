#!/usr/bin/env python3
r"""Export mapped ChesterWorld waterways from EXISTING regional Unity/GIS tiles.

Input: E:\ChesterWorld\Data\16_RegionalTiles\Tiles\tile_rXX_cXX.json
Output: src/shared/WaterData/Tiles/*.lua (Rojo ModuleScripts)
No web access, water guessing, road changes, or terrain changes in this step.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path

import numpy as np
from rasterio.features import rasterize
from rasterio.transform import from_origin
from shapely import affinity
from shapely.geometry import mapping, shape
from shapely.validation import explain_validity

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"E:\ChesterWorld\Data\16_RegionalTiles\Tiles")
DEST = PROJECT / "src" / "shared" / "WaterData" / "Tiles"
MANIFEST = PROJECT / "src" / "shared" / "WaterData" / "Manifest.lua"
REPORT = PROJECT / "tools" / "reports" / "exit6_water_export.json"
S = 3.0
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973
VOXEL = 4  # real Roblox Terrain voxel grid; never shift the existing world


def polygon_parts(geom):
    if geom.is_empty:
        return []
    if not geom.is_valid:
        geom = geom.buffer(0)
    if geom.geom_type == "Polygon":
        return [geom] if geom.area > 0 else []
    if geom.geom_type == "MultiPolygon":
        return [g for g in geom.geoms if g.area > 0]
    if geom.geom_type == "GeometryCollection":
        return [p for g in geom.geoms for p in polygon_parts(g)]
    return []


def to_roblox(geom):
    # Unity tile coordinates: X=east, Z=north (local metres).
    # Roblox: X=east, Z=south; do not flip the world again.
    geom = affinity.scale(geom, xfact=S, yfact=-S, origin=(0, 0))
    return affinity.translate(geom, xoff=-S * CENTER_X_M,
                             yoff=S * CENTER_Z_M)


def input_shapes(tile):
    polygons, streams = [], []
    layers = tile.get("layers") or {}
    for feat in layers.get("water_areas", []):
        try:
            polygons.extend(polygon_parts(to_roblox(shape(feat["geometry"]))))
        except (KeyError, TypeError, ValueError) as exc:
            print(f"  invalid water polygon skipped: {exc}")
    for feat in layers.get("streams", []):
        try:
            geom = shape(feat["geometry"])
            if geom.is_empty:
                continue
            props = feat.get("properties") or {}
            # Width is an approximate depiction ONLY when no polygon boundary
            # covers the stream; never treat a stream centerline as a surveyed bank.
            width = props.get("width_m", props.get("width"))
            try:
                width = float(str(width).split()[0])
            except (TypeError, ValueError, IndexError):
                width = 4.0  # conservative approximate narrow stream (metres)
            width = max(1.5, min(width, 12.0))
            if "LineString" in geom.geom_type:
                geom = geom.buffer(width / 2, cap_style=2, join_style=2)
            streams.extend(polygon_parts(to_roblox(geom)))
        except (KeyError, TypeError, ValueError) as exc:
            print(f"  invalid stream skipped: {exc}")
    return polygons, streams


def to_rects(mask, xmin, zmax):
    """Run-length pixels horizontally; coalesce equal runs vertically."""
    height, width = mask.shape
    active = {}
    result = []
    for row in range(height + 1):
        seen = set()
        if row < height:
            cells = mask[row]
            edges = np.flatnonzero(np.r_[True, cells[1:] != cells[:-1], True])
            for j0, j1 in zip(edges[:-1], edges[1:]):
                kind = int(cells[j0])
                if kind:
                    seen.add((int(j0), int(j1), kind))
        for key, first_row in active.items():
            if key in seen:
                continue
            j0, j1, kind = key
            x0 = xmin + j0 * VOXEL
            z0 = zmax - row * VOXEL
            result.append((x0, z0, (j1 - j0) * VOXEL,
                           (row - first_row) * VOXEL, kind))
        active = {key: active.get(key, row) for key in seen}
    return sorted(result, key=lambda r: (r[1], r[0], r[4]))


def export_one(tile_path):
    tile = json.loads(tile_path.read_text(encoding="utf-8"))
    polygons, streams = input_shapes(tile)
    geometries = polygons + streams
    if not geometries:
        return None, {"polygons": 0, "streams": 0, "rects": 0, "cells": 0}
    bounds = [g.bounds for g in geometries]
    xmin = math.floor(min(b[0] for b in bounds) / VOXEL) * VOXEL
    xmax = math.ceil(max(b[2] for b in bounds) / VOXEL) * VOXEL
    zmin = math.floor(min(b[1] for b in bounds) / VOXEL) * VOXEL
    zmax = math.ceil(max(b[3] for b in bounds) / VOXEL) * VOXEL
    width, height = (xmax - xmin) // VOXEL, (zmax - zmin) // VOXEL
    # Tiles are clipped to the existing 1km geographic source-grid.
    if width <= 0 or height <= 0 or width * height > 1_000_000:
        raise RuntimeError(f"Unexpected water bounds for {tile_path.name}: {width}x{height}")
    transform = from_origin(xmin, zmax, VOXEL, VOXEL)
    # Stream centerlines are approximate (2); polygon shorelines are mapped (1).
    shapes = [(mapping(g), 2) for g in streams]
    shapes += [(mapping(g), 1) for g in polygons]
    mask = rasterize(shapes, out_shape=(height, width), transform=transform,
                     fill=0, all_touched=False, dtype=np.uint8)
    rects = to_rects(mask, xmin, zmax)
    info = {"polygons": len(polygons), "streams": len(streams),
            "rects": len(rects), "cells": int(np.count_nonzero(mask)),
            "mapped_polygon_cells": int(np.count_nonzero(mask == 1)),
            "approx_stream_cells": int(np.count_nonzero(mask == 2))}
    if not rects:
        return None, info
    rows = [f"    {{{x},{z},{w},{d},{k}}}," for x, z, w, d, k in rects]
    content = "\n".join([
        "-- Generated by tools/build_exit6_water.py. Do not edit by hand.",
        f'return {{tile_id="{tile_path.stem}", rects={{',
        *rows,
        "}}",
        "",
    ])
    return content, info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--check", action="store_true",
                        help="audit source coverage without writing files")
    args = parser.parse_args()
    tiles = sorted(args.source.glob("tile_r??_c??.json"))
    if not tiles:
        raise SystemExit(f"No regional GIS tile JSON files in {args.source}. "
                         "Existing Chester regional tile data is required.")
    totals = Counter()
    emitted = {}
    for tile_path in tiles:
        content, stats = export_one(tile_path)
        totals.update(stats)
        if content is not None:
            emitted[tile_path.stem] = content
    if totals["mapped_polygon_cells"] == 0:
        raise SystemExit("No mapped water polygons found in the regional GIS tiles. "
                         "Refusing to fabricate the Delaware shoreline.")
    print(f"[EXIT6 Water GIS] read={len(tiles)} tiles, mapped polygon cells="
          f"{totals['mapped_polygon_cells']}, approximate-stream cells="
          f"{totals['approx_stream_cells']}, water tiles={len(emitted)}, "
          f"water rectangles={totals['rects']}")
    if args.check:
        return
    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.glob("tile_r??_c??.lua"):
        if old.stem not in emitted:
            old.unlink()
    for name, content in emitted.items():
        (DEST / f"{name}.lua").write_text(content, encoding="utf-8")
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(
        "-- Generated water coverage manifest; version 1.\n"
        f"return {{version=1, tiles={len(emitted)}, rects={totals['rects']}}}\n",
        encoding="utf-8")
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({
        "source": str(args.source), "source_tiles": len(tiles),
        "water_tiles": len(emitted), "voxel_studs": VOXEL,
        "water_rectangles": totals["rects"],
        "mapped_polygon_cells": totals["mapped_polygon_cells"],
        "approximate_stream_cells": totals["approx_stream_cells"],
        "notes": "Polygons follow mapped GIS banks; stream widths without measured polygons are approximations. Existing roads are not altered."
    }, indent=2) + "\n", encoding="utf-8")
    print(f"[EXIT6 Water GIS] exported {len(emitted)} Rojo modules and {REPORT}")


if __name__ == "__main__":
    main()
