#!/usr/bin/env python3
"""Download OSM building ways from Overpass and convert to WGS84 GeoJSON.
Run locally; requires internet. OpenStreetMap contributors / ODbL.
Examples:
  py tools/reconstruction/fetch_osm_buildings.py --south 39.84 --west -75.39 --north 39.85 --east -75.37 --out chester_buildings.geojson
Coordinates in the example are NOT a verified 9th/Kerlin crop.
"""
import argparse
import json
import urllib.parse
import urllib.request
from pathlib import Path

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--south", type=float, required=True)
    p.add_argument("--west", type=float, required=True)
    p.add_argument("--north", type=float, required=True)
    p.add_argument("--east", type=float, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--endpoint", default="https://overpass-api.de/api/interpreter")
    args = p.parse_args()
    if not (-90 <= args.south < args.north <= 90 and -180 <= args.west < args.east <= 180):
        p.error("Invalid WGS84 bounding box")
    if (args.north - args.south) > 0.035 or (args.east - args.west) > 0.05:
        p.error("Pilot bbox too large. Select a few blocks first.")
    bbox = f"{args.south},{args.west},{args.north},{args.east}"
    query = f'[out:json][timeout:90];way["building"]({bbox});out geom;'
    url = args.endpoint + "?" + urllib.parse.urlencode({"data": query})
    req = urllib.request.Request(url, headers={"User-Agent": "ChesterWorldReconstructionPilot/0.1 (OpenStreetMap attribution in docs)"})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            payload = json.load(response)
    except Exception as exc:
        raise SystemExit(f"Overpass fetch failed: {exc}. Retry later or choose another endpoint.") from exc
    features = []
    for item in payload.get("elements", []):
        if item.get("type") != "way":
            continue
        geom = item.get("geometry") or []
        if len(geom) < 4:
            continue
        ring = [[point["lon"], point["lat"]] for point in geom]
        if ring[0] != ring[-1]:
            ring.append(ring[0])
        if len(set((p[0], p[1]) for p in ring)) < 3:
            continue
        tags = item.get("tags") or {}
        features.append({"type": "Feature", "id": "osm_way_" + str(item["id"]),
                         "properties": tags,
                         "geometry": {"type": "Polygon", "coordinates": [ring]}})
    result = {"type": "FeatureCollection",
              "metadata": {"source": "OpenStreetMap contributors", "license": "ODbL",
                           "attribution": "© OpenStreetMap contributors", "bbox": bbox,
                           "note": "Ways only; complex multipolygon relations not included"},
              "features": features}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")
    print(f"Saved {len(features)} OSM building ways to {args.out}. Attribution: © OpenStreetMap contributors (ODbL)")
    if not features:
        raise SystemExit("No building ways found. Check location and OSM coverage.")

if __name__ == "__main__":
    main()
