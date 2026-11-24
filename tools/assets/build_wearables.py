"""EXIT 6 wearables: original procedural meshes for the player look.

Run:  python tools/assets/build_wearables.py
Out:  assets/wear/exit6_wear.glb        (one node per mesh, uploaded once)
      assets/wear/manifest.json          (bounds, triangles, body part)
      src/shared/Exit6WearMeshes.luau    (runtime fit data, generated)

Every mesh is authored in the local space of one R15 body part at the
default (scale 1) blocky body measured in Studio: origin = part centre,
front = -Z, right = +X, units = studs. At runtime Exit6Style scales each
piece by (actual part size / canonical part size), so the same mesh fits
any body scale. Sleeves and leg pieces are authored for the RIGHT limb and
turned 180 degrees about Y for the left one.
"""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "wear"
LUAU = ROOT / "src" / "shared" / "Exit6WearMeshes.luau"
TAU = math.tau

# canonical R15 part sizes (Studio, default HumanoidDescription, 2026-11-24)
CANON = {
    "Head": (1.159, 1.182, 1.161),
    "UpperTorso": (1.943, 1.698, 1.004),
    "LowerTorso": (1.991, 0.401, 1.004),
    "UpperArm": (1.001, 1.242, 1.002),
    "LowerArm": (1.001, 1.118, 1.002),
    "UpperLeg": (0.993, 1.363, 0.973),
    "LowerLeg": (0.993, 1.301, 0.973),
    "Foot": (1.009, 0.312, 1.001),
}
for side in ("Left", "Right"):
    for k in ("UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot"):
        CANON[side + k] = CANON[k]


# ----------------------------------------------------------------- vectors
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    l = length(a)
    return (0.0, 1.0, 0.0) if l < 1e-12 else (a[0] / l, a[1] / l, a[2] / l)
def lerp(a, b, t): return a + (b - a) * t
def vlerp(a, b, t): return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t))
def clamp(x, lo, hi): return lo if x < lo else hi if x > hi else x
def smooth(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0) if e1 != e0 else (1.0 if x >= e1 else 0.0)
    return t * t * (3 - 2 * t)


def rot_y(p, a):
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


def rot_axis(v, axis, a):
    """Rodrigues rotation of v about unit axis."""
    c, s = math.cos(a), math.sin(a)
    return add(add(mul(v, c), mul(cross(axis, v), s)), mul(axis, dot(axis, v) * (1 - c)))


# ----------------------------------------------------------------- mesh
class Prim:
    """One primitive under construction: vertices with outward hints."""

    def __init__(self):
        self.v: list[tuple] = []
        self.n: list[tuple] = []
        self.f: list[tuple] = []

    def add(self, p, n):
        self.v.append(p)
        self.n.append(n)
        return len(self.v) - 1

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def grid(self, rows, closed):
        for r0, r1 in zip(rows, rows[1:]):
            cnt = len(r0)
            for i in range(cnt if closed else cnt - 1):
                j = (i + 1) % cnt
                self.quad(r0[i], r0[j], r1[j], r1[i])


class Mesh:
    def __init__(self, name, part, note=""):
        self.name, self.part, self.note = name, part, note
        self.v: list[tuple] = []
        self.f: list[tuple] = []

    def put(self, prim: Prim, weld=True):
        """Merge a primitive: weld duplicate positions, orient every
        triangle so its face normal agrees with the outward hints."""
        remap = {}
        local = []
        mp = []
        base = len(self.v)
        for i, p in enumerate(prim.v):
            key = (round(p[0], 5), round(p[1], 5), round(p[2], 5)) if weld else i
            if key not in remap:
                remap[key] = len(local)
                local.append(p)
            mp.append(remap[key])
        self.v.extend(local)
        for a, b, c in prim.f:
            ia, ib, ic = mp[a], mp[b], mp[c]
            if ia == ib or ib == ic or ia == ic:
                continue
            pa, pb, pc = local[ia], local[ib], local[ic]
            fn = cross(sub(pb, pa), sub(pc, pa))
            hint = add(add(prim.n[a], prim.n[b]), prim.n[c])
            if dot(fn, hint) < 0:
                ib, ic = ic, ib
            self.f.append((base + ia, base + ib, base + ic))

    def bounds(self):
        xs = [p[0] for p in self.v]; ys = [p[1] for p in self.v]; zs = [p[2] for p in self.v]
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def normals(self):
        acc = [[0.0, 0.0, 0.0] for _ in self.v]
        for a, b, c in self.f:
            fn = cross(sub(self.v[b], self.v[a]), sub(self.v[c], self.v[a]))
            for i in (a, b, c):
                acc[i][0] += fn[0]; acc[i][1] += fn[1]; acc[i][2] += fn[2]
        return [norm(tuple(n)) for n in acc]


# ----------------------------------------------------------------- primitives
def axis_coords(h, r, n_mid, n_r):
    """Sample positions across [-h, h] dense in the rounded ends."""
    inner = max(h - r, 0.0)
    out = []
    for i in range(n_r):
        a = (math.pi / 2) * (1 - i / n_r)
        out.append(-inner - r * math.sin(a))
    for i in range(n_mid + 1):
        out.append(-inner + 2 * inner * i / n_mid)
    for i in range(1, n_r + 1):
        a = (math.pi / 2) * (i / n_r)
        out.append(inner + r * math.sin(a))
    return out


def rounded_box(mesh, c, h, r, n_mid=6, n_r=3, disp=None, xform=None):
    """Rounded box centre c, half extents h, edge radius r. disp(p, n)
    returns a displaced point (garment detail); xform(p) a final warp."""
    r = min(r, *h)
    inner = tuple(max(h[i] - r, 0.0) for i in range(3))
    coords = [axis_coords(h[i], r, n_mid, n_r) for i in range(3)]
    for ax in range(3):
        j, k = (ax + 1) % 3, (ax + 2) % 3
        for s in (-1.0, 1.0):
            pr = Prim()
            rows = []
            for cj in coords[j]:
                row = []
                for ck in coords[k]:
                    q = [0.0, 0.0, 0.0]
                    q[ax] = s * h[ax]; q[j] = cj; q[k] = ck
                    cl = tuple(clamp(q[i], -inner[i], inner[i]) for i in range(3))
                    d = sub(tuple(q), cl)
                    nn = norm(d) if length(d) > 1e-9 else tuple(s if i == ax else 0.0 for i in range(3))
                    p = add(cl, mul(nn, r))
                    if disp:
                        p = disp(p, nn)
                    if xform:
                        p = xform(p)
                    row.append(pr.add(add(p, c), nn))
                rows.append(row)
            pr.grid(rows, False)
            mesh.put(pr)


def frames(points):
    """Parallel-transport frames along a polyline."""
    tangents = []
    for i in range(len(points)):
        a = points[max(0, i - 1)]; b = points[min(len(points) - 1, i + 1)]
        tangents.append(norm(sub(b, a)))
    t0 = tangents[0]
    ref = (0.0, 1.0, 0.0) if abs(t0[1]) < 0.9 else (1.0, 0.0, 0.0)
    nrm = norm(cross(t0, ref))
    out = []
    for t in tangents:
        nrm = norm(sub(nrm, mul(t, dot(nrm, t))))
        out.append((t, nrm, cross(t, nrm)))
    return out


