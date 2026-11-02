#!/usr/bin/env python3
r"""
ChesterWorld street-order audit.

Purpose:
Prove the current transform around Kerlin/9th mathematically.

Checks:
- 8th & Kerlin
- 9th & Kerlin
- 9th & Butler
- 9th & Parker
- 9th & Fulton
- 9th & Barclay

Then computes:
1. Is 9th north or south of 8th in the CURRENT Roblox transform?
2. When traveling from 8th & Kerlin -> 9th & Kerlin, which intersection is
   geometrically to the RIGHT: Parker or Butler?

This tool does not modify any project files.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import Point, shape
from shapely.ops import nearest_points, transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS = ROOT / "Data" / "15_RoadGeneratorPrep" / "chester_generator_roads.geojson"
WORLD = ROOT / "Data" / "16_UnityTiles" / "chester_world_manifest.json"
PLACEMENT = PROJECT / "terrain_import" / "terrain_import_manifest.json"


def load(path: Path):
    if not path.exists():
        raise SystemExit(f"Missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def clean(v):
    if v is None:
        return ""
    return " ".join(str(v).strip().split())


def road_name(props):
    lower = {str(k).lower(): v for k, v in (props or {}).items()}
    for key in ("generator_name", "st_name", "streetname", "fullname", "name"):
        value = clean(lower.get(key))
        if value and value.lower() not in {"none", "null", "nan"}:
            return value
    return ""


def street_pattern(term):
    if term == "8th":
        return re.compile(r"(?<!\d)(?:8th|eighth)(?!\d)", re.I)
    if term == "9th":
        return re.compile(r"(?<!\d)(?:9th|ninth)(?!\d)", re.I)
    return re.compile(rf"\b{re.escape(term)}\b", re.I)


def resolve_intersection(records, a_term, b_term, max_gap_m=40.0):
    pa = street_pattern(a_term)
    pb = street_pattern(b_term)

    a = [(n, g) for n, g in records if pa.search(n)]
    b = [(n, g) for n, g in records if pb.search(n)]

    if not a or not b:
        raise RuntimeError(
            f"Missing candidates for {a_term} / {b_term}: "
            f"{len(a)} / {len(b)}"
        )

    best = None
    for an, ag in a:
        for bn, bg in b:
            inter = ag.intersection(bg)
            if not inter.is_empty:
                point = inter.representative_point()
                gap = 0.0
            else:
                gap = ag.distance(bg)
                if gap > max_gap_m:
                    continue
                p1, p2 = nearest_points(ag, bg)
                point = Point(
                    (p1.x + p2.x) / 2.0,
                    (p1.y + p2.y) / 2.0,
                )

            if best is None or gap < best["gap"]:
                best = {
                    "a": an,
                    "b": bn,
                    "point": point,
                    "gap": gap,
                }

    if best is None:
        raise RuntimeError(f"Could not resolve {a_term} & {b_term}")

    return best


def main():
    road_data = load(ROADS)
    world = load(WORLD)
    placement = load(PLACEMENT)

    origin_x = float(world["origin_epsg3857"]["x"])
    origin_z = float(world["origin_epsg3857"]["z"])

    scale = float(placement["studs_per_meter"])
    center_x = float(placement["world_center_local_m"]["x"])
    center_z = float(placement["world_center_local_m"]["z"])

    project = Transformer.from_crs(
        "EPSG:4326",
        "EPSG:3857",
        always_xy=True,
    ).transform

    records = []
    for feature in road_data.get("features", []):
        name = road_name(feature.get("properties") or {})
        geometry = feature.get("geometry")
        if not name or not geometry:
            continue
        try:
            records.append((name, shp_transform(project, shape(geometry))))
        except Exception:
            pass

    targets = [
        ("8th", "Kerlin"),
        ("9th", "Kerlin"),
        ("9th", "Butler"),
        ("9th", "Parker"),
        ("9th", "Fulton"),
        ("9th", "Barclay"),
    ]

    results = {}

    def to_coords(point):
        local_x = point.x - origin_x
        local_z = point.y - origin_z

        roblox_x = (local_x - center_x) * scale
        roblox_z = (local_z - center_z) * scale

        lonlat = Transformer.from_crs(
            "EPSG:3857", "EPSG:4326", always_xy=True
        ).transform(point.x, point.y)

        return {
            "local_x": local_x,
            "local_z": local_z,
            "x": roblox_x,
            "z": roblox_z,
            "lon": lonlat[0],
            "lat": lonlat[1],
        }

    print("=" * 72)
    print("CHESTERWORLD STREET ORDER AUDIT")
    print("=" * 72)
    print("Current transform assumption: +X east, +Z north")
    print()

    for a, b in targets:
        item = resolve_intersection(records, a, b)
        coords = to_coords(item["point"])
        results[(a, b)] = coords

        print(
            f"{a:>4} & {b:<8} "
            f"Roblox X={coords['x']:9.2f} Z={coords['z']:9.2f} | "
            f"lon={coords['lon']:.6f} lat={coords['lat']:.6f} | "
            f"gap={item['gap']:.2f}m"
        )

    p8 = results[("8th", "Kerlin")]
    p9 = results[("9th", "Kerlin")]
    butler = results[("9th", "Butler")]
    parker = results[("9th", "Parker")]
    fulton = results[("9th", "Fulton")]
    barclay = results[("9th", "Barclay")]

    travel_x = p9["x"] - p8["x"]
    travel_z = p9["z"] - p8["z"]
    travel_len = math.hypot(travel_x, travel_z)

    fx = travel_x / travel_len
    fz = travel_z / travel_len

    # Right-hand direction in Roblox X/Z plane.
    # For forward +Z (north), right must be +X (east).
    rx = fz
    rz = -fx

    def relation(target):
        dx = target["x"] - p9["x"]
        dz = target["z"] - p9["z"]
        right_dot = dx * rx + dz * rz
        forward_dot = dx * fx + dz * fz
        distance = math.hypot(dx, dz)
        return right_dot, forward_dot, distance

    b_right, b_forward, b_dist = relation(butler)
    p_right, p_forward, p_dist = relation(parker)

    print()
    print("-" * 72)
    print("NORTH/SOUTH TEST")
    print("-" * 72)

    dz = p9["z"] - p8["z"]
    dlat = p9["lat"] - p8["lat"]

    print(f"Raw latitude change 8th -> 9th: {dlat:+.8f} degrees")
    print(f"Roblox Z change    8th -> 9th: {dz:+.2f} studs")

    if dlat > 0:
        print("REAL WORLD: 9th is NORTH of 8th.")
    else:
        print("REAL WORLD: 9th is SOUTH of 8th. [unexpected]")

    if dz > 0:
        print("CURRENT ROBLOX TRANSFORM: 9th is +Z / NORTH of 8th.")
    else:
        print("CURRENT ROBLOX TRANSFORM: 9th is -Z / SOUTH of 8th.")

    print()
    print("-" * 72)
    print("RIGHT-TURN TEST: travel 8th & Kerlin -> 9th & Kerlin")
    print("-" * 72)
    print(
        f"Travel vector: X={travel_x:+.2f}, Z={travel_z:+.2f} "
        f"(unit {fx:+.3f}, {fz:+.3f})"
    )
    print(
        f"Computed RIGHT vector: X={rx:+.3f}, Z={rz:+.3f}"
    )
    print()
    print(
        f"Butler: right-dot={b_right:+.2f}, "
        f"forward-dot={b_forward:+.2f}, distance={b_dist:.1f}"
    )
    print(
        f"Parker: right-dot={p_right:+.2f}, "
        f"forward-dot={p_forward:+.2f}, distance={p_dist:.1f}"
    )

    predicted_right = "PARKER" if p_right > b_right else "BUTLER"
    print()
    print(f"CURRENT DATA SAYS A RIGHT TURN SHOULD LEAD TOWARD: {predicted_right}")

    print()
    print("-" * 72)
    print("9TH STREET EAST/WEST ORDER BY ROBLOX X")
    print("-" * 72)

    ordered = [
        ("Butler", butler),
        ("Kerlin", p9),
        ("Parker", parker),
        ("Fulton", fulton),
        ("Barclay", barclay),
    ]
    ordered.sort(key=lambda item: item[1]["x"])

    for name, coords in ordered:
        print(f"{coords['x']:9.2f}  {name}")

    print()
    print("Expected west -> east order:")
    print("Butler -> Kerlin -> Parker -> Fulton -> Barclay")
    print("=" * 72)


if __name__ == "__main__":
    main()
