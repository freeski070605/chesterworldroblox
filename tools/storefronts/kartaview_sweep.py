"""Citywide KartaView street-imagery sweep for ChesterWorld (CC BY-SA 4.0).

Grids the Chester City polygon (plus a buffer for bridge approaches), catalogs
every KartaView frame, thins each sequence to one frame per --spacing metres,
downloads them and tags each with the nearest road and highway structure.

    py -3 tools/storefronts/kartaview_sweep.py catalog
    py -3 tools/storefronts/kartaview_sweep.py download [--spacing 15] [--limit N]
    py -3 tools/storefronts/kartaview_sweep.py index

Output: E:\\ChesterWorld\\Data\\23_StreetImagery_KartaView (resumable, non-destructive).
"""
import argparse
import csv
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402

OUT = s.DATA / "23_StreetImagery_KartaView"
LICENSE = "CC BY-SA 4.0 - KartaView contributors (attribute contributor + KartaView)"


def grid_points(step_m, buffer_m):
    import pyproj
    from shapely.ops import transform
    to_m = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    to_ll = pyproj.Transformer.from_crs(32618, 4326, always_xy=True).transform
    area = transform(to_m, s.city_polygon()).buffer(buffer_m)
    from shapely.geometry import Point
    x0, y0, x1, y1 = area.bounds
    pts = []
    y = y0
    while y <= y1:
        x = x0
        while x <= x1:
            if area.contains(Point(x, y)):
                lon, lat = to_ll(x, y)
                pts.append((lat, lon))
            x += step_m
        y += step_m
    return pts, area, to_m


def query(lat, lon, radius):
    for attempt in range(4):
        try:
            d = s.http(s.KARTA, {"lat": f"{lat:.7f}", "lng": f"{lon:.7f}", "radius": radius,
                                 "itemsPerPage": 150, "page": 1}, timeout=45)
            st = d.get("status") or {}
            if str(st.get("apiCode")) != "600":
                raise RuntimeError(st.get("apiMessage"))
            return (d.get("result") or {}).get("data") or []
        except Exception as exc:
            if "429" in str(exc):
                s.log("rate limited; sleeping 120 s")
                time.sleep(120)
            elif attempt == 3:
                s.log("query failed", lat, lon, str(exc)[:100])
                return []
            else:
                time.sleep(3 * (attempt + 1))
    return []


def cmd_catalog(a):
    pts, area, to_m = grid_points(a.step, a.buffer)
    cat_p = OUT / "catalog.json"
    cat = s.load(cat_p, {"photos": {}, "done": []})
    done = set(cat["done"])
    s.log(f"grid points {len(pts)} (step {a.step} m, radius {a.radius} m); already queried {len(done)}")
    from shapely.geometry import Point
    for n, (lat, lon) in enumerate(pts, 1):
        key = f"{lat:.6f},{lon:.6f}"
        if key in done:
            continue
        for p in query(lat, lon, a.radius):
            if not (p.get("storage") and p.get("filepathProc") and p.get("lat")):
                continue
            pla, plo = float(p["lat"]), float(p["lng"])
            if not area.contains(Point(to_m(plo, pla))):
                continue
            cat["photos"][str(p["id"])] = {
                "id": str(p["id"]), "sequence": str(p.get("sequenceId")), "seq_index": int(p.get("sequenceIndex") or 0),
                "lat": pla, "lon": plo, "heading": float(p["heading"]) if p.get("heading") not in (None, "") else None,
                "date": (p.get("shotDate") or p.get("dateAdded") or "")[:19],
                "projection": (p.get("projection") or "").upper(), "fov": p.get("fieldOfView"),
                "width": p.get("width"), "height": p.get("height"), "way_id": p.get("wayId"),
                "url": f"https://{p['storage']}.openstreetcam.org/files/photo/{p['filepathProc']}",
                "page": f"https://kartaview.org/details/{p.get('sequenceId')}/{p.get('sequenceIndex')}/track-info"}
        done.add(key)
        cat["done"] = sorted(done)
        if n % 25 == 0:
            s.save(cat_p, cat)
            s.log(f"  {n}/{len(pts)} points, {len(cat['photos'])} unique photos")
        time.sleep(a.delay)
    s.save(cat_p, cat)
    seqs = {}
    for p in cat["photos"].values():
        seqs.setdefault(p["sequence"], []).append(p)
    s.log(f"catalog: {len(cat['photos'])} unique photos in {len(seqs)} sequences")
    for sq, ps in sorted(seqs.items(), key=lambda kv: -len(kv[1]))[:30]:
        s.log(f"  seq {sq:>8} {ps[0]['date'][:10]} n={len(ps)} proj={ps[0]['projection']}")


def thinned(photos, spacing):
    seqs = {}
    for p in photos.values():
        seqs.setdefault(p["sequence"], []).append(p)
    keep = []
    for ps in seqs.values():
        ps.sort(key=lambda p: p["seq_index"])
        last = None
        for p in ps:
            if last is None or s.dist_m(last["lat"], last["lon"], p["lat"], p["lon"]) >= spacing or p["projection"] == "SPHERE":
                keep.append(p)
                last = p
    return keep


