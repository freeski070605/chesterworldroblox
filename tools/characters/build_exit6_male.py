"""Build the Exit 6 male base character in Blender from the measured reference.

Run headless:
    blender -b --factory-startup -P tools/characters/build_exit6_male.py -- [--no-render] [--voxel=0.85]

Pipeline
  1. Loft anatomical shells (torso, neck, head, ears, arms, palms, legs, feet)
     from the silhouette tables in exit6_male_spec.py, with muscle relief and
     facial features applied as analytic displacement. Every shell carries
     analytic R15 skin weights.
  2. Fuse the shells with a voxel remesh, smooth, and transfer the weights.
  3. Add fingers/toes (kept as separate clean shells), eyes, brows, goatee,
     scalp cap, two-strand twists and boxer briefs.
  4. Materials, R15 armature, armature modifiers, a pose-test action.
  5. Scale reference pixels to studs, render the four comparison views, save.
"""
import bpy, bmesh, math, os, sys, time, json
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib, exit6_male_spec as S
importlib.reload(S)

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "characters", "exit6_male")
REN_DIR = os.path.join(OUT_DIR, "renders")
os.makedirs(REN_DIR, exist_ok=True)

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {"render": True, "voxel": 0.85, "samples": 96, "poses": True}
for a in ARGV:
    if a == "--no-render": OPT["render"] = False
    if a == "--no-poses": OPT["poses"] = False
    if a.startswith("--voxel="): OPT["voxel"] = float(a.split("=")[1])
    if a.startswith("--samples="): OPT["samples"] = int(a.split("=")[1])

SOLE, CX, CS = S.SOLE, S.CX, S.CS
K = S.HEIGHT_STUDS / (S.SOLE - S.SKULL_TOP)   # studs per reference pixel
T0 = time.time()


def log(*a):
    print("[exit6 %6.1fs]" % (time.time() - T0), *a, flush=True)


# ------------------------------------------------------------------ math
def V(xf, xs, y):
    return np.array([xf - CX, xs - CS, SOLE - y], float)


def norm(a, axis=-1):
    n = np.linalg.norm(a, axis=axis, keepdims=True)
    return a / np.maximum(n, 1e-9)


def sstep(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def smooth_interp(xk, yk, xq):
    """Monotone cubic (Fritsch-Carlson) interpolation, clamped at the ends."""
    xk = np.asarray(xk, float); yk = np.asarray(yk, float); xq = np.asarray(xq, float)
    o = np.argsort(xk); xk = xk[o]; yk = yk[o]
    n = len(xk)
    h = np.diff(xk); d = np.diff(yk) / h
    m = np.zeros(n)
    m[1:-1] = (d[:-1] + d[1:]) / 2
    m[0], m[-1] = d[0], d[-1]
    for i in range(n - 1):
        if d[i] == 0:
            m[i] = m[i + 1] = 0
        else:
            a, b = m[i] / d[i], m[i + 1] / d[i]
            if a < 0: m[i] = 0
            if b < 0: m[i + 1] = 0
            s = a * a + b * b
            if s > 9:
                t = 3 / math.sqrt(s); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i]
    xc = np.clip(xq, xk[0], xk[-1])
    i = np.clip(np.searchsorted(xk, xc) - 1, 0, n - 2)
    t = (xc - xk[i]) / h[i]
    h00 = 2 * t ** 3 - 3 * t ** 2 + 1; h10 = t ** 3 - 2 * t ** 2 + t
    h01 = -2 * t ** 3 + 3 * t ** 2; h11 = t ** 3 - t ** 2
    return h00 * yk[i] + h10 * h[i] * m[i] + h01 * yk[i + 1] + h11 * h[i] * m[i + 1]


def col_interp(tab, col, xq):
    tab = np.asarray(tab, float)
    return smooth_interp(tab[:, 0], tab[:, col], xq)


def se_pow(v, n):
    return np.sign(v) * np.abs(v) ** (2.0 / n)


def gauss(x, y, cx, cy, sx, sy_up, sy_dn=None):
    """y is an image row: sy_up applies above the centre (smaller y)."""
    sy_dn = sy_up if sy_dn is None else sy_dn
    dy = y - cy
    sy = np.where(dy < 0, sy_up, sy_dn)
    return np.exp(-0.5 * ((x - cx) / sx) ** 2 - 0.5 * (dy / sy) ** 2)


def seg_line(x, y, x0, y0, x1, y1, w):
    px, py = x - x0, y - y0
    vx, vy = x1 - x0, y1 - y0
    t = np.clip((px * vx + py * vy) / (vx * vx + vy * vy), 0, 1)
    d = np.hypot(px - t * vx, py - t * vy)
    return np.exp(-(d / w) ** 2)


def catmull(ctrl, per=40):
    P = np.asarray(ctrl, float)
    P = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
    out = []
    t = np.linspace(0, 1, per, endpoint=False)[:, None]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        out.append(0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2][None])
    return np.vstack(out)


def resample(path, step):
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(s[-1] / step) + 1)
    sq = np.linspace(0, s[-1], n)
    return np.stack([np.interp(sq, s, path[:, k]) for k in range(3)], 1), sq / max(s[-1], 1e-9)


def tangents(P):
    return norm(np.gradient(P, axis=0))


# ------------------------------------------------------------ mesh data
class Shell:
    def __init__(self, name, verts, faces, weights, remesh=True, kind="skin"):
        self.name, self.verts, self.faces = name, np.asarray(verts, float), faces
        self.weights, self.remesh, self.kind = weights, remesh, kind


def rings_mesh(rings, cap0=True, cap1=True):
    rings = np.asarray(rings, float)
    R, N, _ = rings.shape
    verts = rings.reshape(-1, 3)
    i = np.arange(R - 1)[:, None]; j = np.arange(N)[None, :]
    a = i * N + j; b = i * N + (j + 1) % N; c = (i + 1) * N + (j + 1) % N; d = (i + 1) * N + j
    faces = np.stack([a, b, c, d], -1).reshape(-1, 4).tolist()
    extra = []
    if cap0:
        ci = len(verts); extra.append(rings[0].mean(0))
        faces += [[ci, (k + 1) % N, k] for k in range(N)]
    if cap1:
        ci = len(verts) + len(extra); extra.append(rings[-1].mean(0)); base = (R - 1) * N
        faces += [[ci, base + k, base + (k + 1) % N] for k in range(N)]
    if extra:
        verts = np.vstack([verts, np.array(extra)])
    return verts, faces


BONES = ["LowerTorso", "UpperTorso", "Head",
         "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
         "RightUpperLeg", "RightLowerLeg", "RightFoot"]
BI = {b: i for i, b in enumerate(BONES)}


def wmat(n):
    return np.zeros((n, len(BONES)))


def mirror_shell(sh, name):
    v = sh.verts.copy(); v[:, 0] *= -1
    faces = [list(reversed(f)) for f in sh.faces]
    W = np.zeros_like(sh.weights)
    for b, i in BI.items():
        if b.startswith("Right"):
            W[:, BI["Left" + b[5:]]] = sh.weights[:, i]
        elif b.startswith("Left"):
            W[:, BI["Right" + b[4:]]] = sh.weights[:, i]
        else:
            W[:, i] = sh.weights[:, i]
    return Shell(name, v, faces, W, sh.remesh, sh.kind)


# ---------------------------------------------------------- slice lofts
def slice_rings(tab, step, n_around, se_front, se_back, mid_frac, feature_fn=None):
    tab = np.asarray(tab, float)
    ys = np.arange(tab[0, 0], tab[-1, 0] + 1e-6, step)
    hw = col_interp(tab, 1, ys); fr = col_interp(tab, 2, ys); bk = col_interp(tab, 3, ys)
    Yf = fr - CS; Yb = bk - CS; ym = Yf + mid_frac * (Yb - Yf)
    th = np.linspace(0, 2 * np.pi, n_around, endpoint=False)
    c, s = np.cos(th)[None, :], np.sin(th)[None, :]
    exf, exb = 2.0 / se_front, 2.0 / se_back
    ex = np.where(s < 0, exf, exb)
    X = hw[:, None] * np.sign(c) * np.abs(c) ** ex
    Y = ym[:, None] + np.where(s < 0, np.abs(s) ** exf * (Yf - ym)[:, None],
                               np.abs(s) ** exb * (Yb - ym)[:, None])
    Z = np.broadcast_to((SOLE - ys)[:, None], X.shape).copy()
    if feature_fn is not None:
        X, Y, Z = feature_fn(X, Y, Z, ys[:, None], np.broadcast_to(s, X.shape),
                             np.broadcast_to(c, X.shape), ym[:, None])
    return np.stack([X, Y, Z], -1)


def radial_push(X, Y, ym, d):
    nx, ny = X, Y - ym
    L = np.maximum(np.hypot(nx, ny), 1e-6)
    return X + d * nx / L, Y + d * ny / L


