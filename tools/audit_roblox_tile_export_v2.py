#!/usr/bin/env python3
r"""
ChesterWorld Roblox tile export audit v2.

This version does NOT assume the road-name field is called `name`.
It first inspects the literal generated Lua modules and discovers which
field contains Chester street names.

Then it audits:
- 8th & Kerlin
- 9th & Kerlin
- 9th & Butler
- 9th & Parker
- 9th & Fulton
- 9th & Barclay

No files are modified.
"""

from __future__ import annotations

import math
import re
from collections import Counter, defaultdict
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")
TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"

SEARCH_TERMS = ["Kerlin", "Parker", "Fulton", "Barclay", "Butler", "9th", "Ninth", "8th", "Eighth"]

FIELD_RE = re.compile(
    r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*'
    r'(?:"([^"]*)"|\'([^\']*)\'|([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?))'
)

BLOCK_RE = re.compile(r"\{([^{}]{0,1800})\}", re.S)


def clean(value):
    return " ".join((value or "").strip().split())


def parse_value(match):
    if match.group(2) is not None:
        return match.group(2)
    if match.group(3) is not None:
        return match.group(3)
    return match.group(4)


def inspect_literal_matches(files):
    print("=" * 80)
    print("LITERAL STREET-NAME SEARCH IN GENERATED LUA")
    print("=" * 80)

    found_any = False
    examples = defaultdict(list)

    for path in files:
        text = path.read_text(encoding="utf-8", errors="ignore")

        for term in SEARCH_TERMS:
            if re.search(re.escape(term), text, re.I):
                found_any = True

                for m in re.finditer(re.escape(term), text, re.I):
                    start = max(0, m.start() - 180)
                    end = min(len(text), m.end() + 180)
                    snippet = text[start:end].replace("\n", " ")
                    snippet = re.sub(r"\s+", " ", snippet)

                    if len(examples[term]) < 3:
                        examples[term].append((path.name, snippet))

    for term in SEARCH_TERMS:
        rows = examples.get(term, [])
        print(f"{term:<8}: {'FOUND' if rows else 'NOT FOUND'}")
        for filename, snippet in rows:
            print(f"  {filename}: {snippet[:420]}")
        if rows:
            print()

    if not found_any:
        print("NO TARGET STREET NAMES EXIST LITERALLY IN THE GENERATED LUA FILES.")
        print("That would prove the exporter dropped street names.")
        print()

    return examples


def discover_string_fields(files):
    value_field_counts = Counter()
    target_field_counts = Counter()
    coordinate_blocks = []

    for path in files:
        text = path.read_text(encoding="utf-8", errors="ignore")

        for block_match in BLOCK_RE.finditer(text):
            block = block_match.group(1)
            fields = {}

            for fm in FIELD_RE.finditer(block):
                fields[fm.group(1)] = parse_value(fm)

            if not {"x1", "z1", "x2", "z2"}.issubset(fields):
                continue

            string_fields = {}
            for key, value in fields.items():
                if key in {"x1", "z1", "x2", "z2"}:
                    continue
                try:
                    float(value)
                    numeric = True
                except Exception:
                    numeric = False

                if not numeric and clean(value):
                    string_fields[key] = clean(value)
                    value_field_counts[key] += 1

                    if any(re.search(re.escape(term), value, re.I) for term in SEARCH_TERMS):
                        target_field_counts[key] += 1

            coordinate_blocks.append({
                "tile": path.stem,
                "fields": fields,
                "strings": string_fields,
            })

    print("=" * 80)
    print("STRING FIELD DISCOVERY IN ROAD-LIKE RECORDS")
    print("=" * 80)
    print(f"Coordinate blocks parsed: {len(coordinate_blocks):,}")
    print()

    print("Most common string fields:")
    for field, count in value_field_counts.most_common(20):
        print(f"  {field:<28} {count:>8,}")

    print()
    print("Fields containing target Chester street names:")
    if target_field_counts:
        for field, count in target_field_counts.most_common():
            print(f"  {field:<28} {count:>8,}")
    else:
        print("  NONE")

    print()

    if target_field_counts:
        return target_field_counts.most_common(1)[0][0], coordinate_blocks

    # Fallback: common likely names.
    for candidate in (
        "street_name",
        "road_name",
        "generator_name",
        "name",
        "street",
        "label",
    ):
        if value_field_counts[candidate]:
            return candidate, coordinate_blocks

    return None, coordinate_blocks


