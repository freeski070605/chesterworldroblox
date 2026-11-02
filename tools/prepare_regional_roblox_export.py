#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")
TOOLS = PROJECT / "tools"

SOURCE_EXPORTER = TOOLS / "package_roblox_world.py"
REGIONAL_EXPORTER = TOOLS / "package_roblox_regional_world.py"

REGIONAL_TILES = Path(
    r"E:\ChesterWorld\Data\16_RegionalTiles"
)
REGIONAL_MANIFEST = (
    REGIONAL_TILES / "chester_world_manifest.json"
)

WORLD_PLACEMENT = (
    PROJECT / "src" / "shared" / "WorldPlacement.lua"
)

WORLD_TILES = (
    PROJECT / "src" / "shared" / "WorldData" / "Tiles"
)

STAGED_PLACEMENT = (
    PROJECT / "src" / "shared"
    / "WorldPlacement.regional.staged.lua"
)

BACKUP_ROOT = TOOLS / "backups" / (
    "regional_export_"
    + datetime.now().strftime("%Y%m%d_%H%M%S")
)

REGIONAL_CENTER_X_M = 6347.889
REGIONAL_CENTER_Z_M = 7201.973

LOCKED_AXES_NOTE = (
    "Roblox orientation remains locked: "
    "N=-Z, S=+Z, E=+X, W=-X"
)


def require(path: Path, label: str):
    if not path.exists():
        raise SystemExit(
            f"Missing {label}: {path}"
        )


def patch_regional_source(text: str) -> tuple[str, int]:
    replacements = 0

    # Most likely current exporter path.
    new_text, count = re.subn(
        r'(?i)16_UnityTiles',
        '16_RegionalTiles',
        text,
    )
    text = new_text
    replacements += count

    # Defensive support for scripts that refer to the directory with a
    # variable/string using lowercase or other separators is handled by the
    # case-insensitive replacement above.
    return text, replacements


def patch_generator_name_priority(
    text: str,
) -> tuple[str, int]:
    """
    Future exports must not regress repaired street names back to "Road".

    Patch common first-value/property-name tuples so generator_name wins.
    This is intentionally conservative: if no known pattern is found, the
    regional exporter is still created, but a warning is printed.
    """
    total = 0

    patterns = [
        (
            r'\(\s*"name"\s*,\s*"street"\s*,\s*'
            r'"road_name"\s*,\s*"full_name"\s*\)',
            '("generator_name", "name", "street", '
            '"road_name", "full_name")',
        ),
        (
            r'\[\s*"name"\s*,\s*"street"\s*,\s*'
            r'"road_name"\s*,\s*"full_name"\s*\]',
            '["generator_name", "name", "street", '
            '"road_name", "full_name"]',
        ),
        (
            r'\(\s*[\'"]name[\'"]\s*,\s*'
            r'[\'"]street[\'"]\s*,\s*'
            r'[\'"]road_name[\'"]\s*,\s*'
            r'[\'"]full_name[\'"]\s*\)',
            '("generator_name", "name", "street", '
            '"road_name", "full_name")',
        ),
    ]

    for pattern, replacement in patterns:
        text, count = re.subn(
            pattern,
            replacement,
            text,
        )
        total += count

    # If generator_name already exists, that is also acceptable.
    if total == 0 and "generator_name" in text:
        return text, -1

    return text, total


