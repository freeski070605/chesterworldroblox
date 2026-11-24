"""EXIT 6 Premium collection: original meshes for the Robux cosmetics line.

Run:  python tools/assets/build_premium.py
Out:  assets/wear/premium/exit6_premium.glb   (one node per mesh, with UVs + tangents)
      assets/wear/premium/manifest.json
      src/shared/Exit6PremiumMeshes.luau       (runtime fit data, generated)

Same conventions as build_wearables.py (whose helpers this reuses): every
mesh is authored in the local space of one R15 part at the canonical size,
front = -Z, right = +X, studs. Exit6Style scales and welds it.

Differences from the base wardrobe:
- Each mesh carries UVs (per-face box charts, so no smeared seams) at a
  texel density chosen for its texture set, and MikkTSpace-style tangents,
  so the PBR SurfaceAppearance sets from build_premium_textures.py (normal,
  roughness, metalness maps) render properly.
- Lettering ("EXIT 6") is extruded from hand-drawn glyph outlines (no font
  data), with a bevelled metal rim and a recessed stone face.
- Gems are faceted (flat shaded); overlays are clipped shells of the base.

Visual reference: the EXIT 6 concept sheets (hero / premium cosmetics /
clothing + footwear). Every shape here is original; the sneaker uses an
original rising "exit arrow" side mark, not any brand's mark.
"""
from __future__ import annotations

import json
import math
import random
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_wearables as W  # noqa: E402
from build_wearables import (  # noqa: E402
    TAU, Prim, Mesh, add, sub, mul, dot, cross, length, norm, lerp, vlerp, clamp, smooth,
    rot_y, axis_coords, tube, catmull, resample, torus, ellipsoid, cylinder, rounded_box,
    head_cap, head_point, head_len, ell_at_y, head_sdf, hl, HL_FULL, HY, strand, scalp_roots,
    twist_r, braid_r, noise3, frames, quilt, rib,
)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "wear" / "premium"
LUAU = ROOT / "src" / "shared" / "Exit6PremiumMeshes.luau"
TRI_LIMIT = 20000

# texture sets (build_premium_textures.py) and how many tiles per stud each uses
TEX_DENSITY = {
    "nylon": 2.2,      # puffer shell ripstop
    "fleece": 2.0,     # cotton fleece / track knit
    "knit": 4.0,       # rib cuffs, cap wool
    "leather": 2.6,    # sneaker leather
    "rubber": 3.0,     # soles
    "pave": 3.4,       # pave-set stones (stone ~0.02 studs)
    "metal": 2.5,      # polished / brushed silver
    "locs": 5.0,       # matted hair fibre
}

MESHES: list[Mesh] = []


def new(name, part, tex, note=""):
    assert name.startswith("px_"), name
    assert tex in TEX_DENSITY, tex
    m = Mesh(name, part, note)
    m.tex = tex
    MESHES.append(m)
    return m


# ----------------------------------------------------------------- primitives
def rbox(mesh, c, h, r, n=(6, 6, 6), n_r=3, disp=None, xform=None, keep=None):
    """Rounded box with a sample count per axis (rows of quilting need dense
    sampling along one axis only). keep(p) drops quads (for clipped shells)."""
    r = min(r, *h)
    inner = tuple(max(h[i] - r, 0.0) for i in range(3))
    coords = [axis_coords(h[i], r, n[i], n_r) for i in range(3)]
    for ax in range(3):
        j, k = (ax + 1) % 3, (ax + 2) % 3
        for s in (-1.0, 1.0):
            pr = Prim()
            rows = []
            pos = []
            for cj in coords[j]:
                row = []
                prow = []
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
                    p = add(p, c)
                    row.append(pr.add(p, nn))
                    prow.append(p)
                rows.append(row)
                pos.append(prow)
            for a in range(len(rows) - 1):
                for b in range(len(rows[a]) - 1):
                    if keep:
                        quad = (pos[a][b], pos[a][b + 1], pos[a + 1][b + 1], pos[a + 1][b])
                        cen = tuple(sum(q[i] for q in quad) / 4 for i in range(3))
                        if not keep(cen):
                            continue
                    pr.quad(rows[a][b], rows[a][b + 1], rows[a + 1][b + 1], rows[a + 1][b])
            mesh.put(pr)


def facet(mesh, pts, centre):
    """One flat facet (convex polygon) - its own vertices, so it shades flat."""
    pr = Prim()
    c = tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))
    hint = norm(sub(c, centre))
    idx = [pr.add(p, hint) for p in pts]
    for i in range(1, len(idx) - 1):
        pr.f.append((idx[0], idx[i], idx[i + 1]))
    mesh.put(pr, weld=False)


def basis(axis):
    axis = norm(axis)
    u = norm(cross(axis, (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)))
    return axis, u, cross(axis, u)


# ----------------------------------------------------------------- glyphs
# Hand-drawn bold block letters, cap height 1, origin bottom-left, CCW.
GLYPHS = {
    "E": ([(0, 0), (0.72, 0), (0.72, 0.24), (0.29, 0.24), (0.29, 0.39), (0.63, 0.39), (0.63, 0.61),
           (0.29, 0.61), (0.29, 0.76), (0.72, 0.76), (0.72, 1), (0, 1)], [], 0.72),
    "X": ([(0, 0), (0.29, 0), (0.43, 0.29), (0.57, 0), (0.86, 0), (0.6, 0.5), (0.86, 1), (0.57, 1),
           (0.43, 0.71), (0.29, 1), (0, 1), (0.26, 0.5)], [], 0.86),
    "I": ([(0, 0), (0.3, 0), (0.3, 1), (0, 1)], [], 0.3),
    "T": ([(0.23, 0), (0.53, 0), (0.53, 0.75), (0.76, 0.75), (0.76, 1), (0, 1), (0, 0.75), (0.23, 0.75)], [], 0.76),
    # chamfered jersey "6": outer outline + the bowl's counter (a hole)
    "6": ([(0.12, 0), (0.78, 0), (0.9, 0.12), (0.9, 0.72), (0.78, 0.84), (0.3, 0.84), (0.3, 1.16),
           (0.86, 1.16), (0.86, 1.4), (0.12, 1.4), (0, 1.28), (0, 0.12)],
          [[(0.28, 0.24), (0.28, 0.6), (0.62, 0.6), (0.62, 0.24)]], 0.9),
}


def area2(poly):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1])) / 2


def oriented(poly, ccw):
    return list(poly) if (area2(poly) > 0) == ccw else list(reversed(poly))


