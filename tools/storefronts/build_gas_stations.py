"""Build src/shared/WorldData/GasStations.lua from the verified storefront inventory.

For each gas station whose street-imagery review is confirmed/plausible
(Data/10_StorefrontPanoramas manifest), finds the county footprints that are
really the fuel canopy (within 10 m of the fuel point, <= 7.5 m tall, near-
rectangular - checked against the DVRPC 2025 aerial), and writes their oriented
boxes plus the ids to replace. Stations with no canopy footprint get a
synthetic 24 x 10 m canopy parallel to the street. GasStationBuilder.server.lua
removes the box buildings and builds an open canopy, pump islands and a brand
sign.

    py -3 tools/storefronts/build_gas_stations.py
"""
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src" / "shared" / "WorldData" / "GasStations.lua"
MANIFEST = s.OUT_DEFAULT / "chesterworld_storefront_reference_manifest.json"
LAT0 = 39.85
STUDS_PER_M = 3.0 / math.cos(math.radians(LAT0))  # horizontal: Web-Mercator metres x3

# brand: fascia, accent, sign text colour (from the Google Street View review 2026-11-05)
BRANDS = {
    "Sunoco": ((0, 61, 165), (255, 204, 0), (255, 255, 255)),
    "US Gas": ((196, 30, 42), (240, 240, 240), (255, 255, 255)),
    "Eagle Fuel": ((28, 48, 118), (206, 38, 44), (255, 255, 255)),
    "Lukoil": ((214, 24, 32), (245, 245, 245), (255, 255, 255)),
    "BP": ((236, 236, 236), (200, 30, 36), (24, 24, 24)),
}
DEFAULT_BRAND = ((236, 236, 236), (200, 30, 36), (24, 24, 24))
# Street View corrections: 1201 Kerlin St is "Chester GAS" (black / red script /
# gold, on the pylon and the canopy fascia), not BP.
NAME_FIX = {"cw_98a00d067e": "Chester Gas"}
BRANDS["Chester Gas"] = ((24, 24, 24), (200, 30, 36), (232, 190, 80))
# Pylon price panel per brand: background, LED colour, grade labels. Prices are
# read off the Street View captures where legible (Chester GAS regular 2.97,
# Sunoco 2200 Edgmont 3.49); the rest are illustrative for the area.
PRICE_STYLE = {
    "Sunoco": ((12, 30, 90), (255, 52, 40), ("REGULAR", "ULTRA 93", "DIESEL")),
    "Chester Gas": ((22, 120, 70), (255, 52, 40), ("REGULAR", "ULTIMATE", "DIESEL")),
    "Eagle Fuel": ((150, 20, 28), (255, 70, 50), ("REGULAR", "PREMIUM", "DIESEL")),
    "Lukoil": ((245, 245, 245), (220, 30, 36), ("REGULAR", "PLUS", "PREMIUM")),
    "US Gas": ((20, 20, 24), (255, 52, 40), ("REGULAR", "PLUS", "DIESEL")),
}
# pylon post / frame colour where it differs from the canopy fascia (Street
# View: Eagle Fuel's pylon is red with the eagle emblem on top)
PYLON_POST = {"Eagle Fuel": (206, 38, 44)}
PRICES = {
    "cw_98a00d067e": (2.97, 3.57, 3.89),
    "cw_28a6741d42": (3.49, 4.09, 4.29),
}
DEFAULT_PRICES = {"Sunoco": (3.39, 3.99, 4.19), "Eagle Fuel": (3.19, 3.79, 4.09),
                  "Lukoil": (3.25, 3.55, 3.95), "US Gas": (3.15, 3.45, 3.99)}

