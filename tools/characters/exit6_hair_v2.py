"""Two-strand twist hairstyle for the Exit 6 male, V2.

Shared twist paths feed two meshes:
  * render twists: two interleaved helical strands per twist (the real
    two-strand / beaded look), ~3k tris per twist;
  * game twists: one tube per twist, 5-sided cross-section, a ring at every
    bead peak and valley (radius alternates bead / waist) with the section
    rotated 36 degrees per ring, so each bead keeps full round volume
    (~150 tris per twist) instead of collapsing into a ribbon.

All geometry is built in reference-pixel space (x, Y = side-x - 700, Z = 1140 - row)
against a BVH of the head, exactly like the v1 generators.
"""
import math
import numpy as np
from mathutils import Vector

import exit6_male_spec as S
import build_exit6_male as B

SOLE = S.SOLE
HEAD_C = np.array([0.0, 12.0, SOLE - 268.0])

# tuning
SPACING = 14.0         # px between twist roots (box size)
PART_GAP = 3.2         # half-width of the centre part
R_TWIST = 5.2          # twist radius (px)
PITCH = 8.4            # bead spacing along the twist (px)
STEP = 1.2


def norm(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def surface(bvh, p, d):
    hit = bvh.ray_cast(Vector(p), Vector(d))
    if hit[0] is None:
        return None, None
    loc, n = np.array(hit[0]), np.array(hit[1])
    if n @ (-np.asarray(d, float)) < 0:
        n = -n
    return loc, n


def phi_of(p):
    return math.atan2(p[0], -(p[1] - HEAD_C[1]))


def tip_row(phi, elev):
    a = abs(phi)
    # fringe ends at the brows / eyes, temples to the cheek, sides to the jaw, back to the nape
    return float(np.interp(a, [0.0, 0.45, 0.8, 1.2, 1.7, 2.2, math.pi], [258, 263, 280, 294, 300, 316, 328]))


def roots(bvh, rng):
    n = 4000
    i = np.arange(n) + 0.5
    ph = np.arccos(1 - 2 * i / n)
    th = math.pi * (1 + 5 ** 0.5) * i
    dirs = np.stack([np.cos(th) * np.sin(ph), np.sin(th) * np.sin(ph), np.cos(ph)], 1)
    cand = []
    R = np.array([48.0, 63.0, 53.0])
    for d in dirs:
        if d[0] < 0:
            continue
        dd = norm(d * R)
        p, nrm = surface(bvh, HEAD_C + dd * 220, -dd)
        if p is None:
            continue
        phi = phi_of(p)
        if SOLE - p[2] > B.hairline_y(phi) - 3.5:
            continue
        if p[0] < PART_GAP + 1.0:
            continue
        cand.append((p, nrm))
    rng.shuffle(cand)
    # Poisson-disk selection, the centre-line neighbours first so the part stays straight
    cand.sort(key=lambda c: c[0][0] > PART_GAP + SPACING * 0.6)
    chosen = []
    for p, nrm in cand:
        if all(np.linalg.norm(p - q) >= SPACING for q, _ in chosen):
            # mirrored partner must also keep spacing across the part
            if p[0] < SPACING / 2 and any(np.linalg.norm(p * [-1, 1, 1] - q) < SPACING for q, _ in chosen):
                continue
            chosen.append((p, nrm))
    out = chosen + [(p * np.array([-1, 1, 1]), n_ * np.array([-1, 1, 1])) for p, n_ in chosen]
    return out


def grow(bvh, p, n, rng):
    phi = phi_of(p)
    elev = (p[2] - HEAD_C[2]) / 53.0
    down = np.array([0, 0, -1.0]); fwd = np.array([0, -1.0, 0])
    side = np.array([np.sign(p[0]), 0, 0])
    a = abs(phi)
    if a < 0.7:
        d0 = norm(0.7 * n + 0.3 * fwd + 0.55 * side)
    elif a < 2.0:
        d0 = norm(0.8 * n + 0.2 * side)
    else:
        d0 = norm(0.85 * n + 0.15 * np.array([0, 1.0, 0]))
    d0 = norm(d0 + rng.normal(0, 0.08, 3))
    target = tip_row(phi, elev) + rng.uniform(-4, 4)
    pts = [p - n * 1.5, p.copy()]
    q = p + n * 1.0
    d = d0
    margin = R_TWIST + 0.6
    total = 0
    grav = (0.06 if elev > 0.55 else 0.10) + 0.05 * rng.random()
    while SOLE - q[2] < target and total < 95:
        d = norm(d + down * grav)
        q = q + d * STEP
        hit = bvh.find_nearest(Vector(q))
        if hit[0] is not None:
            h = np.array(hit[0]); nn = norm(q - h)
            dist = np.linalg.norm(q - h)
            inside = (q - h) @ np.array(hit[1]) < 0
            if inside or dist < margin:
                outn = np.array(hit[1]) if not inside else -norm(q - h) if dist > 1e-6 else np.array(hit[1])
                outn = norm(outn if outn @ (q - HEAD_C) > 0 else -outn)
                q = h + outn * margin
                d = norm(d - (d @ outn) * outn * 1.0)
        pts.append(q.copy())
        total += STEP
    return np.array(pts)


def frames(C):
    T = norm(np.gradient(C, axis=0))
    ref = np.array([0, 0, 1.0]) if abs(T[0][2]) < 0.9 else np.array([1.0, 0, 0])
    A1 = np.zeros_like(C); A2 = np.zeros_like(C)
    a = norm(ref - (ref @ T[0]) * T[0])
    for i in range(len(C)):
        a = norm(a - (a @ T[i]) * T[i])
        A1[i] = a; A2[i] = np.cross(T[i], a)
    return T, A1, A2


def smooth_path(pts, step):
    C, _ = B.resample(B.catmull(pts, 8), step)
    return C


def tube(C, A1, A2, T, radii, sides, rot=None, cap=True):
    th = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    rings = []
    for i in range(len(C)):
        t = th + (0 if rot is None else rot[i])
        rings.append(C[i] + radii[i] * (np.cos(t)[:, None] * A1[i] + np.sin(t)[:, None] * A2[i]))
    rings = np.array(rings)
    V = rings.reshape(-1, 3).tolist()
    F = []
    for i in range(len(C) - 1):
        for k in range(sides):
            a = i * sides + k; b = i * sides + (k + 1) % sides
            F.append([a, b, b + sides, a + sides])
    if cap:
        tip = len(V); V.append((C[-1] + T[-1] * radii[-1] * 0.8).tolist())
        base = (len(C) - 1) * sides
        for k in range(sides):
            F.append([base + k, base + (k + 1) % sides, tip])
        root = len(V); V.append((C[0] - T[0] * radii[0] * 0.3).tolist())
        for k in range(sides):
            F.append([(k + 1) % sides, k, root])
    return np.array(V), F


def render_twist(pts, rng):
    C = smooth_path(pts, 0.55)
    T, A1, A2 = frames(C)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    L = s[-1]
    taper = 1.0 - 0.15 * (s / L)
    ph0 = rng.uniform(0, 2 * np.pi)
    out_v, out_f = [], []
    for strand in (0, 1):
        ang = 2 * np.pi * s / (2 * PITCH) + strand * np.pi + ph0
        off = 0.40 * R_TWIST * taper
        Cs = C + off[:, None] * (np.cos(ang)[:, None] * A1 + np.sin(ang)[:, None] * A2)
        Ts, A1s, A2s = frames(Cs)
        # each strand swells between crossings -> round beads
        r = 0.6 * R_TWIST * taper * (1 + 0.12 * np.cos(2 * np.pi * s / PITCH * 2 + ph0))
        v, f = tube(Cs, A1s, A2s, Ts, r, 10)
        base = sum(len(x) for x in out_v)
        out_v.append(v); out_f += [[i + base for i in ff] for ff in f]
    return np.vstack(out_v), out_f


def game_twist(pts, rng):
    C0 = smooth_path(pts, 0.5)
    s0 = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C0, axis=0), axis=1))])
    L = s0[-1]
    n = max(4, int(round(L / (PITCH / 2))))
    sq = np.linspace(0, L, n + 1)
    C = np.stack([np.interp(sq, s0, C0[:, k]) for k in range(3)], 1)
    T, A1, A2 = frames(C)
    taper = 1.0 - 0.15 * (sq / L)
    peak = (np.arange(len(sq)) % 2 == 1)
    radii = R_TWIST * taper * np.where(peak, 1.0, 0.8)
    radii[0] = R_TWIST * 0.85
    rot = np.radians(36.0) * np.arange(len(sq))
    return tube(C, A1, A2, T, radii, 5, rot=rot)


