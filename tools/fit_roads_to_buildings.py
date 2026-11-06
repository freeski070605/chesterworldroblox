"""Fit ground-level roads in src/shared/WorldData/Tiles to the building
footprints in src/shared/WorldData/BuildingTiles (what the game builds).

Audit 2026-11-06 (in-Play overlap test + Street View metadata):
  * driveways / parking aisles / service lanes / alleys / county "Private"
    stubs were paved at full width straight through buildings;
  * Chester's back streets (Woodrow, Union, Mary, James, Congress ...) are
    ~4 m lanes with houses and garages built to the edge - Street View drives
    them and the real footprints sit 1.5-2 m from the centreline - but were
    paved as 7.5 m streets with 1.7 m sidewalks on both sides;
  * some public street segments run through buildings (vacated / unbuilt
    blocks the county centreline file still carries).
The public network itself is placed correctly (Street View pano GPS sits a
median 0.9 m from the centrelines), so roads are fitted, buildings are not moved.

Minor roads (MINOR_CLASSES, county "Private"):
  cut where the centreline enters a footprint (+CLEAR_M); narrow a piece that
  passes closer than its half width; drop it if under MIN_WIDTH_M.
Public streets (STREET_CLASSES):
  cut only where the centreline runs inside a footprint; if buildings crowd at
  least CROWDED_FRACTION of a segment, narrow it to the measured corridor
  (local streets down to STREET_MIN_WIDTH_M, main roads to
  MAIN_MIN_WIDTH_M) and drop its sidewalks (sidewalk=false) when they cannot fit.
Highways, bridges, tunnels, rail lines and grade-separated layers are never touched.

Run after tools/build_building_tiles.py. Idempotent.
    py -3 tools/fit_roads_to_buildings.py [--check]
"""
import math
import re
import sys
from collections import Counter
from pathlib import Path

from shapely.geometry import LineString, MultiLineString, Point, Polygon
from shapely.ops import substring, unary_union
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
TILES = ROOT / "src" / "shared" / "WorldData" / "Tiles"
BUILDINGS = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"

MINOR_CLASSES = {"service", "parking_aisle", "driveway", "alley"}
LOCAL_CLASSES = {"residential", "local", "unclassified", "living_street"}
MAIN_CLASSES = {"tertiary", "secondary", "primary"}
RAIL_NAMES = {"Cr Chester Secondary", "Amtrak Ne Corridor", "Linwood Industrial Track", "Csx Phila Subdivision"}

CLEAR_M = 0.3            # gap kept between road edge and wall
MIN_WIDTH_M = 2.6        # minor road narrower than this is dropped
MIN_PIECE_M = 1.5
END_TRIM_M = 3.0         # piece ends may stop at the wall they were cut against
SNAP_TOL_M = 0.02        # coordinates are written to 3 decimals
TOL_M = 0.05             # changes smaller than this are ignored (stable reruns)
SIDEWALK_M = (5.0 + 0.1) / 3.0   # WorldConfig SIDEWALK_WIDTH + GAP, studs -> source m
STREET_MIN_WIDTH_M = 3.6
MAIN_MIN_WIDTH_M = {"tertiary": 6.0, "secondary": 7.0, "primary": 8.0}  # absolute: reruns stay stable
CROWDED_FRACTION = 0.2
SAMPLE_M = 2.0
FOOTWAY_WIDTH_M = 3.0

ROAD_RE = re.compile(
    r'^(?P<indent>\s*)\{name="(?P<name>[^"]*)",x1=(?P<x1>[-\d.]+),z1=(?P<z1>[-\d.]+),'
    r'x2=(?P<x2>[-\d.]+),z2=(?P<z2>[-\d.]+),width_m=(?P<w>[-\d.]+),road_class="(?P<cls>\w+)",'
    r'bridge=(?P<bridge>\w+),tunnel=(?P<tunnel>\w+),layer=(?P<layer>[-\d]+)(?P<sw>,sidewalk=false)?(?P<rest>.*)$')


