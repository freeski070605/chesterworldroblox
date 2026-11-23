"""Make one geographically batched ChesterWorld visual-reconstruction queue.

Existing citywide audits contain much more evidence than the few hand-authored
property overrides. Merge their rows by stable ChesterBuildingId, retain every
conflict, and queue entire tiles rather than patching one business at a time.

Inputs are produced by:
  py -3 tools/storefronts/citywide_visual_audit.py
  py -3 tools/reconstruction/citywide_residential_audit.py
  py -3 tools/reconstruction/property_evidence.py --all

Run:
  py -3 tools/reconstruction/citywide_batch_queue.py

SAFE: this script never alters the Roblox city, geometry, player data, or
verified photo evidence. The CSV/JSON outputs are review artifacts (build/).
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
EVIDENCE = BUILD / "property_evidence" / "citywide.csv"
STORES = BUILD / "citywide_storefront_review.csv"
HOMES = BUILD / "citywide_residential_review.csv"
OUT = BUILD / "citywide_reconstruction_queue"
TILES = ROOT / "src" / "shared" / "WorldData" / "BuildingTiles"
ID = re.compile(r'\["(\d+)"\]=\{')
TILE = re.compile(r"tile_r(\d+)_c(\d+)\.lua")


def rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def index_tiles(root: Path) -> dict[str, str]:
    """Find buildings in source tiles without converting/redrawing geometry."""
    found = {}
    for tile in sorted(root.glob("tile_r*_c*.lua")):
        for bid in ID.findall(tile.read_text(encoding="utf-8")):
            if bid in found and found[bid] != tile.name:
                raise ValueError(f"{bid} duplicated across {found[bid]} / {tile.name}")
            found[bid] = tile.name
    return found


def score(item: dict) -> tuple[int, list[str]]:
    points = 0
    flags = []
    store = item.get("store", [])
    home = item.get("home")
    ev = item.get("evidence")
    for row in store:
        if row.get("source_lat") == "" or row.get("source_lon") == "":
            points += 30
            flags.append("storefront_no_matched_county_footprint")
        try:
            if float(row.get("placement_delta_m") or 0) > 5:
                points += 25
                flags.append("storefront_placement_delta_over_5m")
        except ValueError:
            flags.append("invalid_storefront_delta")
        if (row.get("confidence") or "").lower() in ("conflicting", "unresolved"):
            points += 35
            flags.append("storefront_identity_or_facade_conflict")
        if not row.get("image_reference") and not row.get("panorama_references"):
            points += 12
            flags.append("storefront_missing_photo")
        if row.get("visual_review") != "full_size":
            flags.append("storefront_not_full_size_verified")
        if row.get("business_name") and row.get("business_place_id"):
            points += 4  # important, customer-facing, linked gameplay
    if home:
        if "type conflict" in (home.get("review_flags") or "").lower():
            points += 30
            flags.append("residential_type_conflict")
        if "placement delta >5m" in (home.get("review_flags") or "").lower():
            points += 20
            flags.append("residential_placement_delta_over_5m")
        if home.get("photo_review") != "full_size":
            flags.append("residential_not_full_size_verified")
        if home.get("confidence") == "conflicting":
            points += 25
            flags.append("residential_identity_conflict")
    if ev:
        if ev.get("conflicts"):
            points += 40
            flags.append("photo_pose_or_type_conflict")
        if ev.get("review_status") in ("conflict", "needs_imagery"):
            points += 20
            flags.append("missing_or_conflicting_entrance_evidence")
        if not ev.get("images_showing_front") or ev["images_showing_front"] == "0":
            flags.append("front_wall_not_confirmed")
    if len(store) > 1:
        points += 10
        flags.append("multi_tenant_parcel_check")
    return points, sorted(set(flags))


def build_queue(
    stores: list[dict[str, str]],
    homes: list[dict[str, str]],
    evidence: list[dict[str, str]],
    tile_index: dict[str, str],
    batch_size: int = 50,
) -> dict:
    if batch_size < 1:
        raise ValueError("batch_size must be positive")
    entries = {bid: {"id": bid, "tile": tile, "store": [], "home": None, "evidence": None}
               for bid, tile in tile_index.items()}
    unmatched = set()
    for kind, data in (("store", stores), ("home", homes), ("evidence", evidence)):
        for row in data:
            bid = (row.get("building_id") or "").strip()
            if not bid:
                continue
            if bid not in entries:
                unmatched.add(bid)
                entries[bid] = {"id": bid, "tile": row.get("tile") or "unmatched",
                                "store": [], "home": None, "evidence": None}
            if kind == "store":
                entries[bid]["store"].append(row)
            elif entries[bid][kind] is None:
                entries[bid][kind] = row
    tiles: dict[str, list[dict]] = defaultdict(list)
    for entry in entries.values():
        points, flags = score(entry)
        if entry["id"] in unmatched:
            points += 50
            flags.append("building_id_not_in_source_tile")
        store = entry["store"]
        home = entry["home"] or {}
        evidence = entry["evidence"] or {}
        image_refs = sorted({r.get("image_reference", "") for r in store if r.get("image_reference")}
            | ({home["image_path"]} if home.get("image_path") else set()))
        tile = entry["tile"]
        review = {
            "building_id": entry["id"],
            "tile": tile,
            "score": points,
            "flags": sorted(set(flags)),
            "businesses": sorted({r.get("business_name", "") for r in store if r.get("business_name")}),
            "source_address": next((r.get("source_address") for r in store if r.get("source_address")),
                                   home.get("source_address") or evidence.get("address") or ""),
            "source_lat": next((r.get("source_lat") for r in store if r.get("source_lat")),
                               home.get("source_lat") or ""),
            "source_lon": next((r.get("source_lon") for r in store if r.get("source_lon")),
                               home.get("source_lon") or ""),
            "street": evidence.get("primary_street", ""),
            "image_references": image_refs,
            "evidence_status": evidence.get("review_status", ""),
            "visual_verified": bool(store) and all(r.get("visual_review") == "full_size" for r in store)
                or bool(home) and home.get("photo_review") == "full_size",
            "requires_review": bool(flags) or bool(store) or bool(home),
        }
        # No one gets a verified placement just because there is an aerial
        # footprint or because a nearest-street bearing can be estimated.
        tiles[tile].append(review)
    batches = []
    for tile in sorted(tiles, key=lambda name: (
            -sum(x["score"] for x in tiles[name]),
            -sum(bool(x["businesses"]) for x in tiles[name]),
            name)):
        selected = sorted(tiles[tile], key=lambda r: (-r["score"], int(r["building_id"])))
        for i in range(0, len(selected), batch_size):
            chunk = selected[i:i+batch_size]
            batches.append({
                "batch_id": f"{tile.removesuffix('.lua')}_{i//batch_size + 1:03d}",
                "tile": tile,
                "count": len(chunk),
                "total_priority": sum(e["score"] for e in chunk),
                "review_flagged": sum(e["requires_review"] for e in chunk),
                "building_ids": [r["building_id"] for r in chunk],
                "properties": chunk,
            })
    return {
        "schema_version": 1,
        "safe_review_only": True,
        "building_ids": len(entries),
        "tile_count": len(tiles),
        "unmatched_source_ids": sorted(unmatched, key=lambda i: int(i) if i.isdigit() else 0),
        "batches": batches,
    }


def write_report(report: dict, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.with_suffix(".json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    fields = ["batch_id", "tile", "building_id", "priority", "businesses",
              "address", "street", "evidence_status", "visual_verified",
              "flags", "image_references"]
    with output.with_suffix(".csv").open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for batch in report["batches"]:
            for rec in batch["properties"]:
                writer.writerow({
                    "batch_id": batch["batch_id"],
                    "tile": batch["tile"],
                    "building_id": rec["building_id"],
                    "priority": rec["score"],
                    "businesses": " | ".join(rec["businesses"]),
                    "address": rec["source_address"], "street": rec["street"],
                    "evidence_status": rec["evidence_status"],
                    "visual_verified": rec["visual_verified"],
                    "flags": " | ".join(rec["flags"]),
                    "image_references": " | ".join(rec["image_references"]),
                })
    md = [
        "# Chester citywide geographic reconstruction work queue", "",
        "Evidence-driven review in *geographic batches*. Not an automatic",
        "replacement or certification of any building. Xbox-safe: no game code changes.",
        "",
        f"- Building IDs indexed: {report['building_ids']:,}",
        f"- Tiles represented: {report['tile_count']}",
        f"- Review batches: {len(report['batches']):,}",
        f"- IDs missing from the source tiles: {len(report['unmatched_source_ids']):,}",
        "",
        "| Batch | Tile | Buildings | Priority | Flagged |", "|---|---|---:|---:|---:|",
    ]
    for batch in report["batches"][:100]:
        md.append(f"| {batch['batch_id']} | {batch['tile']} | {batch['count']} | "
                  f"{batch['total_priority']} | {batch['review_flagged']} |")
    md += ["", "## Approval gates", "",
           "1. Inspect the source imagery **at full size**, including neighboring houses, roads, sidewalks and lot boundaries.",
           "2. Resolve camera/footprint/tenant mismatch before editing the facade or front door.",
           "3. Apply verified changes to a full batch with stable ChesterBuildingId values.",
           "4. Verify overlapping geometry, entrances, gameplay, and roads in Studio.",
           "5. Publish and Xbox-test before moving to another group of tiles.",
           ""]
    output.with_suffix(".md").write_text("\n".join(md), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--storefronts", type=Path, default=STORES)
    ap.add_argument("--residential", type=Path, default=HOMES)
    ap.add_argument("--evidence", type=Path, default=EVIDENCE)
    ap.add_argument("--tiles", type=Path, default=TILES)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--batch-size", type=int, default=50)
    a = ap.parse_args()
    sources = (a.storefronts, a.residential, a.evidence)
    if not any(p.is_file() for p in sources):
        ap.error("No audits found. Run citywide_visual_audit.py, citywide_residential_audit.py and property_evidence.py --all first")
    result = build_queue(rows(a.storefronts), rows(a.residential),
                         rows(a.evidence), index_tiles(a.tiles), a.batch_size)
    write_report(result, a.out)
    print(f"Citywide queue: {result['building_ids']:,} IDs, {result['tile_count']} tiles, "
          f"{len(result['batches'])} geographic batches")
    print(f"CSV / JSON / MD: {a.out}.csv / .json / .md")


if __name__ == "__main__":
    main()
