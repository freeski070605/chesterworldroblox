"""Overlay a building's tile rectangles on the 1 m DVRPC aerial (private reference).

    py -3 tools/harness/aerial_overlay.py <id> [pad_m] [--grid]
Writes build/institutions/aerial/<id>.png (4 px per source metre, 10 m grid
labelled in source metres so outlines can be traced from it).
"""
import json, math, re, sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DATA = Path(r"E:\ChesterWorld\Data\19_Aerial")
X_OFFSET, Z_OFFSET = 8397592.0, -4837229.0
K = 4


def record(bid):
    for f in (ROOT / "src/shared/WorldData/BuildingTiles").glob("tile_*.lua"):
        t = f.read_text(encoding="utf-8")
        i = t.find(f'["{bid}"]={{style=')
        if i >= 0:
            body = t[i:t.index("}}},", i)]
            rects = [tuple(map(float, r)) for r in re.findall(r"\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)", body)]
            a = float(re.search(r"\ba=([-\d.]+)", body).group(1))
            return rects, a
    raise SystemExit(f"{bid} not found")


def rect_corners(cx, cz, along, across, a):
    # tile convention: CFrame.Angles(0, rad(a), 0) turns local +X (along) to
    # source (east, north) = (cos a, sin a); local +Z (across) to (sin a, -cos a)
    t = math.radians(a)
    ux, uz = math.cos(t), math.sin(t)
    vx, vz = math.sin(t), -math.cos(t)
    out = []
    for s, r in ((1, 1), (1, -1), (-1, -1), (-1, 1)):
        out.append((cx + ux * along / 2 * s + vx * across / 2 * r, cz + uz * along / 2 * s + vz * across / 2 * r))
    return out


def mosaic(x0, z0, x1, z1):
    idx = json.loads((DATA / "index.json").read_text())
    mx0, mx1, my0, my1 = x0 - X_OFFSET, x1 - X_OFFSET, z0 - Z_OFFSET, z1 - Z_OFFSET
    W, H = int(mx1 - mx0), int(my1 - my0)
    can = Image.new("RGB", (W, H))
    for e in idx:
        if e["xmax"] < mx0 or e["xmin"] > mx1 or e["ymax"] < my0 or e["ymin"] > my1:
            continue
        im = Image.open(DATA / e["file"])
        can.paste(im, (int(e["xmin"] - mx0), int(my1 - e["ymax"])))
    return can


def main():
    bid = sys.argv[1]
    pad = float(sys.argv[2]) if len(sys.argv) > 2 and not sys.argv[2].startswith("-") else 25
    rects, a = record(bid)
    pts = [p for r in rects for p in rect_corners(*r, a)]
    x0, x1 = min(p[0] for p in pts) - pad, max(p[0] for p in pts) + pad
    z0, z1 = min(p[1] for p in pts) - pad, max(p[1] for p in pts) + pad
    img = mosaic(x0, z0, x1, z1).resize((int(x1 - x0) * K, int(z1 - z0) * K))
    d = ImageDraw.Draw(img)
    P = lambda x, z: ((x - x0) * K, (z1 - z) * K)
    if "--grid" in sys.argv:
        for gx in range(int(x0 // 10 * 10), int(x1) + 1, 10):
            d.line([P(gx, z0), P(gx, z1)], fill=(0, 255, 255) if gx % 50 == 0 else (0, 120, 140), width=1)
            if gx % 50 == 0:
                d.text(P(gx + 1, z1 - 2), str(gx), fill="cyan")
        for gz in range(int(z0 // 10 * 10), int(z1) + 1, 10):
            d.line([P(x0, gz), P(x1, gz)], fill=(0, 255, 255) if gz % 50 == 0 else (0, 120, 140), width=1)
            if gz % 50 == 0:
                d.text(P(x0 + 1, gz + 2), str(gz), fill="cyan")
    if "--norects" not in sys.argv:
        for i, r in enumerate(rects):
            c = rect_corners(*r, a)
            d.line([P(*p) for p in c + c[:1]], fill="yellow", width=2)
            d.text(P(r[0], r[1]), str(i), fill="yellow")
    out = ROOT / "build/institutions/aerial"
    out.mkdir(parents=True, exist_ok=True)
    img.save(out / f"{bid}.png")
    print(out / f"{bid}.png", img.size, "a=", a)


if __name__ == "__main__":
    main()
