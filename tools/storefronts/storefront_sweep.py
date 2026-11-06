"""ChesterWorld citywide storefront / gas-station reference sweep.

Re-implementation of the ChesterWorld_Storefront_Panorama_Sweep toolkit workflow
(inventory -> scan -> collect -> match -> index) with broader sources and
fixed endpoints. Writes ONLY under E:\\ChesterWorld\\Data\\10_StorefrontPanoramas
(or --out); never touches source GIS, tiles, terrain or the Roblox place.

    py -3 tools/storefronts/storefront_sweep.py inventory
    py -3 tools/storefronts/storefront_sweep.py scan
    py -3 tools/storefronts/storefront_sweep.py collect --limit 35   (repeat / --limit 999)
    py -3 tools/storefronts/storefront_sweep.py match
    py -3 tools/storefronts/storefront_sweep.py index
    py -3 tools/storefronts/storefront_sweep.py sites --kind structures   (bridges/highway crossings)

Sources and licences
  OpenStreetMap via Overpass ............ ODbL, (c) OpenStreetMap contributors
  Overture Maps Places (S3 release) ..... CDLA-Permissive-2.0
  US Census geocoder (seed addresses) ... public domain, TIGER interpolated
  Delaware County parcels (public svc) .. county public-access GIS
  KartaView street imagery .............. CC BY-SA 4.0
  Mapillary (only if MAPILLARY_TOKEN) ... CC BY-SA 4.0
  Google Street View METADATA only ...... no imagery downloaded; (c) Google
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import html
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CW = Path(r"E:\ChesterWorld")
DATA = CW / "Data"
OUT_DEFAULT = DATA / "10_StorefrontPanoramas"
SEEDS = CW / "StorefrontSweepTools" / "seed_chester_businesses.csv"
KERLIN = CW / "ChesterWorldMapData" / "KerlinPrototype"
ENV_FILE = CW / "ChesterWorldMapData" / ".env"
BOUNDARY = DATA / "00_Boundary" / "chester_world_boundary.geojson"
BUILDINGS = DATA / "13_RegionalMaster" / "regional_buildings_base.geojson"
ROADS = DATA / "02_Roads" / "delco_roads.geojson"
KERLIN_PARCELS = KERLIN / "01_CorridorGIS" / "kerlin_parcels.geojson"
BUILDING_TILES = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"

UA = "ChesterWorldResearchSweep/1.1 (local archival research; low volume)"
OVERPASS = ("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")
OVERTURE_RELEASE = "2026-10-21.0"
CENSUS = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress"
KARTA = "https://api.kartaview.org/2.0/photo/"
MAPILLARY = "https://graph.mapillary.com/images"
GSV_META = "https://maps.googleapis.com/maps/api/streetview/metadata"
DELCO_PARCELS = "https://gis.delcopa.gov/arcgis/rest/services/Parcels/Parcels_Public_Access/FeatureServer/0/query"
BBOX = (39.82, -75.43, 39.88, -75.33)  # s, w, n, e  (selection only; clipped to city polygon)

LIC = {
    "OSM": "ODbL 1.0 - (c) OpenStreetMap contributors",
    "Overture": "CDLA-Permissive-2.0 - Overture Maps Foundation",
    "Census": "Public domain - US Census Bureau TIGER (interpolated)",
    "KartaView": "CC BY-SA 4.0 - KartaView contributors (attribute contributor + KartaView)",
    "Mapillary": "CC BY-SA 4.0 - Mapillary contributors",
    "GoogleStreetView": "(c) Google - Google Maps Platform Terms; reference only, not redistributable",
}

OSM_SHOPS = {"convenience": "corner_store", "general": "corner_store", "kiosk": "corner_store",
             "newsagent": "corner_store", "deli": "deli", "grocery": "market", "supermarket": "market",
             "greengrocer": "market", "butcher": "market", "food": "market"}
OV_TAXA = {"convenience_store": "corner_store", "gas_station": "gas_station", "fueling_station": "gas_station",
           "grocery_store": "market", "delicatessen": "deli", "supermarket": "market",
           "international_grocery_store": "market", "asian_grocery_store": "market",
           "health_food_store": "market"}
OUT_OF_SCOPE = re.compile(r"rite aid|\bcvs\b|walgreens|dollar tree|family dollar|dollar general|check cashing|wireless|amazon locker", re.I)
NAME_STORE = re.compile(r"\b(deli|market|mart|grocery|groceries|food store|bodega|supermarket|mini ?mart|convenience)\b", re.I)


def log(*a):
    print("[ChesterWorld Storefronts]", *a, flush=True)


# ------------------------------------------------------------------ io helpers
def load(path, default=None):
    path = Path(path)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def save(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False, default=str), encoding="utf-8")
    tmp.replace(path)


def write_csv(path, rows, fields):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as fd:
        w = csv.DictWriter(fd, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: (json.dumps(v) if isinstance(v, (list, dict)) else v) for k, v in r.items()})


def http(url, params=None, form=None, timeout=60, raw=False, max_bytes=20_000_000):
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    data = urllib.parse.urlencode(form).encode() if form is not None else None
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read(max_bytes + 1)
        if len(body) > max_bytes:
            raise ValueError("response too large")
        return (body, r.headers.get("Content-Type", "")) if raw else json.loads(body.decode("utf-8"))


def secret(name):
    if os.environ.get(name):
        return os.environ[name].strip()
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8", errors="ignore").splitlines():
            k, _, v = line.partition("=")
            if k.strip() == name:
                return v.strip().strip('"').strip("'")
    return ""


# ------------------------------------------------------------------ geometry
def dist_m(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(a)))


def bearing(lat1, lon1, lat2, lon2):
    y = math.sin(math.radians(lon2 - lon1)) * math.cos(math.radians(lat2))
    x = (math.cos(math.radians(lat1)) * math.sin(math.radians(lat2))
         - math.sin(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.cos(math.radians(lon2 - lon1)))
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def adiff(a, b):  # signed a-b in (-180, 180]
    return (a - b + 180) % 360 - 180


def studs(lon, lat):  # identical to tools/build_landmarks.py
    mx = lon * 20037508.34 / 180.0
    my = math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0
    return round((mx + 8397592 - 6347.889) * 3, 1), round(-(my - 4837229 - 7201.973) * 3, 1)


def city_polygon():
    from shapely.geometry import shape
    fc = load(BOUNDARY)
    for f in fc["features"]:
        if f["properties"].get("Muni") == "Chester City":
            return shape(f["geometry"]).buffer(0)
    raise RuntimeError("Chester City polygon not found in " + str(BOUNDARY))


# ------------------------------------------------------------------ normalisation
ABBR = {"street": "st", "avenue": "ave", "av": "ave", "road": "rd", "boulevard": "blvd", "drive": "dr",
        "west": "w", "east": "e", "north": "n", "south": "s", "lane": "ln", "place": "pl", "highway": "hwy",
        "first": "1st", "second": "2nd", "third": "3rd", "fourth": "4th", "fifth": "5th", "sixth": "6th",
        "seventh": "7th", "eighth": "8th", "ninth": "9th", "tenth": "10th"}
NAME_STOP = {"the", "inc", "llc", "co", "corp", "and", "store", "shop", "of", "chester", "pa", "#"}


def norm_addr(a):
    a = (a or "").lower().split(",")[0]
    a = re.sub(r"[^a-z0-9 ]", " ", a)
    toks = [ABBR.get(t, t) for t in a.split()]
    toks = [t for t in toks if t not in ("w", "e", "n", "s")] if len(toks) > 2 else toks
    return " ".join(toks)


def addr_number(a):
    m = re.match(r"\s*(\d+)", a or "")
    return m.group(1) if m else ""


def norm_name(n):
    n = (n or "").lower().replace("&", " and ").replace("'", "")
    n = re.sub(r"[^a-z0-9 ]", " ", n)
    return " ".join(t for t in n.split() if t not in NAME_STOP)


def name_sim(a, b):
    a, b = norm_name(a), norm_name(b)
    if not a or not b:
        return 0.0
    ta, tb = set(a.split()), set(b.split())
    jac = len(ta & tb) / max(1, len(ta | tb))
    return max(jac, SequenceMatcher(None, a, b).ratio())


def generic_name(n):
    return not n or norm_name(n) in ("", "gas station", "corner unnamed", "convenience", "unnamed", "deli",
                                     "market", "food market", "mini market", "gas")


# ------------------------------------------------------------------ inventory sources
def src_osm(out):
    # bbox query (light on Overpass); results are clipped to the county Chester City polygon afterwards
    b = f"({BBOX[0]},{BBOX[1]},{BBOX[2]},{BBOX[3]})"
    q = f"""[out:json][timeout:120];
