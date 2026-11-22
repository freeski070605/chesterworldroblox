"""Turn visual verdicts on zoning-only "commercial" footprints into structural reviews.

Inputs
  tools/reconstruction/zoning_verdicts.txt   slot -> verdict (see its header)
  build/property_evidence/zsheets/index.json slot -> building id, ray-centred photo
Outputs
  tools/reconstruction/pose_reviews.csv      appended/updated rows for changed types
  docs/zoning_review_log.csv                 every reviewed slot, incl. confirmed
                                             commercial and skipped (evidence record)
Then: py -3 tools/reconstruction/property_evidence.py --reviewed
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERDICTS = ROOT / "tools/reconstruction/zoning_verdicts.txt"
INDEX = ROOT / "build/property_evidence/zsheets/index.json"
POSE = ROOT / "tools/reconstruction/pose_reviews.csv"
LOG = ROOT / "docs/zoning_review_log.csv"

STYLE = {"R": "rowhouse", "T": "twin", "H": "house", "A": "apartment", "G": "garage"}
ROOF = {"f": "flat", "s": "side_gable", "g": "front_gable", "h": "hip", "m": "mansard"}
KIND = {"R": "residential_rowhouse", "T": "residential_twin", "H": "residential_house", "A": "residential_apartment",
        "G": "garage", "C": "confirmed_commercial_no_change", "X": "unresolved_no_change", "K": "existing_review_kept"}


def parse(line):
    parts = line.split()
    slot, code, extra = int(parts[0]), parts[1], parts[2:]
    v = dict(slot=slot, code=code, roof="", porch="0", floors="", bay="", bays="", units="", door="", conf="medium")
    for e in extra:
        if e in ROOF:
            v["roof"] = ROOF[e]
        elif e == "p":
            v["porch"] = "1"
        elif e == "y":
            v["bay"] = "1"
        elif e == "u1":
            v["units"] = "1"
        elif e == "!":
            v["conf"] = "high"
        elif e.isdigit():
            v["floors"] = e
        elif e.startswith("b") and e[1:].isdigit():
            v["bays"] = e[1:]
        elif e.startswith("d"):
            v["door"] = e[1:]
    return v


def main():
    index = {i["n"]: i for i in json.loads(INDEX.read_text())}
    verdicts = [parse(l) for l in VERDICTS.read_text().splitlines() if l.strip() and not l.startswith("#")]
    rows = list(csv.DictReader(POSE.open(newline="", encoding="utf-8")))
    fields = list(rows[0].keys())
    by_id = {r["building_id"]: r for r in rows}
    log = []
    changed = 0
    for v in verdicts:
        it = index[v["slot"]]
        bid = it["id"]
        sheet = f"z{v['slot'] // 16:03d}#{v['slot']}"
        log.append(dict(building_id=bid, verdict=KIND[v["code"]], tile_style=it["tile"][1], tile=it["tile"][0],
                        street=it.get("street") or "", photo=it["photo"], fov_share=it["share"], sheet=sheet,
                        roof=v["roof"], porch=v["porch"] if v["code"] in "RTHA" else "", floors=v["floors"],
                        confidence=v["conf"]))
        if v["code"] not in STYLE:
            continue
        style = STYLE[v["code"]]
        if style == "rowhouse":
            arch = "porch_row" if v["porch"] == "1" else "flat_row"
        elif style == "twin":
            arch = "victorian_twin" if v["roof"] == "front_gable" else "colonial_twin"
        elif style == "house":
            arch = "victorian_house" if v["roof"] == "front_gable" else "colonial_house"
        elif style == "apartment":
            arch = "apartment"
        else:
            arch = ""
        garage = style == "garage"
        row = {f: "" for f in fields}
        row.update(building_id=bid, photo=it["photo"].split("images/", 1)[1], style=style, arch=arch,
                   units=v["units"] or ("2" if style == "twin" else "1" if style == "house" else ""),
                   roof=v["roof"], door=v["door"], porch="0" if garage else v["porch"], floors=v["floors"] or ("1" if garage else ""),
                   bay=v["bay"], garage_bays=(v["bays"] or "0") if garage else "",
                   use="garage" if garage else "residential", confidence=v["conf"],
                   notes=(f"zoning-only 'commercial' (tile {it['tile'][1]}); ray-centred front photo share "
                          f"{it['share']}, review sheet {sheet}: {KIND[v['code']]}"
                          + ("" if v["roof"] else "; roof not legible - procedural roof kept")))
        if bid in by_id:
            by_id[bid].update(row)
        else:
            rows.append(row)
            by_id[bid] = row
        changed += 1
    with POSE.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    with LOG.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(log[0].keys()))
        w.writeheader()
        w.writerows(log)
    counts = {}
    for l in log:
        counts[l["verdict"]] = counts.get(l["verdict"], 0) + 1
    print(f"{len(log)} reviewed, {changed} type corrections -> {POSE.name}; {counts}")


if __name__ == "__main__":
    main()
