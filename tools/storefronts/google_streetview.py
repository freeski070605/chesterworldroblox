"""Google Street View Static captures for ChesterWorld stores and buildings.

Uses GOOGLE_MAPS_API_KEY (env or E:\\ChesterWorld\\ChesterWorldMapData\\.env).
Metadata calls are free; each saved image is one billed Static request.
Images are (c) Google, Google Maps Platform Terms: private modelling reference
only - do not redistribute or publish. The key is never written to any output.

    py -3 tools/storefronts/google_streetview.py stores      # 65 stores: 4 views + 6-face cubemap
    py -3 tools/storefronts/google_streetview.py buildings [--limit N] [--workers 8]

Stores  -> Data/10_StorefrontPanoramas/businesses/<group>/<store>/google_*.jpg (+ places.json imagery)
Buildings -> Data/25_GoogleStreetView_Buildings/images/<OBJECTID>/front.jpg + manifest.csv
"""
import argparse
import math
import re
import sys
import threading
import time
import urllib.error
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402

META = "https://maps.googleapis.com/maps/api/streetview/metadata"
IMG = "https://maps.googleapis.com/maps/api/streetview"
LIC = "(c) Google - Google Maps Platform Terms; private reference only, do not redistribute"
OUT_B = s.DATA / "25_GoogleStreetView_Buildings"
STORE_OUT = s.OUT_DEFAULT
lock = threading.Lock()
counters = {"meta": 0, "img": 0, "fail": 0}


def key():
    k = s.secret("GOOGLE_MAPS_API_KEY")
    if not k:
        raise SystemExit("GOOGLE_MAPS_API_KEY not found")
    return k


class Meta:
    def __init__(self, path):
        self.path = path
        self.cache = s.load(path, {})

    def get(self, lat, lon, radius, k):
        ck = f"{lat:.6f},{lon:.6f},{radius}"
        if ck in self.cache:
            return self.cache[ck]
        for attempt in range(4):
            try:
                d = s.http(META, {"location": f"{lat},{lon}", "radius": radius, "source": "outdoor", "key": k}, timeout=30)
                break
            except Exception:
                time.sleep(2 * (attempt + 1))
        else:
            return None
        v = None
        if d.get("status") == "OK":
            v = {"pano_id": d["pano_id"], "lat": d["location"]["lat"], "lon": d["location"]["lng"],
                 "date": d.get("date", ""), "copyright": d.get("copyright", "")}
        with lock:
            self.cache[ck] = v
            counters["meta"] += 1
        return v

    def flush(self):
        with lock:
            s.save(self.path, self.cache)


def fetch(pano, heading, pitch, fov, dest, k):
    if dest.exists():
        return True
    params = {"size": "640x640", "pano": pano, "heading": f"{heading:.1f}", "pitch": f"{pitch:.1f}",
              "fov": f"{fov:.0f}", "return_error_code": "true", "source": "outdoor", "key": k}
    for attempt in range(4):
        try:
            body, ctype = s.http(IMG, params, raw=True, timeout=45)
            if not ctype.startswith("image/"):
                raise ValueError("not image")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
            with lock:
                counters["img"] += 1
            return True
        except urllib.error.HTTPError as exc:
            if exc.code in (403, 400):
                raise SystemExit(f"Static API refused ({exc.code}) - check key / API enabled / billing")
            if exc.code == 404:
                break
            time.sleep(2 * (attempt + 1))
        except Exception:
            time.sleep(2 * (attempt + 1))
    with lock:
        counters["fail"] += 1
    return False


def public_url(pano, heading, pitch, fov):  # no key
    return f"{IMG}?size=640x640&pano={pano}&heading={heading:.1f}&pitch={pitch:.1f}&fov={fov:.0f}"


# --------------------------------------------------------------- road geometry
def road_index():
    import pyproj
    from shapely.geometry import shape
    from shapely.ops import transform
    from shapely.strtree import STRtree
    tm = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    tl = pyproj.Transformer.from_crs(32618, 4326, always_xy=True).transform
    roads = []
    for f in s.load(s.ROADS)["features"]:
        p = f["properties"]
        if not f.get("geometry") or re.match(r"I ?95|I ?476|US ?322 ?Hwy", p.get("St_Name") or ""):
            continue
        if "ramp" in (p.get("RoadClass") or "").lower():
            continue
        nm = " ".join(x for x in (p.get("St_PreDir"), p.get("St_Name"), p.get("St_PosTyp")) if x)
        roads.append((nm, transform(tm, shape(f["geometry"]))))
    return roads, STRtree([g for _, g in roads]), tm, tl


def frontage(pt, roads, tree, maxd=70):
    idx = tree.query(pt.buffer(maxd))
    if not len(idx):
        return None
    i = min(idx, key=lambda j: roads[j][1].distance(pt))
    return roads[i]


