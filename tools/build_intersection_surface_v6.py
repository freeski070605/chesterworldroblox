#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
import statistics
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import (
    GeometryCollection,
    LineString,
    MultiLineString,
    MultiPoint,
    MultiPolygon,
    Point,
    Polygon,
    box,
    shape,
)
from shapely.ops import transform as shp_transform
from shapely.ops import triangulate, unary_union
from shapely.strtree import STRtree

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS = ROOT / "Data" / "18_StreetSystemV3" / "regional_motor_roads_v3.geojson"
MANIFEST = ROOT / "Data" / "17_RegionalTiles_RealWorld" / "chester_world_manifest.json"

OUT_DIR = ROOT / "Data" / "22_IntersectionSurfaceV6"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LUA_DATA = PROJECT / "src" / "shared" / "IntersectionSurfaceData.lua"
LUA_TILES = PROJECT / "src" / "shared" / "IntersectionSurfaceTiles"
REPORT = OUT_DIR / "intersection_surface_v6_report.json"

TO_WEBM = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True).transform

STUDS_PER_METER = 3.0
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973

INTERSECTION_CLUSTER_M = 1.75
ENDPOINT_CLUSTER_M = 2.25

# Patch radius is derived from the widest street at the junction.
MIN_PATCH_RADIUS_M = 5.0
MAX_PATCH_RADIUS_M = 12.0
PATCH_RADIUS_WIDTH_MULT = 0.62
PATCH_RADIUS_EXTRA_M = 3.0

# Runtime trimming starts just inside the patch so there is a small overlap.
ROAD_OVERLAP_STUDS = 1.5
SIDEWALK_OVERLAP_STUDS = 0.5

# Mesh grouping. 500m -> ~1500 studs, safely under Roblox's 2048-stud limit.
CELL_SIZE_M = 500.0
MAX_EXTENT_STUDS = 1800.0

SIMPLIFY_M = 0.08
MAX_EDGE_M = 4.0
MIN_TRIANGLE_AREA_M2 = 0.02

MAX_TOTAL_TRIANGLES = 180000


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def clean(value):
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in {"none", "null", "nan"} else text


def road_width(props):
    for key in (
        "generator_width_m",
        "generator_render_width_m",
        "width_m",
        "width",
    ):
        try:
            value = float(props.get(key))
            if 1.0 <= value <= 80.0:
                return value
        except Exception:
            pass
    return 6.0


def street_identity(props, feature_index):
    name = clean(props.get("generator_name") or props.get("name"))
    if name:
        return "NAME:" + " ".join(name.upper().split())
    return f"FEATURE:{feature_index}"


def lines_from_geom(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, LineString):
        return [geom]
    if isinstance(geom, MultiLineString):
        return [g for g in geom.geoms if not g.is_empty]
    if isinstance(geom, GeometryCollection):
        out = []
        for g in geom.geoms:
            out.extend(lines_from_geom(g))
        return out
    return []


def points_from_geom(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Point):
        return [geom]
    if isinstance(geom, MultiPoint):
        return list(geom.geoms)
    if isinstance(geom, GeometryCollection):
        out = []
        for g in geom.geoms:
            out.extend(points_from_geom(g))
        return out
    return []


def polygons_from_geom(geom):
    if geom is None or geom.is_empty:
        return []
    if isinstance(geom, Polygon):
        return [geom]
    if isinstance(geom, MultiPolygon):
        return [g for g in geom.geoms if not g.is_empty]
    if isinstance(geom, GeometryCollection):
        out = []
        for g in geom.geoms:
            out.extend(polygons_from_geom(g))
        return out
    return []


def query_indices(tree, geoms, target):
    raw = tree.query(target)
    out = []

    for item in raw:
        try:
            idx = int(item)
            if 0 <= idx < len(geoms):
                out.append(idx)
                continue
        except Exception:
            pass

        for idx, geom in enumerate(geoms):
            if geom is item:
                out.append(idx)
                break

    return out


def cluster_key(x, y, size):
    return (int(round(x / size)), int(round(y / size)))


def densify_ring(coords, max_edge):
    coords = list(coords)
    result = []

    for i in range(len(coords) - 1):
        ax, ay = coords[i][:2]
        bx, by = coords[i + 1][:2]

        dx = bx - ax
        dy = by - ay
        dist = math.hypot(dx, dy)
        steps = max(1, int(math.ceil(dist / max_edge)))

        for step in range(steps):
            t = step / steps
            result.append((ax + dx * t, ay + dy * t))

    if coords:
        result.append(tuple(coords[-1][:2]))

    return result


