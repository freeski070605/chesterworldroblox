#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import package_roblox_street_v3_world as base

DEFAULT_SOURCE = Path(r"E:\ChesterWorld\Data\18_RegionalTiles_StreetV3")
DEFAULT_OUT = Path(__file__).resolve().parents[1] / "src" / "shared" / "WorldData" / "Tiles"

# County UPAS/St_PosTyp=Underpass describes Kerlin, the lower road. It does
# not identify the road above it. The HighwayReference crossing inventory
# independently identifies I-95 as upper; the shared source endpoints below
# identify the exact graph nodes. No vertical position is inferred here.
KERLIN_I95 = {
    "id": "KERLIN_I95",
    "tile_id": "tile_r07_c07",
    "vertical_status": "unmeasured",
    "upper_source_ids": (423, 424, 425, 426),
    "lower_source_ids": (2758, 27163, 20771, 20770),
    "nodes": (
        {"x": 7019.645007064566, "z": 7193.492147859186,
         "upper_ids": (424, 425), "lower_ids": (2758, 27163)},
        {"x": 7011.453849650919, "z": 7208.862662491389,
         "upper_ids": (423, 426), "lower_ids": (20771, 20770)},
    ),
}


def county_object_id(props: dict[str, Any], source: str) -> int | None:
    if source.lower() != "county":
        return None
    value = props.get("OBJECTID")
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def at_source_node(x: float, z: float, node: dict[str, Any]) -> bool:
    return abs(x - node["x"]) < 0.002 and abs(z - node["z"]) < 0.002


def validate_kerlin_source(tile: dict[str, Any]) -> None:
    """Fail closed if the source changes before applying the local override."""
    roads = (tile.get("layers") or {}).get("roads", []) or []
    expected = set(KERLIN_I95["upper_source_ids"] + KERLIN_I95["lower_source_ids"])
    found: dict[int, dict[str, Any]] = {}
    for record in roads:
        props = record.get("properties") or {}
        source = base.first_text(props, ("generator_source", "source")) or ""
        source_id = county_object_id(props, source)
        if source_id in expected:
            if source_id in found:
                raise ValueError(f"Duplicate Kerlin source OBJECTID {source_id}")
            found[source_id] = record
    if set(found) != expected:
        raise ValueError(f"Kerlin source IDs changed: expected {sorted(expected)}, found {sorted(found)}")

    for source_id in KERLIN_I95["upper_source_ids"]:
        if clean(found[source_id]["properties"].get("LSt_Name")).upper() != "I95":
            raise ValueError(f"Kerlin upper OBJECTID {source_id} is no longer I-95")
    for source_id in KERLIN_I95["lower_source_ids"]:
        if not clean(found[source_id]["properties"].get("LSt_Name")).upper().startswith("KERLIN"):
            raise ValueError(f"Kerlin lower OBJECTID {source_id} is no longer Kerlin Street")
    for source_id in (27163, 20771):
        props = found[source_id]["properties"]
        if clean(props.get("St_PosTyp")).lower() != "underpass" or clean(props.get("LSt_Type")).upper() != "UPAS":
            raise ValueError(f"Kerlin OBJECTID {source_id} no longer has county underpass semantics")

    for node in KERLIN_I95["nodes"]:
        for role in ("upper", "lower"):
            for source_id in node[f"{role}_ids"]:
                lines = base.geometry_lines(found[source_id].get("geometry") or {})
                endpoints = [point for line in lines if line for point in (line[0], line[-1])]
                if not any(at_source_node(float(p[0]), float(p[1]), node) for p in endpoints):
                    raise ValueError(f"Kerlin {role} OBJECTID {source_id} no longer meets the expected node")


def kerlin_connection_group(tile_id: str, source_id: int | None, x: float, z: float) -> str:
    if tile_id != KERLIN_I95["tile_id"] or source_id not in KERLIN_I95["lower_source_ids"]:
        return ""
    for node in KERLIN_I95["nodes"]:
        if source_id in node["lower_ids"] and at_source_node(x, z, node):
            return "KERLIN_I95:lower"
    return ""


def clean(value: Any) -> str:
    if value is None:
        return ""
    text = str(value).strip()
    return "" if text.lower() in {"", "none", "null", "nan"} else text


def truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return clean(value).lower() in {
        "1", "true", "yes", "y", "viaduct", "movable",
        "aqueduct", "building_passage", "culvert",
    }


def first_grade_number(props: dict[str, Any], source: str) -> int:
    value = base.first_number(props, ("osm_layer", "generator_layer"))
    if value is None and source.lower() == "osm":
        value = base.first_number(props, ("layer",))
    if value is None:
        return 0
    return max(-5, min(5, int(round(value))))


def stable_grade_group(
    props: dict[str, Any],
    source: str,
    road_name: str,
    road_class: str,
    layer: int,
    record_index: int,
    tile_id: str,
) -> str:
    source_id = base.first_text(
        props,
        (
            "generator_source_id",
            "OBJECTID",
            "objectid",
            "ObjectID",
            "FID",
            "fid",
            "osm_id",
            "osm_way_id",
            "@id",
            "id",
        ),
    )
    if source_id:
        return f"{source}:{source_id}:g{layer}"

    return f"{tile_id}:r{record_index}:{road_name}:{road_class}:g{layer}"


