"""Exit 6 male V3.1: anatomical relief maps for the sculpted normal bake.

    python tools/characters/exit6_anatomy_v31.py            # writes build/exit6_v3/polish/anatomy_v31.npz
                                                             # + anatomy_overlay_{front,back,side}.png

The relief is authored the way an artist would paint a displacement layer in an
orthographic view: grooves (muscle separations), domes (muscle bellies) and
blurred blocks (ab segments, pecs), placed in reference-pixel coordinates
measured off assets/characters/reference/male_body_turnaround.png:

  * front view: u = |x| (x = col - 165), v = row
  * back view:  u = |x| (x = 966.5 - col), v = row
  * side view:  u = Y   (Y = col - 700, negative = front), v = row; it shows the
    character's left side and is used for the outward-facing side of arms/legs.

Each view has three layers (torso / arm / leg) so a feature only lands on its
own body region (the arm hangs over the torso side in the side view).
Heights are in reference pixels (1 px = 0.00606 studs ~ 1.9 mm); positive =
raised. The low-poly game mesh is unchanged; this relief only feeds the
normal / cavity bake (polish_exit6_male_v31.py).
"""
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "build", "exit6_v3", "polish")
STEP = 0.25                                   # grid spacing, reference px
VIEWS = {"front": (0.0, 150.0), "back": (0.0, 150.0), "side": (-100.0, 100.0)}
ROWS = (330.0, 1100.0)
REGIONS = ("torso", "arm", "leg")


# ------------------------------------------------------------------ features
def G(pts, depth, sigma, region):
    """groove along a polyline (depth > 0 cuts in; depth < 0 is a ridge)"""
    return dict(k="groove", pts=pts, h=-depth, s=sigma, r=region)


def D(c, r, h, region, p=1.6, rot=0.0):
    """dome: h * (1 - rho^2)^p over an ellipse of radii r=(ru, rv), rotated rot degrees"""
    return dict(k="dome", c=c, rad=r, h=h, p=p, rot=rot, r=region)


def B(poly, h, blur, region):
    """flat-topped block: polygon rasterised then Gaussian-blurred (sigma = blur px)"""
    return dict(k="block", poly=poly, h=h, s=blur, r=region)