def densify_polygon(poly):
    exterior = densify_ring(poly.exterior.coords, MAX_EDGE_M)
    holes = [densify_ring(r.coords, MAX_EDGE_M) for r in poly.interiors]

    result = Polygon(exterior, holes)

    if not result.is_valid:
        result = result.buffer(0)

    return result


def triangulate_polygon(poly):
    triangles = []

    if poly.is_empty:
        return triangles

    try:
        poly = poly.simplify(SIMPLIFY_M, preserve_topology=True)
    except Exception:
        pass

    poly = densify_polygon(poly)

    for tri in triangulate(poly):
        if tri.is_empty or tri.area < MIN_TRIANGLE_AREA_M2:
            continue

        try:
            inside_area = tri.intersection(poly).area
        except Exception:
            continue

        if tri.area <= 0 or inside_area / tri.area < 0.985:
            continue

        coords = list(tri.exterior.coords)
        if len(coords) < 4:
            continue

        triangles.append([
            tuple(coords[0][:2]),
            tuple(coords[1][:2]),
            tuple(coords[2][:2]),
        ])

    return triangles


def local_to_roblox(local_x, local_z):
    return (
        (local_x - CENTER_X_M) * STUDS_PER_METER,
        -(local_z - CENTER_Z_M) * STUDS_PER_METER,
    )


def lua_num(value):
    return f"{float(value):.3f}"


