#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

REPORT = (
    ROOT / "Data" / "20_StreetSurfaceV53"
    / "street_surface_v53_report.json"
)
MODULE_DIR = (
    PROJECT / "src" / "shared"
    / "StreetSurfaceTilesV53"
)
RUNTIME = (
    PROJECT / "src" / "server" / "World"
    / "StreetSurfaceMeshBuilder.server.lua"
)

print("=" * 96)
print("CHESTERWORLD STREET SURFACE V5.3 - FILE AUDIT")
print("=" * 96)

for path in (REPORT, MODULE_DIR, RUNTIME):
    if not path.exists():
        raise SystemExit(f"Missing V5.3 file: {path}")

report = json.loads(REPORT.read_text(encoding="utf-8"))
modules = sorted(MODULE_DIR.glob("*.lua"))

print(f"Surface modules:         {len(modules):,}")
print(f"Total vertices:          {int(report['total_vertices']):,}")
print(f"Total triangles:         {int(report['total_triangles']):,}")
print(f"Max X extent:            {float(report['max_extent_x_studs']):,.1f} studs")
print(f"Max Z extent:            {float(report['max_extent_z_studs']):,.1f} studs")
print(f"Roblox hard limit:       {float(report['engine_extent_limit_studs']):,.1f} studs")
print(f"V5.3 guard limit:        {float(report['guard_extent_limit_studs']):,.1f} studs")

if len(modules) != int(report["surface_modules"]):
    raise SystemExit("Module count does not match V5.3 report.")

if float(report["max_extent_x_studs"]) > 1800.0:
    raise SystemExit("V5.3 X extent safety check failed.")

if float(report["max_extent_z_studs"]) > 1800.0:
    raise SystemExit("V5.3 Z extent safety check failed.")

runtime = RUNTIME.read_text(encoding="utf-8")

for token in (
    "StreetSurfaceTilesV53",
    "CreateEditableMesh",
    "CreateMeshPartAsync",
    "junctionAdjustedY",
    "CW_StreetSurfaceV53",
):
    if token not in runtime:
        raise SystemExit(
            f"Runtime missing required V5.3 token: {token}"
        )

print()
print("STREET SURFACE V5.3 FILE AUDIT: PASS")
print("=" * 96)
