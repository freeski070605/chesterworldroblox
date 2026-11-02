#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import time
from collections import Counter
from pathlib import Path

import requests
from pyproj import Transformer
from shapely.geometry import LineString, box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(r"E:\ChesterWorld")

REGION_DIR = ROOT / "Data" / "00_Boundary" / "RegionalExpansion"
BOUNDARY = REGION_DIR / "chester_region_boundary.geojson"
AREAS = REGION_DIR / "chester_region_areas.geojson"

CURRENT_BUILDINGS = (
    ROOT / "Data" / "14_GeneratorPrep_v2"
    / "chester_generator_buildings_v2.geojson"
)

BUILD_OUT_DIR = ROOT / "Data" / "13_RegionalMaster"
BUILD_OFFICIAL = BUILD_OUT_DIR / "official_delco_buildings_regional.geojson"
BUILD_MERGED = BUILD_OUT_DIR / "regional_buildings_base.geojson"

ROAD_OUT_DIR = ROOT / "Data" / "02_RegionalRoads"
ROAD_OFFICIAL = ROAD_OUT_DIR / "delco_roads_202601_regional.geojson"

OSM_OUT_DIR = ROOT / "Data" / "03_RegionalOSM"
OSM_ROADS = OSM_OUT_DIR / "osm_transport_lines_regional.geojson"

REPORT = REGION_DIR / "regional_source_fill_report.json"

BUILDING_LAYER = (
    "https://gis.delcopa.gov/arcgis/rest/services/"
    "DataLayers_911/Delaware_County_Building_Footprints/MapServer/0"
)

ROAD_LAYER = (
    "https://mapservices.pasda.psu.edu/server/rest/services/"
    "pasda/DelawareCounty/MapServer/0"
)

OVERPASS_ENDPOINTS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

