# ============================================================
# REGIONAL EXPORTER — generated from the current working
# package_roblox_world.py. The original exporter is untouched.
# Input: E:\ChesterWorld\Data\18_RegionalTiles_StreetV3
# Street names: generator_name is preferred when the current
# exporter exposes the known road-name property tuple.
# ============================================================

#!/usr/bin/env python3
r"""
ChesterWorld -> Roblox first-pass tile exporter.

Reads the EXISTING ChesterWorld Unity tile package:
    E:\ChesterWorld\Data\18_RegionalTiles_StreetV3

and converts selected tile JSON into compact Luau ModuleScripts for Rojo.

This first pass intentionally generates:
  - road segments
  - oriented building greybox masses

The purpose is coordinate/scale validation in Roblox before swapping in the
finished Chester meshes and detailed terrain.

Examples:

  # Find tiles whose properties mention Kerlin:
  py tools\package_roblox_world.py --find Kerlin

  # Export every tile matching Kerlin:
  py tools\package_roblox_world.py --match Kerlin

  # Narrow the search further:
  py tools\package_roblox_world.py --match Kerlin --match 12th

  # Export exact tiles after --find:
  py tools\package_roblox_world.py --tile T_r03_c04 --tile T_r03_c05

  # Export all tiles (later, not recommended for first proof):
  py tools\package_roblox_world.py --all
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any, Iterable

try:
    from shapely.geometry import shape
except ImportError as exc:
    raise SystemExit(
        "Missing shapely. Install with:\n"
        "  py -m pip install shapely\n"
    ) from exc


DEFAULT_SOURCE = Path(r"E:\ChesterWorld\Data\18_RegionalTiles_StreetV3")
DEFAULT_OUT = Path(__file__).resolve().parents[1] / "src" / "shared" / "WorldData" / "Tiles"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def safe_module_name(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9_]+", "_", value)
    if value and value[0].isdigit():
        value = "_" + value
    return value or "Tile"


def prop_text(properties: dict[str, Any]) -> str:
    parts: list[str] = []
    for key, value in (properties or {}).items():
        parts.append(str(key))
        if isinstance(value, (str, int, float, bool)):
            parts.append(str(value))
    return " ".join(parts).lower()


def tile_matches(tile: dict[str, Any], terms: list[str]) -> bool:
    if not terms:
        return True

    haystacks: list[str] = []
    for layer_name, records in (tile.get("layers") or {}).items():
        haystacks.append(str(layer_name).lower())
        for record in records or []:
            haystacks.append(prop_text(record.get("properties") or {}))

    combined = "\n".join(haystacks)
    return all(term.lower() in combined for term in terms)


def first_number(props: dict[str, Any], keys: Iterable[str]) -> float | None:
    lower = {str(k).lower(): v for k, v in (props or {}).items()}
    for key in keys:
        value = lower.get(key.lower())
        if value in (None, ""):
            continue
        try:
            return float(value)
        except (TypeError, ValueError):
            pass
    return None


def first_text(props: dict[str, Any], keys: Iterable[str]) -> str | None:
    lower = {str(k).lower(): v for k, v in (props or {}).items()}
    for key in keys:
        value = lower.get(key.lower())
        if value not in (None, ""):
            return str(value)
    return None


def building_height(props: dict[str, Any]) -> float:
    height = first_number(
        props,
        (
            "height_m",
            "generator_height_m",
            "building_height_m",
            "height",
        ),
    )
    if height and 2.0 <= height <= 250.0:
        return height

    floors = first_number(
        props,
        (
            "estimated_floors",
            "floors",
            "stories",
            "levels",
            "building_levels",
        ),
    )
    if floors and floors > 0:
        return max(3.05 * floors, 3.05)

    return 9.15


def geometry_lines(geometry: dict[str, Any]) -> list[list[list[float]]]:
    kind = (geometry or {}).get("type")
    coords = (geometry or {}).get("coordinates") or []
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return coords
    return []


def oriented_box(geometry: dict[str, Any]):
    geom = shape(geometry)
    if geom.is_empty:
        return None

    # Use largest polygon if clipping produced a collection/multipolygon.
    if geom.geom_type == "MultiPolygon":
        geom = max(geom.geoms, key=lambda g: g.area)
    elif geom.geom_type == "GeometryCollection":
        polys = [g for g in geom.geoms if g.geom_type == "Polygon"]
        if not polys:
            return None
        geom = max(polys, key=lambda g: g.area)

    if geom.geom_type != "Polygon" or geom.area <= 0:
        return None

    rect = geom.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:4]
    if len(coords) < 4:
        return None

    edges = []
    for i in range(4):
        x1, z1 = coords[i]
        x2, z2 = coords[(i + 1) % 4]
        dx, dz = x2 - x1, z2 - z1
        edges.append((math.hypot(dx, dz), dx, dz))

    long_edge = max(edges, key=lambda e: e[0])
    short_edge = min(edges, key=lambda e: e[0])

    width = max(long_edge[0], 0.2)
    depth = max(short_edge[0], 0.2)
    yaw = math.degrees(math.atan2(long_edge[2], long_edge[1]))
    c = rect.centroid

    return float(c.x), float(c.y), width, depth, yaw


def lua_string(value: Any) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def fmt(value: float) -> str:
    if abs(value) < 0.0005:
        value = 0.0
    return f"{value:.3f}".rstrip("0").rstrip(".")


def convert_tile(tile: dict[str, Any]) -> dict[str, Any]:
    layers = tile.get("layers") or {}

    roads_out: list[dict[str, Any]] = []
    for record in layers.get("roads", []) or []:
        props = record.get("properties") or {}
        width_m = first_number(props, ("generator_width_m", "width_m", "width")) or 7.0
        road_name = first_text(props, ("generator_name", "name", "street", "road_name", "full_name")) or "Road"

        for line in geometry_lines(record.get("geometry") or {}):
            for a, b in zip(line, line[1:]):
                if len(a) < 2 or len(b) < 2:
                    continue
                x1, z1 = float(a[0]), float(a[1])
                x2, z2 = float(b[0]), float(b[1])
                if math.hypot(x2 - x1, z2 - z1) < 0.15:
                    continue
                roads_out.append(
                    {
                        "name": road_name,
                        "x1": x1,
                        "z1": z1,
                        "x2": x2,
                        "z2": z2,
                        "width_m": width_m,
                    }
                )

    buildings_out: list[dict[str, Any]] = []
    for idx, record in enumerate(layers.get("buildings", []) or [], start=1):
        props = record.get("properties") or {}
        box = oriented_box(record.get("geometry") or {})
        if not box:
            continue

        x, z, width, depth, yaw = box
        bid = first_text(
            props,
            ("building_id", "objectid", "OBJECTID", "id", "osm_id"),
        ) or f"building_{idx}"

        name = first_text(
            props,
            ("name", "address", "street_address"),
        ) or str(bid)

        buildings_out.append(
            {
                "id": str(bid),
                "name": name,
                "x_m": x,
                "z_m": z,
                "width_m": width,
                "depth_m": depth,
                "yaw_deg": yaw,
                "height_m": building_height(props),
            }
        )

    return {
        "tile_id": tile.get("tile_id", "unknown"),
        "roads": roads_out,
        "buildings": buildings_out,
    }


def write_lua(path: Path, data: dict[str, Any]) -> None:
    lines = ["return {", f"    tile_id = {lua_string(data['tile_id'])},", "    roads = {"]

    for r in data["roads"]:
        lines.append(
            "        {"
            f"name={lua_string(r['name'])},"
            f"x1={fmt(r['x1'])},z1={fmt(r['z1'])},"
            f"x2={fmt(r['x2'])},z2={fmt(r['z2'])},"
            f"width_m={fmt(r['width_m'])}"
            "},"
        )

    lines.extend(["    },", "    buildings = {"])

    for b in data["buildings"]:
        lines.append(
            "        {"
            f"id={lua_string(b['id'])},"
            f"name={lua_string(b['name'])},"
            f"x_m={fmt(b['x_m'])},z_m={fmt(b['z_m'])},"
            f"width_m={fmt(b['width_m'])},depth_m={fmt(b['depth_m'])},"
            f"yaw_deg={fmt(b['yaw_deg'])},height_m={fmt(b['height_m'])}"
            "},"
        )

    lines.extend(["    },", "}", ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def discover_tiles(source: Path):
    manifest_path = source / "chester_world_manifest.json"
    if not manifest_path.exists():
        raise SystemExit(f"Manifest not found: {manifest_path}")

    manifest = load_json(manifest_path)
    for entry in manifest.get("tiles", []):
        rel = entry.get("file")
        if not rel:
            continue
        path = source / Path(rel)
        if path.exists():
            yield entry, path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--find", action="append", default=[], help="List matching tiles only.")
    parser.add_argument("--match", action="append", default=[], help="Export tiles containing ALL terms.")
    parser.add_argument("--tile", action="append", default=[], help="Exact tile_id to export.")
    parser.add_argument("--all", action="store_true", help="Export every active tile.")
    parser.add_argument("--max-tiles", type=int, default=8)
    args = parser.parse_args()

    discovered = list(discover_tiles(args.source))
    print(f"Active ChesterWorld tiles discovered: {len(discovered)}")

    if args.find:
        hits = []
        for entry, path in discovered:
            tile = load_json(path)
            if tile_matches(tile, args.find):
                hits.append(entry)
        print(f"Tiles matching {args.find}: {len(hits)}")
        for entry in hits:
            counts = entry.get("feature_counts") or {}
            print(
                f"  {entry.get('tile_id')} | "
                f"buildings={counts.get('buildings', 0)} "
                f"roads={counts.get('roads', 0)} "
                f"file={entry.get('file')}"
            )
        return

    exact = set(args.tile)
    selected = []

    for entry, path in discovered:
        tile_id = str(entry.get("tile_id", ""))

        if exact:
            if tile_id in exact:
                selected.append((entry, path))
            continue

        if args.all:
            selected.append((entry, path))
            continue

        if args.match:
            tile = load_json(path)
            if tile_matches(tile, args.match):
                selected.append((entry, path))

    if not selected:
        raise SystemExit(
            "No tiles selected.\n"
            "Start with:\n"
            "  py tools\\package_roblox_world.py --find Kerlin\n"
        )

    if not args.all and len(selected) > args.max_tiles:
        print(
            f"Matched {len(selected)} tiles; limiting first pass to "
            f"{args.max_tiles}. Use --max-tiles to change this."
        )
        selected = selected[: args.max_tiles]

    args.out.mkdir(parents=True, exist_ok=True)

    total_roads = 0
    total_buildings = 0

    for entry, path in selected:
        tile = load_json(path)
        converted = convert_tile(tile)
        tile_id = converted["tile_id"]
        module_name = safe_module_name(tile_id)
        output = args.out / f"{module_name}.lua"
        write_lua(output, converted)

        total_roads += len(converted["roads"])
        total_buildings += len(converted["buildings"])

        print(
            f"Wrote {output.name}: "
            f"{len(converted['buildings'])} buildings, "
            f"{len(converted['roads'])} road segments"
        )

    print()
    print("CHESTERWORLD -> ROBLOX EXPORT COMPLETE")
    print(f"Tiles:      {len(selected)}")
    print(f"Buildings:  {total_buildings}")
    print(f"Road segs:  {total_roads}")
    print(f"Output:     {args.out}")


if __name__ == "__main__":
    main()
