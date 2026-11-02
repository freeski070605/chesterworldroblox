#!/usr/bin/env python3
r"""
Audit the GENERATED Roblox tile modules, not the raw GIS.

This proves whether the Lua tiles that Roblox actually renders preserve
the correct Chester street order.

Checks generated road segments near:
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
from pathlib import Path

PROJECT = Path(r"E:\code\chesterworld-roblox")
TILES = PROJECT / "src" / "shared" / "WorldData" / "Tiles"

TARGET_NAMES = ["8th", "9th", "Kerlin", "Butler", "Parker", "Fulton", "Barclay"]

FIELD_RE = re.compile(
    r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*'
    r'(?:"([^"]*)"|\'([^\']*)\'|([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?))'
)

BLOCK_RE = re.compile(r"\{([^{}]{0,1200})\}", re.S)


def clean_name(value: str) -> str:
    return " ".join((value or "").strip().split())


def normalize(name: str) -> str:
    return clean_name(name).lower()


def parse_modules():
    roads = []
    files = sorted(TILES.glob("*.lua"))

    if not files:
        raise SystemExit(f"No generated tile .lua files found in {TILES}")

    for path in files:
        text = path.read_text(encoding="utf-8", errors="ignore")

        for match in BLOCK_RE.finditer(text):
            block = match.group(1)
            fields = {}

            for f in FIELD_RE.finditer(block):
                key = f.group(1)
                if f.group(2) is not None:
                    value = f.group(2)
                elif f.group(3) is not None:
                    value = f.group(3)
                else:
                    value = f.group(4)
                fields[key] = value

            required = {"x1", "z1", "x2", "z2"}
            if not required.issubset(fields):
                continue

            try:
                x1 = float(fields["x1"])
                z1 = float(fields["z1"])
                x2 = float(fields["x2"])
                z2 = float(fields["z2"])
            except Exception:
                continue

            name = clean_name(
                fields.get("name")
                or fields.get("street")
                or fields.get("generator_name")
                or ""
            )

            roads.append({
                "tile": path.stem,
                "name": name,
                "x1": x1,
                "z1": z1,
                "x2": x2,
                "z2": z2,
            })

    return roads, files


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

    def within(v, a0, a1, eps=2.0):
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


def point_segment_distance(px, pz, road):
    ax, az = road["x1"], road["z1"]
    bx, bz = road["x2"], road["z2"]
    vx, vz = bx-ax, bz-az
    wx, wz = px-ax, pz-az
    l2 = vx*vx + vz*vz
    if l2 <= 1e-12:
        return math.hypot(px-ax, pz-az)

    t = max(0.0, min(1.0, (wx*vx + wz*vz) / l2))
    qx = ax + t*vx
    qz = az + t*vz
    return math.hypot(px-qx, pz-qz)


def name_matches(name, term):
    n = normalize(name)

    if term == "8th":
        return bool(re.search(r"(?<!\d)(8th|eighth)(?!\d)", n))
    if term == "9th":
        return bool(re.search(r"(?<!\d)(9th|ninth)(?!\d)", n))

    return re.search(rf"\b{re.escape(term.lower())}\b", n) is not None


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

            # Tile clipping / simplified centerlines may stop just short.
            endpoints_a = [(a["x1"], a["z1"]), (a["x2"], a["z2"])]
            endpoints_b = [(b["x1"], b["z1"]), (b["x2"], b["z2"])]

            for ax, az in endpoints_a:
                d = point_segment_distance(ax, az, b)
                if d <= 20:
                    candidates.append((d, ax, az, a, b))

            for bx, bz in endpoints_b:
                d = point_segment_distance(bx, bz, a)
                if d <= 20:
                    candidates.append((d, bx, bz, a, b))

    if not candidates:
        return {
            "ok": False,
            "reason": "no generated segment crossing/near-crossing found",
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
    roads, files = parse_modules()

    named = [r for r in roads if r["name"]]

    print("=" * 76)
    print("CHESTERWORLD ROBLOX TILE EXPORT AUDIT")
    print("=" * 76)
    print(f"Tile modules scanned:       {len(files):,}")
    print(f"Road records parsed:        {len(roads):,}")
    print(f"Named road records parsed:  {len(named):,}")
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
                f"EXPORT X={result['x']:9.2f} Z={result['z']:9.2f} "
                f"gap={result['gap']:.2f} | "
                f"{result['a_tile']} / {result['b_tile']}"
            )
        else:
            print(
                f"{a:>4} & {b:<8} FAILED: {result['reason']}"
            )

    required = [
        ("8th", "Kerlin"),
        ("9th", "Kerlin"),
        ("9th", "Butler"),
        ("9th", "Parker"),
        ("9th", "Fulton"),
        ("9th", "Barclay"),
    ]

    if not all(results[k]["ok"] for k in required):
        print()
        print("AUDIT INCOMPLETE: one or more generated intersections could not be parsed.")
        print("Send this entire output back.")
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

    # right of forward in X/Z
    rx = fz
    rz = -fx

    def right_score(target):
        dx = target["x"] - p9["x"]
        dz = target["z"] - p9["z"]
        return dx*rx + dz*rz

    bscore = right_score(butler)
    pscore = right_score(parker)

    print()
    print("-" * 76)
    print("GENERATED TILE RIGHT-TURN TEST")
    print("-" * 76)
    print(f"8th->9th forward unit: X={fx:+.3f} Z={fz:+.3f}")
    print(f"right unit:            X={rx:+.3f} Z={rz:+.3f}")
    print(f"Butler right score:    {bscore:+.2f}")
    print(f"Parker right score:    {pscore:+.2f}")
    print()
    print(
        "GENERATED ROBLOX TILES SAY RIGHT TURN LEADS TOWARD: "
        + ("PARKER" if pscore > bscore else "BUTLER")
    )

    print()
    print("-" * 76)
    print("GENERATED TILE 9TH STREET X ORDER")
    print("-" * 76)

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
    print("EXPECTED:")
    print("Butler -> Kerlin -> Parker -> Fulton -> Barclay")
    print("=" * 76)


if __name__ == "__main__":
    main()