# ---- torso relief
def torso_front(x, y):
    ax = np.abs(x)
    dy = y - 452
    r2 = ((ax - 40) / 30) ** 2 + (dy / np.where(dy < 0, 30, 19)) ** 2
    d = 9.0 * np.exp(-r2 ** 2) + 2.0 * gauss(ax, y, 40, 452, 26, 22, 6.0)   # pectorals
    d -= 2.2 * seg_line(ax, y, 4, 481, 62, 471, 2.6)                # under-pec fold
    d += 1.1 * gauss(ax, y, 46, 462, 2.4, 2.4)                      # nipples
    d -= 2.0 * seg_line(ax, y, 0, 428, 0, 478, 3.5)                 # sternal cleft
    d -= 1.8 * seg_line(ax, y, 0, 486, 0, 590, 2.8)                 # linea alba
    for yy, hw in ((509, 24), (534, 26), (559, 27)):
        d -= 1.5 * seg_line(ax, y, 2, yy, hw, yy - 1.5, 2.6)        # tendinous inscriptions
    d -= 2.0 * seg_line(ax, y, 31, 490, 33, 596, 3.6)              # linea semilunaris
    for yy, a in ((496, 3.0), (521, 3.8), (546, 3.8), (576, 3.0)):
        d += a * gauss(ax, y, 15, yy, 9.0, 9.5, 9.5)                # ab blocks
    d -= 3.0 * gauss(ax, y, 0, 566, 2.4, 2.4)                       # navel
    d -= 2.4 * seg_line(ax, y, 42, 586, 17, 640, 3.6)              # inguinal V-line
    d += 2.2 * gauss(ax, y, 52, 562, 9, 28)                         # obliques
    d += 0.8 * seg_line(ax, y, 8, 388, 56, 393, 4.0)               # clavicles
    return 1.3 * d


def torso_back(x, y):
    return 1.3 * _torso_back(x, y)


def _torso_back(x, y):
    ax = np.abs(x)
    d = -3.0 * seg_line(ax, y, 0, 395, 0, 640, 3.0)                 # spine
    d += 4.0 * gauss(ax, y, 36, 445, 18, 22, 20)                    # scapulae
    d += 3.0 * gauss(ax, y, 0, 395, 42, 18, 26)                     # trapezius
    d += 3.0 * gauss(ax, y, 12, 578, 7, 28)                         # erectors
    return d


def torso_side(x, y):
    ax = np.abs(x)
    d = 0.0
    for yy in (478, 494, 510):
        d = d + 1.2 * gauss(ax, y, 64, yy, 6, 4)                    # serratus
    return d


def torso_features(X, Y, Z, ys, s, c, ym):
    y = SOLE - Z
    wf = np.clip(-s, 0, 1) ** 0.7
    wb = np.clip(s, 0, 1) ** 0.7
    ws = np.abs(c) ** 1.5
    d = wf * torso_front(X, y) + wb * torso_back(X, y) + ws * torso_side(X, y)
    X, Y = radial_push(X, Y, ym, d)
    return X, Y, Z


def neck_features(X, Y, Z, ys, s, c, ym):
    y = SOLE - Z
    ax = np.abs(X)
    wf = np.clip(-s, 0, 1) ** 0.5
    d = 2.2 * seg_line(ax, y, 30, 318, 7, 382, 4.0) * (0.4 + 0.6 * np.abs(c))  # sternocleidomastoid
    d += 1.6 * gauss(ax, y, 0, 350, 4, 4) * wf                                    # larynx
    X, Y = radial_push(X, Y, ym, d)
    return X, Y, Z


# ---- head / face
EYE_Y = S.EYE_Y_PX
EYE_R = 9.5
EYE_CY = (S.EYE_FRONT_SIDE_X - CS) + EYE_R
HW_EYE, HH_EYE = S.EYE_OPEN_HALF_W, S.EYE_OPEN_HALF_H


def eye_fields(x, y):
    """Signed almond distance (px, <0 inside the eye opening) plus helpers."""
    ax = np.abs(x)
    dx = ax - S.EYE_X
    dy = y - EYE_Y
    u = dx / HW_EYE
    dyt = dy + 1.1 * u                        # outer corners lifted
    e = np.clip(1 - u * u, 0, 1) ** 0.75
    top = HH_EYE * np.clip(1 - u * u, 0, 1) ** 0.45 * (1 + 0.1 * np.clip(-u, 0, 1))  # flat, hooded upper lid
    bot = HH_EYE * 0.78 * e
    sv = np.where(dyt < 0, -dyt - top, dyt - bot)
    su = (np.abs(u) - 1) * HW_EYE
    sd = np.maximum(sv, su)
    return sd, dx, dy, dyt, top


def nose_lift(x, y):
    yk = [262, 268, 275, 283, 288, 292, 295, 298.5]
    hk = [0, 0.0, 3.0, 11.0, 18, 16.5, 8, 0]
    wk = [9, 9.5, 9.5, 9.5, 10.5, 12, 12, 9.5]
    h = np.interp(y, yk, hk, left=0, right=0)
    w = np.interp(y, yk, wk)
    ridge = h * np.clip(1 - (x / w) ** 2, 0, 1) ** 1.3
    alae = 11.5 * gauss(np.abs(x), y, 9.5, 291.5, 4.2, 3.6, 2.6)
    tip = 2.0 * gauss(x, y, 0, 288, 5, 3)
    return np.maximum(ridge + tip, alae)


def lip_shapes(x, y):
    """Upper and lower lip as lens shapes: (upper, lower) heights in px."""
    ax = np.abs(x)
    wu = np.clip(1 - (ax / 16.5) ** 2, 0, 1)
    top = 299.6 + 0.9 * np.exp(-(ax / 2.2) ** 2) - 0.6 * np.exp(-((ax - 4.5) / 2.5) ** 2)  # cupid's bow
    yc_u = (top + 306.2) / 2; th_u = (306.2 - top) / 2 * wu ** 0.35
    upper = 3.2 * wu ** 1.1 * np.clip(1 - ((y - yc_u) / np.maximum(th_u, 0.3)) ** 2, 0, 1) ** 0.55
    wl = np.clip(1 - (ax / 15.0) ** 2, 0, 1)
    th_l = 3.4 * wl ** 0.45
    lower = 4.2 * wl ** 0.9 * np.clip(1 - ((y - 309.6) / np.maximum(th_l, 0.3)) ** 2, 0, 1) ** 0.6
    return upper, lower


def lips_lift(x, y):
    ax = np.abs(x)
    muzzle = 1.2 * gauss(ax, y, 0, 305, 22, 9, 8)
    upper, lower = lip_shapes(x, y)
    crease = 2.6 * np.exp(-((y - 306.2) / 0.7) ** 2) * np.clip(1 - (ax / 17.0) ** 2, 0, 1) ** 0.5
    corners = 2.0 * gauss(ax, y, 16.6, 306.2, 1.5, 1.5)
    return muzzle + upper + lower - crease - corners


def face_lift(x, y):
    ax = np.abs(x)
    d = nose_lift(x, y) + lips_lift(x, y)
    d += 3.0 * gauss(ax, y, 19, 262, 15, 4, 4)            # brow ridge
    d -= 3.5 * gauss(ax, y, S.EYE_X, 274, 12, 7, 7)      # eye sockets
    d += 2.5 * gauss(ax, y, 33, 285, 9, 7)               # cheekbones
    d += 5.5 * gauss(ax, y, 0, 326, 13, 6, 5)            # chin
    d -= 2.0 * gauss(ax, y, 0, 315, 10, 1.8)             # mentolabial sulcus
    d -= 0.6 * seg_line(ax, y, 0, 296, 0, 299.5, 1.6)    # philtrum
    d -= 0.8 * seg_line(ax, y, 14, 294, 19, 308, 2.4)    # nasolabial fold
    d -= 1.2 * gauss(ax, y, 27, 312, 7, 8)               # under cheek
    return d


def head_features(X, Y, Z, ys, s, c, ym):
    y = SOLE - Z
    wf = np.clip(-s, 0, 1) ** 0.35
    Y = Y - wf * face_lift(X, y)
    # eyelids hug the eyeball; inside the almond the skin is pushed behind it
    sd, dx, dy, dyt, top = eye_fields(X, y)
    r2 = EYE_R ** 2 - dx ** 2 - dy ** 2
    ys_eye = EYE_CY - np.sqrt(np.clip(r2, 0, None))
    cover = sstep(EYE_R, EYE_R - 3.5, np.sqrt(dx ** 2 + dy ** 2)) * (wf > 0.5)
    crease = 1.0 * np.exp(-((-dyt - top - 2.6) / 1.0) ** 2) * (dyt < 0) * (np.abs(dx) < HW_EYE * 1.1)
    wl = sstep(5.0, 0.0, sd) * cover
    target = ys_eye - 1.0 + crease
    Y = Y + wl * (target - Y)
    wi = sstep(0.7, -0.7, sd) * cover
    Y = Y + wi * ((ys_eye + 5.0) - Y)
    return X, Y, Z


def build_head():
    rings = slice_rings(S.HEAD, 0.5, 168, 3.1, 2.1, 0.45, head_features)
    v, f = rings_mesh(rings)
    W = wmat(len(v)); W[:, BI["Head"]] = 1
    return Shell("Head", v, f, W)


