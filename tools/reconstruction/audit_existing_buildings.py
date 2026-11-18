#!/usr/bin/env python3
"""Inventory existing ChesterWorld building records around an exact Roblox X/Z.
Reads checked-in tile Lua modules, no network or imagery required.
Usage: py tools/reconstruction/audit_existing_buildings.py --x 2810 --z 1519
Values in examples are historical and should be replaced with current Studio coords.
"""
import argparse
import csv
import re
from pathlib import Path

S = 3.0
CX, CZ = 6347.889, 7201.973
RECORD = re.compile(
    r'\{id="(?P<id>[^"]+)",name="(?P<name>[^"]*)",'
    r'x_m=(?P<x>-?\d+(?:\.\d+)?),z_m=(?P<z>-?\d+(?:\.\d+)?),'
    r'width_m=(?P<width>-?\d+(?:\.\d+)?),depth_m=(?P<depth>-?\d+(?:\.\d+)?),'
    r'yaw_deg=(?P<yaw>-?\d+(?:\.\d+)?),height_m=(?P<height>-?\d+(?:\.\d+)?)'
)

def collect(folder, x, z, radius):
    found = []
    for path in sorted(folder.glob("tile_*.lua")):
        raw = path.read_text(encoding="utf-8")
        # Only building records have this exact id/name/dimensions signature.
        for match in RECORD.finditer(raw):
            row = match.groupdict()
            sx = (float(row["x"]) - CX) * S
            sz = -(float(row["z"]) - CZ) * S
            d = ((sx - x)**2 + (sz - z)**2)**0.5
            if d <= radius:
                found.append({
                    "tile": path.stem, "id": row["id"], "name": row["name"],
                    "world_x": round(sx, 2), "world_z": round(sz, 2),
                    "distance_studs": round(d, 2),
                    "width_m": row["width"], "depth_m": row["depth"],
                    "height_m": row["height"], "yaw_deg": row["yaw"],
                })
    return sorted(found, key=lambda item: item["distance_studs"])

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--x", type=float, required=True, help="Roblox Studio world X at pilot center")
    p.add_argument("--z", type=float, required=True, help="Roblox Studio world Z at pilot center")
    p.add_argument("--radius", type=float, default=450.0, help="Audit radius in studs")
    p.add_argument("--tiles", type=Path, default=Path("src/shared/WorldData/Tiles"))
    p.add_argument("--out", type=Path, default=Path("reconstruction_building_audit.csv"))
    args = p.parse_args()
    if not args.tiles.is_dir():
        p.error(f"Tile directory not found: {args.tiles}")
    if args.radius <= 0:
        p.error("--radius must be positive")
    records = collect(args.tiles, args.x, args.z, args.radius)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    fields = ["tile", "id", "name", "world_x", "world_z", "distance_studs",
              "width_m", "depth_m", "height_m", "yaw_deg"]
    with args.out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(records)
    print(f"Found {len(records)} existing building records within {args.radius} studs, exported {args.out}")
    print("These are existing approximate oriented rectangles; not surveyed LiDAR outlines.")

if __name__ == "__main__":
    main()
