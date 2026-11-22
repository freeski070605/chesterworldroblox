"""Geographic image-to-building evidence pipeline (block-by-block, citywide-capable).

Resolves WHICH county footprint (stable ChesterBuildingId = county OBJECTID) and
WHICH wall each photograph actually shows, instead of trusting the building ID
a photo was downloaded for. For every camera with a known pose it casts rays
across the field of view against every nearby footprint; the nearest polygon
hit per ray wins (occlusion), so neighbouring houses, side walls and rear
yards are detected geometrically.

Observations are never overwritten. Each property record keeps every
observation (old photo override, user Google review, GIS zoning guess, fresh
Google panorama metadata) with its association verdict, then a resolver picks
a type only when the supporting observation is geometrically about that
building. Disagreements stay in `conflicts`.

    py -3 tools/reconstruction/property_evidence.py                 # 9th/Kerlin scope
    py -3 tools/reconstruction/property_evidence.py --bbox W,S,E,N --name block_x
    py -3 tools/reconstruction/property_evidence.py --all           # all 21.7k IDs (evidence only)
    py -3 tools/reconstruction/property_evidence.py --fresh-panos     # free metadata
          calls: find extra Google panoramas facing every street wall
    py -3 tools/reconstruction/property_evidence.py --render          # aerial debug map

Outputs (build/ is git-ignored; the Lua module is the runtime product):
    build/property_evidence/<name>.json   full evidence records
    build/property_evidence/<name>.csv    one row per property
    src/server/World/PropertyReconstruction.lua  status + structure per ID
Google imagery is (c) Google: private modelling reference, not redistributed.
"""
import argparse
import csv
import json
import math
import re
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon, shape
from shapely.strtree import STRtree

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(r"E:\ChesterWorld\Data")
OUT_DIR = ROOT / "build" / "property_evidence"
LUA_OUT = ROOT / "src/server/World/PropertyReconstruction.lua"
OVERRIDES = ROOT / "src/server/World/BuildingReviewOverrides.lua"
USER_REVIEWS = [ROOT / "build" / "chester_google_visual_classifications.csv",
                Path.home() / "Downloads" / "chester_google_visual_classifications.csv"]
# W 9th, Lincoln to Concord/five points, 8th-to-10th blocks (same as
# kerlin_neighborhood.py) plus a margin so occluders outside the scope count.
KERLIN = (-75.37465, 39.84720, -75.37020, 39.84870)
X_OFFSET, Z_OFFSET = 8397592.0, -4837229.0   # EPSG:3857 -> tile source metres
RAYS = 41
MAX_RANGE_M = 70.0
FRONT_DOT, REAR_DOT = 0.6, -0.6

# user review vocabulary -> builder style
USER_STYLE = {"Residential — rowhouse": "rowhouse", "Residential — twin": "twin",
              "Residential — detached": "house", "Commercial — storefront": "storefront",
              "Commercial — other": "commercial", "Mixed-use": "mixed",
              "Institutional / civic": "institutional", "Garage / outbuilding": "garage",
              "Vacant / lot": "lot"}
RESIDENTIAL = {"rowhouse", "twin", "house", "apartment"}


def merc(lon, lat):
    return lon * 20037508.34 / 180.0, math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0


def src_xy(lon, lat):
    mx, my = merc(lon, lat)
    return mx + X_OFFSET, my + Z_OFFSET


SCALE = 1 / math.cos(math.radians(39.848))  # mercator metres per true metre here


def to_src_poly(geom):
    rings = geom["coordinates"] if geom["type"] == "Polygon" else max(
        geom["coordinates"], key=lambda p: len(p[0]))
    return Polygon([src_xy(lon, lat) for lon, lat, *_ in rings[0]])


def bearing_vec(deg):  # compass bearing -> (east, north)
    r = math.radians(deg)
    return math.sin(r), math.cos(r)


def vec_bearing(dx, dz):
    return math.degrees(math.atan2(dx, dz)) % 360


# ------------------------------------------------------------------ inputs
def load_footprints():
    geo = json.loads((DATA / "13_RegionalMaster" / "regional_buildings_base.geojson").read_text())
    out = {}
    for f in geo["features"]:
        p = f["properties"]
        poly = to_src_poly(f["geometry"])
        if not poly.is_valid:
            poly = poly.buffer(0)
        out[str(p["OBJECTID"])] = dict(id=str(p["OBJECTID"]), poly=poly, props=p,
                                       lonlat=(p.get("center_lon"), p.get("center_lat")))
    return out