def tube(mesh, points, radius, sides=6, caps=True, squash=1.0, twist=0.0):
    """Tube along points; radius(i, frac) -> r. squash flattens the
    binormal axis (ribbons, chain links)."""
    if len(points) < 2:
        return
    fr = frames(points)
    pr = Prim()
    rows = []
    total = len(points) - 1
    for i, (p, (t, n, b)) in enumerate(zip(points, fr)):
        frac = i / total
        r = radius(i, frac) if callable(radius) else radius
        row = []
        for s in range(sides):
            a = TAU * s / sides + twist * frac
            d = add(mul(n, math.cos(a)), mul(b, math.sin(a) * squash))
            row.append(pr.add(add(p, mul(d, r)), norm(add(mul(n, math.cos(a)), mul(b, math.sin(a))))))
        rows.append(row)
    pr.grid(rows, True)
    if caps:
        for end, row, sign in ((points[0], rows[0], -1), (points[-1], rows[-1], 1)):
            t = fr[0][0] if sign < 0 else fr[-1][0]
            r_end = (radius(0, 0) if sign < 0 else radius(total, 1)) if callable(radius) else radius
            tip = pr.add(add(end, mul(t, sign * r_end * 0.6)), mul(t, sign))
            for s in range(sides):
                pr.f.append((row[s], row[(s + 1) % sides], tip))
    mesh.put(pr, weld=False)


def catmull(pts, per=6):
    """Catmull-Rom resample of control points."""
    out = []
    p = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                   + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in range(3)))
    out.append(pts[-1])
    return out


def resample(pts, step):
    """Even spacing along a polyline."""
    dist = [0.0]
    for a, b in zip(pts, pts[1:]):
        dist.append(dist[-1] + length(sub(b, a)))
    total = dist[-1]
    n = max(2, int(total / step) + 1)
    out, j = [], 0
    for i in range(n):
        d = total * i / (n - 1)
        while j < len(dist) - 2 and dist[j + 1] < d:
            j += 1
        seg = dist[j + 1] - dist[j]
        t = 0 if seg < 1e-9 else (d - dist[j]) / seg
        out.append(vlerp(pts[j], pts[j + 1], t))
    return out, total


def path_len(pts):
    return sum(length(sub(b, a)) for a, b in zip(pts, pts[1:]))


def torus(mesh, c, axis, R, r, nu=16, nv=6, rx=None, rz=None, squash=1.0, bump=None):
    """Ring around `axis` through c. rx / rz give an elliptical ring."""
    axis = norm(axis)
    u0 = norm(cross(axis, (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (1.0, 0.0, 0.0)))
    w0 = cross(axis, u0)
    rx = rx or R; rz = rz or R
    pr = Prim()
    rows = []
    for i in range(nu):
        a = TAU * i / nu
        ring_dir = add(mul(u0, math.cos(a) * rx), mul(w0, math.sin(a) * rz))
        out = norm(ring_dir)
        centre = add(c, ring_dir)
        rr = r * (bump(a) if bump else 1.0)
        row = []
        for j in range(nv):
            b = TAU * j / nv
            d = add(mul(out, math.cos(b)), mul(axis, math.sin(b) * squash))
            row.append(pr.add(add(centre, mul(d, rr)), norm(add(mul(out, math.cos(b)), mul(axis, math.sin(b))))))
        rows.append(row)
    rows.append(rows[0])
    pr.grid(rows, True)
    mesh.put(pr, weld=False)


def ellipsoid(mesh, c, rad, nu=20, nv=12, disp=None):
    pr = Prim()
    rows = []
    for j in range(nv + 1):
        th = math.pi * j / nv
        row = []
        for i in range(nu):
            ph = TAU * i / nu
            n = (math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))
            p = (n[0] * rad[0], n[1] * rad[1], n[2] * rad[2])
            if disp:
                p = disp(p, n)
            row.append(pr.add(add(c, p), n))
        rows.append(row)
    pr.grid(rows, True)
    mesh.put(pr)


def cylinder(mesh, c, axis, radius, half_len, sides=16, bevel=0.0):
    """Capped cylinder (optionally bevelled) along axis."""
    axis = norm(axis)
    u = norm(cross(axis, (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)))
    w = cross(axis, u)
    prof = [(0.0, -half_len), (radius - bevel, -half_len), (radius, -half_len + bevel),
            (radius, half_len - bevel), (radius - bevel, half_len), (0.0, half_len)]
    pr = Prim()
    rows = []
    for rr, hh in prof:
        row = []
        for s in range(sides):
            a = TAU * s / sides
            radial = add(mul(u, math.cos(a)), mul(w, math.sin(a)))
            hint = norm(add(mul(radial, rr / max(radius, 1e-6)), mul(axis, hh / max(half_len, 1e-6) * 0.5)))
            row.append(pr.add(add(add(c, mul(radial, rr)), mul(axis, hh)), hint))
        rows.append(row)
    pr.grid(rows, True)
    mesh.put(pr)


# ----------------------------------------------------------------- head shell
HX, HY, HZ = 0.5795, 0.591, 0.5805
HEAD_R = 0.585
HEAD_E = 0.22          # top edge rounding of the classic head
SQ = 2.3               # squircle exponent (covers round and blocky heads)


def head_r(az):
    s, c = abs(math.sin(az)), abs(math.cos(az))
    return HEAD_R / (s ** SQ + c ** SQ) ** (1 / SQ)


def az_dir(az):
    return (math.sin(az), 0.0, -math.cos(az))


def head_len(az):
    """Arc length from y=-1 up the side, round the edge, to the crown."""
    rh = head_r(az)
    side = (HY - HEAD_E) + 1.0
    return side, side + math.pi * HEAD_E / 2, side + math.pi * HEAD_E / 2 + (rh - HEAD_E)


def head_point(az, ell, t):
    """Point on the head surface offset outward by t; ell = arc length."""
    rh = head_r(az)
    l_side, l_corner, l_top = head_len(az)
    if ell <= l_side:
        rho, y, nr, ny = rh, -1.0 + ell, 1.0, 0.0
    elif ell <= l_corner:
        phi = (ell - l_side) / HEAD_E
        rho = rh - HEAD_E + HEAD_E * math.cos(phi)
        y = HY - HEAD_E + HEAD_E * math.sin(phi)
        nr, ny = math.cos(phi), math.sin(phi)
    else:
        rho, y, nr, ny = max(rh - HEAD_E - (ell - l_corner), 0.0), HY, 0.0, 1.0
    d = az_dir(az)
    rr = rho + nr * t
    return (d[0] * rr, y + ny * t, d[2] * rr), (d[0] * nr, ny, d[2] * nr)


def ell_at_y(az, y):
    """Arc length where the head side reaches height y (side or edge)."""
    l_side, l_corner, l_top = head_len(az)
    if y <= HY - HEAD_E:
        return y + 1.0
    phi = math.asin(clamp((y - (HY - HEAD_E)) / HEAD_E, 0, 1))
    return l_side + phi * HEAD_E


def keyed(table, deg):
    deg = abs(deg)
    for (a0, y0), (a1, y1) in zip(table, table[1:]):
        if a0 <= deg <= a1:
            return lerp(y0, y1, smooth(0, 1, (deg - a0) / (a1 - a0)) * 0.5 + (deg - a0) / (a1 - a0) * 0.5)
    return table[-1][1]


# hairline keypoints (degrees from the front, y in head space)
HL_FULL = [(0, .34), (28, .34), (40, .30), (55, .20), (66, .02), (76, -.08), (84, .10), (100, .14),
           (118, .0), (140, -.20), (180, -.32)]


def hl(table, raise_sides=0.0, start=55, full=80):
    def f(az):
        deg = math.degrees(az)
        y = keyed(table, deg)
        return y + raise_sides * smooth(start, full, abs(deg))
    return f


