#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import (
    GeometryCollection,
    LineString,
    MultiLineString,
    MultiPoint,
    Point,
    shape,
    mapping,
)
from shapely.ops import (
    linemerge,
    transform as shp_transform,
    unary_union,
)
from shapely.strtree import STRtree

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS = (
    ROOT / "Data" / "17_RealWorldCleanup"
    / "regional_generator_roads_render_v2.geojson"
)
MANIFEST = (
    ROOT / "Data" / "17_RegionalTiles_RealWorld"
    / "chester_world_manifest.json"
)

OUT_DIR = ROOT / "Data" / "18_StreetSystemV3"
OUT_DIR.mkdir(parents=True, exist_ok=True)

MOTOR_ROADS = OUT_DIR / "regional_motor_roads_v3.geojson"
NONMOTOR_PATHS = OUT_DIR / "regional_nonmotor_paths_v3.geojson"
REPORT = OUT_DIR / "street_system_v3_report.json"
FINISH_JSON = OUT_DIR / "street_finish_source_v3.json"

LUA_DATA = PROJECT / "src" / "shared" / "StreetFinishData.lua"

UTM = "EPSG:26918"
WGS84 = "EPSG:4326"
WEBM = "EPSG:3857"

TO_UTM = Transformer.from_crs(WGS84, UTM, always_xy=True).transform
UTM_TO_WEBM = Transformer.from_crs(UTM, WEBM, always_xy=True)

STUDS_PER_METER = 3.0
CENTER_X_M = 6347.889
CENTER_Z_M = 7201.973

NON_MOTOR_CLASSES = {
    "pedestrian",
    "footway",
    "path",
    "cycleway",
    "steps",
    "track",
    "bridleway",
}

NO_SIDEWALK_CLASSES = NON_MOTOR_CLASSES | {
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "service",
    "alley",
}

DEFAULT_SIDEWALK_CLASSES = {
    "residential",
    "tertiary",
    "tertiary_link",
    "secondary",
    "secondary_link",
    "primary",
    "primary_link",
    "unclassified",
    "living_street",
    "local",
    "road",
}

SIDEWALK_WIDTH_M = 1.50
CURB_GAP_M = 0.20
MAX_SIDEWALK_SEGMENT_M = 24.0
MIN_SIDEWALK_SEGMENT_M = 1.2
SIMPLIFY_M = 0.18

# Tight enough to remove obvious micro-slivers after clipping/source prep.
MIN_MOTOR_LINE_LENGTH_M = 1.5

# Source-level intersection handling.
INTERSECTION_CLUSTER_M = 1.75
ENDPOINT_CLUSTER_M = 2.25
INTERSECTION_EXTRA_M = 1.45


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(value):
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in {"", "none", "null", "nan"} else text


def road_class(props):
    return clean(
        props.get("generator_road_class")
        or props.get("road_class")
        or props.get("osm_highway")
        or "unknown"
    ).lower()


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


def source_name(props):
    return clean(props.get("generator_source")).lower()


def source_priority(props):
    try:
        return int(props.get("generator_source_priority", 9))
    except Exception:
        return 9


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
    # If two lines overlap, don't treat the whole overlap as an intersection node.
    return []


def sidewalk_sides(props, cls):
    if cls in NO_SIDEWALK_CLASSES:
        return []

    bridge = clean(props.get("osm_bridge")).lower()
    tunnel = clean(props.get("osm_tunnel")).lower()
    if bridge in {"yes", "true", "1"} or tunnel in {"yes", "true", "1"}:
        return []

    tag = clean(props.get("osm_sidewalk")).lower()

    if tag in {"no", "none", "false", "0"}:
        return []
    if tag == "left":
        return ["left"]
    if tag == "right":
        return ["right"]
    if tag in {"both", "yes", "separate"}:
        return ["left", "right"]

    if cls in DEFAULT_SIDEWALK_CLASSES:
        return ["left", "right"]

    return []


def normalized_name(props, fallback):
    name = clean(props.get("generator_name") or props.get("name"))
    if name:
        return " ".join(name.upper().split())
    return fallback


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

        for idx, candidate in enumerate(geoms):
            if candidate is item:
                out.append(idx)
                break
    return out


def cluster_key(x, y, size):
    return (
        int(round(x / size)),
        int(round(y / size)),
    )


def roblox_xz_from_utm(x, y, origin):
    web_x, web_y = UTM_TO_WEBM.transform(x, y)

    local_x = web_x - float(origin["x"])
    local_z = web_y - float(origin["z"])

    rx = (local_x - CENTER_X_M) * STUDS_PER_METER
    rz = -(local_z - CENTER_Z_M) * STUDS_PER_METER

    return rx, rz


