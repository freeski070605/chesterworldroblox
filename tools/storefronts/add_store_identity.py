"""Store identity: every storefront business gets its own shopfront + sign.

Source: Overture Maps places (build/_overture_places_bbox.parquet - Chester,
Brookhaven, Eddystone, Woodlyn, Parkside, Upland, Marcus Hook, Trainer ...).
Each open, storefront-kind business (food, takeout, corner store, market,
barber / salon, pharmacy, dollar store, apparel, phone, laundromat, check
cashing, bank, bar ...) with a usable name is matched to the building
footprint it stands in (or the nearest within MATCH_M). Each matched building
section gets a sign: the business name in brand colours (known chains / local
staples such as NY Fried Chicken, Happy House) or its category's colours,
facing the nearest public street. The building gets a shopfront ground floor
(gs=1).

Written to BuildingTiles as  ss={{"Name",rect,bearing,0xBG,0xTEXT},...}
(rect = 0-based section index). Buildings already carrying a Street View
verified sign (sb=) keep it. Idempotent: ss= is stripped and rewritten.

Pipeline: after tools/add_porches.py (which rewrites gs / sc / st).

    py -3 tools/storefronts/add_store_identity.py [--check]
"""
import math
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fit_roads_to_buildings as fit  # noqa: E402

PLACES = ROOT / "build" / "_overture_places_bbox.parquet"
MATCH_M = 10.0
MIN_CONF = 0.6
MAX_PER_BUILDING = 6