def load_roads():
    geo = json.loads((DATA / "02_Roads" / "delco_roads.geojson").read_text())
    roads = []
    for f in geo["features"]:
        p = f["properties"]
        g = f["geometry"]
        parts = g["coordinates"] if g["type"] == "MultiLineString" else [g["coordinates"]]
        name = " ".join(x for x in (p.get("St_PreDir"), p.get("St_Name"), p.get("St_PosTyp")) if x)
        for part in parts:
            if len(part) < 2:
                continue
            line = LineString([src_xy(lon, lat) for lon, lat, *_ in part])
            roads.append(dict(name=name, line=line, cls=p.get("RoadClass"),
                              rng=(p.get("FromAddr_L"), p.get("ToAddr_L"), p.get("FromAddr_R"), p.get("ToAddr_R"))))
    return roads


def load_photos():
    photos = []
    for folder, src in (("25_GoogleStreetView_Buildings", "google_streetview"),
                        ("24_BuildingImagery_Mapillary", "mapillary")):
        path = DATA / folder / "manifest.csv"
        if not path.exists():
            continue
        for r in csv.DictReader(path.open(newline="", encoding="utf-8-sig")):
            if r.get("status", "ok") != "ok" or not r.get("camera_lat"):
                continue
            photos.append(dict(source=src, downloaded_for=str(r["objectid"]),
                               path=f"{folder}/{r['path'].replace(chr(92), '/')}",
                               pano=r.get("pano_id") or r.get("photo_id"), date=r.get("capture_date", ""),
                               cam=src_xy(float(r["camera_lon"]), float(r["camera_lat"])),
                               cam_ll=(float(r["camera_lat"]), float(r["camera_lon"])),
                               heading=float(r["camera_heading_deg"]),
                               fov=float(r.get("fov_deg") or 70), url=r.get("source_url", "")))
    return photos


def load_user_reviews():
    for path in USER_REVIEWS:
        if path.exists():
            return path, {r["building_id"]: r for r in csv.DictReader(path.open(newline="", encoding="utf-8-sig"))}
    return None, {}


def load_old_overrides():
    text = OVERRIDES.read_text(encoding="utf-8")
    out = {}
    starts = list(re.finditer(r'^ \["(\d+)"\]=\{', text, re.M))
    for k, m in enumerate(starts):
        body = text[m.end(): starts[k + 1].start() if k + 1 < len(starts) else len(text)]
        style = re.search(r'style="(\w+)"', body)
        ev = re.search(r'G\.\."([^"]+)"', body)
        conf = re.search(r'confidence="(\w+)"', body)
        out[m.group(1)] = dict(style=style and style.group(1), confidence=conf and conf.group(1),
                               photo=ev and ("25_GoogleStreetView_Buildings/images/" + ev.group(1).split(";")[0].strip()))
    return out


POSE_REVIEWS = ROOT / "tools" / "reconstruction" / "pose_reviews.csv"


def load_pose_reviews():
    """Structural review of photos whose camera ray was verified to centre on
    the building (tools/reconstruction/pose_reviews.csv, one row per ID)."""
    if not POSE_REVIEWS.exists():
        return {}
    return {r["building_id"]: r for r in csv.DictReader(POSE_REVIEWS.open(newline="", encoding="utf-8"))}


def adjacency(fp, fps, tree, ids):
    """Party walls: neighbouring county footprints sharing >= 2 m of wall."""
    shared = []
    ring = fp["poly"].exterior
    for j in tree.query(fp["poly"].buffer(0.6 * SCALE)):
        other = fps[ids[j]]
        if other["id"] == fp["id"]:
            continue
        length = ring.intersection(other["poly"].buffer(0.6 * SCALE)).length / SCALE
        if length >= 2.0:
            shared.append(dict(building_id=other["id"], shared_m=round(length, 1)))
    kind = "detached" if not shared else "semi_attached" if len(shared) == 1 else "attached_row"
    return kind, shared


