#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")
REPORT = ROOT / "Data" / "20_StreetSurfaceV5" / "street_surface_v5_report.json"
LUA_DIR = PROJECT / "src" / "shared" / "StreetSurfaceTiles"
RUNTIME = PROJECT / "src" / "server" / "World" / "StreetSurfaceMeshBuilder.server.lua"
OLD_V4 = PROJECT / "src" / "server" / "World" / "StreetSurfaceBuilder.server.lua"

print("=" * 92)
print("CHESTERWORLD STREET SURFACE V5 - FILE AUDIT")
print("=" * 92)
for path in (REPORT, LUA_DIR, RUNTIME):
    if not path.exists():
        raise SystemExit(f"Missing V5 file: {path}")

report = json.loads(REPORT.read_text(encoding="utf-8"))
modules = sorted(LUA_DIR.glob("*.lua"))

print(f"Source tile JSON:          {int(report['tile_json_count']):,}")
print(f"Surface tile modules:      {len(modules):,}")
print(f"Total vertices:            {int(report['total_vertices']):,}")
print(f"Total triangles:           {int(report['total_triangles']):,}")
print(f"Max vertices / tile:       {int(report['max_vertices_per_tile']):,}")
print(f"Max triangles / tile:      {int(report['max_triangles_per_tile']):,}")
print(f"Bridge/tunnel skipped:     {int(report['bridge_tunnel_records_skipped']):,}")
print(f"Old V4 runtime present:    {'YES' if OLD_V4.exists() else 'NO'}")

if len(modules) != int(report["surface_tile_modules"]):
    raise SystemExit("V5 module count does not match report.")
if int(report["max_vertices_per_tile"]) > 50000:
    raise SystemExit("V5 exceeds per-tile EditableMesh vertex safety budget.")
if int(report["total_triangles"]) > 250000:
    raise SystemExit("V5 exceeds total triangle safety budget.")

runtime = RUNTIME.read_text(encoding="utf-8")
for token in ("CreateEditableMesh", "CreateMeshPartAsync", "CW_RoadConformComplete", "StreetSurfaceV5"):
    if token not in runtime:
        raise SystemExit(f"V5 runtime missing required token: {token}")

print()
print("STREET SURFACE V5 FILE AUDIT: PASS")
print("=" * 92)
