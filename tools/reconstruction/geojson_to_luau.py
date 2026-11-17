#!/usr/bin/env python3
"""Convert real WGS84 building-footprint GeoJSON into an opt-in Roblox preview.

Dependencies: pip install pyproj
Uses the checked-in Chester source grid (EPSG:3857), +X east, -Z north.
No Google imagery is scraped, copied, or used for training.
"""
import argparse
import json
import math
from pathlib import Path

try:
    from pyproj import Transformer
except ImportError as exc:
    raise SystemExit("Install pyproj: py -m pip install pyproj") from exc

STUDS_PER_METER = 3.0
MAX_BUILDINGS = 300
ORIGIN_E, ORIGIN_N = -8397592.0, 4837229.0
CENTER_X, CENTER_Z = 6347.889, 7201.973

def numeric(value):
    try:
        v = float(value)
        return v if math.isfinite(v) else None
    except (ValueError, TypeError):
        return None

def rings_from_geometry(geometry):
    kind = geometry.get("type")
    coordinates = geometry.get("coordinates") or []
    if kind == "Polygon":
        return [coordinates[0]] if coordinates else []
    if kind == "MultiPolygon":
        return [polygon[0] for polygon in coordinates if polygon]
    return []

def output_module(buildings, metadata):
    lines = ["-- Generated, do not hand-edit. Uses real source footprint vertices.",
             "return {", "    metadata = " + json.dumps(metadata, ensure_ascii=False) + ",",
             "    buildings = {"]
    # JSON object syntax is not valid Luau; metadata emitted as key=value below.
    lines[2] = "    metadata = { " + ", ".join(
        key + " = " + json.dumps(value, ensure_ascii=False)
        for key, value in metadata.items()
    ) + " },"
    for b in buildings:
        lines.append("        { id = " + json.dumps(b["id"]) +
                     ", height = " + str(round(b["height"], 2)) +
                     ", heightSource = " + json.dumps(b.get("height_source", "default")) + ", points = {")
        for x, z in b["points"]:
            lines.append("            { " + f"{x:.3f}, {z:.3f}" + " },")
        lines.append("        } },")
    lines.extend(["    },", "}"])
    return "\n".join(lines) + "\n"

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--geojson", type=Path, required=True)
    p.add_argument("--origin-e", type=float, default=ORIGIN_E, help="Source manifest EPSG:3857 origin easting")
    p.add_argument("--origin-n", type=float, default=ORIGIN_N, help="Source manifest EPSG:3857 origin northing")
    p.add_argument("--center-x", type=float, default=CENTER_X)
    p.add_argument("--center-z", type=float, default=CENTER_Z)
    p.add_argument("--out", type=Path, default=Path("src/shared/ReconstructionPilot.lua"))
    p.add_argument("--max-buildings", type=int, default=MAX_BUILDINGS)
    args = p.parse_args()
    if not (1 <= args.max_buildings <= 3000):
        p.error("--max-buildings must be between 1 and 3000")
    data = json.loads(args.geojson.read_text(encoding="utf-8"))
    if data.get("type") != "FeatureCollection":
        p.error("Input must be a WGS84 lon/lat GeoJSON FeatureCollection")
    project = Transformer.from_crs("EPSG:4326", "EPSG:3857", always_xy=True)
    seen = set()
    buildings = []
    skipped = 0
    missing_heights = 0
    for idx, feature in enumerate(data.get("features") or []):
        props = feature.get("properties") or {}
        if props.get("building") in (None, "no", False) and props.get("building:part") in (None, "no", False) and props.get("Description") != "Building":
            skipped += 1
            continue
        rings = rings_from_geometry(feature.get("geometry") or {})
        for part_index, ring in enumerate(rings):
            if len(buildings) >= args.max_buildings:
                break
            points = []
            for coord in ring:
                if not isinstance(coord, (list, tuple)) or len(coord) < 2:
                    continue
                lon, lat = numeric(coord[0]), numeric(coord[1])
                if lon is None or lat is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
                    continue
                e, n = project.transform(lon, lat)
                points.append(((e - args.origin_e - args.center_x) * STUDS_PER_METER,
                               -(n - args.origin_n - args.center_z) * STUDS_PER_METER))
            if len(points) >= 2 and math.dist(points[0], points[-1]) < 0.02:
                points.pop()
            if len(points) < 3 or len(points) > 128:
                skipped += 1
                continue
            ident = str(feature.get("id") or props.get("@id") or idx) + "_" + str(part_index)
            if ident in seen:
                continue
            seen.add(ident)
            height_m = numeric(props.get("height"))
            height_source = "osm_height" if height_m and height_m > 0 else "default"
            if height_m is None:
                height_m = numeric(props.get("BuildingHeightM"))
                if height_m and height_m > 0:
                    height_source = "county_estimate"
            if height_m is None:
                levels = numeric(props.get("building:levels"))
                if levels and levels > 0:
                    height_source = "osm_levels_estimate"
                else:
                    missing_heights += 1
                height_m = (levels * 3.0) if levels and levels > 0 else 9.0
            height_m = max(2.0, min(height_m, 100.0))
            buildings.append({"id": ident, "height": height_m * STUDS_PER_METER,
                              "height_source": height_source, "points": points})
        if len(buildings) >= args.max_buildings:
            break
    source_meta = data.get("metadata") or {}
    metadata = {"studsPerMeter": STUDS_PER_METER, "count": len(buildings),
                "defaultHeightCount": missing_heights, "source": args.geojson.name,
                "attribution": source_meta.get("attribution", ""),
                "license": source_meta.get("license", ""),
                "originE": args.origin_e, "originN": args.origin_n,
                "centerX": args.center_x, "centerZ": args.center_z}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(output_module(buildings, metadata), encoding="utf-8")
    print(f"Wrote {len(buildings)} footprint(s) to {args.out}; "
          f"{missing_heights} used default 9m height; skipped {skipped}.")
    if not buildings:
        raise SystemExit("No building footprints extracted. Check GeoJSON properties.")
if __name__ == "__main__":
    main()