def capture_params(pano, target_lat, target_lon, width_m, height_m):
    d = max(4.0, s.dist_m(pano["lat"], pano["lon"], target_lat, target_lon))
    heading = s.bearing(pano["lat"], pano["lon"], target_lat, target_lon)
    fov = max(35.0, min(100.0, math.degrees(2 * math.atan((width_m / 2 + 3) / d))))
    pitch = max(0.0, min(25.0, math.degrees(math.atan(((height_m or 7) / 2 - 2.5) / d))))
    return heading, pitch, fov, d


# --------------------------------------------------------------- stores
def cmd_stores(a):
    from shapely.geometry import Point
    from shapely.ops import nearest_points
    k = key()
    meta = Meta(STORE_OUT / "sources" / "google_metadata_cache.json")
    roads, tree, tm, tl = road_index()
    places = s.load(STORE_OUT / "places.json")
    for n, p in enumerate(places, 1):
        folder = s.site_dir(STORE_OUT, p)
        b = (p.get("match") or {}).get("building") or {}
        h = b.get("height_m") or 7
        w = min(40, math.sqrt(b.get("footprint_m2") or 150) * 1.3)
        pt = Point(tm(p["lon"], p["lat"]))
        fr = frontage(pt, roads, tree)
        views = []
        if fr:
            line = fr[1]
            m = line.project(pt)
            for role, off in (("front", 0), ("left_approach", -25), ("right_approach", 25),
                              ("opposite_corner", -45), ("opposite_corner", 45)):
                q = line.interpolate(min(max(m + off, 0), line.length))
                lon, lat = tl(q.x, q.y)
                views.append((role, lat, lon))
        else:
            views.append(("front", p["lat"], p["lon"]))
        imgs = [i for i in p.get("imagery") or [] if i["source"] != "GoogleStreetView"]
        used, roles = set(), set()
        for role, lat, lon in views:
            if role in roles and role != "opposite_corner":
                continue
            if role == "opposite_corner" and "opposite_corner" in roles:
                continue
            md = meta.get(lat, lon, 30, k)
            if not md or md["pano_id"] in used:
                continue
            heading, pitch, fov, d = capture_params(md, p["lat"], p["lon"], w, h)
            if d > 90:
                continue
            dest = folder / f"google_{role}_{md['pano_id']}.jpg"
            if fetch(md["pano_id"], heading, pitch, fov, dest, k):
                used.add(md["pano_id"])
                roles.add(role)
                imgs.append(img_rec(dest, md, heading, pitch, fov, d, role, False))
        # full 360 coverage: 6 cube faces of the nearest pano to the storefront
        md = meta.get(p["lat"], p["lon"], 60, k)
        if md:
            faces = [("F", 0, 0), ("R", 90, 0), ("B", 180, 0), ("L", 270, 0), ("U", 0, 90), ("D", 0, -90)]
            base = s.bearing(md["lat"], md["lon"], p["lat"], p["lon"])
            ok = 0
            for name, dh, pitch in faces:
                hd = (base + dh) % 360
                dest = folder / "google_cubemap" / f"{name}_{md['pano_id']}.jpg"
                if fetch(md["pano_id"], hd, pitch, 90, dest, k):
                    ok += 1
            if ok == 6:
                rec = img_rec(folder / "google_cubemap" / f"F_{md['pano_id']}.jpg", md, base, 0, 90,
                              s.dist_m(md["lat"], md["lon"], p["lat"], p["lon"]), "360_cubemap", True)
                rec["note"] = "6 cube faces (F/R/B/L/U/D, fov 90) from one Google 360 pano; F faces the storefront"
                rec["path"] = str((folder / "google_cubemap").relative_to(STORE_OUT))
                imgs.append(rec)
        p["imagery"] = imgs
        p["imagery_status"] = s.imagery_status(p)
        s.log(f"[{n}/{len(places)}] {p['name'][:32]:32} google views={sum(i['source']=='GoogleStreetView' for i in imgs)} -> {p['imagery_status']}")
        if n % 10 == 0:
            meta.flush()
            s.save(STORE_OUT / "places.json", places)
    meta.flush()
    s.save(STORE_OUT / "places.json", places)
    s.write_index(STORE_OUT, places)
    s.log(f"stores done; static images fetched this run {counters['img']}, failed {counters['fail']}, metadata calls {counters['meta']}")


def img_rec(dest, md, heading, pitch, fov, d, role, is360):
    return {"path": str(dest.relative_to(STORE_OUT)), "source": "GoogleStreetView", "source_id": md["pano_id"],
            "source_url": public_url(md["pano_id"], heading, pitch, fov),
            "source_page": f"https://www.google.com/maps/@?api=1&map_action=pano&pano={md['pano_id']}&heading={heading:.0f}",
            "license": LIC, "contributor": md.get("copyright", ""), "capture_date": md.get("date", ""),
            "camera_lat": md["lat"], "camera_lon": md["lon"], "camera_heading_deg": round(heading, 1),
            "camera_pitch_deg": round(pitch, 1), "fov_deg": round(fov), "is_360_panorama": is360,
            "projection": "cubemap_6x90" if is360 else "perspective", "view_role": role,
            "distance_m": round(d, 1), "facing_offset_deg": 0.0, "review_status": "unverified_storefront_view"}


