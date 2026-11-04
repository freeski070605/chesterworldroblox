#!/usr/bin/env python3
"""Build a self-contained Luau bundle that runs the ChesterWorld world
generation pipeline offline (tools/harness/roblox_mock.luau) and audits the
resulting highway pavement.

Usage:
  python tools/harness/build_bundle.py --rev WORKTREE --out bundle.luau [--tiles r06-r08,c06-c08]
  python tools/harness/build_bundle.py --rev origin/fix/street-owner-grade-separation --out base.luau

--rev selects where server/shared sources come from (git revision or the
working tree). Tile data, terrain model and audit are identical for every
revision so before/after metrics are comparable.

Terrain: the real regional DEM is not in the repository, so the harness uses
a SYNTHETIC bare-earth model: smooth rolling ground plus a notch wherever
the source data says a highway passes OVER another road (that is what a
bare-earth DEM shows under every overpass). Around Kerlin the model is
calibrated to the 2026-11-04 Studio baseline samples (rim ~56.8, floor ~38.7).
Results are therefore evidence about the GENERATOR LOGIC, not about exact
in-world elevations.
"""
from __future__ import annotations
import argparse, json, math, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "highway"))
import tiledata as T  # noqa: E402
from crossings import find as find_crossings  # noqa: E402
from analyze_graph import level  # noqa: E402

SHARED = ["WorldConfig", "WorldPlacement", "StreetData", "HighwayStructureRegistry"]
WORLD_MODULES = ["TileBuilderV2", "TileBuilderV3", "HighwayProfile"]
WORLD_SCRIPTS = ["RoadTerrainConformer", "HighwayInfrastructure"]


def read(rev: str, rel: str) -> str | None:
    if rev == "WORKTREE":
        p = ROOT / rel
        return p.read_text(encoding="utf-8") if p.exists() else None
    r = subprocess.run(["git", "-C", str(ROOT), "show", f"{rev}:{rel}"], capture_output=True)
    return r.stdout.decode("utf-8") if r.returncode == 0 else None


def long_string(text: str) -> str:
    level_ = 1
    while ("]" + "=" * level_ + "]") in text:
        level_ += 1
    eq = "=" * level_
    return f"[{eq}[\n{text}]{eq}]"


# --- corridor classification used ONLY by the audit (same for every rev) ---
HW = {"motorway", "motorway_link", "trunk", "trunk_link"}
MAIN = {"i 95", "i 476", "us 322", "commodore john barry bridge", "conchester"}


def norm(n):
    v = re.sub(r"[^a-z0-9]", " ", str(n or "").lower())
    return re.sub(r"\s+", " ", v).strip()


def route(n):
    p = f" {n} "
    return bool(re.search(r" (i|us|pa) \d+ ", p)) or " barry " in p or " conchester " in p


def corridor(r):
    n = norm(r["name"])
    if not n or any(f" {t} " in f" {n} " for t in ("pedestrian", "amtrak", "csx", "subdivision", "railroad", "rail")) or n.startswith("cr "):
        return False
    if n in MAIN:
        return True
    if r["road_class"] not in HW:
        return False
    if level(r) > 0 and not route(n):
        return False
    return True