# ------------------------------------------------------------------ geometry
def frontage(fp, roads, road_tree):
    """Each footprint edge -> outward normal, nearest named road it faces.

    Returns the primary street wall (the longest wall facing a road within
    18 m), all street-facing walls, and the corner flag."""
    poly = fp["poly"]
    coords = list(poly.exterior.coords)
    ccw = poly.exterior.is_ccw
    walls = []
    for i in range(len(coords) - 1):
        (x0, z0), (x1, z1) = coords[i][:2], coords[i + 1][:2]
        length = math.hypot(x1 - x0, z1 - z0)
        if length < 1.0 * SCALE:
            continue
        dx, dz = (x1 - x0) / length, (z1 - z0) / length
        nx, nz = (dz, -dx) if ccw else (-dz, dx)
        mid = ((x0 + x1) / 2, (z0 + z1) / 2)
        probe = LineString([mid, (mid[0] + nx * 22 * SCALE, mid[1] + nz * 22 * SCALE)])
        best = None
        for j in road_tree.query(probe):
            road = roads[j]
            if road["cls"] in ("INTERSTATE", "RAMP"):
                continue
            hit = probe.intersection(road["line"])
            if hit.is_empty:
                continue
            d = Point(mid).distance(hit) / SCALE
            if best is None or d < best[0]:
                best = (d, road["name"], road["cls"])
        walls.append(dict(edge=i, length_m=round(length / SCALE, 2), normal=(nx, nz), mid=mid,
                          bearing=round(vec_bearing(nx, nz)), street=best and best[1],
                          street_cls=best and best[2], street_dist_m=best and round(best[0], 1)))
    street = [w for w in walls if w["street"]]
    # primary: longest stretch facing the CLOSEST street (row frontages are
    # long; corner side walls are usually longer but on a side street)
    by_street = {}
    for w in street:
        by_street.setdefault(w["street"], []).append(w)
    primary = None
    if by_street:
        def score(ws):
            # houses sit close to the street they face; a main street wins a tie
            d = min(w["street_dist_m"] for w in ws)
            bonus = {"MAJOR": 1.5, "SECONDARY": 1.5, "WALKWAY": 0.7}.get(ws[0]["street_cls"], 1.0)
            return bonus * sum(w["length_m"] for w in ws) / (1 + (d / 5) ** 2)
        name = max(by_street, key=lambda n: score(by_street[n]))
        primary = max(by_street[name], key=lambda w: w["length_m"])
    return walls, primary, sorted(by_street)


def wall_kind(normal, primary):
    if primary is None:
        return "unknown"
    d = normal[0] * primary["normal"][0] + normal[1] * primary["normal"][1]
    return "front" if d > FRONT_DOT else "rear" if d < REAR_DOT else "side"


def cast(photo, fps, tree, ids):
    """Nearest footprint hit for every ray across the camera's horizontal FOV."""
    cx, cz = photo["cam"]
    hits = []
    for k in range(RAYS):
        h = photo["heading"] - photo["fov"] / 2 + photo["fov"] * k / (RAYS - 1)
        ex, ez = bearing_vec(h)
        ray = LineString([(cx, cz), (cx + ex * MAX_RANGE_M * SCALE, cz + ez * MAX_RANGE_M * SCALE)])
        best = None
        for j in tree.query(ray):
            fp = fps[ids[j]]
            inter = ray.intersection(fp["poly"].exterior)
            if inter.is_empty:
                continue
            pts = [inter] if inter.geom_type == "Point" else list(getattr(inter, "geoms", []))
            for p in pts:
                if p.geom_type != "Point":
                    continue
                d = math.hypot(p.x - cx, p.y - cz)
                if best is None or d < best[0]:
                    best = (d, fp["id"], (p.x, p.y))
        hits.append((k, best))
    return hits


def hit_wall(fp, point):
    coords = list(fp["poly"].exterior.coords)
    best = None
    for i in range(len(coords) - 1):
        seg = LineString([coords[i][:2], coords[i + 1][:2]])
        d = seg.distance(Point(point))
        if best is None or d < best[0]:
            best = (d, i)
    return best[1]