def convert_tile(tile: dict[str, Any]) -> dict[str, Any]:
    layers = tile.get("layers") or []
    if isinstance(layers, list):
        layers = {}

    tile_id = str(tile.get("tile_id", "unknown"))
    if tile_id == KERLIN_I95["tile_id"]:
        validate_kerlin_source(tile)
    roads_out: list[dict[str, Any]] = []

    for record_index, record in enumerate(layers.get("roads", []) or [], start=1):
        props = record.get("properties") or {}

        width_m = (
            base.first_number(
                props,
                ("generator_width_m", "generator_render_width_m", "width_m", "width"),
            )
            or 7.0
        )

        road_name = (
            base.first_text(
                props,
                ("generator_name", "name", "street", "road_name", "full_name"),
            )
            or "Road"
        )

        road_class = (
            base.first_text(
                props,
                ("generator_road_class", "road_class", "osm_highway", "highway"),
            )
            or "local"
        )

        source = base.first_text(props, ("generator_source", "source")) or ""
        source_id = county_object_id(props, source)

        # Prefer explicit upstream engineering/OSM tags. Never infer that a
        # road is elevated merely from its name ("I 95" etc.). A false "N"
        # from county data must NOT be interpreted as a bridge.
        bridge = truthy(base.first_text(
            props, ("osm_bridge", "generator_bridge", "is_bridge", "bridge")
        ))
        tunnel = truthy(base.first_text(
            props, ("osm_tunnel", "generator_tunnel", "is_tunnel", "tunnel")
        ))

        layer = first_grade_number(props, source)
        if bridge and layer <= 0:
            layer = 1
        elif tunnel and layer >= 0:
            layer = -1

        grade_group = stable_grade_group(
            props,
            source or "unknown",
            road_name,
            road_class,
            layer,
            record_index,
            tile_id,
        )

        for line in base.geometry_lines(record.get("geometry") or {}):
            for a, b in zip(line, line[1:]):
                if len(a) < 2 or len(b) < 2:
                    continue

                x1, z1 = float(a[0]), float(a[1])
                x2, z2 = float(b[0]), float(b[1])

                if ((x2 - x1) ** 2 + (z2 - z1) ** 2) ** 0.5 < 0.15:
                    continue

                road = {
                    "name": road_name,
                    "x1": x1,
                    "z1": z1,
                    "x2": x2,
                    "z2": z2,
                    "width_m": width_m,
                    "road_class": road_class,
                    "bridge": bridge,
                    "tunnel": tunnel,
                    "layer": layer,
                    "grade_group": grade_group,
                    "source": source,
                }
                if tile_id == KERLIN_I95["tile_id"]:
                    node1_group = kerlin_connection_group(tile_id, source_id, x1, z1)
                    node2_group = kerlin_connection_group(tile_id, source_id, x2, z2)
                    if node1_group:
                        road["node1_connection_group"] = node1_group
                    if node2_group:
                        road["node2_connection_group"] = node2_group
                    # The county calls the same continuous street "Kerlin"
                    # on its approaches and "Kerlin St" beneath I-95.
                    # Keep the source name for rendering; unify only the
                    # junction label so a two-arm bend does not become a pad.
                    if source_id in (27163, 20771):
                        road["junction_name"] = "Kerlin"
                roads_out.append(road)

    buildings_out: list[dict[str, Any]] = []
    for idx, record in enumerate(layers.get("buildings", []) or [], start=1):
        props = record.get("properties") or {}
        oriented = base.oriented_box(record.get("geometry") or {})
        if not oriented:
            continue

        x, z, width, depth, yaw = oriented
        bid = (
            base.first_text(
                props,
                ("building_id", "objectid", "OBJECTID", "id", "osm_id"),
            )
            or f"building_{idx}"
        )
        name = (
            base.first_text(props, ("name", "address", "street_address"))
            or str(bid)
        )

        buildings_out.append(
            {
                "id": str(bid),
                "name": name,
                "x_m": x,
                "z_m": z,
                "width_m": width,
                "depth_m": depth,
                "yaw_deg": yaw,
                "height_m": base.building_height(props),
            }
        )

    return {
        "tile_id": tile_id,
        "roads": roads_out,
        "buildings": buildings_out,
        "grade_separations": [KERLIN_I95] if tile_id == KERLIN_I95["tile_id"] else [],
    }


def lua_bool(value: bool) -> str:
    return "true" if value else "false"


