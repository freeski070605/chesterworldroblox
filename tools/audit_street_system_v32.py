#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

BOOTSTRAP = PROJECT / "src" / "server" / "Bootstrap.server.lua"
CONFORMER = PROJECT / "src" / "server" / "World" / "RoadTerrainConformer.server.lua"
FINISH = PROJECT / "src" / "server" / "World" / "StreetFinishBuilder.server.lua"
DATA = PROJECT / "src" / "shared" / "StreetFinishData.lua"
REPORT = ROOT / "Data" / "18_StreetSystemV3" / "street_system_v3_report.json"

print("=" * 88)
print("CHESTERWORLD STREET SYSTEM V3.2 - FILE AUDIT")
print("=" * 88)

required = [BOOTSTRAP, CONFORMER, FINISH, DATA, REPORT]
for path in required:
    if not path.exists():
        raise SystemExit(f"Missing required file: {path}")

bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
conformer = CONFORMER.read_text(encoding="utf-8")
finish = FINISH.read_text(encoding="utf-8")
report = json.loads(REPORT.read_text(encoding="utf-8"))
stats = report.get("stats", {})

checks = {
    "bootstrap_false_signal":
        'CW_BootstrapComplete", false' in bootstrap,
    "bootstrap_true_signal":
        'CW_BootstrapComplete", true' in bootstrap,
    "conformer_waits_for_bootstrap":
        "CW_BootstrapComplete" in conformer,
    "conformer_sets_complete":
        'CW_RoadConformComplete", true' in conformer,
    "street_waits_for_conformer":
        "CW_RoadConformComplete" in finish,
    "square_junction_pads_disabled":
        "junctionPads=DISABLED" in finish,
}

for name, ok in checks.items():
    print(f"{name:34} {'PASS' if ok else 'FAIL'}")
    if not ok:
        raise SystemExit(f"V3.2 audit failed: {name}")

print()
print(f"Corrected source junctions: {int(stats.get('junctions', 0)):,}")
print(f"Source sidewalk segments:   {int(stats.get('sidewalk_segments', 0)):,}")

if int(stats.get("sidewalk_segments", 0)) > 30000:
    raise SystemExit("Sidewalk segment count exceeds 30,000 budget.")

print()
print("STREET SYSTEM V3.2 FILE AUDIT: PASS")
print("=" * 88)