def associate(photo, hits, fps, walls_by_id):
    """Turn ray hits into a verdict about which building and wall is visible."""
    total = len(hits)
    share = {}
    centre = hits[total // 2][1]
    for _, h in hits:
        if h:
            share[h[1]] = share.get(h[1], 0) + 1
    shares = {k: round(v / total, 2) for k, v in sorted(share.items(), key=lambda kv: -kv[1])}
    target = photo["downloaded_for"]
    visible = []
    for bid, s in shares.items():
        if s < 0.12:
            continue
        fp = fps[bid]
        walls, primary = walls_by_id[bid]
        kinds = {}
        for _, h in hits:
            if h and h[1] == bid:
                edge = hit_wall(fp, h[2])
                w = next((w for w in walls if w["edge"] == edge), None)
                kind = wall_kind(w["normal"], primary) if w else "unknown"
                kinds[kind] = kinds.get(kind, 0) + 1
        visible.append(dict(building_id=bid, fov_share=s, wall=max(kinds, key=kinds.get) if kinds else "unknown",
                            centre=bool(centre and centre[1] == bid)))
    tgt = next((v for v in visible if v["building_id"] == target), None)
    dominant = visible[0]["building_id"] if visible else None
    if tgt is None:
        verdict = f"views_other:{dominant}" if dominant else "views_nothing"
    elif tgt["centre"] and tgt["fov_share"] >= 0.25:
        verdict = f"target_{tgt['wall']}"
    elif dominant != target:
        verdict = f"target_partial_dominant:{dominant}"
    else:
        verdict = f"target_{tgt['wall']}_offcentre"
    return verdict, visible


# ------------------------------------------------------------------ address
def address_for(fp, primary, roads, road_tree):
    """Interpolate a house number from the county centreline address range."""
    if not primary:
        return ""
    mid = Point(primary["mid"])
    best = None
    for j in road_tree.query(mid.buffer(25 * SCALE)):
        r = roads[j]
        if r["name"] != primary["street"]:
            continue
        d = r["line"].distance(mid)
        if best is None or d < best[0]:
            best = (d, r)
    if not best or None in best[1]["rng"]:
        return primary["street"]
    r = best[1]
    line = r["line"]
    t = line.project(mid) / max(line.length, 1e-6)
    # side: left/right of the digitised direction
    a = line.interpolate(max(line.project(mid) - 1, 0))
    b = line.interpolate(min(line.project(mid) + 1, line.length))
    cross = (b.x - a.x) * (mid.y - a.y) - (b.y - a.y) * (mid.x - a.x)
    lo, hi = (r["rng"][0], r["rng"][1]) if cross > 0 else (r["rng"][2], r["rng"][3])
    if not lo and not hi:
        return primary["street"]
    n = round(lo + (hi - lo) * t)
    if (n - lo) % 2:
        n += 1 if hi >= lo else -1
    return f"~{n} {primary['street']}"


# ------------------------------------------------------------------ resolver
KEYWORDS_REAR = re.compile(r"backyard|back yard|rear", re.I)
KEYWORDS_SIDE = re.compile(r"side of|side wall", re.I)
KEYWORDS_DUP = re.compile(r"duplic", re.I)


def resolve(rec):
    """Pick a verified type/front only from observations about THIS building."""
    support, against = [], []
    for ob in rec["observations"]:
        if ob.get("style") is None or ob.get("superseded_by"):
            continue
        ok = ob.get("about_target", False)
        (support if ok else against).append(ob)
    styles = {}
    for ob in support:
        w = {"high": 3, "medium": 2, "low": 1}.get(ob.get("confidence"), 1)
        if ob["kind"] == "pose_verified_review":
            w += 2   # known camera pose, ray-verified target and wall
        elif ob["kind"] == "user_google_review":
            w -= 1   # Maps link chose the pano and heading, target not guaranteed
        styles.setdefault(ob["style"], []).append((w, ob["kind"]))
    verified, conf = None, "unverified"
    if styles:
        ranked = sorted(styles.items(), key=lambda kv: -sum(w for w, _ in kv[1]))
        verified = ranked[0][0]
        top = sum(w for w, _ in ranked[0][1])
        second = sum(w for w, _ in ranked[1][1]) if len(ranked) > 1 else 0
        conf = "high" if top >= 4 and top >= 2 * second else "medium" if top > second else "conflict"
    rec["verified_type"] = verified if conf != "conflict" else None
    rec["type_confidence"] = conf
    rec["conflicts"] = [f"{ob['kind']}:{ob['style']} ({ob.get('association', '')})" for ob in against
                        if ob["style"] != verified and ob["kind"] != "gis_zoning"] + (
        [f"{k}:{s}" for s, obs in styles.items() if s != verified for _, k in obs] if verified else [])
    missing = []
    seen = {v.get("wall") for ob in rec["observations"] if ob.get("about_target") for v in [ob]}
    if "front" not in seen:
        missing.append("front")
    if rec["corner"] and "side" not in seen:
        missing.append("street_side")
    missing.append("roof_3d")  # no Google 3D tiles/LiDAR roof read yet in this pipeline
    rec["missing_viewpoints"] = missing
    rec["review_status"] = ("verified" if conf == "high" else "supported" if conf == "medium"
                            else "conflict" if conf == "conflict" else "needs_imagery")


def user_observation(row, rec):
    style = USER_STYLE.get(row["visual_classification"])
    notes = row.get("notes", "")
    ob = dict(kind="user_google_review", style=style, notes=notes,
              confidence=row["visual_confidence"].split()[0].lower(),
              url=row.get("street_view_url", ""), camera="unknown (Maps chose nearest pano to centroid)")
    # The review link opened Google's nearest pano to the footprint CENTROID
    # with a default heading, so the visible building is not guaranteed.
    if KEYWORDS_DUP.search(notes):
        ob.update(about_target=False, wall="unknown", association="duplicate_view_of_other_building")
    elif KEYWORDS_REAR.search(notes):
        street = re.search(r"on (\w+) st", notes, re.I)
        fronts = street and rec["primary_street"] and street.group(1).lower() in rec["primary_street"].lower()
        ob.update(about_target=bool(fronts), wall="rear",
                  association="rear_of_this_building" if fronts else "rear_yard_of_neighbor_on_" + (street.group(1) if street else "?"))
    elif KEYWORDS_SIDE.search(notes):
        street = re.search(r"on (\w+) st", notes, re.I)
        on_street = street and street.group(1).lower() in " ".join(rec["streets"]).lower()
        ob.update(about_target=bool(on_street) or not street, wall="side",
                  association="side_wall_of_this_building" if (on_street or not street) else "side_of_neighbor")
    else:
        ob.update(about_target=True, wall="front", association="user_identified_target")
    return ob


def build_records(scope_ids, fps, roads, photos, user, old, pose=None):
    pose = pose or {}
    road_tree = STRtree([r["line"] for r in roads])
    ids = list(fps)
    tree = STRtree([fps[i]["poly"] for i in ids])
    walls_by_id = {}

    def walls_of(bid):
        if bid not in walls_by_id:
            w, p, _ = frontage(fps[bid], roads, road_tree)
            walls_by_id[bid] = (w, p)
        return walls_by_id[bid]

    class LazyWalls(dict):
        def __missing__(self, bid):
            return walls_of(bid)

    lazy = LazyWalls()
    # cast every camera near the scope once; a photo is evidence for every
    # building it actually shows, not only the one it was downloaded for
    scope_union = [fps[i]["poly"] for i in scope_ids]
    minx = min(p.bounds[0] for p in scope_union) - 80 * SCALE
    minz = min(p.bounds[1] for p in scope_union) - 80 * SCALE
    maxx = max(p.bounds[2] for p in scope_union) + 80 * SCALE
    maxz = max(p.bounds[3] for p in scope_union) + 80 * SCALE
    scope_tree = STRtree(scope_union)
    by_building = {}
    photo_out = []
    for ph in photos:
        x, z = ph["cam"]
        if not (minx <= x <= maxx and minz <= z <= maxz):
            continue
        if not scope_tree.query(Point(x, z).buffer(MAX_RANGE_M * SCALE)).size:
            continue   # scattered scopes (--reviewed): only cameras near a scoped building
        hits = cast(ph, fps, tree, ids)
        verdict, visible = associate(ph, hits, fps, lazy)
        ph = dict(ph, verdict=verdict, visible=visible)
        photo_out.append(ph)
        for v in visible:
            by_building.setdefault(v["building_id"], []).append((ph, v))
    records = {}
    for bid in scope_ids:
        fp = fps[bid]
        walls, primary, streets = frontage(fp, roads, road_tree)
        p = fp["props"]
        rec = dict(building_id=bid,
                   footprint=[[round(x, 2), round(z, 2)] for x, z in fp["poly"].exterior.coords],
                   footprint_area_m2=round(fp["poly"].area / SCALE ** 2, 1),
                   height_m=p.get("height_m"), lonlat=fp["lonlat"],
                   primary_street=primary and primary["street"],
                   front_bearing=primary and primary["bearing"], streets=streets,
                   corner=len(streets) > 1,
                   address=p.get("address") or address_for(fp, primary, roads, road_tree),
                   street_walls=[dict(bearing=w["bearing"], street=w["street"], length_m=w["length_m"])
                                 for w in walls if w["street"]],
                   gis=dict(use=p.get("building_use"), archetype=p.get("generator_archetype"),
                            use_source=p.get("building_use_source"), use_confidence=p.get("building_use_confidence")),
                   images=[], observations=[])
        rec["attachment"], rec["party_walls"] = adjacency(fp, fps, tree, ids)
        for ph, v in by_building.get(bid, []):
            rec["images"].append(dict(source=ph["source"], id=ph["pano"], path=ph["path"], date=ph["date"],
                                      camera=[round(c, 7) for c in ph["cam_ll"]], heading=ph["heading"],
                                      fov=ph["fov"], downloaded_for=ph["downloaded_for"],
                                      fov_share=v["fov_share"], wall=v["wall"], centre=v["centre"],
                                      verdict_for_download_target=ph["verdict"]))
        gis_style = {"commercial": "storefront", "residential": None}.get(p.get("building_use"))
        rec["observations"].append(dict(kind="gis_zoning", style=gis_style, confidence="low",
                                        about_target=False, association="zoning_district_not_a_building_observation"))
        if bid in old:
            o = old[bid]
            img = next((i for i in rec["images"] if o["photo"] and i["path"] == o["photo"]), None)
            if img is None:
                assoc = "evidence_photo_does_not_show_building"
                about = False
            else:
                about = img["centre"] and img["fov_share"] >= 0.25
                assoc = f"evidence_photo_shows_{img['wall']}" + ("" if about else "_not_centred")
            rec["observations"].append(dict(kind="old_photo_override", style=o["style"], confidence=o["confidence"],
                                            about_target=about, wall=img and img["wall"], association=assoc,
                                            photo=o["photo"]))
        if bid in user:
            rec["observations"].append(user_observation(user[bid], rec))
        if bid in pose:
            pr = pose[bid]
            path = "25_GoogleStreetView_Buildings/images/" + pr["photo"]
            img = next((i for i in rec["images"] if i["path"] == path), None)
            ok = bool(img and img["fov_share"] >= 0.25)
            rec["observations"].append(dict(kind="pose_verified_review", style=pr["style"] or None,
                                            confidence=pr["confidence"], about_target=ok,
                                            wall=img and img["wall"], photo=path, notes=pr["notes"],
                                            association=(f"camera_ray_{img['wall']}_share_{img['fov_share']}" if img
                                                         else "photo_not_cast")))
            # the same photograph must not be counted twice
            for ob in rec["observations"]:
                if ob["kind"] == "old_photo_override" and ob.get("photo") == path and ok:
                    ob["superseded_by"] = "pose_verified_review"
            rec["structure"] = {k: v for k, v in pr.items() if k not in ("building_id", "photo", "notes") and v}
        resolve(rec)
        records[bid] = rec
    return records, photo_out


# ------------------------------------------------------------------ fresh Google viewpoints
def fresh_panos(records, fps, budget_images=0):
    """Free Street View metadata calls: one probe opposite every street wall.

    Records the pano id, camera position, date and the heading that points at
    that wall, so a reviewer (or --fetch N, billed) can open an exact view."""
    sys.path.insert(0, str(ROOT / "tools" / "storefronts"))
    import google_streetview as gsv  # noqa: E402
    k = gsv.key()
    meta = gsv.Meta(gsv.OUT_B / "metadata_cache.json")
    fetched = 0
    for rec in records.values():
        fp = fps[rec["building_id"]]
        coords = list(fp["poly"].exterior.coords)
        views = []
        walls, _, _ = frontage(fp, ROADS, ROAD_TREE)
        for w in [w for w in walls if w["street"]][:4]:
            d = (w["street_dist_m"] or 8) * SCALE
            px, pz = w["mid"][0] + w["normal"][0] * d, w["mid"][1] + w["normal"][1] * d
            mx, my = px - X_OFFSET, pz - Z_OFFSET
            lon = mx * 180 / 20037508.34
            lat = math.degrees(2 * math.atan(math.exp(my / 6378137.0)) - math.pi / 2)
            m = meta.get(lat, lon, 20, k)
            if not m:
                views.append(dict(wall_bearing=w["bearing"], street=w["street"], status="no_pano"))
                continue
            cx, cz = src_xy(m["lon"], m["lat"])
            heading = vec_bearing(w["mid"][0] - cx, w["mid"][1] - cz)
            # keyless Google Maps link that opens this exact pano and heading
            url = ("https://www.google.com/maps/@?api=1&map_action=pano"
                   f"&pano={m['pano_id']}&heading={heading:.0f}&pitch=5&fov=80")
            view = dict(wall_bearing=w["bearing"], street=w["street"], pano=m["pano_id"], date=m["date"],
                        camera=[m["lat"], m["lon"]], heading=round(heading, 1), url=url)
            if fetched < budget_images:
                dest = DATA / "25_GoogleStreetView_Buildings" / "images" / rec["building_id"] / \
                    f"wall{w['bearing']:03d}_{m['pano_id']}.jpg"
                dest.parent.mkdir(parents=True, exist_ok=True)
                if not dest.exists() and gsv.fetch(m["pano_id"], heading, 5, 80, dest, k):
                    fetched += 1
                view["path"] = str(dest.relative_to(DATA)).replace("\\", "/") if dest.exists() else None
            views.append(view)
        rec["fresh_google_views"] = views
        # keep the review gaps; add walls Google has no panorama for, and list
        # the exact panos still to inspect for walls no reviewed photo shows
        rec["missing_viewpoints"] += [f"no_pano_for_wall_{v['wall_bearing']}" for v in views if not v.get("pano")]
        seen = {i["wall"] for i in rec["images"] if i["centre"]}
        rec["panos_to_review"] = [v["url"] for v in views if v.get("pano") and
                                  ("front" not in seen or v["street"] != rec["primary_street"])]
    meta.flush()
    print(f"fresh pano metadata calls: {gsv.counters['meta']} (free); images fetched: {fetched}")


# ------------------------------------------------------------------ outputs
def write(records, photos, name):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / f"{name}.json").write_text(json.dumps(dict(properties=records, photos=[
        {k: v for k, v in p.items() if k != "cam"} for p in photos]), indent=1, default=str))
    with (OUT_DIR / f"{name}.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["building_id", "address", "primary_street", "front_bearing", "corner", "gis_use",
                    "verified_type", "type_confidence", "review_status", "images_showing_front",
                    "images_total", "conflicts", "missing_viewpoints"])
        for r in records.values():
            w.writerow([r["building_id"], r["address"], r["primary_street"], r["front_bearing"], r["corner"],
                        r["gis"]["use"], r["verified_type"], r["type_confidence"], r["review_status"],
                        sum(1 for i in r["images"] if i["wall"] == "front" and i["centre"]), len(r["images"]),
                        " | ".join(r["conflicts"]), " ".join(r["missing_viewpoints"])])
    print(f"{len(records)} properties, {len(photos)} camera poses cast -> {OUT_DIR / name}.json/.csv")


