#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import (
    GeometryCollection,
    LineString,
    MultiLineString,
    MultiPoint,
    Point,
    shape,
)
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

OUT_JSON = OUT_DIR / "9th_kerlin_overlap_audit_v2.json"

CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973
STUDS_PER_METER = 3.0

TARGET_ROBLOX_X = 2810.21
TARGET_ROBLOX_Z = 1518.82

SEARCH_RADIUS_M = 90.0
PAIR_DISTANCE_M = 4.0
PARALLEL_ANGLE_DEG = 12.0

# Anything above this is real shared linework rather than numerical noise.
TRUE_OVERLAP_MIN_M = 0.75

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


def line_length_from_intersection(geom):
    if geom is None or geom.is_empty:
        return 0.0
    if isinstance(geom, LineString):
        return geom.length
    if isinstance(geom, MultiLineString):
        return sum(g.length for g in geom.geoms)
    if isinstance(geom, GeometryCollection):
        return sum(
            line_length_from_intersection(g)
            for g in geom.geoms
        )
    return 0.0


def point_count_from_intersection(geom):
    if geom is None or geom.is_empty:
        return 0
    if isinstance(geom, Point):
        return 1
    if isinstance(geom, MultiPoint):
        return len(geom.geoms)
    if isinstance(geom, GeometryCollection):
        return sum(
            point_count_from_intersection(g)
            for g in geom.geoms
        )
    return 0


def heading_deg(line: LineString, point: Point):
    d = line.project(point)
    d0 = max(0.0, d - 5.0)
    d1 = min(line.length, d + 5.0)

    a = line.interpolate(d0)
    b = line.interpolate(d1)

    dx = b.x - a.x
    dz = b.y - a.y

    if math.hypot(dx, dz) < 1e-6:
        return None

    return math.degrees(math.atan2(dx, dz)) % 360.0


def angle_delta(a, b):
    if a is None or b is None:
        return 180.0

    d = abs(a - b) % 180.0
    return min(d, 180.0 - d)


def endpoint_distance_to_point(line, point):
    coords = list(line.coords)

    a = Point(coords[0])
    b = Point(coords[-1])

    da = a.distance(point)
    db = b.distance(point)

    return min(da, db)


def endpoint_to_endpoint_distance(a, b):
    ac = list(a.coords)
    bc = list(b.coords)

    endpoints_a = [
        Point(ac[0]),
        Point(ac[-1]),
    ]
    endpoints_b = [
        Point(bc[0]),
        Point(bc[-1]),
    ]

    return min(
        pa.distance(pb)
        for pa in endpoints_a
        for pb in endpoints_b
    )


def classify_pair(a, b, target):
    line_a = a["line"]
    line_b = b["line"]

    intersection = line_a.intersection(line_b)

    shared_length = line_length_from_intersection(intersection)
    point_count = point_count_from_intersection(intersection)

    endpoint_gap = endpoint_to_endpoint_distance(
        line_a,
        line_b,
    )

    a_target_endpoint = (
        endpoint_distance_to_point(line_a, target)
        <= 0.75
    )
    b_target_endpoint = (
        endpoint_distance_to_point(line_b, target)
        <= 0.75
    )

    if shared_length >= TRUE_OVERLAP_MIN_M:
        relationship = "TRUE_LINEAR_OVERLAP"
    elif point_count > 0:
        relationship = "POINT_TOUCH_OR_CROSS"
    elif endpoint_gap <= 0.75:
        relationship = "NEAR_ENDPOINT_JOIN"
    else:
        relationship = "PARALLEL_NEARBY"

    return {
        "relationship": relationship,
        "shared_line_length_m": round(shared_length, 3),
        "intersection_point_count": point_count,
        "endpoint_to_endpoint_gap_m": round(endpoint_gap, 3),
        "a_target_is_endpoint": a_target_endpoint,
        "b_target_is_endpoint": b_target_endpoint,
        "geometry_intersection_type": (
            intersection.geom_type
            if not intersection.is_empty
            else "EMPTY"
        ),
    }