def build_ear(side):
    E = S.EAR
    hh, hd0, ht = E["half_h"], E["half_d"], E["half_t"]
    zs = np.linspace(-hh, hh, 30)
    th = np.linspace(0, 2 * np.pi, 36, endpoint=False)
    rings = []
    for z in zs:
        sc = math.sqrt(max(1 - (z / hh) ** 2, 0.0)) ** 0.8
        hd = (hd0 + 1.5 * z / hh) * sc + 0.3
        t = ht * sc + 0.3
        tt = t * np.cos(th); dd = hd * np.sin(th)
        rin = np.sqrt((dd / max(hd, 1e-3)) ** 2 + (z / hh) ** 2)
        bowl = 3.4 * np.clip(1 - (rin / 0.74) ** 2, 0, 1) * (np.cos(th) > 0)
        tt = tt - bowl
        rings.append(np.stack([tt, dd, np.full_like(tt, z)], 1))
    R = np.array(rings)
    a, b = math.radians(E["tilt_back_deg"]), math.radians(E["flare_deg"])
    t, d, h = R[..., 0], R[..., 1], R[..., 2]
    d, h = d * math.cos(a) + h * math.sin(a), -d * math.sin(a) + h * math.cos(a)
    t, d = t * math.cos(b) + d * math.sin(b), -t * math.sin(b) + d * math.cos(b)
    X = side * (E["x"] + t)
    Y = (E["side_x"] - CS) + d
    Z = (SOLE - E["y"]) + h
    v, f = rings_mesh(np.stack([X, Y, Z], -1))
    W = wmat(len(v)); W[:, BI["Head"]] = 1
    return Shell("Ear_%s" % ("L" if side > 0 else "R"), v, f, W)


def build_neck():
    rings = slice_rings(S.NECK, 0.8, 96, 2.0, 2.0, 0.5, neck_features)
    v, f = rings_mesh(rings)
    y = SOLE - v[:, 2]
    W = wmat(len(v)); h = sstep(386, 334, y)
    W[:, BI["Head"]] = h; W[:, BI["UpperTorso"]] = 1 - h
    return Shell("Neck", v, f, W)


def build_torso():
    rings = slice_rings(S.TORSO, 0.8, 192, 2.35, 2.25, 0.47, torso_features)
    v, f = rings_mesh(rings)
    y = SOLE - v[:, 2]; x = v[:, 0]
    W = wmat(len(v))
    lo = sstep(566, 616, y)
    leg = sstep(672, 735, y) * sstep(6, 30, np.abs(x))
    W[:, BI["UpperTorso"]] = 1 - lo
    W[:, BI["LowerTorso"]] = lo * (1 - leg)
    W[:, BI["RightUpperLeg"]] = lo * leg * (x < 0)
    W[:, BI["LeftUpperLeg"]] = lo * leg * (x >= 0)
    return Shell("Torso", v, f, W)


# ---------------------------------------------------------------- limbs
def limb_rings(ctrl_px, radii, bumps, side, n_around=80, step=0.8, se_n=2.1, dome=True):
    C, _ = resample(catmull([V(*p) for p in ctrl_px]), step)
    T = tangents(C)
    ypx = SOLE - C[:, 2]
    A = col_interp(radii, 1, ypx); B = col_interp(radii, 2, ypx)
    roll = np.radians(col_interp(radii, 3, ypx))
    front = np.array([0, -1.0, 0]); out = np.array([side, 0, 0.0])
    D = norm(front - (T @ front)[:, None] * T)
    L = norm(out - (T @ out)[:, None] * T - (D @ out)[:, None] * D)
    Lr = np.cos(roll)[:, None] * L + np.sin(roll)[:, None] * D
    Dr = -np.sin(roll)[:, None] * L + np.cos(roll)[:, None] * D
    th = np.linspace(0, 2 * np.pi, n_around, endpoint=False)
    cx, cy = se_pow(np.cos(th), se_n), se_pow(np.sin(th), se_n)
    phi = th[None, :] + roll[:, None]
    disp = np.zeros((len(C), n_around))
    for (yb, ang, sy, sa, h) in bumps:
        h = h * 1.3
        da = (phi - math.radians(ang) + np.pi) % (2 * np.pi) - np.pi
        disp += h * np.exp(-0.5 * ((ypx[:, None] - yb) / sy) ** 2 - 0.5 * (da / math.radians(sa)) ** 2)
    offs = Lr[:, None, :] * (A[:, None] * cx[None, :])[..., None] + \
        Dr[:, None, :] * (B[:, None] * cy[None, :])[..., None]
    rl = np.linalg.norm(offs, axis=2, keepdims=True)
    offs = offs * (1 + disp[..., None] / np.maximum(rl, 1e-6))
    rings = C[:, None, :] + offs
    if dome:
        cap_h = 0.85 * min(A[0], B[0])
        pre = []
        for k in range(10, 0, -1):
            a = k / 11 * (math.pi / 2)
            pre.append(C[0] - T[0] * cap_h * math.sin(a) + offs[0] * math.cos(a))
        rings = np.concatenate([np.array(pre), rings], 0)
    return rings, C, T


def build_arm():
    rings, C, T = limb_rings(S.ARM_PATH, S.ARM_RADII, S.ARM_BUMPS, -1)
    v, f = rings_mesh(rings)
    y = SOLE - v[:, 2]
    W = wmat(len(v))
    ua = sstep(398, 448, y); la = sstep(558, 598, y); hd = sstep(668, 694, y)
    W[:, BI["UpperTorso"]] = 1 - ua
    W[:, BI["RightUpperArm"]] = ua * (1 - la)
    W[:, BI["RightLowerArm"]] = la * (1 - hd)
    W[:, BI["RightHand"]] = hd
    return Shell("Arm_R", v, f, W), C[-1], T[-1]


def build_deltoid():
    D = S.DELTOID
    nu, nv = 64, 40
    u = np.linspace(0, 2 * np.pi, nu, endpoint=False)
    v = np.linspace(-np.pi / 2, np.pi / 2, nv)[1:-1]
    rings = []
    for vv in v:
        r_h = D["r_up"] if vv > 0 else D["r_up"] * 0.9
        z = r_h * math.sin(vv)
        c = math.cos(vv)
        x = -D["r_lat"] * c * np.cos(u)          # right shoulder: outward is -X
        yy = D["r_depth"] * c * np.sin(u)
        rings.append(np.stack([x, yy, np.full_like(x, z)], 1))
    R = np.array(rings)
    t = math.radians(D["tilt_deg"])                 # top leans toward the neck
    x, z = R[..., 0].copy(), R[..., 2].copy()
    R[..., 0], R[..., 2] = x * math.cos(t) + z * math.sin(t), -x * math.sin(t) + z * math.cos(t)
    R += np.array([-D["x"], D["side_x"] - CS, SOLE - D["y"]])
    v_, f = rings_mesh(R)
    y = SOLE - v_[:, 2]
    W = wmat(len(v_)); ua = sstep(402, 452, y)
    W[:, BI["UpperTorso"]] = 1 - ua; W[:, BI["RightUpperArm"]] = ua
    return Shell("Deltoid_R", v_, f, W)


def build_leg():
    bumps = list(S.LEG_BUMPS) + [(1046, 0, 6, 35, 3.0), (1040, 180, 6, 35, 3.0)]  # malleoli
    rings, C, T = limb_rings(S.LEG_PATH, S.LEG_RADII, bumps, -1)
    v, f = rings_mesh(rings)
    y = SOLE - v[:, 2]
    W = wmat(len(v))
    ul = sstep(655, 720, y); ll = sstep(845, 888, y); ft = sstep(1034, 1068, y)
    W[:, BI["LowerTorso"]] = 1 - ul
    W[:, BI["RightUpperLeg"]] = ul * (1 - ll)
    W[:, BI["RightLowerLeg"]] = ll * (1 - ft)
    W[:, BI["RightFoot"]] = ft
    return Shell("Leg_R", v, f, W)


def tube(points, radii, ref_axis, n_around=16, step=0.6, flat=0.88,
         round_end=True, round_start=False):
    P = np.asarray(points, float)
    C, u = resample(catmull(P, 30), step)
    T = tangents(C)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    knots = np.concatenate([[0], np.cumsum(seg)]) / max(seg.sum(), 1e-9)
    r = np.interp(u, knots, radii)
    ref = np.asarray(ref_axis, float)
    A1 = norm(ref - (T @ ref)[:, None] * T)
    A2 = np.cross(T, A1)
    th = np.linspace(0, 2 * np.pi, n_around, endpoint=False)
    ring = lambda c, a1, a2, rr: c + rr * (np.cos(th)[:, None] * a1 + flat * np.sin(th)[:, None] * a2)
    rings = [ring(C[i], A1[i], A2[i], r[i]) for i in range(len(C))]
    if round_end:
        for k in range(1, 7):
            a = k / 7 * (math.pi / 2) * 0.97
            rings.append(ring(C[-1] + T[-1] * r[-1] * math.sin(a), A1[-1], A2[-1], r[-1] * math.cos(a)))
    if round_start:
        pre = []
        for k in range(6, 0, -1):
            a = k / 7 * (math.pi / 2) * 0.97
            pre.append(ring(C[0] - T[0] * r[0] * math.sin(a), A1[0], A2[0], r[0] * math.cos(a)))
        rings = pre + rings
    return rings_mesh(np.array(rings))