def lua_str(v):
    return '"' + str(v).replace("\\", "/").replace('"', "'") + '"'


def write_lua(records):
    """Runtime product (src/server/World/PropertyReconstruction.lua).

    Every processed ID gets its evidence status, geographic frontage and
    attachment. IDs with a pose-verified structural review whose type the
    resolver accepted also get the structure the builders consume: style,
    archetype, roof form, parapet, unit count, door pattern, porch, storeys,
    bay, garage bays, finish. Accumulates block by block."""
    entries = {}
    if LUA_OUT.exists():
        for m in re.finditer(r'^\t\["(\d+)"\]=(\{.*\}),$', LUA_OUT.read_text(encoding="utf-8"), re.M):
            entries[m.group(1)] = m.group(2)
    # a withdrawn review must not leave its structure behind in the runtime
    reviewed = set(load_pose_reviews())
    entries = {k: v for k, v in entries.items()
               if k in reviewed or not re.match(r'\{status="(reconstructed|finish_verified)"', v)}
    for r in records.values():
        st = r.get("structure")
        accepted = st and r["verified_type"] is not None and (not st.get("style") or st["style"] == r["verified_type"])
        accepted = accepted or (st and not st.get("style"))  # finish-only review (e.g. a store side wall)
        status = ("reconstructed" if st.get("style") else "finish_verified") if accepted else r["review_status"]
        f = [f"status={lua_str(status)}", f"evidence={lua_str(r['review_status'])}",
             f"attach={lua_str(r['attachment'])}"]
        if r["verified_type"]:
            f.append(f"type={lua_str(r['verified_type'])}")
        if r["front_bearing"] is not None:
            f.append(f"geoFront={r['front_bearing']}")
        if r["primary_street"]:
            f.append(f"street={lua_str(r['primary_street'])}")
        if accepted:
            if st.get("style"):
                f.append(f"style={lua_str(st['style'])}")
            if st.get("arch"):
                f.append(f"arch={lua_str(st['arch'])}")
            if st.get("use"):
                f.append(f"use={lua_str(st['use'])}")
            if st.get("material"):
                f.append(f"material={lua_str(st['material'])}")
            if st.get("wall"):
                f.append(f"wall=0x{st['wall']}")
            if st.get("porch") in ("0", "1"):
                f.append(f"porch={'true' if st['porch'] == '1' else 'false'}")
            if st.get("bay") == "1":
                f.append("bay=true")
            if st.get("front"):
                f.append(f"front={int(st['front'])}")
            if st.get("garage_bays"):
                f.append(f"garageBays={int(st['garage_bays'])}")
            if st.get("roof") in ("gable", "front_gable", "side_gable") and st.get("style") in ("garage", "church", "school"):
                f.append('roof="gable"')
            spec = [f"{k}={st[src]}" for k, src in (("roof", "roof"), ("par", "parapet"), ("door", "door"),
                                                   ("units", "units"), ("floors", "floors")) if st.get(src)]
            if spec:
                f.append(f"spec={lua_str('/'.join(spec))}")
            f.append(f"confidence={lua_str(st.get('confidence', 'medium'))}")
            photo = next((o["photo"] for o in r["observations"] if o["kind"] == "pose_verified_review"), "")
            f.append(f"photo={lua_str(photo)}")
        entries[r["building_id"]] = "{" + ",".join(f) + "}"
    body = "".join(f'\t["{k}"]={v},\n' for k, v in sorted(entries.items(), key=lambda kv: int(kv[0])))
    LUA_OUT.write_text("-- Generated by tools/reconstruction/property_evidence.py - do not hand edit;\n"
                       "-- edit tools/reconstruction/pose_reviews.csv and re-run. ChesterBuildingId ->\n"
                       "-- geographic evidence status (status = reconstructed | verified | supported |\n"
                       "-- conflict | needs_imagery), county-centreline frontage (geoFront, compass\n"
                       "-- bearing), party-wall attachment, and for reconstructed IDs the structure the\n"
                       "-- builders apply (spec: roof/par(apet)/door pattern viewer-left->right/units/floors).\n"
                       "return {\n" + body + "}\n", encoding="utf-8")
    print(f"{LUA_OUT}: {len(entries)} IDs, {sum('reconstructed' in v for v in entries.values())} reconstructed")


