"""Build per-tile building geometry modules from the county footprints.

    python tools/build_building_tiles.py [--check]

Reads the regional county footprints (with the prep-stage classification), fills
default heights from Overture lidar heights, classifies unclassified buildings by
footprint shape and neighbours, decomposes each footprint into rectangles along
the building's own axis, and writes src/shared/WorldData/BuildingTiles/<tile>.lua
keyed by building id. The existing tile modules (roads, box buildings) are not
modified; TileBuilderV2 uses these shapes when present.
"""
import json
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from shapely import affinity
from shapely.geometry import box, shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[1]
DATA = Path(r"E:\ChesterWorld\Data")
COUNTY = DATA / "13_RegionalMaster" / "regional_buildings_base.geojson"
OVERTURE = DATA / "01_Buildings" / "overture_buildings_region_20261021.geojson"
TILES = ROOT / "src" / "shared" / "WorldData" / "Tiles"
OUT = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"
AERIAL = DATA / "19_Aerial"

# EPSG:3857 metres -> source metres (tiles store x_m, z_m in this frame)
X_OFFSET, Z_OFFSET = 8397592.0, -4837229.0
DEFAULT_HEIGHT_M = 9.15
DEFAULT_BY_STYLE = {"rowhouse": 9.5, "house": 7.5, "twin": 8.5, "garage": 3.5, "storefront": 7.0,
                    "commercial": 8.0, "industrial": 9.0, "warehouse": 10.0, "apartment": 12.0,
                    "church": 14.0, "school": 11.0, "generic": 7.0}
SNAP_M = 0.35          # vertex snap along the building axis
MIN_SLAB_M = 1.2       # slabs narrower than this merge into a neighbour
MAX_RECTS = 14

# collapse the prep archetypes to the builder's style keys
STYLE = {
    "rowhouse_middle": "rowhouse", "rowhouse_end": "rowhouse",
    "twin_semi_detached": "twin", "detached_house": "house",
    "small_multifamily": "apartment", "apartment_multifamily": "apartment",
    "small_commercial_storefront": "storefront", "commercial_lowrise": "commercial",
    "small_industrial": "industrial", "warehouse_industrial": "warehouse",
    "religious_building": "church", "school_building": "school",
    "generic_unknown_building": "generic",
}


def merc(lon, lat):
    return lon * 20037508.34 / 180.0, math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0


def to_source(geom):
    """lon/lat polygon -> source metres (x east, z north)."""
    def tx(lon, lat, z=None):
        mx, my = merc(lon, lat)
        return mx + X_OFFSET, my + Z_OFFSET
    from shapely.ops import transform
    return transform(lambda xs, ys, zs=None: tuple(zip(*[tx(x, y) for x, y in zip(xs, ys)])), geom)


def lua_string(text):
    """Luau string literal (json.dumps emits backslash-u escapes Luau rejects)."""
    out = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")
    return '"' + out + '"'


def tile_of_ids():
    owner = {}
    for path in TILES.glob("tile_*.lua"):
        for bid in re.findall(r'\{id="([^"]+)",name=', path.read_text(encoding="utf-8")):
            owner[bid] = path.stem
    return owner