def terrain_features():
    feats = []
    for c in find_crossings():
        if not c["relation"].startswith("highway_over"):
            continue
        feats.append(c)
    return feats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", default="WORKTREE")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tiles", default="", help="row/col window, e.g. r06-r08,c06-c08")
    ap.add_argument("--skip-structures", action="store_true")
    ap.add_argument("--extra", default="", help="Luau file appended after the runner (debug probes)")
    args = ap.parse_args()

    roads = T.load_roads()
    tiles = sorted(T.TILE_DIR.glob("tile_r*_c*.lua"))
    if args.tiles:
        m = re.match(r"r(\d+)-r(\d+),c(\d+)-c(\d+)", args.tiles)
        r0, r1, c0, c1 = map(int, m.groups())
        def keep(p):
            rr, cc = map(int, re.match(r"tile_r(\d+)_c(\d+)", p.stem).groups())
            return r0 <= rr <= r1 and c0 <= cc <= c1
        tiles = [p for p in tiles if keep(p)]
    tile_names = {p.stem for p in tiles}

    # Synthetic bare-earth features at every source crossing of the corridor.
    # Truth: NBI-inventory crossings (local street OVER I-95) get a CUT along
    # the highway; everything else uses the unambiguous source layer rule,
    # where the upper road gets a NOTCH in the DEM along the LOWER road.
    INVENTORY_LOCAL_OVER = [  # (upper street prefix, cx, cz, radius)
        ("edgmont", 6223, -2232, 75), ("madison", 6372, -2256, 55),
        ("upland", 6802, -2509, 65), ("potter", 7280, -2752, 65),
        ("chestnut", 8114, -3199, 65), ("melrose", 8901, -3688, 75),
        ("highland", -7366, 4463, 75),
    ]
    by_src = {}
    for r in roads:
        by_src.setdefault(":".join(r["grade_group"].split(":")[:2]), []).append(r)

    def direction_at(src, x, z):
        best = None
        for r in by_src.get(src, []):
            ax, az = T.to_studs(r["x1"], r["z1"]); bx, bz = T.to_studs(r["x2"], r["z2"])
            L = math.hypot(bx - ax, bz - az)
            if L < 0.1:
                continue
            t = max(0, min(1, ((x - ax) * (bx - ax) + (z - az) * (bz - az)) / (L * L)))
            d = math.hypot(ax + (bx - ax) * t - x, az + (bz - az) * t - z)
            if best is None or d < best[0]:
                best = (d, (bx - ax) / L, (bz - az) / L, r["width_m"] * 3)
        return best

    feats = []
    seen = set()
    for (street, cx, cz, rad) in INVENTORY_LOCAL_OVER:
        feats.append((2, cx, cz, 0.0, 0.0, 0.0))  # direction filled below
    cut_dirs = {}
    for c in find_crossings():
        x, z = c["x"], c["z"]
        local_over = None
        for i, (street, cx, cz, rad) in enumerate(INVENTORY_LOCAL_OVER):
            if math.hypot(x - cx, z - cz) <= rad and norm(c["other"]).startswith(street):
                local_over = i
        if local_over is not None:
            d = direction_at(c["hw_src"], x, z)
            if d and local_over not in cut_dirs:
                cut_dirs[local_over] = (d[1], d[2], d[3] / 2)
            continue
        if not c["relation"].startswith("highway_over"):
            continue
        d = direction_at(c["other_src"], x, z)
        if not d:
            continue
        key = (round(x / 30), round(z / 30))
        if key in seen:
            continue
        seen.add(key)
        feats.append((1, x, z, d[1], d[2], d[3] / 2))
    for i, (street, cx, cz, rad) in enumerate(INVENTORY_LOCAL_OVER):
        if i in cut_dirs:
            dx, dz, half = cut_dirs[i]
            feats[i] = (2, cx, cz, dx, dz, half)
    feats = [f for f in feats if not (f[0] == 2 and f[3] == 0 and f[4] == 0)]

    corridor_segments = []
    for r in roads:
        if r["tile"] in tile_names and corridor(r):
            ax, az = T.to_studs(r["x1"], r["z1"]); bx, bz = T.to_studs(r["x2"], r["z2"])
            corridor_segments.append((ax, az, bx, bz, norm(r["name"]), r["grade_group"]))
    all_segments = []
    for r in roads:
        if r["tile"] in tile_names:
            ax, az = T.to_studs(r["x1"], r["z1"]); bx, bz = T.to_studs(r["x2"], r["z2"])
            all_segments.append((ax, az, bx, bz, norm(r["name"])))

    out = []
    out.append("--!nocheck")
    out.append(f"-- generated by tools/harness/build_bundle.py rev={args.rev}")
    out.append((ROOT / "tools/harness/roblox_mock.luau").read_text().replace("return M\n", "local Mock = M\n"))
    out.append("local SRC = {}")
    for name in SHARED:
        text = read(args.rev, f"src/shared/{name}.lua")
        if text is not None:
            out.append(f"SRC[{json.dumps('shared/' + name)}] = {long_string(text)}")
    for name in WORLD_MODULES:
        text = read(args.rev, f"src/server/World/{name}.lua")
        if text is not None:
            out.append(f"SRC[{json.dumps('world/' + name)}] = {long_string(text)}")
    for name in WORLD_SCRIPTS:
        text = read(args.rev, f"src/server/World/{name}.server.lua")
        if text is not None:
            out.append(f"SRC[{json.dumps('script/' + name)}] = {long_string(text)}")
    out.append(f"SRC['bootstrap'] = {long_string(read(args.rev, 'src/server/Bootstrap.server.lua'))}")
    out.append("local TILES = {}")
    for p in tiles:
        out.append(f"TILES[{json.dumps(p.stem)}] = {long_string(p.read_text(encoding='utf-8'))}")
    out.append("local FEATURES = {")
    for f in feats:
        out.append("{%d,%.3f,%.3f,%.5f,%.5f,%.3f}," % f)
    out.append("}")
    out.append("local CORRIDOR = {")
    for s in corridor_segments:
        out.append("{%.3f,%.3f,%.3f,%.3f,%s,%s}," % (s[0], s[1], s[2], s[3], json.dumps(s[4]), json.dumps(s[5])))
    out.append("}")
    out.append("local ALLSEG = {")
    for s in all_segments:
        out.append("{%.3f,%.3f,%.3f,%.3f,%s}," % (s[0], s[1], s[2], s[3], json.dumps(s[4])))
    out.append("}")
    out.append(f"local SKIP_STRUCTURES = {'true' if args.skip_structures else 'false'}")
    out.append(f"local REV = {json.dumps(args.rev)}")
    out.append((ROOT / "tools/harness/runner.luau").read_text())
    if args.extra:
        out.append(Path(args.extra).read_text())
    Path(args.out).write_text("\n".join(out), encoding="utf-8")
    print(f"bundle {args.out}: tiles={len(tiles)} features={len(feats)} corridorSegments={len(corridor_segments)}")


if __name__ == "__main__":
    main()
