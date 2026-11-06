"""Front porches for Chester's rowhouses, twins and houses.

The 2026-11-06 Street View audit: nearly every residential capture shows a
front porch / porch roof (often one continuous porch roof along a whole row),
and none were built in game. For each rowhouse / twin / house, the face of its
largest rectangle that looks onto the nearest public street is its front; a
porch is added only where the gap between that face and the street edge
(carriageway + sidewalk, as fitted by tools/fit_roads_to_buildings.py) can take
it, so porches never reach the sidewalk.

Appends ,pb=<compass bearing the front faces>,pd=<porch depth m> to the
building's entry in src/shared/WorldData/BuildingTiles. Idempotent; run after
build_building_tiles.py and fit_roads_to_buildings.py.
    py -3 tools/add_porches.py
"""
import math
import re
import sys
from collections import Counter
from pathlib import Path

from shapely.geometry import LineString, Point
from shapely.ops import nearest_points
from shapely.strtree import STRtree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fit_roads_to_buildings as fit  # noqa: E402

STYLES = {"rowhouse", "twin", "house"}
MAX_DEPTH_M = 2.6      # source (Mercator) metres, ~2 m real
MIN_DEPTH_M = 1.5
EDGE_GAP_M = 0.5
SEARCH_M = 25.0
MIN_FACE_M = 4.0
SIDEWALK_M = fit.SIDEWALK_M
SHOP_STYLES = {"generic", "commercial", "apartment"}
SHOP_MAX_GAP_M = 6.0


def streets():
    segs, half, main = [], [], []
    for path in fit.TILES.glob("tile_*.lua"):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = fit.ROAD_RE.match(line)
            if not m or fit.kind(m) not in ("local", "main"):
                continue
            segs.append(LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))]))
            half.append(float(m["w"]) / 2 + (0 if m["sw"] else SIDEWALK_M))
            main.append(fit.kind(m) == "main")
    return segs, half, main


# Hand-detailed landmarks (Street View audit 2026-11-06): building id -> treatment
LANDMARKS = {
    "193959": "granite",   # 5-7 W 5th St: rusticated grey granite, round-arched windows
}
STORE_COLOURS = Path(__file__).resolve().parent / "storefronts" / "store_colours.csv"


def store_colours():
    """Sign / shopfront colours read off the Google Street View front captures
    of the verified corner stores (tools/storefronts/store_colours.csv)."""
    import csv
    out = {}
    if STORE_COLOURS.exists():
        with STORE_COLOURS.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                tag = ",sc=0x%s,st=0x%s" % (row["sign_bg"], row["sign_text"])
                if row["ground"]:
                    tag += ",gc=0x%s" % row["ground"]
                out[row["objectid"]] = tag
    return out


def main():
    colours = store_colours()
    segs, half, main_road = streets()
    tree = STRtree(segs)
    stats = Counter()
    line_re = re.compile(r'^(\s*\["(\d+)"\]=\{style="(\w+)",h=[\d.]+,a=([-\d.]+))(.*?)(,r=\{.*)$')
    for path in sorted(fit.BUILDINGS.glob("*.lua")):
        out = []
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = line_re.match(line)
            if not m:
                out.append(line)
                continue
            head, style, a, extra, rects_txt = m.group(1), m.group(3), float(m.group(4)), m.group(5), m.group(6)
            extra = re.sub(r",pb=[-\d.]+,pd=[\d.]+", "", extra).replace(",gs=1", "")
            extra = re.sub(r",sc=0x\w+,st=0x\w+(,gc=0x\w+)?", "", extra)
            extra = re.sub(r',lm="\w+",lb=[\d.]+', "", extra)
            if m.group(2) in colours:
                extra += colours[m.group(2)]
                stats["store_colours"] += 1
            if style in STYLES or style in SHOP_STYLES:
                stats[style] += 1  # noqa
                rects = [tuple(map(float, r)) for r in fit.RECT_RE.findall(rects_txt)]
                cx, cz, L, W = max(rects, key=lambda r: r[2] * r[3])
                ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
                ax, az = (ca, sa), (-sa, ca)          # local along / across axes in source frame
                best = None
                for n, span, offset in ((ax, W, L / 2), ((-ax[0], -ax[1]), W, L / 2),
                                        (az, L, W / 2), ((-az[0], -az[1]), L, W / 2)):
                    if span < MIN_FACE_M:
                        continue
                    mid = Point(cx + n[0] * offset, cz + n[1] * offset)
                    for i in tree.query(mid.buffer(SEARCH_M)):
                        q = nearest_points(segs[i], mid)[0]
                        dx, dz = q.x - mid.x, q.y - mid.y
                        d = math.hypot(dx, dz)
                        if d < 0.1 or (dx * n[0] + dz * n[1]) / d < 0.8:
                            continue   # street not in front of this face
                        gap = d - half[i]
                        if best is None or d < best[0]:
                            best = (d, gap, n, main_road[i])
                if best and m.group(2) in LANDMARKS:
                    bearing = math.degrees(math.atan2(best[2][0], best[2][1])) % 360
                    extra += ',lm="%s",lb=%.0f' % (LANDMARKS[m.group(2)], bearing)
                    stats["landmarks"] += 1
                elif best and style in SHOP_STYLES:
                    # main-street commercial block built to the sidewalk: shopfront ground floor
                    if best[3] and best[1] < SHOP_MAX_GAP_M:
                        extra += ",gs=1"
                        stats["shopfront_ground_floors"] += 1
                elif best:
                    depth = min(MAX_DEPTH_M, best[1] - EDGE_GAP_M)
                    if depth >= MIN_DEPTH_M:
                        bearing = math.degrees(math.atan2(best[2][0], best[2][1])) % 360
                        extra += ",pb=%.0f,pd=%.1f" % (bearing, depth)
                        stats["porches"] += 1
                    else:
                        stats["no_room"] += 1
                else:
                    stats["no_street_in_front"] += 1
            out.append(head + extra + rects_txt)
        path.write_text("\n".join(out), encoding="utf-8")
    print(dict(stats))


if __name__ == "__main__":
    main()