def make_staged_world_placement():
    current = WORLD_PLACEMENT.read_text(
        encoding="utf-8",
        errors="ignore",
    )

    text = current

    center_x_patterns = [
        (
            r'(CENTER_X_M\s*=\s*)'
            r'[-+]?\d+(?:\.\d+)?',
            rf'\g<1>{REGIONAL_CENTER_X_M:.3f}',
        ),
    ]
    center_z_patterns = [
        (
            r'(CENTER_Z_M\s*=\s*)'
            r'[-+]?\d+(?:\.\d+)?',
            rf'\g<1>{REGIONAL_CENTER_Z_M:.3f}',
        ),
    ]

    x_changed = 0
    z_changed = 0

    for pattern, replacement in center_x_patterns:
        text, count = re.subn(
            pattern,
            replacement,
            text,
        )
        x_changed += count

    for pattern, replacement in center_z_patterns:
        text, count = re.subn(
            pattern,
            replacement,
            text,
        )
        z_changed += count

    if x_changed == 0 or z_changed == 0:
        raise SystemExit(
            "Could not safely patch CENTER_X_M/CENTER_Z_M "
            f"in {WORLD_PLACEMENT}. "
            "The working file was NOT changed."
        )

    header = (
        "-- STAGED REGIONAL PLACEMENT — DO NOT RENAME INTO PLACE "
        "UNTIL REGIONAL TERRAIN IS IMPORTED.\n"
        "-- Existing Chester coordinates are preserved by the "
        "regional origin/center shift.\n"
        "-- " + LOCKED_AXES_NOTE + "\n\n"
    )

    STAGED_PLACEMENT.write_text(
        header + text,
        encoding="utf-8",
    )


def main():
    print("=" * 78)
    print("CHESTERWORLD REGIONAL ROBLOX EXPORT PREP")
    print("=" * 78)

    require(
        SOURCE_EXPORTER,
        "working Roblox exporter",
    )
    require(
        REGIONAL_MANIFEST,
        "regional world manifest",
    )
    require(
        WORLD_PLACEMENT,
        "working WorldPlacement.lua",
    )

    BACKUP_ROOT.mkdir(
        parents=True,
        exist_ok=True,
    )

    shutil.copy2(
        SOURCE_EXPORTER,
        BACKUP_ROOT / SOURCE_EXPORTER.name,
    )
    shutil.copy2(
        WORLD_PLACEMENT,
        BACKUP_ROOT / WORLD_PLACEMENT.name,
    )

    if WORLD_TILES.exists():
        tile_backup = BACKUP_ROOT / "WorldData_Tiles"
        shutil.copytree(
            WORLD_TILES,
            tile_backup,
            dirs_exist_ok=True,
        )
        print(
            f"Backed up current Roblox Lua tiles: "
            f"{tile_backup}"
        )

    source = SOURCE_EXPORTER.read_text(
        encoding="utf-8",
        errors="ignore",
    )

    regional, source_replacements = (
        patch_regional_source(source)
    )

    if source_replacements == 0:
        raise SystemExit(
            "Could not find '16_UnityTiles' in the current "
            "package_roblox_world.py, so no unsafe guess was made. "
            f"Backup is at {BACKUP_ROOT}"
        )

    regional, name_patch_count = (
        patch_generator_name_priority(
            regional
        )
    )

    banner = (
        "# ============================================================\n"
        "# REGIONAL EXPORTER — generated from the current working\n"
        "# package_roblox_world.py. The original exporter is untouched.\n"
        "# Input: E:\\ChesterWorld\\Data\\16_RegionalTiles\n"
        "# Street names: generator_name is preferred when the current\n"
        "# exporter exposes the known road-name property tuple.\n"
        "# ============================================================\n\n"
    )

    REGIONAL_EXPORTER.write_text(
        banner + regional,
        encoding="utf-8",
    )

    make_staged_world_placement()

    print(f"Backup: {BACKUP_ROOT}")
    print(
        "Regional exporter source path replacements: "
        f"{source_replacements}"
    )

    if name_patch_count == -1:
        print(
            "Street-name protection: exporter already references "
            "generator_name"
        )
    elif name_patch_count > 0:
        print(
            "Street-name protection patches: "
            f"{name_patch_count}"
        )
    else:
        print(
            "WARNING: known road-name tuple was not found. "
            "No name logic was guessed. Check the regional output "
            "before replacing the working modules."
        )

    print()
    print(f"Created: {REGIONAL_EXPORTER}")
    print(f"Created: {STAGED_PLACEMENT}")
    print()
    print(
        "WorldPlacement working file was NOT changed."
    )
    print(
        f"Staged regional center: "
        f"X={REGIONAL_CENTER_X_M:.3f}, "
        f"Z={REGIONAL_CENTER_Z_M:.3f}"
    )
    print(LOCKED_AXES_NOTE)
    print("=" * 78)


if __name__ == "__main__":
    main()
