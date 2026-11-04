#!/usr/bin/env python3
"""Validate the source-linked Kerlin/I-95 graph split without claiming 3-D clearance."""
from __future__ import annotations

import math
import re
import tempfile
from collections import defaultdict
from pathlib import Path

import package_roblox_street_v3_world as base
import package_roblox_street_v4_world as exporter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = exporter.DEFAULT_SOURCE / "Tiles" / "tile_r07_c07.json"
OUTPUT = exporter.DEFAULT_OUT / "tile_r07_c07.lua"


def lua_number(path: Path, name: str) -> float:
    match = re.search(rf"\b{name}\s*=\s*([\d.]+)", path.read_text(encoding="utf-8"))
    assert match, f"Missing {name} in {path}"
    return float(match.group(1))


def main() -> None:
    tile = exporter.convert_tile(base.load_json(SOURCE))
    roads = tile["roads"]
    assert len(tile["grade_separations"]) == 1
    assert tile["grade_separations"][0]["id"] == "KERLIN_I95"
    assert tile["grade_separations"][0]["vertical_status"] == "unmeasured"

    with tempfile.TemporaryDirectory() as folder:
        generated = Path(folder) / OUTPUT.name
        exporter.write_lua(generated, tile)
        assert generated.read_bytes() == OUTPUT.read_bytes(), "Working tile differs from source export"

    placement = ROOT / "src" / "shared" / "WorldPlacement.lua"
    config = ROOT / "src" / "shared" / "WorldConfig.lua"
    scale = lua_number(placement, "STUDS_PER_METER")
    center_x = lua_number(placement, "CENTER_X_M")
    center_z = lua_number(placement, "CENTER_Z_M")
    q = lua_number(config, "INTERSECTION_ENDPOINT_QUANTIZE_STUDS")

    def key(x: float, z: float, group: str = "") -> tuple[int, int, str]:
        return (math.floor((x - center_x) * scale / q + 0.5),
                math.floor(-(z - center_z) * scale / q + 0.5), group)

    nodes: dict[tuple[int, int, str], set[str]] = defaultdict(set)
    names: dict[tuple[int, int, str], set[str]] = defaultdict(set)
    for road in roads:
        for endpoint in (1, 2):
            node = key(road[f"x{endpoint}"], road[f"z{endpoint}"],
                       road.get(f"node{endpoint}_connection_group", ""))
            nodes[node].add(road["grade_group"])
            names[node].add(road.get("junction_name", road["name"]))

    expected = (
        (7019.645, 7193.492, {"county:424:g0", "county:425:g0"},
         {"county:2758:g0", "county:27163:g0"}),
        (7011.454, 7208.863, {"county:423:g0", "county:426:g0"},
         {"county:20771:g0", "county:20770:g0"}),
    )
    for x, z, upper, lower in expected:
        assert nodes[key(x, z)] == upper, f"I-95 continuity lost at {(x, z)}"
        assert nodes[key(x, z, "KERLIN_I95:lower")] == lower, f"Kerlin continuity lost at {(x, z)}"
        assert names[key(x, z)] == {"I 95"}
        assert names[key(x, z, "KERLIN_I95:lower")] == {"Kerlin"}

    # The nearby 12th/Kerlin junction remains connected on the ordinary key.
    assert nodes[key(7058.997, 7121.307)] == {
        "county:3389:g0", "county:24221:g0", "county:24732:g0", "county:2758:g0"
    }
    assert names[key(7058.997, 7121.307)] == {"12th", "Kerlin"}
    assert sum(bool(r.get("node1_connection_group")) + bool(r.get("node2_connection_group"))
               for r in roads) == 4
    for road in roads:
        if road["grade_group"] in {
            "county:423:g0", "county:424:g0", "county:425:g0", "county:426:g0",
            "county:2758:g0", "county:27163:g0", "county:20771:g0", "county:20770:g0",
        }:
            assert road["layer"] == 0 and not road["bridge"] and not road["tunnel"]
    print("PASS: two split graph nodes, Kerlin/I-95 continuity, nearby 12th junction, no vertical claims")


if __name__ == "__main__":
    main()