def densify_pair(a, b, max_len):
    ax, ay = a
    bx, by = b

    dist = math.hypot(bx - ax, by - ay)
    steps = max(1, int(math.ceil(dist / max_len)))

    pts = []
    for i in range(steps + 1):
        t = i / steps
        pts.append((
            ax + (bx - ax) * t,
            ay + (by - ay) * t,
        ))
    return pts


def iter_segment_pairs(line):
    coords = list(line.coords)
    if len(coords) < 2:
        return

    for i in range(len(coords) - 1):
        dense = densify_pair(
            coords[i],
            coords[i + 1],
            MAX_SIDEWALK_SEGMENT_M,
        )

        for j in range(len(dense) - 1):
            a = dense[j]
            b = dense[j + 1]

            if math.hypot(
                b[0] - a[0],
                b[1] - a[1],
            ) >= MIN_SIDEWALK_SEGMENT_M:
                yield a, b


def lua_number(v):
    return f"{float(v):.3f}"


def write_lua_data(segments, junctions, stats):
    LUA_DATA.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        "-- Generated by build_street_system_v3.py",
        "-- Source-level sidewalks/intersections; do not hand-edit.",
        "return {",
        '\tversion = "street-v3",',
        f"\tsidewalkWidthStuds = {lua_number(SIDEWALK_WIDTH_M * STUDS_PER_METER)},",
        "\tstats = {",
    ]

    for key in (
        "motor_features",
        "nonmotor_features",
        "dropped_osm_building_conflicts",
        "dropped_micro_motor_lines",
        "sidewalk_segments",
        "junctions",
    ):
        lines.append(f"\t\t{key} = {int(stats.get(key, 0))},")

    lines += [
        "\t},",
        "\tsegments = {",
    ]

    for s in segments:
        lines.append(
            "\t\t{"
            f"x1={lua_number(s['x1'])},"
            f"z1={lua_number(s['z1'])},"
            f"x2={lua_number(s['x2'])},"
            f"z2={lua_number(s['z2'])}"
            "},"
        )

    lines += [
        "\t},",
        "\tjunctions = {",
    ]

    for j in junctions:
        lines.append(
            "\t\t{"
            f"x={lua_number(j['x'])},"
            f"z={lua_number(j['z'])},"
            f"size={lua_number(j['size'])}"
            "},"
        )

    lines += [
        "\t},",
        "}",
        "",
    ]

    LUA_DATA.write_text("\n".join(lines), encoding="utf-8")