def name_matches(name, term):
    n = clean(name).lower()

    if term == "8th":
        return bool(re.search(r"(?<!\d)(?:8th|eighth)(?!\d)", n))
    if term == "9th":
        return bool(re.search(r"(?<!\d)(?:9th|ninth)(?!\d)", n))

    return re.search(rf"\b{re.escape(term.lower())}\b", n) is not None


def point_segment_distance(px, pz, road):
    ax, az = road["x1"], road["z1"]
    bx, bz = road["x2"], road["z2"]
    vx, vz = bx - ax, bz - az
    wx, wz = px - ax, pz - az

    l2 = vx * vx + vz * vz
    if l2 <= 1e-12:
        return math.hypot(px - ax, pz - az)

    t = max(0.0, min(1.0, (wx * vx + wz * vz) / l2))
    qx = ax + t * vx
    qz = az + t * vz

    return math.hypot(px - qx, pz - qz)


def segment_intersection(a, b):
    x1, y1, x2, y2 = a["x1"], a["z1"], a["x2"], a["z2"]
    x3, y3, x4, y4 = b["x1"], b["z1"], b["x2"], b["z2"]

    den = (x1-x2)*(y3-y4) - (y1-y2)*(x3-x4)
    if abs(den) < 1e-9:
        return None

    px = (
        (x1*y2-y1*x2)*(x3-x4)
        - (x1-x2)*(x3*y4-y3*x4)
    ) / den

    py = (
        (x1*y2-y1*x2)*(y3-y4)
        - (y1-y2)*(x3*y4-y3*x4)
    ) / den

    def within(v, a0, a1, eps=3.0):
        lo, hi = sorted((a0, a1))
        return lo - eps <= v <= hi + eps

    if (
        within(px, x1, x2)
        and within(py, y1, y2)
        and within(px, x3, x4)
        and within(py, y3, y4)
    ):
        return px, py

    return None


def build_roads(blocks, name_field):
    roads = []

    for block in blocks:
        fields = block["fields"]

        try:
            x1 = float(fields["x1"])
            z1 = float(fields["z1"])
            x2 = float(fields["x2"])
            z2 = float(fields["z2"])
        except Exception:
            continue

        name = clean(fields.get(name_field, ""))

        roads.append({
            "tile": block["tile"],
            "name": name,
            "x1": x1,
            "z1": z1,
            "x2": x2,
            "z2": z2,
        })

    return roads


def find_intersection(roads, a_term, b_term):
    a_roads = [r for r in roads if name_matches(r["name"], a_term)]
    b_roads = [r for r in roads if name_matches(r["name"], b_term)]

    if not a_roads or not b_roads:
        return {
            "ok": False,
            "reason": f"missing named segments: {a_term}={len(a_roads)}, {b_term}={len(b_roads)}",
        }

    candidates = []

    for a in a_roads:
        for b in b_roads:
            p = segment_intersection(a, b)
            if p is not None:
                candidates.append((0.0, p[0], p[1], a, b))

            for ax, az in ((a["x1"], a["z1"]), (a["x2"], a["z2"])):
                d = point_segment_distance(ax, az, b)
                if d <= 25:
                    candidates.append((d, ax, az, a, b))

            for bx, bz in ((b["x1"], b["z1"]), (b["x2"], b["z2"])):
                d = point_segment_distance(bx, bz, a)
                if d <= 25:
                    candidates.append((d, bx, bz, a, b))

    if not candidates:
        return {
            "ok": False,
            "reason": "no crossing/near-crossing in generated tile geometry",
            "a_count": len(a_roads),
            "b_count": len(b_roads),
        }

    candidates.sort(key=lambda x: x[0])
    gap, x, z, a, b = candidates[0]

    return {
        "ok": True,
        "x": x,
        "z": z,
        "gap": gap,
        "a_name": a["name"],
        "b_name": b["name"],
        "a_tile": a["tile"],
        "b_tile": b["tile"],
    }


