"""Exit 6 male V3: visual-quality correction on top of the V2 build.

    blender -b --factory-startup -P tools/characters/build_exit6_male_v3.py -- [--stage=face|full]
          [--samples=N] [--no-hair] [--no-render] [--tag=NAME]

Keeps the V2 pipeline (MPFB hm08 base, skeletal fit onto the v1 R15 joints,
v1 rig, MPFB weights mapped to R15) and changes what V2 got visually wrong:

  * face: lean / angular MPFB targets instead of V2's volume targets, a
    least-squares pre-alignment before a softened landmark warp (V2's raw
    warp moved the jaw 39 px and puffed the face), then named sculpt strokes
    (exit6_sculpt_v3.py, exit6_male_v3_spec.FACE_SCULPT);
  * eyes: bigger aperture, shallower sockets;
  * goatee: tapered shell following the chin, soft edge;
  * hair: thinner, fewer, separated twists (exit6_hair_v3.py);
  * body: sculpt strokes for deltoids / chest / arms / abs, hand scale and
    relaxed fingers;
  * review: neutral soft lighting, clay + skin renders from matching angles.

--stage=face stops after the head and renders face reviews only.
"""
import bpy, os, sys, math, json, time
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib
import exit6_male_v3_spec as S3
importlib.reload(S3)
import build_exit6_male_v2 as V
import build_exit6_male as B
import exit6_male_spec as S
import exit6_sculpt_v3 as SC
import exit6_hair_v3 as H3
importlib.reload(SC); importlib.reload(H3)

V.S2 = S3                      # every V2 function now reads the V3 values
V.H = H3
H3.apply_tune(**S3.HAIR)
H3.TIP.update(ang=S3.HAIR_TIP_ANG, rows=S3.HAIR_TIP_ROWS)
K = B.K
SOLE = S.SOLE
OUT_DIR = V.OUT_DIR
REN_DIR = os.path.join(OUT_DIR, "renders_v3")
WORK = os.path.join(V.REPO, "build", "exit6_v3")
os.makedirs(REN_DIR, exist_ok=True); os.makedirs(WORK, exist_ok=True)
V.REN_DIR = REN_DIR; B.REN_DIR = REN_DIR; V.WORK = WORK
V3_BLEND = os.path.join(OUT_DIR, "Exit6_Male_V3.blend")
OPT = V.OPT
OPT.setdefault("tag", "")
for a in V.ARGV:
    if a.startswith("--tag="): OPT["tag"] = a.split("=")[1]
    if a == "--quick": OPT["quick"] = True
T0 = time.time()


def log(*a):
    print("[exit6v3 %6.1fs]" % (time.time() - T0), *a, flush=True)


V.log = log


# ------------------------------------------------------------------ helpers
def get_P(me):
    P = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", P); return P.reshape(-1, 3)


def set_P(me, P):
    me.vertices.foreach_set("co", P.ravel().astype(np.float32)); me.update()


def to_Q(P):
    return np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)


def to_P(Q):
    return np.stack([Q[:, 0] * K, Q[:, 1] * K, (SOLE - Q[:, 2]) * K], 1)


def mesh_tris(me):
    me.calc_loop_triangles()
    t = np.zeros(len(me.loop_triangles) * 3, np.int32); me.loop_triangles.foreach_get("vertices", t)
    return t.reshape(-1, 3)


