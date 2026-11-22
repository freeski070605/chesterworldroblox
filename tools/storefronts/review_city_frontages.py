"""Build a citywide, image-linked storefront frontage review queue.

This command DOES NOT decide which wall faces the street by proximity. It
cross-references the current Roblox BuildingTiles storefronts against existing
Google Street View and Mapillary image manifests, producing an evidence queue.
Google photos remain on the local E: drive for private review; do not commit them.

Usage:
  py tools/storefronts/review_city_frontages.py
  py tools/storefronts/review_city_frontages.py --data E:/ChesterWorld/Data
  py tools/storefronts/review_city_frontages.py --out build/city_frontage_review.csv

Review the referenced photos and record a verified target street/frontage in the
source identity pipeline before regenerating tiles. This is a review report, not
an automatic claim that an image proves entrance orientation.
"""
from __future__ import annotations
import argparse
import csv
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILDINGS = ROOT / "src/shared/WorldData/BuildingTiles"
BASE = Path("E:/ChesterWorld/Data")
TUPLE = re.compile(r'\{"((?:[^"\\]|\\.)*)",(\d+),(-?\d+),0x[0-9a-fA-F]+,0x[0-9a-fA-F]+,"([^"]*)"\}')
LINE = re.compile(r'^\s*\["(\d+)"\]=\{(.*)\}\s*,?\s*$')


def manifest(path: Path) -> dict:
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8-sig", newline="") as f:
        return {str(r.get("objectid") or r.get("OBJECTID") or ""): r
                for r in csv.DictReader(f) if r.get("objectid") or r.get("OBJECTID")}


def path_if_exists(directory: Path, row: dict) -> str:
    raw = row.get("path") or ""
    if not raw:
        return ""
    path = directory / raw
    return str(path) if path.is_file() else ""


def run(data: Path, out: Path):
    google = data / "25_GoogleStreetView_Buildings"
    mapi = data / "24_BuildingImagery_Mapillary"
    gm = manifest(google / "manifest.csv")
    mm = manifest(mapi / "manifest.csv")
    records, stats = [], Counter()
    for path in sorted(BUILDINGS.glob("*.lua")):
        for line in path.read_text(encoding="utf-8").splitlines():
            m = LINE.match(line)
            if not m:
                continue
            bid, body = m.groups()
            if "ss={{" not in body and "sb={{" not in body:
                continue
            for name, section, bearing, placeid in TUPLE.findall(body):
                g = gm.get(bid, {})
                mp = mm.get(bid, {})
                photo_g = path_if_exists(google, g)
                photo_m = path_if_exists(mapi, mp)
                photo = photo_g or photo_m
                src = "GoogleStreetView" if photo_g else "Mapillary" if photo_m else "missing"
                stats[src] += 1
                records.append({
                    "building_id": bid, "section": section, "shop_name": name,
                    "tile": path.name, "game_bearing": bearing,
                    "source": src, "image_local_path": photo,
                    "capture_date": (g if photo_g else mp).get("capture_date", ""),
                    "image_recorded_road": (g if photo_g else mp).get("road", ""),
                    "imagery_review_status": "NEEDS_MANUAL_IMAGE_REVIEW",
                    "verified_facing_street": "",
                    "verified_bearing_deg": "",
                    "review_notes": "",
                    "business_place_id": placeid,
                })
    out.parent.mkdir(parents=True, exist_ok=True)
    fields = ["building_id", "section", "shop_name", "tile", "game_bearing",
              "source", "image_local_path", "capture_date", "image_recorded_road",
              "imagery_review_status", "verified_facing_street", "verified_bearing_deg",
              "review_notes", "business_place_id"]
    with out.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(records)
    stats["total"] = len(records)
    print(f"[CW ImageryFrontage] wrote {out}")
    print(f"[CW ImageryFrontage] counts {dict(stats)}")
    for item in records:
        if "sherylynn" in re.sub(r"[^a-z0-9]+", "", item["shop_name"].lower()):
            print("[CW ImageryFrontage] SHERYLYNN:", item)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", type=Path, default=BASE)
    ap.add_argument("--out", type=Path, default=ROOT / "build/city_frontage_review.csv")
    args = ap.parse_args()
    run(args.data, args.out)