# --------------------------------------------------------------- buildings
def cmd_buildings(a):
    from shapely.geometry import shape
    from shapely.ops import transform, nearest_points
    k = key()
    meta = Meta(OUT_B / "metadata_cache.json")
    roads, tree, tm, tl = road_index()
    city = transform(tm, s.city_polygon())
    jobs = []
    for f in s.load(s.BUILDINGS)["features"]:
        bp = f["properties"]
        g = transform(tm, shape(f["geometry"]))
        c = g.centroid
        if not city.contains(c) or g.area < a.min_area:
            continue
        jobs.append((bp, g))
    jobs.sort(key=lambda j: str(j[0]["OBJECTID"]))
    s.log(f"buildings in Chester City >= {a.min_area} m2: {len(jobs)}; this run {min(len(jobs), a.limit)}")
    rows = s.load(OUT_B / "manifest.json", {})

    def work(job):
        bp, g = job
        oid = str(bp["OBJECTID"])
        if oid in rows and (OUT_B / rows[oid]["path"]).exists():
            return
        fr = frontage(g.centroid, roads, tree, 90)
        if not fr:
            rows[oid] = {"objectid": oid, "status": "no_road_within_90m"}
            return
        q = nearest_points(fr[1], g)[0]
        lon, lat = tl(q.x, q.y)
        md = meta.get(lat, lon, 35, k)
        if not md:
            rows[oid] = {"objectid": oid, "status": "no_google_pano", "road": fr[0]}
            return
        face = nearest_points(g, q)[0]  # aim at the footprint edge facing the street, nudged inward
        clon, clat = tl(*g.centroid.coords[0])
        flon, flat = tl(face.x, face.y)
        tlat, tlon = flat * 0.6 + clat * 0.4, flon * 0.6 + clon * 0.4
        rect = g.minimum_rotated_rectangle.exterior.coords
        sides = sorted(math.dist(rect[i], rect[i + 1]) for i in range(4))
        width = min(45, sides[-1])
        heading, pitch, fov, d = capture_params(md, tlat, tlon, width, bp.get("height_m"))
        if d > 110:
            rows[oid] = {"objectid": oid, "status": "pano_too_far", "distance_m": round(d, 1)}
            return
        dest = OUT_B / "images" / oid / f"front_{md['pano_id']}.jpg"
        ok = fetch(md["pano_id"], heading, pitch, fov, dest, k)
        rows[oid] = {"objectid": oid, "master_id": bp.get("master_id"), "status": "ok" if ok else "image_failed",
                     "path": str(dest.relative_to(OUT_B)), "archetype": bp.get("generator_archetype"),
                     "height_m": bp.get("height_m"), "floors": bp.get("estimated_floors"),
                     "address": bp.get("address") or bp.get("site_address") or "", "road": fr[0],
                     "pano_id": md["pano_id"], "capture_date": md["date"], "camera_lat": md["lat"], "camera_lon": md["lon"],
                     "camera_heading_deg": round(heading, 1), "pitch_deg": round(pitch, 1), "fov_deg": round(fov),
                     "distance_m": round(d, 1), "studs": s.studs(clon, clat),
                     "source_url": public_url(md["pano_id"], heading, pitch, fov), "license": LIC,
                     "review_status": "unverified_view_of_building"}

    done = 0
    batch = jobs[: a.limit]
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i in range(0, len(batch), 200):
            list(ex.map(work, batch[i:i + 200]))
            done += len(batch[i:i + 200])
            meta.flush()
            s.save(OUT_B / "manifest.json", rows)
            s.log(f"  {done}/{len(batch)}  images={counters['img']} failed={counters['fail']} meta={counters['meta']}")
    s.save(OUT_B / "manifest.json", rows)
    ok = [r for r in rows.values() if r.get("status") == "ok"]
    if ok:
        s.write_csv(OUT_B / "manifest.csv", ok, list(ok[0]))
    from collections import Counter
    st = Counter(r.get("status") for r in rows.values())
    s.save(OUT_B / "summary.json", {"buildings_considered": len(jobs), "status": st, "license": LIC})
    s.log(f"buildings: {dict(st)}; static images this run {counters['img']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["stores", "buildings"])
    ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--min-area", type=float, default=30)
    a = ap.parse_args()
    OUT_B.mkdir(parents=True, exist_ok=True)
    {"stores": cmd_stores, "buildings": cmd_buildings}[a.command](a)


if __name__ == "__main__":
    main()
