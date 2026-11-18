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
from shapely.geometry import Polygon
from shapely.ops import triangulate

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
        return [coordinates[0]] if len(coordinates) == 1 else []
    if kind == "MultiPolygon":
        return [polygon[0] for polygon in coordinates if len(polygon) == 1]
    return []

def roof_triangles(points):
    """Return nonoverlapping triangle vertices for a simple, hole-free ring."""
    polygon = Polygon(points)
    if not polygon.is_valid or polygon.area <= 1e-6 or polygon.interiors:
        raise ValueError("roof requires a valid simple polygon without holes")
    pieces = []
    for triangle in triangulate(polygon):
        clipped = triangle.intersection(polygon)
        if clipped.is_empty:
            continue
        shapes = [clipped] if clipped.geom_type == "Polygon" else list(getattr(clipped, "geoms", []))
        for shape in shapes:
            if shape.area <= 1e-6:
                continue
            # A clipped triangle can be concave; triangulate it once more and
            # accept only triangles fully covered by the clipped polygon.
            for part in triangulate(shape):
                if part.area > 1e-6 and shape.covers(part):
                    pieces.append(list(part.exterior.coords)[:3])
    if abs(sum(Polygon(t).area for t in pieces) - polygon.area) > max(0.01, polygon.area * 1e-6):
        raise ValueError("roof triangles do not seal footprint")
    return pieces

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
                     ", heightSource = " + json.dumps(b.get("height_source", "estimated_default")) +
                     ", heightConfidence = " + json.dumps(b.get("height_confidence", "low")) +
                     ", roofType = " + json.dumps(b.get("roof_type", "flat_preview")) +
                     ", roofSource = " + json.dumps(b.get("roof_source", "procedural_estimate")) +
                     ", roofConfidence = " + json.dumps(b.get("roof_confidence", "low")) +
                     ", sourceRef = " + json.dumps(b.get("source_ref", "")) +
                     ", buildingType = " + json.dumps(b.get("building_type", "yes")) + ", points = {")
        for x, z in b["points"]:
            lines.append("            { " + f"{x:.3f}, {z:.3f}" + " },")
        lines.append("        }, roofTriangles = {")
        for triangle in b.get("roof_triangles", roof_triangles(b["points"])):
            lines.append("            { " + ", ".join("{ %.3f, %.3f }" % (x, z) for x, z in triangle) + " },")
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
            height_source = "osm_tag" if height_m and height_m > 0 else "estimated_default"
            if height_m is None:
                height_m = numeric(props.get("BuildingHeightM"))
                if height_m and height_m > 0:
                    height_source = "county_unverified"
            if height_m is None:
                levels = numeric(props.get("building:levels"))
                if levels and levels > 0:
                    height_source = "osm_levels_estimate"
                else:
                    missing_heights += 1
                height_m = (levels * 3.0) if levels and levels > 0 else 9.0
            height_m = max(2.0, min(height_m, 100.0))
            try:
                triangles = roof_triangles(points)
            except ValueError:
                skipped += 1
                continue
            buildings.append({"id": ident, "height": height_m * STUDS_PER_METER,
                              "height_source": height_source, "height_confidence": "low" if height_source != "osm_tag" else "medium",
                              "roof_type": props.get("roof:shape") or "flat_preview",
                              "roof_source": "osm_tag" if props.get("roof:shape") else "procedural_estimate",
                              "roof_confidence": "medium" if props.get("roof:shape") else "low",
                              "source_ref": "https://www.openstreetmap.org/way/" + ident.split("_")[2] if ident.startswith("osm_way_") else "",
                              "building_type": props.get("building") or "yes", "points": points,
                              "roof_triangles": triangles})
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