def head_cap(mesh, low, thick, cols=56, rows=18, high=None, disp=None, rim=True, hole=None, rim_r=None):
    """Shell over the head from the line low(az) up to the crown (or up
    to high(az)). thick(az, v) is the offset; v = 0 at the edge, 1 at top."""
    pr = Prim()
    grid_rows = []
    keep = []
    for j in range(rows + 1):
        v = j / rows
        row = []
        krow = []
        for i in range(cols):
            az = TAU * i / cols - math.pi
            l0 = ell_at_y(az, low(az))
            l1 = ell_at_y(az, high(az)) if high else head_len(az)[2]
            ell = lerp(l0, l1, v)
            t = thick(az, v)
            p, n = head_point(az, ell, t)
            if disp:
                p = disp(p, n, az, v)
            row.append(pr.add(p, n))
            krow.append(hole is None or not hole(p))
        grid_rows.append(row)
        keep.append(krow)
    for j in range(rows):
        for i in range(cols):
            k = (i + 1) % cols
            if keep[j][i] and keep[j][k] and keep[j + 1][i] and keep[j + 1][k]:
                pr.quad(grid_rows[j][i], grid_rows[j][k], grid_rows[j + 1][k], grid_rows[j + 1][i])
    mesh.put(pr)
    if rim:
        pts = []
        for i in range(cols + 1):
            az = TAU * (i % cols) / cols - math.pi
            p, n = head_point(az, ell_at_y(az, low(az)), thick(az, 0.0) * 0.5)
            pts.append(p)
        rr = rim_r or max(thick(0.0, 0.0) * 0.55, 0.012)
        tube(mesh, pts, rr, sides=5, caps=False)


def head_sdf(p):
    """Signed distance (approx) to the head envelope; below the head the
    neck is thin, so nothing collides there."""
    x, y, z = p
    rho = math.hypot(x, z)
    az = math.atan2(x, -z)
    rh = head_r(az)
    if y < -HY:
        return 1.0
    if y <= HY - HEAD_E:
        side = rho - rh
        top = y - HY
        return max(side, top)
    if rho <= rh - HEAD_E:
        return y - HY
    return math.hypot(rho - (rh - HEAD_E), y - (HY - HEAD_E)) - HEAD_E


def head_grad(p):
    e = 1e-3
    return norm(tuple((head_sdf(add(p, d)) - head_sdf(sub(p, d))) for d in ((e, 0, 0), (0, e, 0), (0, 0, e))))


# torso, in head space (head centre is 1.386 above the torso centre)
TORSO_TOP = -0.50
TORSO_HALF = (1.0, 0.62)


def strand(root, nrm, length_, gravity, margin, sweep=None, brow=0.18, rng=None, step=0.05, lift=0.35):
    """Grow one strand from a scalp root; returns the polyline."""
    # hair flows away from the crown along the scalp, then gravity takes it
    away = sub(root, (0.0, HY + 0.1, 0.08))
    flow = sub(away, mul(nrm, dot(away, nrm)))
    flow = norm(flow) if length(flow) > 1e-6 else norm((root[0] + 1e-3, 0.0, root[2] + 1e-3))
    d = norm(add(add(mul(nrm, lift), flow), (0.0, -0.15, 0.0)))
    if sweep:
        d = norm(add(d, sweep))
    p = root
    pts = [p]
    travelled = 0.0
    while travelled < length_:
        d = norm(add(d, (0.0, -gravity * step * 6, 0.0)))
        q = add(p, mul(d, step))
        # keep outside the head
        sd = head_sdf(q)
        if sd < margin:
            q = add(q, mul(head_grad(q), margin - sd))
        # bangs stop at the brow, side pieces at the jaw
        front = q[2] < -0.35 and abs(q[0]) < 0.45
        if front and q[1] < brow:
            break
        # shoulders: hair behind the back slides down it, on the shoulders it rests
        if q[1] < TORSO_TOP and abs(q[0]) < TORSO_HALF[0] and abs(q[2]) < TORSO_HALF[1]:
            if q[2] > 0.25:
                q = (q[0], q[1], TORSO_HALF[1] + 0.02)
                d = norm((d[0] * 0.3, -1.0, 0.05))
            else:
                break
        travelled += length(sub(q, p))
        d = norm(sub(q, p))
        p = q
        pts.append(p)
    return pts


def scalp_roots(low, t, count, rng, min_dist, region=None):
    """Even-ish roots over the hair area (dart throwing)."""
    roots = []
    tries = 0
    while len(roots) < count and tries < count * 400:
        tries += 1
        az = rng.uniform(-math.pi, math.pi)
        l0 = ell_at_y(az, low(az))
        l1 = head_len(az)[2]
        ell = rng.uniform(l0 + 0.04, l1)
        p, n = head_point(az, ell, t)
        rho = math.hypot(p[0], p[2])
        if rng.random() > max(rho / head_r(az), 0.25):
            continue
        if region and not region(p, az):
            continue
        if all(length(sub(p, q[0])) >= min_dist for q in roots):
            roots.append((p, n, az))
    return roots


def twist_r(base, freq, amp, taper=0.25):
    def f(i, frac, total=None):
        tip = smooth(1.0, 1.0 - taper, frac) * 0.55 + 0.45
        return base * (1 + amp * math.sin(i * freq)) * tip
    return f


def braid_r(base, amp=0.28, period=2.0):
    def f(i, frac):
        tip = smooth(1.0, 0.85, frac) * 0.5 + 0.5
        return base * (1 + amp * abs(math.sin(math.pi * i / period))) * tip
    return f


def noise3(p, k):
    x, y, z = p
    return (math.sin(x * k + 1.3) * math.sin(y * k * 1.17 + 0.7) * math.sin(z * k * 0.93 + 2.1)
            + 0.5 * math.sin(x * k * 2.3 + z * k * 1.9) * math.sin(y * k * 2.1 + 1.1))


# ----------------------------------------------------------------- builders
MESHES: list[Mesh] = []


def new(name, part, note=""):
    m = Mesh(name, part, note)
    MESHES.append(m)
    return m


def fade_band(name, lo, hi, t=0.014):
    m = new(name, "Head", "semi-transparent fade band")
    head_cap(m, lo, lambda az, v: t, rows=5, high=hi, rim=False)


def hair_cut(name, low, top_t, edge_t=0.012, disp=None):
    m = new(name, "Head", "hair")
    def thick(az, v):
        return lerp(edge_t, top_t, smooth(0.0, 0.45, v))
    head_cap(m, low, thick, disp=disp, rim_r=0.012)
    return m


