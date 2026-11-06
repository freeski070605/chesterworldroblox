"""Google Street View reference captures of the Commodore Barry Bridge itself
(the truss over the Delaware), for modelling LandmarkBuilder's bridge:
  - views along the deck from panos on the bridge (forward, up at the truss)
  - side views of the truss from the Chester riverfront.
Output: E:\\ChesterWorld\\Data\\HighwayReference\\imagery\\google\\BARRY_MAIN_BRIDGE\\ + barry_google.json
Images (c) Google - private reference only, do not redistribute.
    py -3 tools/storefronts/google_barry.py
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402
import google_streetview as g  # noqa: E402
from google_structures import unstuds  # noqa: E402

OUT = s.DATA / "HighwayReference" / "imagery" / "google" / "BARRY_MAIN_BRIDGE"
START = (1070.0, 8161.0)          # end of the PA approach (studs)
DIR = (0.632, 0.775)              # along the bridge toward NJ (studs, +z south)
HEADING = math.degrees(math.atan2(DIR[0], -DIR[1])) % 360   # compass bearing toward NJ


def point(s_along, offset=0.0):
    return (START[0] + DIR[0] * s_along - DIR[1] * offset, START[1] + DIR[1] * s_along + DIR[0] * offset)


def bearing(a, b):
    la1, lo1 = map(math.radians, a)
    la2, lo2 = map(math.radians, b)
    y = math.sin(lo2 - lo1) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(lo2 - lo1)
    return math.degrees(math.atan2(y, x)) % 360


def main():
    k = g.key()
    meta = g.Meta(OUT / "metadata_cache.json")
    shots = []
    # on the deck, every ~400 studs from the shore to mid-river
    for i, sa in enumerate(range(200, 3400, 400)):
        lat, lon = unstuds(*point(sa))
        md = meta.get(lat, lon, 40, k)
        if not md:
            continue
        for tag, head, pitch, fov in (("ahead", HEADING, 12, 100), ("up", HEADING, 40, 100),
                                      ("back", (HEADING + 180) % 360, 12, 100)):
            dest = OUT / f"deck_{i:02d}_{tag}_{md['pano_id']}.jpg"
            if g.fetch(md["pano_id"], head, pitch, fov, dest, k):
                shots.append({"file": str(dest), "role": f"deck_{tag}", "s": sa, "pano": md["pano_id"],
                              "date": md["date"], "heading": head, "pitch": pitch, "fov": fov})
    # side views from the Chester shore, aimed at the truss
    for i, (sx, sz) in enumerate(((620, 8600), (900, 8800), (1500, 8150), (1800, 8350))):
        lat, lon = unstuds(sx, sz)
        md = meta.get(lat, lon, 80, k)
        if not md:
            continue
        for j, sa in enumerate((900, 1700, 2500)):
            target = unstuds(*point(sa))
            head = bearing((md["lat"], md["lon"]), target)
            dest = OUT / f"side_{i:02d}_{j}_{md['pano_id']}.jpg"
            if g.fetch(md["pano_id"], head, 8, 90, dest, k):
                shots.append({"file": str(dest), "role": "side", "s": sa, "pano": md["pano_id"],
                              "date": md["date"], "heading": head, "pitch": 8, "fov": 90})
    meta.flush()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "barry_google.json").write_text(json.dumps({"license": "(c) Google - private reference only",
                                                        "shots": shots}, indent=1), encoding="utf-8")
    print("shots", len(shots), "->", OUT)


if __name__ == "__main__":
    main()
