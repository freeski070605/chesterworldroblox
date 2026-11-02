#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

SOURCE_REPORT = (
    ROOT / "Data" / "18_StreetSystemV3"
    / "street_system_v3_report.json"
)
TILE_ROOT = ROOT / "Data" / "18_RegionalTiles_StreetV3"
TILES = TILE_ROOT / "Tiles"
LUA_TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
LUA_DATA = PROJECT / "src" / "shared" / "StreetFinishData.lua"

print("=" * 88)
print("CHESTERWORLD STREET SYSTEM V3 — FINAL FILE AUDIT")
print("=" * 88)

if not SOURCE_REPORT.exists():
    raise SystemExit(f"Missing source report: {SOURCE_REPORT}")

report = json.loads(SOURCE_REPORT.read_text(encoding="utf-8"))
stats = report["stats"]

json_tiles = sorted(TILES.glob("*.json"))
lua_tiles = sorted(
    p for p in LUA_TILES.iterdir()
    if p.is_file() and p.suffix.lower() in {".lua", ".luau"}
) if LUA_TILES.exists() else []

print(f"Motor source road features:    {stats['motor_features']:,}")
print(f"Non-motor separated:           {stats['nonmotor_features']:,}")
print(
    "OSM building conflicts dropped: "
    f"{stats['dropped_osm_building_conflicts']:,}"
)
print(f"Source sidewalk segments:      {stats['sidewalk_segments']:,}")
print(f"Source junctions:               {stats['junctions']:,}")
print(f"Regional JSON tiles:           {len(json_tiles):,}")
print(f"Roblox Lua tile modules:       {len(lua_tiles):,}")
print(f"StreetFinishData.lua:          {'YES' if LUA_DATA.exists() else 'NO'}")

if len(json_tiles) != 102:
    raise SystemExit(
        f"Expected 102 regional JSON tiles, found {len(json_tiles)}"
    )

if len(lua_tiles) != 102:
    raise SystemExit(
        f"Expected 102 Roblox Lua tile modules, found {len(lua_tiles)}"
    )

if not LUA_DATA.exists():
    raise SystemExit("StreetFinishData.lua was not generated.")

print()
print("STREET SYSTEM V3 FILE AUDIT: PASS")
print("=" * 88)
