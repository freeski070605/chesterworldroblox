#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import math
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import LineString, MultiLineString, GeometryCollection, Point, shape
from shapely.ops import transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")

ROADS = (
    ROOT / "Data" / "18_StreetSystemV3"
    / "regional_motor_roads_v3.geojson"
)
MANIFEST = (
    ROOT / "Data" / "17_RegionalTiles_RealWorld"
    / "chester_world_manifest.json"
)

OUT_DIR = (
    ROOT / "Data" / "21_JunctionAudit"
    / "9th_Kerlin"
)
OUT_DIR.mkdir(parents=True, exist_ok=True)

CSV_OUT = OUT_DIR / "9th_kerlin_source_roads.csv"
JSON_OUT = OUT_DIR / "9th_kerlin_source_audit.json"

# Locked ChesterWorld placement.
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973
STUDS_PER_METER = 3.0

# Known validated runtime location of 9th & Kerlin.
TARGET_ROBLOX_X = 2810.21
TARGET_ROBLOX_Z = 1518.82

SEARCH_RADIUS_M = 90.0
DUPLICATE_DISTANCE_M = 4.0
DUPLICATE_ANGLE_DEG = 12.0

TO_WEBM = Transformer.from_crs(
    "EPSG:4326",
    "EPSG:3857",
    always_xy=True,
).transform


def clean(v):
    if v is None:
        return ""
    t = str(v).strip()
    return "" if t.lower() in {"none", "null", "nan"} else t


