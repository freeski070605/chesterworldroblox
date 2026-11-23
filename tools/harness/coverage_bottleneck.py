"""Quantify why the citywide visual audits report so few reviewed photos.

    py -3 tools/harness/coverage_bottleneck.py
"""
import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = Path("E:/ChesterWorld/Data")
B = ROOT / "build"


def rows(p):
    with Path(p).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def manifest(folder):
    m = rows(DATA / folder / "manifest.csv")
    ok = [r for r in m if r.get("status", "ok") == "ok" and r.get("path")]
    exists = [r for r in ok if (DATA / folder / r["path"]).is_file()]
    ids = Counter(r["objectid"] for r in exists)
    on_disk = {p for p in (DATA / folder / "images").rglob("*.jpg")}
    listed = {(DATA / folder / r["path"]).resolve() for r in exists}
    print(f"{folder}: rows={len(m)} ok={len(ok)} file_exists={len(exists)} broken={len(ok)-len(exists)} "
          f"objectids={len(ids)} ids_with_>1_photo={sum(v > 1 for v in ids.values())} "
          f"photos_dropped_by_dict_keyed_on_objectid={len(exists)-len(ids)} "
          f"jpg_on_disk={len(on_disk)} on_disk_not_in_manifest={len({p.resolve() for p in on_disk} - listed)}")
    return exists


g = manifest("25_GoogleStreetView_Buildings")
mp = manifest("24_BuildingImagery_Mapillary")

ev = json.loads((B / "property_evidence/citywide.json").read_text(encoding="utf-8"))
props, photos = ev["properties"], ev["photos"]
verd = Counter(p["verdict"].split(":")[0] for p in photos)
print("cast photos", len(photos), "verdicts", dict(verd))
on_target = sum(p["verdict"].startswith("target_front") and "offcentre" not in p["verdict"] for p in photos)
print("photos centred on the download target's FRONT wall:", on_target)
centred = Counter()
for r in props.values():
    for i in r["images"]:
        if i["centre"] and i["fov_share"] >= 0.25:
            centred[i["wall"]] += 1
print("property records", len(props), "with any image", sum(bool(r["images"]) for r in props.values()),
      "with centred front image", sum(any(i["centre"] and i["wall"] == "front" and i["fov_share"] >= .25 for i in r["images"]) for r in props.values()))
print("centred image-walls", dict(centred))
multi = Counter(len({v["building_id"] for v in p["visible"]}) for p in photos)
print("buildings visible per photo (>=12% FOV)", dict(sorted(multi.items())))

st = rows(B / "citywide_storefront_review.csv")
ids = Counter(r["building_id"] for r in st)
print("storefront csv rows", len(st), "unique ids", len(ids), "ids repeated (shop sections)", sum(v > 1 for v in ids.values()),
      "extra rows", len(st) - len(ids))
print("storefront confidence", dict(Counter(r["confidence"] for r in st)))
noimg = [r for r in st if r["confidence"] == "imagery_missing"]
cast_ids = {bid for bid, r in props.items() if r["images"]}
print("imagery_missing rows whose building IS seen by >=1 cast photo:", sum(r["building_id"] in cast_ids for r in noimg))
print("imagery_missing rows with a centred cast photo:",
      sum(any(i["centre"] and i["fov_share"] >= .25 for i in props.get(r["building_id"], {}).get("images", [])) for r in noimg))
res = rows(B / "citywide_residential_review.csv")
print("residential rows", len(res), "unique", len({r["building_id"] for r in res}),
      "also in storefront sections", len({r["building_id"] for r in res} & {r["building_id"] for r in st if r["record_type"] == "storefront_section"}))

q = json.loads((B / "citywide_reconstruction_queue.json").read_text(encoding="utf-8"))
tiles = Counter(b["tile"] for b in q["batches"])
print("queue tiles", len(tiles), "non-tile groups", [t for t in tiles if not t.startswith("tile_")])
print("unmatched IDs", len(q["unmatched_source_ids"]), q["unmatched_source_ids"][:30])
src_tiles = sorted(p.name for p in (ROOT / "src/shared/WorldData/BuildingTiles").glob("tile_*.lua"))
print("BuildingTiles files", len(src_tiles))
fp = {str(f["properties"]["OBJECTID"]) for f in json.loads((DATA / "13_RegionalMaster/regional_buildings_base.geojson").read_text())["features"]}
um = set(q["unmatched_source_ids"])
print("unmatched IDs that are county footprints", len(um & fp))