def main():
    print("=" * 96)
    print("CHESTERWORLD INTERSECTION SURFACE V6 - BUILD")
    print("=" * 96)

    if not ROADS.exists():
        raise SystemExit(f"Missing motor roads: {ROADS}")
    if not MANIFEST.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST}")

    roads_data = load_json(ROADS)
    manifest = load_json(MANIFEST)
    origin = manifest["origin_epsg3857"]
    origin_x = float(origin["x"])
    origin_z = float(origin["z"])

    records = []

    for fi, feature in enumerate(roads_data.get("features", [])):
        props = dict(feature.get("properties") or {})

        try:
            geom_wgs = shape(feature.get("geometry"))
            geom_web = shp_transform(TO_WEBM, geom_wgs)
        except Exception:
            continue

        def to_local(x, y, z=None):
            if z is None:
                return (x - origin_x, y - origin_z)
            return (x - origin_x, y - origin_z, z)

        try:
            geom_local = shp_transform(to_local, geom_web)
        except Exception:
            continue

        identity = street_identity(props, fi)
        width = road_width(props)

        for line in lines_from_geom(geom_local):
            if line.length < 0.5:
                continue

            records.append({
                "line": line,
                "street": identity,
                "width": width,
                "feature_index": fi,
            })

    geoms = [r["line"] for r in records]
    tree = STRtree(geoms)

    clusters = {}

    def add_junction_point(point, streets, max_width):
        key = cluster_key(point.x, point.y, INTERSECTION_CLUSTER_M)

        rec = clusters.get(key)
        if rec is None:
            rec = {
                "xs": [],
                "ys": [],
                "streets": set(),
                "max_width": 0.0,
            }
            clusters[key] = rec

        rec["xs"].append(point.x)
        rec["ys"].append(point.y)
        rec["streets"].update(streets)
        rec["max_width"] = max(rec["max_width"], max_width)

    # Exact crossings / shared endpoints between distinct streets.
    for i, a in enumerate(records):
        for j in query_indices(tree, geoms, a["line"]):
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

            for point in points_from_geom(inter):
                add_junction_point(
                    point,
                    {a["street"], b["street"]},
                    max(a["width"], b["width"]),
                )

    # T-junction tolerance from endpoints.
    endpoint_clusters = {}

    for record in records:
        coords = list(record["line"].coords)

        for xy in (coords[0], coords[-1]):
            key = cluster_key(xy[0], xy[1], ENDPOINT_CLUSTER_M)

            rec = endpoint_clusters.get(key)
            if rec is None:
                rec = {
                    "points": [],
                    "streets": set(),
                    "max_width": 0.0,
                }
                endpoint_clusters[key] = rec

            rec["points"].append(xy)
            rec["streets"].add(record["street"])
            rec["max_width"] = max(rec["max_width"], record["width"])

    for rec in endpoint_clusters.values():
        if len(rec["streets"]) < 2:
            continue

        p = Point(
            statistics.fmean(v[0] for v in rec["points"]),
            statistics.fmean(v[1] for v in rec["points"]),
        )

        add_junction_point(
            p,
            rec["streets"],
            rec["max_width"],
        )

    junctions = []

    for rec in clusters.values():
        if len(rec["streets"]) < 2:
            continue

        x = statistics.fmean(rec["xs"])
        z = statistics.fmean(rec["ys"])
        max_width = rec["max_width"]

        radius_m = max(
            MIN_PATCH_RADIUS_M,
            min(
                MAX_PATCH_RADIUS_M,
                max_width * PATCH_RADIUS_WIDTH_MULT + PATCH_RADIUS_EXTRA_M,
            ),
        )

        junctions.append({
            "x": x,
            "z": z,
            "radius_m": radius_m,
            "max_width_m": max_width,
        })

    print(f"Corrected real junctions: {len(junctions):,}")

    # Build exact local road footprint around each junction.
    patch_polys = []

    for ji, junction in enumerate(junctions):
        point = Point(junction["x"], junction["z"])
        radius = junction["radius_m"]

        search = point.buffer(radius + 8.0)
        candidates = query_indices(tree, geoms, search)

        buffers = []

        for idx in candidates:
            record = records[idx]

            try:
                if record["line"].distance(point) > radius + record["width"]:
                    continue
            except Exception:
                continue

            try:
                road_poly = record["line"].buffer(
                    record["width"] / 2.0,
                    cap_style=2,
                    join_style=2,
                    mitre_limit=3.0,
                )
            except Exception:
                continue

            buffers.append(road_poly)

        if not buffers:
            continue

        try:
            footprint = unary_union(buffers)
            footprint = footprint.intersection(
                point.buffer(radius, resolution=12)
            )
        except Exception:
            continue

        if footprint.is_empty:
            continue

        patch_polys.append((ji, footprint))

    # Group patches into 500m cells to keep MeshPart extents safely below 2048 studs.
    cell_polys = {}

    for ji, footprint in patch_polys:
        min_x, min_z, max_x, max_z = footprint.bounds

        min_cx = math.floor(min_x / CELL_SIZE_M)
        max_cx = math.floor(max_x / CELL_SIZE_M)
        min_cz = math.floor(min_z / CELL_SIZE_M)
        max_cz = math.floor(max_z / CELL_SIZE_M)

        for cx in range(min_cx, max_cx + 1):
            for cz in range(min_cz, max_cz + 1):
                cell = box(
                    cx * CELL_SIZE_M,
                    cz * CELL_SIZE_M,
                    (cx + 1) * CELL_SIZE_M,
                    (cz + 1) * CELL_SIZE_M,
                )

                clipped = footprint.intersection(cell)

                if clipped.is_empty:
                    continue

                cell_polys.setdefault((cx, cz), []).append(clipped)

    if LUA_TILES.exists():
        shutil.rmtree(LUA_TILES)
    LUA_TILES.mkdir(parents=True, exist_ok=True)

    total_vertices = 0
    total_triangles = 0
    max_extent_x = 0.0
    max_extent_z = 0.0
    surface_count = 0

    for (cx, cz), polygons in sorted(cell_polys.items()):
        merged = unary_union(polygons)

        triangles_xy = []

        for poly in polygons_from_geom(merged):
            triangles_xy.extend(triangulate_polygon(poly))

        if not triangles_xy:
            continue

        center_local_x = (cx + 0.5) * CELL_SIZE_M
        center_local_z = (cz + 0.5) * CELL_SIZE_M
        origin_rx, origin_rz = local_to_roblox(center_local_x, center_local_z)

        vertex_map = {}
        vertices = []
        triangles = []

        def vid(local_x, local_z):
            rx, rz = local_to_roblox(local_x, local_z)
            key = (
                round(rx - origin_rx, 3),
                round(rz - origin_rz, 3),
            )

            existing = vertex_map.get(key)
            if existing is not None:
                return existing

            idx = len(vertices) + 1
            vertex_map[key] = idx
            vertices.append(key)
            return idx

        for tri in triangles_xy:
            ids = [
                vid(*tri[0]),
                vid(*tri[1]),
                vid(*tri[2]),
            ]

            if len(set(ids)) == 3:
                triangles.append(tuple(ids))

        if not vertices or not triangles:
            continue

        xs = [v[0] for v in vertices]
        zs = [v[1] for v in vertices]

        extent_x = max(xs) - min(xs)
        extent_z = max(zs) - min(zs)

        if extent_x > MAX_EXTENT_STUDS or extent_z > MAX_EXTENT_STUDS:
            raise RuntimeError(
                f"Intersection cell {cx},{cz} exceeds mesh extent guard: "
                f"{extent_x:.1f} x {extent_z:.1f} studs"
            )

        max_extent_x = max(max_extent_x, extent_x)
        max_extent_z = max(max_extent_z, extent_z)

        surface_id = f"intersection_c{cx}_{cz}"
        path = LUA_TILES / f"{surface_id}.lua"

        lines = [
            "-- Generated by build_intersection_surface_v6.py",
            "return {",
            f'\tsurfaceId = "{surface_id}",',
            f"\toriginX = {lua_num(origin_rx)},",
            f"\toriginZ = {lua_num(origin_rz)},",
            "\tvertices = {",
        ]

        flat = []
        for x, z in vertices:
            flat.extend((x, z))

        chunk = []
        for value in flat:
            chunk.append(lua_num(value))
            if len(chunk) >= 16:
                lines.append("\t\t" + ",".join(chunk) + ",")
                chunk = []
        if chunk:
            lines.append("\t\t" + ",".join(chunk) + ",")

        lines += ["\t},", "\ttriangles = {"]

        flat_tri = []
        for a, b, c in triangles:
            flat_tri.extend((a, b, c))

        chunk = []
        for value in flat_tri:
            chunk.append(str(int(value)))
            if len(chunk) >= 24:
                lines.append("\t\t" + ",".join(chunk) + ",")
                chunk = []
        if chunk:
            lines.append("\t\t" + ",".join(chunk) + ",")

        lines += ["\t},", "}", ""]

        path.write_text("\n".join(lines), encoding="utf-8")

        surface_count += 1
        total_vertices += len(vertices)
        total_triangles += len(triangles)

    if total_triangles > MAX_TOTAL_TRIANGLES:
        raise RuntimeError(
            f"Intersection mesh triangle budget exceeded: {total_triangles:,}"
        )

    # Junction metadata for runtime trimming / plane fitting.
    lines = [
        "-- Generated by build_intersection_surface_v6.py",
        "return {",
        f"\troadOverlapStuds = {lua_num(ROAD_OVERLAP_STUDS)},",
        f"\tsidewalkOverlapStuds = {lua_num(SIDEWALK_OVERLAP_STUDS)},",
        "\tjunctions = {",
    ]

    for j in junctions:
        rx, rz = local_to_roblox(j["x"], j["z"])
        lines.append(
            "\t\t{"
            f"x={lua_num(rx)},"
            f"z={lua_num(rz)},"
            f"radius={lua_num(j['radius_m'] * STUDS_PER_METER)},"
            f"width={lua_num(j['max_width_m'] * STUDS_PER_METER)}"
            "},"
        )

    lines += ["\t},", "}", ""]

    LUA_DATA.parent.mkdir(parents=True, exist_ok=True)
    LUA_DATA.write_text("\n".join(lines), encoding="utf-8")

    report = {
        "schema": "chesterworld.intersection_surface.v6",
        "junctions": len(junctions),
        "patches_built": len(patch_polys),
        "surface_modules": surface_count,
        "total_vertices": total_vertices,
        "total_triangles": total_triangles,
        "max_extent_x_studs": round(max_extent_x, 3),
        "max_extent_z_studs": round(max_extent_z, 3),
        "cell_size_m": CELL_SIZE_M,
        "max_extent_guard_studs": MAX_EXTENT_STUDS,
    }

    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Intersection patches:    {len(patch_polys):,}")
    print(f"Surface modules:         {surface_count:,}")
    print(f"Total vertices:          {total_vertices:,}")
    print(f"Total triangles:         {total_triangles:,}")
    print(f"Max X extent:            {max_extent_x:,.1f} studs")
    print(f"Max Z extent:            {max_extent_z:,.1f} studs")
    print(f"Data:                    {LUA_DATA}")
    print(f"Surface folder:          {LUA_TILES}")
    print(f"Report:                  {REPORT}")
    print("=" * 96)


if __name__ == "__main__":
    main()
