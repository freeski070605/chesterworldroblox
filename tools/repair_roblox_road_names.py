#!/usr/bin/env python3
r"""
Repair ChesterWorld road names in the already-generated Roblox Lua tiles.

WHY:
The source Chester Unity/JSON tiles preserve the full road property dictionary,
including `generator_name`. The first Roblox exporter used a generic `name`
field, so most road segments became:

    name="Road"

while a few OSM-origin roads such as Butler Street kept a literal `name`.

THIS SCRIPT:
- reads the 62 source Chester JSON tiles;
- extracts every road segment and its normalized generator_name;
- matches those source segments to the already-generated Lua road records
  by X/Z endpoints;
- replaces ONLY `name="..."` in road records;
- does NOT change coordinates, widths, buildings, terrain, or placement;
- creates a backup outside the Rojo-synced tree before modifying anything.

Run from:
    E:\code\chesterworld-roblox

Command:
    py .\tools\repair_roblox_road_names.py
"""

from __future__ import annotations

import json
import re
import shutil
import time
from collections import Counter
from pathlib import Path

SOURCE_TILES = Path(r"E:\ChesterWorld\Data\16_UnityTiles\Tiles")
PROJECT = Path(r"E:\code\chesterworld-roblox")
LUA_TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
BACKUP_ROOT = PROJECT / "tools" / "backups"

ROAD_RECORD_RE = re.compile(
    r'\{'
    r'name="(?P<name>(?:\\.|[^"])*)",'
    r'x1=(?P<x1>[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?),'
    r'z1=(?P<z1>[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?),'
    r'x2=(?P<x2>[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?),'
    r'z2=(?P<z2>[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?),'
    r'width_m=(?P<width>[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)'
    r'\}'
)


def lua_escape(value: str) -> str:
    return (
        str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "")
    )


def clean(value) -> str:
    if value is None:
        return ""
    text = " ".join(str(value).strip().split())
    if text.lower() in {"", "none", "null", "nan"}:
        return ""
    return text


def street_name(props: dict) -> str:
    # Source road prep's canonical normalized field.
    for key in (
        "generator_name",
        "St_Name",
        "StreetName",
        "FULLNAME",
        "NAME",
        "name",
    ):
        value = clean(props.get(key))
        if value:
            return value
    return "Road"


def iter_lines(geometry):
    if not geometry:
        return

    geom_type = geometry.get("type")
    coords = geometry.get("coordinates")

    if geom_type == "LineString":
        yield coords or []
    elif geom_type == "MultiLineString":
        for line in coords or []:
            yield line
    elif geom_type == "GeometryCollection":
        for child in geometry.get("geometries") or []:
            yield from iter_lines(child)


def canonical_key(x1, z1, x2, z2, digits=3):
    a = (round(float(x1), digits), round(float(z1), digits))
    b = (round(float(x2), digits), round(float(z2), digits))
    return (a, b) if a <= b else (b, a)


def source_segment_map(tile_json: Path):
    payload = json.loads(tile_json.read_text(encoding="utf-8"))

    roads = (
        (payload.get("layers") or {}).get("roads")
        or payload.get("roads")
        or []
    )

    maps = {
        3: {},
        2: {},
        1: {},
    }

    stats = Counter()

    for feature in roads:
        props = feature.get("properties") or {}
        name = street_name(props)
        geometry = feature.get("geometry")

        for coords in iter_lines(geometry):
            if not coords or len(coords) < 2:
                continue

            for i in range(len(coords) - 1):
                a = coords[i]
                b = coords[i + 1]

                if len(a) < 2 or len(b) < 2:
                    continue

                x1, z1 = float(a[0]), float(a[1])
                x2, z2 = float(b[0]), float(b[1])

                if abs(x2 - x1) + abs(z2 - z1) < 1e-9:
                    continue

                stats["source_segments"] += 1

                for digits in maps:
                    key = canonical_key(x1, z1, x2, z2, digits)
                    existing = maps[digits].get(key)

                    if existing is None:
                        maps[digits][key] = name
                    elif existing != name:
                        # Ambiguous only at this rounding level.
                        maps[digits][key] = False

    return maps, stats


def find_name(maps, x1, z1, x2, z2):
    for digits in (3, 2, 1):
        key = canonical_key(x1, z1, x2, z2, digits)
        value = maps[digits].get(key)
        if value:
            return value, digits

    return None, None


