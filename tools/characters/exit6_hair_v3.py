"""Two-strand twists for the Exit 6 male, V3: thinner, fewer, separated twists.

V2's twists (exit6_hair_v2.py) read as oversized and crowded. V3 keeps the V2
growth / mesh code and changes the parameters it runs with, plus the goatee
(a tapered shell that follows the chin instead of V2's flat plate).
"""
import math
import numpy as np
import exit6_hair_v2 as H2
from exit6_hair_v2 import surface, norm   # noqa: F401
import exit6_male_spec as S

SOLE = S.SOLE

TUNE = {}


def apply_tune(**kw):
    TUNE.update(kw)
    for k, v in kw.items():
        setattr(H2, k, v)


def build(bvh, seed=7):
    return H2.build(bvh, seed)


def goatee(bvh):
    return H2.goatee(bvh)


# ------------------------------------------------------------------ goatee
# traced off 10x zooms of the reference (front face centre x = 170.3; side x - 700 = Y)
# front: a narrow soul patch from row 319.5 opens into a wide chin patch (+-17.5 px at
# row 327-328) whose lower edge runs as a V to row 336 and wraps under the chin
G_TOP_X = [0.0, 2.0, 3.5, 5.0, 8.0, 12.0, 16.0, 17.5, 30.0]
G_TOP = [319.5, 321.0, 322.5, 324.0, 325.0, 325.8, 326.6, 327.5, 340.0]
G_W_ROW = [319.0, 322.0, 324.0, 325.5, 327.0, 328.5, 331.0, 334.0, 337.0, 341.0, 346.0]
G_W = [0.6, 2.8, 4.5, 12.0, 17.0, 17.5, 16.0, 13.0, 10.0, 6.0, 0.0]
# side: back edge of the beard on the chin / under the jaw (row -> Y)
G_BACK_ROW = [318.0, 322.0, 326.0, 330.0, 334.0, 338.0, 342.0]
G_BACK = [-55.0, -50.0, -40.0, -32.0, -31.0, -33.0, -36.0]
G_THICK = 2.6          # px at the middle of the chin patch
G_SOUL_THICK = 1.3     # px on the soul patch
G_EDGE = 2.2           # px over which the shell tapers to the skin
LAST = {}


def goatee(bvh, seed=3):
    """tapered shell following the chin: thick in the middle, meeting the skin at a soft edge"""
    rng = np.random.default_rng(seed)
    C = np.array([0.0, -26.0, SOLE - 322.0])
    angs = np.radians(np.linspace(-35, 100, 230))
    xs = np.linspace(-21, 21, 170)
    E = np.zeros((len(angs), len(xs))); G = np.zeros((len(angs), len(xs), 3))
    for i, a in enumerate(angs):
        d = np.array([0, -math.cos(a), -math.sin(a)])
        for j, x in enumerate(xs):
            p, n = surface(bvh, C + np.array([x, 0, 0]) + d * 90, -d)
            if p is None:
                continue
            row = SOLE - p[2]
            ax = abs(p[0])
            m1 = row - np.interp(ax, G_TOP_X, G_TOP)
            m2 = np.interp(row, G_W_ROW, G_W) - ax
            m3 = np.interp(row, G_BACK_ROW, G_BACK) - p[1]
            e = np.clip(min(m1, m2, m3) / G_EDGE, 0, 1)
            E[i, j] = e
            if e <= 0:
                continue
            soul = np.clip((325.5 - row) / 1.5, 0, 1)
            t = (G_THICK * (1 - soul) + G_SOUL_THICK * soul) * e ** 0.6
            G[i, j] = p + n * (0.12 + t + rng.normal(0, 0.12) * e)
    verts, faces, ev = [], [], []
    idx = -np.ones(E.shape, int)
    # keep a one-sample rim at e = 0 so the shell closes onto the skin
    keep = E > 0
    rim = np.zeros_like(keep)
    rim[1:] |= keep[:-1]; rim[:-1] |= keep[1:]; rim[:, 1:] |= keep[:, :-1]; rim[:, :-1] |= keep[:, 1:]
    rim &= ~keep
    for i in range(E.shape[0]):
        for j in range(E.shape[1]):
            if keep[i, j] or rim[i, j]:
                if not keep[i, j]:
                    a = angs[i]; d = np.array([0, -math.cos(a), -math.sin(a)])
                    p, n = surface(bvh, C + np.array([xs[j], 0, 0]) + d * 90, -d)
                    if p is None:
                        continue
                    G[i, j] = p + n * 0.05
                idx[i, j] = len(verts); verts.append(G[i, j]); ev.append(E[i, j])
    for i in range(E.shape[0] - 1):
        for j in range(E.shape[1] - 1):
            a, b, c, d = idx[i, j], idx[i, j + 1], idx[i + 1, j + 1], idx[i + 1, j]
            if min(a, b, c, d) >= 0:
                faces.append([a, b, c, d])
    LAST["edge"] = np.array(ev)
    return np.array(verts), faces, G_THICK