def hand_frame(Cw, Tw, side):
    H = S.HAND
    medial = np.array([-side, 0, 0.0]); back = np.array([0, 1.0, 0])
    Ld = norm(Tw + math.tan(math.radians(H["bend_forward_deg"])) * np.array([0, -1.0, 0]))
    phi = math.radians(H["palm_normal_back_deg"])
    N = math.cos(phi) * medial + math.sin(phi) * back
    N = norm(N - (N @ Ld) * Ld)
    W = np.cross(Ld, N)
    if W @ np.array([0, -1.0, 0]) < 0:
        W = -W
    return Ld, W, N


def build_hand(Cw, Tw, side):
    """Palm (remeshed with the body) plus separate finger and thumb shells."""
    H = S.HAND
    Ld, Wv, N = hand_frame(Cw, Tw, side)
    O = Cw
    to_w = lambda a, w, n: O + np.multiply.outer(a, Ld) + np.multiply.outer(w, Wv) + np.multiply.outer(n, N)
    pt = np.array(H["palm"], float)
    al = np.arange(pt[0, 0], pt[-1, 0] + 0.01, 0.6)
    hw = np.interp(al, pt[:, 0], pt[:, 1]); ht = np.interp(al, pt[:, 0], pt[:, 2])
    th = np.linspace(0, 2 * np.pi, 64, endpoint=False)
    cw, cn = se_pow(np.cos(th), 2.6), se_pow(np.sin(th), 2.2)
    rings = []
    for a, w, t in zip(al, hw, ht):
        ww = w * cw
        nn = t * cn
        # thenar / hypothenar pads on the palm side (+N)
        pad = (nn > 0) * (2.6 * np.exp(-((ww - w * 0.55) / 6) ** 2 - ((a - 14) / 10) ** 2)
                          + 1.6 * np.exp(-((ww + w * 0.6) / 6) ** 2 - ((a - 24) / 14) ** 2))
        knuckles = (nn < 0) * 1.4 * np.exp(-((a - 46) / 4) ** 2)
        nn = nn + pad - knuckles
        rings.append(to_w(np.full_like(ww, a), ww, nn))
    v, f = rings_mesh(np.array(rings))
    palm = Shell("Palm", v, f, None)
    fingers = []
    c1, c2, c3 = [math.radians(x) for x in H["curl"]]
    for i, (off, ka, r, ln, spread) in enumerate(H["fingers"]):
        sp = math.radians(spread)
        d0 = math.cos(sp) * Ld + math.sin(sp) * Wv
        base = O + ka * Ld + off * Wv - 0.8 * N
        pts = [base - d0 * 6.0, base]
        d = d0; p = base
        for frac, cang in ((0.44, c1), (0.31, c2), (0.25, c3)):
            d = norm(math.cos(cang) * d + math.sin(cang) * N)
            p = p + d * ln * frac
            pts.append(p)
        rr = [r * 1.02, r, r * 0.95, r * 0.88, r * 0.8]
        fv, ff = tube(pts, rr, Wv, n_around=18, step=0.55, flat=0.86)
        fingers.append(Shell("Finger%d" % i, fv, ff, None, remesh=False))
    tl = H["thumb_len"]
    tb = O + 6 * Ld + 13 * Wv + 3.0 * N
    d0 = norm(0.9 * Ld + 0.25 * Wv + 0.32 * N)
    p1 = tb + d0 * 14
    d1 = norm(d0 + 0.6 * Ld + 0.2 * N)
    p2 = p1 + d1 * tl * 0.45
    d2 = norm(d1 + 0.45 * N + 0.1 * Ld)
    p3 = p2 + d2 * tl * 0.38
    fv, ff = tube([tb, p1, p2, p3], [8.6, 7.0, 6.2, 5.5], N, n_around=18, step=0.55, flat=0.85)
    fingers.append(Shell("Thumb", fv, ff, None, remesh=False))
    return palm, fingers, (O, Ld, Wv, N)


def build_foot():
    F = np.array(S.FOOT, float)
    xs = np.arange(F[0, 0], F[-1, 0] - 0.01, -0.7)
    hw = np.interp(-xs, -F[:, 0], F[:, 1]); top = np.interp(-xs, -F[:, 0], F[:, 2])
    bot = np.interp(-xs, -F[:, 0], F[:, 3])
    u = (F[0, 0] - xs) / (F[0, 0] - F[-1, 0])
    cxf = (S.FOOT_X_HEEL + (S.FOOT_X_TOE - S.FOOT_X_HEEL) * u) - CX
    th = np.linspace(0, 2 * np.pi, 72, endpoint=False)
    rings = []
    for x0, w, t, b, uu, yside in zip(cxf, hw, top, bot, u, xs):
        zc = SOLE - (t + b) / 2; hh = (b - t) / 2
        cxs = se_pow(np.cos(th), 2.4)
        sn = np.sin(th)
        czs = np.where(sn > 0, se_pow(sn, 2.2), se_pow(sn, 4.0))
        X = x0 + w * cxs
        Z = zc + hh * czs
        medial = np.clip(cxs, 0, 1)          # right foot: medial side is +X
        arch = 5.5 * medial * (sn < 0) * np.exp(-((uu - 0.48) / 0.2) ** 2)
        Z = Z + arch
        rings.append(np.stack([X, np.full_like(X, yside - CS), Z], 1))
    v, f = rings_mesh(np.array(rings))
    W = wmat(len(v)); W[:, BI["RightFoot"]] = 1
    foot = Shell("Foot_R", v, f, W)
    toes = []
    ue = 1.0
    x_toe = S.FOOT_X_TOE - CX
    for i, (off, tip, r) in enumerate(S.TOES):
        x = x_toe + off
        zc = r * 0.82 - 1.0
        base = np.array([x, 652 - CS, zc + 3.0])
        mid = np.array([x, (652 + tip) / 2 - CS, zc + 1.2])
        end = np.array([x - 0.5 * np.sign(off), tip + r - CS, zc])
        tv, tf = tube([base, mid, end], [r * 1.05, r, r * 0.92], [1, 0, 0], n_around=16, step=0.55,
                      flat=0.78, round_end=True)
        Wt = wmat(len(tv)); Wt[:, BI["RightFoot"]] = 1
        toes.append(Shell("Toe%d_R" % i, tv, tf, Wt, remesh=False))
    return foot, toes


# ------------------------------------------------------------- blender io
def make_obj(name, verts, faces, coll, smooth=True):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", np.asarray(verts, np.float32).ravel())
    flat = [i for f in faces for i in f]
    me.loops.add(len(flat))
    me.loops.foreach_set("vertex_index", np.asarray(flat, np.int32))
    me.polygons.add(len(faces))
    starts = np.cumsum([0] + [len(f) for f in faces[:-1]]).astype(np.int32)
    me.polygons.foreach_set("loop_start", starts)
    me.update(calc_edges=True)
    me.validate()
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    if smooth:
        me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def mesh_arrays(ob):
    me = ob.data
    v = np.zeros(len(me.vertices) * 3, np.float32); me.vertices.foreach_get("co", v)
    return v.reshape(-1, 3).astype(float)


def set_verts(ob, v):
    ob.data.vertices.foreach_set("co", np.asarray(v, np.float32).ravel())
    ob.data.update()


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def assign_groups(ob, W):
    W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
    for b, i in BI.items():
        vg = ob.vertex_groups.new(name=b)
        q = np.round(W[:, i] * 100).astype(int)
        for val in np.unique(q):
            if val <= 0:
                continue
            vg.add(np.nonzero(q == val)[0].tolist(), val / 100.0, "REPLACE")


def group_weights(ob):
    me = ob.data
    W = np.zeros((len(me.vertices), len(BONES)))
    gi = {vg.index: BI.get(vg.name) for vg in ob.vertex_groups}
    for v in me.vertices:
        for g in v.groups:
            j = gi.get(g.group)
            if j is not None:
                W[v.index, j] = g.weight
    return W


