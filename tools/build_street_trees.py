"""Trees where Chester actually has tree canopy.

Source: PASDA Pennsylvania High Resolution Land Cover 2013, 1 m canopy masks
(E:\\ChesterWorld\\Data\\12_Vegetation\\Canopy_2013, EPSG:3857). The 2026-11-06
image audit found no trees anywhere in the game while mature street and yard
trees dominate most Street View captures.

Candidates on a jittered SPACING_M grid inside Chester City (+BUFFER_M) are kept
where the canopy covers at least MIN_COVER of a crown-sized disc; the crown
size follows the surrounding canopy. Trunks never stand inside building
rectangles (BuildingTiles), on road carriageways or on highway / rail corridors
(Tiles). Output: src/shared/WorldData/StreetTrees.lua as {x, z, crown_m, height_m}
in source metres, built in game by src/server/World/TreeBuilder.server.lua.

    py -3 tools/build_street_trees.py
"""
import json
import math
import random
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from shapely.geometry import LineString, Point
from shapely.ops import transform
from shapely.prepared import prep
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "storefronts"))
import fit_roads_to_buildings as fit  # noqa: E402
import storefront_sweep as sweep  # noqa: E402

CANOPY = Path(r"E:\ChesterWorld\Data\12_Vegetation\Canopy_2013")
OUT = ROOT / "src" / "shared" / "WorldData" / "StreetTrees.lua"
X_OFFSET, Z_OFFSET = 8397592.0, -4837229.0
SPACING_M = 12.0
BUFFER_M = 120.0
MIN_COVER = 0.6
BUILDING_CLEAR_M = 1.2
ROAD_CLEAR_M = 0.4
CORRIDOR_CLEAR_M = 4.0   # highways and rail: keep the whole corridor clear
CORRIDOR = {"motorway", "motorway_link", "trunk", "trunk_link"}


def main():
    meta = json.loads((CANOPY / "chester_tree_canopy_metadata.json").read_text())
    tiles = []
    for t in meta["tiles"]:
        mask = np.asarray(Image.open(CANOPY / "Masks" / t["mask_file"]).convert("L")) > 0
        tiles.append((t["bounds"], mask))

    def cover(mx, my, r):
        for b, mask in tiles:
            if b["xmin"] <= mx < b["xmax"] and b["ymin"] <= my < b["ymax"]:
                c = int(mx - b["xmin"])
                rr = int(b["ymax"] - my)
                r0, r1 = max(rr - r, 0), min(rr + r + 1, mask.shape[0])
                c0, c1 = max(c - r, 0), min(c + r + 1, mask.shape[1])
                win = mask[r0:r1, c0:c1]
                if win.size == 0:
                    return 0.0
                yy, xx = np.ogrid[r0 - rr:r1 - rr, c0 - c:c1 - c]
                disc = (yy * yy + xx * xx) <= r * r
                return float(win[disc].mean()) if disc.any() else 0.0
        return 0.0

    to_src = lambda x, y, z=None: (x + X_OFFSET, y + Z_OFFSET)
    city = transform(to_src, transform(_to3857(), sweep.city_polygon()))  # lon/lat -> source m
    area = prep(city.buffer(BUFFER_M))

    buildings = STRtree(fit.footprints())
    roads, widths = [], []
    for path in fit.TILES.glob("tile_*.lua"):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = fit.ROAD_RE.match(line)
            if not m:
                continue
            seg = LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))])
            w = float(m["w"]) / 2
            if m["cls"] in CORRIDOR or m["name"] in fit.RAIL_NAMES or m["bridge"] == "true":
                w += CORRIDOR_CLEAR_M
            else:
                w += ROAD_CLEAR_M
            roads.append(seg)
            widths.append(w)
    road_tree = STRtree(roads)

    rng = random.Random(20261106)
    minx, miny, maxx, maxy = city.buffer(BUFFER_M).bounds
    trees = []
    stats = {"candidates": 0, "no_canopy": 0, "building": 0, "road": 0}
    y = miny
    while y < maxy:
        x = minx
        while x < maxx:
            px = x + rng.uniform(-0.35, 0.35) * SPACING_M
            pz = y + rng.uniform(-0.35, 0.35) * SPACING_M
            x += SPACING_M
            p = Point(px, pz)
            if not area.contains(p):
                continue
            stats["candidates"] += 1
            mx, my = px - X_OFFSET, pz - Z_OFFSET
            if cover(mx, my, 3) < MIN_COVER:
                stats["no_canopy"] += 1
                continue
            if any(buildings.geometries[i].distance(p) < BUILDING_CLEAR_M
                   for i in buildings.query(p.buffer(BUILDING_CLEAR_M))):
                stats["building"] += 1
                continue
            if any(roads[i].distance(p) < widths[i] for i in road_tree.query(p.buffer(20))):
                stats["road"] += 1
                continue
            wide = cover(mx, my, 7)
            crown = round(6.0 + 8.0 * wide + rng.uniform(-1, 1), 1)
            height = round(crown * 0.77 * rng.uniform(1.0, 1.3) + 2.0, 1)  # crown is Mercator m, height real m
            trees.append((round(px, 1), round(pz, 1), crown, height))
        y += SPACING_M
    stats["trees"] = len(trees)
    print(stats)
    lines = ["-- Generated by tools/build_street_trees.py from the PASDA 2013 1 m tree canopy.",
             "-- {x, z, crown_m, height_m} in source metres (x east, z north).",
             "return {"]
    for t in trees:
        lines.append("{%s,%s,%s,%s}," % t)
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", OUT)


def _to3857():
    from pyproj import Transformer
    tf = Transformer.from_crs(4326, 3857, always_xy=True).transform
    return tf


if __name__ == "__main__":
    main()
