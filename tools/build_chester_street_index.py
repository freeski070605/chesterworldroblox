#!/usr/bin/env python3
r"""
Rebuild ChesterWorld's runtime street-location database.

This version keeps only named PUBLIC DRIVABLE road classes for the
player-facing street HUD/spawn resolver. Rail lines, footways, service paths,
parking aisles, etc. are excluded from the street identifier.
"""

from __future__ import annotations

import json
import math
import re
from collections import defaultdict
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import Point, shape
from shapely.ops import nearest_points, transform as shapely_transform

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

ROADS_FILE = ROOT / "Data" / "15_RoadGeneratorPrep" / "chester_generator_roads.geojson"
WORLD_MANIFEST = ROOT / "Data" / "16_UnityTiles" / "chester_world_manifest.json"
PLACEMENT_MANIFEST = PROJECT / "terrain_import" / "terrain_import_manifest.json"

OUT_DATA = PROJECT / "src" / "shared" / "StreetData.lua"
OUT_CELLS = PROJECT / "src" / "shared" / "StreetCells"

CELL_SIZE_STUDS = 600.0
SPAWN_A_PATTERN = re.compile(r"(?<!\d)(?:9th|ninth)(?!\d)", re.I)
SPAWN_B_PATTERN = re.compile(r"\bkerlin\b", re.I)
MAX_INTERSECTION_GAP_M = 35.0

PUBLIC_DRIVABLE_CLASSES = {
    "motorway", "motorway_link", "trunk", "trunk_link",
    "primary", "primary_link", "secondary", "secondary_link",
    "tertiary", "tertiary_link", "residential", "living_street",
    "local", "unclassified", "road",
}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(value) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    if text.lower() in {"", "none", "null", "nan"}:
        return ""
    return " ".join(text.split())


def road_name(props: dict) -> str:
    for key in ("generator_name", "St_Name", "StreetName", "FULLNAME", "NAME", "name"):
        value = clean(props.get(key))
        if value:
            return value
    return ""


def road_class(props: dict) -> str:
    return clean(props.get("generator_road_class")).lower()


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def module_name(cx: int, cz: int) -> str:
    def enc(v: int) -> str:
        return ("p" + str(v)) if v >= 0 else ("m" + str(abs(v)))
    return f"cell_x{enc(cx)}_z{enc(cz)}"


def iter_lines(geom):
    if geom.is_empty:
        return
    if geom.geom_type == "LineString":
        yield geom
    elif geom.geom_type == "MultiLineString":
        yield from geom.geoms
    elif geom.geom_type == "GeometryCollection":
        for part in geom.geoms:
            yield from iter_lines(part)