RECT_RE = re.compile(r'\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\}')


def footprints(with_keys=False):
    polys, keys = [], []
    for path in sorted(BUILDINGS.glob("*.lua")):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.search(r'\["(\d+)"\]=\{(.*)\}', line)
            if not m:
                continue
            a = math.radians(float(re.search(r'\ba=([-\d.]+)', m.group(2)).group(1)))
            ca, sa = math.cos(a), math.sin(a)
            for k, (cx, cz, L, W) in enumerate(RECT_RE.findall(m.group(2).split(",r={", 1)[1])):
                cx, cz, L, W = map(float, (cx, cz, L, W))
                polys.append(Polygon([(cx + ca * u * L / 2 - sa * v * W / 2, cz + sa * u * L / 2 + ca * v * W / 2)
                                      for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1))]))
                keys.append((path.name, m.group(1), k))
    return (polys, keys) if with_keys else polys


def yield_buildings_to_main_roads(check, stats):
    """Main roads (driven by Street View) win over building rectangles their
    centreline runs through: those rectangles are removed from BuildingTiles."""
    polys, keys = footprints(with_keys=True)
    tree = STRtree(polys)
    drop = {}
    for path in sorted(TILES.glob("tile_*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = ROAD_RE.match(line)
            if not m or kind(m) != "main":
                continue
            seg = LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))])
            for i in tree.query(seg):
                if polys[i].buffer(-0.25).intersects(seg):
                    fname, bid, k = keys[i]
                    drop.setdefault((fname, bid), set()).add(k)
    for fname in sorted({f for f, _ in drop}):
        path = BUILDINGS / fname
        out = []
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = re.match(r'^(\s*\["(\d+)"\]=\{.*?,r=\{)(.*)(\}\},?\s*)$', line)
            if m and (fname, m.group(2)) in drop:
                rects = RECT_RE.findall(m.group(3))
                gone = drop[(fname, m.group(2))]
                kept = [r for k, r in enumerate(rects) if k not in gone]
                stats["building_rects_yielded"] += len(rects) - len(kept)
                if not kept:
                    stats["buildings_removed_on_main_roads"] += 1
                    continue
                line = m.group(1) + ",".join("{%s,%s,%s,%s}" % r for r in kept) + m.group(4)
            out.append(line)
        if not check:
            path.write_text("\n".join(out), encoding="utf-8")


def kind(m):
    if m["bridge"] != "false" or m["tunnel"] != "false" or m["layer"] != "0" or m["name"] in RAIL_NAMES:
        return None
    if m["cls"] in MINOR_CLASSES or (m["name"] == "Private" and m["cls"] in LOCAL_CLASSES):
        return "minor"
    if m["cls"] in LOCAL_CLASSES:
        return "local"
    if m["cls"] in MAIN_CLASSES:
        return "main"
    return None


def pieces(geom):
    if geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [geom]
    if isinstance(geom, MultiLineString):
        return list(geom.geoms)
    return [g for g in getattr(geom, "geoms", []) if isinstance(g, LineString)]


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def fit_minor(seg, width, near):
    blocked = unary_union([p.buffer(CLEAR_M - SNAP_TOL_M) for p in near])
    kept = []
    for piece in pieces(seg.difference(blocked)):
        if piece.length < MIN_PIECE_M:
            continue
        trim = min(END_TRIM_M, piece.length / 3)
        body = substring(piece, trim, piece.length - trim)
        w = 2 * (min(p.distance(body) for p in near) - CLEAR_M)
        w = width if w >= width - TOL_M else w
        if w >= MIN_WIDTH_M:
            kept.append((piece, w, False))
    return kept


