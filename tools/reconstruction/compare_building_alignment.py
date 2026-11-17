#!/usr/bin/env python3
"""Compare candidate polygons with existing oriented building rectangles (review only)."""
import argparse
import csv
import re
from pathlib import Path

from shapely.affinity import rotate, translate
from shapely.geometry import Polygon, box

RECORD = re.compile(r'\{ id = "(?P<id>[^"]+)", height = (?P<height>\d+(?:\.\d+)?),'
                    r'(?: heightSource = "[^"]+",)? points = \{(?P<points>.*?)\}\s*\}', re.S)
POINT = re.compile(r'\{\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\s*\}')
FIELDS = ["candidate_id", "matched_id", "status", "centroid_error_studs",
          "footprint_gap_studs", "intersection_over_union", "candidate_overlap_fraction",
          "tile", "vertices"]


def candidates(path):
    results = []
    for match in RECORD.finditer(path.read_text(encoding="utf-8")):
        points = [(float(x), float(z)) for x, z in POINT.findall(match["points"])]
        polygon = Polygon(points)
        if len(points) < 3 or not polygon.is_valid or polygon.area <= 0:
            continue
        results.append({"id": match["id"], "polygon": polygon,
                        "x": polygon.centroid.x, "z": polygon.centroid.y,
                        "vertices": len(points), "height_studs": float(match["height"])})
    return results


def old_polygon(row):
    x, z = float(row["world_x"]), float(row["world_z"])
    w, d = float(row["width_m"]) * 3, float(row["depth_m"]) * 3
    if w <= 0 or d <= 0:
        raise ValueError("nonpositive dimensions")
    return translate(rotate(box(-w/2, -d/2, w/2, d/2),
                            -float(row["yaw_deg"]), origin=(0, 0)), xoff=x, yoff=z)


def compare(existing, new):
    old = []
    for row in existing:
        try:
            old.append({"id": row["id"], "tile": row["tile"], "polygon": old_polygon(row)})
        except (ValueError, KeyError):
            continue
    rows = []
    for item in new:
        candidate = item["polygon"]
        if not old:
            rows.append(dict.fromkeys(FIELDS, "") | {"candidate_id": item["id"],
                         "status": "NO_LEGACY_DATA", "vertices": item["vertices"]})
            continue
        # Prefer actual shared area. Several rowhouses touch at zero gap.
        closest = max(old, key=lambda o: (
            candidate.intersection(o["polygon"]).area,
            -candidate.distance(o["polygon"])))
        overlap = candidate.intersection(closest["polygon"]).area
        union = candidate.union(closest["polygon"]).area
        gap = candidate.distance(closest["polygon"])
        centroid = candidate.centroid.distance(closest["polygon"].centroid)
        rows.append({"candidate_id": item["id"], "matched_id": closest["id"],
                     "status": "REVIEW_OVERLAP" if overlap > 0 else "UNMATCHED",
                     "centroid_error_studs": round(centroid, 2),
                     "footprint_gap_studs": round(gap, 2),
                     "intersection_over_union": round(overlap / union, 3) if union else 0,
                     "candidate_overlap_fraction": round(overlap / candidate.area, 3),
                     "tile": closest["tile"], "vertices": item["vertices"]})
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--existing", type=Path, required=True)
    p.add_argument("--candidate", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("reconstruction_alignment_report.csv"))
    args = p.parse_args()
    with args.existing.open(newline="", encoding="utf-8") as f:
        old = list(csv.DictReader(f))
    new = candidates(args.candidate)
    if not new:
        raise SystemExit("No candidate polygons found. Run converter first.")
    rows = compare(old, new)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    matched = sum(row["status"] == "REVIEW_OVERLAP" for row in rows)
    errors = sorted(float(row["centroid_error_studs"]) for row in rows if row["status"] == "REVIEW_OVERLAP")
    median = errors[len(errors)//2] if errors else None
    print(f"Imported={len(new)} existing={len(old)} overlap_candidates={matched} unmatched={len(rows)-matched} median_centroid_error_studs={median}")
    print(f"Report: {args.out}. Overlaps require visual identity review; no buildings replaced.")


if __name__ == "__main__":
    main()
