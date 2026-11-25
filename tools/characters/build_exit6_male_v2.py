"""Exit 6 male V2: anatomical base mesh, fitted onto the v1 measurements and rig.

    blender -b --factory-startup -P tools/characters/build_exit6_male_v2.py -- [--stage=face|full] [--samples=N]

Continues from the v1 build: the v1 R15 rig, skin weights, measured spec,
hair / brow / goatee generators and render setup are reused as is. What
changes is the skin surface:

  1. MPFB / MakeHuman hm08 base mesh (CC0, quad topology with real eyelids,
     nostrils, lips, ears, hands and feet), set up with macro sliders and
     face targets from exit6_male_v2_spec.py.
  2. Skeletal fit: linear-blend skinning with MPFB's game-engine weights,
     each bone aimed and stretched onto the v1 R15 joints; head scaled to the
     reference landmarks; hands posed (palm roll, finger curl).
  3. Low-frequency body fit: the v1 body silhouette (IoU 0.91 to the
     reference) pulls the torso and limbs via a heavily smoothed displacement
     field, so MPFB's anatomy stays and the measured volume is matched.
  4. Eyes from MPFB, brows / goatee / scalp / twists re-grown on the new
     head, briefs re-cut, v1 R15 weights transferred, bound to the v1 rig.

--stage=face stops after step 2 plus brows/goatee/hair and renders the face
close-up comparisons only (fast iteration).
"""
import bpy, bmesh, math, os, sys, time, json, gzip, addon_utils
import numpy as np
from importlib import import_module
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib
import exit6_male_spec as S
import exit6_male_v2_spec as S2
import build_exit6_male as B
import exit6_hair_v2 as H
importlib.reload(S2)

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "characters", "exit6_male")
REN_DIR = os.path.join(OUT_DIR, "renders_v2")
WORK = os.path.join(REPO, "build", "exit6_v2")
os.makedirs(REN_DIR, exist_ok=True); os.makedirs(WORK, exist_ok=True)
V1_BLEND = os.path.join(OUT_DIR, "Exit6_Male_Base.blend")
V2_BLEND = os.path.join(OUT_DIR, "Exit6_Male_V2.blend")

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {"stage": "full", "samples": 96, "hair": True, "render": True}
for a in ARGV:
    if a.startswith("--stage="): OPT["stage"] = a.split("=")[1]
    if a.startswith("--samples="): OPT["samples"] = int(a.split("=")[1])
    if a == "--no-hair": OPT["hair"] = False
    if a == "--no-render": OPT["render"] = False

K = B.K
B.REN_DIR = REN_DIR
SOLE = S.SOLE
T0 = time.time()


def log(*a):
    print("[exit6v2 %6.1fs]" % (time.time() - T0), *a, flush=True)


def norm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-12)


def px(xf, xs, y):
    """reference px (front x, side x, row) -> studs"""
    return np.array([xf - S.CX, xs - S.CS, SOLE - y]) * K


# ------------------------------------------------------------------ MPFB
class MP:
    pass


def mpfb():
    name = next(m.__name__ for m in addon_utils.modules() if m.__name__.endswith(".mpfb"))
    addon_utils.enable(name, default_set=True)
    MP.name = name
    MP.HS = import_module(name + ".services.humanservice").HumanService
    MP.TS = import_module(name + ".services.targetservice").TargetService
    MP.LS = import_module(name + ".services.locationservice").LocationService
    MP.data = MP.LS.get_mpfb_data()
    MP.udata = MP.LS.get_user_data()
    return MP


def expand_targets(tab):
    out = {}
    for k, w in tab.items():
        if k.startswith("lr:"):
            folder, nm = k[3:].split("/")
            out["%s/l-%s" % (folder, nm)] = w
            out["%s/r-%s" % (folder, nm)] = w
        else:
            out[k] = w
    return out


def create_human():
    macro = dict(S2.MACRO)
    bm = MP.HS.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                            feet_on_ground=True, scale=0.1, macro_detail_dict=macro)
    tdir = os.path.join(MP.data, "targets")
    for key, w in expand_targets(S2.FACE_TARGETS).items():
        MP.TS.load_target(bm, os.path.join(tdir, key + ".target.gz"), weight=w)
    # bake the shape-key mix into plain coordinates
    kb = bm.data.shape_keys.key_blocks
    n = len(bm.data.vertices)

    def co(k):
        a = np.zeros(n * 3, np.float32); k.data.foreach_get("co", a); return a.reshape(-1, 3).astype(float)
    basis = co(kb[0]); mix = basis.copy()
    find_landmark_indices(bm, basis)
    for k in kb[1:]:
        if k.value != 0:
            mix += k.value * (co(k) - co(k.relative_key))
    bm.shape_key_clear()
    bm.data.vertices.foreach_set("co", mix.ravel().astype(np.float32))
    bm.data.update()
    bm.name = "Exit6_Male_Body"
    bm.data.name = "Exit6_Male_Body"
    return bm


LMI = {}


def boundary_verts(me):
    e = np.zeros(len(me.edges) * 2, int); me.edges.foreach_get("vertices", e); e = e.reshape(-1, 2)
    cnt = np.zeros(len(e), int)
    key = {tuple(sorted(x)): i for i, x in enumerate(e.tolist())}
    for p in me.polygons:
        vs = list(p.vertices)
        for k in range(len(vs)):
            cnt[key[tuple(sorted((vs[k], vs[(k + 1) % len(vs)])))]] += 1
    return np.unique(e[cnt == 1].ravel())