def inset(poly, d):
    """Offset a contour into the solid by d (outer CCW / hole CW: the left
    side of every edge is solid)."""
    n = len(poly)
    out = []
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        e1 = (b[0] - a[0], b[1] - a[1]); e2 = (c[0] - b[0], c[1] - b[1])
        l1 = math.hypot(*e1) or 1; l2 = math.hypot(*e2) or 1
        n1 = (-e1[1] / l1, e1[0] / l1); n2 = (-e2[1] / l2, e2[0] / l2)
        m = (n1[0] + n2[0], n1[1] + n2[1])
        ml = math.hypot(*m)
        if ml < 1e-9:
            m, ml = n1, 1.0
        m = (m[0] / ml, m[1] / ml)
        k = d / max(m[0] * n1[0] + m[1] * n1[1], 0.4)
        out.append((b[0] + m[0] * k, b[1] + m[1] * k))
    return out


def bridge(outer, hole):
    """Join a CW hole into a CCW outer contour (ear clipping needs one loop)."""
    mi = max(range(len(hole)), key=lambda i: (hole[i][0], -hole[i][1]))
    M = hole[mi]
    best, bx = None, math.inf
    n = len(outer)
    for i in range(n):
        a, b = outer[i], outer[(i + 1) % n]
        if a[1] == b[1] or (a[1] - M[1]) * (b[1] - M[1]) > 0:
            continue
        t = (M[1] - a[1]) / (b[1] - a[1])
        x = a[0] + t * (b[0] - a[0])
        if x >= M[0] and x < bx:
            bx, best = x, i
    a, b = outer[best], outer[(best + 1) % n]
    pi = best if a[0] > b[0] else (best + 1) % n
    return outer[:pi + 1] + hole[mi:] + hole[:mi + 1] + [outer[pi]] + outer[pi + 1:]