def build_hair():
    rng = random.Random(6)
    full = hl(HL_FULL)

    # low taper / caesar with a sharp line-up
    low_op = hl(HL_FULL, 0.12, 60, 80)
    hair_cut("hair_sharp_low_taper", low_op, 0.04)
    fade_band("fade_sharp_low_taper", lambda az: full(az) - 0.03, lambda az: low_op(az) + 0.04)

    # mid skin fade: sides start at the temple
    mid_op = lambda az: max(full(az), lerp(full(az), 0.20, smooth(50, 72, abs(math.degrees(az)))))
    hair_cut("hair_mid_skin_fade", mid_op, 0.05)
    fade_band("fade_mid_a", lambda az: min(mid_op(az) - 0.18, mid_op(az) - 0.01), lambda az: mid_op(az) + 0.04)
    fade_band("fade_mid_b", lambda az: full(az) - 0.02, lambda az: mid_op(az) - 0.15)

    # high-top fade: tight sides, tall flat block
    high_op = lambda az: max(full(az), lerp(full(az), 0.36, smooth(40, 60, abs(math.degrees(az)))))
    m = hair_cut("hair_high_top_fade", high_op, 0.03)
    rounded_box(m, (0.0, 0.88, 0.02), (0.56, 0.46, 0.55), 0.12, n_mid=6, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.008 * noise3(p, 55))),
                xform=lambda p: (p[0] * (1 + 0.05 * (p[1] + 0.46)), p[1], p[2] * (1 + 0.05 * (p[1] + 0.46))))
    fade_band("fade_high_a", lambda az: high_op(az) - 0.2, lambda az: high_op(az) + 0.04)
    fade_band("fade_high_b", lambda az: full(az) - 0.02, lambda az: high_op(az) - 0.17)

    # 360 waves: concentric ridges round the crown
    crown = (0.0, 0.62, 0.18)
    def waves(p, n, az, v):
        d = length(sub(p, crown))
        return add(p, mul(n, 0.012 * math.sin(d * TAU / 0.075) * smooth(0.02, 0.25, v)))
    hair_cut("hair_waves_360", low_op, 0.04, disp=waves)
    fade_band("fade_waves", lambda az: full(az) - 0.03, lambda az: low_op(az) + 0.04)

    # afro taper: a round coily puff (outer surface = an ellipsoid round the
    # crown), tapering into the fade only right at the hairline
    A_C, A_R = (0.0, 0.26, 0.05), (0.84, 0.74, 0.86)
    def to_ellipsoid(p, n):
        lo, hi = 0.0, 0.8
        for _ in range(22):
            mid = (lo + hi) / 2
            q = add(p, mul(n, mid))
            e = sum(((q[i] - A_C[i]) / A_R[i]) ** 2 for i in range(3))
            if e < 1.0:
                lo = mid
            else:
                hi = mid
        return lo
    def afro_t(az, v):
        l0 = ell_at_y(az, low_op(az)); l1 = head_len(az)[2]
        p, n = head_point(az, lerp(l0, l1, v), 0.0)
        return lerp(0.03, max(to_ellipsoid(p, n), 0.05), smooth(0.0, 0.2, v))
    def coils(p, n, az, v):
        return add(p, mul(n, 0.022 * noise3(p, 38) * smooth(0.05, 0.4, v)))
    m = new("hair_afro_taper", "Head", "hair")
    head_cap(m, low_op, afro_t, cols=64, rows=24, disp=coils, rim_r=0.014)
    fade_band("fade_afro", lambda az: full(az) - 0.03, lambda az: low_op(az) + 0.04)

    # locs: base cap + grown strands
    def locs(name, count, lmin, lmax, radius, gravity, lift, brow, sides=5, seed=1, step=0.055, amp=0.16):
        r = random.Random(seed)
        m = new(name, "Head", "hair")
        head_cap(m, full, lambda az, v: lerp(0.02, 0.045, smooth(0, .4, v)), rim_r=0.012)
        roots = scalp_roots(full, 0.04, count, r, radius * 1.7)
        for p, n, az in roots:
            L = r.uniform(lmin, lmax)
            pts = strand(p, n, L, gravity, 0.045 + radius * 0.9, brow=brow, lift=lift, step=step,
                         sweep=(r.uniform(-.08, .08), 0.0, r.uniform(-.05, .08)))
            if len(pts) >= 3:
                tube(m, pts, twist_r(radius, 2.4 + r.random(), amp), sides=sides)
        return m

    locs("hair_starter_locs", 52, 0.20, 0.32, 0.048, 0.35, 0.9, -1, seed=11)
    locs("hair_medium_locs", 74, 0.50, 0.78, 0.046, 1.2, 0.3, 0.16, seed=12)
    locs("hair_shoulder_locs", 74, 0.95, 1.35, 0.045, 1.4, 0.3, 0.16, seed=13, step=0.07)
    locs("hair_two_strand_twists", 96, 0.18, 0.30, 0.036, 0.25, 1.0, -1, seed=14, step=0.045, amp=0.32)

    # cornrows: braided rows front to back
    def surface_along(dirv, offset):
        lo, hi = 0.0, 1.6
        for _ in range(28):
            mid = (lo + hi) / 2
            if head_sdf(mul(dirv, mid)) < offset:
                lo = mid
            else:
                hi = mid
        return mul(dirv, hi)

    def row_path(lam, back_end=1.0, target=None):
        pts = []
        for k in range(41):
            beta = lerp(-0.15, math.pi * 0.98 * back_end, k / 40)
            dirv = norm((lam * (0.55 + 0.35 * math.sin(beta)), math.sin(beta) * 1.0 + 0.25, -math.cos(beta)))
            if target is not None:
                dirv = norm(vlerp(dirv, target, smooth(0.3, 1.0, k / 40)))
            p = surface_along(dirv, 0.045)
            az = math.atan2(p[0], -p[2])
            if p[1] >= full(az) + 0.02:
                pts.append(p)
        return pts

    def cornrow_cap(name, rows_, target=None, back_end=1.0):
        m = new(name, "Head", "hair")
        head_cap(m, full, lambda az, v: 0.022, rim_r=0.01)
        for i in range(rows_):
            lam = lerp(-1.0, 1.0, i / (rows_ - 1))
            pts = row_path(lam, back_end, target)
            if len(pts) > 3:
                pts, _ = resample(pts, 0.035)
                tube(m, pts, braid_r(0.042, 0.3, 2.0), sides=6)
        return m

    cornrow_cap("hair_cornrows", 8)

    # box braids: cornrow-parted cap + long hanging braids
    r = random.Random(21)
    m = new("hair_box_braids", "Head", "hair")
    head_cap(m, full, lambda az, v: 0.028, rim_r=0.012)
    for p, n, az in scalp_roots(full, 0.03, 46, r, 0.075):
        side = 1 if p[0] >= 0 else -1
        sweep = (side * 0.35, 0.0, 0.55) if p[2] < 0.1 else (0.0, 0.0, 0.2)
        pts = strand(p, n, r.uniform(1.05, 1.4), 1.3, 0.075, sweep=sweep, brow=0.5, lift=0.2, step=0.06)
        if len(pts) >= 3:
            tube(m, pts, braid_r(0.036, 0.3, 1.6), sides=5)

    # braided ponytail: rows sweep to the back of the crown
    tgt = norm((0.0, 0.45, 0.9))
    m = cornrow_cap("hair_braided_ponytail", 6, target=tgt, back_end=0.62)
    base = (0.0, 0.42, 0.66)
    torus(m, add(base, (0, -0.02, 0.04)), (0.0, 0.3, 1.0), 0.09, 0.03, nu=14, nv=6)
    tail = catmull([base, (0.0, 0.25, 0.86), (0.0, -0.25, 0.80), (0.0, -0.8, 0.72), (0.0, -1.2, 0.70)], per=8)
    tail, _ = resample(tail, 0.035)
    tube(m, tail, lambda i, f: 0.085 * (1 + 0.3 * abs(math.sin(math.pi * i / 2.2))) * (1 - 0.45 * f), sides=8)

    # high bun (slick back + coily bun)
    soft = hl(HL_FULL, -0.04, 60, 80)
    m = new("hair_high_bun", "Head", "hair")
    head_cap(m, soft, lambda az, v: lerp(0.015, 0.035, v), rim_r=0.01)
    ellipsoid(m, (0.0, 0.80, 0.16), (0.36, 0.30, 0.34), nu=28, nv=16,
              disp=lambda p, n: add(p, mul(n, 0.03 * noise3(p, 30))))
    torus(m, (0.0, 0.58, 0.12), (0.0, 1.0, 0.2), 0.24, 0.05, nu=20, nv=6)

    # space buns
    m = new("hair_space_buns", "Head", "hair")
    head_cap(m, soft, lambda az, v: lerp(0.015, 0.035, v), rim_r=0.01)
    for s in (-1, 1):
        ellipsoid(m, (s * 0.40, 0.66, 0.06), (0.25, 0.24, 0.25), nu=22, nv=12,
                  disp=lambda p, n: add(p, mul(n, 0.025 * noise3(p, 34))))
    # middle part
    tube(m, [(0.0, 0.62, -0.25), (0.0, 0.64, 0.0), (0.0, 0.6, 0.3)], 0.012, sides=4)

    # long silk press: full cap, drape down the back, face-framing sides
    m = new("hair_long_silk_press", "Head", "hair")
    def press_t(az, v):
        return lerp(0.02, 0.07, smooth(0, .5, v))
    def strands_fx(p, n, az, v):
        return add(p, mul(n, 0.006 * math.sin(az * 70)))
    head_cap(m, soft, press_t, disp=strands_fx, rim_r=0.015)
    def drape(p, n):
        return add(p, mul(n, 0.006 * math.sin(p[0] * 80)))
    rounded_box(m, (0.0, -0.55, 0.69), (0.56, 0.78, 0.075), 0.07, n_mid=6, n_r=2, disp=drape,
                xform=lambda p: (p[0] * (1 + 0.2 * clamp(-(p[1]) / 1.2, 0, 1)), p[1], p[2] + 0.08 * clamp((0.3 - p[1]) / 1.0, 0, 1)))
    for s in (-1, 1):
        rounded_box(m, (s * 0.64, -0.12, -0.12), (0.07, 0.5, 0.34), 0.06, n_mid=5, n_r=2, disp=drape,
                    xform=lambda p, s=s: (p[0] + s * 0.05 * clamp(-(p[1] + 0.1), 0, 1), p[1], p[2]))


