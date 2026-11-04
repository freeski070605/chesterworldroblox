#!/usr/bin/env python3
"""Verify the 102 locally exported ChesterWorld highway tiles before Studio."""
from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"
ROAD_LINE = re.compile(r"^\s*\{name=\"")
FIELD = re.compile(r'(\w+)=("(?:\\.|[^"\\])*"|[^,}]+)')


def read_roads():
    modules = sorted(TILES.glob("tile_r*_c*.lua"))
    if len(modules) != 102:
        raise SystemExit(f"FAILED: expected 102 tile modules, found {len(modules)}")
    roads = []
    for module in modules:
        for line in module.read_text(encoding="utf-8").splitlines():
            if not ROAD_LINE.match(line):
                continue
            fields = dict(FIELD.findall(line))
            if not fields:
                continue
            record = {}
            for key, raw in fields.items():
                if raw.startswith('"'):
                    record[key] = json.loads(raw)
                elif raw in ("true", "false"):
                    record[key] = raw == "true"
                else:
                    try:
                        record[key] = float(raw)
                    except ValueError:
                        record[key] = raw
            for key in ("bridge", "tunnel", "layer", "grade_group", "road_class"):
                if key not in record:
                    raise SystemExit(
                        f"FAILED: {module.name} road lacks {key}. "
                        "Run the grade-aware exporter before Studio."
                    )
            record["tile"] = module.name
            roads.append(record)
    return modules, roads


def point_distance_to_segment(x, z, road):
    ax, az = road["x1"], road["z1"]
    bx, bz = road["x2"], road["z2"]
    dx, dz = bx-ax, bz-az
    d2 = dx*dx+dz*dz
    if d2 == 0:
        return math.hypot(x-ax, z-az)
    t = max(0, min(1, ((x-ax)*dx+(z-az)*dz)/d2))
    return math.hypot(x-(ax+t*dx), z-(az+t*dz))


def classify_ramp(r):
    cls = str(r.get("road_class", "")).lower()
    name = str(r.get("name", "")).lower()
    return cls.endswith("_link") or (
        ("i 95" in name or "i-95" in name)
        and " to " in name
    )


def main():
    modules, roads = read_roads()
    grades = Counter(
        "bridge" if r["bridge"] or r["layer"] > 0 else
        "tunnel" if r["tunnel"] or r["layer"] < 0 else "ground"
        for r in roads
    )
    ramps = [r for r in roads if classify_ramp(r)]
    highway = [r for r in roads if "i 95" in str(r["name"]).lower()
               or "i-95" in str(r["name"]).lower()
               or "motorway" in str(r["road_class"]).lower()]
    bridge_groups = Counter()
    for road in roads:
        if road["bridge"] or road["layer"] > 0:
            bridge_groups[str(road["grade_group"])] += 1

    # Inspect an approximate 250m circle around the I-95 / Kerlin area.
    # This is a SOURCE-DATA audit, not a claim of vertical clearance.
    kerlin_x, kerlin_z = 7007, 7253
    near = [r for r in roads
            if point_distance_to_segment(kerlin_x, kerlin_z, r) <= 250]
    near_bridge = sum(bool(r["bridge"] or r["layer"] > 0) for r in near)
    near_tunnel = sum(bool(r["tunnel"] or r["layer"] < 0) for r in near)
    near_ramp = sum(classify_ramp(r) for r in near)

    summary = {
        "tile_modules": len(modules),
        "roads": len(roads),
        "bridge_segments": grades["bridge"],
        "tunnel_segments": grades["tunnel"],
        "ground_segments": grades["ground"],
        "bridge_source_groups": len(bridge_groups),
        "ramp_link_segments": len(ramps),
        "i95_or_motorway_segments": len(highway),
        "kerlin_250m": {
            "roads": len(near),
            "bridge_segments": near_bridge,
            "tunnel_segments": near_tunnel,
            "ramp_segments": near_ramp,
        },
        "largest_bridge_groups": bridge_groups.most_common(10),
    }
    report = PROJECT / "tools" / "highway_export_audit.json"
    report.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print("=" * 72)
    print("CHESTERWORLD I-95 / RAMP SOURCE AUDIT")
    print("=" * 72)
    for key in (
        "tile_modules", "roads", "bridge_segments",
        "tunnel_segments", "ground_segments", "bridge_source_groups",
        "ramp_link_segments", "i95_or_motorway_segments",
    ):
        print(f"{key:27} {summary[key]}")
    print("I-95/Kerlin source area (250m):", summary["kerlin_250m"])
    print("Report:", report)

    if grades["bridge"] == 0:
        raise SystemExit(
            "FAILED: no bridge segments exported. "
            "Do not run highway geometry without source bridge metadata."
        )
    if not highway:
        raise SystemExit("FAILED: no I-95/motorway segments exported.")
    if not ramps:
        print("WARNING: No tagged motorway links or named I-95 ramps.")
    if near and near_bridge == 0:
        print("WARNING: No explicitly grade-tagged bridge in the "
              "I-95/Kerlin source area. Verify county/OSM layer tags.")
    print("HIGHWAY SOURCE AUDIT: PASS (geometry must still be tested in Studio)")
    print("=" * 72)


if __name__ == "__main__":
    main()