def main():
    files = sorted(TILES.glob("*.lua"))
    if not files:
        raise SystemExit(f"No Lua tile modules found in {TILES}")

    inspect_literal_matches(files)

    name_field, blocks = discover_string_fields(files)

    if not name_field:
        print("RESULT: GENERATED TILE RECORDS HAVE NO DISCOVERABLE STREET-NAME FIELD.")
        print("The Roblox exporter must be fixed/re-run before street-order can be audited.")
        return

    print(f"Selected street-name field: {name_field}")
    print()

    roads = build_roads(blocks, name_field)
    named = [r for r in roads if r["name"]]

    print("=" * 80)
    print("GENERATED ROBLOX TILE STREET-ORDER AUDIT")
    print("=" * 80)
    print(f"Road records:       {len(roads):,}")
    print(f"Named road records: {len(named):,}")
    print()

    tests = [
        ("8th", "Kerlin"),
        ("9th", "Kerlin"),
        ("9th", "Butler"),
        ("9th", "Parker"),
        ("9th", "Fulton"),
        ("9th", "Barclay"),
    ]

    results = {}

    for a, b in tests:
        result = find_intersection(roads, a, b)
        results[(a, b)] = result

        if result["ok"]:
            print(
                f"{a:>4} & {b:<8} "
                f"X={result['x']:9.2f} Z={result['z']:9.2f} "
                f"gap={result['gap']:.2f} | "
                f"{result['a_name']} / {result['b_name']}"
            )
        else:
            print(f"{a:>4} & {b:<8} FAILED: {result['reason']}")

    required = list(results)
    if not all(results[k]["ok"] for k in required):
        print()
        print("RESULT: EXPORT AUDIT STILL INCOMPLETE.")
        print("The literal-search and field-discovery sections above identify why.")
        return

    p8 = results[("8th", "Kerlin")]
    p9 = results[("9th", "Kerlin")]
    butler = results[("9th", "Butler")]
    parker = results[("9th", "Parker")]
    fulton = results[("9th", "Fulton")]
    barclay = results[("9th", "Barclay")]

    fx = p9["x"] - p8["x"]
    fz = p9["z"] - p8["z"]
    fl = math.hypot(fx, fz)
    fx /= fl
    fz /= fl

    rx = fz
    rz = -fx

    def right_score(target):
        dx = target["x"] - p9["x"]
        dz = target["z"] - p9["z"]
        return dx * rx + dz * rz

    bscore = right_score(butler)
    pscore = right_score(parker)

    print()
    print("-" * 80)
    print("RIGHT TURN FROM 8TH & KERLIN -> 9TH & KERLIN")
    print("-" * 80)
    print(f"Butler right score: {bscore:+.2f}")
    print(f"Parker right score: {pscore:+.2f}")
    print(
        "GENERATED TILES SAY RIGHT TURN LEADS TOWARD: "
        + ("PARKER" if pscore > bscore else "BUTLER")
    )

    print()
    print("-" * 80)
    print("9TH STREET ORDER BY GENERATED X")
    print("-" * 80)

    ordered = [
        ("Butler", butler),
        ("Kerlin", p9),
        ("Parker", parker),
        ("Fulton", fulton),
        ("Barclay", barclay),
    ]
    ordered.sort(key=lambda item: item[1]["x"])

    for name, p in ordered:
        print(f"{p['x']:9.2f}  {name}")

    print()
    print("EXPECTED WEST -> EAST:")
    print("Butler -> Kerlin -> Parker -> Fulton -> Barclay")
    print("=" * 80)


if __name__ == "__main__":
    main()