# The station's own shop (DVRPC 2025 aerial + Street View, tools/harness/
# station_aerial.py, 2026-11-06). The canopy detector above also swallowed the
# shop at Lukoil, US Gas and the Edgmont Sunoco. GasStationBuilder rebuilds
# the shop in its real footprint as an enterable branded store (EXIT 6).
#   footprint: (county id, rect index | "nearest") - the store is that building
#   under:     kiosk under the canopy at canopy-local (u, v) fractions of the
#              half length / width ("sw_end" = the south-west end), size (len_m, wid_m)
#   behind:    kiosk this many metres behind the canopy (away from the street)
# sign: the shop's own fascia text (None = the fuel brand artwork)
STORES = {
    # Sunoco 700 W 9th (9th & Kerlin): white walls, grey shingle gable roof,
    # blue band with the A-Plus badge (Street View 2024)
    "cw_687c501096": {"footprint": ("191030", 0), "sign": "A-PLUS", "roof": "gable",
                      "wall": (236, 236, 232), "roofColor": (104, 106, 112)},
    # US Gas: the white building at the canopy's east end is the check cashing
    # office (blue sign on Street View) that doubles as the station's shop
    "cw_fefc0bb360": {"footprint": ("50221", 1), "sign": "CHECK CASHING",
                      "sign_colors": ((28, 70, 160), (240, 190, 40), (255, 255, 255))},
    "cw_28a6741d42": {"footprint": ("40026", 1), "sign": "A-PLUS"},         # Sunoco 2200 Edgmont
    "cw_1ab25071e5": {"footprint": ("122402", "nearest"), "sign": "FOOD MART / DELI"},  # Sunoco 2nd St
    "cw_5f192ec41c": {"under": ("sw_end", 0.0), "size": (9.0, 4.6), "sign": "MINI-MART"},  # Lukoil
    "cw_442801b4e3": {"under": (0.0, 0.0), "size": (7.0, 4.0), "sign": None},  # Sunoco Township Line
    "cw_98a00d067e": {"behind": 4.0, "size": (6.5, 5.0), "sign": None},     # Chester Gas kiosk
    # cw_ab912b6f80 Eagle Fuel: no shop of its own (the "Ave Mart" beside it is
    # another business) - no EXIT 6 store
}
KIOSK_H_M = 3.4
# Pylon spot fixes from Street View (9th & Kerlin captures, 2024): the pylon
# stands at the lot corner where the two named streets meet.
SIGN_AT_CORNER = {
    # Sunoco: SE corner by the 9th St crosswalk, board facing Kerlin traffic
    # (first road = the one the board runs along)
    "cw_687c501096": ("Kerlin", "9th"),
}
# measured off the gridded aerial (tools/harness/aerial_grid.py): the Eagle
# Fuel lot corner at Kerlin / Concord; the county Concord centreline meets
# Kerlin ~10 m south of the real road there, so the corner rule lands short
SIGN_FIXED = {
    "cw_ab912b6f80": [2699.0, 1383.0, 152.0],
}
SIGN_ON_ROAD_IN_FRONT_OF_STORE = {}

# pylon placement: just inside the lot, behind the sidewalk of a public street
SIGN_SETBACK = 5.0      # studs past the back of the sidewalk
SIGN_SEARCH = 140.0     # studs from the canopy centre


def place_sign(canopies, roads, footprints):
    """Pick the pylon spot on the line SIGN_SETBACK behind the sidewalks of the
    streets around the station, preferring the lot corner where two streets
    meet; never on a carriageway / sidewalk / canopy / building. Returns
    [x, z, bearing] with bearing the compass direction of the board normal,
    parallel to the street so both faces read to traffic."""
    from shapely.geometry import Point, Polygon
    from shapely.ops import unary_union
    cx = sum(c["box"][0] for c in canopies) / len(canopies)
    cz = sum(c["box"][1] for c in canopies) / len(canopies)
    here = Point(cx, cz)
    near = [r for r in roads if r[0].distance(here) < SIGN_SEARCH + 40]
    if not near:
        return None
    lines = [r[0].buffer(r[1] + SIGN_SETBACK, cap_style=2) for r in near]
    blocked = unary_union([r[0].buffer(r[1] + 1.0, cap_style=2) for r in near])
    boxes = []
    for c in canopies:
        x, z, L, W, yaw = c["box"]
        a = math.radians(-yaw)          # box yaw is a Roblox Y rotation (studs, +z south)
        ca, sa = math.cos(a), math.sin(a)
        boxes.append(Polygon([(x + ca * u * L / 2 - sa * v * W / 2, z + sa * u * L / 2 + ca * v * W / 2)
                              for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1))]).buffer(4))
    own = {c["replaces"] for c in canopies}
    obstacles = unary_union(boxes + [f for f, fid in footprints
                                     if fid not in own and f.distance(here) < SIGN_SEARCH + 60]).buffer(2)
    edge = unary_union(lines).boundary
    best = None
    for k in range(int(edge.length / 2) + 1):
        p = edge.interpolate(k * 2.0)
        d = p.distance(here)
        if d > SIGN_SEARCH or blocked.contains(p) or obstacles.contains(p):
            continue
        dists = sorted((ln.exterior.distance(p), i) for i, ln in enumerate(lines))
        corner = sum(1 for dd, _ in dists if dd < 6.0)
        score = (-min(corner, 2), d)
        if best is None or score < best[0]:
            best = (score, p, near[dists[0][1]][0])
    if not best:
        return None
    _, p, road = best
    (x1, z1), (x2, z2) = road.coords[0], road.coords[-1]
    bearing = math.degrees(math.atan2(x2 - x1, -(z2 - z1))) % 360   # studs: +x east, -z north
    return [round(p.x, 1), round(p.y, 1), round(bearing, 1)]