def transfer_weights(src_v, src_tris, src_W, dst_v):
    bvh = BVHTree.FromPolygons(src_v.tolist(), src_tris.tolist())
    n = len(dst_v)
    loc = np.zeros((n, 3)); fi = np.zeros(n, int)
    for i in range(n):
        hit = bvh.find_nearest(Vector(dst_v[i]))
        loc[i] = hit[0]; fi[i] = hit[2]
    tri = src_tris[fi]
    a, b, c = src_v[tri[:, 0]], src_v[tri[:, 1]], src_v[tri[:, 2]]
    v0, v1, v2 = b - a, c - a, loc - a
    d00 = (v0 * v0).sum(1); d01 = (v0 * v1).sum(1); d11 = (v1 * v1).sum(1)
    d20 = (v2 * v0).sum(1); d21 = (v2 * v1).sum(1)
    den = np.maximum(d00 * d11 - d01 * d01, 1e-12)
    bv = (d11 * d20 - d01 * d21) / den; bw = (d00 * d21 - d01 * d20) / den
    bu = 1 - bv - bw
    bary = np.clip(np.stack([bu, bv, bw], 1), 0, 1)
    bary /= np.maximum(bary.sum(1, keepdims=True), 1e-9)
    return (src_W[tri] * bary[..., None]).sum(1)


def triangulate(faces):
    tris = []
    for f in faces:
        for k in range(1, len(f) - 1):
            tris.append((f[0], f[k], f[k + 1]))
    return np.array(tris, int)


def srgb_lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def set_colors(ob, cols, name="Col"):
    me = ob.data
    if name in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[name])
    ca = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    rgba = np.ones((len(cols), 4), np.float32); rgba[:, :3] = cols
    ca.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = ca


def vertex_normals(ob):
    me = ob.data
    n = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("normal", n)
    return n.reshape(-1, 3).astype(float)


# ------------------------------------------------------------------ build
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    root = bpy.data.collections.new("Exit6_Male")
    sc.collection.children.link(root)
    shells = bpy.data.collections.new("Exit6_Male_BuildShells")
    sc.collection.children.link(shells)
    return root, shells


def build_body(root, shells_coll):
    log("lofting shells")
    head = build_head(); neck = build_neck(); torso = build_torso()
    earR, earL = build_ear(-1), build_ear(1)
    armR, Cw, Tw = build_arm()
    palmR, fingersR, hfR = build_hand(Cw, Tw, -1)
    legR = build_leg()
    deltR = build_deltoid()
    footR, toesR = build_foot()
    for sh in [palmR] + fingersR:
        sh.weights = wmat(len(sh.verts)); sh.weights[:, BI["RightHand"]] = 1
    shells = [head, neck, torso, earR, earL, armR, deltR, palmR, legR, footR] + fingersR + toesR
    left = [mirror_shell(s, s.name.replace("_R", "_L") if "_R" in s.name else s.name + "_L")
            for s in [armR, deltR, palmR, legR, footR] + fingersR + toesR]
    shells += left
    hand_frames = {"R": hfR, "L": (hfR[0] * np.array([-1, 1, 1]), hfR[1] * np.array([-1, 1, 1]),
                                   hfR[2] * np.array([-1, 1, 1]), hfR[3] * np.array([-1, 1, 1]))}
    for sh in shells:
        ob = make_obj("Shell_" + sh.name, sh.verts, sh.faces, shells_coll)
        assign_groups(ob, sh.weights)
    rem = [s for s in shells if s.remesh]
    sep = [s for s in shells if not s.remesh]
    # one combined source for remesh + weight lookup
    allv, alltri, allW, off = [], [], [], 0
    for s in rem:
        allv.append(s.verts); alltri.append(triangulate(s.faces) + off); allW.append(s.weights)
        off += len(s.verts)
    allv = np.vstack(allv); alltri = np.vstack(alltri); allW = np.vstack(allW)
    log("remesh source: %d verts" % len(allv))
    src = make_obj("RemeshSource", allv, alltri.tolist(), root, smooth=False)
    mod = src.modifiers.new("vox", "REMESH"); mod.mode = "VOXEL"
    mod.voxel_size = OPT["voxel"]; mod.adaptivity = 0.0; mod.use_smooth_shade = True
    sm = src.modifiers.new("smooth", "SMOOTH"); sm.factor = 0.5; sm.iterations = 3
    apply_modifiers(src)
    bv = mesh_arrays(src)
    yy = SOLE - bv[:, 2]
    jaw = sstep(318, 348, yy) * (0.35 + 0.65 * sstep(-30, -5, bv[:, 1]))
    mask = np.maximum(jaw, sstep(338, 352, yy))      # face stays crisp, jaw line and neck soften
    vg = src.vertex_groups.new(name="body_smooth")
    q = np.round(mask * 20).astype(int)
    for val in np.unique(q):
        if val > 0:
            vg.add(np.nonzero(q == val)[0].tolist(), val / 20.0, "REPLACE")
    sm2 = src.modifiers.new("smooth_body", "SMOOTH"); sm2.factor = 0.6; sm2.iterations = 32
    sm2.vertex_group = "body_smooth"
    apply_modifiers(src)
    body_v = mesh_arrays(src)
    log("remeshed body: %d verts, %d faces" % (len(body_v), len(src.data.polygons)))
    log("transferring weights")
    W = transfer_weights(allv, alltri, allW, body_v)
    # append the separate finger / toe shells
    faces_body = np.zeros(len(src.data.polygons) * 4, np.int32)
    src.data.polygons.foreach_get("vertices", faces_body)
    faces_body = faces_body.reshape(-1, 4).tolist()
    V_all, F_all, W_all = [body_v], list(faces_body), [W]
    off = len(body_v)
    for s in sep:
        V_all.append(s.verts); F_all += [[i + off for i in f] for f in s.faces]; W_all.append(s.weights)
        off += len(s.verts)
    V_all = np.vstack(V_all); W_all = np.vstack(W_all)
    bpy.data.objects.remove(src)
    body = make_obj("Exit6_Male_Body", V_all, F_all, root)
    assign_groups(body, W_all)
    shells_coll.hide_render = True
    bpy.context.view_layer.layer_collection.children["Exit6_Male_BuildShells"].exclude = True
    return body, W_all, hand_frames, head


def skin_colors(body, W, hand_frames):
    v = mesh_arrays(body)
    x, Y, y = v[:, 0], v[:, 1], SOLE - v[:, 2]
    base = srgb_lin(S.SKIN_SRGB)
    col = np.tile(base, (len(v), 1))
    rng = np.random.default_rng(7)
    # broad, soft tone variation (warmer cheeks/ears, slightly deeper on limbs ends)
    var = 1.0 + 0.04 * np.sin(x * 0.05) * np.sin(y * 0.031) + 0.02 * np.sin(y * 0.11 + x * 0.07)
    col *= var[:, None]
    face = (y < 340) & (Y < -10)
    # lips: tinted inside the lens shapes
    ax = np.abs(x)
    up_, lo_ = lip_shapes(x, y)
    lipw = sstep(0.15, 1.2, np.maximum(up_, lo_)) * face
    col = col * (1 - lipw[:, None]) + srgb_lin(S.SKIN_LIPS_SRGB) * lipw[:, None]
    # nipples / areolae
    ar = np.hypot(ax - 46, y - 462)
    aw = sstep(4.2, 2.6, ar) * (Y < -30)
    col = col * (1 - 0.45 * aw[:, None])
    # lash line and lid shading
    sd, dx, dy, dyt, top = eye_fields(x, y)
    near_eye = face & (np.abs(dx) < HW_EYE * 1.25)
    upper = near_eye & (dyt < 0) & (sd > -0.9) & (sd < 1.7)
    lower = near_eye & (dyt > 0) & (sd > -0.4) & (sd < 0.8)
    col[upper] = srgb_lin((22, 14, 12))
    col[lower] = col[lower] * 0.55
    inside = near_eye & (sd < -0.6)
    col[inside] = srgb_lin((60, 30, 26))
    lid = near_eye & (dyt < 0) & (sd >= 1.3) & (sd < 4.5)
    col[lid] *= 0.86
    # nostrils
    nos = face & (gauss(ax, y, 5.5, 295.2, 2.2, 1.0) > 0.5)
    col[nos] *= 0.35
    # palms and soles lighter
    for side, key in ((-1, "R"), (1, "L")):
        O, Ld, Wv, N = hand_frames[key]
        rel = v - O
        a = rel @ Ld; n = rel @ N
        hand_w = W[:, BI["RightHand" if side < 0 else "LeftHand"]]
        palm = (a > -2) & (a < 90) & (np.sign(x) == side) & (n > 2.0) & (hand_w > 0.5)
        col[palm] = col[palm] * 0.75 + srgb_lin((196, 140, 104)) * 0.25
    sole = v[:, 2] < 3.0
    col[sole] = col[sole] * 0.5 + srgb_lin((190, 136, 100)) * 0.5
    set_colors(body, col)


# ------------------------------------------------------------ accessories
def head_bvh(head):
    return BVHTree.FromPolygons(head.verts.tolist(), triangulate(head.faces).tolist())


HEAD_C = np.array([0.0, 12.0, SOLE - 268.0])
HEAD_R = np.array([48.0, 63.0, 53.0])


def surface_hit(bvh, p, d):
    """Ray hit on the analytic head; the normal is flipped to face outward
    (the slice lofts wind inward)."""
    hit = bvh.ray_cast(Vector(p), Vector(d))
    if hit[0] is None:
        return None, None
    loc, n = np.array(hit[0]), np.array(hit[1])
    if n @ (-np.asarray(d, float)) < 0:
        n = -n
    return loc, n


