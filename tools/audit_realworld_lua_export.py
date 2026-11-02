#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")
TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"

if not TILES.exists():
    raise SystemExit(f"Missing generated Lua tile folder: {TILES}")

files = sorted(
    p for p in TILES.iterdir()
    if p.is_file() and p.suffix.lower() in {".lua", ".luau"}
)

print("=" * 80)
print("CHESTERWORLD REAL-WORLD LUA EXPORT AUDIT")
print("=" * 80)
print(f"Lua tile modules: {len(files):,}")

if len(files) != 102:
    raise SystemExit(
        f"Expected exactly 102 Lua tile modules; found {len(files)}."
    )

total_bytes = sum(p.stat().st_size for p in files)
print(f"Lua size:         {total_bytes / 1024 / 1024:.2f} MB")

# Lightweight sanity scan. Exact record totals are printed by the exporter itself,
# but every tile should still be a non-empty ModuleScript payload.
tiny = [p.name for p in files if p.stat().st_size < 100]
if tiny:
    raise SystemExit(
        "Suspiciously tiny Lua modules: " + ", ".join(tiny[:10])
    )

print("Module count/size sanity: PASS")
print("=" * 80)
