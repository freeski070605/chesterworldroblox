#!/usr/bin/env python3
r"""
ChesterWorld orientation truth check.

Reads the ORIGINAL GIS sources and resolves:
  1. 9th St & Barclay St intersection
  2. official Chester High School point
  3. the master/generator building assigned to Chester High School

Then converts all three into the CURRENT recentered Roblox coordinate frame.

Outputs:
  src/shared/OrientationTruth.lua

This DOES NOT modify terrain, roads, buildings, StreetData, or WorldPlacement.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import Point, shape
from shapely.ops import nearest_points, transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS = ROOT / "Data" / "15_RoadGeneratorPrep" / "chester_generator_roads.geojson"
SCHOOLS = ROOT / "Data" / "05_Official_POI" / "delco_public_schools.geojson"
BUILDINGS = ROOT / "Data" / "14_GeneratorPrep_v2" / "chester_generator_buildings_v2.geojson"
WORLD = ROOT / "Data" / "16_UnityTiles" / "chester_world_manifest.json"
PLACEMENT = PROJECT / "terrain_import" / "terrain_import_manifest.json"

OUT = PROJECT / "src" / "shared" / "OrientationTruth.lua"

NINTH = re.compile(r"(?<!\d)(?:9th|ninth)(?!\d)", re.I)
BARCLAY = re.compile(r"\bbarclay\b", re.I)
CHESTER_HIGH = re.compile(r"\bchester\b.*\bhigh\b|\bhigh\b.*\bchester\b", re.I)


def load(path: Path):
    if not path.exists():
        raise SystemExit(f"Missing required file: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def clean(v):
    if v is None:
        return ""
    s = " ".join(str(v).strip().split())
    return "" if s.lower() in {"", "none", "null", "nan"} else s


def first(props, names):
    lower = {str(k).lower(): v for k, v in (props or {}).items()}
    for name in names:
        v = clean(lower.get(name.lower()))
        if v:
            return v
    return ""


def road_name(props):
    return first(props, ["generator_name", "St_Name", "StreetName", "FULLNAME", "NAME", "name"])


def school_name(props):
    return first(props, ["LABEL", "NAME", "SchoolName", "school_name"])


def school_address(props):
    return first(props, ["ADDRESS", "Address", "address"])


def lua_quote(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def representative_point(geom):
    if geom.geom_type == "Point":
        return geom
    return geom.representative_point()


def main():
    roads_data = load(ROADS)
    schools_data = load(SCHOOLS)
    buildings_data = load(BUILDINGS)
    world = load(WORLD)
    placement = load(PLACEMENT)

    origin_x = float(world["origin_epsg3857"]["x"])
    origin_z = float(world["origin_epsg3857"]["z"])

    studs_per_meter = float(placement["studs_per_meter"])
    center_x_m = float(placement["world_center_local_m"]["x"])
    center_z_m = float(placement["world_center_local_m"]["z"])

    to_3857 = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True).transform

    ninth_geoms = []
    barclay_geoms = []

    for feature in roads_data.get("features", []):
        props = feature.get("properties") or {}
        name = road_name(props)
        gj = feature.get("geometry")
        if not name or not gj:
            continue

        try:
            geom = shp_transform(to_3857, shape(gj))
        except Exception:
            continue

        if NINTH.search(name):
            ninth_geoms.append((name, geom))
        if BARCLAY.search(name):
            barclay_geoms.append((name, geom))

    if not ninth_geoms or not barclay_geoms:
        raise SystemExit(
            f"Could not find 9th/Barclay road candidates "
            f"(9th={len(ninth_geoms)}, Barclay={len(barclay_geoms)})."
        )

    best = None
    for n_name, n_geom in ninth_geoms:
        for b_name, b_geom in barclay_geoms:
            inter = n_geom.intersection(b_geom)
            if not inter.is_empty:
                p = representative_point(inter)
                gap = 0.0
            else:
                gap = n_geom.distance(b_geom)
                if gap > 30:
                    continue
                pa, pb = nearest_points(n_geom, b_geom)
                p = Point((pa.x + pb.x) / 2, (pa.y + pb.y) / 2)

            if best is None or gap < best["gap"]:
                best = {"ninth": n_name, "barclay": b_name, "point": p, "gap": gap}

    if best is None:
        raise SystemExit("Could not resolve 9th & Barclay intersection.")

    intersection_abs = best["point"]

    school_candidates = []

    for feature in schools_data.get("features", []):
        props = feature.get("properties") or {}
        name = school_name(props)
        address = school_address(props)
        text = f"{name} {address}".lower()

        if (
            CHESTER_HIGH.search(name)
            or ("chester" in text and ("9th" in text or "ninth" in text))
        ):
            gj = feature.get("geometry")
            if not gj:
                continue
            try:
                g = shape(gj)
                p_wgs = representative_point(g)
                p_abs = shp_transform(to_3857, p_wgs)
            except Exception:
                continue

            school_candidates.append(
                {"name": name, "address": address, "point": p_abs, "properties": props}
            )

    if not school_candidates:
        for feature in schools_data.get("features", []):
            props = feature.get("properties") or {}
            gj = feature.get("geometry")
            if not gj:
                continue
            try:
                p_abs = shp_transform(to_3857, representative_point(shape(gj)))
            except Exception:
                continue
            school_candidates.append(
                {
                    "name": school_name(props),
                    "address": school_address(props),
                    "point": p_abs,
                    "properties": props,
                }
            )

    school_candidates.sort(key=lambda item: item["point"].distance(intersection_abs))
    school = school_candidates[0]

    tagged = []
    for feature in buildings_data.get("features", []):
        props = feature.get("properties") or {}
        tag = clean(props.get("official_school_name"))
        if not tag or not CHESTER_HIGH.search(tag):
            continue

        gj = feature.get("geometry")
        if not gj:
            continue

        try:
            g_abs = shp_transform(to_3857, shape(gj))
            p_abs = representative_point(g_abs)
        except Exception:
            continue

        tagged.append({"name": tag, "point": p_abs, "props": props})

    building = None
    if tagged:
        tagged.sort(key=lambda item: item["point"].distance(school["point"]))
        building = tagged[0]

    def abs_to_local_m(p):
        return p.x - origin_x, p.y - origin_z

    def local_to_roblox(xm, zm):
        return (
            (xm - center_x_m) * studs_per_meter,
            (zm - center_z_m) * studs_per_meter,
        )

    ixm, izm = abs_to_local_m(intersection_abs)
    sxm, szm = abs_to_local_m(school["point"])
    irx, irz = local_to_roblox(ixm, izm)
    srx, srz = local_to_roblox(sxm, szm)

    dx_m = sxm - ixm
    dz_m = szm - izm
    distance_m = math.hypot(dx_m, dz_m)

    bearing = math.degrees(math.atan2(dx_m, dz_m))
    if bearing < 0:
        bearing += 360

    ns = "NORTH" if dz_m > 1 else "SOUTH" if dz_m < -1 else "SAME N/S"
    ew = "EAST" if dx_m > 1 else "WEST" if dx_m < -1 else "SAME E/W"

    if dz_m > 1:
        side_facing_east = "LEFT"
    elif dz_m < -1:
        side_facing_east = "RIGHT"
    else:
        side_facing_east = "STRAIGHT/LEVEL"

    print("============================================================")
    print("CHESTERWORLD ORIENTATION TRUTH CHECK")
    print("============================================================")
    print("Authoritative GIS axes: NORTH=+Z  SOUTH=-Z  EAST=+X  WEST=-X")
    print()
    print(f"Intersection: {best['ninth']} & {best['barclay']}")
    print(f"Intersection geometry gap: {best['gap']:.2f} m")
    print(f"Roblox intersection X/Z: {irx:.2f}, {irz:.2f}")
    print()
    print(f"Official school: {school['name']}")
    print(f"Official address: {school['address']}")
    print(f"Roblox school X/Z: {srx:.2f}, {srz:.2f}")
    print()
    print(
        f"School relative to 9th & Barclay: "
        f"{distance_m:.1f} m, {ns} / {ew}, bearing {bearing:.1f}°"
    )
    print(
        f"If facing EAST on 9th, official school should be on your: "
        f"{side_facing_east}"
    )

    building_payload = None
    if building:
        bxm, bzm = abs_to_local_m(building["point"])
        brx, brz = local_to_roblox(bxm, bzm)
        bdz = bzm - izm
        bdist_school = math.hypot(bxm - sxm, bzm - szm)
        bside = "LEFT" if bdz > 1 else "RIGHT" if bdz < -1 else "STRAIGHT/LEVEL"

        building_payload = {
            "name": building["name"],
            "x": brx,
            "z": brz,
            "distance_from_school_m": bdist_school,
            "side_facing_east": bside,
        }

        print()
        print(f"Tagged building: {building['name']}")
        print(f"Roblox building X/Z: {brx:.2f}, {brz:.2f}")
        print(f"Building vs official school point: {bdist_school:.1f} m")
        print(f"If facing EAST on 9th, tagged building is on your: {bside}")
    else:
        print()
        print("WARNING: No generator building explicitly tagged Chester High was found.")

    lines = [
        "return {",
        '    axes = { north = "+Z", south = "-Z", east = "+X", west = "-X" },',
        "    intersection = {",
        f"        label = {lua_quote(best['ninth'] + ' & ' + best['barclay'])},",
        f"        x = {irx:.3f},",
        f"        z = {irz:.3f},",
        "    },",
        "    school = {",
        f"        label = {lua_quote(school['name'] or 'Chester High School')},",
        f"        address = {lua_quote(school['address'])},",
        f"        x = {srx:.3f},",
        f"        z = {srz:.3f},",
        f"        sideFacingEast = {lua_quote(side_facing_east)},",
        f"        bearingFromIntersection = {bearing:.3f},",
        "    },",
    ]

    if building_payload:
        lines += [
            "    taggedBuilding = {",
            f"        label = {lua_quote(building_payload['name'])},",
            f"        x = {building_payload['x']:.3f},",
            f"        z = {building_payload['z']:.3f},",
            f"        sideFacingEast = {lua_quote(building_payload['side_facing_east'])},",
            f"        distanceFromSchoolMeters = {building_payload['distance_from_school_m']:.3f},",
            "    },",
        ]
    else:
        lines += ["    taggedBuilding = nil,"]

    lines.append("}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print()
    print(f"Wrote Roblox truth markers: {OUT}")
    print("============================================================")


if __name__ == "__main__":
    main()