# ------------------------------------------------------------ head fit V3
def head_fit3(hm, groups, bones, Wn):
    """least-squares affine pre-alignment, then a thin-plate warp of the residual with per-landmark trust"""
    me = hm.data
    P = get_P(me)
    nv = len(P)
    body = np.zeros(nv, bool); body[groups["body"]] = True
    wH = np.clip(Wn[:, bones.index("head")] + 0.5 * Wn[:, bones.index("neck_01")], 0, 1)
    Q = to_Q(P)
    pts = [p for p in V.head_points(Q, groups) if S3.LANDMARK_SOFT.get(p[0], 0.0) is not None]
    src = np.array([p for _, _, p, _ in pts])
    # midline landmarks: keep the vertex's own x (some sit a few px off the centre line)
    dst = np.array([[p[0] if t[0] == 0 else side * t[0], p[1] if t[2] is None else t[2], t[1]]
                    for _, side, p, t in pts])
    soft = np.array([S3.LANDMARK_SOFT.get(k, 0.0) for k, _, _, _ in pts]) + S3.TPS_SMOOTH_BASE
    names = ["%s%s" % (k, "" if side > 0 else "_R") for k, side, _, _ in pts]
    log("landmark offsets before prealign (px):",
        {n: [round(float(v), 1) for v in d - s] for n, s, d in zip(names, src, dst)})
    # 1. affine pre-alignment (x stays symmetric: no x shear / translation)
    Xh = np.hstack([src, np.ones((len(src), 1))])
    A = np.linalg.lstsq(Xh, dst, rcond=None)[0]           # 4x3
    A[1:3, 0] = 0; A[0, 1:] = 0; A[3, 0] = 0              # keep left/right symmetry
    Qa = np.hstack([Q, np.ones((nv, 1))]) @ A
    Q1 = Q + (Qa - Q) * wH[:, None]
    src1 = np.hstack([src, np.ones((len(src), 1))]) @ A
    log("prealign affine:", np.round(A[:3].T, 3).tolist(), "t", np.round(A[3], 1).tolist())
    log("landmark residual after prealign (px):",
        {n: round(float(e), 1) for n, e in zip(names, np.linalg.norm(dst - src1, axis=1))})
    if S3.HEAD_FIT == "affine":
        set_P(me, to_P(Q1))
        return {}
    # 2. residual warp, neck anchored
    ring = np.nonzero(body & (np.abs(Q1[:, 2] - 372) < 3))[0][::7]
    s_all = np.vstack([src1, Q1[ring]]); d_all = np.vstack([dst, Q1[ring]])
    lam = np.concatenate([soft, np.full(len(ring), 0.0)])
    n = len(s_all)
    Kr = np.linalg.norm(s_all[:, None] - s_all[None], axis=2) + np.diag(lam)
    Pm = np.hstack([np.ones((n, 1)), s_all])
    M = np.zeros((n + 4, n + 4)); M[:n, :n] = Kr; M[:n, n:] = Pm; M[n:, :n] = Pm.T
    rhs = np.zeros((n + 4, 3)); rhs[:n] = d_all - s_all
    sol = np.linalg.solve(M, rhs)
    Qn = V.tps_apply((s_all, sol[:n], sol[n:]), Q1)
    Q2 = Q1 + (Qn - Q1) * wH[:, None]
    set_P(me, to_P(Q2))
    after = V.head_points(Q2, groups)
    after = [p for p in after if S3.LANDMARK_SOFT.get(p[0], 0.0) is not None]
    err = {n_: round(float(np.linalg.norm(p - d)), 1) for n_, (_, _, p, _), d in zip(names, after, dst)}
    log("landmark error after V3 fit (px):", err)
    return err


# ------------------------------------------------------------------ sculpt
RIGID = ("helper-l-eye", "helper-r-eye", "helper-tongue", "helper-upper-teeth", "helper-lower-teeth")


def sculpt(hm, groups, brushes, label):
    if not brushes:
        return
    me = hm.data
    P = get_P(me)
    e = np.zeros(len(me.edges) * 2, int); me.edges.foreach_get("vertices", e); e = e.reshape(-1, 2)
    rigid = [groups[g] for g in RIGID if g in (groups or {})]
    # brushes move only the skin and the helpers that ride on it (lashes); rigid parts follow as a whole
    movable = np.ones(len(P), bool)
    sc_ = SC.Sculptor(to_Q(P), e, mesh_tris(me), movable, rigid)
    Qs = sc_.run(brushes)
    set_P(me, to_P(Qs))
    log("%s strokes (max px):" % label, sc_.log)