TO_UTM = Transformer.from_crs(
    "EPSG:4326", "EPSG:32618", always_xy=True
).transform


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def save_json(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def feature_collection(name, features):
    return {
        "type": "FeatureCollection",
        "name": name,
        "crs": {
            "type": "name",
            "properties": {"name": "EPSG:4326"},
        },
        "features": features,
    }


def get_region():
    if not BOUNDARY.exists() or not AREAS.exists():
        raise SystemExit(
            "Missing RegionalExpansion boundary files. "
            "Run build_regional_expansion.py first."
        )

    boundary_data = load_json(BOUNDARY)
    region = unary_union(
        [
            shape(f["geometry"])
            for f in boundary_data.get("features", [])
            if f.get("geometry")
        ]
    )

    area_data = load_json(AREAS)
    areas = []
    for f in area_data.get("features", []):
        if not f.get("geometry"):
            continue
        props = f.get("properties") or {}
        name = (
            props.get("chesterworld_name")
            or props.get("Name")
            or props.get("NAME")
            or "Unknown"
        )
        areas.append(
            {
                "name": str(name),
                "role": props.get("chesterworld_role", ""),
                "geometry": shape(f["geometry"]),
            }
        )

    return region, areas


def arcgis_ids(layer_url: str, bounds):
    minx, miny, maxx, maxy = bounds
    params = {
        "where": "1=1",
        "geometry": f"{minx},{miny},{maxx},{maxy}",
        "geometryType": "esriGeometryEnvelope",
        "inSR": "4326",
        "spatialRel": "esriSpatialRelIntersects",
        "returnIdsOnly": "true",
        "f": "json",
    }
    r = requests.get(layer_url + "/query", params=params, timeout=90)
    r.raise_for_status()
    data = r.json()
    if data.get("error"):
        raise RuntimeError(data["error"])
    return data.get("objectIds") or []


def arcgis_geojson_by_ids(layer_url: str, object_ids):
    """
    Fetch ArcGIS features by object ID using POST.

    PASDA rejects/404s very long GET query strings, so do not put hundreds
    of object IDs in a URL. POST keeps the IDs in the request body.

    If a server still dislikes a batch, split it recursively.
    """
    session = requests.Session()
    session.headers.update({
        "User-Agent": "ChesterWorld/1.0 regional map builder"
    })

    features = []
    completed = 0

    def fetch_chunk(chunk, attempt=1):
        nonlocal completed

        params = {
            "objectIds": ",".join(str(x) for x in chunk),
            "outFields": "*",
            "returnGeometry": "true",
            "outSR": "4326",
            "f": "geojson",
        }

        try:
            r = session.post(
                layer_url + "/query",
                data=params,
                timeout=120,
            )

            # Retry transient server/rate failures before splitting.
            if r.status_code in {429, 500, 502, 503, 504}:
                raise requests.HTTPError(
                    f"{r.status_code} from ArcGIS service",
                    response=r,
                )

            r.raise_for_status()
            data = r.json()

            if data.get("error"):
                raise RuntimeError(
                    f"ArcGIS error: {data['error']}"
                )

            if data.get("type") != "FeatureCollection":
                raise RuntimeError(
                    "Expected GeoJSON FeatureCollection; "
                    f"received keys={list(data)[:10]}"
                )

            features.extend(data.get("features", []))
            completed += len(chunk)
            print(
                f"  downloaded {completed:,}/{len(object_ids):,}"
            )
            return

        except Exception as exc:
            # Long/problematic batches are divided until the service accepts
            # them. This also makes the downloader tolerant of PASDA quirks.
            if len(chunk) > 25:
                middle = len(chunk) // 2
                print(
                    f"  batch of {len(chunk)} failed ({exc}); "
                    "splitting..."
                )
                fetch_chunk(chunk[:middle])
                fetch_chunk(chunk[middle:])
                return

            if attempt < 4:
                wait_seconds = attempt * 2
                print(
                    f"  retry {attempt}/3 for {len(chunk)} IDs "
                    f"after error: {exc}"
                )
                time.sleep(wait_seconds)
                fetch_chunk(chunk, attempt + 1)
                return

            raise RuntimeError(
                f"ArcGIS batch failed after retries "
                f"({len(chunk)} IDs): {exc}"
            ) from exc

    # POST batches are intentionally smaller than the server's advertised
    # 1000-record cap to keep response bodies and processing stable.
    chunk_size = 200

    for start in range(0, len(object_ids), chunk_size):
        fetch_chunk(object_ids[start:start + chunk_size])

    return features


def filter_intersecting(features, region):
    output = []
    for f in features:
        geom_json = f.get("geometry")
        if not geom_json:
            continue
        try:
            geom = shape(geom_json)
        except Exception:
            continue
        if geom.is_empty or not geom.intersects(region):
            continue
        output.append(f)
    return output


def area_name_for_geometry(geom, areas):
    point = geom.representative_point()

    for area in areas:
        if area["geometry"].covers(point):
            return area["name"]

    best_name = "Regional Connector"
    best_measure = 0.0

    for area in areas:
        try:
            inter = geom.intersection(area["geometry"])
            measure = inter.area if geom.geom_type.endswith("Polygon") else inter.length
        except Exception:
            continue
        if measure > best_measure:
            best_measure = measure
            best_name = area["name"]

    return best_name


def building_key(props):
    for field in ("Id", "id", "OBJECTID", "objectid"):
        value = props.get(field)
        if value not in (None, ""):
            return f"{field.lower()}:{value}"
    return None


def normalize_official_building(feature, areas):
    props = dict(feature.get("properties") or {})
    geom = shape(feature["geometry"])

    area_name = area_name_for_geometry(geom, areas)

    height_m = None
    for key in ("BuildingHeightM", "buildingheightm", "height_m"):
        try:
            value = float(props.get(key))
        except Exception:
            continue
        if math.isfinite(value) and value > 2.0:
            height_m = value
            break

    if height_m is None:
        try:
            ft = float(props.get("BuildingHeightFt"))
        except Exception:
            ft = 0.0
        if math.isfinite(ft) and ft > 6.5:
            height_m = ft * 0.3048

    height_source = "county_building_height"
    if height_m is None:
        height_m = 9.15
        height_source = "regional_default"

    objectid = props.get("OBJECTID")
    source_id = props.get("Id") or objectid or "unknown"

    props.update(
        {
            "master_id": f"regional_{source_id}",
            "municipality": area_name,
            "chesterworld_region_area": area_name,
            "height_m": round(float(height_m), 4),
            "height_ft": round(float(height_m) / 0.3048, 4),
            "height_source": height_source,
            "building_use": props.get("building_use", "unknown"),
            "building_use_source": props.get(
                "building_use_source", "county_footprint_only"
            ),
            "building_use_confidence": props.get(
                "building_use_confidence", "low"
            ),
            "source_geometry": "delaware_county_building_footprints",
        }
    )

    return {
        "type": "Feature",
        "properties": props,
        "geometry": feature["geometry"],
    }


def merge_buildings(official_features, region, areas):
    current = (
        load_json(CURRENT_BUILDINGS)
        if CURRENT_BUILDINGS.exists()
        else {"features": []}
    )

    baseline = []
    keys = set()

    for f in current.get("features", []):
        if not f.get("geometry"):
            continue
        try:
            geom = shape(f["geometry"])
        except Exception:
            continue
        if geom.is_empty or not geom.intersects(region):
            continue

        baseline.append(f)
        key = building_key(f.get("properties") or {})
        if key:
            keys.add(key)

    added = []
    skipped = 0

    for f in official_features:
        props = f.get("properties") or {}
        key = building_key(props)
        if key and key in keys:
            skipped += 1
            continue

        nf = normalize_official_building(f, areas)
        added.append(nf)

        nkey = building_key(nf.get("properties") or {})
        if nkey:
            keys.add(nkey)

    merged = baseline + added

    save_json(
        BUILD_MERGED,
        feature_collection("ChesterWorld_Regional_Buildings_Base", merged),
    )

    return {
        "existing_enriched_preserved": len(baseline),
        "official_new_added": len(added),
        "official_duplicates_skipped": skipped,
        "merged_total": len(merged),
    }


def osm_query(region):
    minx, miny, maxx, maxy = region.bounds
    query = f"""
[out:json][timeout:180];
(
  way["highway"]({miny},{minx},{maxy},{maxx});
);
out tags geom;
""".strip()

    last_error = None
    for endpoint in OVERPASS_ENDPOINTS:
        try:
            print(f"Querying OSM roads: {endpoint}")
            r = requests.post(
                endpoint,
                data={"data": query},
                timeout=240,
                headers={"User-Agent": "ChesterWorld/1.0 regional map builder"},
            )
            r.raise_for_status()
            return r.json(), endpoint
        except Exception as exc:
            print(f"  failed: {exc}")
            last_error = exc

    raise RuntimeError(f"All Overpass endpoints failed: {last_error}")


def overpass_to_geojson(data, region):
    output = []

    for element in data.get("elements", []):
        if element.get("type") != "way":
            continue

        coords = []
        for p in element.get("geometry") or []:
            try:
                coords.append((float(p["lon"]), float(p["lat"])))
            except Exception:
                pass

        if len(coords) < 2:
            continue

        line = LineString(coords)
        if line.is_empty or not line.intersects(region):
            continue

        props = dict(element.get("tags") or {})
        props["osm_id"] = element.get("id")
        props["source"] = "OpenStreetMap"

        output.append(
            {
                "type": "Feature",
                "properties": props,
                "geometry": mapping(line),
            }
        )

    return output


def counts_by_area(features, areas):
    counts = Counter()
    for f in features:
        if not f.get("geometry"):
            continue
        try:
            geom = shape(f["geometry"])
        except Exception:
            continue
        for area in areas:
            if geom.intersects(area["geometry"]):
                counts[area["name"]] += 1
    return dict(counts)


def main():
    BUILD_OUT_DIR.mkdir(parents=True, exist_ok=True)
    ROAD_OUT_DIR.mkdir(parents=True, exist_ok=True)
    OSM_OUT_DIR.mkdir(parents=True, exist_ok=True)

    region, areas = get_region()

    print("=" * 86)
    print("CHESTERWORLD REGIONAL SOURCE FILL")
    print("=" * 86)

    if BUILD_OFFICIAL.exists():
        print(
            "\nUsing cached official Delaware County building footprints..."
        )
        official_buildings = load_json(
            BUILD_OFFICIAL
        ).get("features", [])
        print(
            f"Cached official buildings: {len(official_buildings):,}"
        )
    else:
        print(
            "\nDownloading official Delaware County building footprints..."
        )
        building_ids = arcgis_ids(BUILDING_LAYER, region.bounds)
        print(
            f"Building IDs in regional envelope: {len(building_ids):,}"
        )
        official_buildings = arcgis_geojson_by_ids(
            BUILDING_LAYER, building_ids
        )
        official_buildings = filter_intersecting(
            official_buildings, region
        )
        save_json(
            BUILD_OFFICIAL,
            feature_collection(
                "Official_Delco_Buildings_Regional",
                official_buildings,
            ),
        )

    # Rebuild the merged staging file from the cached official source.
    # This is local-only work and keeps the operation deterministic.
    building_merge = merge_buildings(
        official_buildings, region, areas
    )

    if ROAD_OFFICIAL.exists():
        print(
            "\nUsing cached 2026 Delaware County road centerlines..."
        )
        official_roads = load_json(
            ROAD_OFFICIAL
        ).get("features", [])
        print(
            f"Cached official roads: {len(official_roads):,}"
        )
    else:
        print(
            "\nDownloading 2026 Delaware County road centerlines..."
        )
        road_ids = arcgis_ids(ROAD_LAYER, region.bounds)
        print(
            f"Road IDs in regional envelope: {len(road_ids):,}"
        )
        official_roads = arcgis_geojson_by_ids(
            ROAD_LAYER, road_ids
        )
        official_roads = filter_intersecting(
            official_roads, region
        )
        save_json(
            ROAD_OFFICIAL,
            feature_collection(
                "Delaware_County_Roads_202601_Regional",
                official_roads,
            ),
        )

    if OSM_ROADS.exists():
        print(
            "\nUsing cached regional OSM highway/service/path detail..."
        )
        osm_features = load_json(
            OSM_ROADS
        ).get("features", [])
        osm_endpoint = "cached"
        print(
            f"Cached OSM transport features: {len(osm_features):,}"
        )
    else:
        print(
            "\nDownloading regional OSM highway/service/path detail..."
        )
        osm_data, osm_endpoint = osm_query(region)
        osm_features = overpass_to_geojson(osm_data, region)
        save_json(
            OSM_ROADS,
            feature_collection(
                "OSM_Transport_Lines_Regional",
                osm_features,
            ),
        )

    report = {
        "building_service": BUILDING_LAYER,
        "road_service": ROAD_LAYER,
        "osm_endpoint_used": osm_endpoint,
        "official_buildings": len(official_buildings),
        "building_merge": building_merge,
        "official_roads": len(official_roads),
        "osm_transport_features": len(osm_features),
        "building_counts_by_area": counts_by_area(
            official_buildings, areas
        ),
        "road_counts_by_area": counts_by_area(
            official_roads, areas
        ),
        "osm_counts_by_area": counts_by_area(
            osm_features, areas
        ),
        "outputs": {
            "regional_buildings_base": str(BUILD_MERGED),
            "official_roads": str(ROAD_OFFICIAL),
            "regional_osm": str(OSM_ROADS),
        },
    }

    save_json(REPORT, report)

    print()
    print("=" * 86)
    print("SOURCE FILL COMPLETE")
    print("=" * 86)
    print(
        f"Buildings preserved from current enriched source: "
        f"{building_merge['existing_enriched_preserved']:,}"
    )
    print(
        f"Official missing buildings added: "
        f"{building_merge['official_new_added']:,}"
    )
    print(
        f"Regional building total: "
        f"{building_merge['merged_total']:,}"
    )
    print(f"Official regional roads: {len(official_roads):,}")
    print(f"Regional OSM detail ways: {len(osm_features):,}")
    print()
    print("BUILDING COUNTS BY AREA")
    for name, count in sorted(
        report["building_counts_by_area"].items()
    ):
        print(f"  {name:<26} {count:>7,}")
    print()
    print("ROAD COUNTS BY AREA")
    for name, count in sorted(
        report["road_counts_by_area"].items()
    ):
        print(f"  {name:<26} {count:>7,}")
    print("=" * 86)


if __name__ == "__main__":
    main()
