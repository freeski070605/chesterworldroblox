#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import re
from pathlib import Path
from collections import Counter

import requests
from pyproj import Transformer
from shapely.geometry import shape, mapping
from shapely.ops import unary_union, transform as shp_transform

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

OUT_DIR = ROOT / "Data" / "00_Boundary" / "RegionalExpansion"
OUT_DIR.mkdir(parents=True, exist_ok=True)

CORE_MUNICIPALITIES = [
    "Chester City",
    "Brookhaven Borough",
    "Upland Borough",
    "Eddystone Borough",
    "Marcus Hook Borough",
]

INCLUDE_CONNECTORS = True
CONNECTOR_MUNICIPALITIES = [
    "Parkside Borough",
    "Chester Township",
    "Trainer Borough",
]

DELCO_URL = (
    "https://gis.delcopa.gov/arcgis/rest/services/Boundaries/"
    "Delaware_County_Municipal_Boundaries/FeatureServer/0/query"
)

CENSUS_WOODLYN_URL = (
    "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/"
    "Places_CouSub_ConCity_SubMCD/MapServer/5/query"
)

OLD_MANIFEST = ROOT / "Data" / "16_UnityTiles" / "chester_world_manifest.json"
WORLD_PLACEMENT = PROJECT / "src" / "shared" / "WorldPlacement.lua"

CURRENT_SOURCE_LAYERS = {
    "buildings": ROOT / "Data" / "14_GeneratorPrep_v2" / "chester_generator_buildings_v2.geojson",
    "roads": ROOT / "Data" / "15_RoadGeneratorPrep" / "chester_generator_roads.geojson",
    "schools": ROOT / "Data" / "05_Official_POI" / "delco_public_schools.geojson",
    "parks": ROOT / "Data" / "05_Official_POI" / "delco_parks.geojson",
    "streams": ROOT / "Data" / "06_Water" / "delco_streams.geojson",
    "water_areas": ROOT / "Data" / "06_Water" / "delco_water_polygons.geojson",
    "rail": ROOT / "Data" / "07_Rail" / "penndot_railroads.geojson",
    "landuse": ROOT / "Data" / "11_LandUse" / "osm_landuse_areas.geojson",
}

TO_3857 = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True).transform


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def fetch_geojson(url: str, params: dict):
    response = requests.get(url, params=params, timeout=90)
    response.raise_for_status()
    data = response.json()
    if data.get("error"):
        raise RuntimeError(f"GIS server returned error: {data['error']}")
    if data.get("type") != "FeatureCollection":
        raise RuntimeError(f"Expected GeoJSON FeatureCollection from {response.url}")
    return data


def download_boundaries():
    names = list(CORE_MUNICIPALITIES)
    if INCLUDE_CONNECTORS:
        names += CONNECTOR_MUNICIPALITIES

    quoted = ",".join("'" + n.replace("'", "''") + "'" for n in names)

    municipal = fetch_geojson(
        DELCO_URL,
        {
            "where": f"Name IN ({quoted})",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
        },
    )

    found = {
        str((f.get("properties") or {}).get("Name"))
        for f in municipal.get("features", [])
    }
    missing = [n for n in names if n not in found]
    if missing:
        raise RuntimeError("Official Delaware County boundary query missed: " + ", ".join(missing))

    woodlyn = fetch_geojson(
        CENSUS_WOODLYN_URL,
        {
            "where": "STATE='42' AND PLACE='86288'",
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
        },
    )
    if len(woodlyn.get("features", [])) != 1:
        raise RuntimeError("Expected exactly one current Census Woodlyn CDP feature.")

    return municipal, woodlyn


def feature_record(feature, source, role, display_name):
    return {
        "type": "Feature",
        "properties": {
            **(feature.get("properties") or {}),
            "chesterworld_name": display_name,
            "chesterworld_role": role,
            "chesterworld_boundary_source": source,
        },
        "geometry": feature.get("geometry"),
    }