FRONT = [
    # ---- chest
    B([(3, 416), (30, 409), (60, 411), (80, 421), (86, 440), (80, 457), (68, 469), (45, 476),
       (20, 475), (4, 469)], 1.6, 5.0, "torso"),
    G([(3, 471), (20, 477), (45, 479), (66, 472), (80, 460), (87, 444)], 1.7, 2.2, "torso"),
    G([(0, 410), (0, 474)], 1.1, 2.4, "torso"),                       # sternal furrow
    G([(9, 396), (40, 393), (76, 398)], -0.7, 2.6, "torso"),           # clavicles
    G([(14, 403), (44, 401), (72, 406)], 0.5, 3.0, "torso"),           # under the clavicle
    G([(83, 405), (87, 428), (88, 452)], 1.2, 2.4, "torso"),           # deltopectoral groove
    D((57, 460), (3.4, 3.0), 0.45, "torso"),                           # areola
    D((57, 459.6), (1.3, 1.2), 0.7, "torso"),                          # nipple
    D((0, 398), (5.0, 4.0), -1.3, "torso"),                            # sternal notch
    G([(6, 396), (14, 372), (22, 352)], -0.6, 3.0, "torso"),           # sternocleidomastoid
    # ---- abs: rounded segments (pillows), tapered intersections, linea alba, semilunar lines
    D((18, 492), (16, 12), 1.7, "torso", p=0.7),
    D((19, 515), (17, 10), 1.7, "torso", p=0.7),
    D((19, 535), (17, 9.5), 1.6, "torso", p=0.7),
    D((17, 570), (16, 24), 0.8, "torso", p=0.8),
    G([(0, 476, 0.7), (0, 500, 1.0), (0, 545, 1.0), (0, 558, 0.6)], 1.3, 2.0, "torso"),
    G([(0, 566, 0.6), (0, 596, 0.2)], 0.6, 2.4, "torso"),
    G([(0, 504.5, 1.0), (14, 505.5, 0.9), (27, 504, 0.55), (35, 501.5, 0.1)], 1.3, 2.0, "torso"),
    G([(0, 525, 1.0), (14, 525.5, 0.9), (28, 524, 0.55), (36, 522, 0.1)], 1.3, 2.0, "torso"),
    G([(0, 546, 0.9), (14, 546.5, 0.75), (28, 545.5, 0.4), (35, 544, 0.05)], 1.0, 2.1, "torso"),
    G([(35, 481, 0.6), (38, 520, 1.0), (37, 556, 0.9), (31, 592, 0.4)], 1.2, 2.3, "torso"),
    D((0, 562), (3.2, 2.4), -3.0, "torso", p=1.0),                     # navel
    G([(-3.4, 560.5), (0, 559.2), (3.4, 560.5)], -0.5, 0.9, "torso"),  # navel upper rim
    # ---- serratus fingers, obliques, iliac (V) line
    D((73, 485), (6.5, 2.6), 0.9, "torso", rot=-28),
    D((75, 496), (6.5, 2.6), 0.9, "torso", rot=-28),
    D((75, 507), (6.0, 2.4), 0.8, "torso", rot=-28),
    G([(68, 491), (80, 484)], 0.7, 1.2, "torso"),
    G([(69, 502), (81, 495)], 0.7, 1.2, "torso"),
    B([(42, 528), (72, 520), (76, 560), (62, 590), (44, 596)], 0.9, 6.0, "torso"),
    G([(68, 556), (60, 582), (46, 600), (28, 620)], 1.6, 2.4, "torso"),
    # ---- arms (front)
    D((108, 432), (22, 34), 1.0, "arm"),
    G([(96, 462), (108, 475), (120, 478), (131, 470)], 1.4, 2.2, "arm"),   # deltoid / biceps
    D((113, 510), (12, 30), 1.6, "arm"),                                    # biceps
    G([(127, 485), (129, 545)], 0.9, 2.4, "arm"),                           # biceps / brachialis
    G([(104, 552), (125, 557)], 0.8, 2.0, "arm"),                           # elbow crease
    D((128, 580), (9, 25), 1.3, "arm"),                                     # brachioradialis
    G([(115, 566), (121, 600), (129, 640)], 0.7, 3.0, "arm"),
    G([(121, 489), (123, 520), (124, 546)], -0.45, 0.9, "arm"),             # cephalic vein
    G([(119, 568), (122, 600), (127, 632), (131, 662)], -0.5, 0.9, "arm"),  # forearm vein
    G([(122, 598), (114, 620), (110, 640)], -0.35, 0.8, "arm"),
    # ---- legs (front)
    D((48, 792), (12, 40), 1.0, "leg"),                                     # rectus femoris
    D((70, 800), (10, 46), 1.2, "leg"),                                     # vastus lateralis
    G([(62, 758), (63, 800), (61, 846)], 0.55, 3.0, "leg"),
    D((32, 830), (10, 18), 1.8, "leg"),                                     # vastus medialis
    G([(23, 800), (31, 812), (40, 842)], 0.50, 2.6, "leg"),
    G([(60, 752), (44, 795), (30, 846)], 0.33, 3.6, "leg"),                  # sartorius
    D((46, 868), (9, 11), 1.2, "leg"),                                      # patella
    G([(38, 852), (46, 849), (54, 852)], 0.39, 2.4, "leg"),
    G([(40, 882), (52, 882)], 0.39, 2.4, "leg"),
    G([(45, 895), (46, 960), (47, 1030)], -0.6, 2.0, "leg"),                # tibia ridge
    D((53, 930), (6, 35), 0.9, "leg"),                                      # tibialis anterior
    D((28, 930), (8, 28), 1.0, "leg"),
    D((68, 915), (6, 25), 0.8, "leg"),
    D((35, 1062), (4, 4), 1.0, "leg"), D((61, 1056), (4, 4), 1.0, "leg"),  # malleoli
]