def render(records, fps, photos, name):
    """Aerial + footprints + camera rays debug map (private reference)."""
    from PIL import Image, ImageDraw
    tile = DATA / "19_Aerial" / "dvrpc2025_1m_-8392000_4842000.jpg"
    img = Image.open(tile).convert("RGB")
    xs = [x for r in records.values() for x, _ in r["footprint"]]
    zs = [z for r in records.values() for _, z in r["footprint"]]
    pad = 25
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad

    def px(x, z):  # source metres -> tile pixel (1 m/px, tile origin -8392000,4842000..4844000)
        return (x - X_OFFSET + 8392000), (4844000 - (z - Z_OFFSET))
    a, b = px(x0, z1), px(x1, z0)
    k = 4
    crop = img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1]))).resize((int(b[0] - a[0]) * k, int(b[1] - a[1]) * k))
    d = ImageDraw.Draw(crop)

    def P(x, z):
        u, v = px(x, z)
        return (u - int(a[0])) * k, (v - int(a[1])) * k
    for r in ROADS or []:
        if r["line"].bounds[2] < x0 or r["line"].bounds[0] > x1 or r["line"].bounds[3] < z0 or r["line"].bounds[1] > z1:
            continue
        d.line([P(x, z) for x, z in r["line"].coords], fill="magenta", width=2)
        m = r["line"].interpolate(0.5, normalized=True)
        d.text(P(m.x, m.y), r["name"], fill="magenta", stroke_width=2, stroke_fill="white")
    colour = {"verified": "lime", "supported": "yellow", "conflict": "red", "needs_imagery": "cyan"}
    for r in records.values():
        d.line([P(x, z) for x, z in r["footprint"]], fill=colour[r["review_status"]], width=2)
        c = fps[r["building_id"]]["poly"].centroid
        d.text(P(c.x, c.y), r["building_id"], fill="white", stroke_width=2, stroke_fill="black")
    for ph in photos:
        cx, cz = ph["cam"]
        for h in (ph["heading"] - ph["fov"] / 2, ph["heading"], ph["heading"] + ph["fov"] / 2):
            ex, ez = bearing_vec(h)
            d.line([P(cx, cz), P(cx + ex * 14 * SCALE, cz + ez * 14 * SCALE)], fill="orange", width=1)
        d.text(P(cx, cz), ph["downloaded_for"], fill="orange")
    out = OUT_DIR / f"{name}_map.jpg"
    crop.save(out, quality=88)
    print(out)


