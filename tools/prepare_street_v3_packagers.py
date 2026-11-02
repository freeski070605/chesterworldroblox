#!/usr/bin/env python3
from __future__ import annotations

import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")

SOURCE_PACKAGER = PROJECT / "tools" / "package_regional_world_tiles_realworld.py"
NEW_PACKAGER = PROJECT / "tools" / "package_regional_world_tiles_street_v3.py"

SOURCE_EXPORTER = PROJECT / "tools" / "package_roblox_realworld_world.py"
NEW_EXPORTER = PROJECT / "tools" / "package_roblox_street_v3_world.py"

ACTIVE_LUA = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
BACKUPS = PROJECT / "tools" / "backups" / "street_system_v3"


def replace_required(text, old, new, label):
    if old not in text:
        raise RuntimeError(
            f"Could not find {label}: {old}"
        )
    return text.replace(old, new)


def main():
    print("=" * 88)
    print("CHESTERWORLD STREET SYSTEM V3 — PREPARE PACKAGERS")
    print("=" * 88)

    if not SOURCE_PACKAGER.exists():
        raise SystemExit(
            f"Missing Pass 2 regional packager: {SOURCE_PACKAGER}"
        )

    if not SOURCE_EXPORTER.exists():
        raise SystemExit(
            f"Missing Pass 3 Roblox exporter: {SOURCE_EXPORTER}"
        )

    pack = SOURCE_PACKAGER.read_text(encoding="utf-8")

    pack = replace_required(
        pack,
        "17_RealWorldCleanup",
        "18_StreetSystemV3",
        "road source folder",
    )
    pack = replace_required(
        pack,
        "regional_generator_roads_render_v2.geojson",
        "regional_motor_roads_v3.geojson",
        "road source filename",
    )
    pack = replace_required(
        pack,
        "17_RegionalTiles_RealWorld",
        "18_RegionalTiles_StreetV3",
        "tile output folder",
    )

    NEW_PACKAGER.write_text(pack, encoding="utf-8")

    export = SOURCE_EXPORTER.read_text(encoding="utf-8")
    export = replace_required(
        export,
        "17_RegionalTiles_RealWorld",
        "18_RegionalTiles_StreetV3",
        "Roblox exporter input",
    )

    NEW_EXPORTER.write_text(export, encoding="utf-8")

    BACKUPS.mkdir(parents=True, exist_ok=True)

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    if ACTIVE_LUA.exists():
        backup = BACKUPS / f"Tiles_before_street_v3_{stamp}"
        shutil.copytree(ACTIVE_LUA, backup)
        print(f"Backed up active Lua tiles -> {backup}")

    print(f"Prepared tile packager: {NEW_PACKAGER}")
    print(f"Prepared Roblox exporter: {NEW_EXPORTER}")
    print("=" * 88)


if __name__ == "__main__":
    main()