def main():
    print("=" * 96)
    print("CHESTERWORLD - 9TH & KERLIN TRUE OVERLAP AUDIT V2")
    print("=" * 96)

    if not ROADS.exists():
        raise SystemExit(f"Missing source roads: {ROADS}")
    if not MANIFEST.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST}")

    data = json.loads(ROADS.read_text(encoding="utf-8"))
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    origin = manifest["origin_epsg3857"]
    origin_x = float(origin["x"])
    origin_z = float(origin["z"])

    target_local_x = (
        TARGET_ROBLOX_X / STUDS_PER_METER
        + CENTER_X_M
    )
    target_local_z = (
        -TARGET_ROBLOX_Z / STUDS_PER_METER
        + CENTER_Z_M
    )
    target = Point(
        target_local_x,
        target_local_z,
    )

    records = []

    for fi, feature in enumerate(data.get("features", [])):
        props = dict(feature.get("properties") or {})

        try:
            geom_wgs = shape(feature.get("geometry"))
            geom_web = shp_transform(
                TO_WEBM,
                geom_wgs,
            )
        except Exception:
            continue

        def to_local(x, y, z=None):
            if z is None:
                return (
                    x - origin_x,
                    y - origin_z,
                )
            return (
                x - origin_x,
                y - origin_z,
                z,
            )

        try:
            from shapely.ops import transform
            geom_local = transform(
                to_local,
                geom_web,
            )
        except Exception:
            continue

        for li, line in enumerate(
            lines_from_geom(geom_local)
        ):
            distance = line.distance(target)

            if distance > SEARCH_RADIUS_M:
                continue

            heading = heading_deg(
                line,
                target,
            )

            records.append({
                "id": len(records) + 1,
                "feature_index": fi,
                "line_index": li,
                "name": clean(
                    props.get("generator_name")
                    or props.get("name")
                ),
                "source": clean(
                    props.get("generator_source")
                ),
                "class": clean(
                    props.get("generator_road_class")
                ),
                "width_m": props.get(
                    "generator_width_m",
                    "",
                ),
                "distance_m": round(
                    distance,
                    3,
                ),
                "heading_deg": (
                    None
                    if heading is None
                    else round(heading, 2)
                ),
                "target_endpoint_distance_m": round(
                    endpoint_distance_to_point(
                        line,
                        target,
                    ),
                    3,
                ),
                "line": line,
            })

    records.sort(
        key=lambda r: (
            r["distance_m"],
            r["name"],
            r["id"],
        )
    )

    # Renumber exactly like the printed sorted list.
    for new_id, record in enumerate(records, start=1):
        record["display_id"] = new_id

    pairs = []

    for i in range(len(records)):
        a = records[i]

        for j in range(i + 1, len(records)):
            b = records[j]

            if not a["name"] or not b["name"]:
                continue

            if (
                a["name"].strip().upper()
                != b["name"].strip().upper()
            ):
                continue

            corridor_distance = (
                a["line"].distance(
                    b["line"]
                )
            )

            if corridor_distance > PAIR_DISTANCE_M:
                continue

            delta = angle_delta(
                a["heading_deg"],
                b["heading_deg"],
            )

            if delta > PARALLEL_ANGLE_DEG:
                continue

            relation = classify_pair(
                a,
                b,
                target,
            )

            pairs.append({
                "a": a["display_id"],
                "b": b["display_id"],
                "name": a["name"],
                "a_class": a["class"],
                "b_class": b["class"],
                "a_width_m": a["width_m"],
                "b_width_m": b["width_m"],
                "heading_delta_deg": round(
                    delta,
                    2,
                ),
                "corridor_distance_m": round(
                    corridor_distance,
                    3,
                ),
                **relation,
            })

    true_overlaps = [
        p for p in pairs
        if p["relationship"]
        == "TRUE_LINEAR_OVERLAP"
    ]

    normal_joins = [
        p for p in pairs
        if p["relationship"]
        in {
            "POINT_TOUCH_OR_CROSS",
            "NEAR_ENDPOINT_JOIN",
        }
    ]

    print(f"Nearby source lines: {len(records)}")
    print(f"Same-name close pairs: {len(pairs)}")
    print(f"TRUE linear overlaps: {len(true_overlaps)}")
    print(f"Endpoint/point joins: {len(normal_joins)}")
    print()

    print("PAIR CLASSIFICATION")
    print("-" * 96)

    for pair in pairs:
        print(
            f"#{pair['a']:02d} <-> #{pair['b']:02d} "
            f"{pair['name']:<12} "
            f"{pair['relationship']:<22} "
            f"shared={pair['shared_line_length_m']:7.2f}m "
            f"endGap={pair['endpoint_to_endpoint_gap_m']:5.2f}m "
            f"targetEnds={pair['a_target_is_endpoint']}/"
            f"{pair['b_target_is_endpoint']} "
            f"classes={pair['a_class']}/{pair['b_class']} "
            f"widths={pair['a_width_m']}/{pair['b_width_m']}"
        )

    print()
    print("TRUE DUPLICATE / OVERLAP PAIRS")
    print("-" * 96)

    if not true_overlaps:
        print("NONE")
    else:
        for pair in true_overlaps:
            print(
                f"#{pair['a']:02d} <-> #{pair['b']:02d} "
                f"{pair['name']} "
                f"shared={pair['shared_line_length_m']:.2f}m "
                f"classes={pair['a_class']}/{pair['b_class']} "
                f"widths={pair['a_width_m']}/{pair['b_width_m']}"
            )

    serializable_records = []
    for record in records:
        serializable_records.append({
            key: value
            for key, value in record.items()
            if key != "line"
        })

    OUT_JSON.write_text(
        json.dumps({
            "nearby_records": serializable_records,
            "pair_classification": pairs,
            "true_overlaps": true_overlaps,
        }, indent=2),
        encoding="utf-8",
    )

    print()
    print(f"JSON: {OUT_JSON}")
    print("=" * 96)


if __name__ == "__main__":
    main()