def find_landmark_indices(bm, P):
    """Stable vertex indices of face landmarks, picked on the neutral basis mesh (+X = left)."""
    g = vgroup_members(bm)
    nv = len(P)

    def m(name):
        x = np.zeros(nv, bool); x[g[name]] = True; return x
    body, mid, lips, ears = m("body"), m("Mid"), m("lips"), m("ears")
    H = P[body, 2].max()
    head = body & (P[:, 2] > 0.84 * H)
    L = {}
    c = np.nonzero(head & mid & ~lips)[0]
    L["nose_tip"] = c[np.argmin(P[c, 1])]
    nt = P[L["nose_tip"]]
    li = np.nonzero(lips & body & (P[:, 0] > 0))[0]
    L["mouth_corner"] = li[np.argmax(P[li, 0])]
    mz = P[L["mouth_corner"], 2]
    lm = np.nonzero(lips & body & mid)[0]
    up = lm[P[lm, 2] > mz]; lo = lm[P[lm, 2] < mz]
    L["lip_up_front"] = up[np.argmin(P[up, 1])]
    L["lip_lo_front"] = lo[np.argmin(P[lo, 1])]
    L["lip_up_top"] = up[np.argmax(P[up, 2])]
    lo_out = lo[P[lo, 1] < P[L["lip_lo_front"], 1] + 0.006]
    L["lip_lo_bot"] = lo_out[np.argmin(P[lo_out, 2])]
    c = np.nonzero(body & mid & (P[:, 2] < nt[2]) & (P[:, 2] > P[L["lip_up_top"], 2]) & (P[:, 1] < nt[1] + 0.03))[0]
    L["subnasale"] = c[np.argmax(P[c, 1])]
    eyeC = P[g["helper-l-eye"]].mean(0)
    lash = np.concatenate([g["helper-l-eyelashes-1"], g["helper-l-eyelashes-2"]])
    L["eye_in"] = lash[np.argmin(P[lash, 0])]; L["eye_out"] = lash[np.argmax(P[lash, 0])]
    cx = (P[L["eye_in"], 0] + P[L["eye_out"], 0]) / 2
    cen = lash[np.abs(P[lash, 0] - cx) < 0.004]
    L["lid_up"] = cen[np.argmax(P[cen, 2])]; L["lid_lo"] = cen[np.argmin(P[cen, 2])]
    ez = eyeC[2]
    c = np.nonzero(body & mid & (P[:, 2] > ez - 0.01) & (P[:, 2] < ez + 0.012) & (P[:, 1] < nt[1] + 0.04))[0]
    L["sellion"] = c[np.argmax(P[c, 1])]
    c = np.nonzero(body & mid & (P[:, 2] > ez + 0.012) & (P[:, 2] < ez + 0.035) & (P[:, 1] < nt[1] + 0.05))[0]
    L["glabella"] = c[np.argmin(P[c, 1])]
    c = np.nonzero(body & mid & (P[:, 2] < P[L["lip_lo_bot"], 2]) & (P[:, 2] > ez - 0.2) & (P[:, 1] < nt[1] + 0.05))[0]
    pog = P[c, 1].min()
    L["pogonion"] = c[np.argmin(P[c, 1])]
    c2 = c[P[c, 1] < pog + 0.012]
    L["menton"] = c2[np.argmin(P[c2, 2])]
    nz_ = np.nonzero(body & ~ears & ~mid & (P[:, 0] > 0) & (np.linalg.norm(P - nt, axis=1) < 0.035)
                     & (P[:, 2] < nt[2] + 0.004) & (P[:, 2] > P[L["subnasale"], 2] - 0.004))[0]
    L["alar"] = nz_[np.argmax(P[nz_, 0])]
    earC = P[g["ears"]][P[g["ears"], 0] > 0].mean(0)
    for name in ("jaw", "zygion"):
        if name == "jaw":
            z0 = P[L["menton"], 2] + 0.45 * (mz - P[L["menton"], 2])
        else:
            z0 = (ez + nt[2]) / 2
        c = np.nonzero(body & ~ears & (P[:, 0] > 0) & (np.abs(P[:, 2] - z0) < 0.004) & (P[:, 1] < earC[1] - 0.01))[0]
        L[name] = c[np.argmax(P[c, 0])]
    L["skull_top"] = np.nonzero(body)[0][np.argmax(P[body, 2])]
    gz = P[L["glabella"], 2]; tz = P[L["skull_top"], 2]
    for name, f in (("forehead_lo", 0.35), ("forehead_hi", 0.65)):
        z0 = gz + f * (tz - gz)
        c = np.nonzero(body & mid & (np.abs(P[:, 2] - z0) < 0.004) & (P[:, 1] < nt[1] + 0.08))[0]
        L[name] = c[np.argmin(P[c, 1])]
    z0 = P[L["menton"], 2] + 0.008
    c = np.nonzero(body & (P[:, 0] > 0.008) & (np.abs(P[:, 2] - z0) < 0.003) & (P[:, 1] < pog + 0.02))[0]
    L["chin_lat"] = c[np.argmax(P[c, 0])] if len(c) else L["menton"]
    c = np.nonzero(body & mid & (np.abs(P[:, 2] - (ez + 0.03)) < 0.01))[0]
    L["occiput"] = c[np.argmax(P[c, 1])]
    for k, v in L.items():
        LMI[k] = int(v)
    from mathutils.kdtree import KDTree
    kd = KDTree(nv)
    for i in range(nv):
        kd.insert(Vector(P[i]), i)
    kd.balance()
    mir = {}
    for k in ("eye_in", "eye_out", "lid_up", "lid_lo", "alar", "mouth_corner", "jaw", "zygion", "chin_lat"):
        _, j, d = kd.find(Vector(P[LMI[k]] * np.array([-1, 1, 1])))
        mir[k] = int(j)
    LMI["_mirror"] = mir
    LMI["mouth_l"] = LMI["mouth_corner"]; LMI["mouth_r"] = mir["mouth_corner"]
    LMI["nose"] = LMI["nose_tip"]; LMI["chin"] = LMI["menton"]
    log("landmark vertices", {k: v for k, v in LMI.items() if k != "_mirror"})


def vgroup_members(ob):
    me = ob.data
    names = {g.index: g.name for g in ob.vertex_groups}
    mem = {g.name: [] for g in ob.vertex_groups}
    for v in me.vertices:
        for g in v.groups:
            if g.weight > 0:
                mem[names[g.group]].append(v.index)
    return {k: np.array(v, int) for k, v in mem.items()}


def mpfb_weights(nv):
    path = os.path.join(MP.data, "rigs", "standard", "weights.game_engine.json")
    d = json.load(open(path))["weights"]
    bones = sorted(d.keys())
    W = np.zeros((nv, len(bones)))
    for j, b in enumerate(bones):
        for vi, w in d[b]:
            if vi < nv:
                W[vi, j] = w
    return bones, W


# --------------------------------------------------------- skeletal fit
def rot_between(a, b):
    a, b = norm(a), norm(b)
    v = np.cross(a, b); c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3) if c > 0 else -np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def rot_axis(axis, ang):
    return np.array(Matrix.Rotation(ang, 3, Vector(norm(axis))))


def affine(A, h_s, h_t):
    return (A, h_t - A @ h_s)


def compose(T2, T1):
    """T2 after T1"""
    A2, b2 = T2; A1, b1 = T1
    return (A2 @ A1, A2 @ b1 + b2)


def about(R, c):
    """rotation R about point c"""
    return (R, c - R @ c)


def v1_joints():
    J = {}
    for k in ("root", "waist", "neck", "head_top"):
        J[k] = B.jp(k)
    for side in ("Left", "Right"):
        for k in ("shoulder", "elbow", "wrist", "hand_tip", "hip", "knee", "ankle", "toe"):
            J[(side, k)] = B.jp(k, side)
    return J


