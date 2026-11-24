"""Citywide inventory of schools, churches and other institutional buildings.

Joins, per stable county building id (ChesterBuildingId = county OBJECTID):
  * the regional master GIS record (13_RegionalMaster/regional_buildings_base:
    OSM POI identity, address, building_use, official school match, LiDAR
    height, footprint dimensions/orientation),
  * the in-game record (src/shared/WorldData/BuildingTiles: style, height,
    rectangles, name, frontage bearing),
  * the local Street View reference (25_GoogleStreetView_Buildings manifest:
    camera pose, distance, date) and Mapillary coverage,
  * the photo-reviewed institution spec, if any
    (src/server/World/InstitutionReconstruction.lua).

Writes build/institutions/inventory.{csv,json} and 3x3 review sheets of the
reference photos (build/institutions/sheets/). The sheets are a viewing aid;
the cited evidence is always the original photo path.

    py -3 tools/reconstruction/institution_inventory.py [--sheets]
"""
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(r"E:\ChesterWorld\Data")
OUT = ROOT / "build" / "institutions"
TILES = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"
SPEC = ROOT / "src" / "server" / "World" / "InstitutionReconstruction.lua"

NAME_RE = re.compile(r"church|school|chapel|academy|temple|ministr|baptist|tabernacle|mosque|masjid|"
                     r"cathedral|parish|gospel|elementary|charter|convent|seminary|meeting|fellowship|"
                     r"iglesia|cogic|kingdom hall|synagogue|day care|child ?care|learning|kidz", re.I)
# names that match NAME_RE but are not institutions of worship or learning
NOT_INSTITUTION = re.compile(r"ballroom|wedding chapel|social security|township administration", re.I)


# Photos reviewed on 2026-11-24 (build/institutions/sheets) that cannot carry a
# reconstruction: the reason is kept so the building is not silently "done".
PHOTO_UNUSABLE = {
    "3394": "photo shows a mural wall and parking lot, not the academy's facade",
    "32087": "box truck blocks the whole view",
    "60699": "camera centred between a rowhouse and a low stucco building; identity unclear",
    "79550": "photo shows brick rowhouses (1504/1506), not the church",
    "90381": "2007 image, building hidden behind trees",
    "131545": "trees and fence hide the building",
    "133426": "trees hide the building",
    "143358": "interior image (nursing lab), no exterior",
    "156127": "overexposed image",
    "159545": "tree in front of the lens",
    "161293": "trees hide the building",
    "163157": "tree hides the facade",
    "199239": "trees hide the building",
    "51140": "tree hides most of the house",
    "126997": "trees hide the house",
    "48219": "tree hides the house",
    "134163": "2019 image shows a 'Grand Opening' storefront; current church use unverified",
    "60370": "NOT A CHURCH: Minaret Temple 174 is a fraternal (Shriners) lodge; photo shows a garage in front; left generic",
    "169877": "photo shows the campus pergola gateway, not the building",
    "184264": "photo shows two different houses; footprint identity ambiguous",
    "163783": "unnamed; photo shows a gabled brick house-like building behind a tree; use unverified",
}


def area_of(tile):
    """Geographic batch (tile row / column) used for the reconstruction commits."""
    if not tile:
        return ""
    r, c = int(tile[1:3]), int(tile[5:7])
    if r <= 5 and c <= 5:
        return "West End"
    if r >= 8:
        return "North / Widener"
    if c >= 8:
        return "East Side"
    return "Central West"


def tile_records():
    out = {}
    for f in sorted(TILES.glob("tile_*.lua")):
        text = f.read_text(encoding="utf-8")
        for m in re.finditer(r'\["(\d+)"\]=\{(.*?)\}\}\},?\n', text):
            body = m.group(2)
            rects = re.findall(r"\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)(?:\}|$)", body)
            name = re.search(r'name="([^"]*)"', body)
            fb = re.search(r"\bfb=(\d+)", body)
            fl = re.search(r"floors=(\d+)", body)
            out[m.group(1)] = {
                "tile": f.stem[5:],
                "style": re.search(r'style="(\w+)"', body).group(1),
                "h": float(re.search(r"\bh=([\d.]+)", body).group(1)),
                "floors": int(fl.group(1)) if fl else None,
                "name": name.group(1) if name else "",
                "fb": int(fb.group(1)) if fb else None,
                "rects": len(rects),   # the last rectangle's closing brace ends the record
                "rect_area_m2": round(sum(float(r[2]) * float(r[3]) for r in rects), 1),
            }
    return out


def master_records():
    feats = json.loads((DATA / "13_RegionalMaster" / "regional_buildings_base.geojson").read_text(encoding="utf-8"))["features"]
    return {str(f["properties"]["OBJECTID"]): f["properties"] for f in feats}


def photo_manifest():
    out = {}
    with open(DATA / "25_GoogleStreetView_Buildings" / "manifest.csv", encoding="utf-8-sig") as fh:
        for row in csv.DictReader(fh):
            if row["status"] == "ok":
                out.setdefault(row["objectid"], []).append(row)
    return out


def reviewed_specs():
    if not SPEC.exists():
        return {}
    text = SPEC.read_text(encoding="utf-8")
    out = {}
    # an entry runs until the next entry, section rule or the closing brace
    for m in re.finditer(r'\["(\d+)"\]=\{kind="(\w+)"(.*?)(?=\n\["|\n-{6}|\n\}\s*$)', text, re.S):
        body = m.group(3)

        def field(key):
            f = re.search(key + r'="([^"]*)"', body)
            return f.group(1) if f else ""
        out[m.group(1)] = {"kind": m.group(2), "confidence": field("confidence"), "arch": field("arch"),
                           "seen": field("seen"), "note": field("note")}
    return out


