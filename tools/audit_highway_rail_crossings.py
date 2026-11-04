#!/usr/bin/env python3
"""Audit rail corridors crossing grade-tagged road bridges, non-destructively.

This audits HORIZONTAL source crossings only, not vertical clearance.
The RoadTerrainConformer checks roads, but rail lines are stored in a
separate regional tile layer and were omitted from its crossing counts.
"""
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from shapely.geometry import LineString, Point
from shapely.strtree import STRtree

import package_roblox_street_v3_world as base
import package_roblox_street_v4_world as grade

ROOT = Path(r"E:\ChesterWorld\Data\18_RegionalTiles_StreetV3")
OUT = Path(__file__).resolve().parent / "highway_rail_crossings.json"


def lines(feature):
    for raw in base.geometry_lines(feature.get("geometry") or {}):
        if len(raw) >= 2:
            coords = [(float(p[0]), float(p[1])) for p in raw if len(p) >= 2]
            if len(coords) >= 2:
                yield LineString(coords)


def main():
    discovered = list(base.discover_tiles(ROOT))
    if len(discovered) != 102:
        raise SystemExit(f"Expected 102 source regional JSON tiles, found {len(discovered)}")

    roads, rails = [], []
    rail_features = 0
    for entry, source in discovered:
        tile = base.load_json(source)
        for road in grade.convert_tile(tile)["roads"]:
            if road["bridge"] or road["layer"] > 0:
                line = LineString([(road["x1"], road["z1"]),
                                   (road["x2"], road["z2"])])
                if line.length > 0.1:
                    roads.append((road, line))
        layers = tile.get("layers") or {}
        for key in ("rail", "railways", "railroads"):
            for feature in layers.get(key, []) or []:
                rail_features += 1
                properties = feature.get("properties") or {}
                name = (base.first_text(properties, (
                    "name", "railway", "rail_name", "operator",
                    "ref", "generator_name")) or "Rail")
                for line in lines(feature):
                    rails.append((name, line))

    print("=" * 72)
    print("CHESTERWORLD - BRIDGE / RAILWAY GEOMETRY AUDIT")
    print("=" * 72)
    print(f"Bridge road segments: {len(roads)}")
    print(f"Rail features:        {rail_features}")
    print(f"Rail segments:        {len(rails)}")

    crossings = {}
    # The source tiles can duplicate a feature at a seam; dedupe by position.
    geometries = [line for _, line in rails]
    rail_tree = STRtree(geometries) if geometries else None
    for road, line in roads:
        for candidate in (rail_tree.query(line) if rail_tree else []):
            rail_name, rail_line = rails[int(candidate)]
            if not line.intersects(rail_line):
                continue
            intersection = line.intersection(rail_line)
            if intersection.is_empty:
                continue
            if isinstance(intersection, Point):
                points = [intersection]
            elif intersection.geom_type == "MultiPoint":
                points = list(intersection.geoms)
            else:
                continue
            for point in points:
                x, z = float(point.x), float(point.y)
                token = (round(x, 1), round(z, 1), str(road["name"]))
                crossings[token] = {
                    "source_x_m": round(x, 3),
                    "source_z_m": round(z, 3),
                    "road": str(road["name"]),
                    "rail": rail_name,
                    "grade_group": str(road.get("grade_group", "")),
                    "horizontal_overlap_only": True,
                    "vertical_clearance_verified": False,
                }

    records = list(crossings.values())
    near_i95_kerlin = [
        item for item in records
        if (item["source_x_m"] - 6974.5)**2
           + (item["source_z_m"] - 7297.0)**2 < 350**2
    ]
    report = {
        "rail_source_features": rail_features,
        "bridge_source_segments": len(roads),
        "horizontal_bridge_rail_crossings": len(records),
        "near_i95_kerlin": near_i95_kerlin,
        "vertical_clearance_verified": False,
        "notes": "Rail is not included in Roblox Roads; a horizontal crossing "
                 "cannot establish actual underpass elevation or clearance.",
        "crossings": records,
    }
    OUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Horizontal bridge/rail intersections: {len(records)}")
    print(f"I-95/Kerlin area matches:            {len(near_i95_kerlin)}")
    print("Vertical clearance: UNVERIFIED (needs grade data + rendered rail)")
    print(f"Report: {OUT}")
    if not rails:
        print("WARNING: No rail geometry was present in the 102 source tiles.")
    elif not records:
        print("WARNING: No exact bridge/rail centerline crossings found; "
              "this does NOT prove there are no rail underpasses.")
    print("=" * 72)


if __name__ == "__main__":
    main()