def goatee_material(ob):
    """near-black short hair: noise bump for texture, alpha fades over the outer edge"""
    import bpy
    me = ob.data
    at = me.attributes.new("edge", "FLOAT", "POINT")
    at.data.foreach_set("value", LAST["edge"].astype(np.float32))
    m = bpy.data.materials.new("M_Exit6_Goatee")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (0.012, 0.010, 0.009, 1)
    p.inputs["Roughness"].default_value = 0.8
    a = nt.nodes.new("ShaderNodeAttribute"); a.attribute_name = "edge"
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 900.0
    nz.inputs["Detail"].default_value = 4.0
    add = nt.nodes.new("ShaderNodeMath"); add.operation = "ADD"
    mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 0.6
    nt.links.new(nz.outputs["Fac"], mul.inputs[0])
    nt.links.new(a.outputs["Fac"], add.inputs[0]); nt.links.new(mul.outputs[0], add.inputs[1])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = 0.35; ramp.inputs["From Max"].default_value = 0.75
    nt.links.new(add.outputs[0], ramp.inputs["Value"])
    nt.links.new(ramp.outputs["Result"], p.inputs["Alpha"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.6
    nt.links.new(nz.outputs["Fac"], bump.inputs["Height"]); nt.links.new(bump.outputs["Normal"], p.inputs["Normal"])
    me.materials.clear(); me.materials.append(m)
    return m


# ------------------------------------------------------------ twists, V3
# crown twists lift off the scalp before they fall (reference: rounded volume above the skull)
GRAV_TOP = 0.03        # gravity per step for roots high on the crown (V2: 0.06)
GRAV_SIDE = 0.075
LIFT = 0.35            # extra push along the scalp normal at the root for crown twists
STRAND_OFF = 0.34      # render twist: strand offset / R_TWIST
STRAND_R = 0.70        # render twist: strand radius / R_TWIST (chunky round beads)
BEAD_SWELL = 0.06
SIDE_FLARE = 0.4      # extra outward push for side roots


def grow3(bvh, p, n, rng):
    phi = H2.phi_of(p)
    elev = (p[2] - H2.HEAD_C[2]) / 53.0
    down = np.array([0, 0, -1.0]); fwd = np.array([0, -1.0, 0])
    side = np.array([np.sign(p[0]), 0, 0])
    a = abs(phi)
    if a < 0.7:
        d0 = H2.norm(0.7 * n + 0.3 * fwd + 0.55 * side)
    elif a < 2.0:
        d0 = H2.norm(0.8 * n + (0.2 + SIDE_FLARE) * side)
    else:
        d0 = H2.norm(0.85 * n + 0.15 * np.array([0, 1.0, 0]))
    top = np.clip((elev - 0.3) / 0.4, 0, 1)
    d0 = H2.norm(d0 + n * LIFT * top + rng.normal(0, 0.08, 3))
    target = H2.tip_row(phi, elev) + rng.uniform(-4, 4)
    pts = [p - n * 1.5, p.copy()]
    q = p + n * 1.0
    d = d0
    margin = H2.R_TWIST + 0.6
    total = 0
    grav = GRAV_SIDE + (GRAV_TOP - GRAV_SIDE) * top + 0.03 * rng.random()
    while SOLE - q[2] < target and total < 110:
        d = H2.norm(d + down * grav)
        q = q + d * H2.STEP
        hit = bvh.find_nearest(H2.Vector(q))
        if hit[0] is not None:
            h = np.array(hit[0])
            dist = np.linalg.norm(q - h)
            inside = (q - h) @ np.array(hit[1]) < 0
            if inside or dist < margin:
                outn = np.array(hit[1]) if not inside else -H2.norm(q - h) if dist > 1e-6 else np.array(hit[1])
                outn = H2.norm(outn if outn @ (q - H2.HEAD_C) > 0 else -outn)
                q = h + outn * margin
                d = H2.norm(d - (d @ outn) * outn)
        pts.append(q.copy())
        total += H2.STEP
    return np.array(pts)


def render_twist3(pts, rng):
    C = H2.smooth_path(pts, 0.55)
    T, A1, A2 = H2.frames(C)
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    L = s[-1]
    taper = 1.0 - 0.12 * (s / L)
    ph0 = rng.uniform(0, 2 * np.pi)
    out_v, out_f = [], []
    R = H2.R_TWIST
    for strand in (0, 1):
        ang = 2 * np.pi * s / (2 * H2.PITCH) + strand * np.pi + ph0
        off = STRAND_OFF * R * taper
        Cs = C + off[:, None] * (np.cos(ang)[:, None] * A1 + np.sin(ang)[:, None] * A2)
        Ts, A1s, A2s = H2.frames(Cs)
        r = STRAND_R * R * taper * (1 + BEAD_SWELL * np.cos(2 * np.pi * s / H2.PITCH * 2 + ph0))
        v, f = H2.tube(Cs, A1s, A2s, Ts, r, 10)
        base = sum(len(x) for x in out_v)
        out_v.append(v); out_f += [[i + base for i in ff] for ff in f]
    return np.vstack(out_v), out_f


H2.grow = grow3
H2.render_twist = render_twist3


def recolor_scalp(ob, roots, hair_srgb, part_srgb=(48, 30, 20), centre_srgb=(118, 72, 46)):
    """dark scalp, faint box parts, a clear centre part (reference)"""
    import build_exit6_male as B
    me = ob.data
    P = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    rp = np.array([p for p, _ in roots])
    d = np.linalg.norm(P[:, None, :] - rp[None, :, :], axis=2); d.sort(1)
    part = np.clip(1 - (d[:, 1] - d[:, 0]) / 1.2, 0, 1)
    col = np.tile(B.srgb_lin(hair_srgb), (len(P), 1))
    col = col * (1 - part[:, None]) + B.srgb_lin(part_srgb) * part[:, None]
    cen = np.clip(1 - np.abs(P[:, 0]) / 1.1, 0, 1) * (P[:, 1] < 20)
    col = col * (1 - cen[:, None]) + B.srgb_lin(centre_srgb) * cen[:, None]
    B.set_colors(ob, col)


TIP = {"ang": [0.0, 0.45, 0.8, 1.2, 1.7, 2.2, math.pi], "rows": [258, 263, 280, 294, 300, 316, 328]}


def tip_row3(phi, elev):
    return float(np.interp(abs(phi), TIP["ang"], TIP["rows"]))


H2.tip_row = tip_row3