# Overture basic_category -> sign palette key (None = not a storefront)
CATEGORY = {
    "restaurant": "food", "casual_eatery": "food", "fast_food_restaurant": "food", "pizzaria": "food",
    "bakery": "food", "cafe": "cafe", "coffee_shop": "cafe", "ice_cream_shop": "food", "dessert_shop": "food",
    "food_and_beverage_store": "market", "convenience_store": "market", "grocery_store": "market",
    "supermarket": "market", "deli": "market", "liquor_store": "market", "beer_wine_and_spirits": "market",
    "bar": "bar", "pub": "bar", "lounge": "bar", "nightclub": "bar",
    "personal_or_beauty_service": "beauty", "beauty_salon": "beauty", "barber": "beauty", "nail_salon": "beauty",
    "hair_salon": "beauty", "beauty_supply_store": "beauty",
    "pharmacy_and_drug_store": "pharmacy",
    "discount_store": "discount", "department_store": "discount", "general_merchandise_store": "discount",
    "fashion_and_apparel_store": "apparel", "shoe_store": "apparel", "clothing_store": "apparel",
    "electronics_store": "phone", "mobile_phone_store": "phone",
    "laundry_service": "laundry", "laundromat": "laundry", "dry_cleaning": "laundry",
    "financial_service": "money", "bank_or_credit_union": "bank", "check_cashing": "money",
    "hardware_home_and_garden_store": "hardware", "furniture_store": "hardware",
    "pet_store": "retail", "florist": "retail", "gift_shop": "retail", "book_store": "retail",
    "sporting_goods_store": "retail", "jewelry_store": "retail", "thrift_store": "retail",
    "tattoo_or_piercing_salon": "beauty", "specialty_store": "retail", "retail": "retail",
}
PALETTE = {  # (sign background, text)
    "food": ((196, 30, 36), (255, 214, 40)), "cafe": ((70, 44, 30), (245, 235, 220)),
    "market": ((24, 92, 56), (255, 255, 255)), "bar": ((30, 30, 34), (255, 196, 80)),
    "beauty": ((120, 40, 120), (255, 255, 255)), "pharmacy": ((20, 80, 160), (255, 255, 255)),
    "discount": ((240, 196, 30), (30, 30, 30)), "apparel": ((24, 24, 28), (255, 255, 255)),
    "phone": ((230, 90, 20), (255, 255, 255)), "laundry": ((40, 120, 200), (255, 255, 255)),
    "money": ((28, 70, 160), (240, 190, 40)), "bank": ((16, 50, 100), (255, 255, 255)),
    "hardware": ((180, 40, 30), (255, 255, 255)), "retail": ((40, 60, 90), (255, 255, 255)),
}
# brands / local staples by name (lower-case substring -> bg, text)
BRANDS = [
    ("fried chicken", ((200, 24, 30), (255, 220, 40))),     # NY / Chester / Kennedy Fried Chicken
    ("happy house", ((200, 24, 30), (255, 220, 40))),
    ("mcdonald", ((218, 41, 28), (255, 199, 44))), ("popeyes", ((240, 110, 30), (255, 255, 255))),
    ("dunkin", ((255, 105, 30), (220, 30, 140))), ("wawa", ((180, 20, 40), (255, 210, 40))),
    ("subway", ((0, 130, 60), (255, 200, 20))), ("wendy", ((200, 20, 40), (255, 255, 255))),
    ("burger king", ((240, 110, 30), (80, 40, 20))), ("checkers", ((200, 20, 30), (255, 255, 255))),
    ("rite aid", ((20, 70, 150), (255, 255, 255))), ("cvs", ((204, 0, 0), (255, 255, 255))),
    ("walgreens", ((225, 30, 40), (255, 255, 255))), ("family dollar", ((230, 90, 20), (255, 255, 255))),
    ("dollar general", ((255, 210, 0), (20, 20, 20))), ("dollar tree", ((0, 120, 60), (255, 255, 255))),
    ("rent-a-center", ((255, 210, 0), (20, 60, 140))), ("aaron", ((230, 120, 20), (255, 255, 255))),
    ("metro by t-mobile", ((110, 40, 160), (255, 255, 255))), ("boost", ((240, 120, 20), (20, 20, 20))),
    ("cricket", ((0, 140, 80), (255, 255, 255))), ("t-mobile", ((226, 0, 116), (255, 255, 255))),
    ("pizza", ((190, 30, 30), (255, 255, 255))), ("deli", ((24, 92, 56), (255, 255, 255))),
    ("beauty supply", ((150, 30, 110), (255, 255, 255))), ("barber", ((20, 40, 110), (255, 255, 255))),
    ("laundromat", ((40, 120, 200), (255, 255, 255))), ("check cashing", ((28, 70, 160), (240, 190, 40))),
    ("pnc", ((240, 110, 30), (255, 255, 255))), ("wells fargo", ((200, 20, 30), (255, 200, 40))),
    ("td bank", ((50, 160, 60), (255, 255, 255))), ("santander", ((236, 0, 0), (255, 255, 255))),
    ("citizens", ((0, 120, 90), (255, 255, 255))), ("acme", ((200, 20, 30), (255, 255, 255))),
    ("aldi", ((0, 40, 120), (255, 160, 30))), ("save a lot", ((230, 30, 30), (255, 220, 40))),
]
# importance for choosing one business per building section
RANK = {"food": 9, "market": 9, "pharmacy": 8, "discount": 8, "beauty": 7, "bar": 7, "money": 7, "phone": 6,
        "laundry": 6, "apparel": 6, "bank": 6, "cafe": 8, "hardware": 5, "retail": 5}
# Staple shops verified on Street View that Overture rates low or places off
# the building (9th & Concord, 2026-11-07): name, category, building id, a
# point on the shop (studs) to pick the building section, address street
# (the point may be a section index instead)
CURATED = [
    ("Boost Mobile", "phone", "93584", (2944, 1671), "Concord"),
    # the strip's middle store is J & S (owner's local knowledge, 2026-11-07);
    # Overture's "Lee Seafood" listing is out of date - see SUPPRESS
    ("J & S", "food", "93584", 2, "Concord"),
    ("D's Laundromat", "laundry", "48391", None, "Kerlin"),
]
# Overture listings that are out of date (name or business changed)
SUPPRESS = {"lee seafood"}
# Buildings whose shops all open onto one street regardless of their mailing
# address (Street View): the 805 Concord Ave strip faces its parking lot on
# Concord, though Lee Seafood is listed at 823 Kerlin
FACING = {"93584": "concord"}
STREET_SUFFIX = re.compile(r"\b(st|street|ave|av|avenue|rd|road|blvd|boulevard|dr|drive|ln|lane|pl|place|"
                           r"pike|pk|pke|hwy|highway|way|ct|court|ter|terrace|cir|circle)\b\.?")