def cmd_download(a):
    cat = s.load(OUT / "catalog.json")
    if not cat:
        raise SystemExit("run catalog first")
    keep = thinned(cat["photos"], a.spacing)
    todo = [p for p in keep if not (OUT / "images" / p["sequence"] / f"{p['seq_index']:05d}_{p['id']}.jpg").exists()]
    s.log(f"thinned to {len(keep)} frames at {a.spacing} m; to download {len(todo)}; this run {min(len(todo), a.limit)}")
    got = fail = 0
    for n, p in enumerate(todo[: a.limit], 1):
        dest = OUT / "images" / p["sequence"] / f"{p['seq_index']:05d}_{p['id']}.jpg"
        try:
            body, ctype = s.http(p["url"], raw=True, timeout=60)
            if not (ctype.startswith("image/") or body[:2] == b"\xff\xd8"):
                raise ValueError("not an image")
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp = dest.with_suffix(".part")
            tmp.write_bytes(body)
            tmp.replace(dest)
            got += 1
        except Exception as exc:
            fail += 1
            if fail <= 10:
                s.log("  failed", p["id"], str(exc)[:80])
        if n % 50 == 0:
            s.log(f"  {n}/{min(len(todo), a.limit)} downloaded={got} failed={fail}")
        time.sleep(a.delay)
    s.log(f"download done: {got} new, {fail} failed")
    cmd_index(a)


def cmd_index(a):
    import pyproj
    from shapely.geometry import shape, Point
    from shapely.ops import transform
    from shapely.strtree import STRtree
    cat = s.load(OUT / "catalog.json")
    to_m = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    roads = []
    for f in s.load(s.ROADS)["features"]:
        p = f["properties"]
        if not f.get("geometry"):
            continue
        nm = " ".join(x for x in (p.get("St_PreDir"), p.get("St_Name"), p.get("St_PosTyp"), p.get("St_PosDir")) if x)
        roads.append((nm, transform(to_m, shape(f["geometry"]))))
    tree = STRtree([g for _, g in roads])
    structs = []
    with (s.DATA / "HighwayReference" / "crossings.csv").open(encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            if r.get("latitude"):
                structs.append((r["id"], float(r["latitude"]), float(r["longitude"])))
    rows = []
    for p in cat["photos"].values():
        path = OUT / "images" / p["sequence"] / f"{p['seq_index']:05d}_{p['id']}.jpg"
        if not path.exists():
            continue
        pt = Point(to_m(p["lon"], p["lat"]))
        idx = tree.query(pt.buffer(30))
        road = min(idx, key=lambda i: roads[i][1].distance(pt)) if len(idx) else None
        near = min(structs, key=lambda t: s.dist_m(p["lat"], p["lon"], t[1], t[2])) if structs else None
        nd = s.dist_m(p["lat"], p["lon"], near[1], near[2]) if near else None
        sx, sz = s.studs(p["lon"], p["lat"])
        rows.append({**{k: p[k] for k in ("id", "sequence", "seq_index", "lat", "lon", "heading", "date", "projection", "url", "page")},
                     "path": str(path.relative_to(OUT)), "studs_x": sx, "studs_z": sz,
                     "road": roads[road][0] if road is not None else "", "is_360": p["projection"] == "SPHERE",
                     "nearest_structure": near[0] if near and nd <= 300 else "",
                     "structure_distance_m": round(nd, 1) if near and nd <= 300 else "", "license": LICENSE})
    rows.sort(key=lambda r: (r["sequence"], r["seq_index"]))
    if rows:
        s.write_csv(OUT / "manifest.csv", rows, list(rows[0]))
    s.save(OUT / "manifest.geojson", {"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "Point", "coordinates": [r["lon"], r["lat"]]}, "properties": r} for r in rows]})
    from collections import Counter
    rc = Counter(r["road"] for r in rows)
    sc = Counter(r["nearest_structure"] for r in rows if r["nearest_structure"])
    s.log(f"indexed {len(rows)} downloaded frames; 360={sum(r['is_360'] for r in rows)}")
    s.log("top roads: " + ", ".join(f"{k or '?'}={v}" for k, v in rc.most_common(15)))
    s.log("near structures: " + ", ".join(f"{k}={v}" for k, v in sc.most_common()))
    s.save(OUT / "summary.json", {"frames": len(rows), "roads": rc.most_common(), "structures": sc.most_common(),
                                  "license": LICENSE, "source": "KartaView api.kartaview.org 2.0"})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["catalog", "download", "index"])
    ap.add_argument("--step", type=float, default=110)
    ap.add_argument("--radius", type=int, default=80)
    ap.add_argument("--buffer", type=float, default=250)
    ap.add_argument("--spacing", type=float, default=15)
    ap.add_argument("--limit", type=int, default=100000)
    ap.add_argument("--delay", type=float, default=0.5)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    {"catalog": cmd_catalog, "download": cmd_download, "index": cmd_index}[a.command](a)


if __name__ == "__main__":
    main()