# --------------------------------------------------------------- hands
def hand_fix(hm, groups, bones, Wn):
    """scale the hands about the wrist and close the finger spread toward the middle finger"""
    if S3.HAND_SCALE == 1.0 and S3.FINGER_CLOSE == 0.0:
        return
    me = hm.data
    P = get_P(me)
    jc = {k[6:]: P[v].mean(0) for k, v in groups.items() if k.startswith("joint-") and len(v)}
    BI_ = {b: i for i, b in enumerate(bones)}
    fingers = {2: "index", 3: "middle", 4: "ring", 5: "pinky", 1: "thumb"}
    for s in ("l", "r"):
        hb = ["hand_" + s] + ["%s_0%d_%s" % (f, k, s) for f in fingers.values() for k in (1, 2, 3)]
        wh = sum(Wn[:, BI_[b]] for b in hb if b in BI_)
        wr = jc[s + "-hand"]
        P = P + (S3.HAND_SCALE - 1) * (P - wr) * wh[:, None]
        jc = {k[6:]: P[v].mean(0) for k, v in groups.items() if k.startswith("joint-") and len(v)}
        if S3.FINGER_CLOSE:
            mid = jc[s + "-finger-3-4"] - jc[s + "-finger-3-1"]
            across = jc[s + "-finger-2-1"] - jc[s + "-finger-5-1"]
            pn = np.cross(mid, across); pn /= np.linalg.norm(pn)
            md = mid - (mid @ pn) * pn; md /= np.linalg.norm(md)
            # thumb: swing it from the A-pose spread toward the hand axis
            hd = jc[s + "-finger-3-4"] - wr
            wt = sum(Wn[:, BI_["thumb_0%d_%s" % (k, s)]] for k in (1, 2, 3))
            k0 = jc[s + "-finger-1-1"]
            td = jc[s + "-finger-1-4"] - k0
            ax = np.cross(td, hd); ax /= np.linalg.norm(ax)
            ang = math.acos(np.clip(td @ hd / np.linalg.norm(td) / np.linalg.norm(hd), -1, 1)) * S3.THUMB_CLOSE
            R = np.array(Matrix.Rotation(ang, 3, Vector(ax)))
            P = P + (((P - k0) @ R.T + k0) - P) * wt[:, None]
            for f in (2, 4, 5):
                wf = sum(Wn[:, BI_["%s_0%d_%s" % (fingers[f], k, s)]] for k in (1, 2, 3))
                k0 = jc["%s-finger-%d-1" % (s, f)]
                fd = jc["%s-finger-%d-4" % (s, f)] - k0
                fd = fd - (fd @ pn) * pn; fd /= np.linalg.norm(fd)
                ang = math.atan2(np.cross(fd, md) @ pn, fd @ md) * S3.FINGER_CLOSE
                R = np.array(Matrix.Rotation(ang, 3, Vector(pn)))
                Pr = (P - k0) @ R.T + k0
                P = P + (Pr - P) * wf[:, None]
    set_P(me, P)
    log("hands: scale %.2f, finger close %.2f" % (S3.HAND_SCALE, S3.FINGER_CLOSE))