BACK = [
    # ---- spine, erectors, traps, scapulae, lats
    G([(0, 406, 0.4), (0, 450, 0.75), (0, 500, 1.0), (0, 560, 1.05), (0, 596, 0.7)], 1.5, 2.5, "torso"),
    D((13, 548), (9, 46), 1.4, "torso"),                                    # erector spinae
    B([(0, 392), (40, 390), (72, 398), (42, 420), (14, 462), (0, 482)], 0.8, 6.0, "torso"),  # trapezius
    G([(10, 468), (40, 426), (70, 404)], 0.6, 3.0, "torso"),
    D((45, 448), (20, 22), 1.6, "torso"),                                   # infraspinatus
    D((70, 478), (12, 10), 1.2, "torso"),                                   # teres major
    G([(30, 470), (50, 472), (72, 465)], 0.8, 2.4, "torso"),
    G([(18, 428), (24, 455), (34, 478)], 0.7, 2.6, "torso"),                # scapula medial border
    D((60, 512), (22, 30), 1.0, "torso"),                                   # latissimus
    G([(20, 562), (40, 548), (58, 528), (74, 504)], 0.9, 3.0, "torso"),
    D((12, 600), (12, 8), -0.6, "torso"),                                   # sacral dimples (above briefs)
    # ---- arms (back)
    G([(100, 465), (115, 478), (128, 470)], 1.2, 2.2, "arm"),               # posterior deltoid edge
    D((115, 505), (15, 32), 1.5, "arm"),                                    # triceps
    G([(104, 537, 0.4), (115, 526, 1.0), (126, 537, 0.4)], 0.6, 2.6, "arm"),  # triceps horseshoe
    D((120, 555), (5, 5), 0.8, "arm"),                                      # olecranon
    D((125, 592), (10, 25), 1.0, "arm"),                                    # forearm extensors
    # ---- legs (back)
    D((34, 800), (12, 42), 1.0, "leg"), D((60, 800), (12, 42), 1.0, "leg"),  # hamstrings
    G([(47, 768), (47, 850)], 0.50, 3.0, "leg"),
    G([(30, 868), (47, 870), (64, 868)], 0.66, 3.0, "leg"),                  # knee crease
    D((34, 920), (13, 38), 2.0, "leg"),                                     # gastrocnemius medial
    D((60, 910), (11, 32), 1.7, "leg"),                                     # gastrocnemius lateral
    G([(47, 888), (47, 956)], 0.72, 2.6, "leg"),
    G([(30, 960), (47, 975), (62, 948)], 0.50, 3.1, "leg"),
    G([(47, 990), (47, 1060)], -0.8, 3.0, "leg"),                           # Achilles
    G([(40, 995), (41, 1050)], 0.28, 2.4, "leg"), G([(54, 995), (53, 1050)], 0.28, 2.4, "leg"),
]

SIDE = [
    # ---- arm, outer face (Y negative = front)
    D((20, 430), (38, 35), 1.2, "arm"),                                     # deltoid cap
    G([(-22, 470), (8, 497), (45, 470)], 1.3, 2.3, "arm"),                  # deltoid insertion V
    D((-15, 515), (14, 30), 1.2, "arm"),                                    # biceps
    D((40, 505), (16, 30), 1.5, "arm"),                                     # triceps lateral head
    G([(10, 500), (16, 522), (18, 545)], 1.0, 2.2, "arm"),                  # biceps / triceps
    G([(30, 535), (50, 525)], 0.8, 2.0, "arm"),
    D((-15, 575), (10, 22), 1.0, "arm"),                                    # brachioradialis
    G([(-5, 560), (2, 600), (8, 640)], 0.8, 2.6, "arm"),
    G([(-8, 520), (-6, 545)], -0.4, 0.9, "arm"),
    # ---- torso side (under the arm): serratus / obliques
    D((-40, 500), (10, 4), 0.7, "torso", rot=-30), D((-38, 512), (10, 4), 0.7, "torso", rot=-30),
    B([(-48, 525), (-10, 525), (-5, 590), (-40, 595)], 0.7, 6.0, "torso"),
    # ---- leg, outer face
    D((-5, 800), (16, 46), 1.1, "leg"),                                     # vastus lateralis
    G([(12, 765), (14, 845)], 0.50, 3.6, "leg"),                             # iliotibial band
    D((22, 915), (10, 30), 1.3, "leg"),                                     # gastrocnemius lateral
    G([(2, 900), (6, 1000)], 0.33, 2.9, "leg"),                              # peroneus line
    D((8, 1056), (4, 4), 1.0, "leg"),
]
LAYERS = {"front": FRONT, "back": BACK, "side": SIDE}


