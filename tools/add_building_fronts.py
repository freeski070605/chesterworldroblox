"""Front / side / units for every building (real-buildings pass, 2026-11-07).

Buildings were extruded boxes with the same door-and-window (homes) or
shop-glass (stores) texture tiled on all four walls. TileBuilderV2's
real-building facades need to know, per building:

  fb   compass bearing the front faces: the nearest public street from the
       building (a store: the street its first shop faces, from ss=)
  fb2  a second street the building also faces when it stands on a corner
       (distinct name, within CORNER_M of the front's distance, >= 50 deg off)
  un   units along the front of a rowhouse block (one front + back door each)

Appended as ,fb=<deg>[,fb2=<deg>][,un=<n>] before r={. Idempotent: the three
fields are stripped and rewritten. Run after tools/storefronts/add_store_identity.py.

    py -3 tools/add_building_fronts.py [--check]
"""
import math
import re
import sys
from collections import Counter
from pathlib import Path

from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fit_roads_to_buildings as fit  # noqa: E402

SEARCH_M = 70.0
CORNER_M = 6.0
UNIT_M = 6.4          # a Chester rowhouse unit, ~4.9 m real, in source (Mercator) metres
ROW_STYLES = {"rowhouse"}
LINE_RE = re.compile(r'^(\s*\["(\d+)"\]=\{)(.*?)(,r=\{.*)$')
RECT_RE = re.compile(r'\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\}')


def bearing(dx, dz):
    """compass bearing (deg) of a source-metre direction (x east, z north)"""
    return math.degrees(math.atan2(dx, dz)) % 360


def face_bearing(rect, street):
    """compass bearing of the outward normal of the rect face nearest the
    street (source metres: x east, z north). A shop or house fronts on its
    nearest face, not on whichever face points roughly toward the street (a
    narrow strip unit 8 m wide x 25 m deep would otherwise get its side wall)."""
    from shapely.geometry import Point as _P
    c = rect.centroid
    pts = list(rect.exterior.coords)[:4]
    best = None
    for i in range(4):
        (x1, z1), (x2, z2) = pts[i], pts[(i + 1) % 4]
        mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
        d = street.distance(_P(mx, mz))
        if best is None or d < best[0]:
            best = (d, mx - c.x, mz - c.y)
    return math.degrees(math.atan2(best[1], best[2])) % 360


def main(check=False):
    segs, names = [], []
    for path in sorted(fit.TILES.glob("tile_*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = fit.ROAD_RE.match(line)
            if m and fit.kind(m) in ("local", "main", "minor") and m["name"] not in fit.RAIL_NAMES:
                segs.append(LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))]))
                names.append(m["name"])
    tree = STRtree(segs)
    stats = Counter()
    files = 0
    for path in sorted(fit.BUILDINGS.glob("*.lua")):
        lines = path.read_text(encoding="utf-8").split("\n")
        out = []
        for line in lines:
            m = LINE_RE.match(line)
            if not m:
                out.append(line)
                continue
            head, bid, body, tail = m.groups()
            body = re.sub(r",fb=[\d.]+|,fb2=[\d.]+|,un=\d+", "", body)
            a = math.radians(float(re.search(r"\ba=([-\d.]+)", body).group(1)))
            ca, sa = math.cos(a), math.sin(a)
            rects = [tuple(map(float, r)) for r in RECT_RE.findall(tail.split("}}", 1)[0] + "}")]
            if not rects:
                out.append(line)
                continue
            polys = [Polygon([(cx + ca * u * L / 2 - sa * v * W / 2, cz + sa * u * L / 2 + ca * v * W / 2)
                              for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1))]) for cx, cz, L, W in rects]
            shape = unary_union(polys)
            c = shape.centroid
            near = [(segs[j].distance(shape), j) for j in tree.query(shape.buffer(SEARCH_M))]
            near = [(d, j) for d, j in near if d < SEARCH_M]
            extra = ""
            store = re.search(r',ss=\{\{"[^"]*",\d+,(\d+)', body)
            if store:
                fb = float(store.group(1))
                stats["store_front"] += 1
            elif re.search(r",pb=([\d.]+)", body):
                fb = float(re.search(r",pb=([\d.]+)", body).group(1))
                stats["porch_front"] += 1
            elif near:
                d, j = min(near)
                fb = face_bearing(max(polys, key=lambda g: g.area), segs[j])
                stats["street_front"] += 1
            else:
                stats["no_street"] += 1
                out.append(head + body + tail)
                continue
            extra += ",fb=%.0f" % fb
            # corner: a differently named street almost as close, well off the front
            if near:
                d0 = min(near)[0]
                front_name = names[min(near)[1]]
                for d, j in sorted(near):
                    if d > d0 + CORNER_M:
                        break
                    if names[j] == front_name:
                        continue
                    b2 = face_bearing(max(polys, key=lambda g: g.area), segs[j])
                    if abs((b2 - fb + 180) % 360 - 180) >= 50:
                        extra += ",fb2=%.0f" % b2
                        stats["corner"] += 1
                        break
            style = re.search(r'style="(\w+)"', body)
            if style and style.group(1) in ROW_STYLES:
                # front length of the largest rect: its extent across the front bearing
                cx, cz, L, W = max(rects, key=lambda r: r[2] * r[3])
                fa = math.radians(fb)
                fx, fz = math.sin(fa), math.cos(fa)      # front direction (x east, z north)
                along_dot = abs(ca * fx + sa * fz)         # rect L axis vs front direction
                front_len = W if along_dot > 0.7071 else L
                un = max(1, round(front_len / UNIT_M))
                extra += ",un=%d" % un
                stats["units"] += un
            out.append(head + body + extra + tail)
        if out != lines:
            files += 1
            if not check:
                path.write_text("\n".join(out), encoding="utf-8")
    stats["files"] = files
    print(dict(stats))


if __name__ == "__main__":
    main("--check" in sys.argv)