def hairline_y(phi):
    pk = [0, 0.45, 0.75, 1.0, 1.3, 1.6, 1.95, 2.35, 2.75, math.pi]
    yk = [236, 238, 246, 258, 270, 266, 290, 316, 326, 328]
    return np.interp(np.abs(phi), pk, yk)


def scalp_dirs(n):
    i = np.arange(n) + 0.5
    phi = np.arccos(1 - 2 * i / n)
    th = math.pi * (1 + 5 ** 0.5) * i
    d = np.stack([np.cos(th) * np.sin(phi), np.sin(th) * np.sin(phi), np.cos(phi)], 1)
    return d


def build_hair(bvh, root):
    rng = np.random.default_rng(42)
    dirs = scalp_dirs(250)
    dirs = dirs[dirs[:, 0] > 0.02]
    roots = []
    for d in dirs:
        dd = d * HEAD_R
        o = HEAD_C + norm(dd) * 200
        p, n = surface_hit(bvh, o, -norm(dd))
        if p is None:
            continue
        phi = math.atan2(p[0], -(p[1] - HEAD_C[1]))
        if SOLE - p[2] > hairline_y(phi) - 1:
            continue
        if abs(p[0]) < 2.5:
            continue
        roots.append((p, n))
    roots += [(p * np.array([-1, 1, 1]), n * np.array([-1, 1, 1])) for p, n in roots]
    log("hair roots: %d" % len(roots))
    allv, allf = [], []
    tips = []
    marg = HEAD_R + 5.0
    down = np.array([0, 0, -1.0]); fwd = np.array([0, -1.0, 0]); bk = np.array([0, 1.0, 0])
    for p, n in roots:
        phi = math.atan2(p[0], -(p[1] - HEAD_C[1]))
        ap = abs(phi)
        lat = np.array([np.sign(p[0]), 0, 0])
        elev = (p[2] - HEAD_C[2]) / HEAD_R[2]
        radial = norm(np.array([p[0], p[1] - HEAD_C[1], 0]))
        if ap < 0.55:                       # fringe: forward, then off to the side
            hang = norm(0.8 * down + 1.35 * lat + 0.3 * fwd); L = 26 + 10 * max(elev, 0); lift = 6
        elif elev > 0.55 and ap < 1.0:      # front crown: swept to the side
            hang = norm(0.8 * down + 1.0 * lat + 0.25 * bk); L = 44; lift = 6
        elif elev > 0.55:                   # crown: up and over
            hang = norm(1.0 * down + 0.45 * radial); L = 46; lift = 5
        elif ap < 2.1:                      # sides
            hang = norm(1.0 * down + 0.3 * lat + 0.1 * bk); L = 40 + 6 * elev; lift = 6
        else:                               # back
            hang = norm(1.0 * down + 0.3 * bk + 0.1 * lat); L = 44 + 6 * elev; lift = 6
        L *= rng.uniform(0.9, 1.1)
        hang = norm(hang + rng.normal(0, 0.06, 3))
        P0 = p - n * 2.0
        P1 = p + n * lift
        P2 = P1 + hang * L
        ts = np.linspace(0, 1, 28)[:, None]
        curve = (1 - ts) ** 2 * p + 2 * (1 - ts) * ts * P1 + ts ** 2 * P2
        pts = [P0]
        for q in curve:
            rel = (q - HEAD_C) / marg
            r = np.linalg.norm(rel)
            if r < 1.0:
                q = HEAD_C + rel / r * marg
            pts.append(q)
        pts = np.array(pts)
        tips.append(pts[-1])
        tv, tf = twist_mesh(pts, rng)
        allf += [[i + sum(len(a) for a in allv) for i in f] for f in tf]
        allv.append(tv)
    V_ = np.vstack(allv)
    ob = make_obj("Exit6_Male_Hair_Twists", V_, allf, root)
    W = wmat(len(V_)); W[:, BI["Head"]] = 1
    assign_groups(ob, W)
    return ob, roots


def twist_mesh(pts, rng, R0=5.2):
    C, u = resample(catmull(pts, 12), 0.9)
    T = tangents(C)
    ref = np.array([0, 0, 1.0]) if abs(T[0][2]) < 0.9 else np.array([1.0, 0, 0])
    A1 = np.zeros_like(C); A2 = np.zeros_like(C)
    a = norm(ref - (ref @ T[0]) * T[0])
    for i in range(len(C)):          # parallel transport
        a = norm(a - (a @ T[i]) * T[i])
        A1[i] = a; A2[i] = np.cross(T[i], a)
    length = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(C, axis=0), axis=1))])
    P = rng.uniform(12.0, 13.5)
    ph = rng.uniform(0, 2 * np.pi)
    th = np.linspace(0, 2 * np.pi, 16, endpoint=False)
    taper = 1.0 - 0.12 * (length / length[-1])
    rings = []
    for i in range(len(C)):
        s = length[i]
        lob = 1 + 0.08 * np.cos(2 * th - 2 * np.pi * s / P + ph)
        bead = 1 + 0.11 * np.cos(4 * np.pi * s / P + ph)
        r = R0 * taper[i] * lob * bead
        rings.append(C[i] + r[:, None] * (np.cos(th)[:, None] * A1[i] + np.sin(th)[:, None] * A2[i]))
    rl = R0 * taper[-1]
    for k in range(1, 6):
        ang = k / 6 * (math.pi / 2)
        rr = rl * math.cos(ang)
        rings.append(C[-1] + T[-1] * rl * math.sin(ang) * 1.1 +
                     rr * (np.cos(th)[:, None] * A1[-1] + np.sin(th)[:, None] * A2[-1]))
    return rings_mesh(np.array(rings))


def build_scalp_cap(bvh, roots, root_coll):
    nphi, nel = 200, 90
    phis = np.linspace(-math.pi, math.pi, nphi, endpoint=False)
    els = np.linspace(-0.55, 1.0, nel)
    rp = np.array([p for p, n in roots])
    grid = np.full((nel, nphi, 3), np.nan)
    ok = np.zeros((nel, nphi), bool)
    for i, e in enumerate(els):
        for j, ph in enumerate(phis):
            ce = math.cos(math.asin(min(e, 0.999)))
            d = np.array([math.sin(ph) * ce, -math.cos(ph) * ce, e]) * HEAD_R
            dn = norm(d)
            p, n = surface_hit(bvh, HEAD_C + dn * 200, -dn)
            if p is None:
                continue
            grid[i, j] = p + n * 1.4
            ok[i, j] = SOLE - p[2] < hairline_y(ph) + 1.5
    verts, faces, idx = [], [], -np.ones((nel, nphi), int)
    for i in range(nel):
        for j in range(nphi):
            if ok[i, j]:
                idx[i, j] = len(verts); verts.append(grid[i, j])
    for i in range(nel - 1):
        for j in range(nphi):
            a, b, c, d = idx[i, j], idx[i, (j + 1) % nphi], idx[i + 1, (j + 1) % nphi], idx[i + 1, j]
            if min(a, b, c, d) >= 0:
                faces.append([a, b, c, d])
    verts = np.array(verts)
    ob = make_obj("Exit6_Male_Hair_Scalp", verts, faces, root_coll)
    sol = ob.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 0.8; sol.offset = -1
    # box parts: lighter scalp where the two nearest twist roots are equidistant
    d = np.linalg.norm(verts[:, None, :] - rp[None, :, :], axis=2)
    d.sort(1)
    part = (d[:, 1] - d[:, 0]) < 1.1
    col = np.tile(srgb_lin(S.HAIR_SRGB), (len(verts), 1))
    col[part] = srgb_lin((92, 56, 36))
    set_colors(ob, col)
    W = wmat(len(verts)); W[:, BI["Head"]] = 1
    assign_groups(ob, W)
    return ob


def build_brows(bvh, root):
    pts = [(-29, 262.5, 5.2), (-24, 262.0, 6.8), (-18, 262.8, 7.6),
           (-12.5, 264.6, 8.0), (-8.0, 266.8, 8.2), (-5.2, 268.2, 7.6)]
    rings = []
    for x, yc, t in pts:
        ring = []
        for (vv, out) in ((-0.5, -0.6), (-0.5, 1.8), (-0.25, 2.9), (0.15, 3.1), (0.5, 2.0),
                          (0.5, -0.6), (0.0, -1.0)):
            yy = yc + vv * t
            p, n = surface_hit(bvh, np.array([x, -200, SOLE - yy]), np.array([0, 1.0, 0]))
            ring.append(p + n * out)
        rings.append(ring)
    rings = np.array(rings)
    v, f = rings_mesh(rings)
    v2 = v.copy(); v2[:, 0] *= -1
    f2 = [list(reversed(ff)) for ff in f]
    V_ = np.vstack([v, v2]); F_ = f + [[i + len(v) for i in ff] for ff in f2]
    ob = make_obj("Exit6_Male_Brows", V_, F_, root)
    W = wmat(len(V_)); W[:, BI["Head"]] = 1
    assign_groups(ob, W)
    return ob


