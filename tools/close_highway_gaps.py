"""Close short gaps in the county freeway centrelines.

The county splits a carriageway where a bridge record starts and sometimes
leaves a gap of 10-20 m between the at-grade record's end and the bridge
record's start (I-95 by Widener: county 62 -> 854 and 63 -> 559, ~14 m).
HighwayProfile then builds two unconnected strokes - one ending at grade, one
starting on the deck 25 studs higher - and the piece between is dropped as too
steep: a hole with an abutment wall across the freeway.

For every dangling end A of a motorway / motorway_link record and a dangling
end B of a record with the same name within MAX_GAP_M, where B lies ahead of A
along A's direction and B's record continues the same way, a connector record
A -> B is added (attributes copied from A's record). Idempotent; --check only
reports.

Pipeline: after fix_ramp_widths, before fit_roads_to_buildings.
"""
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TILES = ROOT / "src" / "shared" / "WorldData" / "Tiles"
MAX_GAP_M = 20.0
ALIGN = 0.85
LINE_RE = re.compile(r'^(?P<indent>\s*)\{name="(?P<name>[^"]*)",x1=(?P<x1>[-\d.]+),z1=(?P<z1>[-\d.]+),'
                     r'x2=(?P<x2>[-\d.]+),z2=(?P<z2>[-\d.]+),(?P<rest>width_m=[-\d.]+,road_class="(?P<cls>\w+)".*)$')


def key(x, z):
    return (round(x * 2), round(z * 2))


def main(check=False):
    segs = []
    for path in sorted(TILES.glob("tile_*.lua")):
        for i, line in enumerate(path.read_text(encoding="utf-8").split("\n")):
            m = LINE_RE.match(line)
            if m:
                segs.append({"path": path, "line": i, "m": m, "cls": m["cls"], "name": m["name"],
                             "a": (float(m["x1"]), float(m["z1"])), "b": (float(m["x2"]), float(m["z2"]))})
    degree = defaultdict(int)
    for s in segs:
        degree[key(*s["a"])] += 1
        degree[key(*s["b"])] += 1
    ends = []   # dangling freeway ends: (point, outward unit dir, seg)
    for s in segs:
        if s["cls"] not in ("motorway", "motorway_link"):
            continue
        (ax, az), (bx, bz) = s["a"], s["b"]
        length = math.hypot(bx - ax, bz - az)
        if length < 0.5:
            continue
        ux, uz = (bx - ax) / length, (bz - az) / length
        if degree[key(ax, az)] == 1:
            ends.append(((ax, az), (-ux, -uz), s))
        if degree[key(bx, bz)] == 1:
            ends.append(((bx, bz), (ux, uz), s))
    added, used = [], set()
    for i, (pa, da, sa) in enumerate(ends):
        if i in used:
            continue
        best = None
        for j, (pb, db, sb) in enumerate(ends):
            if j == i or j in used or sb is sa or sb["name"] != sa["name"]:
                continue
            dx, dz = pb[0] - pa[0], pb[1] - pa[1]
            d = math.hypot(dx, dz)
            if d < 0.5 or d > MAX_GAP_M:
                continue
            ahead = (dx * da[0] + dz * da[1]) / d
            facing = da[0] * db[0] + da[1] * db[1]     # outward dirs point at each other
            if ahead > ALIGN and facing < -ALIGN and (best is None or d < best[0]):
                best = (d, j, pb)
        if best:
            used.update({i, best[1]})
            added.append((sa, pa, best[2], best[0]))
    by_path = defaultdict(list)
    for sa, pa, pb, d in added:
        m = sa["m"]
        line = '%s{name="%s",x1=%s,z1=%s,x2=%s,z2=%s,%s' % (
            m["indent"], m["name"], round(pa[0], 3), round(pa[1], 3), round(pb[0], 3), round(pb[1], 3), m["rest"])
        by_path[sa["path"]].append((sa["line"], line))
        print("  close %-28s %.1f m at (%.0f, %.0f) studs" % (
            sa["name"], d, (pa[0] - 6347.889) * 3, -(pa[1] - 7201.973) * 3))
    if not check:
        for path, inserts in by_path.items():
            lines = path.read_text(encoding="utf-8").split("\n")
            for index, line in sorted(inserts, reverse=True):
                lines.insert(index + 1, line)
            path.write_text("\n".join(lines), encoding="utf-8")
    print({"gaps_closed": len(added), "check": check})


if __name__ == "__main__":
    main("--check" in sys.argv)