# ----------------------------------------------------------------- clothing
def quilt(row_h, amp, axis=1):
    def d(p, n):
        frac = (p[axis] / row_h) % 1.0
        bulge = math.sin(math.pi * frac) ** 0.6
        side = 1.0 if abs(n[1]) < 0.85 else 0.3
        return add(p, mul(n, amp * bulge * side))
    return d


def rib(freq, amp):
    def d(p, n):
        a = math.atan2(p[0], p[2])
        return add(p, mul(n, amp * math.sin(a * freq)))
    return d


def flare(y0, y1, amount):
    """Widen x/z towards y1 (a hem or sleeve opening)."""
    def x(p):
        t = smooth(y0, y1, p[1]) if y1 > y0 else smooth(y0, y1, p[1])
        s = 1 + amount * t
        return (p[0] * s, p[1], p[2] * s)
    return x


def build_tops():
    # canonical upper torso half: (0.97, 0.85, 0.50)
    # tee / tank: torso reaching over the hips (covers the lower torso too)
    m = new("tee_torso", "UpperTorso", "tee body, hangs to the hips")
    rounded_box(m, (0.0, -0.18, 0.0), (1.005, 1.06, 0.545), 0.16, n_mid=7, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.006 * math.sin(p[0] * 9 + p[1] * 3))),
                xform=flare(-0.6, -1.24, 0.025))
    torus(m, (0.0, 0.89, -0.02), (0.0, 1.0, 0.0), 0.3, 0.035, nu=20, nv=6, rx=0.33, rz=0.28)

    m = new("tee_sleeve", "UpperArm", "short sleeve")
    rounded_box(m, (0.0, 0.25, 0.0), (0.545, 0.42, 0.545), 0.16, n_mid=5, n_r=3, xform=flare(0.2, -0.17, 0.06))
    torus(m, (0.0, -0.15, 0.0), (0.0, 1.0, 0.0), 0.5, 0.03, nu=20, nv=5, rx=0.56, rz=0.56)

    # hoodie: baggy body, kangaroo pocket, drawstrings, bunched hood
    m = new("hoodie_torso", "UpperTorso", "pullover hoodie body")
    rounded_box(m, (0.0, -0.2, 0.0), (1.04, 1.08, 0.575), 0.18, n_mid=7, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.008 * math.sin(p[0] * 7 + p[1] * 4))))
    torus(m, (0.0, -1.24, 0.0), (0.0, 1.0, 0.0), 1.0, 0.045, nu=28, nv=6, rx=1.03, rz=0.56, squash=1.4)
    rounded_box(m, (0.0, -0.73, -0.585), (0.58, 0.28, 0.035), 0.03, n_mid=4, n_r=2,
                xform=lambda p: (p[0] * (1 - 0.15 * clamp((p[1] + 0.73) / 0.28, 0, 1)), p[1], p[2]))
    hood = catmull([(-0.42, 0.86, -0.30), (-0.52, 0.96, 0.05), (-0.30, 1.02, 0.38), (0.0, 1.04, 0.47),
                    (0.30, 1.02, 0.38), (0.52, 0.96, 0.05), (0.42, 0.86, -0.30)], per=6)
    tube(m, hood, lambda i, f: 0.13 + 0.07 * math.sin(math.pi * f), sides=10, squash=0.75)
    rounded_box(m, (0.0, 0.55, 0.62), (0.40, 0.36, 0.06), 0.05, n_mid=4, n_r=2,
                xform=lambda p: (p[0] * (1 - 0.25 * clamp((0.55 - p[1]) / 0.5, 0, 1)), p[1], p[2]))
    for s in (-1, 1):
        cord = [(s * 0.13, 0.84, -0.56), (s * 0.15, 0.6, -0.6), (s * 0.14, 0.35, -0.6)]
        tube(m, catmull(cord, 4), 0.018, sides=5)
        cylinder(m, (s * 0.14, 0.31, -0.6), (0, 1, 0), 0.025, 0.04, sides=6)

    # long sleeve pieces (hoodie / track jacket / puffer share this cut)
    m = new("sleeve_upper", "UpperArm", "long sleeve, upper")
    rounded_box(m, (0.0, 0.03, 0.0), (0.55, 0.66, 0.55), 0.17, n_mid=5, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.006 * math.sin(p[1] * 11 + p[2] * 5))))
    m = new("sleeve_lower", "LowerArm", "long sleeve, lower with ribbed cuff")
    rounded_box(m, (0.0, 0.08, 0.0), (0.535, 0.5, 0.535), 0.15, n_mid=5, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.012 * smooth(-0.1, -0.4, p[1]) * (0.5 + 0.5 * math.sin(p[1] * 40)))))
    rounded_box(m, (0.0, -0.46, 0.0), (0.51, 0.06, 0.51), 0.12, n_mid=4, n_r=2, disp=rib(28, 0.008))

    # track jacket: fitted body, stand collar; trims carry the stripes
    m = new("track_torso", "UpperTorso", "track jacket body")
    rounded_box(m, (0.0, -0.17, 0.0), (1.0, 1.05, 0.545), 0.15, n_mid=7, n_r=3,
                xform=flare(-0.8, -1.22, -0.03))
    torus(m, (0.0, 0.92, 0.0), (0.0, 1.0, 0.0), 0.34, 0.06, nu=22, nv=6, rx=0.38, rz=0.32, squash=1.8)
    m = new("track_trim_torso", "UpperTorso", "zip line + collar tape (accent)")
    rounded_box(m, (0.0, -0.18, -0.553), (0.035, 1.0, 0.018), 0.015, n_mid=4, n_r=1)
    cylinder(m, (0.0, 0.72, -0.575), (0, 0, 1), 0.035, 0.012, sides=8)
    for s in (-1, 1):
        rounded_box(m, (s * 0.99, 0.55, 0.0), (0.03, 0.18, 0.2), 0.02, n_mid=3, n_r=1)
    m = new("track_trim_upper", "UpperArm", "sleeve stripes (accent), outer side")
    for dz in (-0.09, 0.09):
        rounded_box(m, (0.555, 0.03, dz), (0.012, 0.64, 0.035), 0.01, n_mid=4, n_r=1)
    m = new("track_trim_lower", "LowerArm", "sleeve stripes (accent), outer side")
    for dz in (-0.09, 0.09):
        rounded_box(m, (0.54, 0.08, dz), (0.012, 0.48, 0.035), 0.01, n_mid=4, n_r=1)

    # puffer: quilted body + stand collar, quilted sleeves
    m = new("puffer_torso", "UpperTorso", "quilted puffer jacket body")
    rounded_box(m, (0.0, -0.2, 0.0), (1.08, 1.08, 0.62), 0.24, n_mid=10, n_r=3, disp=quilt(0.3, 0.07))
    torus(m, (0.0, 0.95, 0.0), (0.0, 1.0, 0.0), 0.42, 0.1, nu=24, nv=8, rx=0.46, rz=0.40, squash=1.6)
    m = new("puffer_upper", "UpperArm", "quilted puffer sleeve, upper")
    rounded_box(m, (0.0, 0.03, 0.0), (0.6, 0.67, 0.6), 0.22, n_mid=8, n_r=3, disp=quilt(0.26, 0.06))
    m = new("puffer_lower", "LowerArm", "quilted puffer sleeve, lower")
    rounded_box(m, (0.0, 0.08, 0.0), (0.58, 0.5, 0.58), 0.2, n_mid=7, n_r=3, disp=quilt(0.24, 0.05))
    rounded_box(m, (0.0, -0.46, 0.0), (0.5, 0.06, 0.5), 0.1, n_mid=4, n_r=2, disp=rib(28, 0.008))