(
 nwr["amenity"="fuel"]{b};
 nwr["shop"~"^({'|'.join(OSM_SHOPS)})$"]{b};
);
out center tags;"""
    cache = out / "sources" / "osm_overpass_raw.json"
    data = None
    for ep in OVERPASS:
        try:
            log("Overpass:", ep)
            data = http(ep, form={"data": q}, timeout=200)
            break
        except Exception as exc:
            log("  failed:", str(exc)[:140])
    if data is None:
        data = load(cache)
        if data is None:
            log("  OSM unavailable and no cache; continuing without live OSM")
            return []
        log("  using cached Overpass result")
    else:
        save(cache, {**data, "query": q, "fetched": dt.datetime.now().isoformat(), "license": LIC["OSM"]})
    recs = []
    for el in data.get("elements", []):
        g = el if el["type"] == "node" else el.get("center") or {}
        if "lat" not in g:
            continue
        t = el.get("tags", {})
        cat = "gas_station" if t.get("amenity") == "fuel" else OSM_SHOPS.get(t.get("shop"), "corner_store")
        addr = " ".join(x for x in (t.get("addr:housenumber", ""), t.get("addr:street", "")) if x)
        recs.append(dict(source="OSM", source_id=f"osm/{el['type']}/{el['id']}", name=t.get("name") or t.get("brand") or "",
                         brand=t.get("brand", ""), address=addr, category=cat, lat=g["lat"], lon=g["lon"],
                         coord_quality="mapped_poi", license=LIC["OSM"], raw_type=t.get("shop") or t.get("amenity"),
                         has_shop=bool(t.get("shop")), operating="open"))
    log(f"  OSM live: {len(recs)}")
    return recs


def src_osm_local():
    recs = []
    for f in ("04_POI/osm_poi_points.geojson", "04_POI/osm_poi_areas.geojson"):
        fc = load(DATA / f, {"features": []})
        for ft in fc["features"]:
            p = ft["properties"]
            shop, amen = p.get("shop"), p.get("amenity")
            if amen != "fuel" and shop not in OSM_SHOPS:
                continue
            from shapely.geometry import shape
            c = shape(ft["geometry"]).representative_point()
            cat = "gas_station" if amen == "fuel" else OSM_SHOPS[shop]
            addr = " ".join(x for x in (p.get("addr:housenumber") or "", p.get("addr:street") or "") if x)
            recs.append(dict(source="OSM_local_2025snapshot", source_id=f"osm/{p.get('osm_type')}/{p.get('osm_id')}",
                             name=p.get("name") or p.get("brand") or "", brand=p.get("brand") or "", address=addr,
                             category=cat, lat=c.y, lon=c.x, coord_quality="mapped_poi", license=LIC["OSM"],
                             raw_type=shop or amen, has_shop=bool(shop), operating="open"))
    log(f"  OSM local snapshot (04_POI): {len(recs)}")
    return recs


def src_overture(out):
    pq = out / "sources" / f"overture_places_{OVERTURE_RELEASE}_chester_bbox.parquet"
    import duckdb
    con = duckdb.connect()
    if not pq.exists():
        log("Overture places: downloading bbox from S3 release", OVERTURE_RELEASE)
        con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
        pq.parent.mkdir(parents=True, exist_ok=True)
        con.execute(f"""copy (select *, (bbox.xmin+bbox.xmax)/2 lon, (bbox.ymin+bbox.ymax)/2 lat
            from read_parquet('s3://overturemaps-us-west-2/release/{OVERTURE_RELEASE}/theme=places/type=place/*', hive_partitioning=1)
            where bbox.xmin between {BBOX[1]} and {BBOX[3]} and bbox.ymin between {BBOX[0]} and {BBOX[2]})
            to '{pq.as_posix()}' (format parquet)""")
    rows = con.execute(f"""select id, names.primary, taxonomy.primary, basic_category, confidence, operating_status,
        addresses[1].freeform, brand.names.primary, lon, lat, sources[1].dataset from '{pq.as_posix()}'""").fetchall()
    recs, rejected = [], []
    for oid, name, taxo, basic, conf, status, addr, brand, lon, lat, ds in rows:
        cat = OV_TAXA.get(taxo) or OV_TAXA.get(basic)
        if not cat and name and taxo and (
                ("restaurant" in taxo and re.search(r"\bdeli\b|food market|mini ?market|grocery", name, re.I)) or
                (taxo in ("sandwich_shop", "butcher_shop", "shipping_or_delivery_service", "food_and_beverage_store",
                          "courier_and_delivery_service") and NAME_STORE.search(name))):
            cat = "deli" if re.search(r"\bdeli\b", name, re.I) else "market"
        if not cat:
            continue
        if cat == "market" and taxo == "grocery_store" and name and re.search(r"beverage|wholesale|distribut", name, re.I):
            continue
        rec = dict(source="Overture", source_id=f"overture/{oid}", name=name or "", brand=brand or "", address=addr or "",
                   category=cat, lat=lat, lon=lon, coord_quality=f"overture_conf_{(conf or 0):.2f}",
                   license=LIC["Overture"] + (f" (upstream: {ds})" if ds else ""), raw_type=taxo or basic,
                   has_shop=cat != "gas_station", operating=status or "unknown", confidence=conf)
        if status == "permanently_closed" or (conf or 0) < 0.45:
            rejected.append({**rec, "reject_reason": "permanently_closed" if status == "permanently_closed" else "low_confidence"})
        else:
            recs.append(rec)
    log(f"  Overture: {len(recs)} kept, {len(rejected)} rejected (closed / conf<0.45)")
    return recs, rejected


def src_seeds(out):
    cache_p = out / "sources" / "census_geocode_cache.json"
    cache = load(cache_p, {})
    recs = []
    if not SEEDS.exists():
        log("  seed CSV missing:", SEEDS)
        return recs
    with SEEDS.open(encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    for row in rows:
        addr = (row.get("address") or "").strip()
        if not addr:
            continue
        key = addr.lower()
        if key not in cache:
            try:
                d = http(CENSUS, {"address": addr + ", Chester, PA", "benchmark": "Public_AR_Current", "format": "json"}, timeout=40)
                m = d.get("result", {}).get("addressMatches", [])
                cache[key] = {"lat": m[0]["coordinates"]["y"], "lon": m[0]["coordinates"]["x"],
                              "matched": m[0].get("matchedAddress", "")} if m else None
            except Exception as exc:
                log("  census failed", addr, str(exc)[:80])
                continue
            time.sleep(0.6)
        g = cache.get(key)
        if not g:
            continue
        recs.append(dict(source="Seed_directory", source_id="seed/" + hashlib.sha1((key + row.get("name", "").lower()).encode()).hexdigest()[:12],
                         name=row.get("name", ""), brand="", address=addr, category=row.get("category") or "corner_store",
                         lat=g["lat"], lon=g["lon"], coord_quality="census_tiger_interpolated", license=LIC["Census"],
                         raw_type="seed:" + (row.get("source") or ""), has_shop=True, operating="unknown",
                         census_matched=g.get("matched")))
    save(cache_p, cache)
    log(f"  seeds geocoded: {len(recs)} of {len(rows)}")
    return recs


# ------------------------------------------------------------------ dedupe
SRC_RANK = {"OSM": 0, "OSM_local_2025snapshot": 1, "Overture": 2, "Seed_directory": 3}


def should_merge(a, b):
    d = dist_m(a["lat"], a["lon"], b["lat"], b["lon"])
    ns = name_sim(a["name"], b["name"])
    na, nb = norm_addr(a["address"]), norm_addr(b["address"])
    same_addr = bool(na and nb and addr_number(na) and na == nb)
    if a["source_id"] == b["source_id"]:
        return True
    if same_addr and d <= 200:
        return True
    street = lambda n: n.split(" ", 1)[1] if " " in n else ""
    if (addr_number(na) and addr_number(nb) and addr_number(na) != addr_number(nb)
            and street(na) and street(na) == street(nb) and d > 5):
        return False  # different house numbers on the same street = different storefronts
    if "Seed_directory" in (a["source"], b["source"]):
        # Census TIGER points are interpolated - never merge seeds on proximity alone
        return d <= 150 and ns >= 0.6
    if a["source"].startswith("OSM") and b["source"].startswith("OSM") and d > 8 and ns < 0.5 \
            and not generic_name(a["name"]) and not generic_name(b["name"]) and not {a["category"], b["category"]} & {"gas_station"}:
        return False  # two separately mapped, differently named OSM shops
    gas = {a["category"], b["category"]} & {"gas_station"}
    if gas and d <= 45 and (a["category"] != b["category"]):  # fuel + convenience shop on same forecourt
        return ns >= 0.35 or generic_name(a["name"]) or generic_name(b["name"]) or (a["brand"] and a["brand"] == b["brand"]) or d <= 25
    if d <= 10:
        return True
    if d <= 30 and (ns >= 0.5 or generic_name(a["name"]) or generic_name(b["name"])):
        return True
    if d <= 120 and ns >= 0.72:
        return True
    # census-interpolated seeds can be far off; accept strong name + same street number
    if d <= 250 and ns >= 0.8 and addr_number(a["address"]) and addr_number(a["address"]) == addr_number(b["address"]):
        return True
    return False


def dedupe(recs):
    parent = list(range(len(recs)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for i in range(len(recs)):
        for j in range(i + 1, len(recs)):
            if find(i) != find(j) and should_merge(recs[i], recs[j]):
                parent[find(i)] = find(j)
    groups = {}
    for i, r in enumerate(recs):
        groups.setdefault(find(i), []).append(r)
    places = []
    for members in groups.values():
        members.sort(key=lambda r: (SRC_RANK.get(r["source"], 9), generic_name(r["name"])))
        coord = members[0]
        named = [m for m in members if not generic_name(m["name"])]
        name = (named[0]["name"] if named else coord["name"]) or ("Gas station (unnamed)" if coord["category"] == "gas_station" else "Store (unnamed)")
        cats = {m["category"] for m in members}
        cat = "gas_station" if "gas_station" in cats else ("market" if "market" in cats else ("deli" if "deli" in cats else "corner_store"))
        addr = next((m["address"] for m in members if m["source"] in ("OSM", "OSM_local_2025snapshot") and addr_number(m["address"])), "") \
            or next((m["address"] for m in members if addr_number(m["address"])), "")
        pid = "cw_" + hashlib.sha1(min(m["source_id"] for m in members).encode()).hexdigest()[:10]
        places.append(dict(
            id=pid, name=name, category=cat, group="gas_station" if cat == "gas_station" else "store_market",
            has_convenience_store=cat == "gas_station" and any(m["has_shop"] for m in members),
            address=addr, lat=round(coord["lat"], 7), lon=round(coord["lon"], 7),
            coordinate_source=f"{coord['source']} ({coord['coord_quality']})",
            sources=sorted({m["source"] for m in members}), member_ids=sorted({m["source_id"] for m in members}),
            source_records=members, alt_names=sorted({m["name"] for m in members if m["name"] and m["name"] != name}),
            review_status="candidate_unverified", imagery_status="pending"))
    return places


def cmd_inventory(a):
    out = a.out
    city = city_polygon()
    from shapely.geometry import Point
    from shapely.ops import transform
    import pyproj
    to_m = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    city_m = transform(to_m, city).buffer(15)
    log("Inventory sources:")
    osm = src_osm(out)
    loc = src_osm_local()
    ov, ov_rej = src_overture(out)
    seeds = src_seeds(out)
    raw = osm + loc + ov + seeds
    inside, outside = [], []
    for r in raw:
        (inside if city_m.contains(Point(to_m(r["lon"], r["lat"]))) else outside).append(r)
    log(f"Raw source records: {len(raw)}; inside Chester City: {len(inside)}; outside (excluded): {len(outside)}")
    scope = [r for r in inside if not OUT_OF_SCOPE.search(r["name"] or "")]
    oos = [r for r in inside if OUT_OF_SCOPE.search(r["name"] or "")]
    write_csv(out / "sources" / "excluded_out_of_scope.csv", oos, ["source", "source_id", "name", "address", "category", "raw_type", "lat", "lon"])
    log(f"Out of scope (pharmacy / dollar store / check cashing): {len(oos)} records")
    places = dedupe(scope)
    # keep prior imagery state by any shared member id (non-destructive refresh)
    old = load(out / "places.json", [])
    prev = {}
    for o in old:
        for mid in o.get("member_ids", []):
            prev[mid] = o
    for p in places:
        o = next((prev[m] for m in p["member_ids"] if m in prev), None)
        if o:
            for k in ("imagery_status", "imagery", "google_streetview", "match", "frontage", "imagery_note", "review_status"):
                if k in o:
                    p[k] = o[k]
    places.sort(key=lambda p: (p["group"], p["category"], p["name"].casefold()))
    save(out / "places.json", places)
    save(out / "sources" / "raw_source_records.json", raw)
    write_csv(out / "sources" / "excluded_outside_city.csv", outside, ["source", "source_id", "name", "address", "category", "lat", "lon"])
    write_csv(out / "sources" / "rejected_overture.csv", ov_rej, ["source_id", "name", "address", "category", "lat", "lon", "confidence", "operating", "reject_reason"])
    save(out / "sources" / "chester_city_boundary.geojson", {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"Muni": "Chester City", "source": str(BOUNDARY)}, "geometry": city.__geo_interface__}]})
    g = sum(p["group"] == "gas_station" for p in places)
    log(f"Unique businesses: {len(places)}  gas={g}  stores/markets={len(places) - g}")
    write_index(out, places)


# ------------------------------------------------------------------ local archive scan
def scan_sources():
    """Yield local images with known camera position. Each: path, lat, lon, heading, is_360, kind, source, date."""
    items = []
    pano = {}
    for f in (KERLIN / "02_GoogleMetadata").rglob("*.json"):
        d = load(f, [])
        for p in d if isinstance(d, list) else d.get("panoramas", []) if isinstance(d, dict) else []:
            if isinstance(p, dict) and p.get("pano_id") and p.get("lat") is not None:
                pano[p["pano_id"]] = (p["lat"], p.get("lng", p.get("lon")), p.get("date", ""))
    hd = re.compile(r"_H(\d{3,4}(?:\.\d)?)_")
    for d in (KERLIN / "03_StreetReferences").rglob("*.jpg"):
        pid = next((k for k in pano if k in str(d)), None)
        if not pid:
            continue
        m = hd.search(d.name)
        lat, lon, date = pano[pid]
        items.append(dict(path=str(d), lat=lat, lon=lon, heading=float(m.group(1)) if m else None, is_360=False,
                          kind="google_sv_crop_from_360", source="GoogleStreetView (local crop)", source_id=pid,
                          date=date, license=LIC["GoogleStreetView"]))
    plan = KERLIN / "05_ReferencePackages" / "kerlin_google_reconstruction_capture_plan.csv"
    if plan.exists():
        with plan.open(encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                p = KERLIN / "03_ReconstructionReferences_Google" / "CAPTURES" / f"KERLIN_{r['building_id']}_{r['shot']}.jpg"
                if p.exists():
                    items.append(dict(path=str(p), lat=float(r["camera_lat"]), lon=float(r["camera_lon"]),
                                      heading=float(r["heading"]), is_360=False, kind="google_sv_static_capture",
                                      source="GoogleStreetView (local capture)", source_id=f"kerlin_{r['building_id']}_{r['shot']}",
                                      date="", license=LIC["GoogleStreetView"]))
    for man in (KERLIN / "04_MAPILLARY").rglob("*manifest.csv"):
        with man.open(encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                p = man.parent / "images" / r.get("filename", "")
                if not r.get("filename") or not p.exists():
                    continue
                cam = (r.get("camera_type") or "").lower()
                ts = r.get("captured_at") or ""
                date = dt.datetime.fromtimestamp(int(ts) / 1000, dt.timezone.utc).date().isoformat() if ts.isdigit() else ts
                try:
                    creator = json.loads(r.get("creator") or "{}").get("username", "")
                except Exception:
                    creator = ""
                items.append(dict(path=str(p), lat=float(r["lat"]), lon=float(r["lon"]),
                                  heading=float(r["compass_angle"]) if r.get("compass_angle") else None,
                                  is_360=cam in ("spherical", "equirectangular"), kind="mapillary_" + (cam or "unknown"),
                                  source="Mapillary (local)", source_id=r.get("id"), date=date, contributor=creator,
                                  license=LIC["Mapillary"]))
    return items


def exif_scan(root, known):
    from PIL import Image
    out, untagged, n = [], 0, 0
    skip = {"node_modules", ".git", "__pycache__", "10_StorefrontPanoramas", "16_RegionalTiles", "17_RegionalTiles_RealWorld"}
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in skip]
        for fn in fns:
            if not fn.lower().endswith((".jpg", ".jpeg")):
                continue
            p = os.path.join(dp, fn)
            if p in known:
                continue
            n += 1
            try:
                with Image.open(p) as im:
                    ex = im.getexif()
                    gps = ex.get_ifd(34853) if ex else {}
                    if not gps or 2 not in gps or 4 not in gps:
                        untagged += 1
                        continue
                    dms = lambda v: float(v[0]) + float(v[1]) / 60 + float(v[2]) / 3600
                    lat = dms(gps[2]) * (-1 if gps.get(1) in ("S", b"S") else 1)
                    lon = dms(gps[4]) * (-1 if gps.get(3) in ("W", b"W") else 1)
                    head = float(gps[17]) if 17 in gps else None
                    w, h = im.size
                    xmp = im.info.get("xmp") or b""
                    is360 = b"equirectangular" in (xmp if isinstance(xmp, bytes) else xmp.encode()).lower()
                    out.append(dict(path=p, lat=lat, lon=lon, heading=head, is_360=is360,
                                    kind="exif_gps_" + ("360_xmp" if is360 else f"{w}x{h}"), source="local EXIF GPS",
                                    source_id=fn, date=str(ex.get(306, "")), license="Local file - verify ownership"))
            except Exception:
                untagged += 1
    log(f"EXIF scan: {n} unindexed jpgs, {len(out)} GPS-tagged, {untagged} without GPS")
    return out


def view_role(place, cam_lat, cam_lon, front_bearing):
    """front / left_approach / right_approach / opposite_corner / side relative to the storefront."""
    d = dist_m(place["lat"], place["lon"], cam_lat, cam_lon)
    if front_bearing is None:
        return "unknown_frontage"
    off = adiff(bearing(place["lat"], place["lon"], cam_lat, cam_lon), front_bearing)
    if abs(off) <= 25:
        return "front"
    if abs(off) <= 80:
        if d >= 35:
            return "opposite_corner"
        return "left_approach" if off < 0 else "right_approach"
    return "side_or_rear"


def faces(cam, place, max_off=60):
    if cam.get("is_360"):
        return True, 0.0
    if cam.get("heading") is None:
        return None, None
    off = abs(adiff(cam["heading"], bearing(cam["lat"], cam["lon"], place["lat"], place["lon"])))
    return off <= max_off, round(off, 1)


def cmd_scan(a):
    out = a.out
    places = load(out / "places.json")
    if not places:
        raise SystemExit("run inventory first")
    items = scan_sources()
    items += exif_scan(CW, {i["path"] for i in items})
    log(f"Local images with camera position: {len(items)}")
    save(out / "sources" / "local_image_index.json", items)
    fr = load(out / "sources" / "frontage.json", {})
    rows = []
    for p in places:
        hits = []
        for it in items:
            d = dist_m(p["lat"], p["lon"], it["lat"], it["lon"])
            if d > 70:
                continue
            ok, off = faces(it, p)
            if ok is False:
                continue
            hits.append({**it, "distance_m": round(d, 1), "facing_offset_deg": off,
                         "view_role": view_role(p, it["lat"], it["lon"], fr.get(p["id"], {}).get("front_bearing")),
                         "review_status": "camera_faces_site_unverified" if ok else "nearby_heading_unknown"})
        hits.sort(key=lambda h: (h["facing_offset_deg"] is None, h["distance_m"]))
        p["local_imagery"] = hits[:12]
        for h in hits:
            rows.append({"site_id": p["id"], "site_name": p["name"], **h})
    save(out / "places.json", places)
    write_csv(out / "existing_archive_matches.csv", rows, ["site_id", "site_name", "kind", "source", "path", "lat", "lon", "heading",
                                                            "distance_m", "facing_offset_deg", "view_role", "is_360", "date", "license", "review_status"])
    log(f"Businesses with local imagery: {sum(bool(p['local_imagery']) for p in places)}; match rows {len(rows)}")


# ------------------------------------------------------------------ frontage / matching
def build_frontage(places):
    """front_bearing = direction from the site to the nearest named road (the street it faces)."""
    from shapely.geometry import shape, Point
    from shapely.ops import transform, nearest_points
    from shapely.strtree import STRtree
    import pyproj
    to_m = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    to_ll = pyproj.Transformer.from_crs(32618, 4326, always_xy=True).transform
    roads = []
    for f in load(ROADS)["features"]:
        p = f["properties"]
        nm = " ".join(x for x in (p.get("St_PreDir"), p.get("St_PreTyp"), p.get("St_Name"), p.get("St_PosTyp"), p.get("St_PosDir")) if x)
        if not f.get("geometry") or (p.get("RoadClass") or "").lower().startswith(("ramp",)) or re.match(r"I ?95|I ?476|US ?322 ?Hwy", p.get("St_Name") or ""):
            continue
        roads.append((nm, transform(to_m, shape(f["geometry"]))))
    tree = STRtree([g for _, g in roads])
    res = {}
    for pl in places:
        pt = Point(to_m(pl["lon"], pl["lat"]))
        idx = tree.query(pt.buffer(80))
        if not len(idx):
            continue
        best = min(idx, key=lambda i: roads[i][1].distance(pt))
        nm, g = roads[best]
        q = nearest_points(g, pt)[0]
        lon, lat = to_ll(q.x, q.y)
        res[pl["id"]] = {"road": nm, "road_distance_m": round(g.distance(pt), 1),
                         "front_bearing": round(bearing(pl["lat"], pl["lon"], lat, lon), 1)}
    return res


def cmd_match(a):
    out = a.out
    places = load(out / "places.json")
    from shapely.geometry import shape, Point
    from shapely.ops import transform
    from shapely.strtree import STRtree
    import pyproj
    to_m = pyproj.Transformer.from_crs(4326, 32618, always_xy=True).transform
    fr = build_frontage(places)
    save(out / "sources" / "frontage.json", fr)
    log("Loading regional building footprints ...")
    bfeat = load(BUILDINGS)["features"]
    bgeo = [transform(to_m, shape(f["geometry"])).buffer(0) for f in bfeat]
    btree = STRtree(bgeo)
    in_tiles = set()
    if BUILDING_TILES.exists():
        for p in BUILDING_TILES.glob("*.lua"):
            in_tiles.update(re.findall(r'\["(\d+)"\]=', p.read_text(encoding="utf-8")))
    kp = load(KERLIN_PARCELS, {"features": []})["features"]
    kgeo = [transform(to_m, shape(f["geometry"])) for f in kp]
    ktree = STRtree(kgeo) if kgeo else None
    pcache_p = out / "sources" / "delco_parcel_point_cache.json"
    pcache = load(pcache_p, {})
    for pl in places:
        pt = Point(to_m(pl["lon"], pl["lat"]))
        m = {}
        # building: containing footprint, else nearest within 25 m (towards the road side preferred)
        idx = btree.query(pt.buffer(25))
        if len(idx):
            best = min(idx, key=lambda i: bgeo[i].distance(pt))
            dd = bgeo[best].distance(pt)
            bp = bfeat[best]["properties"]
            m["building"] = {"objectid": str(bp.get("OBJECTID")), "master_id": bp.get("master_id"),
                             "distance_m": round(dd, 1), "method": "contains" if dd == 0 else "nearest<=25m",
                             "archetype": bp.get("generator_archetype"), "height_m": bp.get("height_m"),
                             "floors": bp.get("estimated_floors"), "footprint_m2": bp.get("footprint_area_m2"),
                             "existing_poi_name": bp.get("poi_name") or None,
                             "in_roblox_building_tiles": str(bp.get("OBJECTID")) in in_tiles}
        # parcel: Kerlin local first, then Delco public service point query (cached)
        if ktree is not None:
            ki = [i for i in ktree.query(pt) if kgeo[i].contains(pt)]
            if ki:
                kpp = kp[ki[0]]["properties"]
                m["parcel"] = {"pin": kpp.get("PIN"), "address": kpp.get("ADRCAT"), "source": "KerlinPrototype kerlin_parcels.geojson"}
        if "parcel" not in m and not a.offline:
            key = f"{pl['lat']:.7f},{pl['lon']:.7f}"
            if key not in pcache:
                try:
                    d = http(DELCO_PARCELS, {"where": "1=1", "geometry": f"{pl['lon']},{pl['lat']}", "geometryType": "esriGeometryPoint",
                                             "inSR": "4326", "spatialRel": "esriSpatialRelIntersects", "outFields": "PIN,ADRCAT,LEGAL2,LEGAL3,PARID",
                                             "returnGeometry": "false", "f": "json"}, timeout=45)
                    fs = d.get("features", [])
                    pcache[key] = fs[0]["attributes"] if fs else None
                except Exception as exc:
                    log("  parcel query failed", pl["name"], str(exc)[:80])
                time.sleep(0.3)
            if pcache.get(key):
                at = pcache[key]
                m["parcel"] = {"pin": at.get("PIN"), "parid": at.get("PARID"), "address": at.get("ADRCAT"),
                               "legal": " ".join(x for x in (at.get("LEGAL2"), at.get("LEGAL3")) if x),
                               "source": "Delaware County Parcels_Public_Access (point query)"}
        if pl["id"] in fr:
            m["road"] = fr[pl["id"]]
        sx, sz = studs(pl["lon"], pl["lat"])
        m["studs"] = {"x": sx, "z": sz}
        pl["match"] = m
    save(pcache_p, pcache)
    save(out / "places.json", places)
    nb = sum("building" in p["match"] for p in places)
    npc = sum("parcel" in p["match"] for p in places)
    log(f"Matched buildings {nb}/{len(places)}, parcels {npc}/{len(places)}, frontage {len(fr)}")


# ------------------------------------------------------------------ remote collection
def karta(lat, lon, radius):
    d = http(KARTA, {"lat": f"{lat:.7f}", "lng": f"{lon:.7f}", "radius": radius, "itemsPerPage": 150, "page": 1}, timeout=45)
    if (d.get("status") or {}).get("apiCode") not in (600, "600"):
        raise RuntimeError("KartaView API: " + str((d.get("status") or {}).get("apiMessage")))
    res = []
    for p in (d.get("result") or {}).get("data") or []:
        try:
            proj = (p.get("projection") or "").upper()
            fov = float(p.get("fieldOfView") or 0)
            url = f"https://{p['storage']}.openstreetcam.org/files/photo/{p['filepathProc']}" if p.get("storage") and p.get("filepathProc") else None
            if not url:
                continue
            res.append(dict(source="KartaView", id=str(p["id"]), url=url, lat=float(p["lat"]), lon=float(p["lng"]),
                            heading=float(p["heading"]) if p.get("heading") not in (None, "") else None,
                            date=(p.get("shotDate") or p.get("dateAdded") or "")[:19],
                            is_360=proj in ("SPHERE", "EQUIRECTANGULAR", "SPHERICAL") or fov >= 300,
                            projection=proj, sequence=p.get("sequenceId"), contributor="",
                            page=f"https://kartaview.org/details/{p.get('sequenceId')}/{p.get('sequenceIndex')}/track-info",
                            license=LIC["KartaView"]))
        except (TypeError, ValueError, KeyError):
            continue
    return res


def mapillary(lat, lon, token, radius):
    dlat = radius / 111000
    dlon = radius / (111000 * math.cos(math.radians(lat)))
    d = http(MAPILLARY, {"access_token": token, "bbox": f"{lon-dlon},{lat-dlat},{lon+dlon},{lat+dlat}", "limit": 500,
                         "fields": "id,captured_at,computed_geometry,compass_angle,camera_type,thumb_2048_url,creator"}, timeout=45)
    res = []
    for p in d.get("data", []):
        c = (p.get("computed_geometry") or {}).get("coordinates")
        if not c or not p.get("thumb_2048_url"):
            continue
        ts = p.get("captured_at")
        res.append(dict(source="Mapillary", id=str(p["id"]), url=p["thumb_2048_url"], lat=c[1], lon=c[0],
                        heading=p.get("compass_angle"), date=dt.datetime.fromtimestamp(ts / 1000, dt.timezone.utc).date().isoformat() if ts else "",
                        is_360=(p.get("camera_type") or "").lower() in ("spherical", "equirectangular"),
                        projection=p.get("camera_type"), contributor=(p.get("creator") or {}).get("username", ""),
                        page=f"https://www.mapillary.com/app/?pKey={p['id']}", license=LIC["Mapillary"]))
    return res


def gsv_meta(lat, lon, key):
    d = http(GSV_META, {"location": f"{lat},{lon}", "radius": 50, "source": "outdoor", "key": key}, timeout=30)
    if d.get("status") != "OK":
        return {"status": d.get("status")}
    return {"status": "OK", "pano_id": d.get("pano_id"), "date": d.get("date"), "lat": d["location"]["lat"],
            "lon": d["location"]["lng"], "copyright": d.get("copyright"),
            "distance_m": round(dist_m(lat, lon, d["location"]["lat"], d["location"]["lng"]), 1),
            "note": "Google 360 panorama exists here (metadata only; not downloaded)"}


def choose(place, items, front_bearing, n):
    roles = {}
    cands = []
    for it in items:
        d = dist_m(place["lat"], place["lon"], it["lat"], it["lon"])
        if d < 3:
            continue
        ok, off = faces(it, place, 55)
        if ok is False or (ok is None and not it["is_360"]):
            continue
        role = view_role(place, it["lat"], it["lon"], front_bearing)
        if role == "side_or_rear" and not it["is_360"]:
            continue
        score = d + (off or 0) * 0.4 - (40 if it["is_360"] else 0) + (0 if role == "front" else 8)
        cands.append((score, role, d, off, it))
    cands.sort(key=lambda c: c[0])
    chosen, seen_seq = [], set()
    if cands and any(c[4]["is_360"] for c in cands):
        c = next(c for c in cands if c[4]["is_360"])
        chosen.append(c)
        roles["360"] = 1
    for want in ("front", "left_approach", "right_approach", "opposite_corner", "unknown_frontage"):
        for c in cands:
            if len(chosen) >= n:
                break
            if c[1] == want and c not in chosen and want not in roles:
                chosen.append(c)
                roles[want] = 1
                break
    for c in cands:  # fill remaining slots with best other angles from distinct sequences
        if len(chosen) >= n:
            break
        if c not in chosen and c[4].get("sequence") not in seen_seq:
            chosen.append(c)
        seen_seq.add(c[4].get("sequence"))
    return [dict(**c[4], view_role=("360_panorama" if c[4]["is_360"] else c[1]), distance_m=round(c[2], 1),
                 facing_offset_deg=c[3]) for c in chosen]


def slug(s):
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")[:50] or "site"


def site_dir(out, p):
    return out / "businesses" / p["group"] / f"{slug(p['name'])}__{p['id']}"


def collect_one(out, p, a, gkey, mtoken, fr, folder):
    errors = []
    items = []
    try:
        items += karta(p["lat"], p["lon"], a.radius)
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            raise
        errors.append(f"KartaView HTTP {exc.code}")
    except Exception as exc:
        errors.append("KartaView: " + str(exc)[:90])
    if mtoken:
        try:
            items += mapillary(p["lat"], p["lon"], mtoken, a.radius)
        except Exception as exc:
            errors.append("Mapillary: " + str(exc)[:90])
    if gkey and "google_streetview" not in p:
        try:
            p["google_streetview"] = gsv_meta(p["lat"], p["lon"], gkey)
        except Exception as exc:
            errors.append("GSV metadata: " + str(exc)[:60])
    front = (fr.get(p["id"]) or {}).get("front_bearing")
    picks = choose(p, items, front, a.shots)
    imgs = [i for i in p.get("imagery", []) if Path(out / i["path"]).exists()]
    have = {(i["source"], i["source_id"]) for i in imgs}
    for c in picks:
        if (c["source"], c["id"]) in have:
            continue
        dest = folder / f"{c['view_role']}__{c['source']}_{c['id']}.jpg"
        try:
            body, ctype = http(c["url"], raw=True, timeout=60)
            if not (ctype.startswith("image/") or body[:2] == b"\xff\xd8"):
                raise ValueError("not an image")
            folder.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
            imgs.append({"path": str(dest.relative_to(out)), "source": c["source"], "source_id": c["id"],
                         "source_url": c["url"], "source_page": c.get("page"), "license": c["license"],
                         "contributor": c.get("contributor", ""), "capture_date": c["date"], "camera_lat": c["lat"],
                         "camera_lon": c["lon"], "camera_heading_deg": c["heading"], "is_360_panorama": c["is_360"],
                         "projection": c.get("projection"), "view_role": c["view_role"], "distance_m": c["distance_m"],
                         "facing_offset_deg": c["facing_offset_deg"], "review_status": "unverified_storefront_view"})
            have.add((c["source"], c["id"]))
            time.sleep(0.4)
        except Exception as exc:
            errors.append(f"download {c['id']}: {str(exc)[:70]}")
    p["imagery"] = imgs
    p["remote_candidates_found"] = len(items)
    p["imagery_note"] = "; ".join(errors[:4])
    return errors, items


def imagery_status(p):
    local = p.get("local_imagery") or []
    imgs = p.get("imagery") or []
    if any(i["is_360_panorama"] for i in imgs) or any(l["is_360"] for l in local):
        return "true_360_local"
    if imgs or any(l.get("facing_offset_deg") is not None for l in local):
        return "street_level_only"
    return "no_usable_imagery"


def cmd_collect(a):
    out = a.out
    places = load(out / "places.json")
    if not places:
        raise SystemExit("run inventory first")
    gkey = "" if a.no_google_meta else secret("GOOGLE_MAPS_API_KEY")
    mtoken = os.environ.get("MAPILLARY_TOKEN") or os.environ.get("MAPILLARY_ACCESS_TOKEN") or ""
    log(f"Mapillary token: {'yes' if mtoken else 'NO (no Mapillary 360s this run)'}; Google SV metadata: {'yes' if gkey else 'no'}")
    fr = load(out / "sources" / "frontage.json", {})
    todo = [p for p in places if p.get("imagery_status") in (None, "pending", "retry") or a.recheck]
    log(f"Sites pending: {len(todo)}; this run: {min(len(todo), a.limit)}")
    for n, p in enumerate(todo[: a.limit], 1):
        try:
            errors, items = collect_one(out, p, a, gkey, mtoken, fr, site_dir(out, p))
        except urllib.error.HTTPError as exc:
            log("Rate limited (HTTP 429) - stopping batch; rerun later to resume")
            p["imagery_status"] = "retry"
            break
        p["imagery_status"] = "retry" if (errors and not items and not p.get("imagery")) else imagery_status(p)
        gs = (p.get("google_streetview") or {}).get("status")
        log(f"[{n}/{min(len(todo), a.limit)}] {p['name'][:34]:34} remote={len(items):3} saved={len(p['imagery'])} "
            f"local={len(p.get('local_imagery') or [])} gsv={gs} -> {p['imagery_status']}")
        if n % 5 == 0:
            save(out / "places.json", places)
        time.sleep(a.delay)
    save(out / "places.json", places)
    write_index(out, places)


# ------------------------------------------------------------------ outputs
def write_site_records(out, places):
    for p in places:
        folder = site_dir(out, p)
        folder.mkdir(parents=True, exist_ok=True)
        rec = {k: v for k, v in p.items() if k != "source_records"}
        rec["sources_detail"] = [{k: m.get(k) for k in ("source", "source_id", "name", "address", "lat", "lon", "coord_quality", "license", "raw_type", "operating")}
                                 for m in p.get("source_records", [])]
        save(folder / "business.json", rec)


def cmd_index(a):
    places = load(a.out / "places.json")
    write_index(a.out, places)


def write_index(out, places):
    for p in places:
        if p.get("imagery_status") not in (None, "pending", "retry"):
            p["imagery_status"] = imagery_status(p)
    save(out / "places.json", places)
    write_site_records(out, places)
    flat = []
    for p in places:
        m = p.get("match") or {}
        g = p.get("google_streetview") or {}
        flat.append(dict(id=p["id"], name=p["name"], group=p["group"], category=p["category"], address=p["address"],
                         lat=p["lat"], lon=p["lon"], sources="+".join(p["sources"]), coordinate_source=p["coordinate_source"],
                         imagery_status=p.get("imagery_status"), downloaded_images=len(p.get("imagery") or []),
                         local_images=len(p.get("local_imagery") or []), google_360_available=g.get("status") == "OK",
                         google_pano_date=g.get("date", ""), building_objectid=(m.get("building") or {}).get("objectid", ""),
                         parcel_pin=(m.get("parcel") or {}).get("pin", ""), road=(m.get("road") or {}).get("road", ""),
                         folder=str(site_dir(out, p).relative_to(out))))
    fields = list(flat[0]) if flat else ["id"]
    write_csv(out / "places.csv", flat, fields)
    save(out / "places.geojson", {"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "Point", "coordinates": [r["lon"], r["lat"]]}, "properties": r} for r in flat]})
    queue = []
    for p, r in zip(places, flat):
        if r["imagery_status"] == "true_360_local":
            continue
        have = {i["view_role"] for i in p.get("imagery") or []} | {l.get("view_role") for l in p.get("local_imagery") or []}
        need = [v for v in ("360_panorama", "front", "left_approach", "right_approach", "opposite_corner") if v not in have]
        queue.append({**r, "needed_views": "; ".join(need), "frontage_bearing": ((p.get("match") or {}).get("road") or {}).get("front_bearing", "")})
    write_csv(out / "capture_queue.csv", queue, fields + ["needed_views", "frontage_bearing"])
    meta = []
    for p in places:
        for i in p.get("imagery") or []:
            meta.append({"site_id": p["id"], "site_name": p["name"], **i})
    if meta:
        write_csv(out / "photo_metadata.csv", meta, list(meta[0]))
    write_manifest(out, places)
    write_html(out, places, flat)


def write_manifest(out, places):
    biz = []
    for p in places:
        m = p.get("match") or {}
        refs = [{"path": str((out / i["path"]).resolve()), "kind": "downloaded", **{k: i.get(k) for k in (
            "source", "source_id", "license", "contributor", "capture_date", "camera_lat", "camera_lon",
            "camera_heading_deg", "is_360_panorama", "view_role", "distance_m", "source_page")}} for i in p.get("imagery") or []]
        refs += [{"path": l["path"], "kind": "existing_local", "source": l["source"], "source_id": l.get("source_id"),
                  "license": l["license"], "capture_date": l.get("date"), "camera_lat": l["lat"], "camera_lon": l["lon"],
                  "camera_heading_deg": l.get("heading"), "is_360_panorama": l["is_360"], "view_role": l.get("view_role"),
                  "distance_m": l["distance_m"]} for l in p.get("local_imagery") or []]
        biz.append({"id": p["id"], "name": p["name"], "group": p["group"], "category": p["category"],
                    "has_convenience_store": p.get("has_convenience_store", False), "address": p["address"],
                    "lat": p["lat"], "lon": p["lon"], "studs": m.get("studs"), "building": m.get("building"),
                    "parcel": m.get("parcel"), "frontage": m.get("road"), "imagery_status": p.get("imagery_status"),
                    "google_streetview": p.get("google_streetview"), "references": refs,
                    "review_status": p.get("review_status"), "sources": p["sources"]})
    save(out / "chesterworld_storefront_reference_manifest.json", {
        "schema": "chesterworld.storefront_reference.v1", "generated": dt.datetime.now().isoformat(timespec="seconds"),
        "coordinate_note": "studs use the same Web-Mercator x3 transform as tools/build_landmarks.py (x=east, z=south)",
        "building_id_note": "building.objectid == regional_buildings_base OBJECTID == BuildingTiles id",
        "non_destructive": True, "licenses": LIC, "businesses": biz})


def write_html(out, places, flat):
    from collections import Counter
    st = Counter(r["imagery_status"] for r in flat)
    grp = Counter(r["group"] for r in flat)
    rows = []
    for p, r in zip(places, flat):
        thumbs = "".join(f'<a href="{html.escape(i["path"].replace(chr(92), "/"))}"><img loading="lazy" src="{html.escape(i["path"].replace(chr(92), "/"))}" '
                         f'title="{html.escape(i["view_role"] + " | " + i["source"] + " " + str(i["capture_date"]))}"></a>' for i in (p.get("imagery") or [])[:4])
        local = len(p.get("local_imagery") or [])
        g = p.get("google_streetview") or {}
        gl = (f'<a href="https://www.google.com/maps/@?api=1&map_action=pano&pano={g["pano_id"]}">GSV {html.escape(g.get("date") or "")}</a>' if g.get("pano_id") else "-")
        rows.append(f"<tr class='{r['imagery_status']}'><td><b>{html.escape(r['name'])}</b><br><small>{html.escape(r['address'] or '')}</small></td>"
                    f"<td>{r['category']}</td><td>{r['imagery_status']}</td><td class=t>{thumbs}</td><td>{local}</td><td>{gl}</td>"
                    f"<td>{html.escape(str(r['building_objectid']))}<br><small>{html.escape(str(r['parcel_pin']))}</small></td>"
                    f"<td><a href='https://www.openstreetmap.org/?mlat={r['lat']}&mlon={r['lon']}#map=19/{r['lat']}/{r['lon']}'>OSM</a> "
                    f"<a href='https://www.mapillary.com/app/?lat={r['lat']}&lng={r['lon']}&z=18'>Mapillary</a> "
                    f"<a href='https://kartaview.org/map/@{r['lat']},{r['lon']},18z'>KartaView</a></td></tr>")
    doc = f"""<!doctype html><html><head><meta charset=utf-8><title>Chester Storefront References</title>
