#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(r"E:\ChesterWorld")
PROJECT = Path(r"E:\code\chesterworld-roblox")

STAGED_ROOT = ROOT / "Data" / "17_RegionalTiles_RealWorld"
STAGED_MANIFEST = STAGED_ROOT / "chester_world_manifest.json"

ACTIVE_LUA = PROJECT / "src" / "shared" / "WorldData" / "Tiles"

SOURCE_EXPORTER = PROJECT / "tools" / "package_roblox_regional_world.py"
PATCHED_EXPORTER = PROJECT / "tools" / "package_roblox_realworld_world.py"

BACKUP_ROOT = PROJECT / "tools" / "backups" / "realworld_pass3"


def fail(message: str):
    raise SystemExit(message)


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def verify_staged():
    if not STAGED_MANIFEST.exists():
        fail(f"Missing staged manifest: {STAGED_MANIFEST}")

    manifest = load_json(STAGED_MANIFEST)
    tiles = manifest.get("tiles", [])

    if len(tiles) != 102:
        fail(f"Expected 102 staged tiles, found {len(tiles)}")

    buildings = sum(
        int((t.get("feature_counts") or {}).get("buildings", 0))
        for t in tiles
    )
    roads = sum(
        int((t.get("feature_counts") or {}).get("roads", 0))
        for t in tiles
    )

    print("Staged JSON verification:")
    print(f"  tiles:     {len(tiles):,}")
    print(f"  buildings: {buildings:,}")
    print(f"  roads:     {roads:,}")

    if buildings != 21757:
        fail(
            "Staged whole-building count is not 21,757. "
            "Do not promote this tile set."
        )

    if roads != 7209:
        print(
            "WARNING: expected 7,209 tiled road records from the last audit, "
            f"found {roads:,}."
        )

    return buildings, roads


def backup_current():
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = BACKUP_ROOT / f"Tiles_before_realworld_{stamp}"

    if ACTIVE_LUA.exists():
        shutil.copytree(ACTIVE_LUA, backup)
        print(f"Backed up current Lua tiles -> {backup}")
    else:
        print("No active Lua tile folder found to back up.")

    return backup


def prepare_exporter():
    if not SOURCE_EXPORTER.exists():
        fail(f"Missing regional Roblox exporter: {SOURCE_EXPORTER}")

    text = SOURCE_EXPORTER.read_text(encoding="utf-8")

    occurrences = text.count("16_RegionalTiles")
    if occurrences == 0:
        fail(
            "Could not find '16_RegionalTiles' in package_roblox_regional_world.py. "
            "Exporter structure has changed; active Lua tiles were not modified."
        )

    text = text.replace(
        "16_RegionalTiles",
        "17_RegionalTiles_RealWorld",
    )

    PATCHED_EXPORTER.write_text(text, encoding="utf-8")

    print(
        f"Prepared {PATCHED_EXPORTER.name} "
        f"({occurrences} regional input path replacement(s))."
    )


def main():
    print("=" * 88)
    print("CHESTERWORLD REAL-WORLD PASS 3 — PREPARE LUA PROMOTION")
    print("=" * 88)

    verify_staged()
    backup_current()
    prepare_exporter()

    print()
    print("PREP COMPLETE")
    print(f"Run exporter next: {PATCHED_EXPORTER}")
    print("=" * 88)


if __name__ == "__main__":
    main()