def build_region(municipal, woodlyn):
    region_features = []
    area_geometries = {}

    core_set = set(CORE_MUNICIPALITIES)
    connector_set = set(CONNECTOR_MUNICIPALITIES)

    for feature in municipal["features"]:
        props = feature.get("properties") or {}
        name = str(props.get("Name") or "").strip()
        if name in core_set:
            role = "core"
        elif name in connector_set:
            role = "connector"
        else:
            continue

        record = feature_record(feature, "Delaware County GIS", role, name)
        region_features.append(record)
        area_geometries[name] = shape(record["geometry"])

    wf = woodlyn["features"][0]
    woodlyn_record = feature_record(
        wf, "U.S. Census TIGERweb 2026", "core", "Woodlyn CDP"
    )
    region_features.append(woodlyn_record)
    area_geometries["Woodlyn CDP"] = shape(woodlyn_record["geometry"])

    union_geom = unary_union(
        [shape(f["geometry"]) for f in region_features if f.get("geometry")]
    )

    save_json(
        OUT_DIR / "chester_region_areas.geojson",
        {
            "type": "FeatureCollection",
            "name": "ChesterWorld Regional Areas",
            "features": region_features,
        },
    )

    save_json(
        OUT_DIR / "chester_region_boundary.geojson",
        {
            "type": "FeatureCollection",
            "name": "ChesterWorld Regional Playable Boundary",
            "features": [
                {
                    "type": "Feature",
                    "properties": {
                        "name": "ChesterWorld Regional Boundary",
                        "core_areas": [*CORE_MUNICIPALITIES, "Woodlyn CDP"],
                        "connector_areas": CONNECTOR_MUNICIPALITIES if INCLUDE_CONNECTORS else [],
                    },
                    "geometry": mapping(union_geom),
                }
            ],
        },
    )

    return area_geometries, union_geom


def parse_world_placement():
    if not WORLD_PLACEMENT.exists():
        raise RuntimeError(f"Missing current WorldPlacement: {WORLD_PLACEMENT}")

    text = WORLD_PLACEMENT.read_text(encoding="utf-8", errors="ignore")

    def number(name):
        for pattern in (
            rf"{re.escape(name)}\s*=\s*([-+]?\d+(?:\.\d+)?)",
            rf"WorldPlacement\.{re.escape(name)}\s*=\s*([-+]?\d+(?:\.\d+)?)",
        ):
            match = re.search(pattern, text)
            if match:
                return float(match.group(1))
        raise RuntimeError(f"Could not parse {name} from {WORLD_PLACEMENT}")

    return {
        "studs_per_meter": number("STUDS_PER_METER"),
        "center_x_m": number("CENTER_X_M"),
        "center_z_m": number("CENTER_Z_M"),
    }


def placement_shift(union_geom):
    if not OLD_MANIFEST.exists():
        raise RuntimeError(f"Missing current Chester manifest: {OLD_MANIFEST}")

    old_manifest = json.loads(OLD_MANIFEST.read_text(encoding="utf-8"))
    old_origin = old_manifest["origin_epsg3857"]

    region_m = shp_transform(TO_3857, union_geom)
    minx, miny, maxx, maxy = region_m.bounds

    new_origin_x = math.floor(minx)
    new_origin_z = math.floor(miny)

    current = parse_world_placement()

    delta_x = float(old_origin["x"]) - new_origin_x
    delta_z = float(old_origin["z"]) - new_origin_z

    new_center_x = current["center_x_m"] + delta_x
    new_center_z = current["center_z_m"] + delta_z

    values = {
        "old_origin_epsg3857": {"x": float(old_origin["x"]), "z": float(old_origin["z"])},
        "regional_origin_epsg3857": {"x": new_origin_x, "z": new_origin_z},
        "origin_shift_m": {"x": delta_x, "z": delta_z},
        "current_world_placement": {
            "studs_per_meter": current["studs_per_meter"],
            "center_x_m": current["center_x_m"],
            "center_z_m": current["center_z_m"],
        },
        "regional_world_placement": {
            "studs_per_meter": current["studs_per_meter"],
            "center_x_m": new_center_x,
            "center_z_m": new_center_z,
        },
        "regional_bounds_epsg3857": {
            "min_x": minx, "min_z": miny, "max_x": maxx, "max_z": maxy,
        },
        "regional_size_m": {
            "width": maxx - new_origin_x,
            "depth": maxy - new_origin_z,
        },
        "preserves_existing_chester_roblox_positions": True,
        "roblox_axes": {"north": "-Z", "south": "+Z", "east": "+X", "west": "-X"},
    }

    save_json(OUT_DIR / "regional_world_placement_values.json", values)

    proposal_lines = [
        "-- GENERATED PROPOSAL ONLY.",
        "-- Do not install until regional source/terrain coverage is ready.",
        "-- This center shift preserves existing Chester Roblox coordinates.",
        "",
        "local WorldPlacement = {}",
        "",
        f'WorldPlacement.STUDS_PER_METER = {current["studs_per_meter"]:.9f}',
        f'WorldPlacement.CENTER_X_M = {new_center_x:.9f}',
        f'WorldPlacement.CENTER_Z_M = {new_center_z:.9f}',
        "",
        "return WorldPlacement",
        "",
    ]
    (OUT_DIR / "WorldPlacement.regional.proposal.lua").write_text(
        "\n".join(proposal_lines), encoding="utf-8"
    )

    return values


