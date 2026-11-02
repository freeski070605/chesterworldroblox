#!/usr/bin/env python3
from __future__ import annotations

import csv, json
from collections import Counter
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import shape, mapping
from shapely.ops import transform as shp_transform
from shapely.strtree import STRtree

ROOT = Path(r"E:\ChesterWorld")
BUILDINGS = ROOT / "Data" / "14_RegionalGeneratorPrep_v2" / "regional_generator_buildings_v2.geojson"
ROADS = ROOT / "Data" / "15_RegionalRoadGeneratorPrep" / "regional_generator_roads.geojson"
OUT = ROOT / "Data" / "17_RealWorldCleanup"
OUT.mkdir(parents=True, exist_ok=True)

REPORT = OUT / "cleanup_pass1_report.json"
ROAD_CONFLICTS_CSV = OUT / "building_road_conflicts.csv"
BUILDING_CONFLICTS_CSV = OUT / "building_building_conflicts.csv"
ROAD_CORRIDORS_GEOJSON = OUT / "road_corridors.geojson"
CLEAN_BUILDINGS_GEOJSON = OUT / "regional_generator_buildings_clean_v1.geojson"
REMOVED_DUPLICATES_CSV = OUT / "removed_near_duplicate_buildings.csv"

TO_METRIC = Transformer.from_crs("EPSG:4326", "EPSG:26918", always_xy=True).transform
TO_WGS84 = Transformer.from_crs("EPSG:26918", "EPSG:4326", always_xy=True).transform

ROAD_EDGE_CLEARANCE_M = 0.75
NON_MOTOR_CLASSES = {"pedestrian", "footway", "path", "cycleway", "steps", "track"}
DUPLICATE_OVERLAP_RATIO = 0.92
DUPLICATE_AREA_RATIO = 0.80
ROAD_MINOR_RATIO = 0.05
ROAD_SEVERE_RATIO = 0.35


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def clean(v):
    if v is None:
        return ""
    s = str(v).strip()
    return "" if s.lower() in {"", "none", "null", "nan"} else s


def feature_id(feature, index):
    p = feature.get("properties") or {}
    for k in ("building_id", "OBJECTID", "ObjectID", "objectid", "id", "osm_id", "fid"):
        if clean(p.get(k)):
            return str(p.get(k))
    return f"feature_{index}"


def source_priority(feature):
    p = feature.get("properties") or {}
    text = " ".join(clean(p.get(k)).lower() for k in ("source", "generator_source", "building_source", "source_name"))
    if "enrich" in text or "chester" in text:
        return 0
    if "county" in text or "official" in text:
        return 1
    return 2


def road_width(props):
    for k in ("generator_width_m", "width_m", "width"):
        try:
            v = float(props.get(k))
            if 1.0 <= v <= 80.0:
                return v
        except Exception:
            pass
    return 6.0


def road_class(props):
    return clean(props.get("generator_road_class") or props.get("road_class") or props.get("highway") or "unknown").lower()


def metric_geom(feature):
    try:
        g = shape(feature.get("geometry"))
        if g.is_empty:
            return None
        if not g.is_valid:
            g = g.buffer(0)
        if g.is_empty:
            return None
        return shp_transform(TO_METRIC, g)
    except Exception:
        return None


def query_indices(tree, geoms, target):
    raw = tree.query(target)
    out = []
    for item in raw:
        try:
            idx = int(item)
            if 0 <= idx < len(geoms):
                out.append(idx)
                continue
        except Exception:
            pass
        for idx, geom in enumerate(geoms):
            if geom is item:
                out.append(idx)
                break
    return out