def fit_street(seg, width, near, main, sidewalk, cls=""):
    # 1. local streets: cut only where the centreline is inside a footprint
    #    (vacated / unbuilt blocks); main roads are never cut - buildings yield
    if main:
        parts = [seg]
    else:
        inside = unary_union([p.buffer(-SNAP_TOL_M) for p in near])
        parts = [p for p in pieces(seg.difference(inside)) if p.length >= MIN_PIECE_M]
    kept = []
    for piece in parts:
        # 2. corridor: distance to the nearest wall along the body of the piece
        trim = min(END_TRIM_M, piece.length / 3)
        body = substring(piece, trim, piece.length - trim)
        n = max(2, int(body.length / SAMPLE_M) + 1)
        d = sorted(min(p.distance(body.interpolate(i / (n - 1), normalized=True)) for p in near)
                   for i in range(n))
        need = width / 2 + (SIDEWALK_M if sidewalk else 0) + CLEAR_M
        crowded = [x for x in d if x < need]
        w, sw = width, sidewalk
        if len(crowded) >= CROWDED_FRACTION * len(d):
            room = crowded[len(crowded) // 10]   # 10th percentile of the crowded samples
            floor = MAIN_MIN_WIDTH_M.get(cls, 6.0) if main else STREET_MIN_WIDTH_M
            if sidewalk and room < width / 2 + SIDEWALK_M + CLEAR_M:
                sw = False
            w = max(min(width, 2 * (room - CLEAR_M)), min(floor, width))
            w = width if w >= width - TOL_M else w
        kept.append((piece, w, not sw))
    return kept


def normalise_footpaths(line, stats):
    """County pedestrian records (Crosby St footbridge, Barry interchange paths)
    carry the class of whatever runs beneath them - tertiary, motorway (25 m),
    motorway_link - and were paved as highways. Make them 3 m footways."""
    m = ROAD_RE.match(line)
    if not m or "Pedestrian" not in m["name"] or (m["cls"] == "footway" and m["bridge"] == "false"):
        return line
    stats["footpaths_normalised"] += 1
    return '%s{name="%s",x1=%s,z1=%s,x2=%s,z2=%s,width_m=%s,road_class="footway",bridge=false,tunnel=%s,layer=0%s' % (
        m["indent"], m["name"], m["x1"], m["z1"], m["x2"], m["z2"], fmt(FOOTWAY_WIDTH_M), m["tunnel"], m["rest"])


SHAVE_MAX_M = 3.0          # a face may move back at most this far
SHAVE_MAX_FRACTION = 0.4   # ... and never by more than this share of the block
RAIL_BED_M = 4.2


def carriageways():
    """Every ground-level carriageway / rail bed as a flat-capped polygon."""
    polys = []
    for path in sorted(TILES.glob("tile_*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = ROAD_RE.match(line)
            if not m or m["bridge"] != "false" or m["tunnel"] != "false" or m["layer"] != "0":
                continue
            if m["cls"] == "footway":
                continue
            w = RAIL_BED_M if m["name"] in RAIL_NAMES else float(m["w"])
            seg = LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))])
            if seg.length > 0.05:
                polys.append(seg.buffer(w / 2 + CLEAR_M, cap_style=2))
    return polys