def earclip(poly):
    """Triangulate a simple CCW polygon (may contain a bridge seam)."""
    idx = list(range(len(poly)))
    tris = []

    def cross2(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def inside(p, a, b, c):
        return cross2(a, b, p) >= -1e-12 and cross2(b, c, p) >= -1e-12 and cross2(c, a, p) >= -1e-12

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        clipped = False
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = poly[i0], poly[i1], poly[i2]
            if cross2(a, b, c) <= 1e-12:
                continue
            ok = True
            for j in idx:
                p = poly[j]
                if j in (i0, i1, i2) or p == a or p == b or p == c:
                    continue
                if inside(p, a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(k)
                clipped = True
                break
        if not clipped:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def extrude_text(face, body, layout, mapping, depth, rim=0.06, recess=0.25, back=True):
    """Extrude glyph outlines. layout = [(outer, holes)] in 2D; mapping(x, y, z)
    -> body point, z in [0, depth] with z = depth the front. The front stone
    face (inset by `rim`, recessed) goes to `face`; walls, the bevelled rim
    and the back go to `body`."""
    eps = 1e-3

    def hint(x, y, z, n2):
        p0 = mapping(x, y, z)
        dx = sub(mapping(x + eps, y, z), p0); dy = sub(mapping(x, y + eps, z), p0)
        dz = sub(mapping(x, y, z + eps), p0)
        return norm(add(add(mul(dx, n2[0]), mul(dy, n2[1])), mul(dz, n2[2])))

    z_rim = depth * (1 - 0.18)
    z_face = depth - max(0.18 * recess * depth, 0.006)
    for outer, holes in layout:
        outer = oriented(outer, True)
        holes = [oriented(h, False) for h in holes]
        contours = [outer] + holes
        insets = [inset(cn, rim) for cn in contours]
        # walls (z 0 -> z_rim) and bevel (contour at z_rim -> inset at depth)
        for cn, ins in zip(contours, insets):
            pr = Prim()
            n = len(cn)
            for i in range(n):
                a, b = cn[i], cn[(i + 1) % n]
                e = (b[0] - a[0], b[1] - a[1])
                l = math.hypot(*e) or 1
                out2 = (e[1] / l, -e[0] / l, 0.0)  # right of the edge = outside the solid
                ia, ib = a, b
                v = [pr.add(mapping(ia[0], ia[1], 0), hint(*ia, 0, out2)),
                     pr.add(mapping(ib[0], ib[1], 0), hint(*ib, 0, out2)),
                     pr.add(mapping(ib[0], ib[1], z_rim), hint(*ib, z_rim, out2)),
                     pr.add(mapping(ia[0], ia[1], z_rim), hint(*ia, z_rim, out2))]
                pr.quad(*v)
                ja, jb = ins[i], ins[(i + 1) % n]
                bev = (out2[0] * 0.7, out2[1] * 0.7, 0.7)
                w = [pr.add(mapping(ia[0], ia[1], z_rim), hint(*ia, z_rim, bev)),
                     pr.add(mapping(ib[0], ib[1], z_rim), hint(*ib, z_rim, bev)),
                     pr.add(mapping(jb[0], jb[1], depth), hint(*jb, depth, bev)),
                     pr.add(mapping(ja[0], ja[1], depth), hint(*ja, depth, bev))]
                pr.quad(*w)
                # inner lip down to the recessed stone face
                lip = (-out2[0], -out2[1], 0.3)
                x = [pr.add(mapping(ja[0], ja[1], depth), hint(*ja, depth, lip)),
                     pr.add(mapping(jb[0], jb[1], depth), hint(*jb, depth, lip)),
                     pr.add(mapping(jb[0], jb[1], z_face), hint(*jb, z_face, lip)),
                     pr.add(mapping(ja[0], ja[1], z_face), hint(*ja, z_face, lip))]
                pr.quad(*x)
            body.put(pr, weld=False)
            # the inner lip belongs to the stone face (gives it real depth)
            lp = Prim()
            for i in range(len(ins)):
                ja, jb = ins[i], ins[(i + 1) % len(ins)]
                e = (jb[0] - ja[0], jb[1] - ja[1])
                l = math.hypot(*e) or 1
                lip = (-e[1] / l, e[0] / l, 0.3)
                lp.quad(lp.add(mapping(ja[0], ja[1], depth), hint(*ja, depth, lip)),
                        lp.add(mapping(jb[0], jb[1], depth), hint(*jb, depth, lip)),
                        lp.add(mapping(jb[0], jb[1], z_face), hint(*jb, z_face, lip)),
                        lp.add(mapping(ja[0], ja[1], z_face), hint(*ja, z_face, lip)))
            face.put(lp, weld=False)
        # stone face (inset outline) and back (full outline)
        for target, loop, z, nz in ((face, insets, z_face, 1.0), (body, contours, 0.0, -1.0)):
            if target is body and not back:
                continue
            poly = loop[0]
            for h in loop[1:]:
                poly = bridge(poly, h)
            pr = Prim()
            ids = [pr.add(mapping(p[0], p[1], z), hint(p[0], p[1], z, (0, 0, nz))) for p in poly]
            for a, b, c in earclip(poly):
                pr.f.append((ids[a], ids[b], ids[c]))
            target.put(pr)


def text_layout(rows, italic=0.16, gap=0.0):
    """rows = [(text, scale, x_offset, y_offset)] -> list of (outer, holes)
    in text units, plus the overall bounds."""
    out = []
    for text, s, x0, y0 in rows:
        x = x0
        for ch in text:
            if ch == " ":
                x += 0.32 * s
                continue
            outer, holes, w = GLYPHS[ch]
            g = s * (1.0 / 1.4 if ch == "6" and s < 0 else 1.0)

            def tf(p, x=x, g=s):
                return (x + p[0] * g + italic * p[1] * g, y0 + p[1] * g)
            out.append(([tf(p) for p in outer], [[tf(p) for p in h] for h in holes]))
            x += w * s + gap
    xs = [p[0] for o, _ in out for p in o]; ys = [p[1] for o, _ in out for p in o]
    return out, (min(xs), min(ys), max(xs), max(ys))


# ----------------------------------------------------------------- chains + pendants
def chain_path(drop=0.36, front_z=-0.6, spread=1.0):
    ctrl = [(0.0, 0.9, 0.36), (-0.3, 0.92, 0.22), (-0.42 * spread, 0.9, -0.12), (-0.33 * spread, 0.8, -0.48),
            (-0.24, 0.62, front_z), (-0.11, drop + 0.06, front_z - 0.01), (0.0, drop, front_z - 0.012),
            (0.11, drop + 0.06, front_z - 0.01), (0.24, 0.62, front_z), (0.33 * spread, 0.8, -0.48),
            (0.42 * spread, 0.9, -0.12), (0.3, 0.92, 0.22), (0.0, 0.9, 0.36)]
    return catmull(ctrl, per=10)


def build_chains():
    # heavy diamond Cuban: wide, flat, interlocking links (the stones are the pave texture)
    m = new("px_cuban_chain", "UpperTorso", "pave", "diamond Cuban link chain, heavy")
    pts, _ = resample(chain_path(0.32, -0.6, 1.0), 0.05)
    fr = frames(pts)
    for i, (p, (t, n, b)) in enumerate(zip(pts[:-1], fr)):
        up = norm(sub(p, (0.0, 0.25, 0.0)))
        flat = norm(cross(t, up))
        axis = flat if i % 2 == 0 else norm(rot_axis(flat, t, 0.75))
        w0 = cross(axis, t)
        pr = Prim()
        rows = []
        for a_i in range(8):
            a = TAU * a_i / 8
            ring = add(mul(t, math.cos(a) * 0.036), mul(w0, math.sin(a) * 0.024))
            o = norm(ring)
            centre = add(p, ring)
            row = []
            for b_i in range(5):
                bb = TAU * b_i / 5
                d = add(mul(o, math.cos(bb)), mul(axis, math.sin(bb) * 0.62))
                row.append(pr.add(add(centre, mul(d, 0.0145)), norm(add(mul(o, math.cos(bb)), mul(axis, math.sin(bb))))))
            rows.append(row)
        rows.append(rows[0])
        pr.grid(rows, True)
        m.put(pr, weld=False)

    # fine box (franco-style) chain for the silver pendant
    m = new("px_box_chain", "UpperTorso", "metal", "fine square box chain")
    base, _ = resample(chain_path(0.40, -0.6), 0.018)
    tube(m, base, 0.0105, sides=4, caps=False, twist=TAU * 26)

    # EXIT 6 pendants: "EXIT" over a big "6", bail on top
    def pendant(prefix, scale, top_y, z_back, depth, face_tex, note):
        rows = [("EXIT", 1.0, 0.0, 1.62), ("6", 1.08, 1.32, 0.0)]
        layout, (x0, y0, x1, y1) = text_layout(rows, italic=0.16)
        cx = (x0 + x1) / 2
        s = scale

        def mapping(x, y, z):
            # text right reads to the body's -X (seen from the front)
            return (-(x - cx) * s, top_y - (y1 - y) * s, z_back - z)
        face = new(prefix + "_face", "UpperTorso", face_tex, note + " (stone face)")
        body = new(prefix + "_body", "UpperTorso", "metal", note + " (metal rim, walls, bail)")
        extrude_text(face, body, layout, mapping, depth, rim=0.075, recess=0.35)
        # bail: a ring from the top of the X/I join up to the chain
        bx = -((x0 + 0.72 + 0.86 + 0.02) - cx) * s
        torus(body, (bx * 0.0, top_y + 0.035 * s / 0.139, z_back - depth * 0.5), (1.0, 0.0, 0.0),
              0.03 * s / 0.139, 0.0095 * s / 0.139, nu=14, nv=6)
    pendant("px_pendant", 0.108, 0.29, -0.62, 0.034, "pave", "EXIT 6 iced pendant")
    pendant("px_pendant_s", 0.085, 0.345, -0.618, 0.03, "metal", "EXIT 6 polished silver pendant")


def rot_axis(v, axis, a):
    return W.rot_axis(v, axis, a)


# ----------------------------------------------------------------- puffer
def build_puffer():
    # oversized, five deep horizontal baffles, flat zip placket, tall collar
    def baffle(row_h, amp, y0):
        def d(p, n):
            frac = ((p[1] - y0) / row_h) % 1.0
            bulge = math.sin(math.pi * frac) ** 0.55
            side = 1.0 if abs(n[1]) < 0.85 else 0.35
            placket = smooth(0.035, 0.11, abs(p[0])) if n[2] < -0.4 else 1.0
            return add(p, mul(n, (amp * bulge * side - 0.02) * placket))
        return d
    m = new("px_puffer_body", "UpperTorso", "nylon", "oversized quilted puffer body")
    rbox(m, (0.0, -0.22, 0.0), (1.02, 1.1, 0.565), 0.24, n=(9, 34, 6), n_r=3, disp=baffle(0.33, 0.06, -1.32),
         xform=lambda p: (p[0] * (1 + 0.03 * smooth(-0.6, -1.3, p[1])), p[1], p[2]))
    # tall puffy stand collar (zipped)
    torus(m, (0.0, 0.96, 0.0), (0.0, 1.0, 0.0), 0.44, 0.08, nu=30, nv=10, rx=0.48, rz=0.42, squash=1.55)
    torus(m, (0.0, 1.08, 0.0), (0.0, 1.0, 0.0), 0.43, 0.055, nu=30, nv=8, rx=0.465, rz=0.405, squash=1.2)

    k = new("px_puffer_knit", "UpperTorso", "knit", "elastic hem band")
    torus(k, (0.0, -1.3, 0.0), (0.0, 1.0, 0.0), 1.0, 0.045, nu=40, nv=6, rx=1.02, rz=0.57, squash=1.5)

    z = new("px_puffer_zip", "UpperTorso", "metal", "two-way front zip + pull")
    zz = -0.58
    zip_line = [(0.0, y, zz) for y in [-1.3 + 0.05 * i for i in range(46)] if y <= 0.88]
    zip_line += [(0.0, 0.93, -0.53), (0.0, 1.03, -0.51), (0.0, 1.13, -0.47)]
    tube(z, catmull(zip_line[::3] + zip_line[-3:], 3), 0.014, sides=4, caps=False)
    rbox(z, (0.0, 1.06, -0.52), (0.024, 0.05, 0.01), 0.01, n=(2, 3, 1), n_r=2)
    rbox(z, (0.0, -1.22, -0.595), (0.02, 0.04, 0.008), 0.008, n=(2, 3, 1), n_r=2)

    # charcoal hoodie hood out over the collar (the hoodie under the puffer)
    h = new("px_puffer_hood", "UpperTorso", "fleece", "hoodie hood over the collar")
    hood = catmull([(-0.44, 0.98, -0.32), (-0.54, 1.06, 0.06), (-0.34, 1.12, 0.42), (0.0, 1.14, 0.52),
                    (0.34, 1.12, 0.42), (0.54, 1.06, 0.06), (0.44, 0.98, -0.32)], per=7)
    tube(h, hood, lambda i, f: 0.085 + 0.045 * math.sin(math.pi * f), sides=12, squash=0.72)
    rbox(h, (0.0, 0.82, 0.64), (0.36, 0.3, 0.045), 0.04, n=(6, 6, 2), n_r=2,
         xform=lambda p: (p[0] * (1 - 0.25 * clamp((0.0 - p[1]) / 0.4, 0, 1)), p[1], p[2] + 0.03 * p[1]))
    for s in (-1, 1):
        cord = [(s * 0.13, 0.96, -0.55), (s * 0.15, 0.72, -0.625), (s * 0.14, 0.48, -0.635)]
        tube(h, catmull(cord, 4), 0.014, sides=5)

    # sleeves: oversized, quilted in rings
    m = new("px_puffer_upper", "UpperArm", "nylon", "puffer sleeve, upper")
    rbox(m, (0.0, 0.02, 0.0), (0.56, 0.66, 0.56), 0.22, n=(4, 24, 4), n_r=2, disp=baffle(0.27, 0.045, -0.64))
    m = new("px_puffer_lower", "LowerArm", "nylon", "puffer sleeve, lower")
    rbox(m, (0.0, 0.1, 0.0), (0.55, 0.5, 0.55), 0.21, n=(4, 16, 4), n_r=2, disp=baffle(0.25, 0.04, -0.4))
    c = new("px_puffer_cuff", "LowerArm", "knit", "elastic cuff")
    rbox(c, (0.0, -0.46, 0.0), (0.5, 0.075, 0.5), 0.12, n=(6, 2, 6), n_r=2, disp=rib(30, 0.008))


# ----------------------------------------------------------------- tracksuit
def build_tracksuit():
    m = new("px_track_jacket", "UpperTorso", "fleece", "premium track jacket body, stand collar")
    rbox(m, (0.0, -0.17, 0.0), (1.01, 1.06, 0.555), 0.16, n=(10, 12, 6), n_r=3,
         disp=lambda p, n: add(p, mul(n, 0.006 * math.sin(p[0] * 8 + p[1] * 5))),
         xform=W.flare(-0.8, -1.23, -0.035))
    torus(m, (0.0, 0.93, 0.0), (0.0, 1.0, 0.0), 0.35, 0.065, nu=24, nv=6, rx=0.39, rz=0.33, squash=2.0)
    # ribbed hem
    k = new("px_track_rib", "UpperTorso", "knit", "ribbed hem band")
    rbox(k, (0.0, -1.2, 0.0), (0.985, 0.06, 0.54), 0.06, n=(12, 2, 6), n_r=2, disp=rib(80, 0.004))

    t = new("px_track_panels", "UpperTorso", "fleece", "contrast shoulder yoke + side stripes (accent)")
    yoke = lambda p: p[1] > 0.52 and (abs(p[0]) > 0.24 or p[2] > -0.2)
    rbox(t, (0.0, -0.17, 0.0), (1.022, 1.072, 0.567), 0.16, n=(14, 24, 10), n_r=3, keep=yoke)
    for s in (-1, 1):
        for dz in (-0.075, 0.075):
            rbox(t, (s * 1.0, -0.33, dz), (0.022, 0.86, 0.028), 0.012, n=(1, 8, 1), n_r=2)
    z = new("px_track_zip", "UpperTorso", "metal", "front zip + pull")
    tube(z, [(0.0, -1.24, -0.566), (0.0, 0.0, -0.568), (0.0, 0.88, -0.56), (0.0, 1.03, -0.42)], 0.011, sides=4, caps=False)
    rbox(z, (0.0, 0.74, -0.585), (0.024, 0.05, 0.01), 0.008, n=(2, 3, 1), n_r=2)

    # EXIT 6 chest mark (wearer's left chest = -X)
    logo = new("px_track_logo", "UpperTorso", "metal", "EXIT 6 chest mark (accent)")
    layout, (x0, y0, x1, y1) = text_layout([("EXIT", 1.0, 0.0, 1.62), ("6", 1.08, 1.32, 0.0)], italic=0.16)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    s = 0.075

    def mapping(x, y, zz):
        return (-0.48 - (x - cx) * s, 0.42 + (y - cy) * s, -0.557 - zz)
    extrude_text(logo, logo, layout, mapping, 0.012, rim=0.06, recess=0.2, back=False)


# ----------------------------------------------------------------- cargo pants
def build_cargo():
    m = new("px_cargo_upper", "UpperLeg", "fleece", "baggy cargo thigh with bellows pocket + flap")
    rbox(m, (0.0, -0.02, 0.0), (0.53, 0.72, 0.52), 0.15, n=(4, 7, 4), n_r=2,
         disp=lambda p, n: add(p, mul(n, 0.012 * math.sin(p[1] * 8 + p[2] * 6) + 0.006 * math.sin(p[1] * 23))))
    rbox(m, (0.545, -0.27, 0.0), (0.05, 0.23, 0.21), 0.035, n=(2, 5, 5), n_r=2,
         disp=lambda p, n: add(p, mul(n, 0.008 * math.sin(p[1] * 30))))
    rbox(m, (0.605, -0.03, 0.0), (0.02, 0.055, 0.225), 0.018, n=(1, 2, 5), n_r=2)
    # strap hanging from the flap
    rbox(m, (0.605, -0.24, 0.1), (0.01, 0.18, 0.024), 0.008, n=(1, 4, 1), n_r=2)
    h = new("px_cargo_snaps", "UpperLeg", "metal", "flap snaps + strap D-ring")
    for dz in (-0.11, 0.11):
        cylinder(h, (0.628, -0.03, dz), (1, 0, 0), 0.02, 0.006, sides=10, bevel=0.004)
    torus(h, (0.615, -0.43, 0.1), (1.0, 0.0, 0.0), 0.025, 0.006, nu=12, nv=5)

    m = new("px_cargo_lower", "LowerLeg", "fleece", "baggy stacked cargo leg")
    rbox(m, (0.0, 0.22, 0.0), (0.52, 0.44, 0.51), 0.14, n=(4, 5, 4), n_r=2,
         disp=lambda p, n: add(p, mul(n, 0.01 * math.sin(p[1] * 13 + p[0] * 4))))
    for i, y in enumerate((-0.18, -0.3, -0.42, -0.53)):
        rbox(m, (0.0, y, 0.0), (0.535 + 0.01 * i, 0.075, 0.525 + 0.01 * i), 0.065, n=(4, 1, 4), n_r=1,
             xform=lambda p, i=i: (p[0], p[1] + 0.025 * math.sin(math.atan2(p[0], p[2]) * 2 + i * 1.7), p[2]))


# ----------------------------------------------------------------- high-tops
def build_hightops():
    # foot canonical half (0.50, 0.156, 0.50); toe at -Z
    TOP = 0.6

    def shape(p):
        drop = 0.46 * smooth(0.04, -0.54, p[2]) * smooth(-0.12, 0.4, p[1])
        narrow = 1 - 0.1 * smooth(-0.2, -0.62, p[2])
        return (p[0] * narrow, p[1] - drop, p[2])
    HX = 0.515
    C, Hh, R = (0.0, 0.215, -0.065), (HX, 0.385, 0.575), 0.15

    def upper(mesh, off, n, keep=None):
        rbox(mesh, C, Hh, R, n=n, n_r=3, disp=(lambda p, nn: add(p, mul(nn, off))) if off else None,
             xform=shape, keep=keep)

    m = new("px_hightop_base", "Foot", "leather", "high-top upper: base panels, tongue, padded collar")
    upper(m, 0.0, (5, 4, 7))
    torus(m, (0.0, TOP + 0.0, 0.16), (0.0, 1.0, 0.12), 0.38, 0.05, nu=24, nv=7, rx=0.49, rz=0.4)
    rbox(m, (0.0, TOP + 0.06, -0.1), (0.18, 0.1, 0.04), 0.035, n=(4, 3, 1), n_r=2,
         xform=lambda p: (p[0], p[1], p[2] - 0.12 * clamp(-p[1] / 0.15, -0.5, 1)))

    # overlays: mudguard + toe cap, eyestays, heel counter, collar panel
    def overlay(p):
        x, y, z = p
        mud = y < 0.03 or z < -0.5
        eyestay = y > 0.18 and 0.1 < abs(x) < 0.32 and -0.44 < z < 0.08
        heel = z > 0.28 and y < 0.44
        collar = y > TOP - 0.17 and z > -0.2
        return mud or eyestay or heel or collar
    o = new("px_hightop_overlay", "Foot", "leather", "contrast overlays (main)")
    upper(o, 0.009, (11, 9, 14), keep=overlay)

    # original EXIT 6 side mark: a hex patch on the quarter panel carrying a
    # raised "6" (deliberately not a stripe / swoosh-like sweep)
    HEX_C, HEX_R = (0.08, 0.25), 0.13

    def in_hex(z, y):
        dz, dy = abs(z - HEX_C[0]), abs(y - HEX_C[1])
        return dy <= HEX_R * 0.866 and dz <= HEX_R - dy * 0.577
    k = new("px_hightop_mark", "Foot", "leather", "hex side patch (accent)")
    upper(k, 0.016, (13, 22, 30), keep=lambda p: abs(p[0]) > 0.4 and in_hex(p[2], p[1]))
    outer6, holes6, w6 = GLYPHS["6"]
    six = [([(x - w6 / 2, y - 0.7) for x, y in outer6], [[(x - w6 / 2, y - 0.7) for x, y in h] for h in holes6])]
    for side in (1, -1):
        # readable from each side: text right runs toe-ward on +X, heel-ward on -X
        def mapping(x, y, zz, side=side):
            return (side * (HX + 0.017 + zz), HEX_C[1] + y * 0.105, HEX_C[0] - side * x * 0.105)
        extrude_text(o, o, six, mapping, 0.012, rim=0.07, recess=0.15, back=False)

    s = new("px_hightop_sole", "Foot", "rubber", "cupsole with toe bumper and sidewall groove")
    rbox(s, (0.0, -0.1, -0.065), (0.535, 0.075, 0.6), 0.05, n=(6, 2, 8), n_r=2,
         disp=lambda p, n: add(p, mul(n, -0.01 * (1 if abs(p[1] + 0.005) < 0.012 and abs(n[1]) < 0.5 else 0))),
         xform=lambda p: (p[0] * (1 - 0.08 * smooth(-0.2, -0.65, p[2])),
                          p[1] + 0.04 * smooth(-0.4, -0.68, p[2]) * smooth(-0.05, 0.07, p[1]), p[2]))

    lace = new("px_hightop_laces", "Foot", "knit", "flat laces, criss-cross")

    def top_y(z):
        return TOP - 0.46 * smooth(0.04, -0.54, z) + 0.03
    rungs = [-0.42 + 0.08 * i for i in range(7)]
    for a, b in zip(rungs, rungs[1:]):
        for sgn in (-1, 1):
            p0 = (sgn * 0.15, top_y(a) - 0.01, a)
            p1 = (-sgn * 0.15, top_y(b) - 0.01, b)
            mid = vlerp(p0, p1, 0.5)
            tube(lace, [p0, (mid[0], mid[1] + 0.015, mid[2]), p1], 0.014, sides=4, squash=0.45)
    tube(lace, catmull([(0.0, top_y(-0.42), -0.43), (0.12, top_y(-0.42) - 0.07, -0.47), (0.17, top_y(-0.42) - 0.2, -0.46)], 4),
         0.012, sides=4)


# ----------------------------------------------------------------- hair
def build_hair():
    full = hl(HL_FULL)

    # long locs, mid-back length, face-framing, a few silver loc cuffs
    r = random.Random(61)
    m = new("px_hair_long_locs", "Head", "locs", "long locs, mid-back length")
    head_cap(m, full, lambda az, v: lerp(0.022, 0.05, smooth(0, .4, v)), cols=56, rows=16, rim_r=0.013)
    cuffs = new("px_loc_cuffs", "Head", "metal", "silver loc cuffs")
    roots = scalp_roots(full, 0.045, 42, r, 0.094)
    for i, (p, n, az) in enumerate(roots):
        side = 1 if p[0] >= 0 else -1
        front = p[2] < -0.05
        sweep = (side * 0.42, 0.0, 0.42) if front else (side * 0.06, 0.0, 0.22)
        pts = strand(p, n, r.uniform(0.95, 1.3), 1.3, 0.098, sweep=sweep, brow=0.5, lift=0.25, step=0.075)
        if len(pts) < 3:
            continue
        tube(m, pts, twist_r(0.044, 2.2 + r.random(), 0.14, taper=0.12), sides=6)
        if i % 4 == 1 and len(pts) > 9:
            j = r.randint(5, len(pts) - 4)
            t = norm(sub(pts[j + 1], pts[j - 1]))
            cylinder(cuffs, pts[j], t, 0.054, 0.026, sides=10, bevel=0.008)

    # designer cornrows: S-curved rows that finish in short braids at the nape
    def surface_along(dirv, offset):
        lo, hi = 0.0, 1.6
        for _ in range(28):
            mid = (lo + hi) / 2
            if head_sdf(mul(dirv, mid)) < offset:
                lo = mid
            else:
                hi = mid
        return mul(dirv, hi)

    m = new("px_hair_designer_cornrows", "Head", "locs", "designer cornrows: S-curve rows + nape braids")
    head_cap(m, full, lambda az, v: 0.022, rim_r=0.01)
    ROWS = 10
    for i in range(ROWS):
        lam = lerp(-1.0, 1.0, i / (ROWS - 1))
        pts = []
        for kk in range(61):
            beta = lerp(-0.15, math.pi * 0.97, kk / 60)
            wave = 0.16 * math.sin(beta * 2.2) * (1 - 0.4 * abs(lam))
            dirv = norm((lam * (0.55 + 0.35 * math.sin(beta)) + wave, math.sin(beta) + 0.25, -math.cos(beta)))
            p = surface_along(dirv, 0.045)
            azp = math.atan2(p[0], -p[2])
            if p[1] >= full(azp) + 0.02:
                pts.append(p)
        if len(pts) < 4:
            continue
        pts, _ = resample(pts, 0.04)
        end = pts[-1]
        tail = [end]
        for j in range(1, 9):
            q = add(end, (lam * 0.03 * j, -0.055 * j, 0.012 * j))
            sd = head_sdf(q)
            if sd < 0.05:
                q = add(q, mul(W.head_grad(q), 0.05 - sd))
            tail.append(q)
        tube(m, pts + tail[1:], braid_r(0.041, 0.3, 2.0), sides=6)


# ----------------------------------------------------------------- jewelry
def build_studs():
    g = new("px_stud_stone", "Head", "pave", "cushion-cut diamond studs (faceted)")
    st = new("px_stud_setting", "Head", "metal", "four-prong stud settings")
    for s in (-1, 1):
        c = (s * 0.612, -0.06, 0.04)
        ax, u, w = basis((s, 0.0, 0.0))
        R, T = 0.042, 0.026

        def ring(rad, out, rot=0.0):
            pts = []
            for k in range(8):
                a = TAU * k / 8 + math.pi / 8 + rot
                # cushion: a square with softened corners
                sq = rad / max(abs(math.cos(a)), abs(math.sin(a))) ** 0.35
                pts.append(add(c, add(mul(ax, out), add(mul(u, math.cos(a) * sq), mul(w, math.sin(a) * sq)))))
            return pts
        gird = ring(R, 0.0)
        table = ring(T, 0.02)
        tip = add(c, mul(ax, -0.03))
        facet(g, table, add(c, mul(ax, -1.0)))
        for k in range(8):
            facet(g, [gird[k], gird[(k + 1) % 8], table[(k + 1) % 8], table[k]], c)
            facet(g, [gird[(k + 1) % 8], gird[k], tip], c)
        for k in range(4):
            a = TAU * k / 4 + math.pi / 4
            base = add(c, add(mul(ax, -0.017), add(mul(u, math.cos(a) * (R + 0.003)), mul(w, math.sin(a) * (R + 0.003)))))
            top = add(c, add(mul(ax, 0.015), add(mul(u, math.cos(a) * (R - 0.005)), mul(w, math.sin(a) * (R - 0.005)))))
            tube(st, [base, top], 0.0065, sides=6)
        torus(st, add(c, mul(ax, -0.018)), ax, R * 0.85, 0.0045, nu=16, nv=5)


def build_watch():
    # left wrist; dial faces out (-X). Sized to a real wrist: ~0.25-stud case
    # on a 1-stud forearm, bracelet hugging the arm.
    case = new("px_watch_case", "LeftLowerArm", "metal", "octagon case, lugs, three-row link bracelet")
    ice = new("px_watch_ice", "LeftLowerArm", "pave", "iced bezel, dial and centre links")
    hands = new("px_watch_hands", "LeftLowerArm", "metal", "baguette markers and hands")
    Y = -0.38
    RC, RD = 0.125, 0.085          # case and dial radius
    XB, XF, XT = -0.522, -0.556, -0.572   # case back, case front, bezel top

    def octo(x, rad, rot=math.pi / 8):
        return [(x, Y + math.cos(TAU * k / 8 + rot) * rad, math.sin(TAU * k / 8 + rot) * rad) for k in range(8)]
    back, front, bez_in = octo(XB, RC), octo(XF, RC), octo(XT, RD)
    cen = (-0.54, Y, 0.0)
    for k in range(8):
        j = (k + 1) % 8
        facet(case, [back[k], back[j], front[j], front[k]], cen)
    bez_top = octo(XT, RC - 0.006)
    for k in range(8):
        j = (k + 1) % 8
        facet(case, [front[k], front[j], bez_top[j], bez_top[k]], cen)
    facet(case, list(reversed(back)), (0.0, Y, 0.0))
    # iced bezel ring and pave dial
    for k in range(8):
        j = (k + 1) % 8
        facet(ice, [bez_top[k], bez_top[j], bez_in[j], bez_in[k]], add(cen, (0.3, 0, 0)))
    dial = octo(XT + 0.005, RD)
    facet(ice, dial, (0.0, Y, 0.0))
    # markers and hands, raised off the dial
    XM = XT + 0.001
    for k in range(12):
        a = TAU * k / 12
        L = 0.018 if k % 3 == 0 else 0.011
        r0 = RD * 0.75
        cy, cz = Y + math.cos(a) * r0, math.sin(a) * r0
        tube(hands, [(XM, cy, cz), (XM, Y + math.cos(a) * (r0 - L), math.sin(a) * (r0 - L))],
             0.0045, sides=4)
    tube(hands, [(XM - 0.003, Y, 0.0), (XM - 0.003, Y + 0.045, 0.018)], 0.004, sides=4)
    tube(hands, [(XM - 0.005, Y, 0.0), (XM - 0.005, Y - 0.018, -0.06)], 0.003, sides=4)
    cylinder(hands, (XM - 0.004, Y, 0.0), (1, 0, 0), 0.008, 0.003, sides=8)
    # bracelet: three rows of links round the wrist, skipping under the case
    N = 30
    for k in range(N):
        a = TAU * k / N
        if abs(abs(math.atan2(math.sin(a), math.cos(a))) - math.pi) < 0.26:
            continue
        s_, c_ = math.sin(a), math.cos(a)
        rad = 0.515 / (abs(s_) ** 4 + abs(c_) ** 4) ** 0.25
        centre = (rad * c_ * 1.0, Y, rad * s_)
        out = norm((c_, 0.0, s_))
        tang = (-s_, 0.0, c_)
        for row, (dy, target, hw) in enumerate(((-0.04, case, 0.018), (0.0, ice, 0.019), (0.04, case, 0.018))):
            p0 = add(centre, (0.0, dy, 0.0))
            # a link = small box: tangent x radial x vertical
            corners = []
            for sy in (-1, 1):
                for st_ in (-1, 1):
                    for so in (-1, 1):
                        corners.append(add(p0, add(add(mul(tang, st_ * 0.05), mul((0, 1, 0), sy * hw)), mul(out, so * 0.012))))
            def C(sy, st_, so):
                return corners[((sy + 1) // 2) * 4 + ((st_ + 1) // 2) * 2 + (so + 1) // 2]
            faces = [[C(-1, -1, 1), C(-1, 1, 1), C(1, 1, 1), C(1, -1, 1)],
                     [C(-1, -1, -1), C(1, -1, -1), C(1, 1, -1), C(-1, 1, -1)],
                     [C(1, -1, -1), C(1, -1, 1), C(1, 1, 1), C(1, 1, -1)],
                     [C(-1, -1, -1), C(-1, 1, -1), C(-1, 1, 1), C(-1, -1, 1)],
                     [C(-1, 1, -1), C(1, 1, -1), C(1, 1, 1), C(-1, 1, 1)],
                     [C(-1, -1, -1), C(-1, -1, 1), C(1, -1, 1), C(1, -1, -1)]]
            for f in faces:
                facet(target, f, p0)
    # lugs joining case and bracelet
    for dz in (-1, 1):
        for dy in (-1, 1):
            rbox(case, (-0.53, Y + dy * 0.038, dz * RC), (0.016, 0.016, 0.03), 0.008, n=(1, 1, 2), n_r=2)


def build_cap():
    # structured six-panel fitted with a flat brim and a raised EXIT 6 wordmark
    cap_low = lambda az: lerp(0.24, 0.12, smooth(30, 120, abs(math.degrees(az))))

    def crown_t(az, v):
        return 0.085 + 0.03 * math.sin(math.pi * clamp(v * 1.2, 0, 1)) + 0.045 * smooth(0.5, 1.0, v)
    m = new("px_cap_crown", "Head", "knit", "structured fitted crown, panel seams, flat brim")
    head_cap(m, cap_low, crown_t, rows=18, cols=64, rim_r=0.03)
    for k in range(6):
        az = TAU * k / 6 - math.pi
        pts = []
        for j in range(15):
            v = j / 14
            l0 = ell_at_y(az, cap_low(az)); l1 = head_len(az)[2]
            p, n = head_point(az, lerp(l0, l1, v), crown_t(az, v) + 0.006)
            pts.append(p)
        tube(m, pts, 0.008, sides=4)
    cylinder(m, (0.0, HY + 0.135, 0.0), (0, 1, 0), 0.05, 0.015, sides=12, bevel=0.01)
    rbox(m, (0.0, 0.2, -0.79), (0.45, 0.018, 0.245), 0.016, n=(8, 1, 5), n_r=2,
         xform=lambda p: (p[0] * (1 - 0.15 * smooth(-0.78, -1.03, p[2])), p[1], p[2]))

    w = new("px_cap_wordmark", "Head", "knit", "raised EXIT 6 embroidery (accent)")
    layout, (x0, y0, x1, y1) = text_layout([("EXIT 6", 1.0, 0.0, 0.0)], italic=0.16)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    s = 0.13

    def mapping(x, y, z):
        # wrap the text round the crown front
        az = -(x - cx) * s / 0.62
        yy = 0.44 + (y - cy) * s
        l0 = ell_at_y(az, cap_low(az)); l1 = head_len(az)[2]
        ell = ell_at_y(az, yy)
        v = clamp((ell - l0) / (l1 - l0), 0, 1)
        p, n = head_point(az, ell, crown_t(az, v) + 0.004 + z)
        return p
    extrude_text(w, w, layout, mapping, 0.016, rim=0.07, recess=0.1, back=False)


# ----------------------------------------------------------------- export
def charts(m):
    """Per-face box charts: each triangle projects along its dominant axis;
    vertices are split per chart so nothing smears across a seam."""
    nrm = m.normals()
    dens = TEX_DENSITY[m.tex]
    remap = {}
    v, n, uv, f = [], [], [], []
    for a, b, c in m.f:
        fn = cross(sub(m.v[b], m.v[a]), sub(m.v[c], m.v[a]))
        ax = max(range(3), key=lambda i: abs(fn[i]))
        sgn = 1 if fn[ax] >= 0 else -1
        tri = []
        for i in (a, b, c):
            key = (i, ax, sgn)
            if key not in remap:
                p = m.v[i]
                if ax == 0:
                    u_, v_ = -sgn * p[2], p[1]
                elif ax == 1:
                    u_, v_ = p[0], -sgn * p[2]
                else:
                    u_, v_ = sgn * p[0], p[1]
                remap[key] = len(v)
                v.append(p); n.append(nrm[i]); uv.append((u_ * dens, -v_ * dens))
            tri.append(remap[key])
        f.append(tuple(tri))
    return v, n, uv, f


def tangents(v, n, uv, f):
    acc = [[0.0, 0.0, 0.0] for _ in v]
    bacc = [[0.0, 0.0, 0.0] for _ in v]
    for a, b, c in f:
        e1, e2 = sub(v[b], v[a]), sub(v[c], v[a])
        du1, dv1 = uv[b][0] - uv[a][0], uv[b][1] - uv[a][1]
        du2, dv2 = uv[c][0] - uv[a][0], uv[c][1] - uv[a][1]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            continue
        r = 1.0 / det
        t = mul(sub(mul(e1, dv2), mul(e2, dv1)), r)
        bt = mul(sub(mul(e2, du1), mul(e1, du2)), r)
        for i in (a, b, c):
            for k in range(3):
                acc[i][k] += t[k]; bacc[i][k] += bt[k]
    out = []
    for i, nn in enumerate(n):
        t = tuple(acc[i])
        t = sub(t, mul(nn, dot(nn, t)))
        if length(t) < 1e-9:
            t = norm(cross(nn, (0.0, 1.0, 0.0) if abs(nn[1]) < 0.9 else (1.0, 0.0, 0.0)))
        t = norm(t)
        w = -1.0 if dot(cross(nn, t), tuple(bacc[i])) < 0 else 1.0
        out.append((t[0], t[1], t[2], w))
    return out


def write_glb(meshes, path):
    binbuf = bytearray()
    accessors, views, gl_meshes, nodes, materials = [], [], [], [], []

    def view(data, target):
        off = len(binbuf)
        binbuf.extend(data)
        while len(binbuf) % 4:
            binbuf.append(0)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(views) - 1

    for m in meshes:
        v, n, uv, f = charts(m)
        tg = tangents(v, n, uv, f)
        pos = b"".join(struct.pack("<3f", *p) for p in v)
        nb = b"".join(struct.pack("<3f", *q) for q in n)
        ub = b"".join(struct.pack("<2f", *q) for q in uv)
        tb = b"".join(struct.pack("<4f", *q) for q in tg)
        ib = b"".join(struct.pack("<3I", *q) for q in f)
        xs = [p[0] for p in v]; ys = [p[1] for p in v]; zs = [p[2] for p in v]
        a0 = len(accessors)
        accessors += [
            {"bufferView": view(pos, 34962), "componentType": 5126, "count": len(v), "type": "VEC3",
             "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
            {"bufferView": view(nb, 34962), "componentType": 5126, "count": len(v), "type": "VEC3"},
            {"bufferView": view(ub, 34962), "componentType": 5126, "count": len(v), "type": "VEC2"},
            {"bufferView": view(tb, 34962), "componentType": 5126, "count": len(v), "type": "VEC4"},
            {"bufferView": view(ib, 34963), "componentType": 5125, "count": len(f) * 3, "type": "SCALAR"},
        ]
        materials.append({"name": m.name, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                                     "metallicFactor": 0, "roughnessFactor": 1}})
        gl_meshes.append({"name": m.name, "primitives": [{"attributes": {
            "POSITION": a0, "NORMAL": a0 + 1, "TEXCOORD_0": a0 + 2, "TANGENT": a0 + 3},
            "indices": a0 + 4, "material": len(materials) - 1}]})
        nodes.append({"name": m.name, "mesh": len(gl_meshes) - 1})
    gltf = {"asset": {"version": "2.0", "generator": "exit6 build_premium.py"},
            "scene": 0, "scenes": [{"name": "Exit6Premium", "nodes": list(range(len(nodes)))}],
            "nodes": nodes, "meshes": gl_meshes, "materials": materials,
            "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(binbuf)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    with path.open("wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binbuf)))
        fh.write(struct.pack("<II", len(js), 0x4E4F534A)); fh.write(js)
        fh.write(struct.pack("<II", len(binbuf), 0x004E4942)); fh.write(binbuf)


def build_all():
    MESHES.clear()
    build_chains()
    build_puffer()
    build_tracksuit()
    build_cargo()
    build_hightops()
    build_hair()
    build_studs()
    build_watch()
    build_cap()
    for m in MESHES:
        # clipped shells leave unreferenced vertices; they must not count in the bounds
        used = sorted({i for f in m.f for i in f})
        remap = {old: new_i for new_i, old in enumerate(used)}
        m.v = [m.v[i] for i in used]
        m.f = [tuple(remap[i] for i in f) for f in m.f]
    return MESHES


def main():
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--patch="):
            only = a.split("=", 1)[1].split(",")
    build_all()
    names = [m.name for m in MESHES]
    assert len(names) == len(set(names)), "duplicate mesh names"
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    lines = [
        "-- GENERATED by tools/assets/build_premium.py - do not edit by hand.",
        "-- Fit data for the EXIT 6 Premium meshes (same format as Exit6WearMeshes:",
        "-- authored on one canonical R15 part; size + centre in that part's space).",
        "-- tex = the SurfaceAppearance set the mesh's UVs are scaled for.",
        "-- Templates: ServerStorage.Exit6ProductionAssets.Wear.<name>",
        "local M = {}",
        "M.Meshes = {",
    ]
    for m in MESHES:
        lo, hi = m.bounds()
        size = tuple(hi[i] - lo[i] for i in range(3))
        ctr = tuple((hi[i] + lo[i]) / 2 for i in range(3))
        tris = len(m.f)
        assert tris < TRI_LIMIT, f"{m.name}: {tris} triangles over the limit"
        assert tris > 0, f"{m.name}: empty"
        manifest.append({"name": m.name, "part": m.part, "tex": m.tex, "triangles": tris, "vertices": len(m.v),
                         "size": [round(x, 4) for x in size], "center": [round(x, 4) for x in ctr], "note": m.note})
        lines.append(f'\t{m.name} = {{ part = "{m.part}", tex = "{m.tex}", tris = {tris}, '
                     f"size = Vector3.new({size[0]:.4f}, {size[1]:.4f}, {size[2]:.4f}), "
                     f"center = Vector3.new({ctr[0]:.4f}, {ctr[1]:.4f}, {ctr[2]:.4f}) }},")
    lines += ["}", "return M", ""]
    write_glb(MESHES, OUT / "exit6_premium.glb")
    if only:
        sel = [m for m in MESHES if m.name in only]
        assert len(sel) == len(only), "unknown mesh in --patch"
        write_glb(sel, OUT / "exit6_premium_patch.glb")
        print("patch glb:", ", ".join(m.name for m in sel))
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    LUAU.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    for e in manifest:
        print(f"{e['name']:28s} {e['part']:13s} {e['tex']:8s} {e['triangles']:6d} tris  size {e['size']}")
    total = sum(e["triangles"] for e in manifest)
    print(f"{len(manifest)} meshes, {total} triangles, glb {(OUT / 'exit6_premium.glb').stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
