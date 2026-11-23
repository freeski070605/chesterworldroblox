"""Geographic batch review: turn ray-verified local photos into inspected rows.

The citywide evidence (build/property_evidence/citywide.json) already knows,
for every camera pose, which footprint each photo is centred on and which
wall it sees. This tool picks, for a set of tiles, every building whose own
FRONT wall is centred in at least one local photo (fov share >= 0.25), that
has no pose review yet, orders them street by street, and writes
full-resolution 2x2 review sheets (tools/reconstruction/photo_sheet.py).

The reviewer then LOOKS at every sheet and records observations in a
verdict file (one line per photo, see VERDICT FORMAT); `apply` appends them
to pose_reviews.csv with the photo path, share and sheet position. Nothing
is written for a photo the reviewer skips, so an un-inspected or ambiguous
photo can never become evidence.

    py -3 tools/reconstruction/batch_review.py sheets --tiles r06_c07,r05_c07 --name b01
    py -3 tools/reconstruction/batch_review.py apply build/review_sheets/b01/verdicts.txt

VERDICT FORMAT (whitespace separated, '-' = unknown/blank):
    <sheet#>.<cell> <id> <style> <arch> <units> <roof> <porch> <floors> <bay> <garage_bays> <wall_hex> <confidence> | notes
    style: rowhouse twin house apartment garage storefront commercial church school SKIP
    roof:  flat side_gable front_gable hip mansard shed gable
A row whose style is SKIP is recorded in the batch log only (not evidence).
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "reconstruction"))
from photo_sheet import sheet  # noqa: E402

DATA = Path(r"E:\ChesterWorld\Data")
EVIDENCE = ROOT / "build" / "property_evidence" / "citywide.json"
POSE = ROOT / "tools" / "reconstruction" / "pose_reviews.csv"
TILES = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"
SHEETS = ROOT / "build" / "review_sheets"
LOG = ROOT / "docs" / "batch_review_log.csv"
FIELDS = ["building_id", "photo", "style", "arch", "units", "roof", "parapet", "door", "porch", "floors",
          "bay", "garage_bays", "material", "wall", "front", "use", "confidence", "notes"]
STYLES = {"rowhouse", "twin", "house", "apartment", "garage", "storefront", "commercial", "church", "school"}
ROOFS = {"flat", "side_gable", "front_gable", "hip", "mansard", "shed", "gable"}
USE = {"rowhouse": "residential", "twin": "residential", "house": "residential", "apartment": "residential",
       "garage": "garage", "church": "religious", "school": "institutional",
       "storefront": "commercial", "commercial": "commercial"}


def tile_records():
    out = {}
    line = re.compile(r'^\s*\["(\d+)"\]=\{(.*)\}\s*,?\s*$')
    for tile in TILES.glob("tile_*.lua"):
        for raw in tile.read_text(encoding="utf-8").splitlines():
            m = line.match(raw)
            if m:
                body = m.group(2)
                style = re.search(r'style="(\w+)"', body)
                floors = re.search(r"floors=(\d+)", body)
                out[m.group(1)] = dict(tile=tile.stem.removeprefix("tile_"), style=style and style.group(1),
                                       floors=floors and floors.group(1), shops="ss={" in body)
    return out


def best_front_photo(rec):
    best = None
    for im in rec["images"]:
        if im["source"] != "google_streetview" or not im["centre"] or im["wall"] != "front":
            continue
        if im["fov_share"] < 0.25:
            continue
        if best is None or im["fov_share"] > best["fov_share"]:
            best = im
    return best


def cmd_sheets(a):
    tiles = set(a.tiles.split(","))
    ev = json.loads(EVIDENCE.read_text(encoding="utf-8"))["properties"]
    reviewed = {r["building_id"] for r in csv.DictReader(POSE.open(encoding="utf-8"))}
    tr = tile_records()
    picks = []
    for bid, rec in ev.items():
        t = tr.get(bid)
        if not t or t["tile"] not in tiles or bid in reviewed:
            continue
        if a.skip_shops and t["shops"]:
            continue
        im = best_front_photo(rec)
        if not im:
            continue
        picks.append((rec.get("primary_street") or "", rec["lonlat"][0] or 0, bid, rec, im, t))
    picks.sort(key=lambda p: (p[0], p[1]))
    if a.limit:
        picks = picks[:a.limit]
    out = SHEETS / a.name
    out.mkdir(parents=True, exist_ok=True)
    index = []
    for s in range(0, len(picks), 4):
        items = []
        for c, (street, _, bid, rec, im, t) in enumerate(picks[s:s + 4]):
            cap = (f"{bid} {t['style']} fl{t['floors']} | {rec['address'][:22]} | hd{im['heading']:.0f} "
                   f"sh{im['fov_share']} {rec['attachment'][:6]}")
            items.append((str(DATA / im["path"]), cap))
            index.append(dict(cell=f"{s // 4 + 1}.{c + 1}", building_id=bid, photo=im["path"].split("images/", 1)[1],
                              share=im["fov_share"], heading=im["heading"], street=street, address=rec["address"],
                              tile=t["tile"], tile_style=t["style"], tile_floors=t["floors"],
                              attachment=rec["attachment"], front_bearing=rec["front_bearing"]))
        sheet(items, out / f"s{s // 4 + 1:03d}.jpg")
    with (out / "index.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(index[0]))
        w.writeheader()
        w.writerows(index)
    print(f"{len(picks)} buildings -> {(len(picks) + 3) // 4} sheets in {out}")


def parse_verdicts(path):
    for raw in Path(path).read_text(encoding="utf-8-sig").splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        head, _, notes = raw.partition("|")
        f = head.split()
        if len(f) != 12:
            raise ValueError(f"need 12 fields before '|': {raw}")
        yield f, notes.strip()


def cmd_apply(a):
    vpath = Path(a.verdicts)
    index = {r["cell"]: r for r in csv.DictReader((vpath.parent / "index.csv").open(encoding="utf-8"))}
    with POSE.open(encoding="utf-8") as f:
        have = {r["building_id"] for r in csv.DictReader(f)}
    new, log = [], []
    for f, notes in parse_verdicts(vpath):
        cell, bid, style, arch, units, roof, porch, floors, bay, gbays, wall, conf = [None if x == "-" else x for x in f]
        ix = index.get(cell)
        if not ix or ix["building_id"] != bid:
            raise ValueError(f"{cell}: sheet index says {ix and ix['building_id']}, verdict says {bid}")
        log.append(dict(batch=vpath.parent.name, cell=cell, building_id=bid, photo=ix["photo"], share=ix["share"],
                        heading=ix["heading"], tile_style=ix["tile_style"], verdict=style, notes=notes))
        if style == "SKIP":
            continue
        if style not in STYLES or (roof and roof not in ROOFS) or conf not in ("high", "medium"):
            raise ValueError(f"{cell}: bad style/roof/confidence {style}/{roof}/{conf}")
        if bid in have:
            continue
        material = ""
        if wall and ":" in wall:   # "e6dcc8:WoodPlanks" = sided / clapboard finish
            wall, material = wall.split(":", 1)
        if wall and not re.fullmatch(r"[0-9a-f]{6}", wall):
            raise ValueError(f"{cell}: wall must be 6 hex digits, got {wall}")
        row = dict.fromkeys(FIELDS, "")
        row["material"] = material
        row.update(building_id=bid, photo=ix["photo"], style=style, arch=arch or "", units=units or "",
                   roof=roof or "", porch=porch or "", floors=floors or "", bay=bay or "",
                   garage_bays=gbays or "", wall=wall or "", use=USE.get(style, ""), confidence=conf,
                   notes=(f"batch {vpath.parent.name} sheet {cell}: full-size {ix['photo']} hd{float(ix['heading']):.0f} "
                          f"ray-centred front share {ix['share']}; tile was {ix['tile_style']} fl{ix['tile_floors']}; {notes}"))
        new.append(row)
        have.add(bid)
    with POSE.open("a", newline="", encoding="utf-8") as f:
        csv.DictWriter(f, fieldnames=FIELDS).writerows(new)
    first = not LOG.exists()
    with LOG.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(log[0]))
        if first:
            w.writeheader()
        w.writerows(log)
    print(f"{len(log)} photos inspected, {len(new)} pose reviews appended, "
          f"{sum(r['verdict'] == 'SKIP' for r in log)} skipped as not supporting a verdict")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sheets")
    s.add_argument("--tiles", required=True)
    s.add_argument("--name", required=True)
    s.add_argument("--limit", type=int, default=0)
    s.add_argument("--skip-shops", action="store_true", help="leave named store sections to the storefront pass")
    s.set_defaults(fn=cmd_sheets)
    p = sub.add_parser("apply")
    p.add_argument("verdicts")
    p.set_defaults(fn=cmd_apply)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