def principal_angle(poly):
    """Angle (radians) of the longest edge of the minimum rotated rectangle."""
    rect = poly.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)
    best, angle = -1.0, 0.0
    for (x0, y0), (x1, y1) in zip(coords, coords[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        if length > best:
            best, angle = length, math.atan2(y1 - y0, x1 - x0)
    return angle


def decompose(poly):
    """Rectangles (in the building's local frame, axis = principal edge) covering poly."""
    angle = principal_angle(poly)
    c = poly.centroid
    local = affinity.rotate(poly, -angle, origin=c, use_radians=True)
    local = local.buffer(0)
    if local.is_empty:
        return angle, c, []
    xs = sorted({round(x / SNAP_M) * SNAP_M for x, _ in local.exterior.coords})
    minx, miny, maxx, maxy = local.bounds
    xs = [minx] + [x for x in xs if minx + MIN_SLAB_M <= x <= maxx - MIN_SLAB_M] + [maxx]
    merged = [xs[0]]
    for x in xs[1:]:
        if x - merged[-1] >= MIN_SLAB_M:
            merged.append(x)
    merged[-1] = maxx
    slabs = []
    for x0, x1 in zip(merged, merged[1:]):
        strip = local.intersection(box(x0, miny - 1, x1, maxy + 1))
        parts = getattr(strip, "geoms", [strip])
        intervals = []
        for part in parts:
            if part.is_empty or part.area < 0.5:
                continue
            _, z0, _, z1 = part.bounds
            # use the area-equivalent depth so slanted edges are not overstated
            depth = part.area / (x1 - x0)
            mid = (z0 + z1) / 2
            intervals.append((round(mid - depth / 2, 2), round(mid + depth / 2, 2)))
        slabs.append((x0, x1, sorted(intervals)))
    # merge neighbouring slabs with matching intervals
    rects = []
    open_runs = {}
    for x0, x1, intervals in slabs:
        next_runs = {}
        for z0, z1 in intervals:
            key = None
            for (kz0, kz1), run in open_runs.items():
                if abs(kz0 - z0) < 0.4 and abs(kz1 - z1) < 0.4:
                    key = (kz0, kz1)
                    break
            if key:
                run = open_runs.pop(key)
                run[1] = x1
                next_runs[key] = run
            else:
                next_runs[(z0, z1)] = [x0, x1, z0, z1]
        rects.extend(open_runs.values())
        open_runs = next_runs
    rects.extend(open_runs.values())
    return angle, c, rects


def rect_sides(poly):
    coords = list(poly.minimum_rotated_rectangle.exterior.coords)
    sides = sorted(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(coords, coords[1:]))
    return sides[-1], sides[0]


def is_row(poly):
    """A merged rowhouse row: long, house-depth, several units wide."""
    along, across = rect_sides(poly)
    return along >= 20 and 6 <= across <= 18 and along / max(across, 0.1) >= 2.0


def classify_unlabelled(props, poly, neighbours):
    area = poly.area
    along, across = rect_sides(poly)
    aspect = along / max(across, 0.1)
    if area < 45:
        return "garage"
    if area > 4000:
        return "warehouse"
    if area > 1500:
        return "commercial"
    if neighbours >= 2 or is_row(poly):
        return "rowhouse"
    if neighbours == 1 and area < 250:
        return "twin"
    if area < 300:
        return "house"
    return "generic"


class RoofSampler:
    """Median roof colour of a footprint from the DVRPC 2025 1 m mosaic
    (tools/fetch_aerial_mosaic.py). Shadows (darkest fifth) are ignored."""

    def __init__(self):
        self.tiles = json.loads((AERIAL / "index.json").read_text(encoding="utf-8")) if (AERIAL / "index.json").exists() else []
        self.cache = {}

    def image(self, tile):
        if tile["file"] not in self.cache:
            if len(self.cache) > 12:
                self.cache.clear()
            self.cache[tile["file"]] = np.asarray(Image.open(AERIAL / tile["file"]).convert("RGB"))
        return self.cache[tile["file"]]

    def colour(self, poly):
        inner = poly.buffer(-0.8)
        if inner.is_empty or inner.area < 4:
            inner = poly
        if inner.geom_type == "MultiPolygon":
            inner = max(inner.geoms, key=lambda g: g.area)
        # source metres -> EPSG:3857
        mx, my = inner.centroid.x - X_OFFSET, inner.centroid.y - Z_OFFSET
        for tile in self.tiles:
            if tile["xmin"] <= mx < tile["xmax"] and tile["ymin"] <= my < tile["ymax"]:
                img = self.image(tile)
                scale = img.shape[1] / (tile["xmax"] - tile["xmin"])
                pts = [((x - X_OFFSET - tile["xmin"]) * scale, (tile["ymax"] - (y - Z_OFFSET)) * scale)
                       for x, y in inner.exterior.coords]
                xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                c0, r0 = max(int(min(xs)), 0), max(int(min(ys)), 0)
                c1, r1 = min(int(max(xs)) + 1, img.shape[1]), min(int(max(ys)) + 1, img.shape[0])
                if c1 <= c0 or r1 <= r0:
                    return None
                mask = Image.new("L", (c1 - c0, r1 - r0), 0)
                ImageDraw.Draw(mask).polygon([(x - c0, y - r0) for x, y in pts], fill=1)
                pixels = img[r0:r1, c0:c1][np.asarray(mask, bool)]
                if len(pixels) < 3:
                    return None
                lum = pixels.sum(1)
                keep = pixels[lum >= np.percentile(lum, 20)]
                return tuple(int(v) for v in np.median(keep, 0))
        return None


def main(check_only=False):
    county = json.loads(COUNTY.read_text(encoding="utf-8"))["features"]
    owner = tile_of_ids()
    polys, props = [], []
    for f in county:
        g = shape(f["geometry"])
        if not g.is_valid:
            g = g.buffer(0)
        polys.append(to_source(g))
        props.append(f["properties"])

    # Overture lidar heights for default-height buildings
    ov_polys, ov_heights = [], []
    for f in json.loads(OVERTURE.read_text(encoding="utf-8"))["features"]:
        h = f["properties"].get("height")
        if h:
            ov_polys.append(to_source(shape(f["geometry"])))
            ov_heights.append(float(h))
    ov_tree = STRtree(ov_polys)
    tree = STRtree(polys)

    roofs = RoofSampler()
    roofed = 0
    tiles = defaultdict(list)
    styles = Counter()
    filled = 0
    rect_total = 0
    max_rects = 0
    for index, (poly, p) in enumerate(zip(polys, props)):
        bid = str(p.get("OBJECTID"))
        tile = owner.get(bid)
        if not tile or poly.is_empty:
            continue
        if poly.geom_type == "MultiPolygon":
            poly = max(poly.geoms, key=lambda g: g.area)
        height = p.get("BuildingHeightM")
        if not height:
            best, overlap = None, 0.0
            for j in ov_tree.query(poly, predicate="intersects"):
                a = poly.intersection(ov_polys[j]).area
                if a > overlap:
                    best, overlap = ov_heights[j], a
            if best and overlap > 0.4 * poly.area:
                height = best
                filled += 1
        if not height and p.get("estimated_floors"):
            height = 1.0 + 3.1 * float(p["estimated_floors"])
        height = float(height or 0) or None
        style = STYLE.get(p.get("generator_archetype") or "")
        if style in ("house", "twin", "apartment", "generic") and is_row(poly):
            # the prep classifier calls a merged row of rowhouses one detached house
            style = "rowhouse"
        if not style:
            touching = sum(1 for j in tree.query(poly.buffer(0.6), predicate="intersects") if j != index)
            style = classify_unlabelled(p, poly, touching)
        if not height:
            height = DEFAULT_BY_STYLE.get(style, DEFAULT_HEIGHT_M)
        styles[style] += 1
        angle, c, rects = decompose(poly)
        if not rects or len(rects) > MAX_RECTS:
            rect = poly.minimum_rotated_rectangle
            angle, c, rects = decompose(rect)
        rect_total += len(rects)
        max_rects = max(max_rects, len(rects))
        # local frame -> source metres -> studs is done in Lua; emit metres here
        ca, sa = math.cos(angle), math.sin(angle)
        out_rects = []
        for x0, x1, z0, z1 in rects:
            lx, lz = (x0 + x1) / 2 - c.x, (z0 + z1) / 2 - c.y
            out_rects.append((c.x + lx * ca - lz * sa, c.y + lx * sa + lz * ca, x1 - x0, z1 - z0))
        roof = None if check_only else roofs.colour(poly)
        roofed += roof is not None
        tiles[tile].append({
            "id": bid, "style": style, "h": round(height, 2), "a": math.degrees(angle),
            "floors": p.get("estimated_floors"), "name": p.get("poi_name") or p.get("site_name"),
            "rects": out_rects, "roof": roof,
        })

    print("buildings", sum(len(v) for v in tiles.values()), "tiles", len(tiles), "rects", rect_total,
          "maxRects", max_rects, "heightsFilled", filled, "roofColours", roofed)
    print("styles", styles.most_common())
    if check_only:
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.lua"):
        old.unlink()
    for tile, items in tiles.items():
        lines = ["-- Generated by tools/build_building_tiles.py. Footprints as rectangles in",
                 "-- source metres (x east, z north): {cx, cz, along, across}; a = axis deg (north from east).",
                 "return {"]
        for b in items:
            rects = ",".join("{%.2f,%.2f,%.2f,%.2f}" % r for r in b["rects"])
            extra = ""
            if b["floors"]:
                extra += ",floors=%d" % int(b["floors"])
            if b["name"]:
                extra += ",name=%s" % lua_string(str(b["name"]))
            if b["roof"]:
                # roof colour measured from the 2025 aerial, 0xRRGGBB
                extra += ",rc=0x%02x%02x%02x" % b["roof"]
            lines.append('\t["%s"]={style="%s",h=%.2f,a=%.2f%s,r={%s}},' % (
                b["id"], b["style"], b["h"], b["a"], extra, rects))
        lines.append("}")
        (OUT / f"{tile}.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("wrote", len(tiles), "modules to", OUT)


if __name__ == "__main__":
    main("--check" in sys.argv)