def main():
    print("=" * 92)
    print("CHESTERWORLD STREET SYSTEM V3 — SOURCE BUILD")
    print("=" * 92)

    if not ROADS.exists():
        raise SystemExit(f"Missing road source: {ROADS}")
    if not MANIFEST.exists():
        raise SystemExit(f"Missing manifest: {MANIFEST}")

    data = load_json(ROADS)
    manifest = load_json(MANIFEST)
    origin = manifest["origin_epsg3857"]

    motor_features = []
    nonmotor_features = []
    dropped_osm_building_conflicts = []
    dropped_low_priority_unknown = []

    metric_records = []

    for fi, feature in enumerate(data.get("features", [])):
        props = dict(feature.get("properties") or {})
        cls = road_class(props)
        src = source_name(props)

        try:
            geom_wgs = shape(feature.get("geometry"))
            if geom_wgs.is_empty:
                continue
            geom_utm = shp_transform(TO_UTM, geom_wgs)
        except Exception:
            continue

        lines = geometry_lines(geom_utm)
        length_m = sum(g.length for g in lines)

        if cls in NON_MOTOR_CLASSES:
            nonmotor_features.append(feature)
            continue

        # Low-priority OSM detail that physically cuts through a building is
        # almost always the wrong thing to render as a motor street.
        hits = 0
        try:
            hits = int(props.get("generator_centerline_building_hits", 0) or 0)
        except Exception:
            hits = 0

        if src == "osm" and hits > 0:
            dropped_osm_building_conflicts.append(feature)
            continue

        # Unknown, unnamed, very-low-priority OSM detail is not motor asphalt.
        if (
            src == "osm"
            and source_priority(props) >= 4
            and cls in {"", "unknown", "road"}
            and not clean(props.get("generator_name") or props.get("name"))
        ):
            dropped_low_priority_unknown.append(feature)
            continue

        if length_m < MIN_MOTOR_LINE_LENGTH_M:
            # Save as nonmotor/detail so it is not lost, but never render it
            # as a standalone asphalt sliver.
            nonmotor_features.append(feature)
            continue

        motor_features.append(feature)

        for li, line in enumerate(lines):
            if line.length < MIN_MOTOR_LINE_LENGTH_M:
                continue
            metric_records.append({
                "feature_index": fi,
                "line_id": len(metric_records),
                "geometry": line,
                "properties": props,
                "class": cls,
                "width": road_width(props),
            })

    motor_output = dict(data)
    motor_output["name"] = "ChesterWorld_Regional_Motor_Roads_v3"
    motor_output["features"] = motor_features
    MOTOR_ROADS.write_text(
        json.dumps(motor_output, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    path_output = dict(data)
    path_output["name"] = "ChesterWorld_Regional_NonMotor_Paths_v3"
    path_output["features"] = (
        nonmotor_features
        + dropped_osm_building_conflicts
        + dropped_low_priority_unknown
    )
    NONMOTOR_PATHS.write_text(
        json.dumps(path_output, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    # ------------------------------------------------------------------
    # SOURCE-LEVEL INTERSECTION NODES
    # ------------------------------------------------------------------
    geoms = [r["geometry"] for r in metric_records]
    tree = STRtree(geoms)

    point_clusters = {}

    def add_intersection_point(point, width):
        key = cluster_key(
            point.x,
            point.y,
            INTERSECTION_CLUSTER_M,
        )
        rec = point_clusters.get(key)
        if rec is None:
            rec = {
                "xs": [],
                "ys": [],
                "max_width": 0.0,
                "hits": 0,
            }
            point_clusters[key] = rec

        rec["xs"].append(point.x)
        rec["ys"].append(point.y)
        rec["max_width"] = max(rec["max_width"], width)
        rec["hits"] += 1

    pair_count = 0

    for i, a in enumerate(metric_records):
        candidates = query_indices(
            tree,
            geoms,
            a["geometry"],
        )

        for j in candidates:
            if j <= i:
                continue

            b = metric_records[j]

            try:
                if not a["geometry"].intersects(b["geometry"]):
                    continue
                inter = a["geometry"].intersection(b["geometry"])
            except Exception:
                continue

            pts = extract_points(inter)
            if not pts:
                continue

            pair_count += 1
            width = max(a["width"], b["width"])

            for p in pts:
                add_intersection_point(p, width)

    # Endpoint clusters catch T-junctions that miss exact intersection by a
    # small source tolerance.
    endpoint_clusters = {}
    for record in metric_records:
        coords = list(record["geometry"].coords)
        if len(coords) < 2:
            continue

        for xy in (coords[0], coords[-1]):
            key = cluster_key(
                xy[0],
                xy[1],
                ENDPOINT_CLUSTER_M,
            )
            rec = endpoint_clusters.get(key)
            if rec is None:
                rec = {
                    "points": [],
                    "road_ids": set(),
                    "max_width": 0.0,
                }
                endpoint_clusters[key] = rec

            rec["points"].append(xy)
            rec["road_ids"].add(record["line_id"])
            rec["max_width"] = max(
                rec["max_width"],
                record["width"],
            )

    for rec in endpoint_clusters.values():
        if len(rec["road_ids"]) < 3:
            continue

        x = statistics.fmean(p[0] for p in rec["points"])
        y = statistics.fmean(p[1] for p in rec["points"])
        add_intersection_point(
            Point(x, y),
            rec["max_width"],
        )

    junction_records = []
    junction_buffers = []

    for rec in point_clusters.values():
        x = statistics.fmean(rec["xs"])
        y = statistics.fmean(rec["ys"])
        width = rec["max_width"]

        radius = max(
            3.0,
            width / 2.0 + INTERSECTION_EXTRA_M,
        )

        p = Point(x, y)
        junction_buffers.append(p.buffer(radius))

        rx, rz = roblox_xz_from_utm(
            x,
            y,
            origin,
        )

        size_m = max(
            6.0,
            min(14.0, width + 1.5),
        )

        junction_records.append({
            "x": rx,
            "z": rz,
            "size": size_m * STUDS_PER_METER,
        })

    junction_union = (
        unary_union(junction_buffers)
        if junction_buffers
        else None
    )

    # ------------------------------------------------------------------
    # MERGE SAME-STREET SOURCE GEOMETRY BEFORE OFFSETTING
    # ------------------------------------------------------------------
    groups = defaultdict(list)
    group_meta = {}

    for record in metric_records:
        props = record["properties"]
        sides = sidewalk_sides(
            props,
            record["class"],
        )
        if not sides:
            continue

        fallback = f"__feature_{record['feature_index']}"
        name = normalized_name(props, fallback)

        key = (
            name,
            record["class"],
            round(record["width"], 1),
            ",".join(sorted(sides)),
        )

        groups[key].append(record["geometry"])
        group_meta[key] = {
            "width": record["width"],
            "sides": sides,
        }

    sidewalk_segments = []

    for key, group_lines in groups.items():
        meta = group_meta[key]

        try:
            merged = linemerge(unary_union(group_lines))
        except Exception:
            merged = MultiLineString(group_lines)

        center_lines = geometry_lines(merged)

        for center in center_lines:
            if center.length < 2.0:
                continue

            width = meta["width"]
            center_distance = (
                width / 2.0
                + CURB_GAP_M
                + SIDEWALK_WIDTH_M / 2.0
            )

            for side in meta["sides"]:
                distance = (
                    center_distance
                    if side == "left"
                    else -center_distance
                )

                try:
                    offset = center.offset_curve(
                        distance,
                        quad_segs=4,
                        join_style=2,
                        mitre_limit=3.0,
                    )
                except Exception:
                    try:
                        offset = center.parallel_offset(
                            abs(distance),
                            side,
                            resolution=4,
                            join_style=2,
                            mitre_limit=3.0,
                        )
                    except Exception:
                        continue

                if offset is None or offset.is_empty:
                    continue

                if junction_union is not None:
                    try:
                        offset = offset.difference(junction_union)
                    except Exception:
                        pass

                for line in geometry_lines(offset):
                    try:
                        line = line.simplify(
                            SIMPLIFY_M,
                            preserve_topology=False,
                        )
                    except Exception:
                        pass

                    if line.length < MIN_SIDEWALK_SEGMENT_M:
                        continue

                    for a, b in iter_segment_pairs(line):
                        x1, z1 = roblox_xz_from_utm(
                            a[0], a[1], origin
                        )
                        x2, z2 = roblox_xz_from_utm(
                            b[0], b[1], origin
                        )

                        sidewalk_segments.append({
                            "x1": x1,
                            "z1": z1,
                            "x2": x2,
                            "z2": z2,
                        })

    stats = {
        "input_road_features": len(data.get("features", [])),
        "motor_features": len(motor_features),
        "nonmotor_features": len(nonmotor_features),
        "dropped_osm_building_conflicts": len(
            dropped_osm_building_conflicts
        ),
        "dropped_low_priority_unknown": len(
            dropped_low_priority_unknown
        ),
        "dropped_micro_motor_lines": sum(
            1 for f in nonmotor_features
            if road_class(f.get("properties") or {})
            not in NON_MOTOR_CLASSES
        ),
        "metric_motor_lines": len(metric_records),
        "intersection_pairs": pair_count,
        "junctions": len(junction_records),
        "sidewalk_groups": len(groups),
        "sidewalk_segments": len(sidewalk_segments),
    }

    report = {
        "schema": "chesterworld.street_system.v3",
        "stats": stats,
        "constants": {
            "sidewalk_width_m": SIDEWALK_WIDTH_M,
            "curb_gap_m": CURB_GAP_M,
            "max_sidewalk_segment_m": MAX_SIDEWALK_SEGMENT_M,
            "studs_per_meter": STUDS_PER_METER,
            "north": "-Z",
            "east": "+X",
        },
        "outputs": {
            "motor_roads": str(MOTOR_ROADS),
            "nonmotor_paths": str(NONMOTOR_PATHS),
            "finish_json": str(FINISH_JSON),
            "lua_data": str(LUA_DATA),
        },
    }

    FINISH_JSON.write_text(
        json.dumps({
            "segments": sidewalk_segments,
            "junctions": junction_records,
            "stats": stats,
        }, indent=2),
        encoding="utf-8",
    )
    REPORT.write_text(
        json.dumps(report, indent=2),
        encoding="utf-8",
    )

    write_lua_data(
        sidewalk_segments,
        junction_records,
        stats,
    )

    print()
    print("SOURCE ROAD CLEANUP")
    print("-" * 92)
    print(f"Input road features:                {stats['input_road_features']:,}")
    print(f"Motor road features retained:       {stats['motor_features']:,}")
    print(f"Non-motor/path features separated:  {stats['nonmotor_features']:,}")
    print(
        "OSM building-cut conflicts removed: "
        f"{stats['dropped_osm_building_conflicts']:,}"
    )
    print(
        "Low-priority unknown OSM removed:    "
        f"{stats['dropped_low_priority_unknown']:,}"
    )
    print()
    print("SOURCE-LEVEL STREET FINISH")
    print("-" * 92)
    print(f"Motor source lines:                 {stats['metric_motor_lines']:,}")
    print(f"Real junction nodes:                {stats['junctions']:,}")
    print(f"Continuous sidewalk groups:         {stats['sidewalk_groups']:,}")
    print(f"Terrain-conforming sidewalk parts:  {stats['sidewalk_segments']:,}")
    print()
    print(f"Motor roads: {MOTOR_ROADS}")
    print(f"Finish data: {LUA_DATA}")
    print(f"Report:      {REPORT}")
    print("=" * 92)


if __name__ == "__main__":
    main()
