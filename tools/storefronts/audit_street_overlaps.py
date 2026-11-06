"""Check building/street overlaps found in Play against Street View coverage.

Input: build/overlaps_<date>.txt ("id|street|intrusion_m;..." from the in-Play
overlap test). For each overlap, take the point on that street's centreline
(src/shared/WorldData/Tiles) closest to the building's real footprint and ask
the free Street View metadata endpoint for a pano within RADIUS_M. No pano (or
only one far from the centreline) => no drivable public street there today
(vacated / closed block, paper street, or the segment overshoots a dead end).

    py -3 tools/storefronts/audit_street_overlaps.py build/overlaps_2026-11-06.txt
"""
import glob
import json
import re
import sys
from collections import Counter
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import LineString, Point, shape
from shapely.ops import nearest_points, transform
from shapely.strtree import STRtree

sys.path.insert(0, str(Path(__file__).parent))
import google_streetview as gsv  # noqa: E402
import storefront_sweep as s  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RADIUS_M = 12
# elevated / rail / highway overlaps are a separate problem (deck height, rail as road)
SKIP = ("Commodore John Barry", "Cr Chester Secondary", "I 95", "I 476 to I 95",
        "US 13 to US 322", "US 322 to PA 291")
fwd = Transformer.from_crs(4326, 3857, always_xy=True).transform
inv = Transformer.from_crs(3857, 4326, always_xy=True).transform


def to_src(g):
    return transform(lambda x, y, z=None: (x + 8397592, y - 4837229), transform(fwd, g))


def main(path):
    pairs = [p.split("|") for p in Path(path).read_text().strip().split(";")]
    segs, names = [], []
    pat = re.compile(r'\{name="([^"]*)",x1=([-\d.]+),z1=([-\d.]+),x2=([-\d.]+),z2=([-\d.]+),'
                     r'width_m=[\d.]+,road_class="\w+",bridge=false')
    for f in glob.glob(str(ROOT / "src/shared/WorldData/Tiles/*.lua")):
        for m in pat.finditer(open(f, encoding="utf-8").read()):
            n, x1, z1, x2, z2 = m.groups()
            segs.append(LineString([(float(x1), float(z1)), (float(x2), float(z2))]))
            names.append(n)
    tree = STRtree(segs)
    src = {str(f["properties"]["OBJECTID"]): f for f in s.load(s.BUILDINGS)["features"]}
    k = gsv.key()
    meta = gsv.Meta(ROOT / "build" / "street_overlap_meta_cache.json")
    rows = []
    for bid, street, depth in pairs:
        row = {"id": bid, "street": street, "intrusion_m": float(depth)}
        rows.append(row)
        if street in SKIP:
            row["verdict"] = "skipped_elevated_rail_highway"
            continue
        if bid not in src:
            row["verdict"] = "no_footprint"
            continue
        g = to_src(shape(src[bid]["geometry"]))
        cand = [i for i in tree.query(g.buffer(25)) if names[i] == street]
        if not cand:
            row["verdict"] = "segment_not_found"
            continue
        i = min(cand, key=lambda i: segs[i].distance(g))
        p = nearest_points(segs[i], g)[0]
        lon, lat = inv(p.x - 8397592, p.y + 4837229)
        v = meta.get(lat, lon, RADIUS_M, k)
        row.update(probe_lat=round(lat, 6), probe_lon=round(lon, 6),
                   footprint_to_centreline_m=round(g.distance(segs[i]), 2))
        if not v:
            row["verdict"] = "no_streetview_within_%dm" % RADIUS_M
            continue
        px, py = fwd(v["lon"], v["lat"])
        off = segs[i].distance(Point(px + 8397592, py - 4837229))
        row["pano_offset_from_centreline_m"] = round(off, 1)
        row["pano_id"] = v["pano_id"]
        row["verdict"] = "street_driven" if off <= 6 else "pano_off_centreline"
    meta.flush()
    out = ROOT / "build" / (Path(path).stem + "_streetview.json")
    out.write_text(json.dumps(rows, indent=1))
    print(Counter(r["verdict"] for r in rows))
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
