"""Buildings overlapping the rail beds at their built width (RailProfile /
TileBuilderV2 buildProfiledRail: bed + tracks, plus abutment margin)."""
import sys
from collections import Counter
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
import fit_roads_to_buildings as fit
from shapely.geometry import LineString
from shapely.strtree import STRtree

polys, keys = fit.footprints(with_keys=True)
tree = STRtree(polys)
hits, worst = Counter(), Counter()
seen = {}
for path in sorted(fit.TILES.glob("tile_*.lua")):
    for line in path.read_text(encoding="utf-8").split("\n"):
        m = fit.ROAD_RE.match(line)
        if not m or m["name"] not in fit.RAIL_NAMES:
            continue
        seg = LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))])
        if seg.length < 0.05:
            continue
        w = fit.rail_footprint_m(m["name"]) if hasattr(fit, "rail_footprint_m") else fit.RAIL_BED_M
        poly = seg.buffer(w / 2, cap_style=2)
        for i in tree.query(poly):
            a = polys[i].intersection(poly).area
            if a > 0.5:
                seen[keys[i]] = max(seen.get(keys[i], 0), a), m["name"]
for k, (a, name) in seen.items():
    hits[name] += 1
    worst[name] = max(worst[name], a)
print("blocks overlapping:", dict(hits))
print("worst overlap m2:", {k: round(v, 1) for k, v in worst.items()})
