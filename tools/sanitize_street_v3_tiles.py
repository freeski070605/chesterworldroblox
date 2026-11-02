#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
TILE_ROOT = ROOT / "Data" / "18_RegionalTiles_StreetV3"
TILES = TILE_ROOT / "Tiles"
MANIFEST = TILE_ROOT / "chester_world_manifest.json"
REPORT = TILE_ROOT / "street_v3_tile_sanitize_report.json"

MIN_LENGTH_M = 1.5


def line_length(coords):
    total = 0.0
    for i in range(len(coords) - 1):
        a = coords[i]
        b = coords[i + 1]
        if len(a) < 2 or len(b) < 2:
            continue
        total += math.hypot(
            float(b[0]) - float(a[0]),
            float(b[1]) - float(a[1]),
        )
    return total


def geometry_length(geom):
    if not isinstance(geom, dict):
        return 0.0
    typ = geom.get("type")
    coords = geom.get("coordinates")

    if typ == "LineString" and isinstance(coords, list):
        return line_length(coords)

    if typ == "MultiLineString" and isinstance(coords, list):
        return sum(
            line_length(line)
            for line in coords
            if isinstance(line, list)
        )

    return 0.0


def main():
    print("=" * 84)
    print("CHESTERWORLD STREET V3 — TILE SANITIZER")
    print("=" * 84)

    if not TILES.exists():
        raise SystemExit(f"Missing tiles: {TILES}")

    removed = 0
    kept = 0
    tile_counts = {}

    for path in sorted(TILES.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        layers = data.get("layers") or {}
        roads = list(layers.get("roads") or [])

        clean_roads = []
        for item in roads:
            length = geometry_length(item.get("geometry") or {})
            if length < MIN_LENGTH_M:
                removed += 1
                continue
            clean_roads.append(item)
            kept += 1

        layers["roads"] = clean_roads
        data["layers"] = layers

        if isinstance(data.get("feature_counts"), dict):
            data["feature_counts"]["roads"] = len(clean_roads)

        path.write_text(
            json.dumps(
                data,
                ensure_ascii=False,
                separators=(",", ":"),
            ),
            encoding="utf-8",
        )
        tile_counts[path.name] = len(clean_roads)

    if MANIFEST.exists():
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        for item in manifest.get("tiles", []):
            filename = Path(item.get("file", "")).name
            if filename in tile_counts:
                fc = item.setdefault("feature_counts", {})
                fc["roads"] = tile_counts[filename]

        MANIFEST.write_text(
            json.dumps(manifest, indent=2),
            encoding="utf-8",
        )

    report = {
        "min_length_m": MIN_LENGTH_M,
        "road_records_kept": kept,
        "micro_slivers_removed": removed,
        "tiles": len(tile_counts),
    }
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Tiles sanitized:       {len(tile_counts):,}")
    print(f"Road records kept:     {kept:,}")
    print(f"Micro slivers removed: {removed:,}")
    print(f"Report: {REPORT}")
    print("=" * 84)


if __name__ == "__main__":
    main()