def classify(tile, master):
    use = (master or {}).get("building_use", "")
    name = (tile or {}).get("name") or (master or {}).get("poi_name") or (master or {}).get("official_school_name") or ""
    if NOT_INSTITUTION.search(name):
        return None
    style = (tile or {}).get("style", "")
    if use == "religious" or style == "church":
        return "religious"
    if use == "education" or style == "school" or (master or {}).get("official_school_name"):
        return "education"
    if NAME_RE.search(name):
        return "education" if re.search(r"school|academy|elementary|charter|day care|child ?care|learning|kidz|seminary", name, re.I) else "religious"
    return None


def main(make_sheets):
    tiles, master, photos, specs = tile_records(), master_records(), photo_manifest(), reviewed_specs()
    mapillary = {p.name for p in (DATA / "24_BuildingImagery_Mapillary" / "images").iterdir()}
    rows = []
    for bid in sorted(set(tiles) | set(master), key=int):
        t, m = tiles.get(bid), master.get(bid)
        kind = classify(t, m)
        if not kind:
            continue
        m = m or {}
        ph = (photos.get(bid) or [None])[0]
        name = (t or {}).get("name") or m.get("poi_name") or m.get("official_school_name") or ""
        conflicts = []
        if t and kind == "education" and t["style"] not in ("school",):
            conflicts.append(f"styled {t['style']}")
        if t and kind == "religious" and t["style"] != "church":
            conflicts.append(f"styled {t['style']}")
        if m.get("official_school_name") and m.get("poi_name") and m["official_school_name"] != m["poi_name"]:
            conflicts.append(f"POI '{m['poi_name']}' vs official '{m['official_school_name']}'")
        if not t:
            conflicts.append("not in BuildingTiles (outside built world or dropped)")
        rows.append({
            "id": bid, "kind": kind, "name": name,
            "address": m.get("address") or m.get("official_school_address") or "",
            "tile": (t or {}).get("tile", ""), "style": (t or {}).get("style", ""),
            "h_m": (t or {}).get("h") or round(m.get("height_m") or 0, 2),
            "floors": (t or {}).get("floors") or "",
            "footprint_m": f"{m.get('footprint_width_m', '')}x{m.get('footprint_depth_m', '')}",
            "area_m2": m.get("footprint_area_m2", ""), "orient_deg": m.get("footprint_orientation_deg", ""),
            "rects": (t or {}).get("rects", ""), "fb": (t or {}).get("fb", ""),
            "use_source": m.get("building_use_source", ""), "official_school": m.get("official_school_name", ""),
            "photo": ph["path"].replace("\\", "/") if ph else "",
            "photo_date": ph["capture_date"] if ph else "", "photo_heading": ph["camera_heading_deg"] if ph else "",
            "photo_dist_m": ph["distance_m"] if ph else "", "photo_road": ph["road"] if ph else "",
            "mapillary": bid in mapillary,
            "area": area_of((t or {}).get("tile", "")),
            "status": ("reconstructed" if specs.get(bid, {}).get("kind") in ("church", "school", "campus", "ruin")
                       else specs[bid]["kind"] if bid in specs
                       else "photo_unusable" if bid in PHOTO_UNUSABLE
                       else "no_photo" if not ph else "not_reviewed"),
            "reviewed_kind": specs.get(bid, {}).get("kind", ""),
            "arch": specs.get(bid, {}).get("arch", ""),
            "seen_in_photo": specs.get(bid, {}).get("seen", ""),
            "reviewed_confidence": specs.get(bid, {}).get("confidence", ""),
            "review_note": specs.get(bid, {}).get("note", "") or PHOTO_UNUSABLE.get(bid, ""),
            "conflicts": "; ".join(conflicts),
        })
    OUT.mkdir(parents=True, exist_ok=True)
    with open(OUT / "inventory.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    (OUT / "inventory.json").write_text(json.dumps(rows, indent=1), encoding="utf-8")
    by = {}
    for r in rows:
        by.setdefault(r["kind"], [0, 0, 0])
        by[r["kind"]][0] += 1
        by[r["kind"]][1] += bool(r["photo"])
        by[r["kind"]][2] += bool(r["reviewed_kind"])
    for k, (n, p, rv) in by.items():
        print(f"{k}: {n} buildings, {p} with a reference photo, {rv} photo-reviewed specs")
    if make_sheets:
        sys.path.insert(0, str(Path(__file__).parent))
        from PIL import Image, ImageDraw
        cell, bar, cols = 480, 20, 3
        withp = [r for r in rows if r["photo"]]
        (OUT / "sheets").mkdir(exist_ok=True)
        for s in range(0, len(withp), 9):
            chunk = withp[s:s + 9]
            canvas = Image.new("RGB", (cell * cols, (cell + bar) * 3), "black")
            d = ImageDraw.Draw(canvas)
            for k, r in enumerate(chunk):
                x, y = (k % cols) * cell, (k // cols) * (cell + bar)
                im = Image.open(DATA / "25_GoogleStreetView_Buildings" / r["photo"]).convert("RGB")
                im.thumbnail((cell, cell))
                canvas.paste(im, (x, y + bar))
                d.rectangle([x, y, x + cell - 1, y + bar - 1], fill=(30, 30, 30))
                d.text((x + 3, y + 4), f"{r['id']} {r['name'][:40]} h{r['h_m']}", fill="yellow")
            canvas.save(OUT / "sheets" / f"sheet_{s // 9:02d}.jpg", quality=88)
        print("sheets", (len(withp) + 8) // 9)


if __name__ == "__main__":
    main("--sheets" in sys.argv)
