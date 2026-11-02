#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import box, shape
from shapely.ops import unary_union, transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")

REGION_DIR = ROOT / "Data" / "00_Boundary" / "RegionalExpansion"
AREAS = REGION_DIR / "chester_region_areas.geojson"

BUILDINGS = (
    ROOT / "Data" / "14_RegionalGeneratorPrep_v2"
    / "regional_generator_buildings_v2.geojson"
)
ROADS = (
    ROOT / "Data" / "15_RegionalRoadGeneratorPrep"
    / "regional_generator_roads.geojson"
)

REGIONAL_TERRAIN = (
    ROOT / "Data" / "09_RegionalTerrain"
    / "regional_3dep_tiles_metadata.json"
)
OLD_TERRAIN = (
    ROOT / "Data" / "09_Terrain"
    / "chester_3dep_tiles_metadata.json"
)

REPORT = REGION_DIR / "regional_ready_audit.json"

TO_3857 = Transformer.from_crs(
    "EPSG:4326", "EPSG:3857", always_xy=True
).transform


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, data):
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def area_records():
    data = load(AREAS)
    rows = []

    for f in data.get("features", []):
        if not f.get("geometry"):
            continue

        p = f.get("properties") or {}

        rows.append(
            {
                "name": str(
                    p.get("chesterworld_name")
                    or p.get("Name")
                    or "Unknown"
                ),
                "role": p.get("chesterworld_role", ""),
                "geom": shape(f["geometry"]),
            }
        )

    return rows


def feature_counts(path, areas):
    if not path.exists():
        return {}, 0

    data = load(path)
    features = data.get("features", [])
    counts = Counter()

    for f in features:
        if not f.get("geometry"):
            continue

        try:
            g = shape(f["geometry"])
        except Exception:
            continue

        for area in areas:
            if g.intersects(area["geom"]):
                counts[area["name"]] += 1

    return dict(counts), len(features)


def terrain_union():
    terrain_path = (
        REGIONAL_TERRAIN
        if REGIONAL_TERRAIN.exists()
        else OLD_TERRAIN
    )

    if not terrain_path.exists():
        return None, 0, str(terrain_path)

    data = load(terrain_path)
    boxes = []

    for tile in data.get("tiles", []):
        b = tile.get("bounds") or {}

        try:
            boxes.append(
                box(
                    float(b["xmin"]),
                    float(b["ymin"]),
                    float(b["xmax"]),
                    float(b["ymax"]),
                )
            )
        except Exception:
            pass

    if not boxes:
        return None, 0, str(terrain_path)

    return unary_union(boxes), len(boxes), str(terrain_path)


def pct(value):
    return round(float(value) * 100.0, 2)


def main():
    if not AREAS.exists():
        raise SystemExit(
            "Missing regional area file. "
            "Run build_regional_expansion.py first."
        )

    areas = area_records()

    building_counts, building_total = feature_counts(
        BUILDINGS, areas
    )
    road_counts, road_total = feature_counts(
        ROADS, areas
    )

    terrain, terrain_tile_count, terrain_source = terrain_union()

    terrain_by_area = {}

    for area in areas:
        g3857 = shp_transform(TO_3857, area["geom"])

        if terrain is None or g3857.area <= 0:
            coverage = 0.0
        else:
            coverage = (
                g3857.intersection(terrain).area
                / g3857.area
            )

        terrain_by_area[area["name"]] = pct(coverage)

    results = {
        "building_total": building_total,
        "road_total": road_total,
        "terrain_tile_count": terrain_tile_count,
        "terrain_metadata_source": terrain_source,
        "buildings_by_area": building_counts,
        "roads_by_area": road_counts,
        "terrain_coverage_percent_by_area": terrain_by_area,
        "areas": {},
    }

    print("=" * 92)
    print("CHESTERWORLD REGIONAL READY AUDIT")
    print("=" * 92)

    all_core_vectors = True
    all_core_terrain = True

    for area in areas:
        name = area["name"]
        role = area["role"]
        b = int(building_counts.get(name, 0))
        r = int(road_counts.get(name, 0))
        t = float(terrain_by_area.get(name, 0.0))

        vector_ok = b > 0 and r > 0
        terrain_ok = t >= 99.0

        if role == "core":
            all_core_vectors = (
                all_core_vectors and vector_ok
            )
            all_core_terrain = (
                all_core_terrain and terrain_ok
            )

        results["areas"][name] = {
            "role": role,
            "buildings": b,
            "roads": r,
            "terrain_coverage_percent": t,
            "vector_ready": vector_ok,
            "terrain_ready": terrain_ok,
        }

        print(
            f"{name:<26} "
            f"{role:<10} "
            f"buildings={b:>6,}  "
            f"roads={r:>5,}  "
            f"terrain={t:>6.2f}%  "
            f"{'OK' if vector_ok else 'VECTOR MISSING'}"
            f"{'' if terrain_ok else ' / TERRAIN GAP'}"
        )

    results["core_vector_ready"] = all_core_vectors
    results["core_terrain_ready"] = all_core_terrain
    results["ready_for_regional_tiling"] = (
        all_core_vectors and all_core_terrain
    )

    save(REPORT, results)

    print()
    print("-" * 92)
    print(f"Regional generator buildings: {building_total:,}")
    print(f"Regional generator roads:     {road_total:,}")
    print(f"Terrain source tiles:         {terrain_tile_count:,}")
    print(f"Terrain metadata: {terrain_source}")
    print()
    print(
        "CORE VECTOR COVERAGE: "
        + ("READY" if all_core_vectors else "NOT READY")
    )
    print(
        "CORE TERRAIN COVERAGE: "
        + (
            "READY"
            if all_core_terrain
            else "EXPANSION REQUIRED"
        )
    )
    print(
        "REGIONAL TILING: "
        + (
            "READY"
            if results["ready_for_regional_tiling"]
            else "HOLD"
        )
    )
    print("=" * 92)
    print(f"Report: {REPORT}")


if __name__ == "__main__":
    main()