# --------------------------------------------------------- eyes / skin colour
def eye_material3(eyes):
    """procedural eyeball colours by angle from the gaze axis: off-white sclera, large dark iris"""
    V.eye_material(eyes)
    me = eyes.data
    mi = np.zeros(len(me.polygons), int); me.polygons.foreach_get("material_index", mi)
    ball = np.zeros(len(me.vertices), bool)
    for poly in me.polygons:
        if poly.material_index == 0:
            ball[list(poly.vertices)] = True
    P = get_P(me)
    col = np.tile(B.srgb_lin(S3.EYE_SCLERA_SRGB), (len(P), 1))
    for side in (1, -1):
        idx = np.nonzero(ball & (np.sign(P[:, 0]) == side))[0]
        c = P[idx].mean(0)
        d = P[idx] - c; d /= np.linalg.norm(d, axis=1, keepdims=True)
        ang = np.degrees(np.arccos(np.clip(-d[:, 1], -1, 1)))
        t = np.clip((S3.EYE_IRIS_DEG - ang) / 1.5, 0, 1)                 # iris mask, soft limbus
        inner = np.clip((S3.EYE_IRIS_DEG * 0.75 - ang) / 4.0, 0, 1)
        iris = B.srgb_lin(S3.EYE_IRIS_SRGB) * (1 - inner[:, None]) + B.srgb_lin(S3.EYE_IRIS_INNER_SRGB) * inner[:, None]
        limbus = np.clip(1 - np.abs(ang - S3.EYE_IRIS_DEG + 1.5) / 2.0, 0, 1)
        iris = iris * (1 - 0.6 * limbus[:, None])
        pup = np.clip((S3.EYE_PUPIL_DEG - ang) / 1.0, 0, 1)
        cc = col[idx] * (1 - t[:, None]) + iris * t[:, None]
        cc = cc * (1 - pup[:, None]) + 0.003 * pup[:, None]
        col[idx] = cc
    B.set_colors(eyes, col)
    m = eyes.data.materials[0]
    nt = m.node_tree
    p = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeVertexColor"); a.layer_name = "Col"
    nt.links.new(a.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.35
    p.inputs["Coat Weight"].default_value = 0.0
    cp = eyes.data.materials[1].node_tree.nodes["Principled BSDF"]
    # the cornea shell greyed the iris: keep it invisible, the eyeball carries a glossy coat instead
    cp.inputs["Alpha"].default_value = 0.0
    p.inputs["Coat Weight"].default_value = 0.4
    p.inputs["Coat Roughness"].default_value = 0.08
    log("eye colours: iris %.0f deg, pupil %.0f deg" % (S3.EYE_IRIS_DEG, S3.EYE_PUPIL_DEG))


def skin_colors3(hm, groups):
    """V2 skin colours, then V3 lips (dark upper / light lower) and a heavier upper lash line"""
    col = V.skin_colors(hm, groups)
    P = B.mesh_arrays(hm)
    LMI = V.LMI
    lips = groups["lips"]
    q = P[lips]
    zc = (P[LMI["lip_up_front"], 2] + P[LMI["lip_lo_front"], 2]) / 2
    zk = P[LMI["mouth_corner"], 2]; cx = abs(P[LMI["mouth_corner"], 0])
    top = P[LMI["lip_up_top"], 2]; bot = P[LMI["lip_lo_bot"], 2]
    fy = min(P[LMI["lip_up_front"], 1], P[LMI["lip_lo_front"], 1])
    span = top - bot
    seam = zc + (zk - zc) * np.clip(np.abs(q[:, 0]) / cx, 0, 1) ** 2
    upper = np.clip((q[:, 2] - seam) / (0.04 * span) + 0.5, 0, 1)
    w = (np.clip((q[:, 2] - bot) / (0.05 * span) + 0.2, 0, 1) * np.clip((top - q[:, 2]) / (0.05 * span) + 0.2, 0, 1)
         * np.clip((cx * 1.04 - np.abs(q[:, 0])) / (0.1 * cx), 0, 1)
         * np.clip(1 - (q[:, 1] - fy) / (1.2 * span), 0, 1))
    lipc = B.srgb_lin(S3.UPPER_LIP_SRGB) * upper[:, None] + B.srgb_lin(S3.LOWER_LIP_SRGB) * (1 - upper[:, None])
    base = np.tile(B.srgb_lin(S3.SKIN_SRGB), (len(lips), 1))
    col[lips] = base * (1 - w[:, None]) + lipc * w[:, None]
    # mouth line
    d = np.abs(q[:, 2] - seam) / (0.05 * span)
    wl = np.clip(1 - d, 0, 1) * np.clip((cx * 1.08 - np.abs(q[:, 0])) / (0.15 * cx), 0, 1)
    col[lips] *= (1 - 0.7 * wl[:, None])
    # heavier lash line (the reference reads as a dark upper liner)
    from mathutils.kdtree import KDTree
    body = groups["body"]
    for gname, (strength, rad) in (("helper-l-eyelashes-1", S3.LASH_UPPER), ("helper-r-eyelashes-1", S3.LASH_UPPER),
                                   ("helper-l-eyelashes-2", S3.LASH_LOWER), ("helper-r-eyelashes-2", S3.LASH_LOWER)):
        L_ = P[groups[gname]]
        kd = KDTree(len(L_))
        for i, v in enumerate(L_):
            kd.insert(Vector(v), i)
        kd.balance()
        Pb = P[body]
        for k, vi in enumerate(body):
            _, _, dd = kd.find(Vector(Pb[k]))
            ww = max(0.0, 1 - dd / (rad * K)) ** 0.7 * strength
            if ww > 0:
                col[vi] = col[vi] * (1 - ww) + np.array([0.004, 0.003, 0.003]) * ww
    B.set_colors(hm, col)
    return col


def build_brows3(bvh, root):
    """v1 brow shape, relief scaled down (BROW_RELIEF) so the brows sit close to the skin"""
    pts = [(-29, 262.5, 5.2), (-24, 262.0, 6.8), (-18, 262.8, 7.6),
           (-12.5, 264.6, 8.0), (-8.0, 266.8, 8.2), (-5.2, 268.2, 7.6)]
    rings = []
    for x, yc, t in pts:
        ring = []
        for (vv, out) in ((-0.5, -0.6), (-0.5, 1.8), (-0.25, 2.9), (0.15, 3.1), (0.5, 2.0),
                          (0.5, -0.6), (0.0, -1.0)):
            yy = yc + vv * t
            p, n = B.surface_hit(bvh, np.array([x, -200, SOLE - yy]), np.array([0, 1.0, 0]))
            ring.append(p + n * (out * S3.BROW_RELIEF if out > 0 else out))
        rings.append(ring)
    v, f = B.rings_mesh(np.array(rings))
    v2 = v.copy(); v2[:, 0] *= -1
    f2 = [list(reversed(ff)) for ff in f]
    V_ = np.vstack([v, v2]); F_ = f + [[i + len(v) for i in ff] for ff in f2]
    ob = B.make_obj("Exit6_Male_Brows", V_, F_, root)
    W = B.wmat(len(V_)); W[:, B.BI["Head"]] = 1
    B.assign_groups(ob, W)
    return ob


# ------------------------------------------------------------- lighting
def neutral_lights():
    """soft, mostly frontal studio light (the reference sheet is lit flat from the front)"""
    sc = bpy.context.scene
    for o in list(bpy.data.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    lc = bpy.data.collections.get("Exit6_Studio")
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25

    def area(name, az, el, dist, size, power, tgt_z, color=(1, 1, 1)):
        a, e = math.radians(az), math.radians(el)
        tgt = Vector((0, 0, tgt_z))
        loc = tgt + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
        ld = bpy.data.lights.new(name, "AREA"); ld.size = size; ld.energy = power; ld.color = color
        lo = bpy.data.objects.new(name, ld); lc.objects.link(lo)
        lo.location = loc
        lo.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
    zc = 3.0
    area("Key", -28, 22, 10, 6.0, 800, zc, (1.0, 0.97, 0.94))
    area("Fill", 35, 8, 10, 9.0, 380, zc, (0.97, 0.98, 1.0))
    area("Top", 0, 75, 9, 6.0, 160, zc)
    area("RimL", 140, 25, 9, 5.0, 300, zc)
    area("RimR", -140, 25, 9, 5.0, 300, zc)


def clay_material():
    m = bpy.data.materials.new("M_Clay")
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (0.42, 0.42, 0.43, 1)
    p.inputs["Roughness"].default_value = 0.55
    return m


def review_face(cam, tag, extra, clay=True):
    out = {}
    out["skin"] = V.render_face(cam, "face_v3%s" % tag)
    for ob in extra:
        ob.hide_render = True
    out["bare"] = V.render_face(cam, "face_v3%s_bare" % tag)
    if clay:
        vl = bpy.context.view_layer
        vl.material_override = clay_material()
        out["clay"] = V.render_face(cam, "face_v3%s_clay" % tag)
        vl.material_override = None
    for ob in extra:
        ob.hide_render = False
    return out


# ------------------------------------------------------------------ main
def build_head():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "NONE"
    root = bpy.data.collections.new("Exit6_Male_V3")
    sc.collection.children.link(root)
    V.mpfb()
    hm = V.create_human()
    for c in list(hm.users_collection):
        c.objects.unlink(hm)
    root.objects.link(hm)
    groups = V.vgroup_members(hm)
    log("MPFB human", len(hm.data.vertices), "verts; helper groups:",
        sorted(g for g in groups if g.startswith("helper-") and "eyelash" not in g and "tights" not in g)[:20])
    bones, Wn = V.skeletal_fit(hm, groups)
    hand_fix(hm, groups, bones, Wn)
    log("head fit:", S3.HEAD_FIT, "targets:", S3.TARGET_SET)
    if S3.HEAD_FIT == "v2":
        V.head_fit(hm, groups, bones, Wn)
        V.face_relax(hm, groups, bones, Wn)
    else:
        head_fit3(hm, groups, bones, Wn)
    sculpt(hm, groups, S3.FACE_SCULPT, "face")
    return root, hm, groups, bones, Wn


def finish(root, hm, groups, bones, Wn):
    sc = bpy.context.scene
    body_mask = np.zeros(len(hm.data.vertices), bool); body_mask[groups["body"]] = True
    v1b = None
    if OPT["stage"] != "face":
        with bpy.data.libraries.load(V.V1_BLEND, link=False) as (src, dst):
            dst.objects = ["Exit6_Male_Body"]
        v1b = dst.objects[0]; v1b.name = "Exit6_Male_Body_V1"
        for m in list(v1b.modifiers):
            v1b.modifiers.remove(m)
        for o in list(bpy.data.objects):
            if o.type == "ARMATURE":
                bpy.data.objects.remove(o)
        V.body_fit(hm, v1b, bones, Wn, body_mask)
        V.shoulder_relax(hm, groups)
        sculpt(hm, groups, S3.BODY_SCULPT, "body")
        # the muscle-relief shrinkwrap target gets the same strokes, or it would pull the skin back
        sculpt(v1b, None, S3.BODY_SCULPT, "detail target")
    eyes = V.MP.HS.add_mhclo_asset(os.path.join(V.MP.udata, "eyes", "high-poly", "high-poly.mhclo"), hm,
                                   asset_type="Eyes", subdiv_levels=0, material_type="MAKESKIN",
                                   set_up_rigging=False, interpolate_weights=False, import_subrig=False,
                                   import_weights=False)
    eyes.name = "Exit6_Male_Eyes"
    for c in list(eyes.users_collection):
        c.objects.unlink(eyes)
    root.objects.link(eyes)
    eyes.parent = None
    eye_material3(eyes)
    skin_colors3(hm, groups)
    hm.data.materials.clear(); hm.data.materials.append(V.skin_material())
    bvh = V.head_bvh_px(hm, groups)
    tmp = bpy.data.collections.new("tmp_px"); sc.collection.children.link(tmp)
    brows = build_brows3(bvh, tmp)
    gv_, gf_, gthick = H3.goatee(bvh)
    goatee = B.make_obj("Exit6_Male_Goatee", gv_, gf_, tmp)
    Wg = B.wmat(len(gv_)); Wg[:, B.BI["Head"]] = 1
    B.assign_groups(goatee, Wg)
    extra = [brows, goatee]
    hair = hair_g = scalp = None
    if OPT["hair"]:
        roots, paths, (hv, hf), (gv, gf) = H3.build(bvh)
        log("hair: %d twists" % len(paths))
        hair = B.make_obj("Exit6_Male_Hair_Twists", hv, hf, tmp)
        hair_g = B.make_obj("Exit6_Male_Hair_Game", gv, gf, tmp)
        for ob in (hair, hair_g):
            Wh = B.wmat(len(ob.data.vertices)); Wh[:, B.BI["Head"]] = 1
            B.assign_groups(ob, Wh)
        hair_g.hide_render = True
        scalp = B.build_scalp_cap(bvh, roots, tmp)
        H3.recolor_scalp(scalp, roots, S.HAIR_SRGB)
        extra += [hair, scalp, hair_g]
    M = B.make_materials()
    for ob in extra:
        ob.data.transform(Matrix.Scale(K, 4))
        for m in ob.modifiers:
            if m.type == "SOLIDIFY":
                m.thickness *= K
        tmp.objects.unlink(ob); root.objects.link(ob)
        ob.data.materials.append(M["scalp"] if ob.name.endswith("Scalp") else M["hair"])
    H3.goatee_material(goatee)
    bpy.data.collections.remove(tmp)
    sub = hm.modifiers.new("Subdiv", "SUBSURF"); sub.levels = 1; sub.render_levels = 2
    cam = B.setup_render(OPT["samples"])
    neutral_lights()
    if OPT["stage"] == "face":
        if OPT["render"]:
            review_face(cam, OPT["tag"], extra)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "face_lab%s.blend" % OPT["tag"]))
        log("face stage done")
        return
    # ---------------- full stage (as V2): body-only mesh, weights, briefs, rig, relief
    hm.modifiers.remove(sub)
    V.strip_helpers(hm, groups)
    W = V.r15_weights(hm, v1b, bones, Wn, groups, body_mask)
    B.assign_groups(hm, W)
    briefs = V.make_briefs(hm, W, root)
    V.tuck_under_briefs(hm, W)
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
    dm = np.clip(dmask[V.STRIP["keep"]], 0, 1) * S3.DETAIL_STRENGTH
    Qk = to_Q(B.mesh_arrays(hm))
    for (x, Y, row), r in S3.DETAIL_FADE:
        for sx in ((1, -1) if x else (1,)):
            d = np.linalg.norm(Qk - np.array([x * sx, Y, row]), axis=1)
            dm *= np.clip((d - r * 0.55) / (r * 0.45), 0, 1)
    r_ = Qk[:, 2]
    dm *= 1 - np.clip((r_ - 596) / 8, 0, 1) * np.clip((776 - r_) / 8, 0, 1)
    side_band = (Qk[:, 2] < 600) & (Qk[:, 2] > 400)
    dm[side_band] *= np.clip((S3.DETAIL_SIDE_X - np.abs(Qk[side_band, 0])) / 10.0, 0, 1)
    q = np.round(dm * 50).astype(int)
    for val in np.unique(q):
        if val > 0:
            vg.add(np.nonzero(q == val)[0].tolist(), val / 50.0, "REPLACE")
    briefs.data.materials.append(M["briefs"])
    rig = B.build_rig(root)
    char = [hm, eyes, briefs] + extra
    B.bind([v1b], rig)
    We = B.wmat(len(eyes.data.vertices)); We[:, B.BI["Head"]] = 1
    B.assign_groups(eyes, We)
    B.bind(char, rig)
    s_ = hm.modifiers.new("Subdiv", "SUBSURF"); s_.levels = 1; s_.render_levels = 2
    dsw = hm.modifiers.new("MuscleDetail", "SHRINKWRAP"); dsw.target = v1b
    dsw.wrap_method = "PROJECT"; dsw.use_negative_direction = True; dsw.use_positive_direction = True
    dsw.project_limit = S3.DETAIL_LIMIT; dsw.vertex_group = "DetailFit"; dsw.wrap_mode = "ON_SURFACE"
    sol = [m for m in briefs.modifiers if m.type == "SOLIDIFY"]
    th = sol[0].thickness if sol else 0.7 * K
    for m in sol:
        briefs.modifiers.remove(m)
    s_ = briefs.modifiers.new("Subdiv", "SUBSURF"); s_.levels = 1; s_.render_levels = 2
    so = briefs.modifiers.new("thick", "SOLIDIFY"); so.thickness = th; so.offset = -1
    B.build_pose_action(rig)
    V.fix_crouch(rig, hm)
    sc.frame_set(1)
    stats = {}
    for ob in char:
        me = ob.data; me.calc_loop_triangles()
        stats[ob.name] = {"verts": len(me.vertices), "tris": len(me.loop_triangles)}
    with open(os.path.join(OUT_DIR, "build_stats_v3.json"), "w") as fh:
        json.dump({"studs_per_ref_px": K, "objects": stats, "bones": [b.name for b in rig.data.bones],
                   "mpfb_macro": S3.MACRO, "face_targets": S3.FACE_TARGETS,
                   "hand_scale": S3.HAND_SCALE, "finger_close": S3.FINGER_CLOSE,
                   "face_strokes": [b["name"] for b in S3.FACE_SCULPT],
                   "body_strokes": [b["name"] for b in S3.BODY_SCULPT], "hair": H3.TUNE}, fh, indent=1)
    log(json.dumps(stats))
    if OPT["render"]:
        B.render_views(cam, "render_v3")
        if OPT.get("quick"):
            bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "body_lab.blend"), compress=True)
            log("quick renders done")
            return
        review_face(cam, "", extra)
        V.hair_closeups(cam, hair, hair_g, scalp)
        for fi, pname in enumerate(B.POSES, start=1):
            if pname == "rest":
                continue
            sc.frame_set(fi)
            B.render_views(cam, "pose_v3_%s" % pname, {"three_quarter": 35.0, "front": 0.0})
        sc.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=V3_BLEND, compress=True)
    log("saved", V3_BLEND)


def main():
    root, hm, groups, bones, Wn = build_head()
    finish(root, hm, groups, bones, Wn)


if __name__ == "__main__":
    main()