def street_data():
    """Public streets and building footprints from the world tiles, in studs."""
    from shapely.geometry import LineString
    from shapely import affinity
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import fit_roads_to_buildings as fit
    to_studs = [3, 0, 0, -3, -6347.889 * 3, 7201.973 * 3]
    roads = []
    for path in sorted(fit.TILES.glob("tile_*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = fit.ROAD_RE.match(line)
            if not m or fit.kind(m) not in ("local", "main"):
                continue
            seg = affinity.affine_transform(LineString([(float(m["x1"]), float(m["z1"])),
                                                        (float(m["x2"]), float(m["z2"]))]), to_studs)
            if seg.length > 0.5:
                roads.append((seg, float(m["w"]) * 3 / 2 + (0 if m["sw"] else 5.1)))
                NAMED_ROADS.append((seg, float(m["w"]) * 3 / 2 + (0 if m["sw"] else 5.1), m["name"]))
    polys, keys = fit.footprints(with_keys=True)
    foot = [(affinity.affine_transform(p, to_studs), k[1]) for p, k in zip(polys, keys)]
    return roads, foot


def to_studs_geom(g):
    from shapely.ops import transform
    return transform(lambda xs, ys, zs=None: tuple(zip(*[s.studs(x, y) for x, y in zip(xs, ys)])), g)


def oriented(poly):
    rect = poly.minimum_rotated_rectangle
    pts = list(rect.exterior.coords)[:4]
    e1 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    e2 = (pts[2][0] - pts[1][0], pts[2][1] - pts[1][1])
    l1, l2 = math.hypot(*e1), math.hypot(*e2)
    along = e1 if l1 >= l2 else e2
    c = rect.centroid
    return [round(c.x, 1), round(c.y, 1), round(max(l1, l2), 1), round(min(l1, l2), 1),
            round(-math.degrees(math.atan2(along[1], along[0])), 1)]


def building_records():
    """county id -> (a, h_m, rects[(x, z, L, W) source m], rc, wc) from BuildingTiles"""
    import re
    out = {}
    for path in sorted((ROOT / "src" / "shared" / "WorldData" / "BuildingTiles").glob("*.lua")):
        for m in re.finditer(r'\["(\d+)"\]=\{([^\n]*)\}', path.read_text(encoding="utf-8")):
            body = m.group(2)
            a = re.search(r'\ba=([-\d.]+)', body)
            h = re.search(r'\bh=([-\d.]+)', body)
            rc = re.search(r'\brc=(0x[0-9a-fA-F]+)', body)
            wc = re.search(r'\bwc=(0x[0-9a-fA-F]+)', body)
            rects = []
            if "r={" in body:
                rects = [tuple(map(float, r)) for r in
                         re.findall(r'\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\}', body.split("r={", 1)[1])]
            out[m.group(1)] = (float(a.group(1)) if a else 0.0, float(h.group(1)) if h else 4.0, rects,
                               int(rc.group(1), 16) if rc else None, int(wc.group(1), 16) if wc else None)
    return out


def yaw_axes(yaw):
    """Roblox CFrame.Angles(0, yaw): local +X and +Z as world (x, z)"""
    t = math.radians(yaw)
    return (math.cos(t), -math.sin(t)), (math.sin(t), math.cos(t))


def store_box(cx, cz, length, width, yaw, front):
    """Orient a box so its local -Z faces `front`: returns [cx, cz, face width,
    depth, yaw] of the shop frame (Roblox yaw)."""
    ex, ez = yaw_axes(yaw)
    dx, dz = front[0] - cx, front[1] - cz
    if abs(dx * ex[0] + dz * ex[1]) > abs(dx * ez[0] + dz * ez[1]):
        sgn = 1 if dx * ex[0] + dz * ex[1] > 0 else -1
        n, face, depth = (ex[0] * sgn, ex[1] * sgn), width, length
    else:
        sgn = 1 if dx * ez[0] + dz * ez[1] > 0 else -1
        n, face, depth = (ez[0] * sgn, ez[1] * sgn), length, width
    return [round(cx, 1), round(cz, 1), round(face, 1), round(depth, 1),
            round(math.degrees(math.atan2(-n[0], -n[1])), 1)]


def build_store(sid, canopies, sign, records):
    spec = STORES.get(sid)
    if not spec:
        return None
    S = 3.0
    ccx = sum(c["box"][0] for c in canopies) / len(canopies)
    ccz = sum(c["box"][1] for c in canopies) / len(canopies)
    cx0, cz0, L, W, yaw = canopies[0]["box"]
    ex, ez = yaw_axes(yaw)
    street = (sign[0], sign[1]) if sign else (ccx, ccz)
    if "footprint" in spec:
        bid, which = spec["footprint"]
        a, h, rects, rc, wc = records[bid]
        studs = [((x - 6347.889) * S, -(z - 7201.973) * S, rl * S, rw * S) for x, z, rl, rw in rects]
        if which == "nearest":
            which = min(range(len(studs)), key=lambda i: math.hypot(studs[i][0] - ccx, studs[i][1] - ccz))
        x, z, rl, rw = studs[which]
        box = store_box(x, z, rl, rw, a, (ccx, ccz))
        wall, roofc = spec.get("wall"), spec.get("roofColor")
        return {"box": box, "h": round(max(h * S, 10.0), 1), "model": bid,
                "rc": (roofc[0] << 16 | roofc[1] << 8 | roofc[2]) if roofc else rc,
                "wc": (wall[0] << 16 | wall[1] << 8 | wall[2]) if wall else wc, "sign": spec["sign"],
                "sign_colors": spec.get("sign_colors"), "roof": spec.get("roof")}
    ln, wd = spec["size"][0] * STUDS_PER_M, spec["size"][1] * STUDS_PER_M
    if "under" in spec:
        u, v = spec["under"]
        if u == "sw_end":
            ends = [(sgn, cx0 + ex[0] * sgn * L / 2, cz0 + ex[1] * sgn * L / 2) for sgn in (-1, 1)]
            sgn = max(ends, key=lambda e: -e[1] + e[2])[0]
            off = sgn * (L / 2 - ln / 2 - 1.5)
        else:
            off = u * L / 2
        x, z = cx0 + ex[0] * off + ez[0] * v * W / 2, cz0 + ex[1] * off + ez[1] * v * W / 2
        # a kiosk under the canopy lies along it, its long glass front facing
        # the street across the canopy (Street View: Lukoil MINI-MART)
        side = 1 if (street[0] - x) * ez[0] + (street[1] - z) * ez[1] > 0 else -1
        target = (x + ez[0] * side * 100, z + ez[1] * side * 100)
        box = store_box(x, z, wd, ln, yaw + 90, target)
    else:
        side = 1 if (ccx - street[0]) * ez[0] + (ccz - street[1]) * ez[1] > 0 else -1
        d = W / 2 + spec["behind"] * STUDS_PER_M + wd / 2
        x, z = cx0 + ez[0] * side * d, cz0 + ez[1] * side * d
        box = store_box(x, z, ln, wd, yaw, (cx0, cz0))
    return {"box": box, "h": round(KIOSK_H_M * 3.0, 1), "model": None, "rc": None, "wc": None, "sign": spec["sign"],
            "sign_colors": spec.get("sign_colors")}


def sign_at_corner(canopies, road_a, road_b, named_roads):
    """Pylon where the setback lines of two named streets cross, on the
    station's side (nearest the canopies), clear of carriageways / sidewalks."""
    from shapely.geometry import Point
    from shapely.ops import unary_union
    cx = sum(c["box"][0] for c in canopies) / len(canopies)
    cz = sum(c["box"][1] for c in canopies) / len(canopies)
    here = Point(cx, cz)
    def pick(name):
        return [(seg, half) for seg, half, n in named_roads
                if name.lower() in n.lower() and seg.distance(here) < 400]
    ra, rb = pick(road_a), pick(road_b)
    if not ra or not rb:
        return None
    la = unary_union([seg.buffer(h + SIGN_SETBACK, cap_style=2) for seg, h in ra]).boundary
    lb = unary_union([seg.buffer(h + SIGN_SETBACK, cap_style=2) for seg, h in rb]).boundary
    blocked = unary_union([seg.buffer(h + 1.0, cap_style=2) for seg, h, _ in named_roads
                           if seg.distance(here) < 400])
    pts = la.intersection(lb)
    pts = [g for g in getattr(pts, "geoms", [pts]) if g.geom_type == "Point" and not blocked.contains(g)]
    if not pts:
        return None
    p = min(pts, key=lambda g: g.distance(here))
    seg = min(ra, key=lambda r: r[0].distance(p))[0]
    (x1, z1), (x2, z2) = seg.coords[0], seg.coords[-1]
    bearing = math.degrees(math.atan2(x2 - x1, -(z2 - z1))) % 360
    return [round(p.x, 1), round(p.y, 1), round(bearing, 1)]


def sign_in_front_of_store(store, road_name, named_roads):
    """Pylon on `road_name` at the point of its lot edge nearest the shop."""
    from shapely.geometry import Point
    here = Point(store["box"][0], store["box"][1])
    best = None
    for seg, half, name in named_roads:
        if road_name.lower() not in name.lower():
            continue
        edge = seg.buffer(half + SIGN_SETBACK, cap_style=2).exterior
        d = edge.distance(here)
        if best is None or d < best[0]:
            best = (d, edge, seg)
    if not best:
        return None
    _, edge, seg = best
    p = edge.interpolate(edge.project(here))
    (x1, z1), (x2, z2) = seg.coords[0], seg.coords[-1]
    bearing = math.degrees(math.atan2(x2 - x1, -(z2 - z1))) % 360
    return [round(p.x, 1), round(p.y, 1), round(bearing, 1)]


NAMED_ROADS = []
RECORDS = {}


def lua_str(v):
    return '"' + str(v).replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    from shapely.geometry import shape, Point
    from shapely.ops import transform
    import pyproj
    tm = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    man = json.loads(MANIFEST.read_text(encoding="utf-8"))["businesses"]
    feats = s.load(s.BUILDINGS)["features"]
    geoms_m = [transform(tm, shape(f["geometry"]).buffer(0)) for f in feats]
    stations = []
    roads, foot = street_data()
    RECORDS.update(building_records())
    for b in man:
        if b["group"] != "gas_station" or not str(b.get("review_status", "")).startswith("visually"):
            continue
        pt = Point(tm(b["lon"], b["lat"]))
        canopies = []
        for i, g in enumerate(geoms_m):
            if g.distance(pt) > 10:
                continue
            p = feats[i]["properties"]
            h = p.get("height_m") or 0
            fill = g.area / max(g.minimum_rotated_rectangle.area, 1e-6)
            if h <= 7.5 and fill >= 0.7 and 30 <= g.area <= 700:
                gl = shape(feats[i]["geometry"]).buffer(0)
                if gl.geom_type == "MultiPolygon":
                    gl = max(gl.geoms, key=lambda q: q.area)
                canopies.append({"box": oriented(to_studs_geom(gl)), "replaces": str(p["OBJECTID"])})
        front = (b.get("frontage") or {}).get("front_bearing")
        sx, sz = s.studs(b["lon"], b["lat"])
        if not canopies:
            # synthetic canopy parallel to the street (long axis perpendicular to the frontage bearing)
            fb = math.radians(front or 0)
            ax, az = math.cos(fb), math.sin(fb)  # studs frame: x east, z south
            canopies.append({"box": [sx, sz, round(24 * STUDS_PER_M, 1), round(10 * STUDS_PER_M, 1),
                                     round(-math.degrees(math.atan2(az, ax)), 1)], "replaces": None, "synthetic": True})
        # brand sign near the street: from the canopy centre towards the frontage road
        cx = sum(c["box"][0] for c in canopies) / len(canopies)
        cz = sum(c["box"][1] for c in canopies) / len(canopies)
        sign = None
        if front is not None:
            d = max(6.0, ((b.get("frontage") or {}).get("road_distance_m") or 12) - 3.5) * STUDS_PER_M
            fb = math.radians(front)
            sign = [round(sx + math.sin(fb) * d, 1), round(sz - math.cos(fb) * d, 1), round(front, 1)]
        name = NAME_FIX.get(b["id"], b["name"])
        brand = next((k for k in BRANDS if k.lower() in name.lower()), None)
        placed = place_sign(canopies, roads, foot)
        if placed:
            sign = placed
        if b["id"] in SIGN_FIXED:
            sign = list(SIGN_FIXED[b["id"]])
        if b["id"] in SIGN_AT_CORNER:
            corner = sign_at_corner(canopies, *SIGN_AT_CORNER[b["id"]], NAMED_ROADS)
            if corner:
                sign = corner
        store = build_store(b["id"], canopies, sign, RECORDS)
        if store and b["id"] in SIGN_ON_ROAD_IN_FRONT_OF_STORE:
            fixed = sign_in_front_of_store(store, SIGN_ON_ROAD_IN_FRONT_OF_STORE[b["id"]], NAMED_ROADS)
            if fixed:
                sign = fixed
        style = PRICE_STYLE.get(brand, ((20, 20, 24), (255, 52, 40), ("REGULAR", "PLUS", "DIESEL")))
        prices = PRICES.get(b["id"], DEFAULT_PRICES.get(brand, (3.29, 3.89, 4.19)))
        stations.append({"id": b["id"], "name": name, "brand": brand or name, "canopies": canopies,
                         "sign": sign, "colors": BRANDS.get(brand, DEFAULT_BRAND), "address": b.get("address", ""),
                         "panel": style[0], "led": style[1], "grades": style[2], "prices": prices,
                         "placed": bool(placed), "store": store})
    lines = ["-- Generated by tools/storefronts/build_gas_stations.py from the street-imagery-verified",
             "-- storefront inventory (Data/10_StorefrontPanoramas). Studs. box = {cx, cz, length, width, yaw}.",
             "-- replaces = county footprint id that is really the canopy (GasStationBuilder removes it).",
             "-- store = the station's shop: box = {cx, cz, face width, depth, yaw} (local -Z = shop front),",
             "-- h studs, model = county building it replaces, rc / wc = its roof / wall colour, sign = shop name.",
             "return {"]
    for st in stations:
        cans = ",".join("{box={%s},replaces=%s}" % (",".join(str(v) for v in c["box"]),
                                                   lua_str(c["replaces"]) if c["replaces"] else "nil") for c in st["canopies"])
        col = ",".join("{%d,%d,%d}" % c for c in st["colors"])
        sign = "{%s}" % ",".join(str(v) for v in st["sign"]) if st["sign"] else "nil"
        price = "panel={%d,%d,%d},led={%d,%d,%d},grades={%s},prices={%s}" % (
            *st["panel"], *st["led"], ",".join(lua_str(gr) for gr in st["grades"]),
            ",".join("%.2f" % v for v in st["prices"]))
        so = st["store"]
        store = "nil"
        if so:
            sc = so.get("sign_colors")
            store = "{box={%s},h=%s,model=%s,rc=%s,wc=%s,sign=%s,signColors=%s,roof=%s}" % (
                ",".join(str(v) for v in so["box"]), so["h"], lua_str(so["model"]) if so["model"] else "nil",
                "0x%06x" % so["rc"] if so["rc"] is not None else "nil",
                "0x%06x" % so["wc"] if so["wc"] is not None else "nil",
                lua_str(so["sign"]) if so["sign"] else "nil",
                "{%s}" % ",".join("{%d,%d,%d}" % c for c in sc) if sc else "nil",
                lua_str(so["roof"]) if so.get("roof") else "nil")
        post = PYLON_POST.get(st["brand"])
        price += ",post=%s" % ("{%d,%d,%d}" % post if post else "nil")
        lines.append("\t{id=%s,name=%s,brand=%s,address=%s,colors={%s},sign=%s,%s,canopies={%s},store=%s}," % (
            lua_str(st["id"]), lua_str(st["name"]), lua_str(st["brand"]), lua_str(st["address"]), col, sign,
            price, cans, store))
    lines.append("}")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    for st in stations:
        print(f"{st['name']:12} canopies={len(st['canopies'])} sign={st['sign']} store={st['store'] and st['store']['box']}")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