def build_bottoms():
    # lower torso waistband (under any top)
    m = new("pants_waist", "LowerTorso", "waistband + drawcord")
    rounded_box(m, (0.0, -0.02, 0.0), (1.02, 0.24, 0.53), 0.12, n_mid=6, n_r=2)
    rounded_box(m, (0.0, 0.17, 0.0), (1.03, 0.06, 0.535), 0.05, n_mid=6, n_r=2, disp=rib(60, 0.004))

    m = new("pants_upper", "UpperLeg", "pant leg, thigh")
    rounded_box(m, (0.0, -0.02, 0.0), (0.53, 0.72, 0.52), 0.16, n_mid=5, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.008 * math.sin(p[1] * 9 + p[2] * 6))))

    m = new("jogger_lower", "LowerLeg", "jogger leg tapering into a gathered cuff")
    rounded_box(m, (0.0, 0.12, 0.0), (0.52, 0.55, 0.51), 0.15, n_mid=6, n_r=3,
                disp=lambda p, n: add(p, mul(n, 0.012 * smooth(-0.1, -0.4, p[1]) * math.sin(p[1] * 34))),
                xform=lambda p: (p[0] * (1 - 0.08 * smooth(0.3, -0.4, p[1])), p[1], p[2] * (1 - 0.08 * smooth(0.3, -0.4, p[1]))))
    rounded_box(m, (0.0, -0.47, 0.0), (0.47, 0.07, 0.46), 0.1, n_mid=4, n_r=2, disp=rib(26, 0.007))

    m = new("jeans_stacked_lower", "LowerLeg", "straight denim leg stacking over the shoe")
    rounded_box(m, (0.0, 0.2, 0.0), (0.525, 0.47, 0.515), 0.15, n_mid=5, n_r=3)
    for i, y in enumerate((-0.2, -0.31, -0.42, -0.52)):
        rounded_box(m, (0.0, y, 0.0), (0.55 + 0.012 * i, 0.075, 0.54 + 0.012 * i), 0.07, n_mid=4, n_r=2,
                    xform=lambda p, i=i: (p[0], p[1] + 0.02 * math.sin(math.atan2(p[0], p[2]) * 2 + i), p[2]))

    m = new("shorts_upper", "UpperLeg", "basketball shorts leg past the knee")
    rounded_box(m, (0.0, -0.13, 0.0), (0.57, 0.84, 0.56), 0.16, n_mid=6, n_r=3, xform=flare(0.0, -0.95, 0.06))

    m = new("leg_trim_upper", "UpperLeg", "side stripes (accent), outer side")
    for dz in (-0.08, 0.08):
        rounded_box(m, (0.535, -0.02, dz), (0.012, 0.7, 0.033), 0.01, n_mid=4, n_r=1)
    m = new("leg_trim_lower", "LowerLeg", "side stripes (accent), outer side")
    for dz in (-0.08, 0.08):
        rounded_box(m, (0.525, 0.08, dz), (0.012, 0.5, 0.033), 0.01, n_mid=4, n_r=1)


def build_shoes():
    # foot canonical half (0.50, 0.156, 0.50); toe at -Z
    def toe_drop(p):
        # lower the toe box, round the heel
        t = smooth(0.1, -0.7, p[2])
        return (p[0] * (1 - 0.08 * t), p[1] - 0.09 * t * smooth(-0.2, 0.2, p[1]), p[2])
    m = new("sneaker_upper", "Foot", "low-top sneaker upper with laces")
    rounded_box(m, (0.0, 0.07, -0.1), (0.52, 0.22, 0.64), 0.16, n_mid=6, n_r=3, xform=toe_drop)
    torus(m, (0.0, 0.29, 0.22), (0.0, 1.0, 0.2), 0.3, 0.05, nu=18, nv=6, rx=0.42, rz=0.32)
    for k in range(4):
        z = -0.16 - 0.12 * k
        tube(m, [(-0.24, 0.27 - 0.03 * k, z), (0.0, 0.3 - 0.03 * k, z - 0.01), (0.24, 0.27 - 0.03 * k, z)], 0.022, sides=5)
    m = new("sneaker_sole", "Foot", "cupsole (white / gum)")
    rounded_box(m, (0.0, -0.12, -0.1), (0.55, 0.07, 0.67), 0.06, n_mid=6, n_r=2,
                xform=lambda p: (p[0], p[1] + 0.04 * smooth(-0.4, -0.8, p[2]) * smooth(-0.1, 0.1, p[1]), p[2]))

    m = new("boot_upper", "Foot", "work boot, padded collar above the ankle")
    rounded_box(m, (0.0, 0.32, -0.08), (0.55, 0.48, 0.63), 0.18, n_mid=7, n_r=3,
                xform=lambda p: (p[0], p[1] - 0.32 * smooth(0.0, -0.6, p[2]) * smooth(-0.1, 0.4, p[1]), p[2]))
    torus(m, (0.0, 0.8, 0.05), (0.0, 1.0, 0.0), 0.5, 0.07, nu=20, nv=6, rx=0.54, rz=0.52)
    for k in range(5):
        z = -0.25 - 0.06 * k
        y = 0.72 - 0.13 * k
        tube(m, [(-0.3, y, z), (0.0, y + 0.02, z - 0.12), (0.3, y, z)], 0.02, sides=5)
    m = new("boot_sole", "Foot", "lug sole")
    rounded_box(m, (0.0, -0.11, -0.08), (0.58, 0.085, 0.68), 0.06, n_mid=6, n_r=2,
                disp=lambda p, n: add(p, mul(n, 0.01 * (1 if math.sin(p[2] * 40) > 0 else 0) * (1 if n[1] < -0.5 else 0))))


def digit_six(scale=1.0):
    """Centreline of a bold '6' in its own XY plane (origin at loop centre)."""
    loop = [(0.065 * math.cos(a), 0.065 * math.sin(a), 0.0) for a in [math.pi * 0.95 - TAU * k / 22 for k in range(23)]]
    stem = catmull([(-0.064, 0.02, 0.0), (-0.055, 0.10, 0.0), (-0.02, 0.165, 0.0), (0.04, 0.19, 0.0), (0.075, 0.17, 0.0)], per=5)
    path = list(reversed(stem)) + loop[1:]
    # authored seen from behind; mirror so it reads as a 6 from the front (-Z)
    return [(-p[0] * scale, p[1] * scale, p[2] * scale) for p in path]


