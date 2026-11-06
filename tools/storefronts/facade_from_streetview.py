"""Measure each building's facade colour and wall material from street imagery.

Reads the Google Street View building fronts (Data/25_GoogleStreetView_Buildings
manifest.csv) and, where Google has none, the Mapillary building frames
(Data/24_BuildingImagery_Mapillary/manifest.csv). For each image, samples the
centre of the frame where the aimed building sits, drops sky / foliage / road /
deep shadow pixels, clusters the rest and takes the dominant cluster as the
wall colour. A simple colour+texture rule labels the material
(brick / stone / siding / stucco / painted). Low-confidence results are dropped
so the generator falls back to its style palette.

    py -3 tools/storefronts/facade_from_streetview.py
Output: Data/25_GoogleStreetView_Buildings/facade_measurements.json (keyed by OBJECTID)
"""
import csv
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

DATA = Path(r"E:\ChesterWorld\Data")
GOOGLE = DATA / "25_GoogleStreetView_Buildings"
MAPI = DATA / "24_BuildingImagery_Mapillary"
OUT = GOOGLE / "facade_measurements.json"


def kmeans(px, k=4, iters=12, seed=1):
    rng = np.random.default_rng(seed)
    c = px[rng.choice(len(px), k, replace=False)].astype(float)
    for _ in range(iters):
        d = ((px[:, None, :] - c[None]) ** 2).sum(-1)
        lab = d.argmin(1)
        for j in range(k):
            m = px[lab == j]
            if len(m):
                c[j] = m.mean(0)
    return c, lab


CAM_H = 2.5  # Google / dashcam camera height above street, metres


def wall_window(w, h, d, pitch, fov, height_m, width_m):
    """Project the wall band (2 m above ground .. 85% of height) and the building width into pixels."""
    import math
    f = (w / 2) / math.tan(math.radians(fov) / 2)  # focal length, px (square pixels)

    def y_of(z):  # z = height above street (m) at horizontal distance d
        ang = math.atan2(z - CAM_H, d) - math.radians(pitch)
        return h / 2 - f * math.tan(ang)
    H = max(4.0, height_m or 7.0)
    y_top = y_of(H * 0.85)
    y_bot = y_of(min(2.2, H * 0.45))
    half = f * min(width_m or 10, 30) / 2 / d * 0.7
    x0, x1 = max(0, w / 2 - half), min(w, w / 2 + half)
    y0, y1 = max(0, y_top), min(h * 0.92, y_bot)
    if x1 - x0 < 24 or y1 - y0 < 16:
        return None
    return int(x0), int(y0), int(x1), int(y1)


def measure(path, distance_m, pitch=0.0, fov=60.0, height_m=None, width_m=None):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    box_ = wall_window(w, h, max(distance_m, 4), pitch, fov, height_m, width_m)
    if not box_:
        return None
    crop = np.asarray(im.crop(box_).resize((96, 96)), dtype=float)
    gray = crop.mean(-1)
    # local texture (mortar lines / stone joints) before masking
    tex = np.abs(np.diff(gray, axis=1)).mean()
    px = crop.reshape(-1, 3)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    mx, mn = px.max(1), px.min(1)
    sat = (mx - mn) / np.maximum(mx, 1)
    sky = (b > r + 12) & (b > g) & (mx > 140)
    foliage = (g > r + 6) & (g > b + 4)
    dark = mx < 45
    glare = mn > 245
    keep = ~(sky | foliage | dark | glare)
    pxk = px[keep]
    frac = keep.mean()
    if len(pxk) < 600:
        return None
    c, lab = kmeans(pxk)
    counts = np.bincount(lab, minlength=len(c))
    # prefer the largest cluster that is not asphalt-grey road at the bottom
    order = counts.argsort()[::-1]
    j = order[0]
    share = counts[j] / len(pxk)
    rgb = c[j]
    R, G, B = rgb
    m, n = max(rgb), min(rgb)
    s = (m - n) / max(m, 1)
    if R > G * 1.12 and R > B * 1.22 and 60 < m < 215 and s > 0.18:
        mat = "brick"
    elif s < 0.13 and m > 175:
        mat = "siding" if tex < 9 else "stucco"
    elif s < 0.22 and tex > 11 and m < 175:
        mat = "stone"
    elif s < 0.16:
        mat = "stucco"
    else:
        mat = "painted"
    conf = round(float(share * min(1.0, frac / 0.35)), 3)
    return {"rgb": [int(R), int(G), int(B)], "material": mat, "share": round(float(share), 3),
            "facade_fraction": round(float(frac), 3), "texture": round(float(tex), 2), "confidence": conf}


def rows(path, root, idkey="objectid"):
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig") as fh:
        return [(r[idkey], root / r["path"], float(r.get("distance_m") or 20), r) for r in csv.DictReader(fh)]


def main():
    res = {}
    src = Counter()
    google = rows(GOOGLE / "manifest.csv", GOOGLE)
    have = set()
    import math
    for n, (oid, p, d, r) in enumerate(google, 1):
        if not p.exists():
            continue
        fov = float(r.get("fov_deg") or 60)
        width = max(4.0, 2 * (d * math.tan(math.radians(fov) / 2) - 3))  # inverse of capture_params()
        hm = float(r["height_m"]) if r.get("height_m") else None
        m = measure(p, d, float(r.get("pitch_deg") or 0), fov, hm, width)
        if m and m["confidence"] >= 0.22:
            res[oid] = {**m, "source": "GoogleStreetView", "image": str(p), "capture_date": r.get("capture_date")}
            src["google"] += 1
        have.add(oid)
        if n % 1000 == 0:
            print(f"  google {n}/{len(google)}", flush=True)
    for oid, p, d, r in rows(MAPI / "manifest.csv", MAPI):
        if oid in res or not p.exists():
            continue
        m = measure(p, d, 0.0, 75.0, None, 10)  # dashcam: level, ~75 deg horizontal FOV
        if m and m["confidence"] >= 0.25:
            res[oid] = {**m, "source": "Mapillary", "image": str(p), "capture_date": r.get("capture_date")}
            src["mapillary"] += 1
    OUT.write_text(json.dumps(res, indent=1), encoding="utf-8")
    print("measured", len(res), "of", len(google), "google images;", dict(src))
    print("materials", Counter(v["material"] for v in res.values()).most_common())
    print("->", OUT)


if __name__ == "__main__":
    main()