ROADS = ROAD_TREE = None


def main():
    global ROADS, ROAD_TREE
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", help="W,S,E,N lon/lat")
    ap.add_argument("--name", default="9th_kerlin")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--reviewed", action="store_true", help="scope = every ID in pose_reviews.csv")
    ap.add_argument("--fresh-panos", action="store_true", help="free Google metadata probes per street wall")
    ap.add_argument("--fetch-images", type=int, default=0, help="billed Static images, hard cap")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--no-lua", action="store_true")
    ap.add_argument("--lua", action="store_true", help="with --all: also write every ID into the runtime module")
    a = ap.parse_args()
    fps = load_footprints()
    ROADS = load_roads()
    ROAD_TREE = STRtree([r["line"] for r in ROADS])
    if a.reviewed:
        scope = [i for i in load_pose_reviews() if i in fps]
        a.name = "reviewed"
    elif a.all:
        scope = list(fps)
        a.name = "citywide"
    else:
        w, s, e, n = map(float, a.bbox.split(",")) if a.bbox else KERLIN
        scope = [i for i, f in fps.items() if any(w <= lon <= e and s <= lat <= n for lon, lat in
                 [((x - X_OFFSET) * 180 / 20037508.34,
                   math.degrees(2 * math.atan(math.exp((z - Z_OFFSET) / 6378137.0)) - math.pi / 2))
                  for x, z in f["poly"].exterior.coords])]
    user_path, user = load_user_reviews()
    print(f"scope {a.name}: {len(scope)} footprints; user review: {user_path} ({len(user)} rows)")
    records, photos = build_records(scope, fps, ROADS, load_photos(), user, load_old_overrides(), load_pose_reviews())
    if a.fresh_panos:
        fresh_panos(records, fps, a.fetch_images)
    write(records, photos, a.name)
    # citywide evidence is a review queue; the runtime module grows block by
    # block (--bbox) unless --lua explicitly asks for every ID
    if not a.no_lua and (not a.all or a.lua):
        write_lua(records)
    if a.render:
        render(records, fps, photos, a.name)


if __name__ == "__main__":
    main()
