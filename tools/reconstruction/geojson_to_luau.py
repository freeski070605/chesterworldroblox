#!/usr/bin/env python3
"""Convert real WGS84 building-footprint GeoJSON into an opt-in Roblox preview.

Dependencies: pip install pyproj
Uses the VERIFIED ChesterWorld placement convention: +X east, -Z north,
3 studs per meter. The anchor's Roblox X/Z MUST be surveyed in Studio.
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
             "return {", "    metadata = " + json.dumps(metadata, ensure_ascii=True) + ",",
             "    buildings = {"]
    # JSON object syntax is not valid Luau; metadata emitted as key=value below.
    lines[2] = "    metadata = { " + ", ".join(
        key + " = " + json.dumps(value, ensure_ascii=True)
        for key, value in metadata.items()
    ) + " },"
    for b in buildings:
        lines.append("        { id = " + json.dumps(b["id"]) +
                     ", height = " + str(round(b["height"], 2)) + ", points = {")
        for x, z in b["points"]:
            lines.append("            { " + f"{x:.3f}, {z:.3f}" + " },")
        lines.append("        } },")
    lines.extend(["    },", "}"])
    return "\n".join(lines) + "\n"

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--geojson", type=Path, required=True)
    p.add_argument("--anchor-lat", type=float, required=True)
    p.add_argument("--anchor-lon", type=float, required=True)
    p.add_argument("--anchor-x", type=float, required=True, help="Measured Roblox X at anchor")
    p.add_argument("--anchor-z", type=float, required=True, help="Measured Roblox Z at anchor")
    p.add_argument("--out", type=Path, default=Path("src/shared/ReconstructionPilot.lua"))
    p.add_argument("--max-buildings", type=int, default=MAX_BUILDINGS)
    args = p.parse_args()
    if not (-90 <= args.anchor_lat <= 90 and -180 <= args.anchor_lon <= 180):
        p.error("Invalid anchor latitude/longitude")
    if not (1 <= args.max_buildings <= 3000):
        p.error("--max-buildings must be between 1 and 3000")
    data = json.loads(args.geojson.read_text(encoding="utf-8"))
    if data.get("type") != "FeatureCollection":
        p.error("Input must be a WGS84 lon/lat GeoJSON FeatureCollection")
    # Chester, Pennsylvania falls in NAD83 / UTM zone 18N; use WGS84 UTM 18N
    # for local displacement only. Uniform projection for anchor and vertices.
    project = Transformer.from_crs("EPSG:4326", "EPSG:32618", always_xy=True)
    ae, an = project.transform(args.anchor_lon, args.anchor_lat)
    seen = set()
    buildings = []
    skipped = 0
    missing_heights = 0
    for idx, feature in enumerate(data.get("features") or []):
        props = feature.get("properties") or {}
        if props.get("building") in (None, "no", False) and props.get("building:part") in (None, "no", False):
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
                points.append((args.anchor_x + (e - ae) * STUDS_PER_METER,
                               args.anchor_z - (n - an) * STUDS_PER_METER))
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
            if height_m is None:
                levels = numeric(props.get("building:levels"))
                if levels is None:
                    missing_heights += 1
                height_m = (levels * 3.0) if levels and levels > 0 else 9.0
            height_m = max(2.0, min(height_m, 100.0))
            buildings.append({"id": ident, "height": height_m * STUDS_PER_METER, "points": points})
        if len(buildings) >= args.max_buildings:
            break
    metadata = {"studsPerMeter": STUDS_PER_METER, "count": len(buildings),
                "defaultHeightCount": missing_heights, "source": args.geojson.name,
                "anchorLat": args.anchor_lat, "anchorLon": args.anchor_lon}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(output_module(buildings, metadata), encoding="utf-8")
    print(f"Wrote {len(buildings)} footprint(s) to {args.out}; "
          f"{missing_heights} used default 9m height; skipped {skipped}.")
    if not buildings:
        raise SystemExit("No building footprints extracted. Check GeoJSON properties.")
if __name__ == "__main__":
    main()
