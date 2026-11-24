"""Tight Street View zoom on a sign seen in an existing reference image.

    py -3 tools/reconstruction/sign_zoom.py <id> <image stem> <x 0-1> <y 0-1> [fov=12] [name]

<image stem> is a file in Data/25_GoogleStreetView_Buildings/images/<id>/
(e.g. zoom_bAZ_zOpmaD0amtTm_331); x, y are the sign's position as fractions
of that image. The pano, heading, pitch and fov of the source image come from
extra_views.csv / manifest.csv, so the new view is aimed exactly at the sign.
Saves images/<id>/sign_<name>.jpg, logs it in extra_views.csv (role "sign")
and prints the anchor key "<pano 8>_<heading>" for InstitutionReconstruction.
"""
import csv
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "storefronts"))
import google_streetview as g  # noqa: E402

OUT = g.OUT_B


def source_params(bid, stem):
    rel = f"images/{bid}/{stem}.jpg"
    with open(OUT / "extra_views.csv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["objectid"] == bid and r["path"].replace("\\", "/") == rel:
                return r["pano_id"], float(r["heading"]), float(r["pitch"]), float(r["fov"])
    with open(OUT / "manifest.csv", encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            if r["objectid"] == bid and Path(r["path"]).stem == stem:
                return r["pano_id"], float(r["camera_heading_deg"]), float(r["pitch_deg"]), float(r["fov_deg"])
    raise SystemExit(f"no record for {rel}")


def main():
    bid, stem, fx, fy = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    fov = float(sys.argv[5]) if len(sys.argv) > 5 else 12
    name = sys.argv[6] if len(sys.argv) > 6 else "board"
    pano, h0, p0, f0 = source_params(bid, stem)
    t = math.tan(math.radians(f0 / 2))
    heading = (h0 + math.degrees(math.atan((fx - 0.5) * 2 * t))) % 360
    pitch = p0 + math.degrees(math.atan((0.5 - fy) * 2 * t))
    dest = OUT / "images" / bid / f"sign_{name}.jpg"
    if dest.exists():
        dest.unlink()
    g.fetch(pano, heading, pitch, fov, dest, g.key())
    meta = {m["pano_id"]: m for m in json.load(open(OUT / "metadata_cache.json")).values() if m}
    m = meta.get(pano) or {}
    if not m:
        with open(OUT / "manifest.csv", encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                if r["pano_id"] == pano:
                    m = {"date": r["capture_date"], "lat": r["camera_lat"], "lon": r["camera_lon"]}
                    break
    with open(OUT / "extra_views.csv", "a", newline="", encoding="utf-8") as fh:
        csv.writer(fh).writerow([bid, "sign", f"images/{bid}/{dest.name}", pano, m.get("date", ""), m.get("lat", ""),
                                 m.get("lon", ""), round(heading, 1), round(pitch, 1), fov, "", g.LIC])
    print(dest, f"{pano[:8]}_{int(heading)}")


if __name__ == "__main__":
    main()