def main():
    roads = load_json(ROADS_FILE)
    world = load_json(WORLD_MANIFEST)
    placement = load_json(PLACEMENT_MANIFEST)

    origin_x = float(world["origin_epsg3857"]["x"])
    origin_z = float(world["origin_epsg3857"]["z"])
    studs_per_meter = float(placement["studs_per_meter"])
    center_x_m = float(placement["world_center_local_m"]["x"])
    center_z_m = float(placement["world_center_local_m"]["z"])

    project = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True).transform

    named_features = []
    spawn_a_geoms = []
    spawn_b_geoms = []
    excluded_named = 0

    for feature in roads.get("features", []):
        props = feature.get("properties") or {}
        name = road_name(props)
        if not name:
            continue

        if road_class(props) not in PUBLIC_DRIVABLE_CLASSES:
            excluded_named += 1
            continue

        geometry_json = feature.get("geometry")
        if not geometry_json:
            continue

        try:
            geom_abs = shapely_transform(project, shape(geometry_json))
            if geom_abs.is_empty:
                continue
        except Exception:
            continue

        def localize(x, y, z=None):
            return x - origin_x, y - origin_z

        geom_local = shapely_transform(localize, geom_abs)
        named_features.append((name, geom_local))

        if SPAWN_A_PATTERN.search(name):
            spawn_a_geoms.append((name, geom_local))
        if SPAWN_B_PATTERN.search(name):
            spawn_b_geoms.append((name, geom_local))

    print("============================================")
    print("CHESTERWORLD STREET INDEX — PUBLIC ROADS")
    print("============================================")
    print(f"Named public-road features: {len(named_features):,}")
    print(f"Excluded named non-streets: {excluded_named:,}")
    print(f"9th candidates:             {len(spawn_a_geoms):,}")
    print(f"Kerlin candidates:          {len(spawn_b_geoms):,}")

    spawn = None
    best_gap = math.inf

    for name_a, geom_a in spawn_a_geoms:
        for name_b, geom_b in spawn_b_geoms:
            try:
                inter = geom_a.intersection(geom_b)
                if not inter.is_empty:
                    point = inter.representative_point()
                    gap = 0.0
                else:
                    gap = geom_a.distance(geom_b)
                    if gap > MAX_INTERSECTION_GAP_M:
                        continue
                    pa, pb = nearest_points(geom_a, geom_b)
                    point = Point((pa.x + pb.x) / 2.0, (pa.y + pb.y) / 2.0)

                if gap < best_gap:
                    best_gap = gap
                    spawn = {
                        "street_a": name_a,
                        "street_b": name_b,
                        "x_m": float(point.x),
                        "z_m": float(point.y),
                        "gap_m": float(gap),
                    }
            except Exception:
                continue

    if spawn:
        spawn["x_studs"] = (spawn["x_m"] - center_x_m) * studs_per_meter
        spawn["z_studs"] = (spawn["z_m"] - center_z_m) * studs_per_meter
        spawn["label"] = f"{spawn['street_a']} & {spawn['street_b']}"
        print(f"Resolved spawn:             {spawn['label']} (gap={spawn['gap_m']:.2f} m)")
        print(f"Roblox X/Z:                {spawn['x_studs']:.2f}, {spawn['z_studs']:.2f}")
    else:
        print("WARNING: 9th & Kerlin was not resolved.")

    segments = []
    buckets = defaultdict(list)

    for name, geom in named_features:
        for line in iter_lines(geom):
            try:
                line = line.simplify(1.0, preserve_topology=False)
            except Exception:
                pass

            coords = list(line.coords)
            for i in range(len(coords) - 1):
                x1m, z1m = coords[i][0], coords[i][1]
                x2m, z2m = coords[i + 1][0], coords[i + 1][1]

                x1 = (x1m - center_x_m) * studs_per_meter
                z1 = (z1m - center_z_m) * studs_per_meter
                x2 = (x2m - center_x_m) * studs_per_meter
                z2 = (z2m - center_z_m) * studs_per_meter

                if math.hypot(x2 - x1, z2 - z1) < 0.5:
                    continue

                idx = len(segments) + 1
                segments.append((name, x1, z1, x2, z2))

                min_cx = math.floor(min(x1, x2) / CELL_SIZE_STUDS)
                max_cx = math.floor(max(x1, x2) / CELL_SIZE_STUDS)
                min_cz = math.floor(min(z1, z2) / CELL_SIZE_STUDS)
                max_cz = math.floor(max(z1, z2) / CELL_SIZE_STUDS)

                for cx in range(min_cx, max_cx + 1):
                    for cz in range(min_cz, max_cz + 1):
                        buckets[(cx, cz)].append(idx)

    OUT_CELLS.mkdir(parents=True, exist_ok=True)
    for old in OUT_CELLS.glob("*.lua"):
        old.unlink()

    cell_modules = {}
    for (cx, cz), indices in sorted(buckets.items()):
        lines = ["return {"]
        seen = set()
        for idx in indices:
            if idx in seen:
                continue
            seen.add(idx)
            name, x1, z1, x2, z2 = segments[idx - 1]
            lines.append(
                "    {"
                f"name={lua_quote(name)},"
                f"x1={x1:.3f},z1={z1:.3f},"
                f"x2={x2:.3f},z2={z2:.3f}"
                "},"
            )
        lines.append("}")
        mod = module_name(cx, cz)
        (OUT_CELLS / f"{mod}.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
        cell_modules[f"{cx}:{cz}"] = mod

    data = [
        "return {",
        f"    cellSize = {CELL_SIZE_STUDS:.3f},",
        f"    studsPerMeter = {studs_per_meter:.6f},",
        "    cells = {",
    ]
    for key, mod in sorted(cell_modules.items()):
        data.append(f"        [{lua_quote(key)}] = {lua_quote(mod)},")
    data.append("    },")

    if spawn:
        data += [
            "    spawn = {",
            "        resolved = true,",
            f"        label = {lua_quote(spawn['label'])},",
            f"        streetA = {lua_quote(spawn['street_a'])},",
            f"        streetB = {lua_quote(spawn['street_b'])},",
            f"        x = {spawn['x_studs']:.3f},",
            f"        z = {spawn['z_studs']:.3f},",
            f"        sourceGapMeters = {spawn['gap_m']:.3f},",
            "    },",
        ]
    else:
        data.append("    spawn = { resolved = false },")

    data.append("}")
    OUT_DATA.write_text("\n".join(data) + "\n", encoding="utf-8")

    print(f"Street segments:            {len(segments):,}")
    print(f"Spatial cells:              {len(cell_modules):,}")
    print(f"StreetData:                 {OUT_DATA}")
    print(f"StreetCells:                {OUT_CELLS}")
    print("============================================")


if __name__ == "__main__":
    main()