def street_key(name):
    """'901 W 9th St' / 'W 9th St' / '9th' -> '9th'; 'Concord Ave' -> 'concord'"""
    n = (name or "").lower().replace(".", " ")
    n = re.sub(r"#.*$", "", n)
    n = re.sub(r"^\s*[\d-]+[a-z]?\s+", "", n)            # house number
    n = re.sub(r"\b(w|e|n|s|west|east|north|south)\b", " ", n)
    n = STREET_SUFFIX.sub(" ", n)
    return re.sub(r"\s+", " ", n).strip()


LINE_RE = re.compile(r'^(\s*\["(\d+)"\]=\{)(.*?)(\}\},?\s*)$')


def to_source(x, z):
    return x / 3.0 + 6347.889, 7201.973 - z / 3.0


def studs(lon, lat):
    mx = lon * 20037508.34 / 180.0
    my = math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0
    return (mx + 8397592 - 6347.889) * 3, -(my - 4837229 - 7201.973) * 3


def face_bearing(rect, street):
    """compass bearing of the outward normal of the rect face nearest the
    street (source metres: x east, z north). A shop or house fronts on its
    nearest face, not on whichever face points roughly toward the street (a
    narrow strip unit 8 m wide x 25 m deep would otherwise get its side wall)."""
    from shapely.geometry import Point as _P
    c = rect.centroid
    pts = list(rect.exterior.coords)[:4]
    best = None
    for i in range(4):
        (x1, z1), (x2, z2) = pts[i], pts[(i + 1) % 4]
        mx, mz = (x1 + x2) / 2, (z1 + z2) / 2
        d = street.distance(_P(mx, mz))
        if best is None or d < best[0]:
            best = (d, mx - c.x, mz - c.y)
    return math.degrees(math.atan2(best[1], best[2])) % 360


def clean_name(n):
    n = re.sub(r"\s+", " ", n.replace("&amp;", "&")).strip()
    n = re.sub(r"(?i)\s*&\s*grill$", " & Grill", n)
    n = re.sub(r"(?i)^n y ", "NY ", n)
    return n[:28]


def palette(name, key):
    low = name.lower()
    for k, c in BRANDS:
        if k in low:
            return c
    return PALETTE[key]


