#!/usr/bin/env python3
"""Compare new georeferenced footprint outlines to ChesterWorld's existing
building rectangle inventory. Does not modify gameplay or tile data.

Run after audit_existing_buildings.py and geojson_to_luau.py:
  py tools/reconstruction/compare_building_alignment.py \
    --existing reconstruction_building_audit.csv \
    --candidate src/shared/ReconstructionPilot.lua \
    --out reconstruction_alignment_report.csv
"""
import argparse
import csv
import math
import re
from pathlib import Path

# Matches the exact generated Luau format; does not execute Lua source.
RECORD = re.compile(
    r'\{ id = "(?P<id>[^"]+)", height = (?P<height>\d+(?:\.\d+)?), points = \{'
    r'(?P<points>.*?)\}\s*\}', re.S)
POINT = re.compile(r'\{\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\}')

def candidates(path):
    data = path.read_text(encoding="utf-8")
    results = []
    for match in RECORD.finditer(data):
        vertices = [(float(x), float(z)) for x,z in POINT.findall(match["points"])]
        if len(vertices) < 3:
            continue
        n = len(vertices)
        x = sum(v[0] for v in vertices) / n
        z = sum(v[1] for v in vertices) / n
        results.append({"id": match["id"], "x": x, "z": z, "vertices": n,
                        "height_studs": float(match["height"])})
    return results

def compare(existing, new, mismatch_threshold=35.0):
    old = []
    for row in existing:
        try:
            old.append({"id": row["id"], "x": float(row["world_x"]),
                        "z": float(row["world_z"]), "tile": row["tile"]})
        except (ValueError, KeyError):
            continue
    rows = []
    for item in new:
        if not old:
            rows.append({"candidate_id": item["id"], "matched_id": "",
                         "distance_studs": "", "status": "NO_LEGACY_DATA",
                         "tile": "", "vertices": item["vertices"]})
            continue
        closest = min(old, key=lambda p: math.hypot(p["x"] - item["x"], p["z"] - item["z"]))
        dist = math.hypot(closest["x"] - item["x"], closest["z"] - item["z"])
        # Proximity alone is NOT a building identity match; report a candidate only.
        status = "REVIEW_NEARBY" if dist <= mismatch_threshold else "UNMATCHED"
        rows.append({"candidate_id": item["id"], "matched_id": closest["id"],
                     "distance_studs": round(dist, 2), "status": status,
                     "tile": closest["tile"], "vertices": item["vertices"]})
    return rows

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--existing", type=Path, required=True)
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("reconstruction_alignment_report.csv"))
    p.add_argument("--threshold", type=float, default=35.0)
    args = p.parse_args()
    if not 0 < args.threshold <= 300:
        p.error("--threshold must be between 0 and 300 studs")
    with args.existing.open(newline="", encoding="utf-8") as f:
        old = list(csv.DictReader(f))
    new = candidates(args.candidate)
    if not new:
        raise SystemExit("No candidate polygons found. Run converter first.")
    rows = compare(old, new, args.threshold)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["candidate_id", "matched_id",
            "distance_studs", "status", "tile", "vertices"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"Compared {len(new)} imported polygons against {len(old)} existing buildings.")
    print(f"Report: {args.out}")
    print("CAUTION: closest-centroid matches are suggestions only, not validated identities.")
    print("Never replace buildings automatically based on this report.")

if __name__ == "__main__":
    main()