def skeletal_fit(bm, groups):
    me = bm.data
    nv = len(me.vertices)
    P = np.zeros(nv * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    body = np.zeros(nv, bool); body[groups["body"]] = True
    jc = {k[6:]: P[v].mean(0) for k, v in groups.items() if k.startswith("joint-") and len(v)}
    # global scale: sole->skull top = HEIGHT_STUDS
    top = P[body, 2].max()
    g = S.HEIGHT_STUDS / top
    P *= g
    for k in jc:
        jc[k] = jc[k] * g
    T = v1_joints()
    bones, W = mpfb_weights(nv)
    BI_ = {b: i for i, b in enumerate(bones)}
    Tr = {}
    # MPFB left = +X; v1 "Left" = +X as well
    side_of = {"l": "Left", "r": "Right"}
    # ---- torso: vertical scale + y shear, hips -> v1 hips, neck -> v1 neck
    hip_s = (jc["l-upper-leg"] + jc["r-upper-leg"]) / 2
    hip_t = (T[("Left", "hip")] + T[("Right", "hip")]) / 2
    neck_s = jc["neck"]; neck_t = T["neck"]
    dz = neck_s[2] - hip_s[2]
    sz = (neck_t[2] - hip_t[2]) / dz
    shy = ((neck_t[1] - hip_t[1]) - (neck_s[1] - hip_s[1])) / dz
    A = np.array([[1, 0, 0], [0, 1, shy], [0, 0, sz]])
    Ttorso = affine(A, hip_s, hip_t)
    for b in ("Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01"):
        Tr[b] = Ttorso
    # ---- head: landmark scale
    eye_s = (jc["l-eye"] + jc["r-eye"]) / 2
    mouth_s = jc["mouth"]
    eye_t = np.array([0, (S.EYE_FRONT_SIDE_X - S.CS + 9.5) * K, (SOLE - S2.LM["eye"]) * K])
    top_t = (SOLE - S.SKULL_TOP) * K
    mouth_tz = (SOLE - S2.LM["mouth"]) * K
    hz = (top_t - mouth_tz) / (P[body, 2].max() - mouth_s[2])
    hx = (2 * S.EYE_X * K) / abs(jc["l-eye"][0] - jc["r-eye"][0]) * S2.HEAD_WIDTH_MULT
    hy = hx * S2.HEAD_DEPTH_MULT
    Ah = np.diag([hx, hy, hz])
    # anchor: eye centre (x, y) and the top/mouth span in z
    anchor_s = np.array([0, eye_s[1], mouth_s[2]])
    anchor_t = np.array([0, eye_t[1], mouth_tz])
    Thead = affine(Ah, anchor_s, anchor_t)
    Tr["head"] = Thead
    log("head scale", hx, hy, hz, "torso sz", sz)
    # ---- arms
    for s in ("l", "r"):
        side = side_of[s]
        Tc = Ttorso
        cla_h = Tc[0] @ jc[s + "-clavicle"] + Tc[1]
        sh_t = T[(side, "shoulder")]; el_t = T[(side, "elbow")]; wr_t = T[(side, "wrist")]
        tip_t = T[(side, "hand_tip")]

        def aim(h_s, t_s, h_t, t_t, axial=True):
            ds = t_s - h_s; dt = t_t - h_t
            R = rot_between(ds, dt)
            lam = np.linalg.norm(dt) / np.linalg.norm(ds)
            dn = norm(ds)
            Sx = np.eye(3) + (lam - 1) * np.outer(dn, dn) if axial else np.eye(3) * lam
            return affine(R @ Sx, h_s, h_t), R
        Tr["clavicle_" + s], _ = aim(jc[s + "-clavicle"], jc[s + "-shoulder"], cla_h, sh_t)
        Tr["upperarm_" + s], Rua = aim(jc[s + "-shoulder"], jc[s + "-elbow"], sh_t, el_t)
        Tla, Rla = aim(jc[s + "-elbow"], jc[s + "-hand"], el_t, wr_t)
        # hand: uniform scale, aim wrist -> middle fingertip at v1 hand tip, roll the palm
        tip_s = jc[s + "-finger-3-4"]
        wr_s = jc[s + "-hand"]
        lam = np.linalg.norm(tip_t - wr_t) / np.linalg.norm(tip_s - wr_s)
        R0 = rot_between(tip_s - wr_s, tip_t - wr_t)
        across = jc[s + "-finger-2-1"] - jc[s + "-finger-5-1"]
        n_s = norm(np.cross(tip_s - wr_s, across))
        if n_s[2] > 0:          # MPFB A-pose palms face down
            n_s = -n_s
        axis = norm(tip_t - wr_t)
        sgn = 1 if side == "Left" else -1
        inward = np.array([-sgn, 0, 0.0])
        back = np.array([0, 1.0, 0])
        a = math.radians(S2.PALM_BACK_DEG)
        n_t = norm(math.cos(a) * inward + math.sin(a) * back)
        n_r = R0 @ n_s
        p1 = norm(n_r - (n_r @ axis) * axis); p2 = norm(n_t - (n_t @ axis) * axis)
        roll = math.atan2(np.cross(p1, p2) @ axis, p1 @ p2)
        Rroll = rot_axis(axis, roll)
        Rh = Rroll @ R0
        Thand = affine(Rh * lam, wr_s, wr_t)
        # half of the roll goes into the forearm to spread the twist
        Tr["lowerarm_" + s] = compose(about(rot_axis(norm(wr_t - el_t), roll * 0.5), el_t), Tla)
        Tr["hand_" + s] = Thand
        palm_n = Rh @ n_s
        for f, fname in ((2, "index"), (3, "middle"), (4, "ring"), (5, "pinky"), (1, "thumb")):
            Tf = Thand
            for seg in (1, 2, 3):
                bname = {1: "thumb", 2: "index", 3: "middle", 4: "ring", 5: "pinky"}[f] + "_0%d_%s" % (seg, s)
                h = jc["%s-finger-%d-%d" % (s, f, seg)]; t = jc["%s-finger-%d-%d" % (s, f, seg + 1)]
                hw = Tf[0] @ h + Tf[1]; tw = Tf[0] @ t + Tf[1]
                d = norm(tw - hw)
                ax = norm(np.cross(d, palm_n))
                if f == 1:
                    ang = S2.THUMB_CURL[seg - 1]
                else:
                    ang = S2.FINGER_CURL[seg - 1] * S2.FINGER_CURL_SCALE[fname]
                Rc = rot_axis(ax, math.radians(ang))
                Tf = compose(about(Rc, hw), Tf)
                Tr[bname] = Tf
    # ---- legs
    for s in ("l", "r"):
        side = side_of[s]
        hip_t1 = T[(side, "hip")]; kn_t = T[(side, "knee")]; an_v1 = T[(side, "ankle")]
        foot_idx = np.nonzero((W[:, BI_["foot_" + s]] + W[:, BI_["ball_" + s]]) > 0.5)[0]
        foot_idx = foot_idx[body[foot_idx]]
        flen_s = np.ptp(P[foot_idx, 1])
        flen_t = (S.FOOT[0][0] - S.FOOT[-1][0] + 18) * K
        sf = flen_t / flen_s
        an_s = jc[s + "-ankle"]
        an_z = an_s[2] * sf
        # anatomical ankle on the v1 knee->ankle axis at that height
        u = (kn_t[2] - an_z) / (kn_t[2] - an_v1[2])
        an_t = kn_t + u * (an_v1 - kn_t)

        def aim2(h_s, t_s, h_t, t_t):
            ds = t_s - h_s; dt = t_t - h_t
            R = rot_between(ds, dt)
            lam = np.linalg.norm(dt) / np.linalg.norm(ds)
            dn = norm(ds)
            return affine(R @ (np.eye(3) + (lam - 1) * np.outer(dn, dn)), h_s, h_t)
        Tr["thigh_" + s] = aim2(jc[s + "-upper-leg"], jc[s + "-knee"], hip_t1, kn_t)
        Tr["calf_" + s] = aim2(jc[s + "-knee"], an_s, kn_t, an_t)
        # foot: uniform scale about the ankle, no rotation; heel line follows v1 heel x
        Tf = affine(np.eye(3) * sf, an_s, an_t)
        Tr["foot_" + s] = Tf
        Tr["ball_" + s] = Tf
    missing = [b for b in bones if b not in Tr]
    for b in missing:
        Tr[b] = Ttorso
    # ---- blend
    Wn = W.copy()
    nz = Wn.sum(1) > 1e-6
    # helpers without weights: borrow from the nearest weighted vertex
    if (~nz).any():
        from mathutils.kdtree import KDTree
        kd = KDTree(int(nz.sum()))
        idx = np.nonzero(nz)[0]
        for i, j in enumerate(idx):
            kd.insert(Vector(P[j]), i)
        kd.balance()
        for i in np.nonzero(~nz)[0]:
            _, k_, _ = kd.find(Vector(P[i]))
            Wn[i] = Wn[idx[k_]]
    Wn /= Wn.sum(1, keepdims=True)
    out = np.zeros_like(P)
    for j, b in enumerate(bones):
        w = Wn[:, j]
        m = w > 0
        if not m.any():
            continue
        A_, b_ = Tr[b]
        out[m] += w[m, None] * (P[m] @ A_.T + b_)
    me.vertices.foreach_set("co", out.ravel().astype(np.float32))
    me.update()
    return bones, Wn


# ------------------------------------------------------------- head fit
def _smooth_rows(rows, vals, sigma):
    out = np.zeros_like(vals)
    for i, r in enumerate(rows):
        w = np.exp(-0.5 * ((rows - r) / sigma) ** 2)
        out[i] = (w * vals).sum() / w.sum()
    return out


def head_landmarks(Xp, Yp, Rw, groups, body, wH):
    """Landmark rows/positions on the current mesh, all in reference px."""
    ears = np.zeros(len(Xp), bool); ears[groups["ears"]] = True
    top = Rw[body].min()
    eyeL = groups["helper-l-eye"]; eyeR = groups["helper-r-eye"]
    eye = (Rw[eyeL].mean() + Rw[eyeR].mean()) / 2
    eye_x = (np.abs(Xp[eyeL].mean()) + np.abs(Xp[eyeR].mean())) / 2
    mouth = (Rw[LMI["mouth_l"]] + Rw[LMI["mouth_r"]]) / 2
    mouth_hw = (Xp[LMI["mouth_l"]] - Xp[LMI["mouth_r"]]) / 2
    return dict(top=top, eye=eye, eye_x=eye_x, nose=Rw[LMI["nose"]], nose_y=Yp[LMI["nose"]], mouth=mouth,
                mouth_hw=mouth_hw, chin=Rw[LMI["chin"]], chin_y=Yp[LMI["chin"]], ears=ears)


def tps_fit(src, dst, smooth):
    n = len(src)
    Kr = np.linalg.norm(src[:, None] - src[None], axis=2) + np.eye(n) * smooth
    Pm = np.hstack([np.ones((n, 1)), src])
    A = np.zeros((n + 4, n + 4)); A[:n, :n] = Kr; A[:n, n:] = Pm; A[n:, :n] = Pm.T
    rhs = np.zeros((n + 4, 3)); rhs[:n] = dst - src
    sol = np.linalg.solve(A, rhs)
    return src, sol[:n], sol[n:]


def tps_apply(model, X):
    c, w, a = model
    out = np.zeros_like(X)
    for i0 in range(0, len(X), 4000):
        x = X[i0:i0 + 4000]
        r = np.linalg.norm(x[:, None] - c[None], axis=2)
        out[i0:i0 + 4000] = x + r @ w + np.hstack([np.ones((len(x), 1)), x]) @ a
    return out


def head_points(Q, groups):
    """(name, index-or-None, source point) for every landmark, both sides."""
    out = []
    for k, tgt in S2.LANDMARKS.items():
        if k == "eye_c":
            for side, gname in ((1, "helper-l-eye"), (-1, "helper-r-eye")):
                out.append((k, side, Q[groups[gname]].mean(0), tgt))
            continue
        if k == "ear":
            for side in (1, -1):
                e = groups["ears"][(Q[groups["ears"], 0] * side) > 0]
                out.append((k, side, Q[e].mean(0), tgt))
            continue
        out.append((k, 1, Q[LMI[k]].copy(), tgt))
        if k in LMI["_mirror"]:
            out.append((k, -1, Q[LMI["_mirror"][k]].copy(), tgt))
    return out


def head_fit(hm, groups, bones, Wn):
    """Thin-plate warp of the head onto the measured reference landmarks (ref px space)."""
    me = hm.data
    nv = len(me.vertices)
    P = np.zeros(nv * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    body = np.zeros(nv, bool); body[groups["body"]] = True
    wH = np.clip(Wn[:, bones.index("head")] + 0.5 * Wn[:, bones.index("neck_01")], 0, 1)
    Q = np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)   # (x, Y, row) in ref px
    pts = head_points(Q, groups)
    src = np.array([p for _, _, p, _ in pts])
    dst = np.array([[side * t[0], p[1] if t[2] is None else t[2], t[1]] for _, side, p, t in pts])
    names = ["%s%s" % (k, "" if side > 0 else "_R") for k, side, _, _ in pts]
    # neck anchors: keep the neck base where the skeletal fit put it
    ring = np.nonzero(body & (np.abs(Q[:, 2] - 372) < 3))[0][::7]
    src = np.vstack([src, Q[ring]]); dst = np.vstack([dst, Q[ring]])
    err0 = np.linalg.norm(src[:len(names)] - dst[:len(names)], axis=1)
    log("landmark offsets before warp (px):", {n: round(float(e), 1) for n, e in zip(names, err0)})
    model = tps_fit(src, dst, S2.TPS_SMOOTH)
    Qn = tps_apply(model, Q)
    Q2 = Q + (Qn - Q) * wH[:, None]
    P2 = np.stack([Q2[:, 0] * K, Q2[:, 1] * K, (SOLE - Q2[:, 2]) * K], 1)
    me.vertices.foreach_set("co", P2.ravel().astype(np.float32)); me.update()
    after = head_points(Q2, groups)
    err1 = [np.linalg.norm(p - d) for (_, _, p, _), d in zip(after, dst[:len(names)])]
    log("landmark error after warp (px): mean %.2f max %.2f" % (np.mean(err1), np.max(err1)))
    return dict(zip(names, err1))


def face_relax(hm, groups, bones, Wn, iters=6):
    """Relax the cheeks / jaw (lumps from targets + warp) away from eyes, nose and lips."""
    me = hm.data
    nv = len(me.vertices)
    P = np.zeros(nv * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    Q = np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)
    body = np.zeros(nv, bool); body[groups["body"]] = True
    lips = np.zeros(nv, bool); lips[groups["lips"]] = True
    ears = np.zeros(nv, bool); ears[groups["ears"]] = True
    wH = Wn[:, bones.index("head")]
    def far(c, r):
        d = np.linalg.norm((Q[:, [0, 2]] - c[[0, 2]]), axis=1)
        return np.clip((d - r) / 5.0, 0, 1)
    m = body & ~lips & ~ears & (wH > 0.8) & (Q[:, 2] > 270) & (Q[:, 2] < 340)
    w = m.astype(float)
    w *= far(Q[LMI["nose_tip"]], 13)
    w *= far(Q[LMI["mouth_corner"]], 6) * far(Q[LMI["_mirror"]["mouth_corner"]], 6)
    w *= far((Q[LMI["lip_up_front"]] + Q[LMI["lip_lo_front"]]) / 2, 15)
    for gname in ("helper-l-eye", "helper-r-eye"):
        w *= far(Q[groups[gname]].mean(0), 13)
    edges, _ = mesh_adjacency(me)
    deg = np.bincount(edges.ravel(), minlength=nv).astype(float)
    for _ in range(iters):
        acc = np.zeros_like(P)
        np.add.at(acc, edges[:, 0], P[edges[:, 1]]); np.add.at(acc, edges[:, 1], P[edges[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None]
        P = P + (avg - P) * (0.5 * w)[:, None]
    me.vertices.foreach_set("co", P.ravel().astype(np.float32)); me.update()


# -------------------------------------------------------- low-freq fit
def mesh_adjacency(me):
    nv = len(me.vertices)
    e = np.zeros(len(me.edges) * 2, int); me.edges.foreach_get("vertices", e); e = e.reshape(-1, 2)
    return e, nv


def laplacian_smooth_field(F, edges, nv, iters, fixed=None):
    deg = np.bincount(edges.ravel(), minlength=nv).astype(float)
    for _ in range(iters):
        acc = np.zeros_like(F)
        np.add.at(acc, edges[:, 0], F[edges[:, 1]])
        np.add.at(acc, edges[:, 1], F[edges[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None] if F.ndim == 2 else acc / np.maximum(deg, 1)
        F = 0.5 * F + 0.5 * avg
        if fixed is not None:
            F[fixed[0]] = fixed[1]
    return F


def body_fit(bm, v1_body, bones, Wn, body_mask):
    me = bm.data
    nv = len(me.vertices)
    P = np.zeros(nv * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    me.update()
    N = np.zeros(nv * 3); me.vertices.foreach_get("normal", N); N = N.reshape(-1, 3)
    mask = np.zeros(nv)
    for b, w in S2.BODY_FIT.items():
        if b in bones:
            mask += Wn[:, bones.index(b)] * w
    mask[~body_mask] = 0
    Qk = np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)
    for (x, Y, row), r in S2.FIT_FADE:
        for sx in ((1, -1) if x else (1,)):
            d = np.linalg.norm(Qk - np.array([x * sx, Y, row]), axis=1)
            mask *= np.clip((d - r * 0.5) / (r * 0.5), 0, 1) * 0.85 + 0.15 * (d > r * 0.5)
    edges, _ = mesh_adjacency(me)
    mask = laplacian_smooth_field(mask, edges, nv, 30)
    sv = B.mesh_arrays(v1_body)
    v1_body.data.calc_loop_triangles()
    lt = np.zeros(len(v1_body.data.loop_triangles) * 3, np.int32)
    v1_body.data.loop_triangles.foreach_get("vertices", lt)
    bvh = BVHTree.FromPolygons(sv.tolist(), lt.reshape(-1, 3).tolist())
    D = np.zeros((nv, 3)); conf = np.zeros(nv)
    for i in np.nonzero(mask > 0.02)[0]:
        p = Vector(P[i]); n = Vector(N[i])
        best = None
        for sgn in (1, -1):
            hit = bvh.ray_cast(p, n * sgn, S2.BODY_FIT_MAX)
            if hit[0] is not None and (best is None or hit[3] < best[1]):
                best = (np.array(hit[0]), hit[3])
        if best is not None:
            D[i] = best[0] - P[i]; conf[i] = 1
    # confidence-weighted smoothing of the displacement
    Dw = D * conf[:, None]
    for it in range(S2.BODY_FIT_SMOOTH_ITERS):
        Dw = laplacian_smooth_field(Dw, edges, nv, 1)
        conf = laplacian_smooth_field(conf, edges, nv, 1)
    Ds = Dw / np.maximum(conf, 0.05)[:, None]
    P2 = P + Ds * mask[:, None]
    me.vertices.foreach_set("co", P2.ravel().astype(np.float32))
    me.update()
    log("body fit: mean |d| %.4f studs over %d verts" % (np.linalg.norm(Ds[mask > 0.1], axis=1).mean(), (mask > 0.1).sum()))
    return mask


def shoulder_relax(hm, groups):
    """Taubin relax around the shoulder caps: rounds the corner the arm rotation leaves."""
    me = hm.data
    nv = len(me.vertices)
    P = np.zeros(nv * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    Q = np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)
    body = np.zeros(nv, bool); body[groups["body"]] = True
    w = np.zeros(nv)
    (x, Y, row), r = S2.SHOULDER_RELAX
    for sx in (1, -1):
        d = np.linalg.norm(Q - np.array([x * sx, Y, row]), axis=1)
        w = np.maximum(w, np.clip(1 - d / r, 0, 1) ** 0.7)
    w[~body] = 0
    edges, _ = mesh_adjacency(me)
    deg = np.bincount(edges.ravel(), minlength=nv).astype(float)

    def lap(X):
        acc = np.zeros_like(X)
        np.add.at(acc, edges[:, 0], X[edges[:, 1]]); np.add.at(acc, edges[:, 1], X[edges[:, 0]])
        return acc / np.maximum(deg, 1)[:, None] - X
    for _ in range(S2.SHOULDER_RELAX_ITERS):
        P = P + 0.5 * w[:, None] * lap(P)
        P = P - 0.53 * w[:, None] * lap(P)
    me.vertices.foreach_set("co", P.ravel().astype(np.float32)); me.update()


# ------------------------------------------------------------ rendering
def face_cameras():
    """close-up crops matching the reference crops in build/exit6_v2/ref_face_crops.png"""
    return {
        "front": dict(az=0.0, cx=0.0, top=196, bottom=350, width=120),
        "three_quarter": dict(az=-35.0, cx=None, top=196, bottom=350, width=150),
        "side": dict(az=90.0, cx=-5.0, top=196, bottom=350, width=130),
    }


REF_CROPS = {"front": (106, 196, 226, 350), "three_quarter": (380, 196, 530, 350), "side": (630, 196, 760, 350)}


def render_face(cam, prefix, scale=4):
    sc = bpy.context.scene
    out = {}
    for name, c in face_cameras().items():
        a = math.radians(c["az"])
        h = (c["bottom"] - c["top"])
        zc = (SOLE - (c["top"] + c["bottom"]) / 2) * K
        right = np.array([math.cos(a), math.sin(a), 0])
        if c["cx"] is None:
            # centre on the head axis (x=0, y=v1 head centre)
            u = np.array([0, 12 * K, 0]) @ right
        else:
            u = c["cx"] * K
        loc = np.array([math.sin(a) * 30, -math.cos(a) * 30, zc]) + right * u
        cam.location = loc
        cam.rotation_euler = (math.radians(90), 0, a)
        cam.data.ortho_scale = h * K
        cam.data.sensor_fit = "VERTICAL"
        sc.render.resolution_x = c["width"] * scale
        sc.render.resolution_y = h * scale
        path = os.path.join(REN_DIR, "%s_%s.png" % (prefix, name))
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out[name] = path
    cam.data.ortho_scale = 1402 * K
    return out


# ----------------------------------------------------------- materials
def lash_material(ob):
    """Near-black lashes using the MPFB lash texture's alpha."""
    d = os.path.join(MP.udata, "eyelashes", "eyelashes02")
    png = [f for f in os.listdir(d) if f.endswith(".png")][0]
    m = bpy.data.materials.new("M_Exit6_Lashes")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(d, png))
    p.inputs["Base Color"].default_value = (0.01, 0.008, 0.007, 1)
    p.inputs["Roughness"].default_value = 0.5
    nt.links.new(t.outputs["Alpha"], p.inputs["Alpha"])
    ob.data.materials.clear(); ob.data.materials.append(m)
    return m


def skin_material():
    m = B.principled("M_Exit6_Skin", attr="Col", rough=0.6, sss=0.12, coat=0.0, spec=0.38, bump=(900.0, 0.03))
    return m


def eye_material(eyes_ob):
    """Dark brown iris, MPFB eye UVs (brown texture darkened toward the reference)."""
    tex = os.path.join(MP.udata, "eyes", "materials", "brown_eye.png")
    m = bpy.data.materials.new("M_Exit6_Eyes")
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex)
    # luminance ramp: the reference eyes are a near-black brown iris on a warm off-white sclera
    bw = nt.nodes.new("ShaderNodeRGBToBW")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.40; cr.elements[0].color = (0.012, 0.006, 0.004, 1)
    cr.elements[1].position = 0.50; cr.elements[1].color = (0.80, 0.74, 0.68, 1)
    e = cr.elements.new(0.12); e.color = (0.002, 0.002, 0.002, 1)
    nt.links.new(t.outputs["Color"], bw.inputs["Color"])
    nt.links.new(bw.outputs["Val"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.12
    p.inputs["Coat Weight"].default_value = 0.6
    p.inputs["Coat Roughness"].default_value = 0.05
    eyes_ob.data.materials.clear()
    eyes_ob.data.materials.append(m)
    # each eye is two shells: eyeball and a slightly larger cornea; the cornea gets a clear coat
    c = bpy.data.materials.new("M_Exit6_EyeCornea")
    c.use_nodes = True
    cn = c.node_tree
    cp = cn.nodes["Principled BSDF"]
    cp.inputs["Base Color"].default_value = (1, 1, 1, 1)
    cp.inputs["Roughness"].default_value = 0.02
    cp.inputs["Transmission Weight"].default_value = 1.0
    cp.inputs["IOR"].default_value = 1.376
    c.blend_method = "BLEND" if hasattr(c, "blend_method") else None
    eyes_ob.data.materials.append(c)
    me = eyes_ob.data
    bm_ = bmesh.new(); bm_.from_mesh(me)
    bm_.verts.ensure_lookup_table()
    comp = -np.ones(len(bm_.verts), int); parts = []
    for v in bm_.verts:
        if comp[v.index] >= 0:
            continue
        st = [v]; comp[v.index] = len(parts); idx = []
        while st:
            x = st.pop(); idx.append(x.index)
            for ed in x.link_edges:
                o = ed.other_vert(x)
                if comp[o.index] < 0:
                    comp[o.index] = len(parts); st.append(o)
        parts.append(np.array(idx))
    bm_.free()
    # the cornea shells use the small UV island in the texture's lower-right corner
    uv = np.zeros(len(me.loops) * 2); me.uv_layers[0].data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
    lv = np.zeros(len(me.loops), int); me.loops.foreach_get("vertex_index", lv)
    cornea = set()
    for i, p in enumerate(parts):
        u = uv[np.isin(lv, p)].mean(0)
        if u[0] > 0.8 and u[1] < 0.2:
            cornea.add(i)
    for poly in me.polygons:
        poly.material_index = 1 if comp[poly.vertices[0]] in cornea else 0
    log("eye shells", [len(p) for p in parts], "cornea parts", sorted(cornea))
    return m


def skin_colors(ob, groups):
    """Approved skin tone with regional variation: lips, lash line, palms, soles."""
    me = ob.data
    nv = len(me.vertices)
    P = B.mesh_arrays(ob)
    base = B.srgb_lin(S2.SKIN_SRGB)
    col = np.tile(base, (nv, 1))
    def grp(name):
        return groups.get(name, np.array([], int))
    # lips: use the MPFB "lips" group if present, else geometric
    lips = grp("lips")
    if len(lips) and LMI:
        top = P[LMI["lip_up_top"], 2]; bot = P[LMI["lip_lo_bot"], 2]
        cx = abs(P[LMI["mouth_corner"], 0])
        fy = min(P[LMI["lip_up_front"], 1], P[LMI["lip_lo_front"], 1])
        q = P[lips]
        span = top - bot
        w = (np.clip((q[:, 2] - bot) / (0.12 * span) + 0.5, 0, 1) * np.clip((top - q[:, 2]) / (0.12 * span) + 0.5, 0, 1)
             * np.clip((cx - np.abs(q[:, 0])) / (0.15 * cx) + 0.3, 0, 1)
             * np.clip(1 - (q[:, 1] - fy) / (1.2 * span), 0, 1))
        col[lips] = col[lips] * (1 - w[:, None]) + B.srgb_lin(S2.LIP_SRGB) * w[:, None]
        mz = P[LMI["mouth_corner"], 2]
        d = np.abs(q[:, 2] - mz) / (0.07 * span)
        wl = np.clip(1 - d, 0, 1) * np.clip((cx * 1.05 - np.abs(q[:, 0])) / (0.2 * cx), 0, 1)
        col[lips] = col[lips] * (1 - 0.55 * wl[:, None])
    # lash line: dark lid margin along MPFB's lash helper strips (upper strong, lower faint)
    from mathutils.kdtree import KDTree
    body = groups["body"]
    for gname, strength, rad in (("helper-l-eyelashes-1", 0.85, 1.6), ("helper-r-eyelashes-1", 0.85, 1.6),
                                 ("helper-l-eyelashes-2", 0.5, 1.1), ("helper-r-eyelashes-2", 0.5, 1.1)):
        L_ = P[groups[gname]]
        kd = KDTree(len(L_))
        for i, q in enumerate(L_):
            kd.insert(Vector(q), i)
        kd.balance()
        for vi in body:
            _, _, d = kd.find(Vector(P[vi]))
            w = max(0.0, 1 - d / (rad * K)) * strength
            if w > 0:
                col[vi] = col[vi] * (1 - w) + np.array([0.004, 0.003, 0.003]) * w
    # palm and sole lightening (MPFB groups)
    for gname, tint in (("palms", (178, 118, 82)), ("soles", (182, 126, 92))):
        if gname in groups:
            col[groups[gname]] = col[groups[gname]] * 0.4 + B.srgb_lin(tint) * 0.6
    B.set_colors(ob, col)
    return col


# ------------------------------------------------------------ full stage
def strip_helpers(hm, groups):
    """Delete MPFB helper geometry (eye/teeth/clothes helpers, joint cubes); keep the body."""
    for m in list(hm.modifiers):
        if m.type == "MASK":
            hm.modifiers.remove(m)
    keep = np.zeros(len(hm.data.vertices), bool); keep[groups["body"]] = True
    bm_ = bmesh.new(); bm_.from_mesh(hm.data); bm_.verts.ensure_lookup_table()
    bmesh.ops.delete(bm_, geom=[v for v in bm_.verts if not keep[v.index]], context="VERTS")
    bm_.to_mesh(hm.data); bm_.free()
    for vg in list(hm.vertex_groups):
        if vg.name.startswith(("joint-", "helper-")) or vg.name in ("HelperGeometry", "JointCubes"):
            hm.vertex_groups.remove(vg)
    hm.data.update()
    STRIP["keep"] = np.nonzero(keep)[0]
    log("stripped helpers ->", len(hm.data.vertices), "verts")


STRIP = {}

# MPFB bone -> R15 part used where the v1 surface has no matching anatomy (hands, feet)
MP2R15 = {"hand": "Hand", "thumb": "Hand", "index": "Hand", "middle": "Hand", "ring": "Hand", "pinky": "Hand",
          "foot": "Foot", "ball": "Foot"}


# MPFB game-engine bone -> R15 part(s). The skeletal fit put MPFB's joints on the v1 R15
# joints, so MPFB's painted weights are valid for the unchanged v1 rig.
def mp_to_r15(bone):
    side = {"l": "Left", "r": "Right"}.get(bone.rsplit("_", 1)[-1]) if "_" in bone else None
    root = bone.rsplit("_", 1)[0] if side else bone
    if root in ("Root", "pelvis"):
        return {"LowerTorso": 1.0}
    if root == "spine_01":
        return {"LowerTorso": 0.5, "UpperTorso": 0.5}
    if root in ("spine_02", "spine_03", "clavicle", "breast"):
        return {"UpperTorso": 1.0}
    if root == "neck":
        return {"UpperTorso": 0.35, "Head": 0.65}
    if bone == "neck_01":
        return {"UpperTorso": 0.35, "Head": 0.65}
    if root == "head" or bone == "head":
        return {"Head": 1.0}
    part = {"upperarm": "UpperArm", "lowerarm": "LowerArm", "hand": "Hand", "thumb": "Hand", "index": "Hand",
            "middle": "Hand", "ring": "Hand", "pinky": "Hand", "thigh": "UpperLeg", "calf": "LowerLeg",
            "foot": "Foot", "ball": "Foot"}
    for k, v in part.items():
        if root.startswith(k) and side:
            return {side + v: 1.0}
    return {"UpperTorso": 1.0}


def r15_weights(hm, v1b, bones, Wn, groups, body_mask):
    """MPFB's own skin weights mapped onto the (unchanged) v1 R15 bones."""
    keep = STRIP["keep"]
    Wk = Wn[keep]
    W = np.zeros((len(keep), len(B.BONES)))
    for j, b in enumerate(bones):
        col = Wk[:, j]
        if not col.any():
            continue
        for part, f in mp_to_r15(b).items():
            W[:, B.BI[part]] += col * f
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    log("R15 weights from MPFB; unweighted:", int((W.sum(1) < 0.5).sum()))
    return W


def make_briefs(hm, W, root):
    """Re-cut the v1 briefs from the new body (the v1 cutter works in reference px)."""
    tmp = hm.copy(); tmp.data = hm.data.copy(); tmp.modifiers.clear()
    bpy.context.scene.collection.objects.link(tmp)
    tmp.data.transform(Matrix.Scale(1 / K, 4))
    br = B.build_briefs(tmp, W, root)
    # signed push: the v1 cutter's smoothing sinks fabric deep inside on the coarse MPFB mesh
    tmp.data.calc_loop_triangles()
    tv = B.mesh_arrays(tmp)
    # fabric bridges creases (gluteal cleft, crotch): push against a smoothed body
    te, _ = mesh_adjacency(tmp.data)
    tvs = laplacian_smooth_field(tv, te, len(tv), 12)
    lt = np.zeros(len(tmp.data.loop_triangles) * 3, np.int32); tmp.data.loop_triangles.foreach_get("vertices", lt)
    bvhs = [BVHTree.FromPolygons(x.tolist(), lt.reshape(-1, 3).tolist()) for x in (tv, tvs)]
    bv = B.mesh_arrays(br)
    for it in range(3):
        for bvh in bvhs:
            for i in range(len(bv)):
                loc, n, _, _ = bvh.find_nearest(Vector(bv[i]))
                loc = np.array(loc); n = np.array(n)
                if (bv[i] - loc) @ n < 1.7:
                    bv[i] = loc + n * 1.7
        # light relax so the pushed fabric stays smooth
        me_ = br.data
        e = np.zeros(len(me_.edges) * 2, int); me_.edges.foreach_get("vertices", e); e = e.reshape(-1, 2)
        acc = np.zeros_like(bv); deg = np.bincount(e.ravel(), minlength=len(bv)).astype(float)
        np.add.at(acc, e[:, 0], bv[e[:, 1]]); np.add.at(acc, e[:, 1], bv[e[:, 0]])
        bv = bv * 0.7 + 0.3 * acc / np.maximum(deg, 1)[:, None] if it < 2 else bv
    # straight waistband / hem: snap the open boundary to its measured row
    bnd = boundary_verts(br.data)
    rows = SOLE - bv[:, 2]
    top = bnd[rows[bnd] < 660]; bot = bnd[rows[bnd] >= 660]
    bv[top, 2] = SOLE - 604.0
    bv[bot, 2] = SOLE - (765 + 3 * B.sstep(-20, 30, bv[bot, 1]))
    B.set_verts(br, bv)
    br.data.transform(Matrix.Scale(K, 4))
    for m in br.modifiers:
        if m.type == "SOLIDIFY":
            m.thickness *= K
    bpy.data.objects.remove(tmp)
    return br


def tuck_under_briefs(hm, W):
    """Pull the skin under the briefs slightly inward so it can never poke through the fabric."""
    me = hm.data; me.update()
    P = B.mesh_arrays(hm)
    N = B.vertex_normals(hm)
    row = SOLE - P[:, 2] / K
    dom = W.argmax(1)
    ok = np.isin(dom, [B.BI["LowerTorso"], B.BI["UpperTorso"], B.BI["LeftUpperLeg"], B.BI["RightUpperLeg"]])
    hem = 765 + 3 * B.sstep(-20, 30, P[:, 1] / K)
    w = ok * np.clip((row - 607) / 4, 0, 1) * np.clip((hem - 3 - row) / 4, 0, 1)
    P = P - N * (w * 1.6 * K)[:, None]
    # creases the fabric bridges (gluteal cleft, crotch): pull the skin well clear of it
    X, Y = P[:, 0] / K, P[:, 1] / K
    wc = w * np.clip((20 - np.abs(X)) / 8, 0, 1)
    P[:, 1] -= (wc * (Y > 0) * 8.0 * K)
    P[:, 1] += (wc * (Y < -10) * np.clip((row - 670) / 10, 0, 1) * 3.0 * K)
    me.vertices.foreach_set("co", P.ravel().astype(np.float32)); me.update()


def fix_crouch(rig, body):
    """Drop the root in the crouch frame so the soles stay on the floor (v1 floated)."""
    names = list(B.POSES)
    fi = names.index("crouch") + 1
    sc = bpy.context.scene
    pb = rig.pose.bones["HumanoidRootNode"]
    for it in range(3):
        sc.frame_set(fi)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg); me = ev.to_mesh()
        z = min(v.co.z for v in me.vertices)
        ev.to_mesh_clear()
        if abs(z) < 0.003:
            break
        # HumanoidRootNode points up: its local +Y is world +Z
        pb.location = (pb.location[0], pb.location[1] - z, pb.location[2])
        pb.keyframe_insert("location", frame=fi)
        for fc in B._fcurves(rig.animation_data.action):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    log("crouch root drop: %.3f studs (residual %.4f)" % (pb.location[1], z))


def hair_closeups(cam, hair, hair_g, scalp):
    """Hair close-ups: render twists vs game twists (actual geometry), front and back 3/4."""
    sc = bpy.context.scene
    hide = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Exit6") and o not in (hair, hair_g, scalp)]
    for variant, show, other in (("render", hair, hair_g), ("game", hair_g, hair)):
        show.hide_render = False; other.hide_render = True
        for name, az, top, bot, wid in (("front", 0.0, 186, 346, 170), ("back34", 145.0, 186, 346, 170),
                                         ("detail", -35.0, 240, 300, 60)):
            a = math.radians(az)
            cam.location = (math.sin(a) * 30, -math.cos(a) * 30, (SOLE - (top + bot) / 2) * K)
            cam.rotation_euler = (math.radians(90), 0, a)
            cam.data.ortho_scale = (bot - top) * K
            sc.render.resolution_y = 900; sc.render.resolution_x = int(900 * wid / (bot - top))
            sc.render.filepath = os.path.join(REN_DIR, "hair_%s_%s.png" % (variant, name))
            bpy.ops.render.render(write_still=True)
    hair.hide_render = False; hair_g.hide_render = True
    cam.data.ortho_scale = 1402 * K
    sc.render.resolution_x, sc.render.resolution_y = 600, 1402


# ----------------------------------------------------------------- main
def head_bvh_px(ob, groups):
    """BVH of the head region in reference-pixel space (for the v1 generators)."""
    P = B.mesh_arrays(ob) / K
    me = ob.data
    me.calc_loop_triangles()
    lt = np.zeros(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get("vertices", lt)
    lt = lt.reshape(-1, 3)
    body = np.zeros(len(P), bool); body[groups["body"]] = True
    keep = body[lt].all(1) & (P[lt][:, :, 2].min(1) > (SOLE - 400))
    return BVHTree.FromPolygons(P.tolist(), lt[keep].tolist())


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    root = bpy.data.collections.new("Exit6_Male_V2")
    sc.collection.children.link(root)
    mpfb()
    hm = create_human()
    for c in list(hm.users_collection):
        c.objects.unlink(hm)
    root.objects.link(hm)
    groups = vgroup_members(hm)
    log("MPFB human", len(hm.data.vertices), "verts")
    bones, Wn = skeletal_fit(hm, groups)
    head_fit(hm, groups, bones, Wn)
    face_relax(hm, groups, bones, Wn)
    body_mask = np.zeros(len(hm.data.vertices), bool); body_mask[groups["body"]] = True
    if OPT["stage"] != "face":
        with bpy.data.libraries.load(V1_BLEND, link=False) as (src, dst):
            dst.objects = ["Exit6_Male_Body"]
        v1b = dst.objects[0]; v1b.name = "Exit6_Male_Body_V1"
        # the append drags the v1 rig in as a dependency; drop it so the new rig keeps its name
        for m in list(v1b.modifiers):
            v1b.modifiers.remove(m)
        for o in list(bpy.data.objects):
            if o.type == "ARMATURE":
                bpy.data.objects.remove(o)
        fit_mask = body_fit(hm, v1b, bones, Wn, body_mask)
        shoulder_relax(hm, groups)
    # eyes (fitted to the deformed helper geometry)
    eyes = MP.HS.add_mhclo_asset(os.path.join(MP.udata, "eyes", "high-poly", "high-poly.mhclo"), hm,
                                 asset_type="Eyes", subdiv_levels=0, material_type="MAKESKIN",
                                 set_up_rigging=False, interpolate_weights=False, import_subrig=False,
                                 import_weights=False)
    eyes.name = "Exit6_Male_Eyes"
    for c in list(eyes.users_collection):
        c.objects.unlink(eyes)
    root.objects.link(eyes)
    eyes.parent = None
    eye_material(eyes)
    skin_colors(hm, groups)
    hm.data.materials.clear(); hm.data.materials.append(skin_material())
    # brows / goatee / hair from the v1 generators on the new head
    bvh = head_bvh_px(hm, groups)
    tmp = bpy.data.collections.new("tmp_px"); sc.collection.children.link(tmp)
    brows = B.build_brows(bvh, tmp)
    gv_, gf_ = H.goatee(bvh)
    goatee = B.make_obj("Exit6_Male_Goatee", gv_, gf_, tmp)
    sol = goatee.modifiers.new("thick", "SOLIDIFY"); sol.thickness = 0.9; sol.offset = -1
    Wg = B.wmat(len(gv_)); Wg[:, B.BI["Head"]] = 1
    B.assign_groups(goatee, Wg)
    extra = [brows, goatee]
    if OPT["hair"]:
        roots, paths, (hv, hf), (gv, gf) = H.build(bvh)
        log("hair: %d twists" % len(paths))
        hair = B.make_obj("Exit6_Male_Hair_Twists", hv, hf, tmp)
        hair_g = B.make_obj("Exit6_Male_Hair_Game", gv, gf, tmp)
        for ob in (hair, hair_g):
            Wh = B.wmat(len(ob.data.vertices)); Wh[:, B.BI["Head"]] = 1
            B.assign_groups(ob, Wh)
        hair_g.hide_render = True
        scalp = B.build_scalp_cap(bvh, roots, tmp)
        extra += [hair, scalp, hair_g]
    M = B.make_materials()
    for ob in extra:
        ob.data.transform(Matrix.Scale(K, 4))
        for m in ob.modifiers:
            if m.type == "SOLIDIFY":
                m.thickness *= K
        tmp.objects.unlink(ob); root.objects.link(ob)
        ob.data.materials.append(M["scalp"] if ob.name.endswith("Scalp") else M["hair"])
    bpy.data.collections.remove(tmp)
    sub = hm.modifiers.new("Subdiv", "SUBSURF"); sub.levels = 1; sub.render_levels = 2
    cam = B.setup_render(OPT["samples"])
    if OPT["stage"] == "face":
        paths = render_face(cam, "face_v2")
        for ob in extra:
            ob.hide_render = True
        render_face(cam, "face_v2_bare")
        for ob in extra:
            ob.hide_render = False
        log("face renders", paths)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "face_lab.blend"))
        return
    # ---------------- full stage: body-only mesh, weights, briefs, rig
    hm.modifiers.remove(sub)
    strip_helpers(hm, groups)
    W = r15_weights(hm, v1b, bones, Wn, groups, body_mask)
    B.assign_groups(hm, W)
    briefs = make_briefs(hm, W, root)
    tuck_under_briefs(hm, W)
    # muscle relief: v1 sculpt surface as a (decimated, rigged) shrinkwrap target after subdivision
    v1b.name = "Exit6_Male_DetailTarget"; v1b.data.name = "Exit6_Male_DetailTarget"
    if v1b.name not in root.objects:
        root.objects.link(v1b)
    dec = v1b.modifiers.new("dec", "DECIMATE"); dec.ratio = 0.2
    bpy.context.view_layer.objects.active = v1b
    for o in bpy.context.view_layer.objects:
        o.select_set(o == v1b)
    bpy.ops.object.modifier_apply(modifier="dec")
    v1b.hide_render = True
    v1b.display_type = "WIRE"
    vg = hm.vertex_groups.new(name="DetailFit")
    dmask = np.zeros(len(Wn))
    for b in ("pelvis", "spine_01", "spine_02", "spine_03", "Root", "thigh_l", "thigh_r", "calf_l", "calf_r"):
        dmask += Wn[:, bones.index(b)]
    dm = np.clip(dmask[STRIP["keep"]], 0, 1) * S2.DETAIL_STRENGTH
    Pk = B.mesh_arrays(hm) / K
    Qk = np.stack([Pk[:, 0], Pk[:, 1], SOLE - Pk[:, 2]], 1)   # x, Y, row
    for (x, Y, row), r in S2.DETAIL_FADE:
        for sx in ((1, -1) if x else (1,)):
            d = np.linalg.norm(Qk - np.array([x * sx, Y, row]), axis=1)
            dm *= np.clip((d - r * 0.55) / (r * 0.45), 0, 1)
    # no projected relief under the briefs (it would poke through where the fabric bridges)
    r_ = Qk[:, 2]
    dm *= 1 - np.clip((r_ - 596) / 8, 0, 1) * np.clip((776 - r_) / 8, 0, 1)
    # keep the projection away from the arm / torso gap
    side_band = (Qk[:, 2] < 600) & (Qk[:, 2] > 400)
    dm[side_band] *= np.clip((S2.DETAIL_SIDE_X - np.abs(Qk[side_band, 0])) / 10.0, 0, 1)
    q = np.round(dm * 50).astype(int)
    for val in np.unique(q):
        if val > 0:
            vg.add(np.nonzero(q == val)[0].tolist(), val / 50.0, "REPLACE")
    briefs.data.materials.append(M["briefs"])
    rig = B.build_rig(root)
    char = [hm, eyes, briefs] + extra
    B.bind([v1b], rig)
    for ob in (eyes,):
        We = B.wmat(len(ob.data.vertices)); We[:, B.BI["Head"]] = 1
        B.assign_groups(ob, We)
    B.bind(char, rig)
    s_ = hm.modifiers.new("Subdiv", "SUBSURF"); s_.levels = 1; s_.render_levels = 2
    dsw = hm.modifiers.new("MuscleDetail", "SHRINKWRAP"); dsw.target = v1b
    dsw.wrap_method = "PROJECT"; dsw.use_negative_direction = True; dsw.use_positive_direction = True
    dsw.project_limit = S2.DETAIL_LIMIT; dsw.vertex_group = "DetailFit"; dsw.wrap_mode = "ON_SURFACE"
    # briefs: subdivide, then keep the fabric outside the (posed, subdivided) skin, then thickness
    sol = [m for m in briefs.modifiers if m.type == "SOLIDIFY"]
    th = sol[0].thickness if sol else 0.7 * K
    for m in sol:
        briefs.modifiers.remove(m)
    s_ = briefs.modifiers.new("Subdiv", "SUBSURF"); s_.levels = 1; s_.render_levels = 2
    # (fabric is pushed outside the skin at build time; no render-time shrinkwrap)
    so = briefs.modifiers.new("thick", "SOLIDIFY"); so.thickness = th; so.offset = -1
    B.build_pose_action(rig)
    fix_crouch(rig, hm)
    sc.frame_set(1)
    stats = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in char:
        me = ob.data; me.calc_loop_triangles()
        stats[ob.name] = {"verts": len(me.vertices), "tris": len(me.loop_triangles)}
    with open(os.path.join(OUT_DIR, "build_stats_v2.json"), "w") as fh:
        json.dump({"studs_per_ref_px": K, "objects": stats, "bones": [b.name for b in rig.data.bones],
                   "mpfb_macro": S2.MACRO, "face_targets": S2.FACE_TARGETS}, fh, indent=1)
    log(json.dumps(stats))
    if OPT["render"]:
        B.render_views(cam, "render_v2")
        render_face(cam, "face_v2")
        hair_closeups(cam, hair, hair_g, scalp)
        for fi, pname in enumerate(B.POSES, start=1):
            if pname == "rest":
                continue
            sc.frame_set(fi)
            B.render_views(cam, "pose_v2_%s" % pname, {"three_quarter": 35.0, "front": 0.0})
        sc.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=V2_BLEND, compress=True)
    log("saved", V2_BLEND)


if __name__ == "__main__":
    main()
