#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

SOURCE_REPORT = (
    ROOT / "Data" / "18_StreetSystemV3"
    / "street_system_v3_report.json"
)
TILE_DIR = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
STREET_DATA = PROJECT / "src" / "shared" / "StreetFinishData.lua"

print("=" * 88)
print("CHESTERWORLD STREET SYSTEM V3.1 - FINAL AUDIT")
print("=" * 88)

if not SOURCE_REPORT.exists():
    raise SystemExit(f"Missing source report: {SOURCE_REPORT}")

report = json.loads(SOURCE_REPORT.read_text(encoding="utf-8"))
stats = report.get("stats", {})

modules = sorted(
    p for p in TILE_DIR.iterdir()
    if p.is_file() and p.suffix.lower() in {".lua", ".luau"}
) if TILE_DIR.exists() else []

print(f"Roblox Lua tile modules:       {len(modules):,}")
print(f"Motor source road features:    {int(stats.get('motor_features', 0)):,}")
print(f"Non-motor separated:           {int(stats.get('nonmotor_features', 0)):,}")
print(
    "OSM building conflicts dropped: "
    f"{int(stats.get('dropped_osm_building_conflicts', 0)):,}"
)
print(f"Source sidewalk segments:      {int(stats.get('sidewalk_segments', 0)):,}")
print(f"Source junctions:               {int(stats.get('junctions', 0)):,}")
print(f"StreetFinishData.lua:          {'YES' if STREET_DATA.exists() else 'NO'}")

if len(modules) != 102:
    extras = [p.name for p in modules]
    print()
    print("Lua module names:")
    for name in extras[:120]:
        print(f"  {name}")
    raise SystemExit(
        f"Expected exactly 102 Lua tile modules; found {len(modules)}."
    )

if not STREET_DATA.exists():
    raise SystemExit("StreetFinishData.lua missing.")

sidewalks = int(stats.get("sidewalk_segments", 0))
if sidewalks > 30000:
    raise SystemExit(
        f"Sidewalk part budget still too high: {sidewalks:,}. "
        "V3.1 target is <= 30,000."
    )

print()
print("TILE MODULE COUNT: PASS (102)")
print("SIDEWALK PART BUDGET: PASS")
print("STREET SYSTEM V3.1 FINAL AUDIT: PASS")
print("=" * 88)
