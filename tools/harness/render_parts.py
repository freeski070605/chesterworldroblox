"""Offline renderer for Roblox part dumps (used when the Studio viewport cannot
render). Input lines, one per part, grouped by "#<id> <frontBearing>":

    K x y z rx ry rz sx sy sz hex     (K: P part, W wedge, C corner wedge,
                                        Y cylinder, B ball; rotations are
                                        CFrame:ToOrientation degrees)

Wedge: tall edge on local +Z (slope rises from -Z to +Z).
CornerWedge: apex over the local (+X, -Z) corner (probed in Studio 2026-11-24).
Cylinders are 10-sided prisms, balls 10x5 facet spheres; painter's algorithm (PIL only).

    py -3 tools/harness/render_parts.py DUMP.txt OUT.png [per_sheet]
"""
import math
import sys

from PIL import Image, ImageDraw

def mm(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mv(A, v):
    return [sum(A[i][k] * v[k] for k in range(3)) for i in range(3)]


def rot(rx, ry, rz):
    # Roblox ToOrientation: R = Ry(y) * Rx(x) * Rz(z)
    x, y, z = map(math.radians, (rx, ry, rz))
    Rx = [[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]]
    Ry = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    Rz = [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]]
    return mm(mm(Ry, Rx), Rz)


def faces(kind, s):
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    if kind == "W":
        b = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]
        t = [(-hx, hy, hz), (hx, hy, hz)]
        return [b, [b[2], b[3], t[0], t[1]], [b[0], b[1], t[1], t[0]], [b[0], b[3], t[0]], [b[1], b[2], t[1]]]
    if kind == "C":
        b = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]
        a = (hx, hy, -hz)
        return [b, [b[0], b[1], a], [b[1], b[2], a], [b[2], b[3], a], [b[3], b[0], a]]
    if kind == "Y":
        # axis along local X
        n, r = 10, min(hy, hz)
        ring = [(math.cos(2 * math.pi * i / n) * r, math.sin(2 * math.pi * i / n) * r) for i in range(n)]
        out = [[(-hx, a, c) for a, c in ring], [(hx, a, c) for a, c in ring]]
        for i in range(n):
            a0, c0 = ring[i]
            a1, c1 = ring[(i + 1) % n]
            out.append([(-hx, a0, c0), (hx, a0, c0), (hx, a1, c1), (-hx, a1, c1)])
        return out
    if kind == "B":
        n, r = 10, hx
        out = []
        for j in range(n // 2):
            p0, p1 = math.pi * j / (n // 2) - math.pi / 2, math.pi * (j + 1) / (n // 2) - math.pi / 2
            for i in range(n):
                t0, t1 = 2 * math.pi * i / n, 2 * math.pi * (i + 1) / n
                pt = lambda p, t: (r * math.cos(p) * math.cos(t), r * math.sin(p), r * math.cos(p) * math.sin(t))
                out.append([pt(p0, t0), pt(p0, t1), pt(p1, t1), pt(p1, t0)])
        return out
    c = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
         (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    idx = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (0, 3, 7, 4)]
    return [[c[i] for i in f] for f in idx]


def parse(path):
    groups, cur = [], None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            bid, front = line[1:].split()
            cur = {"id": bid, "front": float(front), "parts": []}
            groups.append(cur)
            continue
        k, *v = line.split()
        nums = list(map(float, v[:9]))
        cur["parts"].append((k, nums[0:3], nums[3:6], nums[6:9], v[9]))
    return groups


def render(groups, out, cell=520):
    cols = min(3, len(groups))
    rows = (len(groups) + cols - 1) // cols
    img = Image.new("RGB", (cell * cols, cell * rows), (214, 226, 236))
    d = ImageDraw.Draw(img)
    light = [0.35, 0.85, -0.4]
    for gi, g in enumerate(groups):
        ox, oy = (gi % cols) * cell, (gi // cols) * cell
        world = []
        for k, pos, ang, size, hexc in g["parts"]:
            R = rot(*ang)
            base = [int(hexc[i:i + 2], 16) for i in (0, 2, 4)]
            for f in faces(k, size):
                world.append(([[a + b for a, b in zip(mv(R, p), pos)] for p in f], base))
        allp = [p for f, _ in world for p in f]
        cx = sum(p[0] for p in allp) / len(allp)
        cz = sum(p[2] for p in allp) / len(allp)
        top = max(p[1] for p in allp)
        rad = max(math.hypot(p[0] - cx, p[2] - cz) for p in allp)
        # camera in front of the photographed front, a little to the left, raised
        b = math.radians(g["front"] + 28)
        fwd = (math.sin(b), 0, -math.cos(b))           # compass bearing -> Roblox (-Z north)
        dist = max(rad, top) * 2.6
        eye = (cx + fwd[0] * dist, top * 0.55 + dist * 0.18, cz + fwd[2] * dist)
        tgt = (cx, top * 0.4, cz)
        f = [t - e for t, e in zip(tgt, eye)]
        fl = math.sqrt(sum(v * v for v in f)); f = [v / fl for v in f]
        r = [-f[2], 0, f[0]]; rl = math.sqrt(sum(v * v for v in r)); r = [v / rl for v in r]
        u = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]]   # screen up = right x forward
        scale = cell * 1.25
        polys = []
        for face, base in world:
            cam = [[sum((p[i] - eye[i]) * a[i] for i in range(3)) for a in (r, u, f)] for p in face]
            if any(c[2] <= 1 for c in cam):
                continue
            depth = sum(c[2] for c in cam) / len(cam)
            pts = [(ox + cell / 2 + c[0] / c[2] * scale, oy + cell * 0.62 - c[1] / c[2] * scale) for c in cam]
            if len(face) >= 3:
                a, bb, c = face[0], face[1], face[2]
                n = [(bb[1] - a[1]) * (c[2] - a[2]) - (bb[2] - a[2]) * (c[1] - a[1]),
                     (bb[2] - a[2]) * (c[0] - a[0]) - (bb[0] - a[0]) * (c[2] - a[2]),
                     (bb[0] - a[0]) * (c[1] - a[1]) - (bb[1] - a[1]) * (c[0] - a[0])]
                nl = math.sqrt(sum(v * v for v in n)) or 1
                shade = 0.55 + 0.45 * abs(sum(n[i] / nl * light[i] for i in range(3)))
            else:
                shade = 0.8
            polys.append((depth, pts, tuple(min(255, int(v * shade)) for v in base)))
        polys.sort(key=lambda t: -t[0])
        for _, pts, col in polys:
            d.polygon(pts, fill=col, outline=tuple(max(0, v - 40) for v in col))
        d.text((ox + 8, oy + 8), f"{g['id']}  ({len(g['parts'])} parts)", fill=(20, 20, 20))
    img.save(out)


if __name__ == "__main__":
    groups = parse(sys.argv[1])
    per = int(sys.argv[3]) if len(sys.argv) > 3 else len(groups)
    for k in range(0, len(groups), per):
        out = sys.argv[2] if per >= len(groups) else sys.argv[2].replace(".png", f"_{k // per:02d}.png")
        render(groups[k:k + per], out)
        print("wrote", out)