def write_lua(path: Path, data: dict[str, Any]) -> None:
    lines = [
        "return {",
        f"    tile_id = {base.lua_string(data['tile_id'])},",
        "    roads = {",
    ]

    for road in data["roads"]:
        optional = ""
        for key in ("node1_connection_group", "node2_connection_group", "junction_name"):
            if key in road:
                optional += f",{key}={base.lua_string(road[key])}"
        lines.append(
            "        {"
            f"name={base.lua_string(road['name'])},"
            f"x1={base.fmt(road['x1'])},z1={base.fmt(road['z1'])},"
            f"x2={base.fmt(road['x2'])},z2={base.fmt(road['z2'])},"
            f"width_m={base.fmt(road['width_m'])},"
            f"road_class={base.lua_string(road['road_class'])},"
            f"bridge={lua_bool(road['bridge'])},"
            f"tunnel={lua_bool(road['tunnel'])},"
            f"layer={int(road['layer'])},"
            f"grade_group={base.lua_string(road['grade_group'])},"
            f"source={base.lua_string(road['source'])}{optional}"
            "},"
        )

    lines.append("    },")
    if data["grade_separations"]:
        lines.append("    grade_separations = {")
        for crossing in data["grade_separations"]:
            upper = ",".join(base.lua_string(f"county:{i}") for i in crossing["upper_source_ids"])
            lower = ",".join(base.lua_string(f"county:{i}") for i in crossing["lower_source_ids"])
            lines.append(
                "        {"
                f"id={base.lua_string(crossing['id'])},"
                f"upper_source_ids={{{upper}}},lower_source_ids={{{lower}}},"
                f"vertical_status={base.lua_string(crossing['vertical_status'])}"
                "},"
            )
        lines.append("    },")
    lines.append("    buildings = {")

    for building in data["buildings"]:
        lines.append(
            "        {"
            f"id={base.lua_string(building['id'])},"
            f"name={base.lua_string(building['name'])},"
            f"x_m={base.fmt(building['x_m'])},z_m={base.fmt(building['z_m'])},"
            f"width_m={base.fmt(building['width_m'])},"
            f"depth_m={base.fmt(building['depth_m'])},"
            f"yaw_deg={base.fmt(building['yaw_deg'])},"
            f"height_m={base.fmt(building['height_m'])}"
            "},"
        )

    lines.extend(["    },", "}", ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--find", action="append", default=[])
    parser.add_argument("--match", action="append", default=[])
    parser.add_argument("--tile", action="append", default=[])
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--max-tiles", type=int, default=8)
    args = parser.parse_args()

    discovered = list(base.discover_tiles(args.source))
    print(f"Active ChesterWorld tiles discovered: {len(discovered)}")

    if args.find:
        hits = []
        for entry, path in discovered:
            tile = base.load_json(path)
            if base.tile_matches(tile, args.find):
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
            tile = base.load_json(path)
            if base.tile_matches(tile, args.match):
                selected.append((entry, path))

    if not selected:
        raise SystemExit(
            "No tiles selected.\n"
            "Use --all, --tile, --match, or --find."
        )

    if not args.all and len(selected) > args.max_tiles:
        print(
            f"Matched {len(selected)} tiles; limiting to {args.max_tiles}. "
            "Use --max-tiles to change this."
        )
        selected = selected[: args.max_tiles]

    args.out.mkdir(parents=True, exist_ok=True)

    if args.all:
        for path in args.out.iterdir():
            if path.is_file() and path.suffix.lower() in {".lua", ".luau"}:
                path.unlink()

    total_roads = 0
    total_buildings = 0
    bridge_segments = 0
    tunnel_segments = 0
    layered_segments = 0

    for entry, path in selected:
        tile = base.load_json(path)
        converted = convert_tile(tile)
        tile_id = converted["tile_id"]
        module_name = base.safe_module_name(tile_id)
        output = args.out / f"{module_name}.lua"
        write_lua(output, converted)

        total_roads += len(converted["roads"])
        total_buildings += len(converted["buildings"])
        bridge_segments += sum(1 for r in converted["roads"] if r["bridge"])
        tunnel_segments += sum(1 for r in converted["roads"] if r["tunnel"])
        layered_segments += sum(1 for r in converted["roads"] if r["layer"] != 0)

        print(
            f"Wrote {output.name}: "
            f"{len(converted['buildings'])} buildings, "
            f"{len(converted['roads'])} road segments"
        )

    lua_modules = [
        path
        for path in args.out.iterdir()
        if path.is_file() and path.suffix.lower() in {".lua", ".luau"}
    ]

    if args.all and len(selected) == 102 and len(lua_modules) != 102:
        raise SystemExit(
            f"Expected exactly 102 Lua tile modules after full export; "
            f"found {len(lua_modules)}."
        )

    print()
    print("CHESTERWORLD -> ROBLOX GRADE-AWARE EXPORT COMPLETE")
    print(f"Tiles:       {len(selected)}")
    print(f"Lua modules: {len(lua_modules)}")
    print(f"Buildings:   {total_buildings}")
    print(f"Road segs:   {total_roads}")
    print(f"Bridge segs: {bridge_segments}")
    print(f"Tunnel segs: {tunnel_segments}")
    print(f"Layered segs:{layered_segments}")
    print(f"Output:      {args.out}")


if __name__ == "__main__":
    main()
