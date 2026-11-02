#!/usr/bin/env python3
r"""
Generate exact runtime route-proof coordinates from Chester's raw road GIS.

Creates:
    src/shared/RouteProof.lua

Targets:
    8th & Kerlin
    9th & Kerlin
    9th & Butler
    9th & Parker
    9th & Fulton
    9th & Barclay

Coordinates are converted through the same current WorldPlacement transform.
No city data is modified.
"""

from __future__ import annotations

import json
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
OUT = PROJECT / "src" / "shared" / "RouteProof.lua"


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def clean(v):
    return " ".join(str(v or "").strip().split())


def road_name(props):
    for key in ("generator_name", "St_Name", "StreetName", "FULLNAME", "NAME", "name"):
        val = clean((props or {}).get(key))
        if val and val.lower() not in {"none", "null", "nan"}:
            return val
    return ""


def pat(term):
    if term == "8th":
        return re.compile(r"(?<!\d)(?:8th|eighth)(?!\d)", re.I)
    if term == "9th":
        return re.compile(r"(?<!\d)(?:9th|ninth)(?!\d)", re.I)
    return re.compile(rf"\b{re.escape(term)}\b", re.I)


def main():
    roads = load(ROADS)
    world = load(WORLD)
    placement = load(PLACEMENT)

    origin_x = float(world["origin_epsg3857"]["x"])
    origin_z = float(world["origin_epsg3857"]["z"])
    scale = float(placement["studs_per_meter"])
    cx = float(placement["world_center_local_m"]["x"])
    cz = float(placement["world_center_local_m"]["z"])

    project = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True).transform

    records = []
    for f in roads.get("features", []):
        name = road_name(f.get("properties") or {})
        if not name or not f.get("geometry"):
            continue
        try:
            g = shp_transform(project, shape(f["geometry"]))
        except Exception:
            continue
        records.append((name, g))

    def resolve(a_term, b_term):
        aa = [(n, g) for n, g in records if pat(a_term).search(n)]
        bb = [(n, g) for n, g in records if pat(b_term).search(n)]

        best = None
        for an, ag in aa:
            for bn, bg in bb:
                inter = ag.intersection(bg)
                if not inter.is_empty:
                    p = inter.representative_point()
                    gap = 0.0
                else:
                    gap = ag.distance(bg)
                    if gap > 30:
                        continue
                    pa, pb = nearest_points(ag, bg)
                    p = Point((pa.x + pb.x) / 2, (pa.y + pb.y) / 2)

                if best is None or gap < best[0]:
                    best = (gap, p)

        if best is None:
            raise RuntimeError(f"Could not resolve {a_term} & {b_term}")

        p = best[1]
        local_x = p.x - origin_x
        local_z = p.y - origin_z

        return {
            "x": (local_x - cx) * scale,
            "z": (local_z - cz) * scale,
        }

    targets = [
        ("eightKerlin", "8th", "Kerlin", "8TH & KERLIN", "Eight"),
        ("nineKerlin", "9th", "Kerlin", "9TH & KERLIN", "K"),
        ("nineButler", "9th", "Butler", "9TH & BUTLER", "B"),
        ("nineParker", "9th", "Parker", "9TH & PARKER", "P"),
        ("nineFulton", "9th", "Fulton", "9TH & FULTON", "U"),
        ("nineBarclay", "9th", "Barclay", "9TH & BARCLAY", "L"),
    ]

    rows = []
    print("=" * 72)
    print("CHESTERWORLD RUNTIME ROUTE PROOF")
    print("=" * 72)

    for key, a, b, label, hotkey in targets:
        pos = resolve(a, b)
        rows.append((key, label, hotkey, pos))
        print(f"{label:<18} X={pos['x']:9.2f} Z={pos['z']:9.2f}")

    lua = ["return {"]
    for key, label, hotkey, pos in rows:
        lua += [
            f"    {key} = {{",
            f'        label = "{label}",',
            f'        hotkey = "{hotkey}",',
            f"        x = {pos['x']:.3f},",
            f"        z = {pos['z']:.3f},",
            "    },",
        ]
    lua.append("}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lua) + "\n", encoding="utf-8")

    print()
    print(f"Wrote {OUT}")
    print("=" * 72)


if __name__ == "__main__":
    main()