def build_goatee(bvh, root):
    C = np.array([0.0, -20.0, SOLE - 316.0])
    us = np.linspace(-1, 1, 40)
    angs = np.radians(np.linspace(-8, 78, 34))
    grid = np.zeros((len(angs), len(us), 3)); m = np.zeros((len(angs), len(us)))
    for i, a in enumerate(angs):
        for j, u in enumerate(us):
            x = u * 19.5
            d = np.array([0, -math.cos(a), -math.sin(a)])
            o = C + np.array([x, 0, 0]) + d * 80
            p, n = surface_hit(bvh, o, -d)
            if p is None:
                p, n = C + np.array([x, 0, 0]), -d
            y = SOLE - p[2]
            # goatee outline: wider at the bottom, a soft top edge under the lip
            half = 4.5 + 13.5 * sstep(318, 334, y) ** 0.8
            top = 318.0 + 3.0 * (abs(x) / 18.0) ** 1.3
            mask = sstep(top - 0.5, top + 2.0, y) * sstep(half, half - 3.0, abs(x)) * sstep(-27, -40, p[1])
            m[i, j] = mask
            grid[i, j] = p + n * (2.5 * mask ** 0.6 - 0.4)
    verts, faces, idx = [], [], -np.ones(m.shape, int)
    for i in range(m.shape[0]):
        for j in range(m.shape[1]):
            if m[i, j] > 0.02:
                idx[i, j] = len(verts); verts.append(grid[i, j])
    for i in range(m.shape[0] - 1):
        for j in range(m.shape[1] - 1):
            a, b, c, d = idx[i, j], idx[i, j + 1], idx[i + 1, j + 1], idx[i + 1, j]
            if min(a, b, c, d) >= 0:
                faces.append([a, b, c, d])
    ob = make_obj("Exit6_Male_Goatee", np.array(verts), faces, root)
    sol = ob.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 3.2; sol.offset = -1
    W = wmat(len(verts)); W[:, BI["Head"]] = 1
    assign_groups(ob, W)
    return ob


def build_eyes(root):
    obs = []
    for side in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=24, radius=EYE_R)
        me = bpy.data.meshes.new("eye")
        bm.to_mesh(me); bm.free()
        v = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", v); v = v.reshape(-1, 3)
        # pole (+Z) becomes forward (-Y)
        v = np.stack([v[:, 0], -v[:, 2], v[:, 1]], 1)
        ang = np.degrees(np.arccos(np.clip(-v[:, 1] / EYE_R, -1, 1)))
        v[:, 1] -= 0.7 * np.clip(1 - ang / 40, 0, 1) ** 2           # cornea bulge
        v += np.array([side * S.EYE_X, EYE_CY, SOLE - EYE_Y])
        me.vertices.foreach_set("co", v.ravel().astype(np.float32)); me.update()
        ob = bpy.data.objects.new("Exit6_Male_Eye_%s" % ("L" if side > 0 else "R"), me)
        root.objects.link(ob)
        me.shade_smooth()
        for poly in me.polygons:
            c = np.array(poly.center) - np.array([side * S.EYE_X, EYE_CY, SOLE - EYE_Y])
            a = math.degrees(math.acos(max(-1, min(1, -c[1] / np.linalg.norm(c)))))
            poly.material_index = 2 if a < 12 else (1 if a < 28 else 0)
        W = wmat(len(v)); W[:, BI["Head"]] = 1
        assign_groups(ob, W)
        obs.append(ob)
    return obs


def build_briefs(body, W, root):
    v = mesh_arrays(body)
    nrm = vertex_normals(body)
    y = SOLE - v[:, 2]
    dom = W.argmax(1)
    okb = np.isin(dom, [BI["LowerTorso"], BI["UpperTorso"], BI["LeftUpperLeg"], BI["RightUpperLeg"]])
    hem = 765 + 3 * sstep(-20, 30, v[:, 1])
    inside = okb & (y > 603.5) & (y < hem)
    faces = [list(p.vertices) for p in body.data.polygons]
    sel = [f for f in faces if all(inside[i] for i in f)]
    used = np.unique(np.array(sel).ravel())
    remap = -np.ones(len(v), int); remap[used] = np.arange(len(used))
    nv = v[used].copy(); nn = nrm[used]
    yy = y[used]
    # smooth away muscle grooves (fabric bridges them), keep boundary
    nf = [[remap[i] for i in f] for f in sel]
    adj = [[] for _ in range(len(nv))]
    edge_count = {}
    for f in nf:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            adj[a].append(b); adj[b].append(a)
            e = (min(a, b), max(a, b)); edge_count[e] = edge_count.get(e, 0) + 1
    boundary = np.zeros(len(nv), bool)
    for (a, b), cnt in edge_count.items():
        if cnt == 1:
            boundary[a] = boundary[b] = True
    nbr = [np.unique(a) for a in adj]
    off = 1.5 + 0.9 * sstep(613, 609, yy) + 0.5 * sstep(hem[used] - 4, hem[used], yy)
    nv = nv + nn * off[:, None]
    for it in range(6):
        avg = np.array([nv[n_].mean(0) for n_ in nbr])
        nv = np.where(boundary[:, None], nv, nv * 0.5 + avg * 0.5)
    # keep the fabric outside the skin
    bvh = BVHTree.FromPolygons(v.tolist(), triangulate(faces).tolist())
    for i in range(len(nv)):
        loc, n_, fi, dist = bvh.find_nearest(Vector(nv[i]))
        want = 1.2 + 0.9 * (yy[i] < 612)
        if loc is not None and dist < want:
            nv[i] = np.array(loc) + np.array(n_) * want
    ob = make_obj("Exit6_Male_Briefs", nv, nf, root)
    sol = ob.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 0.7; sol.offset = -1
    col = np.tile(srgb_lin(S.BRIEFS_SRGB), (len(nv), 1))
    band = yy < 612.5
    col[band] *= 0.8
    seam = (np.abs(np.abs(nv[:, 0]) - 33) < 0.7) & (nv[:, 1] < -20) & ~band
    col[seam] = srgb_lin((52, 50, 54))
    set_colors(ob, col)
    Wb = W[used]
    assign_groups(ob, Wb)
    return ob