def build_hats():
    full = hl(HL_FULL)
    # fitted cap: tall crown, flat brim, button, panel seams
    cap_low = lambda az: lerp(0.24, 0.12, smooth(30, 120, abs(math.degrees(az))))
    def crown_t(az, v):
        return 0.15 + 0.05 * math.sin(math.pi * clamp(v * 1.2, 0, 1)) + 0.08 * smooth(0.5, 1.0, v)
    m = new("cap_fitted", "Head", "fitted cap crown + flat brim")
    head_cap(m, cap_low, crown_t, rows=16, rim_r=0.03)
    for k in range(6):
        az = TAU * k / 6 - math.pi
        pts = []
        for j in range(13):
            v = j / 12
            l0 = ell_at_y(az, cap_low(az)); l1 = head_len(az)[2]
            p, n = head_point(az, lerp(l0, l1, v), crown_t(az, v) + 0.006)
            pts.append(p)
        tube(m, pts, 0.008, sides=4)
    cylinder(m, (0.0, HY + 0.24, 0.0), (0, 1, 0), 0.06, 0.018, sides=10, bevel=0.012)
    rounded_box(m, (0.0, 0.21, -0.84), (0.47, 0.022, 0.25), 0.02, n_mid=6, n_r=2,
                xform=lambda p: (p[0] * (1 - 0.15 * smooth(-0.85, -1.1, p[2])), p[1] - 0.02 * (p[0] * p[0]), p[2]))
    m = new("cap_emblem", "Head", "embroidered '6' on the crown front (accent)")
    six = digit_six(1.6)
    tilt = math.radians(-14)
    pts = [(p[0], 0.42 + p[1] * math.cos(tilt), -0.78 - p[1] * math.sin(tilt)) for p in six]
    tube(m, pts, 0.026, sides=6, squash=0.5)

    # beanie: ribbed knit with folded cuff
    m = new("beanie", "Head", "ribbed knit beanie with fold")
    b_low = lambda az: lerp(0.24, 0.10, smooth(30, 120, abs(math.degrees(az))))
    head_cap(m, b_low, lambda az, v: 0.07 + 0.1 * smooth(0.6, 1.0, v), rows=16,
             disp=lambda p, n, az, v: add(p, mul(n, 0.01 * math.sin(az * 36))), rim=False)
    pts = []
    for i in range(41):
        az = TAU * i / 40 - math.pi
        p, n = head_point(az, ell_at_y(az, b_low(az) + 0.08), 0.1)
        pts.append(p)
    tube(m, pts, 0.1, sides=8, caps=False, squash=0.75)

    # durag: tight cap, centre seam, forehead band, flowing tail
    m = new("durag", "Head", "durag with seam and tails")
    d_low = lambda az: lerp(0.30, -0.12, smooth(20, 140, abs(math.degrees(az))))
    head_cap(m, d_low, lambda az, v: 0.03, rows=14, rim_r=0.02)
    seam = []
    for k in range(25):
        beta = lerp(0.1, math.pi * 0.92, k / 24)
        dirv = norm((0.0, math.sin(beta) + 0.25, -math.cos(beta)))
        lo, hi = 0.0, 1.5
        for _ in range(24):
            mid = (lo + hi) / 2
            if head_sdf(mul(dirv, mid)) < 0.045:
                lo = mid
            else:
                hi = mid
        seam.append(mul(dirv, hi))
    tube(m, seam, 0.018, sides=5)
    for s in (-1, 1):
        tail = catmull([(s * 0.05, -0.05, 0.62), (s * 0.08, -0.3, 0.72), (s * 0.1, -0.65, 0.68), (s * 0.12, -0.95, 0.66)], per=6)
        tube(m, tail, lambda i, f: 0.11 * (1 - 0.3 * f), sides=8, squash=0.18, twist=0.6 * s)

    # ski mask: knit cover with eye and mouth openings
    m = new("ski_mask", "Head", "knit ski mask")
    def holes(p):
        az = math.degrees(math.atan2(p[0], -p[2]))
        eyes = abs(az) < 50 and -0.02 < p[1] < 0.2
        mouth = abs(az) < 20 and -0.34 < p[1] < -0.17
        return eyes or mouth
    head_cap(m, lambda az: -0.66, lambda az, v: 0.035 + 0.06 * smooth(0.75, 1.0, v), cols=64, rows=24,
             disp=lambda p, n, az, v: add(p, mul(n, 0.006 * math.sin(az * 40))), hole=holes, rim_r=0.03)


def build_jewelry():
    # chains drape from the back of the neck over the shoulders to the chest
    def chain_path(drop=0.36, front_z=-0.6):
        ctrl = [(0.0, 0.9, 0.36), (-0.3, 0.92, 0.22), (-0.42, 0.9, -0.12), (-0.33, 0.8, -0.48), (-0.24, 0.62, front_z),
                (-0.11, drop + 0.06, front_z - 0.01), (0.0, drop, front_z - 0.012),
                (0.11, drop + 0.06, front_z - 0.01), (0.24, 0.62, front_z), (0.33, 0.8, -0.48), (0.42, 0.9, -0.12),
                (0.3, 0.92, 0.22), (0.0, 0.9, 0.36)]
        return catmull(ctrl, per=10)

    m = new("chain_cuban", "UpperTorso", "Cuban link chain")
    pts, total = resample(chain_path(), 0.052)
    fr = frames(pts)
    for i, (p, (t, n, b)) in enumerate(zip(pts[:-1], fr)):
        # links lie flat on the body, alternating a quarter twist
        up = norm(sub(p, (0.0, 0.3, 0.0)))
        axis = norm(cross(t, up)) if i % 2 == 0 else norm(rot_axis(norm(cross(t, up)), t, 0.9))
        u0 = t
        w0 = cross(axis, u0)
        pr = Prim()
        rows = []
        for a_i in range(10):
            a = TAU * a_i / 10
            ring = add(mul(u0, math.cos(a) * 0.036), mul(w0, math.sin(a) * 0.024))
            o = norm(ring)
            centre = add(p, ring)
            row = []
            for b_i in range(5):
                bb = TAU * b_i / 5
                d = add(mul(o, math.cos(bb)), mul(axis, math.sin(bb) * 0.7))
                row.append(pr.add(add(centre, mul(d, 0.0145)), norm(add(mul(o, math.cos(bb)), mul(axis, math.sin(bb))))))
            rows.append(row)
        rows.append(rows[0])
        pr.grid(rows, True)
        m.put(pr, weld=False)

    m = new("chain_rope", "UpperTorso", "rope chain (twisted)")
    base, _ = resample(chain_path(0.42), 0.02)
    fr = frames(base)
    for strand_i in range(2):
        helix = []
        for i, (p, (t, n, b)) in enumerate(zip(base, fr)):
            a = i * 0.9 + math.pi * strand_i
            helix.append(add(p, add(mul(n, 0.012 * math.cos(a)), mul(b, 0.012 * math.sin(a)))))
        tube(m, helix, 0.011, sides=5, caps=False)

    # pendant '6' with bail, hangs from the chain's low point
    m = new("pendant_six", "UpperTorso", "'6' pendant (logo mark)")
    six = digit_six(1.0)
    pts = [(p[0], 0.13 + p[1], -0.635) for p in six]
    tube(m, pts, 0.024, sides=7, squash=0.6)
    torus(m, (0.0, 0.355, -0.63), (1.0, 0.0, 0.0), 0.028, 0.01, nu=10, nv=5)

    # headphones resting round the neck
    m = new("headphones_neck", "UpperTorso", "over-ear headphones round the neck")
    band = catmull([(-0.45, 0.88, -0.22), (-0.5, 1.0, 0.1), (-0.3, 1.06, 0.38), (0.0, 1.08, 0.45),
                    (0.3, 1.06, 0.38), (0.5, 1.0, 0.1), (0.45, 0.88, -0.22)], per=6)
    tube(m, band, 0.035, sides=7, squash=0.6)
    for s in (-1, 1):
        cylinder(m, (s * 0.42, 0.9, -0.38), norm((s * 0.25, 1.0, -0.35)), 0.17, 0.065, sides=18, bevel=0.03)
        torus(m, (s * 0.42, 0.9, -0.38), norm((s * 0.25, 1.0, -0.35)), 0.15, 0.04, nu=16, nv=6)

    # watch on the left wrist: case faces out (-X), band wraps the forearm
    m = new("watch_case", "LeftLowerArm", "watch case + band")
    ring = []
    for k in range(33):
        a = TAU * k / 32
        s, c = math.sin(a), math.cos(a)
        r = 0.535 / (abs(s) ** 4 + abs(c) ** 4) ** 0.25
        ring.append((r * c, -0.36, r * s))
    tube(m, ring, 0.05, sides=6, caps=False, squash=1.4)
    cylinder(m, (-0.585, -0.36, 0.0), (1, 0, 0), 0.17, 0.05, sides=20, bevel=0.025)
    torus(m, (-0.63, -0.36, 0.0), (1, 0, 0), 0.165, 0.022, nu=20, nv=5)
    m = new("watch_dial", "LeftLowerArm", "watch dial (accent / ice)")
    cylinder(m, (-0.64, -0.36, 0.0), (1, 0, 0), 0.14, 0.008, sides=20)

    # bracelet on the right wrist (cuban links round the cuff line)
    m = new("bracelet_cuban", "RightLowerArm", "Cuban link bracelet")
    ring = []
    for k in range(29):
        a = TAU * k / 28
        s, c = math.sin(a), math.cos(a)
        r = 0.54 / (abs(s) ** 4 + abs(c) ** 4) ** 0.25
        ring.append((r * c, -0.38, r * s))
    tube(m, ring, lambda i, f: 0.035 * (1 + 0.35 * abs(math.sin(math.pi * i / 1.0))), sides=6, caps=False, squash=1.3)

    # earrings: studs and hoops at ear height
    m = new("earring_studs", "Head", "diamond studs")
    for s in (-1, 1):
        ellipsoid(m, (s * 0.6, -0.06, 0.04), (0.035, 0.05, 0.05), nu=10, nv=6)
    m = new("earring_hoops", "Head", "gold hoops")
    for s in (-1, 1):
        torus(m, (s * 0.61, -0.2, 0.04), (1, 0, 0), 0.14, 0.018, nu=24, nv=6)

    # shades: frame and lenses
    m = new("shades_frame", "Head", "sunglasses frame")
    for s in (-1, 1):
        rim = []
        for k in range(29):
            a = TAU * k / 28
            sn, cs = math.sin(a), math.cos(a)
            rr = 1 / (abs(sn) ** 3 + abs(cs) ** 3) ** (1 / 3)
            x = s * 0.22 + cs * rr * 0.16
            y = 0.08 + sn * rr * 0.095 - 0.02 * (cs * s > 0.3)
            z = -0.63 - 0.03 * (1 - abs(x) / 0.4)
            rim.append((x, y, z))
        tube(m, rim, 0.02, sides=5, caps=False)
        arm = [(s * 0.385, 0.12, -0.6), (s * 0.62, 0.12, -0.45), (s * 0.63, 0.1, 0.0), (s * 0.6, 0.02, 0.15)]
        tube(m, catmull(arm, 5), 0.018, sides=5, squash=0.7)
    tube(m, catmull([(-0.065, 0.12, -0.665), (0.0, 0.135, -0.675), (0.065, 0.12, -0.665)], 4), 0.02, sides=5)
    m = new("shades_lens", "Head", "sunglasses lenses (tint)")
    for s in (-1, 1):
        ellipsoid(m, (s * 0.22, 0.075, -0.64), (0.16, 0.095, 0.015), nu=18, nv=6)