def main(check=False):
    import pandas as pd
    from shapely.geometry import LineString, Point
    from shapely.strtree import STRtree
    df = pd.read_parquet(PLACES)
    polys, keys = fit.footprints(with_keys=True)
    tree = STRtree(polys)
    # public streets for the facing bearing
    streets, street_keys = [], []
    for path in sorted(fit.TILES.glob("tile_*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = fit.ROAD_RE.match(line)
            if m and fit.kind(m) in ("local", "main", "minor") and m["name"] not in fit.RAIL_NAMES:
                streets.append(LineString([(float(m["x1"]), float(m["z1"])), (float(m["x2"]), float(m["z2"]))]))
                street_keys.append(street_key(m["name"]))
    street_tree = STRtree(streets)
    stats = Counter()
    by_section = {}
    for r in df.itertuples():
        names = r.names or {}
        name = (names.get("primary") or "").strip()
        key = CATEGORY.get(r.basic_category or "")
        if not name or not key or (r.confidence or 0) < MIN_CONF:
            continue
        if name.lower() in SUPPRESS:
            stats["suppressed"] += 1
            continue
        if r.operating_status and r.operating_status not in ("open",):
            stats["closed"] += 1
            continue
        if key == "money" and not any(w in name.lower() for w in ("check", "cash", "loan", "tax", "money")):
            continue   # financial advisers / insurance offices are not shopfronts
        sx, sz = to_source(*studs(r.lon, r.lat))
        pt = Point(sx, sz)
        best, bd = None, MATCH_M
        for i in tree.query(pt.buffer(MATCH_M)):
            d = polys[i].distance(pt)
            if d < bd:
                best, bd = i, d
        if best is None:
            stats["no_building"] += 1
            continue
        fname, bid, k = keys[best]
        score = RANK.get(key, 4) + (r.confidence or 0)
        addr = (r.addresses[0].get("freeform") if r.addresses is not None and len(r.addresses) else "") or ""
        cur = by_section.get((bid, k))
        if cur is None or score > cur[0]:
            by_section[(bid, k)] = (score, clean_name(name), key, best, fname, street_key(addr), r.id)
        stats["matched"] += 1
    index_of = {(k[1], k[2]): i for i, k in enumerate(keys)}
    for name, key, bid, pt, street in CURATED:
        secs = [k for (b, k) in index_of if b == bid]
        if not secs:
            continue
        if pt is None:
            k = 0
        elif isinstance(pt, int):
            k = pt
        else:
            sx, sz = to_source(*pt)
            k = min(secs, key=lambda kk: polys[index_of[(bid, kk)]].distance(Point(sx, sz)))
        by_section[(bid, k)] = (99.0, name, key, index_of[(bid, k)], "", street_key(street), "curated:" + name)
        stats["curated"] += 1
    # per building: sections in score order, capped
    per_building = defaultdict(list)
    for (bid, k), (score, name, key, idx, fname, skey, pid) in by_section.items():
        per_building[bid].append((score, k, name, key, idx, skey, pid))
    shops = {}
    for bid, items in per_building.items():
        items.sort(reverse=True)
        seen_names = set()
        out = []
        for score, k, name, key, idx, skey, pid in items[:MAX_PER_BUILDING]:
            if name.lower() in seen_names:
                continue
            seen_names.add(name.lower())
            c = polys[idx].centroid
            cand = list(street_tree.query(c.buffer(120)))
            # the shop faces the street in its address; else the nearest street
            skey = FACING.get(bid, skey)
            same = [j for j in cand if skey and street_keys[j] == skey and streets[j].distance(c) < 60]
            if same:
                stats["address_street"] += 1
            near = min(same or [j for j in cand if streets[j].distance(c) < 80],
                       key=lambda j: streets[j].distance(c), default=None)
            if near is None:
                bearing = 0
            else:
                bearing = round(face_bearing(polys[idx], streets[near]))
            bg, tx = palette(name, key)
            out.append((name, k, bearing, bg, tx, pid))
        shops[bid] = out
    stats["buildings"] = len(shops)
    stats["signs"] = sum(len(v) for v in shops.values())

    files_changed = 0
    for path in sorted(fit.BUILDINGS.glob("*.lua")):
        lines = path.read_text(encoding="utf-8").split("\n")
        out = []
        for line in lines:
            m = LINE_RE.match(line)
            if m:
                # (earlier runs appended gs=1 inside the r={...} list, where
                # TileBuilderV2 never saw it: move it out)
                body = re.sub(r",gs=1$", "", m.group(3))
                body = re.sub(r",ss=\{\{.*?\}\}(?=,|$)", "", body)
                body = re.sub(r",ss=\{\}", "", body)
                bid = m.group(2)
                if bid in shops:
                    # (a building with a verified sign keeps it; its other shops
                    # are added - the 805 Concord Ave strip)
                    entries = ",".join('{"%s",%d,%d,0x%02x%02x%02x,0x%02x%02x%02x,"%s"}' % (
                        n.replace('"', "'"), k, b, *bg, *tx, str(pid)) for n, k, b, bg, tx, pid in shops[bid])
                    gs = "" if ",gs=1" in body else ",gs=1"
                    body = body.replace(",r={", "%s,ss={%s},r={" % (gs, entries), 1)
                    stats["written"] += 1
                line = m.group(1) + body + m.group(4)
            out.append(line)
        if out != lines:
            files_changed += 1
            if not check:
                path.write_text("\n".join(out), encoding="utf-8")
    stats["files"] = files_changed
    print(dict(stats))


if __name__ == "__main__":
    main("--check" in sys.argv)