def shave_buildings(check, stats):
    """Last pass: a building block whose edge still pokes into a carriageway
    (corner clips on back streets, highway shoulders, rail beds, the Barry
    approach at grade) has that face moved back to the road edge."""
    roads = carriageways()
    tree = STRtree(roads)
    line_re = re.compile(r'^(\s*\["(\d+)"\]=\{.*?\ba=([-\d.]+).*?,r=\{)(.*)(\}\},?\s*)$')
    for path in sorted(BUILDINGS.glob("*.lua")):
        out, changed = [], False
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = line_re.match(line)
            if not m:
                out.append(line)
                continue
            a = math.radians(float(m.group(3)))
            ca, sa = math.cos(a), math.sin(a)
            rects = [list(map(float, r)) for r in RECT_RE.findall(m.group(4))]
            new = []
            line_changed = False
            for cx, cz, L, W in rects:
                for _ in range(4):
                    poly = Polygon([(cx + ca * u * L / 2 - sa * v * W / 2, cz + sa * u * L / 2 + ca * v * W / 2)
                                    for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1))])
                    hits = [roads[i] for i in tree.query(poly) if roads[i].intersection(poly).area > 0.05]
                    if not hits:
                        break
                    inter = unary_union([h.intersection(poly) for h in hits])
                    pts = [(x - cx, z - cz) for g in getattr(inter, "geoms", [inter]) if not g.is_empty
                           for x, z in getattr(g, "exterior", g).coords]
                    us = [x * ca + z * sa for x, z in pts]
                    vs = [-x * sa + z * ca for x, z in pts]
                    options = [  # (inset, axis, sign)
                        (L / 2 - min(us), "u", 1), (max(us) + L / 2, "u", -1),
                        (W / 2 - min(vs), "v", 1), (max(vs) + W / 2, "v", -1),
                    ]
                    inset, axis, sign = min(options)
                    size = L if axis == "u" else W
                    if inset > SHAVE_MAX_M or inset > SHAVE_MAX_FRACTION * size:
                        stats["blocks_left_overlapping"] += 1
                        break
                    shift = -sign * inset / 2
                    if axis == "u":
                        L -= inset
                        cx, cz = cx + ca * shift, cz + sa * shift
                    else:
                        W -= inset
                        cx, cz = cx - sa * shift, cz + ca * shift
                    stats["faces_shaved"] += 1
                    changed = line_changed = True
                new.append((cx, cz, L, W))
            if line_changed:
                line = m.group(1) + ",".join("{%.2f,%.2f,%.2f,%.2f}" % tuple(r) for r in new) + m.group(5)
            out.append(line)
        if changed and not check:
            path.write_text("\n".join(out), encoding="utf-8")


def main(check=False):
    stats = Counter()
    yield_buildings_to_main_roads(check, stats)
    polys = footprints()
    tree = STRtree(polys)
    for path in sorted(TILES.glob("tile_*.lua")):
        original = path.read_text(encoding="utf-8").split("\n")
        lines = [normalise_footpaths(line, stats) for line in original]
        out, changed = [], False
        for line in lines:
            m = ROAD_RE.match(line)
            k = m and kind(m)
            if not k:
                out.append(line)
                continue
            stats[k] += 1
            seg = LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))])
            width = float(m["w"])
            sidewalk = not m["sw"]
            reach = width / 2 + (SIDEWALK_M if k != "minor" and sidewalk else 0) + CLEAR_M
            near = [polys[i] for i in tree.query(seg.buffer(reach)) if polys[i].distance(seg) < reach]
            if not near:
                out.append(line)
                continue
            if k == "minor":
                kept = fit_minor(seg, width, near)
            else:
                kept = fit_street(seg, width, near, k == "main", sidewalk, m["cls"])
            if len(kept) == 1 and kept[0][0].length >= seg.length - TOL_M and kept[0][1] >= width \
                    and kept[0][2] == (not sidewalk):
                out.append(line)
                continue
            if not kept:
                stats[k + "_dropped"] += 1
            if any(p.length < seg.length - TOL_M for p, _, _ in kept):
                stats[k + "_cut"] += 1
            if any(w < width for _, w, _ in kept):
                stats[k + "_narrowed"] += 1
            if any(nosw for _, _, nosw in kept) and sidewalk:
                stats[k + "_sidewalks_dropped"] += 1
            for piece, w, nosw in kept:
                (x1, z1), (x2, z2) = piece.coords[0], piece.coords[-1]
                out.append('%s{name="%s",x1=%s,z1=%s,x2=%s,z2=%s,width_m=%s,road_class="%s",bridge=%s,tunnel=%s,layer=%s%s%s' % (
                    m["indent"], m["name"], fmt(x1), fmt(z1), fmt(x2), fmt(z2), fmt(w), m["cls"],
                    m["bridge"], m["tunnel"], m["layer"], ",sidewalk=false" if nosw else "", m["rest"]))
            changed = True
        if (changed or lines != original) and not check:
            path.write_text("\n".join(out), encoding="utf-8")
    shave_buildings(check, stats)
    print(dict(stats))


if __name__ == "__main__":
    main("--check" in sys.argv)