def repair_tile(lua_path: Path, source_path: Path):
    maps, source_stats = source_segment_map(source_path)

    text = lua_path.read_text(encoding="utf-8")
    stats = Counter(source_stats)

    unresolved_examples = []

    def replace(match):
        stats["lua_road_records"] += 1

        old_name = match.group("name")
        x1 = float(match.group("x1"))
        z1 = float(match.group("z1"))
        x2 = float(match.group("x2"))
        z2 = float(match.group("z2"))

        new_name, digits = find_name(maps, x1, z1, x2, z2)

        if not new_name:
            stats["unresolved"] += 1
            if len(unresolved_examples) < 8:
                unresolved_examples.append(
                    (x1, z1, x2, z2, old_name)
                )
            return match.group(0)

        stats[f"matched_{digits}dp"] += 1

        if clean(old_name) == clean(new_name):
            stats["already_correct"] += 1
            return match.group(0)

        stats["renamed"] += 1

        return (
            '{'
            f'name="{lua_escape(new_name)}",'
            f'x1={match.group("x1")},'
            f'z1={match.group("z1")},'
            f'x2={match.group("x2")},'
            f'z2={match.group("z2")},'
            f'width_m={match.group("width")}'
            '}'
        )

    repaired = ROAD_RECORD_RE.sub(replace, text)

    if repaired != text:
        lua_path.write_text(repaired, encoding="utf-8")

    return stats, unresolved_examples


def main():
    if not SOURCE_TILES.exists():
        raise SystemExit(f"Missing source tile folder: {SOURCE_TILES}")

    if not LUA_TILES.exists():
        raise SystemExit(f"Missing Roblox tile folder: {LUA_TILES}")

    lua_files = sorted(LUA_TILES.glob("tile_r*_c*.lua"))

    if not lua_files:
        raise SystemExit(f"No generated Lua tiles found in {LUA_TILES}")

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    backup_dir = BACKUP_ROOT / f"tiles_before_road_name_repair_{timestamp}"
    backup_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 76)
    print("CHESTERWORLD ROAD NAME REPAIR")
    print("=" * 76)
    print(f"Lua tiles:   {len(lua_files)}")
    print(f"Source:      {SOURCE_TILES}")
    print(f"Target:      {LUA_TILES}")
    print(f"Backup:      {backup_dir}")
    print()

    totals = Counter()
    missing_source = []
    unresolved_all = []

    for index, lua_path in enumerate(lua_files, start=1):
        source_path = SOURCE_TILES / f"{lua_path.stem}.json"

        if not source_path.exists():
            missing_source.append(source_path)
            print(f"[{index:02d}/{len(lua_files):02d}] MISSING SOURCE {source_path.name}")
            continue

        shutil.copy2(lua_path, backup_dir / lua_path.name)

        stats, unresolved = repair_tile(lua_path, source_path)
        totals.update(stats)

        if unresolved:
            unresolved_all.append((lua_path.name, unresolved))

        print(
            f"[{index:02d}/{len(lua_files):02d}] {lua_path.name}: "
            f"roads={stats['lua_road_records']:,} "
            f"renamed={stats['renamed']:,} "
            f"correct={stats['already_correct']:,} "
            f"unresolved={stats['unresolved']:,}"
        )

    print()
    print("=" * 76)
    print("REPAIR SUMMARY")
    print("=" * 76)
    print(f"Road records:       {totals['lua_road_records']:,}")
    print(f"Names repaired:     {totals['renamed']:,}")
    print(f"Already correct:    {totals['already_correct']:,}")
    print(f"Matched @ 3dp:      {totals['matched_3dp']:,}")
    print(f"Matched @ 2dp:      {totals['matched_2dp']:,}")
    print(f"Matched @ 1dp:      {totals['matched_1dp']:,}")
    print(f"Unresolved:         {totals['unresolved']:,}")
    print(f"Missing sources:    {len(missing_source)}")
    print()

    # Verify the specific Chester corridor names now exist as ROAD RECORDS.
    verify_terms = (
        "Kerlin Street",
        "Parker Street",
        "Fulton Street",
        "Barclay Street",
        "Butler Street",
        "9th",
        "8th",
    )

    combined = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in lua_files
    )

    print("CORRIDOR NAME CHECK")
    print("-" * 76)

    for term in verify_terms:
        count = len(re.findall(re.escape(term), combined, re.I))
        print(f"{term:<18} {count:>6,} literal occurrence(s)")

    if totals["unresolved"]:
        print()
        print("FIRST UNRESOLVED EXAMPLES")
        print("-" * 76)
        shown = 0

        for filename, examples in unresolved_all:
            for item in examples:
                print(filename, item)
                shown += 1
                if shown >= 12:
                    break
            if shown >= 12:
                break

    print()
    print("Backup created outside Rojo tree:")
    print(backup_dir)
    print()
    print("NEXT:")
    print("  1. Let Rojo sync the modified tile modules.")
    print("  2. Re-run audit_roblox_tile_export_v2.py.")
    print("  3. Do not regenerate the city or terrain.")
    print("=" * 76)


if __name__ == "__main__":
    main()