def load_geojson(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    return data if data.get("type") == "FeatureCollection" else None


def geom_intersects_area(geometry, area):
    if geometry is None:
        return False
    try:
        g = shape(geometry)
        return (not g.is_empty) and g.intersects(area)
    except Exception:
        return False


def audit_layer(path: Path, area_geometries):
    result = {
        "path": str(path),
        "exists": path.exists(),
        "feature_count": 0,
        "by_area": {},
    }
    if not path.exists():
        return result

    data = load_geojson(path)
    if not data:
        result["error"] = "not a readable GeoJSON FeatureCollection"
        return result

    features = data.get("features", [])
    result["feature_count"] = len(features)

    for area_name, area in area_geometries.items():
        count = sum(
            1
            for feature in features
            if geom_intersects_area(feature.get("geometry"), area)
        )
        result["by_area"][area_name] = count

    return result


def audit_current_sources(area_geometries):
    report = {}
    for layer, path in CURRENT_SOURCE_LAYERS.items():
        print(f"Auditing {layer}: {path}")
        report[layer] = audit_layer(path, area_geometries)

    save_json(OUT_DIR / "regional_current_source_coverage.json", report)
    return report


def candidate_paths(kind):
    patterns = (
        ["*building*.geojson", "*buildings*.geojson"]
        if kind == "buildings"
        else ["*road*.geojson", "*roads*.geojson", "*transport*.geojson"]
    )

    found = set()
    for pattern in patterns:
        for path in ROOT.rglob(pattern):
            try:
                if path.stat().st_size > 600 * 1024 * 1024:
                    continue
            except Exception:
                continue

            text = str(path).lower()
            if "\\16_unitytiles\\" in text or "\\16_regionaltiles\\" in text:
                continue
            if "kerlinprototype" in text:
                continue
            found.add(path)

    return sorted(found)


def rank_candidates(kind, area_geometries, core_area_names):
    rows = []
    paths = candidate_paths(kind)
    print(f"Scanning {len(paths)} existing {kind} candidate GeoJSON(s)...")

    for index, path in enumerate(paths, 1):
        data = load_geojson(path)
        if not data:
            continue

        features = data.get("features", [])
        if not features:
            continue

        counts = Counter()

        for feature in features:
            geom_json = feature.get("geometry")
            if not geom_json:
                continue
            try:
                geom = shape(geom_json)
            except Exception:
                continue
            if geom.is_empty:
                continue

            for area_name, area in area_geometries.items():
                if geom.intersects(area):
                    counts[area_name] += 1

        covered_core = sum(1 for name in core_area_names if counts[name] > 0)
        total_core = sum(counts[name] for name in core_area_names)

        if covered_core:
            rows.append(
                {
                    "path": str(path),
                    "feature_count": len(features),
                    "covered_core_areas": covered_core,
                    "core_area_count": len(core_area_names),
                    "total_core_intersections": total_core,
                    "by_area": dict(counts),
                }
            )

        if index % 15 == 0:
            print(f"  checked {index}/{len(paths)} {kind} files...")

    rows.sort(
        key=lambda row: (
            row["covered_core_areas"],
            row["total_core_intersections"],
            row["feature_count"],
        ),
        reverse=True,
    )
    return rows[:20]


def candidate_scan(area_geometries):
    core_names = [*CORE_MUNICIPALITIES, "Woodlyn CDP"]
    report = {
        "buildings": rank_candidates("buildings", area_geometries, core_names),
        "roads": rank_candidates("roads", area_geometries, core_names),
    }
    save_json(OUT_DIR / "regional_existing_source_candidates.json", report)
    return report


def print_coverage(report):
    core_names = [*CORE_MUNICIPALITIES, "Woodlyn CDP"]

    print()
    print("=" * 88)
    print("CURRENT SOURCE COVERAGE")
    print("=" * 88)

    for layer in ("buildings", "roads"):
        row = report.get(layer, {})
        print()
        print(layer.upper())
        print(str(row.get("path", "")))
        by_area = row.get("by_area", {})

        for name in core_names:
            count = int(by_area.get(name, 0))
            status = "OK" if count > 0 else "MISSING"
            print(f"  {name:<24} {count:>7,}  {status}")

    print()


def main():
    print()
    print("=" * 88)
    print("CHESTERWORLD REGIONAL EXPANSION")
    print("=" * 88)
    print("Core:")
    for name in [*CORE_MUNICIPALITIES, "Woodlyn CDP"]:
        print(f"  - {name}")

    if INCLUDE_CONNECTORS:
        print("Continuity connectors:")
        for name in CONNECTOR_MUNICIPALITIES:
            print(f"  - {name}")

    print()
    print("Downloading official boundary geometry...")

    municipal, woodlyn = download_boundaries()
    area_geometries, union_geom = build_region(municipal, woodlyn)

    placement = placement_shift(union_geom)
    source_report = audit_current_sources(area_geometries)
    candidate_report = candidate_scan(area_geometries)

    print_coverage(source_report)

    print("=" * 88)
    print("REGIONAL PLACEMENT")
    print("=" * 88)
    print(
        "Old origin:      "
        f"{placement['old_origin_epsg3857']['x']:.0f}, "
        f"{placement['old_origin_epsg3857']['z']:.0f}"
    )
    print(
        "Regional origin: "
        f"{placement['regional_origin_epsg3857']['x']:.0f}, "
        f"{placement['regional_origin_epsg3857']['z']:.0f}"
    )
    print(
        "Center shift:    "
        f"X {placement['origin_shift_m']['x']:+.1f}m, "
        f"Z {placement['origin_shift_m']['z']:+.1f}m"
    )
    print(
        "New center:      "
        f"X {placement['regional_world_placement']['center_x_m']:.3f}, "
        f"Z {placement['regional_world_placement']['center_z_m']:.3f}"
    )
    print("Existing Chester Roblox coordinates preserved: YES")

    print()
    print("=" * 88)
    print("BEST EXISTING BUILDING SOURCES")
    print("=" * 88)
    for row in candidate_report["buildings"][:8]:
        print(
            f"{row['covered_core_areas']}/6 areas | "
            f"{row['total_core_intersections']:,} hits | "
            f"{row['path']}"
        )

    print()
    print("=" * 88)
    print("BEST EXISTING ROAD SOURCES")
    print("=" * 88)
    for row in candidate_report["roads"][:8]:
        print(
            f"{row['covered_core_areas']}/6 areas | "
            f"{row['total_core_intersections']:,} hits | "
            f"{row['path']}"
        )

    print()
    print("=" * 88)
    print("OUTPUT")
    print("=" * 88)
    print(OUT_DIR)
    print()
    print("Send back the console summary or these two JSON files:")
    print("  regional_current_source_coverage.json")
    print("  regional_existing_source_candidates.json")
    print("=" * 88)


if __name__ == "__main__":
    main()