# ------------------------------------------------------------------ raster
def _grid(view):
    u0, u1 = VIEWS[view]
    u = np.arange(u0, u1 + 1e-6, STEP)
    v = np.arange(ROWS[0], ROWS[1] + 1e-6, STEP)
    return u, v


def _seg_dist(U, V, a, b):
    """distance to segment a-b and the weight interpolated along it (points may carry a 3rd value)"""
    wa = a[2] if len(a) > 2 else 1.0; wb = b[2] if len(b) > 2 else 1.0
    a = np.asarray(a[:2], float); b = np.asarray(b[:2], float)
    d = b - a; L2 = max(d @ d, 1e-9)
    t = np.clip(((U - a[0]) * d[0] + (V - a[1]) * d[1]) / L2, 0, 1)
    return np.hypot(U - (a[0] + t * d[0]), V - (a[1] + t * d[1])), wa + (wb - wa) * t


def render(view):
    from scipy.ndimage import gaussian_filter
    from PIL import Image, ImageDraw
    u, v = _grid(view)
    U, V = np.meshgrid(u, v)
    out = {r: np.zeros(U.shape, np.float32) for r in REGIONS}
    for f in LAYERS[view]:
        H = out[f["r"]]
        if f["k"] == "groove":
            pts = f["pts"]
            pad = 4 * f["s"]
            us = [p[0] for p in pts]; vs = [p[1] for p in pts]
            m = ((U > min(us) - pad) & (U < max(us) + pad) & (V > min(vs) - pad) & (V < max(vs) + pad))
            dmin = np.full(m.sum(), 1e9); wmin = np.ones(m.sum())
            for a, b in zip(pts[:-1], pts[1:]):
                dd, ww = _seg_dist(U[m], V[m], a, b)
                closer = dd < dmin
                dmin = np.where(closer, dd, dmin); wmin = np.where(closer, ww, wmin)
            H[m] += f["h"] * wmin * np.exp(-0.5 * (dmin / f["s"]) ** 2)
        elif f["k"] == "dome":
            cu, cv = f["c"]; ru, rv = f["rad"]; t = np.radians(f["rot"])
            du = U - cu; dv = V - cv
            a = (du * np.cos(t) + dv * np.sin(t)) / ru
            b = (-du * np.sin(t) + dv * np.cos(t)) / rv
            rho2 = a * a + b * b
            H += f["h"] * np.clip(1 - rho2, 0, 1) ** f["p"]
        elif f["k"] == "block":
            im = Image.new("L", (len(u), len(v)), 0)
            px = [((p[0] - u[0]) / STEP, (p[1] - v[0]) / STEP) for p in f["poly"]]
            ImageDraw.Draw(im).polygon(px, fill=255)
            M = gaussian_filter(np.asarray(im, np.float32) / 255.0, f["s"] / STEP)
            H += f["h"] * M
    return u, v, out


def hillshade(H, az=315, alt=45):
    gy, gx = np.gradient(H, STEP)
    slope = np.arctan(np.hypot(gx, gy) * 1.5)
    aspect = np.arctan2(-gx, gy)
    a = np.radians(az); e = np.radians(alt)
    return np.clip(np.sin(e) * np.cos(slope) + np.cos(e) * np.sin(slope) * np.cos(a - aspect), 0, 1)


