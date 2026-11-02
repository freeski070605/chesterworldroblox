#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")
BUILDER = PROJECT / "tools" / "build_street_system_v3.py"
TILE_DIR = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
BACKUP_ROOT = PROJECT / "tools" / "backups" / "street_system_v31"

REPLACEMENTS = [
    (
        r"MAX_SIDEWALK_SEGMENT_M\s*=\s*24\.0",
        "MAX_SIDEWALK_SEGMENT_M = 42.0",
        "max sidewalk segment",
    ),
    (
        r"MIN_SIDEWALK_SEGMENT_M\s*=\s*1\.2",
        "MIN_SIDEWALK_SEGMENT_M = 2.0",
        "min sidewalk segment",
    ),
    (
        r"SIMPLIFY_M\s*=\s*0\.18",
        "SIMPLIFY_M = 0.75",
        "sidewalk simplification",
    ),
]


def patch_builder():
    if not BUILDER.exists():
        raise SystemExit(f"Missing builder: {BUILDER}")

    text = BUILDER.read_text(encoding="utf-8")

    backup_dir = BACKUP_ROOT / "builder"
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    shutil.copy2(
        BUILDER,
        backup_dir / f"build_street_system_v3.before_v31_{stamp}.py",
    )

    for pattern, replacement, label in REPLACEMENTS:
        new_text, count = re.subn(pattern, replacement, text, count=1)
        if count == 0:
            # If already patched, accept the target value.
            target_value = replacement.split("=", 1)[1].strip()
            key = replacement.split("=", 1)[0].strip()
            already = re.search(
                rf"{re.escape(key)}\s*=\s*{re.escape(target_value)}",
                text,
            )
            if already:
                continue
            raise RuntimeError(
                f"Could not patch {label}. "
                f"Expected pattern: {pattern}"
            )
        text = new_text

    BUILDER.write_text(text, encoding="utf-8")

    print("Street builder V3.1 settings:")
    print("  MAX_SIDEWALK_SEGMENT_M = 42.0")
    print("  MIN_SIDEWALK_SEGMENT_M = 2.0")
    print("  SIMPLIFY_M = 0.75")


def purge_stale_lua_tiles():
    if not TILE_DIR.exists():
        TILE_DIR.mkdir(parents=True, exist_ok=True)
        print("Tile folder did not exist; created empty folder.")
        return

    lua_files = sorted(
        p for p in TILE_DIR.iterdir()
        if p.is_file() and p.suffix.lower() in {".lua", ".luau"}
    )

    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = BACKUP_ROOT / f"Tiles_before_clean_export_{stamp}"
    backup.mkdir(parents=True, exist_ok=True)

    for path in lua_files:
        shutil.copy2(path, backup / path.name)

    print(f"Backed up {len(lua_files)} Lua module(s) -> {backup}")

    for path in lua_files:
        path.unlink()

    remaining = [
        p for p in TILE_DIR.iterdir()
        if p.is_file() and p.suffix.lower() in {".lua", ".luau"}
    ]

    if remaining:
        raise RuntimeError(
            f"Could not clear {len(remaining)} Lua tile module(s)."
        )

    print(f"Cleared {len(lua_files)} old/stale Lua tile module(s).")
    print("Non-Lua files in the Tiles folder were left untouched.")


def main():
    print("=" * 88)
    print("CHESTERWORLD STREET SYSTEM V3.1 - REPAIR PREP")
    print("=" * 88)

    patch_builder()
    purge_stale_lua_tiles()

    print("=" * 88)
    print("V3.1 REPAIR PREP COMPLETE")
    print("=" * 88)


if __name__ == "__main__":
    main()
