#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import statistics
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import GeometryCollection, LineString, MultiLineString, MultiPoint, Point, shape
from shapely.ops import transform as shp_transform
from shapely.strtree import STRtree

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS = ROOT / "Data" / "18_StreetSystemV3" / "regional_motor_roads_v3.geojson"
MANIFEST = ROOT / "Data" / "17_RegionalTiles_RealWorld" / "chester_world_manifest.json"

OUT_DIR = ROOT / "Data" / "19_StreetSurfaceV4"
OUT_DIR.mkdir(parents=True, exist_ok=True)

REPORT = OUT_DIR / "street_surface_v4_report.json"
DEBUG_JSON = OUT_DIR / "street_surface_v4_junctions.json"
LUA_DATA = PROJECT / "src" / "shared" / "StreetSurfaceData.lua"

UTM = "EPSG:26918"
WGS84 = "EPSG:4326"
WEBM = "EPSG:3857"

TO_UTM = Transformer.from_crs(WGS84, UTM, always_xy=True).transform
UTM_TO_WEBM = Transformer.from_crs(UTM, WEBM, always_xy=True)

STUDS_PER_METER = 3.0
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973

INTERSECTION_CLUSTER_M = 1.75
ENDPOINT_CLUSTER_M = 2.25
NEARBY_ROAD_M = 4.5

MIN_CAP_LENGTH_M = 7.0
MAX_CAP_LENGTH_M = 18.0
CAP_LENGTH_WIDTH_MULT = 1.55
CAP_EXTRA_LENGTH_M = 3.0

MAX_CAP_STRIPS = 9000


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(value):
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in {"", "none", "null", "nan"} else text


def road_width(props):
    for key in ("generator_width_m", "generator_render_width_m", "width_m", "width"):
        try:
            value = float(props.get(key))
            if 1.0 <= value <= 80.0:
                return value
        except Exception:
            pass
    return 6.0