# -------------------------------------------------------------- materials
def principled(name, color=None, attr=None, rough=0.5, sss=0.0, coat=0.0, sheen=0.0, spec=0.5,
               bump=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    if attr:
        a = nt.nodes.new("ShaderNodeVertexColor"); a.layer_name = attr
        nt.links.new(a.outputs["Color"], p.inputs["Base Color"])
    elif color is not None:
        p.inputs["Base Color"].default_value = (*color, 1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Specular IOR Level"].default_value = spec
    if sss:
        p.inputs["Subsurface Weight"].default_value = sss
        p.inputs["Subsurface Radius"].default_value = (1.0, 0.42, 0.24)
        p.inputs["Subsurface Scale"].default_value = 0.012
    if coat:
        p.inputs["Coat Weight"].default_value = coat
        p.inputs["Coat Roughness"].default_value = 0.35
    if sheen:
        p.inputs["Sheen Weight"].default_value = sheen
    if bump:
        nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = bump[0]
        nz.inputs["Detail"].default_value = 6
        bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump[1]
        nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
        nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    return m


def make_materials():
    M = {}
    M["skin"] = principled("M_Exit6_Skin", attr="Col", rough=0.55, sss=0.12, coat=0.05, spec=0.42,
                           bump=(900.0, 0.04))
    M["hair"] = principled("M_Exit6_Hair", color=tuple(srgb_lin(S.HAIR_SRGB)), rough=0.48, spec=0.5,
                           coat=0.1, bump=(70.0, 0.3))
    M["scalp"] = principled("M_Exit6_HairScalp", attr="Col", rough=0.55, spec=0.35, bump=(120.0, 0.3))
    M["sclera"] = principled("M_Exit6_EyeSclera", color=tuple(srgb_lin((196, 184, 176))), rough=0.3, coat=0.5)
    M["iris"] = principled("M_Exit6_EyeIris", color=tuple(srgb_lin((38, 20, 11))), rough=0.35, coat=0.5)
    M["pupil"] = principled("M_Exit6_EyePupil", color=(0.003, 0.003, 0.003), rough=0.3, coat=0.5)
    M["briefs"] = principled("M_Exit6_Briefs", attr="Col", rough=0.78, spec=0.25, sheen=0.4,
                             bump=(260.0, 0.15))
    return M


# ------------------------------------------------------------------- rig
def jp(name, side=None):
    if side is None:
        return V(*S.JOINTS_C[name]) * K
    p = V(*S.JOINTS_R[name])
    if side == "Left":
        p = p * np.array([-1, 1, 1])
    return p * K


def build_rig(root):
    arm = bpy.data.armatures.new("Exit6_Male_Rig")
    ob = bpy.data.objects.new("Exit6_Male_Rig", arm)
    root.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    front = Vector((0, -1, 0))

    def bone(name, head, tail, parent=None, deform=True):
        b = eb.new(name)
        b.head = Vector(head); b.tail = Vector(tail)
        b.align_roll(front)
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]; b.use_connect = False
        return b

    root_p = jp("root")
    bone("HumanoidRootNode", root_p, root_p + np.array([0, 0, 0.35]), deform=False)
    bone("LowerTorso", root_p, jp("waist"), "HumanoidRootNode")
    bone("UpperTorso", jp("waist"), jp("neck"), "LowerTorso")
    bone("Head", jp("neck"), jp("head_top"), "UpperTorso")
    for side in ("Left", "Right"):
        bone(side + "UpperArm", jp("shoulder", side), jp("elbow", side), "UpperTorso")
        bone(side + "LowerArm", jp("elbow", side), jp("wrist", side), side + "UpperArm")
        bone(side + "Hand", jp("wrist", side), jp("hand_tip", side), side + "LowerArm")
        bone(side + "UpperLeg", jp("hip", side), jp("knee", side), "LowerTorso")
        bone(side + "LowerLeg", jp("knee", side), jp("ankle", side), side + "UpperLeg")
        bone(side + "Foot", jp("ankle", side), jp("toe", side), side + "LowerLeg")
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.select_set(False)
    return ob


def bind(objs, rig):
    for ob in objs:
        ob.parent = rig
        sol = [(m.name, m.thickness, m.offset) for m in ob.modifiers if m.type == "SOLIDIFY"]
        for m in [m for m in ob.modifiers if m.type == "SOLIDIFY"]:
            ob.modifiers.remove(m)
        a = ob.modifiers.new("Armature", "ARMATURE"); a.object = rig
        for name, th, off in sol:
            m = ob.modifiers.new(name, "SOLIDIFY"); m.thickness = th; m.offset = off


POSES = {
    "rest": {},
    "walk": {"RightUpperLeg": (-28, 0, 0), "RightLowerLeg": (8, 0, 0), "RightFoot": (-10, 0, 0),
             "LeftUpperLeg": (22, 0, 0), "LeftLowerLeg": (35, 0, 0), "LeftFoot": (12, 0, 0),
             "RightUpperArm": (22, 0, 0), "RightLowerArm": (-18, 0, 0),
             "LeftUpperArm": (-24, 0, 0), "LeftLowerArm": (-30, 0, 0),
             "UpperTorso": (0, 6, 0), "Head": (0, -6, 0)},
    "arms_up": {"RightUpperArm": (0, 0, -82), "LeftUpperArm": (0, 0, 82),
                "RightLowerArm": (0, 0, 0), "LeftLowerArm": (0, 0, 0)},
    "crouch": {"RightUpperLeg": (-62, 0, 0), "LeftUpperLeg": (-62, 0, 0),
               "RightLowerLeg": (95, 0, 0), "LeftLowerLeg": (95, 0, 0),
               "RightFoot": (-30, 0, 0), "LeftFoot": (-30, 0, 0),
               "LowerTorso": (0, 0, 0), "UpperTorso": (22, 0, 0),
               "RightUpperArm": (-45, 0, -10), "LeftUpperArm": (-45, 0, 10),
               "RightLowerArm": (-60, 0, 0), "LeftLowerArm": (-60, 0, 0)},
    "twist": {"UpperTorso": (0, 25, 0), "Head": (-12, 30, 0),
              "RightUpperArm": (-60, 0, -20), "RightLowerArm": (-80, 0, 0),
              "LeftUpperArm": (10, 0, 25)},
}


def build_pose_action(rig):
    rig.animation_data_create()
    act = bpy.data.actions.new("Exit6_PoseTest")
    rig.animation_data.action = act
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
    for fi, (pname, pose) in enumerate(POSES.items(), start=1):
        for pb in rig.pose.bones:
            r = pose.get(pb.name, (0, 0, 0))
            pb.rotation_euler = [math.radians(a) for a in r]
            pb.location = (0, 0, 0)
            pb.keyframe_insert("rotation_euler", frame=fi)
            pb.keyframe_insert("location", frame=fi)
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT"
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = len(POSES)
    return act


def _fcurves(act):
    if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


# ---------------------------------------------------------------- render
def setup_render(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for t in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = t
            prefs.get_devices()
            if any(d.type == t for d in prefs.devices):
                break
        except Exception:
            pass
    for d in prefs.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.film_transparent = True
    sc.render.resolution_x = 600
    sc.render.resolution_y = 1402
    sc.render.resolution_percentage = 100
    world = bpy.data.worlds.new("Studio")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.76, 0.80, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.16
    lc = bpy.data.collections.new("Exit6_Studio")
    sc.collection.children.link(lc)

    def area(name, loc, size, power, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, "AREA"); ld.size = size; ld.energy = power; ld.color = color
        lo = bpy.data.objects.new(name, ld); lc.objects.link(lo)
        lo.location = loc
        tgt = Vector((0, 0, 3.3))
        lo.rotation_euler = (tgt - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return lo
    area("Key", (-4.0, -6.5, 12.0), 4.0, 1300, (1.0, 0.96, 0.92))
    area("Fill", (7.0, -7.5, 4.0), 8.0, 280, (0.95, 0.96, 1.0))
    area("RimL", (6.0, 7.0, 7.0), 4.0, 380)
    area("RimR", (-6.0, 7.0, 7.0), 4.0, 300)
    me = bpy.data.meshes.new("Floor")
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12); bm.to_mesh(me); bm.free()
    fl = bpy.data.objects.new("Floor_ShadowCatcher", me); lc.objects.link(fl)
    fl.is_shadow_catcher = True
    cam_d = bpy.data.cameras.new("Cam"); cam_d.type = "ORTHO"
    cam_d.ortho_scale = 1402 * K; cam_d.sensor_fit = "VERTICAL"
    cam = bpy.data.objects.new("Exit6_Camera", cam_d); lc.objects.link(cam)
    sc.camera = cam
    return cam


VIEWS = {"front": 0.0, "three_quarter": -35.0, "side": 90.0, "back": 180.0}  # reference 3/4 is from the character's right


def render_views(cam, prefix, views=VIEWS, size=None):
    sc = bpy.context.scene
    zc = (SOLE - 701) * K
    out = {}
    for name, az in views.items():
        a = math.radians(az)
        cam.location = (math.sin(a) * 30, -math.cos(a) * 30, zc)
        cam.rotation_euler = (math.radians(90), 0, a)
        path = os.path.join(REN_DIR, "%s_%s.png" % (prefix, name))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out[name] = path
        log("rendered", path)
    return out


# ------------------------------------------------------------------- main
def main():
    root, shells_coll = reset_scene()
    body, W, hand_frames, head = build_body(root, shells_coll)
    skin_colors(body, W, hand_frames)
    bvh = head_bvh(head)
    log("hair, brows, goatee, eyes, briefs")
    hair, roots = build_hair(bvh, root)
    scalp = build_scalp_cap(bvh, roots, root)
    brows = build_brows(bvh, root)
    goatee = build_goatee(bvh, root)
    eyes = build_eyes(root)
    briefs = build_briefs(body, W, root)
    M = make_materials()
    body.data.materials.append(M["skin"])
    for ob in (hair, brows, goatee):
        ob.data.materials.append(M["hair"])
    scalp.data.materials.append(M["scalp"])
    briefs.data.materials.append(M["briefs"])
    for e in eyes:
        for k in ("sclera", "iris", "pupil"):
            e.data.materials.append(M[k])
    # reference pixels -> studs
    S_ = Matrix.Scale(K, 4)
    for ob in list(root.objects) + list(shells_coll.objects):
        if ob.type == "MESH":
            ob.data.transform(S_)
            for m in ob.modifiers:
                if m.type == "SOLIDIFY":
                    m.thickness *= K
    rig = build_rig(root)
    char_objs = [body, hair, scalp, brows, goatee, briefs] + eyes
    bind(char_objs, rig)
    act = build_pose_action(rig)
    bpy.context.scene.frame_set(1)
    stats = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in char_objs:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        stats[ob.name] = {"verts": len(me.vertices), "tris": len(me.loop_triangles)}
        ev.to_mesh_clear()
    log(json.dumps(stats))
    with open(os.path.join(OUT_DIR, "build_stats.json"), "w") as fh:
        json.dump({"studs_per_ref_px": K, "height_studs": S.HEIGHT_STUDS, "voxel_px": OPT["voxel"],
                   "objects": stats, "bones": [b.name for b in rig.data.bones]}, fh, indent=1)
    blend = os.path.join(OUT_DIR, "Exit6_Male_Base.blend")
    if OPT["render"]:
        cam = setup_render(OPT["samples"])
        render_views(cam, "render")
        if OPT["poses"]:
            sc = bpy.context.scene
            sc.render.resolution_x, sc.render.resolution_y = 600, 1402
            for fi, pname in enumerate(POSES, start=1):
                if pname == "rest":
                    continue
                sc.frame_set(fi)
                render_views(cam, "pose_%s" % pname, {"three_quarter": 35.0})
            sc.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    log("saved", blend)


if __name__ == "__main__":
    main()
