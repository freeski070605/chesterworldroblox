"""Extra Street View angles of a school / church (all sides, signs).

The citywide sweep saved one front view per building. A faithful rebuild of a
school or church needs its other sides and its sign, so this tool walks a ring
around the building's county footprint, finds the distinct outdoor panoramas
nearby (metadata calls are free) and saves one view per panorama aimed at the
nearest part of the building, plus an optional tight "sign" view.

    py -3 tools/reconstruction/institution_views.py 155084 [ids ...] [--max 8] [--zoom]

Writes Data/25_GoogleStreetView_Buildings/images/<id>/view_<pano>_<heading>.jpg
and appends to .../extra_views.csv. Images are (c) Google, private modelling
reference only (Google Maps Platform Terms) - never published or committed.
"""
import argparse
import csv
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "storefronts"))
sys.path.insert(0, str(HERE.parent / "harness"))
import google_streetview as g  # noqa: E402
import storefront_sweep as s  # noqa: E402
from aerial_overlay import X_OFFSET, Z_OFFSET, record, rect_corners  # noqa: E402

OUT = g.OUT_B
LOG = OUT / "extra_views.csv"
R_EARTH = 6378137.0
SCALE = 1 / math.cos(math.radians(39.848))  # mercator metres per true metre


def lonlat(x, z):
    mx, my = x - X_OFFSET, z - Z_OFFSET
    lon = mx / R_EARTH * 180 / math.pi
    lat = (2 * math.atan(math.exp(my / R_EARTH)) - math.pi / 2) * 180 / math.pi
    return lon, lat


def src(lon, lat):
    mx = lon * math.pi / 180 * R_EARTH
    my = math.log(math.tan((90 + lat) * math.pi / 360)) * R_EARTH
    return mx + X_OFFSET, my + Z_OFFSET


def footprint(bid):
    rects, a = record(bid)
    pts = [p for r in rects for p in rect_corners(*r, a)]
    return pts


def nearest(pts, x, z):
    return min(pts, key=lambda p: (p[0] - x) ** 2 + (p[1] - z) ** 2)


def perimeter_samples(pts, step=6.0):
    """Points along the convex hull of the footprint corners (source metres)."""
    from shapely.geometry import MultiPoint
    hull = MultiPoint(pts).convex_hull.exterior
    n = max(8, int(hull.length / step))
    return [hull.interpolate(i / n, normalized=True).coords[0] for i in range(n)]


def views_for(bid, k, meta, maxn, zoom):
    pts = footprint(bid)
    cx = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    edge = perimeter_samples(pts)
    rad = max(math.hypot(p[0] - cx, p[1] - cz) for p in pts) + 22 * SCALE
    found = {}
    for i in range(16):
        t = 2 * math.pi * i / 16
        lon, lat = lonlat(cx + math.cos(t) * rad, cz + math.sin(t) * rad)
        m = meta.get(lat, lon, 45, k)
        if m and m["pano_id"] not in found:
            found[m["pano_id"]] = m
    rows = []
    # spread the choice around the building: sort panos by angle, take evenly
    def ang(m):
        x, z = src(m["lon"], m["lat"])
        return math.atan2(z - cz, x - cx)
    panos = sorted(found.values(), key=ang)
    if len(panos) > maxn:
        panos = [panos[int(i * len(panos) / maxn)] for i in range(maxn)]
    for m in panos:
        px, pz = src(m["lon"], m["lat"])
        tx, tz = nearest(edge, px, pz)
        # aim between the nearest wall point and the centre so the view reads the mass
        ax, az = (tx * 2 + cx) / 3, (tz * 2 + cz) / 3
        d_true = math.hypot(ax - px, az - pz) / SCALE
        heading = (math.degrees(math.atan2(ax - px, az - pz)) + 360) % 360
        fov = 90 if d_true < 40 else 70
        pitch = max(0.0, min(20.0, math.degrees(math.atan(6 / max(d_true, 5)))))
        shots = [(heading, pitch, fov, "view")]
        if zoom:
            near_true = math.hypot(tx - px, tz - pz) / SCALE
            hn = (math.degrees(math.atan2(tx - px, tz - pz)) + 360) % 360
            shots.append((hn, 2.0, 35 if near_true > 20 else 50, "zoom"))
        for h, p, f, role in shots:
            dest = OUT / "images" / bid / f"{role}_{m['pano_id']}_{int(h)}.jpg"
            ok = g.fetch(m["pano_id"], h, p, f, dest, k)
            if ok:
                rows.append({"objectid": bid, "role": role, "path": str(dest.relative_to(OUT)),
                             "pano_id": m["pano_id"], "date": m["date"], "lat": m["lat"], "lon": m["lon"],
                             "heading": round(h, 1), "pitch": round(p, 1), "fov": f,
                             "dist_m": round(d_true, 1), "license": g.LIC})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="+")
    ap.add_argument("--max", type=int, default=8)
    ap.add_argument("--zoom", action="store_true", help="also a tight view of the nearest wall (signs)")
    a = ap.parse_args()
    k = g.key()
    meta = g.Meta(OUT / "metadata_cache.json")
    allrows = []
    for bid in a.ids:
        rows = views_for(bid, k, meta, a.max, a.zoom)
        allrows += rows
        print(bid, len(rows), "views")
    meta.flush()
    new = not LOG.exists()
    with open(LOG, "a", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["objectid", "role", "path", "pano_id", "date", "lat", "lon",
                                           "heading", "pitch", "fov", "dist_m", "license"])
        if new:
            w.writeheader()
        w.writerows(allrows)
    print("billed images", g.counters["img"], "metadata", g.counters["meta"], "fail", g.counters["fail"])


if __name__ == "__main__":
    main()