def overlay(view, u, v, out, path):
    """reference crop with the relief hillshade multiplied over it (both halves for front/back)"""
    from PIL import Image
    ref = Image.open(os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")).convert("RGB")
    H = sum(out.values())
    hs = hillshade(H)
    hs = 0.35 + 0.65 * hs / max(hs.max(), 1e-6)
    sc = 3.0
    if view in ("front", "back"):
        cx = 165.0 if view == "front" else 966.5
        x0, x1 = -150, 150
        crop = ref.crop((int(cx + x0), int(ROWS[0]), int(cx + x1), int(ROWS[1])))
        crop = crop.resize((int(crop.width * sc), int(crop.height * sc)), Image.LANCZOS)
        cols = np.arange(crop.width) / sc + x0
        if view == "back":
            cols = -cols
        rows = np.arange(crop.height) / sc + ROWS[0]
    else:
        cx = 700.0
        crop = ref.crop((int(cx - 100), int(ROWS[0]), int(cx + 100), int(ROWS[1])))
        crop = crop.resize((int(crop.width * sc), int(crop.height * sc)), Image.LANCZOS)
        cols = np.arange(crop.width) / sc - 100
        rows = np.arange(crop.height) / sc + ROWS[0]
    uu = np.abs(cols) if view != "side" else cols
    iu = np.clip(np.round((uu - u[0]) / STEP).astype(int), 0, len(u) - 1)
    iv = np.clip(np.round((rows - v[0]) / STEP).astype(int), 0, len(v) - 1)
    S = hs[np.ix_(iv, iu)]
    rel = np.abs(H)[np.ix_(iv, iu)] > 0.05
    a = np.asarray(crop, np.float32) / 255.0
    lum = a.mean(2, keepdims=True)
    tint = np.where(rel[..., None], (0.25 * a + 0.75 * lum * 1.3) * S[..., None], a)
    Image.fromarray((np.clip(tint, 0, 1) * 255).astype(np.uint8)).save(path)


def build(write_overlays=True):
    os.makedirs(OUT, exist_ok=True)
    data = {}
    for view in VIEWS:
        u, v, out = render(view)
        data[view + "_u"] = u.astype(np.float32); data[view + "_v"] = v.astype(np.float32)
        for r in REGIONS:
            data["%s_%s" % (view, r)] = out[r]
        if write_overlays:
            overlay(view, u, v, out, os.path.join(OUT, "anatomy_overlay_%s.png" % view))
        print(view, {r: (float(out[r].min()), float(out[r].max())) for r in REGIONS})
    path = os.path.join(OUT, "anatomy_v31.npz")
    np.savez_compressed(path, **data)
    print("wrote", path)
    return path


# ------------------------------------------------------------------ sampling (Blender side)
def load(path=None):
    z = np.load(path or os.path.join(OUT, "anatomy_v31.npz"))
    return {k: z[k] for k in z.files}


def _bilinear(A, u, v, uq, vq):
    fu = np.clip((uq - u[0]) / STEP, 0, len(u) - 1.001)
    fv = np.clip((vq - v[0]) / STEP, 0, len(v) - 1.001)
    i0 = fu.astype(int); j0 = fv.astype(int); tu = fu - i0; tv = fv - j0
    inside = (uq >= u[0]) & (uq <= u[-1]) & (vq >= v[0]) & (vq <= v[-1])
    r = (A[j0, i0] * (1 - tu) * (1 - tv) + A[j0, i0 + 1] * tu * (1 - tv)
         + A[j0 + 1, i0] * (1 - tu) * tv + A[j0 + 1, i0 + 1] * tu * tv)
    return np.where(inside, r, 0.0)


def relief(maps, Q, N, region_w):
    """displacement (ref px) per vertex.
    Q: (n,3) reference coords (x, Y, row); N: (n,3) unit normals (Blender axes, -Y = front);
    region_w: dict region -> (n,) soft membership."""
    wf = np.clip(-N[:, 1], 0, 1) ** 2
    wb = np.clip(N[:, 1], 0, 1) ** 2
    ws = np.clip(N[:, 0] * np.sign(Q[:, 0] + 1e-9), 0, 1) ** 2      # outward-facing side only
    tot = wf + wb + ws + N[:, 2] ** 2 + 1e-6
    out = np.zeros(len(Q))
    for view, w, uq in (("front", wf, np.abs(Q[:, 0])), ("back", wb, np.abs(Q[:, 0])), ("side", ws, Q[:, 1])):
        u = maps[view + "_u"]; v = maps[view + "_v"]
        acc = np.zeros(len(Q))
        for r in REGIONS:
            acc += region_w[r] * _bilinear(maps["%s_%s" % (view, r)], u, v, uq, Q[:, 2])
        out += (w / tot) * acc
    return out


if __name__ == "__main__":
    build()