def write_csv(path, rows, fields):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    print("=" * 88)
    print("CHESTERWORLD REAL-WORLD CLEANUP — PASS 1")
    print("=" * 88)

    for p, label in ((BUILDINGS, "regional buildings"), (ROADS, "regional roads")):
        if not p.exists():
            raise SystemExit(f"Missing {label}: {p}")

    bdata = load_json(BUILDINGS)
    rdata = load_json(ROADS)
    bfeatures = bdata.get("features", [])
    rfeatures = rdata.get("features", [])
    print(f"Buildings input: {len(bfeatures):,}")
    print(f"Roads input:     {len(rfeatures):,}")

    buildings = []
    for i, f in enumerate(bfeatures):
        g = metric_geom(f)
        if g is None or g.area <= 0.5:
            continue
        buildings.append({"id": feature_id(f, i), "feature": f, "geom": g, "area": float(g.area), "priority": source_priority(f)})

    bgeoms = [r["geom"] for r in buildings]
    btree = STRtree(bgeoms)
    remove = set()
    dup_rows = []

    for i, a in enumerate(buildings):
        if i in remove:
            continue
        for j in query_indices(btree, bgeoms, a["geom"]):
            if j <= i or j in remove:
                continue
            b = buildings[j]
            try:
                inter = a["geom"].intersection(b["geom"])
            except Exception:
                continue
            if inter.is_empty or inter.area <= 0:
                continue
            smaller = min(a["area"], b["area"])
            larger = max(a["area"], b["area"])
            overlap = inter.area / smaller
            area_ratio = smaller / larger if larger else 0
            if overlap >= DUPLICATE_OVERLAP_RATIO and area_ratio >= DUPLICATE_AREA_RATIO:
                ka = (a["priority"], -a["area"], i)
                kb = (b["priority"], -b["area"], j)
                keep, drop = (i, j) if ka <= kb else (j, i)
                remove.add(drop)
                dup_rows.append({
                    "keep_id": buildings[keep]["id"],
                    "remove_id": buildings[drop]["id"],
                    "overlap_ratio": round(overlap, 6),
                    "area_ratio": round(area_ratio, 6),
                })

    print(f"Safe near-duplicate buildings removed: {len(remove):,}")

    roads = []
    corridor_features = []
    for i, f in enumerate(rfeatures):
        g = metric_geom(f)
        if g is None or g.length <= 0.2:
            continue
        p = f.get("properties") or {}
        cls = road_class(p)
        width = road_width(p)
        buffer_m = max(0.75, width / 2.0 + ROAD_EDGE_CLEARANCE_M)
        try:
            corridor = g.buffer(buffer_m, cap_style=2, join_style=2)
        except Exception:
            corridor = g.buffer(buffer_m)
        name = clean(p.get("generator_name") or p.get("name") or "")
        rec = {"geom": g, "corridor": corridor, "road_class": cls, "width_m": width, "motor": cls not in NON_MOTOR_CLASSES, "name": name}
        roads.append(rec)
        corridor_features.append({
            "type": "Feature",
            "properties": {"road_index": i, "name": name, "road_class": cls, "width_m": width, "analysis_buffer_m": buffer_m, "motor": rec["motor"]},
            "geometry": mapping(shp_transform(TO_WGS84, corridor)),
        })

    motor = [r for r in roads if r["motor"]]
    mgeoms = [r["corridor"] for r in motor]
    mtree = STRtree(mgeoms)
    road_conflicts = []
    rc = Counter()

    for bi, b in enumerate(buildings):
        if bi in remove:
            continue
        for ri in query_indices(mtree, mgeoms, b["geom"]):
            r = motor[ri]
            if not r["corridor"].intersects(b["geom"]):
                continue
            try:
                inter = b["geom"].intersection(r["corridor"])
            except Exception:
                continue
            if inter.is_empty or inter.area <= 0:
                continue
            ratio = inter.area / b["area"]
            severity = "severe" if ratio >= ROAD_SEVERE_RATIO else ("moderate" if ratio >= ROAD_MINOR_RATIO else "edge_touch")
            rc[severity] += 1
            road_conflicts.append({
                "building_id": b["id"], "road_name": r["name"], "road_class": r["road_class"],
                "road_width_m": round(r["width_m"], 3), "overlap_area_m2": round(inter.area, 3),
                "building_overlap_ratio": round(ratio, 6), "severity": severity,
            })

    remaining = [r for idx, r in enumerate(buildings) if idx not in remove]
    rgeoms = [r["geom"] for r in remaining]
    rtree = STRtree(rgeoms)
    bb_conflicts = []
    seen = set()
    for i, a in enumerate(remaining):
        for j in query_indices(rtree, rgeoms, a["geom"]):
            if j <= i or (i, j) in seen:
                continue
            seen.add((i, j))
            b = remaining[j]
            try:
                inter = a["geom"].intersection(b["geom"])
            except Exception:
                continue
            if inter.is_empty or inter.area <= 0.25:
                continue
            ratio = inter.area / min(a["area"], b["area"])
            if ratio < 0.02:
                continue
            bb_conflicts.append({
                "building_a": a["id"], "building_b": b["id"], "overlap_area_m2": round(inter.area, 3),
                "smaller_overlap_ratio": round(ratio, 6), "severity": "severe" if ratio >= 0.25 else "moderate",
            })

    clean_features = [r["feature"] for idx, r in enumerate(buildings) if idx not in remove]
    clean_output = dict(bdata)
    clean_output["name"] = "ChesterWorld_Regional_Buildings_Clean_v1"
    clean_output["features"] = clean_features
    CLEAN_BUILDINGS_GEOJSON.write_text(json.dumps(clean_output, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    ROAD_CORRIDORS_GEOJSON.write_text(json.dumps({"type": "FeatureCollection", "name": "ChesterWorld_Road_Corridors_Analysis", "features": corridor_features}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    write_csv(REMOVED_DUPLICATES_CSV, dup_rows, ["keep_id", "remove_id", "overlap_ratio", "area_ratio"])
    write_csv(ROAD_CONFLICTS_CSV, sorted(road_conflicts, key=lambda x: ({"severe": 0, "moderate": 1, "edge_touch": 2}[x["severity"]], -x["building_overlap_ratio"])), ["building_id", "road_name", "road_class", "road_width_m", "overlap_area_m2", "building_overlap_ratio", "severity"])
    write_csv(BUILDING_CONFLICTS_CSV, sorted(bb_conflicts, key=lambda x: (0 if x["severity"] == "severe" else 1, -x["smaller_overlap_ratio"])), ["building_a", "building_b", "overlap_area_m2", "smaller_overlap_ratio", "severity"])

    report = {
        "schema": "chesterworld.real_world_cleanup.pass1.v1",
        "counts": {
            "buildings_input": len(bfeatures),
            "valid_buildings": len(buildings),
            "safe_near_duplicates_removed": len(remove),
            "clean_buildings_output": len(clean_features),
            "roads_input": len(rfeatures),
            "road_corridors": len(roads),
            "motor_road_corridors": len(motor),
            "building_road_conflicts": len(road_conflicts),
            "building_road_severe": rc["severe"],
            "building_road_moderate": rc["moderate"],
            "building_road_edge_touch": rc["edge_touch"],
            "remaining_building_overlap_pairs": len(bb_conflicts),
            "remaining_building_overlap_severe": sum(1 for x in bb_conflicts if x["severity"] == "severe"),
        },
        "policy": {
            "auto_removed": "Near-identical building duplicates only. Road conflicts are report-only.",
            "road_clearance_m": ROAD_EDGE_CLEARANCE_M,
        },
        "outputs": {
            "clean_buildings": str(CLEAN_BUILDINGS_GEOJSON),
            "road_corridors": str(ROAD_CORRIDORS_GEOJSON),
            "road_conflicts_csv": str(ROAD_CONFLICTS_CSV),
            "building_conflicts_csv": str(BUILDING_CONFLICTS_CSV),
            "removed_duplicates_csv": str(REMOVED_DUPLICATES_CSV),
        },
    }
    REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print("\n" + "=" * 88)
    print("PASS 1 COMPLETE")
    print("=" * 88)
    print(f"Safe near-duplicate removals: {len(remove):,}")
    print(f"Clean buildings output:       {len(clean_features):,}")
    print(f"Building/road conflicts:      {len(road_conflicts):,}")
    print(f"  severe:                     {rc['severe']:,}")
    print(f"  moderate:                   {rc['moderate']:,}")
    print(f"  edge-touch:                 {rc['edge_touch']:,}")
    print(f"Building/building overlaps:   {len(bb_conflicts):,}")
    print(f"  severe:                     {sum(1 for x in bb_conflicts if x['severity'] == 'severe'):,}")
    print(f"Report: {REPORT}")
    print("Original regional source files were NOT modified.")
    print("=" * 88)


if __name__ == "__main__":
    main()