def build(bvh, seed=7):
    rng = np.random.default_rng(seed)
    rts = roots(bvh, rng)
    paths = [grow(bvh, p, n, rng) for p, n in rts]
    hv, hf, gv, gf = [], [], [], []
    for pts in paths:
        v, f = render_twist(pts, rng)
        base = sum(len(x) for x in hv); hv.append(v); hf += [[i + base for i in ff] for ff in f]
        v, f = game_twist(pts, rng)
        base = sum(len(x) for x in gv); gv.append(v); gf += [[i + base for i in ff] for ff in f]
    return rts, paths, (np.vstack(hv), hf), (np.vstack(gv), gf)


# ------------------------------------------------------------------ goatee
GOATEE_ROWS = [317.0, 320, 324, 328, 331, 334, 336.5, 338.5]
GOATEE_HALF = [2.5, 4.0, 7.5, 12.5, 15.0, 14.5, 11.0, 5.0]


def goatee(bvh):
    """Soul patch widening into a broad chin patch; a thin shell offset from the skin."""
    C = np.array([0.0, -10.0, SOLE - 322.0])
    angs = np.radians(np.linspace(-25, 85, 150))
    us = np.linspace(-1, 1, 100)
    m = np.zeros((len(angs), len(us))); grid = np.zeros((len(angs), len(us), 3))
    for i, a in enumerate(angs):
        for j, u in enumerate(us):
            x = u * 19.0
            d = np.array([0, -math.cos(a), -math.sin(a)])
            p, n = surface(bvh, C + np.array([x, 0, 0]) + d * 90, -d)
            if p is None:
                continue
            row = SOLE - p[2]
            # under the chin the outline closes toward the throat
            half = np.interp(row, GOATEE_ROWS, GOATEE_HALF, left=0, right=0)
            if p[1] > -36:
                half *= np.clip(1 - (p[1] + 36) / 8.0, 0, 1)
            e = np.clip((half - abs(x)) / 2.0, 0, 1) * np.clip((row - GOATEE_ROWS[0]) / 1.5, 0, 1)
            m[i, j] = e
            grid[i, j] = p + n * (0.25 + 1.1 * e ** 0.7)
    verts, faces, idx = [], [], -np.ones(m.shape, int)
    for i in range(m.shape[0]):
        for j in range(m.shape[1]):
            if m[i, j] > 0.0:
                idx[i, j] = len(verts); verts.append(grid[i, j])
    for i in range(m.shape[0] - 1):
        for j in range(m.shape[1] - 1):
            a, b, c, d = idx[i, j], idx[i, j + 1], idx[i + 1, j + 1], idx[i + 1, j]
            if min(a, b, c, d) >= 0:
                faces.append([a, b, c, d])
    return np.array(verts), faces