# ----------------------------------------------------------------- export
def write_glb(meshes, path):
    bin_chunks = bytearray()
    accessors, views, gl_meshes, nodes, materials = [], [], [], [], []

    def view(data, target):
        off = len(bin_chunks)
        bin_chunks.extend(data)
        while len(bin_chunks) % 4:
            bin_chunks.append(0)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1

    for m in meshes:
        nrm = m.normals()
        pos = bytearray(); nb = bytearray(); uv = bytearray()
        for p, n in zip(m.v, nrm):
            pos += struct.pack("<3f", *p)
            nb += struct.pack("<3f", *n)
            ax = max(range(3), key=lambda i: abs(n[i]))
            u, v = [(p[1], p[2]), (p[0], p[2]), (p[0], p[1])][ax]
            uv += struct.pack("<2f", u * 0.5, v * 0.5)
        idx = bytearray()
        for f in m.f:
            idx += struct.pack("<3I", *f)
        lo, hi = m.bounds()
        a_pos = len(accessors)
        accessors.append({"bufferView": view(pos, 34962), "componentType": 5126, "count": len(m.v), "type": "VEC3",
                          "min": list(lo), "max": list(hi)})
        accessors.append({"bufferView": view(nb, 34962), "componentType": 5126, "count": len(m.v), "type": "VEC3"})
        accessors.append({"bufferView": view(uv, 34962), "componentType": 5126, "count": len(m.v), "type": "VEC2"})
        accessors.append({"bufferView": view(idx, 34963), "componentType": 5125, "count": len(m.f) * 3, "type": "SCALAR"})
        materials.append({"name": m.name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0,
                                                                     "roughnessFactor": 1}})
        gl_meshes.append({"name": m.name, "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_pos + 1,
                                                                          "TEXCOORD_0": a_pos + 2},
                                                           "indices": a_pos + 3, "material": len(materials) - 1}]})
        nodes.append({"name": m.name, "mesh": len(gl_meshes) - 1})

    gltf = {"asset": {"version": "2.0", "generator": "exit6 build_wearables.py"},
            "scene": 0, "scenes": [{"name": "Exit6Wear", "nodes": list(range(len(nodes)))}],
            "nodes": nodes, "meshes": gl_meshes, "materials": materials,
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(bin_chunks)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(bin_chunks)
    with path.open("wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(bin_chunks), 0x004E4942)); f.write(bin_chunks)


def main():
    import sys
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--patch="):
            only = a.split("=", 1)[1].split(",")
    build_hair()
    build_tops()
    build_bottoms()
    build_shoes()
    build_hats()
    build_jewelry()
    OUT.mkdir(parents=True, exist_ok=True)
    names = [m.name for m in MESHES]
    assert len(names) == len(set(names)), "duplicate mesh names"
    manifest = []
    lines = [
        "-- GENERATED by tools/assets/build_wearables.py - do not edit by hand.",
        "-- Fit data for every EXIT 6 wearable mesh: the body part it is authored",
        "-- on (canonical R15 sizes below), its bounds size and centre in that",
        "-- part's space. Templates: ServerStorage.Exit6ProductionAssets.Wear.<name>",
        "local M = {}",
        "M.Canon = {",
    ]
    for k in ("Head", "UpperTorso", "LowerTorso", "UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot"):
        x, y, z = CANON[k]
        lines.append(f"\t{k} = Vector3.new({x}, {y}, {z}),")
    lines += ["}", "M.Meshes = {"]
    for m in MESHES:
        lo, hi = m.bounds()
        size = tuple(hi[i] - lo[i] for i in range(3))
        ctr = tuple((hi[i] + lo[i]) / 2 for i in range(3))
        tris = len(m.f)
        assert tris < 20000, f"{m.name}: {tris} triangles over the Roblox limit"
        manifest.append({"name": m.name, "part": m.part, "triangles": tris, "vertices": len(m.v),
                         "size": [round(s, 4) for s in size], "center": [round(c, 4) for c in ctr], "note": m.note})
        lines.append(f'\t{m.name} = {{ part = "{m.part}", tris = {tris}, '
                     f"size = Vector3.new({size[0]:.4f}, {size[1]:.4f}, {size[2]:.4f}), "
                     f"center = Vector3.new({ctr[0]:.4f}, {ctr[1]:.4f}, {ctr[2]:.4f}) }},")
    lines += ["}", "return M", ""]
    write_glb(MESHES, OUT / "exit6_wear.glb")
    if only:
        sel = [m for m in MESHES if m.name in only]
        assert len(sel) == len(only), "unknown mesh in --patch"
        write_glb(sel, OUT / "exit6_wear_patch.glb")
        print("patch glb:", ", ".join(m.name for m in sel))
    # local preview copies for Studio (EditableMesh over localhost); build/ is not committed
    prev = ROOT / "build" / "wear_preview"
    prev.mkdir(parents=True, exist_ok=True)
    for m in MESHES:
        data = {"v": [round(c, 4) for p in m.v for c in p], "f": [i for f in m.f for i in f]}
        (prev / f"{m.name}.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    LUAU.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    total = sum(m["triangles"] for m in manifest)
    for m in manifest:
        print(f"{m['name']:28s} {m['part']:14s} {m['triangles']:6d} tris  size {m['size']}")
    print(f"{len(manifest)} meshes, {total} triangles, glb {(OUT / 'exit6_wear.glb').stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