<style>:root{{--bg:#10161d;--fg:#e8edf2;--mut:#9fb0c0;--line:#2b3846;--acc:#f0c96a}}
body{{margin:0;padding:20px;background:var(--bg);color:var(--fg);font:14px system-ui,Segoe UI,Arial}}h1{{color:var(--acc);margin:0 0 4px}}
p,small{{color:var(--mut)}}table{{border-collapse:collapse;width:100%}}td,th{{padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top;text-align:left}}
th{{position:sticky;top:0;background:var(--bg)}}a{{color:#8cc8ff}}.t img{{height:70px;margin-right:4px;border-radius:3px}}
tr.no_usable_imagery td:nth-child(3){{color:#ff8f8f}}tr.true_360_local td:nth-child(3){{color:#8fffa8}}
input{{background:#1b2530;color:var(--fg);border:1px solid var(--line);padding:6px;width:280px}}</style></head><body>
<h1>Chester City - corner stores, delis, markets &amp; gas stations</h1>
<p>{len(flat)} unique businesses · gas stations {grp.get('gas_station',0)} · stores/markets {grp.get('store_market',0)} ·
true 360 local {st.get('true_360_local',0)} · street-level only {st.get('street_level_only',0)} · no usable imagery {st.get('no_usable_imagery',0)} · pending {st.get('pending',0)+st.get('retry',0)}</p>
<p>Coordinates from OSM / Overture / Census-interpolated seeds - candidates, not a verified census. Every image is <i>unverified</i> until a human confirms the storefront is visible and current.
GSV links = Google 360 exists remotely (metadata only, not downloaded).</p>
<input id=q placeholder="filter..." oninput="for(const r of document.querySelectorAll('tbody tr'))r.style.display=r.textContent.toLowerCase().includes(this.value.toLowerCase())?'':'none'">
<table><thead><tr><th>Business</th><th>Category</th><th>Imagery</th><th>Downloaded views</th><th>Local refs</th><th>Google 360</th><th>Building / parcel</th><th>Maps</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table>
<p>© OpenStreetMap contributors (ODbL) · Overture Maps (CDLA-Permissive-2.0) · KartaView imagery CC BY-SA 4.0 (per-image contributor in photo_metadata.csv) · Mapillary CC BY-SA 4.0 · Google imagery © Google, reference only.</p>
</body></html>"""
    (out / "INDEX.html").write_text(doc, encoding="utf-8")


# ------------------------------------------------------------------ highway / bridge structures
def cmd_sites(a):
    """Same imagery pass for highway crossings / bridge pins -> Data/HighwayReference/imagery."""
    out = DATA / "HighwayReference" / "imagery"
    sites = []
    with (DATA / "HighwayReference" / "crossings.csv").open(encoding="utf-8-sig") as fh:
        for r in csv.DictReader(fh):
            if r.get("latitude") and r.get("longitude"):
                sites.append({"id": r["id"], "name": r["crossing"], "lat": float(r["latitude"]), "lon": float(r["longitude"]),
                              "group": "structures", "category": "bridge", "address": f"{r['upper']} over {r['lower']}",
                              "clearance_ft": r.get("clearance_ft")})
    extra = load(DATA / "HighwayReference" / "bridge_pins.geojson", {"features": []})["features"]
    for f in extra:
        pid = f["properties"].get("id")
        if pid and all(s["id"] != pid for s in sites):
            lon, lat = f["geometry"]["coordinates"][:2]
            sites.append({"id": pid, "name": f["properties"].get("crossing", pid), "lat": lat, "lon": lon,
                          "group": "structures", "category": "bridge", "address": ""})
    prev = {s["id"]: s for s in load(out / "structures.json", [])}
    gkey = "" if a.no_google_meta else secret("GOOGLE_MAPS_API_KEY")
    mtoken = os.environ.get("MAPILLARY_TOKEN") or os.environ.get("MAPILLARY_ACCESS_TOKEN") or ""
    local = scan_sources()
    for s in sites:
        s.update({k: v for k, v in prev.get(s["id"], {}).items() if k in ("imagery", "google_streetview")})
        s["local_imagery"] = [dict(**it, distance_m=round(dist_m(s["lat"], s["lon"], it["lat"], it["lon"]), 1), view_role="nearby")
                              for it in local if dist_m(s["lat"], s["lon"], it["lat"], it["lon"]) <= 120][:20]
        a.shots = max(a.shots, 6)
        errors, items = collect_one(out, s, a, gkey, mtoken, {}, out / "sites" / f"{slug(s['name'])}__{s['id']}")
        s["imagery_status"] = imagery_status(s)
        log(f"{s['id']:18} remote={len(items):3} saved={len(s['imagery'])} local={len(s['local_imagery'])} gsv={(s.get('google_streetview') or {}).get('status')}")
        time.sleep(a.delay)
    save(out / "structures.json", sites)
    log("Wrote", out / "structures.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["inventory", "scan", "collect", "match", "index", "sites"])
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT)
    ap.add_argument("--limit", type=int, default=35)
    ap.add_argument("--radius", type=int, default=80)
    ap.add_argument("--shots", type=int, default=4)
    ap.add_argument("--delay", type=float, default=1.5)
    ap.add_argument("--recheck", action="store_true", help="re-query sites already processed")
    ap.add_argument("--offline", action="store_true", help="match without parcel service queries")
    ap.add_argument("--no-google-meta", action="store_true")
    ap.add_argument("--kind", default="structures")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    {"inventory": cmd_inventory, "scan": cmd_scan, "collect": cmd_collect, "match": cmd_match,
     "index": cmd_index, "sites": cmd_sites}[a.command](a)


if __name__ == "__main__":
    main()
