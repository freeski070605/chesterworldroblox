"""Download the best Mapillary frame facing each Chester City building (CC BY-SA 4.0).

Needs $env:MAPILLARY_TOKEN. Uses a city catalog built by tiled bbox queries
(cached in Data/24_BuildingImagery_Mapillary/catalog.json). For every building
in regional_buildings_base inside Chester City, picks frames within --radius m
whose camera heading points at the footprint, keeps up to --per views from
distinct sequences, downloads them, and writes manifest.csv keyed by OBJECTID
(the BuildingTiles id). Non-destructive; resumable.

    py -3 tools/storefronts/mapillary_buildings.py catalog
    py -3 tools/storefronts/mapillary_buildings.py download [--per 2] [--radius 30]
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402

OUT = s.DATA / "24_BuildingImagery_Mapillary"
FIELDS = "id,captured_at,computed_geometry,compass_angle,camera_type,sequence,thumb_2048_url,creator"


def token():
    t = os.environ.get("MAPILLARY_TOKEN") or os.environ.get("MAPILLARY_ACCESS_TOKEN")
    if not t:
        raise SystemExit("set $env:MAPILLARY_TOKEN first")
    return t


def cmd_catalog(a):
    from shapely.geometry import Point, box
    t = token()
    cityb = s.city_polygon().buffer(0.002)
    seen = {}

    def q(w, so, e, n, depth=0):
        if not cityb.intersects(box(w, so, e, n)):
            return
        for attempt in range(3):
            try:
                d = s.http(s.MAPILLARY, {"access_token": t, "bbox": f"{w},{so},{e},{n}", "limit": 2000, "fields": FIELDS}, timeout=90)
                break
            except Exception as exc:
                if attempt == 2:
                    s.log("tile failed", w, so, str(exc)[:80])
                    return
                time.sleep(3)
        data = d.get("data", [])
        if len(data) >= 2000 and depth < 6:
            mx, my = (w + e) / 2, (so + n) / 2
            for bb in ((w, so, mx, my), (mx, so, e, my), (w, my, mx, n), (mx, my, e, n)):
                q(*bb, depth=depth + 1)
            return
        for p in data:
            g = (p.get("computed_geometry") or {}).get("coordinates")
            if g and cityb.contains(Point(g[0], g[1])):
                seen[p["id"]] = p
        time.sleep(0.15)

    step = 0.0025  # small tiles: Mapillary bbox results are unreliable on large boxes
    lat = 39.825
    while lat < 39.875:
        lon = -75.425
        while lon < -75.335:
            q(lon, lat, lon + step, lat + step)
            lon += step
        lat += step
    s.save(OUT / "catalog.json", {"fetched": time.strftime("%Y-%m-%d %H:%M"), "photos": list(seen.values())})
    s.log(f"catalog: {len(seen)} frames in/near Chester City")


def cmd_download(a):
    import pyproj
    from shapely.geometry import Point, shape
    from shapely.ops import transform
    from shapely.strtree import STRtree
    cat = s.load(OUT / "catalog.json")
    if not cat:
        raise SystemExit("run catalog first")
    tm = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    photos = [p for p in cat["photos"] if p.get("thumb_2048_url") and p.get("compass_angle") is not None]
    pts = [Point(tm(*p["computed_geometry"]["coordinates"])) for p in photos]
    tree = STRtree(pts)
    city = transform(tm, s.city_polygon())
    rows, todo = [], []
    for f in s.load(s.BUILDINGS)["features"]:
        g = transform(tm, shape(f["geometry"]))
        if not city.contains(g.centroid):
            continue
        bp = f["properties"]
        clon, clat = bp.get("center_lon"), bp.get("center_lat")
        cands = []
        for i in tree.query(g.buffer(a.radius)):
            p = photos[i]
            d = g.distance(pts[i])
            if d > a.radius or d < 1:
                continue
            lon, lat = p["computed_geometry"]["coordinates"]
            off = abs(s.adiff(p["compass_angle"], s.bearing(lat, lon, clat, clon)))
            if off > a.max_offset:
                continue
            cands.append((d + off * 0.3, d, off, p))
        cands.sort(key=lambda c: c[0])
        used = set()
        for score, d, off, p in cands:
            if len(used) >= a.per:
                break
            if p.get("sequence") in used:
                continue
            used.add(p.get("sequence"))
            lon, lat = p["computed_geometry"]["coordinates"]
            dest = OUT / "images" / str(bp["OBJECTID"]) / f"mapillary_{p['id']}.jpg"
            ts = p.get("captured_at")
            row = {"objectid": str(bp["OBJECTID"]), "master_id": bp.get("master_id"), "archetype": bp.get("generator_archetype"),
                   "building_address": bp.get("address") or bp.get("site_address") or "", "photo_id": p["id"],
                   "path": str(dest.relative_to(OUT)), "camera_lat": lat, "camera_lon": lon,
                   "camera_heading_deg": round(p["compass_angle"], 1), "facing_offset_deg": round(off, 1),
                   "distance_m": round(d, 1), "camera_type": p.get("camera_type"),
                   "capture_date": time.strftime("%Y-%m-%d", time.gmtime(ts / 1000)) if ts else "",
                   "contributor": (p.get("creator") or {}).get("username", ""), "sequence": p.get("sequence"),
                   "source_page": f"https://www.mapillary.com/app/?pKey={p['id']}",
                   "license": "CC BY-SA 4.0 - Mapillary contributors", "review_status": "unverified_view_of_building"}
            rows.append(row)
            if not dest.exists():
                todo.append((p["thumb_2048_url"], dest))
    s.log(f"buildings with a facing frame: {len({r['objectid'] for r in rows})}; images {len(rows)}; to download {len(todo)}")
    got = fail = 0
    for n, (url, dest) in enumerate(todo[: a.limit], 1):
        try:
            body, ctype = s.http(url, raw=True, timeout=60)
            if not (ctype.startswith("image/") or body[:2] == b"\xff\xd8"):
                raise ValueError("not an image")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
            got += 1
        except Exception as exc:
            fail += 1
            if fail <= 5:
                s.log("  failed", dest.name, str(exc)[:80])
        if n % 100 == 0:
            s.log(f"  {n}/{min(len(todo), a.limit)} ok={got} failed={fail}")
        time.sleep(a.delay)
    rows = [r for r in rows if (OUT / r["path"]).exists()]
    if rows:
        s.write_csv(OUT / "manifest.csv", rows, list(rows[0]))
    s.save(OUT / "summary.json", {"buildings_with_images": len({r["objectid"] for r in rows}), "images": len(rows),
                                  "radius_m": a.radius, "max_offset_deg": a.max_offset, "per_building": a.per})
    s.log(f"downloaded {got}, failed {fail}; manifest rows {len(rows)} -> {OUT / 'manifest.csv'}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["catalog", "download"])
    ap.add_argument("--radius", type=float, default=30)
    ap.add_argument("--max-offset", type=float, default=50)
    ap.add_argument("--per", type=int, default=2)
    ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--delay", type=float, default=0.1)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    {"catalog": cmd_catalog, "download": cmd_download}[a.command](a)


if __name__ == "__main__":
    main()