def geometry_lines(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [geom]
    if isinstance(geom, MultiLineString):
        return [g for g in geom.geoms if not g.is_empty]
    if isinstance(geom, GeometryCollection):
        result = []
        for g in geom.geoms:
            result.extend(geometry_lines(g))
        return result
    return []


def extract_points(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Point):
        return [geom]
    if isinstance(geom, MultiPoint):
        return list(geom.geoms)
    if isinstance(geom, GeometryCollection):
        result = []
        for g in geom.geoms:
            result.extend(extract_points(g))
        return result
    return []


def street_identity(props, feature_index):
    name = clean(props.get("generator_name") or props.get("name"))
    if name:
        return "NAME:" + " ".join(name.upper().split())
    return f"FEATURE:{feature_index}"


def cluster_key(x, y, size):
    return (int(round(x / size)), int(round(y / size)))


def query_indices(tree, geoms, target):
    raw = tree.query(target)
    result = []

    for item in raw:
        try:
            idx = int(item)
            if 0 <= idx < len(geoms):
                result.append(idx)
                continue
        except Exception:
            pass

        for idx, geom in enumerate(geoms):
            if geom is item:
                result.append(idx)
                break

    return result


def roblox_xz_from_utm(x, y, origin):
    web_x, web_y = UTM_TO_WEBM.transform(x, y)

    local_x = web_x - float(origin["x"])
    local_z = web_y - float(origin["z"])

    rx = (local_x - CENTER_X_M) * STUDS_PER_METER
    rz = -(local_z - CENTER_Z_M) * STUDS_PER_METER

    return rx, rz


def local_tangent(line: LineString, point: Point, sample_m=3.5):
    try:
        d = line.project(point)
        d0 = max(0.0, d - sample_m)
        d1 = min(line.length, d + sample_m)

        if d1 - d0 < 0.25:
            d0 = max(0.0, d - 0.5)
            d1 = min(line.length, d + 0.5)

        a = line.interpolate(d0)
        b = line.interpolate(d1)

        dx = b.x - a.x
        dy = b.y - a.y
        mag = math.hypot(dx, dy)

        if mag < 1e-6:
            return None

        return dx / mag, dy / mag
    except Exception:
        return None


def canonical_dir(dx, dy):
    if dx < 0 or (abs(dx) < 1e-9 and dy < 0):
        return -dx, -dy
    return dx, dy


def lua_number(value):
    return f"{float(value):.3f}"


def main():
    print("=" * 88)
    print("CHESTERWORLD STREET SURFACE V4 - SOURCE INTERSECTION CAPS")
    print("=" * 88)

    if not ROADS.exists():
        raise SystemExit(f"Missing V3 motor roads: {ROADS}")
    if not MANIFEST.exists():
        raise SystemExit(f"Missing world manifest: {MANIFEST}")

    roads_data = load_json(ROADS)
    manifest = load_json(MANIFEST)
    origin = manifest["origin_epsg3857"]

    records = []

    for fi, feature in enumerate(roads_data.get("features", [])):
        props = dict(feature.get("properties") or {})

        try:
            geom = shape(feature.get("geometry"))
            if geom.is_empty:
                continue
            geom_m = shp_transform(TO_UTM, geom)
        except Exception:
            continue

        ident = street_identity(props, fi)
        width = road_width(props)

        for line in geometry_lines(geom_m):
            if line.length < 1.0:
                continue

            records.append({
                "line": line,
                "street": ident,
                "width": width,
                "feature_index": fi,
            })

    geoms = [record["line"] for record in records]
    tree = STRtree(geoms)

    clusters = {}

    def add_point(point, street_keys, width):
        key = cluster_key(point.x, point.y, INTERSECTION_CLUSTER_M)

        record = clusters.get(key)
        if record is None:
            record = {
                "xs": [],
                "ys": [],
                "street_keys": set(),
                "max_width": 0.0,
            }
            clusters[key] = record

        record["xs"].append(point.x)
        record["ys"].append(point.y)
        record["street_keys"].update(street_keys)
        record["max_width"] = max(record["max_width"], width)

    pair_intersections = 0

    for i, a in enumerate(records):
        candidates = query_indices(tree, geoms, a["line"])

        for j in candidates:
            if j <= i:
                continue

            b = records[j]

            if a["street"] == b["street"]:
                continue

            try:
                if not a["line"].intersects(b["line"]):
                    continue
                inter = a["line"].intersection(b["line"])
            except Exception:
                continue

            points = extract_points(inter)
            if not points:
                continue

            pair_intersections += 1

            for point in points:
                add_point(
                    point,
                    {a["street"], b["street"]},
                    max(a["width"], b["width"]),
                )

    endpoint_clusters = {}

    for record in records:
        coords = list(record["line"].coords)

        for xy in (coords[0], coords[-1]):
            key = cluster_key(xy[0], xy[1], ENDPOINT_CLUSTER_M)

            cluster = endpoint_clusters.get(key)
            if cluster is None:
                cluster = {
                    "points": [],
                    "streets": set(),
                    "max_width": 0.0,
                }
                endpoint_clusters[key] = cluster

            cluster["points"].append(xy)
            cluster["streets"].add(record["street"])
            cluster["max_width"] = max(cluster["max_width"], record["width"])

    for cluster in endpoint_clusters.values():
        if len(cluster["streets"]) < 2:
            continue

        point = Point(
            statistics.fmean(p[0] for p in cluster["points"]),
            statistics.fmean(p[1] for p in cluster["points"]),
        )

        add_point(
            point,
            cluster["streets"],
            cluster["max_width"],
        )

    junctions = []

    for cluster in clusters.values():
        if len(cluster["street_keys"]) < 2:
            continue

        x = statistics.fmean(cluster["xs"])
        y = statistics.fmean(cluster["ys"])
        point = Point(x, y)

        candidates = query_indices(tree, geoms, point.buffer(NEARBY_ROAD_M))
        per_street = {}

        for idx in candidates:
            record = records[idx]

            try:
                distance = record["line"].distance(point)
            except Exception:
                continue

            if distance > NEARBY_ROAD_M:
                continue

            tangent = local_tangent(record["line"], point)
            if tangent is None:
                continue

            current = per_street.get(record["street"])
            candidate = {
                "record": record,
                "distance": distance,
                "tangent": tangent,
            }

            if (
                current is None
                or distance < current["distance"]
                or (
                    abs(distance - current["distance"]) < 0.05
                    and record["width"] > current["record"]["width"]
                )
            ):
                per_street[record["street"]] = candidate

        if len(per_street) < 2:
            continue

        rx, rz = roblox_xz_from_utm(x, y, origin)
        strips = []
        seen_orientations = []

        for _, item in sorted(per_street.items()):
            record = item["record"]
            dx_m, dy_m = canonical_dir(*item["tangent"])

            tx, tz = roblox_xz_from_utm(
                x + dx_m,
                y + dy_m,
                origin,
            )

            rdx = tx - rx
            rdz = tz - rz
            magnitude = math.hypot(rdx, rdz)

            if magnitude < 1e-6:
                continue

            rdx /= magnitude
            rdz /= magnitude

            duplicate_orientation = False

            for odx, odz in seen_orientations:
                dot = abs(rdx * odx + rdz * odz)

                if dot >= math.cos(math.radians(7.0)):
                    duplicate_orientation = True
                    break

            if duplicate_orientation:
                continue

            seen_orientations.append((rdx, rdz))

            width_m = record["width"]
            length_m = max(
                MIN_CAP_LENGTH_M,
                min(
                    MAX_CAP_LENGTH_M,
                    width_m * CAP_LENGTH_WIDTH_MULT + CAP_EXTRA_LENGTH_M,
                ),
            )

            strips.append({
                "dx": rdx,
                "dz": rdz,
                "width": width_m * STUDS_PER_METER,
                "length": length_m * STUDS_PER_METER,
            })

        if len(strips) < 2:
            continue

        junctions.append({
            "x": rx,
            "z": rz,
            "strips": strips,
        })

    strip_count = sum(len(junction["strips"]) for junction in junctions)

    if strip_count > MAX_CAP_STRIPS:
        raise RuntimeError(
            f"V4 cap part budget exceeded: {strip_count:,} > {MAX_CAP_STRIPS:,}"
        )

    debug = {
        "junctions": junctions,
        "stats": {
            "source_motor_features": len(roads_data.get("features", [])),
            "source_motor_lines": len(records),
            "pair_intersections": pair_intersections,
            "joined_junctions": len(junctions),
            "cap_strips": strip_count,
        },
    }

    DEBUG_JSON.write_text(json.dumps(debug, indent=2), encoding="utf-8")

    lines = [
        "-- Generated by build_street_surface_v4.py",
        "-- Source-derived intersection surface caps.",
        "return {",
        '\tversion = "street-surface-v4",',
        "\tstats = {",
        f"\t\tjunctions = {len(junctions)},",
        f"\t\tstrips = {strip_count},",
        "\t},",
        "\tjunctions = {",
    ]

    for junction in junctions:
        lines.append(
            "\t\t{"
            f"x={lua_number(junction['x'])},"
            f"z={lua_number(junction['z'])},"
            "strips={"
        )

        for strip in junction["strips"]:
            lines.append(
                "\t\t\t{"
                f"dx={lua_number(strip['dx'])},"
                f"dz={lua_number(strip['dz'])},"
                f"width={lua_number(strip['width'])},"
                f"length={lua_number(strip['length'])}"
                "},"
            )

        lines.append("\t\t}},")

    lines += [
        "\t},",
        "}",
        "",
    ]

    LUA_DATA.parent.mkdir(parents=True, exist_ok=True)
    LUA_DATA.write_text("\n".join(lines), encoding="utf-8")

    report = {
        "schema": "chesterworld.street_surface.v4",
        "source": str(ROADS),
        "joined_junctions": len(junctions),
        "cap_strips": strip_count,
        "part_budget": MAX_CAP_STRIPS,
        "method": (
            "short source-aligned asphalt strips per distinct street, "
            "coplanar within each junction"
        ),
        "output_lua": str(LUA_DATA),
        "debug_json": str(DEBUG_JSON),
    }

    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Motor road features: {len(roads_data.get('features', [])):,}")
    print(f"Motor source lines:  {len(records):,}")
    print(f"Joined junctions:    {len(junctions):,}")
    print(f"V4 asphalt strips:   {strip_count:,}")
    print(f"Part budget:         {MAX_CAP_STRIPS:,}")
    print(f"Lua data:            {LUA_DATA}")
    print(f"Report:              {REPORT}")
    print("=" * 88)


if __name__ == "__main__":
    main()
