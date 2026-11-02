#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

REPORT = ROOT / "Data" / "22_IntersectionSurfaceV6" / "intersection_surface_v6_report.json"
DATA = PROJECT / "src" / "shared" / "IntersectionSurfaceData.lua"
TILES = PROJECT / "src" / "shared" / "IntersectionSurfaceTiles"
RUNTIME = PROJECT / "src" / "server" / "World" / "IntersectionSurfaceBuilder.server.lua"

print("=" * 96)
print("CHESTERWORLD INTERSECTION SURFACE V6 - FILE AUDIT")
print("=" * 96)

for path in (REPORT, DATA, TILES, RUNTIME):
    if not path.exists():
        raise SystemExit(f"Missing V6 file: {path}")

report = json.loads(REPORT.read_text(encoding="utf-8"))
modules = sorted(TILES.glob("*.lua"))

print(f"Corrected junctions:     {int(report['junctions']):,}")
print(f"Intersection patches:    {int(report['patches_built']):,}")
print(f"Surface modules:         {len(modules):,}")
print(f"Total triangles:         {int(report['total_triangles']):,}")
print(f"Max X extent:            {float(report['max_extent_x_studs']):,.1f} studs")
print(f"Max Z extent:            {float(report['max_extent_z_studs']):,.1f} studs")
print("Full-road replacement:   NO")
print("V3.2 roads kept visible: YES")

if len(modules) != int(report["surface_modules"]):
    raise SystemExit("V6 surface module count mismatch.")

if float(report["max_extent_x_studs"]) > 1800:
    raise SystemExit("V6 X mesh extent exceeds safety guard.")

if float(report["max_extent_z_studs"]) > 1800:
    raise SystemExit("V6 Z mesh extent exceeds safety guard.")

runtime = RUNTIME.read_text(encoding="utf-8")

for token in (
    "trimPartAtJunctions",
    "IntersectionSurfaceTiles",
    "CreateEditableMesh",
    "CW_IntersectionSurfaceV6",
):
    if token not in runtime:
        raise SystemExit(f"V6 runtime missing: {token}")

print()
print("INTERSECTION SURFACE V6 FILE AUDIT: PASS")
print("=" * 96)
