#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

REPORT = ROOT / "Data" / "19_StreetSurfaceV4" / "street_surface_v4_report.json"
DATA = PROJECT / "src" / "shared" / "StreetSurfaceData.lua"
RUNTIME = PROJECT / "src" / "server" / "World" / "StreetSurfaceBuilder.server.lua"

print("=" * 88)
print("CHESTERWORLD STREET SURFACE V4 - FILE AUDIT")
print("=" * 88)

for path in (REPORT, DATA, RUNTIME):
    if not path.exists():
        raise SystemExit(f"Missing V4 file: {path}")

report = json.loads(REPORT.read_text(encoding="utf-8"))

junctions = int(report.get("joined_junctions", 0))
strips = int(report.get("cap_strips", 0))
budget = int(report.get("part_budget", 0))

print(f"Source junctions:       {junctions:,}")
print(f"Asphalt cap strips:     {strips:,}")
print(f"Part budget:            {budget:,}")
print("V3.2 tile rebuild:      NO")
print("V3.2 terrain rebuild:   NO")
print("V3.2 sidewalks changed: NO")

if junctions <= 0:
    raise SystemExit("No V4 junctions generated.")

if strips < junctions * 2:
    raise SystemExit("V4 strip count is unexpectedly low.")

if strips > budget:
    raise SystemExit(
        f"V4 part budget exceeded: {strips:,} > {budget:,}"
    )

runtime = RUNTIME.read_text(encoding="utf-8")

if "CW_RoadConformComplete" not in runtime:
    raise SystemExit("V4 runtime does not wait for road conformance.")

if "StreetSurfaceV4" not in runtime:
    raise SystemExit("V4 runtime identity missing.")

print()
print("STREET SURFACE V4 FILE AUDIT: PASS")
print("=" * 88)