def lines_from_geom(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [geom]
    if isinstance(geom, MultiLineString):
        return [g for g in geom.geoms if not g.is_empty]
    if isinstance(geom, GeometryCollection):
        out = []
        for g in geom.geoms:
            out.extend(lines_from_geom(g))
        return out
    return []


def road_width(props):
    for key in (
        "generator_width_m",
        "generator_render_width_m",
        "width_m",
        "width",
    ):
        try:
            value = float(props.get(key))
            if 1.0 <= value <= 80.0:
                return value
        except Exception:
            pass
    return 6.0


def heading_deg(line: LineString, point: Point):
    try:
        d = line.project(point)
        d0 = max(0.0, d - 5.0)
        d1 = min(line.length, d + 5.0)
        a = line.interpolate(d0)
        b = line.interpolate(d1)
        dx = b.x - a.x
        dz = b.y - a.y
        if math.hypot(dx, dz) < 1e-6:
            return None
        # Local world uses +X east, +localZ north before Roblox reflection.
        # Heading here is geographic-style: 0=N, 90=E.
        h = math.degrees(math.atan2(dx, dz)) % 360.0
        return h
    except Exception:
        return None


def angle_delta(a, b):
    if a is None or b is None:
        return 180.0
    d = abs(a - b) % 180.0
    return min(d, 180.0 - d)


def main():
    print("=" * 92)
    print("CHESTERWORLD - 9TH & KERLIN SOURCE ROAD AUDIT")
    print("=" * 92)

    if not ROADS.exists():
        raise SystemExit(f"Missing source roads: {ROADS}")
    if not MANIFEST.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST}")

    roads_data = json.loads(ROADS.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    origin = manifest["origin_epsg3857"]
    origin_x = float(origin["x"])
    origin_z = float(origin["z"])

    # Inverse of the locked runtime mapping:
    # xStud = (localX - CENTER_X_M) * 3
    # zStud = -(localZ - CENTER_Z_M) * 3
    target_local_x = TARGET_ROBLOX_X / STUDS_PER_METER + CENTER_X_M
    target_local_z = -TARGET_ROBLOX_Z / STUDS_PER_METER + CENTER_Z_M
    target = Point(target_local_x, target_local_z)

    records = []

    for fi, feature in enumerate(roads_data.get("features", [])):
        props = dict(feature.get("properties") or {})

        try:
            geom_wgs = shape(feature.get("geometry"))
            if geom_wgs.is_empty:
                continue
            geom_web = shp_transform(TO_WEBM, geom_wgs)
        except Exception:
            continue

        def to_local(x, y, z=None):
            if z is None:
                return (x - origin_x, y - origin_z)
            return (x - origin_x, y - origin_z, z)

        try:
            from shapely.ops import transform
            geom_local = transform(to_local, geom_web)
        except Exception:
            continue

        for li, line in enumerate(lines_from_geom(geom_local)):
            try:
                distance = float(line.distance(target))
            except Exception:
                continue

            if distance > SEARCH_RADIUS_M:
                continue

            nearest = line.interpolate(line.project(target))
            heading = heading_deg(line, target)

            name = clean(
                props.get("generator_name")
                or props.get("name")
            )
            source = clean(props.get("generator_source"))
            road_class = clean(
                props.get("generator_road_class")
                or props.get("osm_highway")
            )
            priority = props.get("generator_source_priority", "")
            width = road_width(props)

            records.append({
                "record_id": len(records),
                "feature_index": fi,
                "line_index": li,
                "name": name,
                "source": source,
                "source_priority": priority,
                "road_class": road_class,
                "width_m": round(width, 2),
                "distance_to_9th_kerlin_m": round(distance, 3),
                "heading_deg": None if heading is None else round(heading, 2),
                "nearest_local_x_m": round(nearest.x, 3),
                "nearest_local_z_m": round(nearest.y, 3),
                "nearest_roblox_x": round(
                    (nearest.x - CENTER_X_M) * STUDS_PER_METER, 2
                ),
                "nearest_roblox_z": round(
                    -(nearest.y - CENTER_Z_M) * STUDS_PER_METER, 2
                ),
                "length_m": round(line.length, 2),
                "osm_highway": clean(props.get("osm_highway")),
                "osm_service": clean(props.get("osm_service")),
                "centerline_building_hits": props.get(
                    "generator_centerline_building_hits", 0
                ),
                "_line": line,
            })

    records.sort(
        key=lambda r: (
            r["distance_to_9th_kerlin_m"],
            r["name"],
            r["source"],
        )
    )

    # Duplicate corridor candidates.
    duplicate_pairs = []

    for i in range(len(records)):
        a = records[i]
        for j in range(i + 1, len(records)):
            b = records[j]

            try:
                corridor_distance = float(
                    a["_line"].distance(b["_line"])
                )
            except Exception:
                continue

            if corridor_distance > DUPLICATE_DISTANCE_M:
                continue

            delta = angle_delta(
                a["heading_deg"],
                b["heading_deg"],
            )

            if delta > DUPLICATE_ANGLE_DEG:
                continue

            same_name = (
                bool(a["name"])
                and bool(b["name"])
                and a["name"].strip().upper()
                == b["name"].strip().upper()
            )

            duplicate_pairs.append({
                "a_record_id": a["record_id"],
                "b_record_id": b["record_id"],
                "a_name": a["name"],
                "b_name": b["name"],
                "a_source": a["source"],
                "b_source": b["source"],
                "corridor_distance_m": round(corridor_distance, 3),
                "heading_delta_deg": round(delta, 2),
                "same_name": same_name,
            })

    # Reassign stable display ids after sorting.
    id_map = {}
    for display_id, record in enumerate(records, start=1):
        id_map[record["record_id"]] = display_id
        record["display_id"] = display_id

    for pair in duplicate_pairs:
        pair["a_display_id"] = id_map[pair["a_record_id"]]
        pair["b_display_id"] = id_map[pair["b_record_id"]]

    csv_fields = [
        "display_id",
        "feature_index",
        "line_index",
        "name",
        "source",
        "source_priority",
        "road_class",
        "width_m",
        "distance_to_9th_kerlin_m",
        "heading_deg",
        "nearest_roblox_x",
        "nearest_roblox_z",
        "length_m",
        "osm_highway",
        "osm_service",
        "centerline_building_hits",
    ]

    with CSV_OUT.open("w", newline="", encoding="utf-8") as fp:
        writer = csv.DictWriter(fp, fieldnames=csv_fields)
        writer.writeheader()
        for record in records:
            writer.writerow({
                key: record.get(key, "")
                for key in csv_fields
            })

    json_records = []
    for record in records:
        json_records.append({
            key: value
            for key, value in record.items()
            if key != "_line"
        })

    output = {
        "target": {
            "name": "9th & Kerlin",
            "roblox_x": TARGET_ROBLOX_X,
            "roblox_z": TARGET_ROBLOX_Z,
            "local_x_m": target_local_x,
            "local_z_m": target_local_z,
            "search_radius_m": SEARCH_RADIUS_M,
        },
        "nearby_source_roads": json_records,
        "duplicate_corridor_candidates": duplicate_pairs,
    }

    JSON_OUT.write_text(
        json.dumps(output, indent=2),
        encoding="utf-8",
    )

    print(f"Target Roblox X/Z: {TARGET_ROBLOX_X:.2f}, {TARGET_ROBLOX_Z:.2f}")
    print(f"Nearby source lines within {SEARCH_RADIUS_M:.0f}m: {len(records)}")
    print(f"Duplicate corridor candidates: {len(duplicate_pairs)}")
    print()
    print("CLOSEST SOURCE LINES")
    print("-" * 92)

    for record in records[:25]:
        print(
            f"#{record['display_id']:02d} "
            f"d={record['distance_to_9th_kerlin_m']:6.2f}m "
            f"hdg={str(record['heading_deg']):>6} "
            f"w={record['width_m']:5.2f}m "
            f"src={record['source'] or '-':8} "
            f"name={record['name'] or '<unnamed>'} "
            f"class={record['road_class'] or '-'}"
        )

    print()
    print("DUPLICATE CORRIDOR CANDIDATES")
    print("-" * 92)

    if not duplicate_pairs:
        print("NONE")
    else:
        for pair in duplicate_pairs[:30]:
            print(
                f"#{pair['a_display_id']:02d} <-> #{pair['b_display_id']:02d} "
                f"gap={pair['corridor_distance_m']:.2f}m "
                f"angle={pair['heading_delta_deg']:.1f}deg "
                f"sameName={pair['same_name']} "
                f"[{pair['a_source']}:{pair['a_name'] or '<unnamed>'}] "
                f"vs [{pair['b_source']}:{pair['b_name'] or '<unnamed>'}]"
            )

    print()
    print(f"CSV:  {CSV_OUT}")
    print(f"JSON: {JSON_OUT}")
    print("=" * 92)


if __name__ == "__main__":
    main()
