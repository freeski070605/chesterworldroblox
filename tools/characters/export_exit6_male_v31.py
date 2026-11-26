"""Game export of the Exit 6 male V3.1 (approved V3 + polish).

    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3_1.blend \
        -P tools/characters/export_exit6_male_v31.py [-- --levels=3] [--no-bake]

Outputs (assets/characters/exit6_male/):
  Exit6_Male_V3_1_Body.glb   15 capped R15 <Part>_Geo meshes skinned to the R15 rig,
                             19 <Name>_Att attachment markers, 15 <Part>_OuterCage cages
                             (Roblox body cage template topology + UVs, fitted to V3.1)
  Exit6_Male_V3_1_Parts.glb  separate, unskinned customisable pieces in the same frame:
                             Hair_Geo, Eyes_Geo, Brows_Geo, Goatee_Geo, Briefs_Geo
  Exit6_Male_V3_1_Game.blend the game objects only, plus Exit6V31_BodyCage (the fitted
                             1358-vertex template cage; inner cage for V3.1 clothing)
  textures_v3_1/*.png        Body colour + sculpted normal (2048), Hair, FaceDetails, Briefs
  export_report_v31.json

The source .blend is never written.

Detail: the bake source is the V3 body at subdivision level 3 (~0.85 M verts)
displaced by the anatomy relief maps (exit6_anatomy_v31.py: pec / ab / serratus /
oblique / deltoid / arm / leg / back separations, veins) along its normals, with
cavity darkening in the colour. The game mesh topology and silhouette are V3's.
The old V1 "MuscleDetail" shrinkwrap (blocky ab grid) is left out of the bake.
"""
import bpy, bmesh, os, sys, json, math, time
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exit6_male_spec as S
import exit6_anatomy_v31 as AN
import export_exit6_male_v3 as E          # bake / split / rig / attachment helpers (main() is guarded)

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {"levels": 3, "bake": True}
for a in ARGV:
    if a.startswith("--levels="): OPT["levels"] = int(a.split("=")[1])
    if a == "--no-bake": OPT["bake"] = False
REPO = E.REPO
OUT = E.OUT
TEX = os.path.join(OUT, "textures_v3_1")
os.makedirs(TEX, exist_ok=True)
E.TEX = TEX
K = E.K
SOLE = S.SOLE
TEMPLATE = os.path.join(REPO, "build", "roblox_templates", "Body_Cage_Templates", "Body_Cage_Templates",
                        "Body_Cage_Template.blend")
CAGE_OFFSET = 0.03        # studs outside the skin
T0 = time.time()
BONES = E.BONES
REGION_OF = {"LowerTorso": "torso", "UpperTorso": "torso", "Head": "head"}
for b in BONES:
    if "Arm" in b or "Hand" in b: REGION_OF[b] = "arm"
    if "Leg" in b or "Foot" in b: REGION_OF[b] = "leg"


def log(*a):
    print("[export31 %6.1fs]" % (time.time() - T0), *a, flush=True)


def arr(me, attr="co"):
    a = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get(attr, a)
    return a.reshape(-1, 3)


def to_Q(P):
    return np.stack([P[:, 0] / K, P[:, 1] / K, SOLE - P[:, 2] / K], 1)


# ------------------------------------------------------------ sculpted bake source
def region_weights(src, n_hi, hi_P):
    """soft torso/arm/leg/head membership per hi-res vertex from the base body's R15 weights"""
    me = src.data
    names = [vg.name for vg in src.vertex_groups]
    W = np.zeros((len(me.vertices), 4))
    cols = {"torso": 0, "arm": 1, "leg": 2, "head": 3}
    for v in me.vertices:
        for g in v.groups:
            r = REGION_OF.get(names[g.group])
            if r:
                W[v.index, cols[r]] += g.weight
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    P0 = arr(me) @ np.array(src.matrix_world)[:3, :3].T + np.array(src.matrix_world)[:3, 3]
    kd = KDTree(len(P0))
    for i, p in enumerate(P0):
        kd.insert(Vector(p), i)
    kd.balance()
    out = np.zeros((n_hi, 4))
    for i in range(n_hi):
        acc = np.zeros(4); tw = 0.0
        for (_, j, d) in kd.find_n(Vector(hi_P[i]), 3):
            w = 1.0 / (d + 1e-4); acc += W[j] * w; tw += w
        out[i] = acc / tw
    return {k: out[:, c] for k, c in cols.items()}


def build_sculpt_source(body):
    sc = bpy.context.scene
    states = {}
    for m in body.modifiers:
        states[m.name] = (m.show_viewport, m.show_render)
        if m.type == "SHRINKWRAP":
            m.show_viewport = m.show_render = False
        if m.type == "SUBSURF":
            states[m.name] += (m.levels,)
            m.levels = OPT["levels"]
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    for m in body.modifiers:
        st = states[m.name]
        m.show_viewport, m.show_render = st[0], st[1]
        if m.type == "SUBSURF":
            m.levels = st[2]
    ob = bpy.data.objects.new("Exit6_Male_Body_Sculpt", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = body.matrix_world.copy()
    P = arr(me) @ np.array(ob.matrix_world)[:3, :3].T + np.array(ob.matrix_world)[:3, 3]
    N = arr(me, "normal")
    log("sculpt source: %d verts (level %d)" % (len(P), OPT["levels"]))
    Q = to_Q(P)
    rw = region_weights(body, len(P), P)
    # the neck in front belongs to Head: let torso features (sternal notch, SCM) reach it below the jaw
    neck = rw["head"] * np.clip((Q[:, 2] - 350) / 8, 0, 1)
    region = {"torso": rw["torso"] + neck, "arm": rw["arm"], "leg": rw["leg"]}
    maps = AN.load()
    disp = AN.relief(maps, Q, N, region)
    P2 = P + N * (disp * K)[:, None]
    Wi = np.linalg.inv(np.array(ob.matrix_world))
    me.vertices.foreach_set("co", (P2 @ Wi[:3, :3].T + Wi[:3, 3]).astype(np.float32).ravel())
    me.update()
    log("relief: min %.2f max %.2f px, |d|>0.3 px on %.0f%% of verts" %
        (disp.min(), disp.max(), 100 * (np.abs(disp) > 0.3).mean()))
    # colour: cavity darkening in grooves, a touch of light on bellies, areola / nipple tone
    ca = me.color_attributes.get("Col")
    if ca and ca.domain == "POINT":
        col = np.zeros(len(P) * 4, np.float32); ca.data.foreach_get("color", col); col = col.reshape(-1, 4)
        cav = np.clip(-disp / 1.6, 0, 1); bel = np.clip(disp / 1.6, 0, 1)
        f = (1 - 0.16 * cav ** 0.8) * (1 + 0.035 * bel)
        col[:, :3] *= f[:, None]
        front = np.clip(-N[:, 1], 0, 1)
        for sx in (1, -1):
            d = np.hypot(Q[:, 0] - 57 * sx, Q[:, 2] - 460) * front
            dd = np.where(front > 0.3, np.hypot(Q[:, 0] - 57 * sx, Q[:, 2] - 460), 1e9)
            a = np.clip((4.0 - dd) / 1.2, 0, 1) * rw["torso"]
            tone = np.array([0.075, 0.032, 0.020])            # linear (~78, 50, 38 sRGB)
            col[:, :3] = col[:, :3] * (1 - 0.7 * a[:, None]) + tone * 0.7 * a[:, None]
        ca.data.foreach_set("color", col.ravel())
    else:
        log("WARNING: no point-domain Col attribute on the sculpt source")
    ob.data.materials.clear()
    for m in body.data.materials:
        ob.data.materials.append(m)
    np.save(os.path.join(REPO, "build", "exit6_v3", "polish", "relief_stats.npy"),
            np.array([disp.min(), disp.max(), np.abs(disp).mean()]))
    return ob


# ------------------------------------------------------------ R15 caps
def cap_parts(parts, skin_uv):
    """close every open boundary loop of every part (Roblox: each part watertight).
    Seams between parts get a fan to the loop centroid; the head's face openings
    (eyes, mouth) get a fan to a point recessed into the skull so the cap stays
    behind the eyeballs."""
    rep = {}
    for name, ob in parts.items():
        bm = bmesh.new(); bm.from_mesh(ob.data)
        uv = bm.loops.layers.uv.active
        dv = bm.verts.layers.deform.verify()
        loops = []
        seen = set()
        bedges = [e for e in bm.edges if e.is_boundary]
        for e0 in bedges:
            if e0 in seen:
                continue
            loop = []; e = e0; v = e0.verts[0]
            while True:
                seen.add(e); loop.append(v)
                v = e.other_vert(v)
                nxt = [x for x in v.link_edges if x.is_boundary and x not in seen]
                if not nxt:
                    break
                e = nxt[0]
            loops.append(loop)
        head_c = None
        if name == "Head":
            P = np.array([v.co for v in bm.verts]); head_c = P.mean(0)
        caps = []
        for loop in loops:
            C = np.array([v.co for v in loop]).mean(0)
            recess = name == "Head" and C[2] > head_c[2] - 0.25 and C[1] < head_c[1] - 0.12
            if recess:
                C = C + np.array([0, 0.12, 0])
            cv = bm.verts.new(Vector(C))
            # weights: average of the loop
            acc = {}
            for v in loop:
                for g, w in v[dv].items():
                    acc[g] = acc.get(g, 0) + w / len(loop)
            for g, w in acc.items():
                cv[dv][g] = w
            nf = 0
            for a, b in zip(loop, loop[1:] + loop[:1]):
                e = bm.edges.get((a, b))
                order = (b, a, cv)
                if e is not None and e.link_faces:
                    f0 = e.link_faces[0]
                    for l in f0.loops:              # f0 walks a->b: the cap must walk b->a
                        if l.vert == b and l.link_loop_next.vert == a:
                            order = (a, b, cv)
                            break
                try:
                    f = bm.faces.new(order)
                except ValueError:
                    continue
                nf += 1
                for l in f.loops:
                    l[uv].uv = skin_uv
            caps.append({"verts": len(loop), "recessed": bool(recess), "faces": nf})
        bm.to_mesh(ob.data); bm.free()
        bm = bmesh.new(); bm.from_mesh(ob.data)
        open_edges = sum(1 for e in bm.edges if e.is_boundary)
        nonman = sum(1 for e in bm.edges if not e.is_manifold)
        bm.free()
        rep[name] = {"caps": caps, "open_edges_after": open_edges, "non_manifold_edges": nonman}
    return rep


# ------------------------------------------------------------ cage fitting
def load_template():
    with bpy.data.libraries.load(TEMPLATE, link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n.endswith("_OuterCage") or n in
                       ("std_cage_deformable", "Body Cages", "std_cage_parts", "Armature")]
    tmp = bpy.data.collections.new("TemplateTmp"); bpy.context.scene.collection.children.link(tmp)
    for o in dst.objects:
        if o:
            tmp.objects.link(o)
    for o in tmp.objects:
        for m in list(getattr(o, "modifiers", [])):
            o.modifiers.remove(m)           # the GN snap is reproduced in numpy
    bpy.context.view_layer.update()
    return tmp


def world_P(ob):
    M = np.array(ob.matrix_world)
    return arr(ob.data) @ M[:3, :3].T + M[:3, 3]


def mesh_normals(P, faces, n):
    N = np.zeros((n, 3))
    for f in faces:
        a, b, c = P[f[0]], P[f[1]], P[f[2]]
        fn = np.cross(b - a, c - a)
        for i in f:
            N[i] += fn
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def bone_frame(head, tail):
    y = tail - head; L = np.linalg.norm(y); y = y / max(L, 1e-9)
    ref = np.array([0, -1.0, 0]) if abs(y[1]) < 0.9 else np.array([0, 0, 1.0])
    x = np.cross(y, ref); x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], 1), L


def fit_cage(tmpl, rig, parts, game_body):
    deform = tmpl.objects["std_cage_deformable"]
    T = world_P(deform)
    me = deform.data
    faces = [tuple(p.vertices) for p in me.polygons]
    n = len(T)
    # part membership of each deformable vertex (template part cages coincide with it)
    kd = KDTree(n)
    for i, p in enumerate(T):
        kd.insert(Vector(p), i)
    kd.balance()
    member = np.zeros((n, len(BONES)))
    part_match = {}
    for bi, b in enumerate(BONES):
        pc = tmpl.objects.get(b + "_OuterCage")
        Pp = world_P(pc)
        idx = []; dmax = 0
        for p in Pp:
            _, j, d = kd.find(Vector(p)); idx.append(j); dmax = max(dmax, d)
        part_match[b] = (np.array(idx), dmax)
        member[np.array(idx), bi] = 1
    member /= np.maximum(member.sum(1, keepdims=True), 1e-9)
    # diffuse membership a little across joints so the bone warp blends
    adj = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices; adj[a].append(b); adj[b].append(a)
    Wm = member.copy()
    for _ in range(3):
        Wm = 0.5 * Wm + 0.5 * np.array([Wm[a].mean(0) if a else Wm[i] for i, a in enumerate(adj)])
    # bone warp: template R15 bones -> game rig bones
    tarm = tmpl.objects["Armature"]
    TM = np.array(tarm.matrix_world)
    tb = {b.name: (TM[:3, :3] @ np.array(b.head_local) + TM[:3, 3], TM[:3, :3] @ np.array(b.tail_local) + TM[:3, 3])
          for b in tarm.data.bones}
    gb = {b.name: (np.array(b.head_local), np.array(b.tail_local)) for b in rig.data.bones}
    X = np.zeros((n, 3))
    stretch = {"UpperArm", "LowerArm", "UpperLeg", "LowerLeg"}
    for bi, b in enumerate(BONES):
        if b.endswith("Foot"):
            # the template foot bone lies along the sole, ours runs ankle -> toe: map boxes instead
            sel = member[:, bi] > 0
            tmin, tmax = T[sel].min(0), T[sel].max(0)
            M = np.array(parts[b].matrix_world)
            G_ = arr(parts[b].data) @ M[:3, :3].T + M[:3, 3]
            gmin, gmax = G_.min(0), G_.max(0)
            X += Wm[:, bi:bi + 1] * ((T - tmin) / (tmax - tmin) * (gmax - gmin) + gmin)
            continue
        Rt, Lt = bone_frame(*tb[b]); Ro, Lo = bone_frame(*gb[b])
        s = Lo / Lt if any(k in b for k in stretch) else 1.0
        loc = (T - tb[b][0]) @ Rt
        loc[:, 1] *= s
        X += Wm[:, bi:bi + 1] * (gb[b][0] + loc @ Ro.T)
    log("cage bone warp done; max template->part match distance %.4f" %
        max(v[1] for v in part_match.values()))
    # surface fit against each vertex's own part(s)
    bvh = {}
    for b, ob in parts.items():
        M = np.array(ob.matrix_world)
        Pp = arr(ob.data) @ M[:3, :3].T + M[:3, 3]
        bvh[b] = BVHTree.FromPolygons([Vector(p) for p in Pp], [tuple(p.vertices) for p in ob.data.polygons])
    owners = [[BONES[k] for k in np.nonzero(member[i] > 0)[0]] for i in range(n)]
    tri = []
    for f in faces:
        for k in range(1, len(f) - 1):
            tri.append((f[0], f[k], f[k + 1]))

    def surf(i, p, nrm):
        best = None
        for b in owners[i]:
            for d in (-nrm, nrm):
                h = bvh[b].ray_cast(Vector(p + nrm * 0.0 - d * 0.0), Vector(d), 0.35)
                if h[0] is not None:
                    dist = (np.array(h[0]) - p) @ (np.array(h[0]) - p)
                    if best is None or dist < best[0]:
                        best = (dist, np.array(h[0]), np.array(h[1]))
            c = bvh[b].find_nearest(Vector(p))
            if c[0] is not None:
                dist = (np.array(c[0]) - p) @ (np.array(c[0]) - p)
                if best is None or dist < best[0] * 0.6:
                    best = (dist, np.array(c[0]), np.array(c[1]))
        return best

    def lap(Y):
        return np.array([Y[a].mean(0) - Y[i] if a else np.zeros(3) for i, a in enumerate(adj)])

    for it in range(40):
        N = mesh_normals(X, tri, n)
        tgt = X.copy()
        for i in range(n):
            s_ = surf(i, X[i], N[i])
            if s_ is not None:
                nn = s_[2] if s_[2] @ N[i] > 0 else -s_[2]
                tgt[i] = s_[1] + nn * CAGE_OFFSET
        X += 0.6 * (tgt - X)
        X += 0.35 * lap(X)               # Taubin pair keeps spacing even without shrinking
        X -= 0.36 * lap(X)
    # final: make sure nothing ends inside the skin
    inside = 0; clear = []
    for i in range(n):
        best = None
        for b in owners[i]:
            c = bvh[b].find_nearest(Vector(X[i]))
            if c[0] is not None:
                d = np.linalg.norm(np.array(c[0]) - X[i])
                if best is None or d < best[0]:
                    best = (d, np.array(c[0]), np.array(c[1]))
        if best is None:
            continue
        sd = (X[i] - best[1]) @ best[2]
        if sd < CAGE_OFFSET * 0.5:
            inside += sd < 0
            X[i] = best[1] + best[2] * CAGE_OFFSET * 0.5
            sd = CAGE_OFFSET * 0.5
        clear.append(sd)
    clear = np.array(clear)
    log("cage fit: clearance mean %.4f min %.4f max %.4f studs; %d verts pushed out from inside" %
        (clear.mean(), clear.min(), clear.max(), inside))
    return X, T, part_match, {"clearance_mean": float(clear.mean()), "clearance_min": float(clear.min()),
                              "clearance_max": float(clear.max()), "pushed_from_inside": int(inside)}


def make_cages(tmpl, X, T, part_match, coll, rig):
    """the 1358-vertex fitted cage + the 15 part cages (each part-cage vertex takes the
    displacement of the deformable vertex it coincides with, like the template's GN setup)"""
    deform = tmpl.objects["std_cage_deformable"]
    me = deform.data.copy(); me.name = "Exit6V31_BodyCage"
    ob = bpy.data.objects.new("Exit6V31_BodyCage", me)
    coll.objects.link(ob)
    me.vertices.foreach_set("co", X.astype(np.float32).ravel()); me.update()
    ob.hide_render = True
    out = {}
    D = X - T
    for b in BONES:
        pc = tmpl.objects[b + "_OuterCage"]
        pm = pc.data.copy(); pm.name = b + "_OuterCage"
        Pp = world_P(pc)
        idx, _ = part_match[b]
        Pn = Pp + D[idx]
        pm.vertices.foreach_set("co", Pn.astype(np.float32).ravel()); pm.update()
        po = bpy.data.objects.new(b + "_OuterCage", pm)
        coll.objects.link(po)
        po.hide_render = True
        out[b] = po
    return ob, out


# ------------------------------------------------------------ main
def main():
    sc = bpy.context.scene
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
    sc.frame_set(1)
    O = bpy.data.objects
    src_rig = O["Exit6_Male_Rig"]
    src_rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    coll = bpy.data.collections.new("Exit6_Male_V3_1_Game")
    sc.collection.children.link(coll)
    report = {"objects": {}, "textures": {}, "source": os.path.basename(bpy.data.filepath)}
    bsrc = O["Exit6_Male_Body"]
    body = E.copy_rest(bsrc, coll, "Game_Body", keep_mods=())
    if OPT["bake"]:
        sculpt = build_sculpt_source(bsrc)
        report["textures"]["Body"] = E.bake(body, [sculpt], 2048, "Exit6V31_Body", normal=True,
                                            extrusion=0.03, ray=0.07)
        bpy.data.objects.remove(sculpt)
        log("body baked")
    # hair
    hair = E.copy_rest(O["Exit6_Male_Hair_Game"], coll, "Game_Hair")
    scalp = E.copy_rest(O["Exit6_Male_Hair_Scalp"], coll, "Game_Scalp", decimate=1600)
    E.activate(hair); scalp.select_set(True); bpy.ops.object.join()
    E.smart_uv(hair)
    if OPT["bake"]:
        report["textures"]["Hair"] = E.bake(hair, [O["Exit6_Male_Hair_Twists"], O["Exit6_Male_Hair_Scalp"]], 1024,
                                            "Exit6V31_Hair", normal=True, extrusion=0.03, ray=0.06)
    hair.name = hair.data.name = "Hair_Geo"
    # face details: eyes / brows / goatee share one atlas, then split into separate pieces
    eyes = E.copy_rest(O["Exit6_Male_Eyes"], coll, "Eyes_Geo", keep_mods=())
    bm = bmesh.new(); bm.from_mesh(eyes.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == 1], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(eyes.data); bm.free()
    brows = E.copy_rest(O["Exit6_Male_Brows"], coll, "Brows_Geo")
    goatee = E.copy_rest(O["Exit6_Male_Goatee"], coll, "Goatee_Geo", decimate=1200)
    tag = {}
    for k, o in enumerate((eyes, brows, goatee)):
        a = o.data.attributes.new("piece", "INT", "FACE")
        a.data.foreach_set("value", np.full(len(o.data.polygons), k, np.int32))
        tag[k] = o.name
    E.activate(eyes); brows.select_set(True); goatee.select_set(True); bpy.ops.object.join()
    face = eyes
    E.smart_uv(face)
    if OPT["bake"]:
        report["textures"]["FaceDetails"] = E.bake(face, [O["Exit6_Male_Eyes"], O["Exit6_Male_Brows"],
                                                          O["Exit6_Male_Goatee"]], 1024, "Exit6V31_FaceDetails",
                                                   extrusion=0.01, ray=0.03)
    pieces = {}
    pv = np.zeros(len(face.data.polygons), np.int32); face.data.attributes["piece"].data.foreach_get("value", pv)
    for k, name in tag.items():
        ob = face.copy(); ob.data = face.data.copy(); coll.objects.link(ob)
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i in range(len(pv)) if pv[i] != k], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(ob.data); bm.free()
        ob.name = ob.data.name = name
        pieces[name] = ob
    bpy.data.objects.remove(face)
    briefs = E.copy_rest(O["Exit6_Male_Briefs"], coll, "Briefs_Geo", decimate=3000)
    briefs.name = briefs.data.name = "Briefs_Geo"
    E.smart_uv(briefs)
    if OPT["bake"]:
        report["textures"]["Briefs"] = E.bake(briefs, [O["Exit6_Male_Briefs"]], 1024, "Exit6V31_Briefs",
                                              extrusion=0.02, ray=0.04)
    log("details baked")
    W, names = E.limit_weights(body)
    extras = [hair, briefs] + list(pieces.values())
    for o in extras:
        E.limit_weights(o)
    # a skin texel for the cap faces (mid upper back)
    me = body.data
    P = arr(me); uvl = me.uv_layers.active.data
    vi = int(np.argmin(np.linalg.norm(P - np.array([0.0, 0.45, P[:, 2].min() + 0.62 * np.ptp(P[:, 2])]), axis=1)))
    skin_uv = None
    for l in me.loops:
        if l.vertex_index == vi:
            skin_uv = tuple(uvl[l.index].uv); break
    parts = E.split_r15(body, W, names, coll)
    hips = Vector(src_rig.data.bones["LowerTorso"].head_local)
    offset = -hips
    allm = list(parts.values()) + extras
    for o in allm:
        o.data.transform(Matrix.Translation(offset))
    bpy.data.objects.remove(body)
    report["caps"] = cap_parts(parts, skin_uv)
    log("caps:", {k: (len(v["caps"]), v["open_edges_after"]) for k, v in report["caps"].items()})
    rig = E.build_game_rig(coll, offset, src_rig)
    rig.name = rig.data.name = "Exit6_Male_V3_1_GameRig"
    for o in list(parts.values()) + [briefs]:
        o.parent = rig
        o.modifiers.clear()
        m = o.modifiers.new("Armature", "ARMATURE"); m.object = rig
    # separate pieces are static (attached / welded in Roblox): drop skinning
    for o in [hair] + list(pieces.values()):
        o.modifiers.clear(); o.parent = None
        for vg in list(o.vertex_groups):
            o.vertex_groups.remove(vg)
    bpy.context.view_layer.update()
    report["attachments"] = E.make_attachments(parts, rig, coll)
    # Roblox's templates parent the _Att markers to the R15 bones; mesh-parented markers import onto
    # HumanoidRootPart (seen in the V3.1 test import), so re-parent them to their part's bone.
    # make_attachments leaves the new markers unevaluated: without this update the first marker's
    # matrix_world reads as identity and it lands on the rig origin (FaceCenter_Att did, 2.24 studs off).
    bpy.context.view_layer.update()
    worlds = {name: bpy.data.objects[name].matrix_world.copy() for name in report["attachments"]}
    for name, info in report["attachments"].items():
        att = bpy.data.objects[name]
        att.parent = rig; att.parent_type = "BONE"; att.parent_bone = info["part"].replace("_Geo", "")
    bpy.context.view_layer.update()
    for name in report["attachments"]:
        bpy.data.objects[name].matrix_world = worlds[name]
    bpy.context.view_layer.update()
    for name, info in report["attachments"].items():
        got = bpy.data.objects[name].matrix_world.translation
        err = (got - Vector(info["pos"])).length
        assert err < 1e-3, f"{name} placed {err:.4f} studs from its marker position"
    # cages
    tmpl = load_template()
    X, T, pm, fitrep = fit_cage(tmpl, rig, parts, None)
    report["cage_fit"] = fitrep
    full_cage, part_cages = make_cages(tmpl, X, T, pm, coll, rig)
    for o in list(tmpl.objects):
        bpy.data.objects.remove(o)
    bpy.data.collections.remove(tmpl)
    for b, o in part_cages.items():          # created while the template's same-named objects existed
        o.name = o.data.name = b + "_OuterCage"
        assert o.name == b + "_OuterCage", o.name
    total = 0
    for o in allm:
        o.data.calc_loop_triangles()
        nt = len(o.data.loop_triangles); total += nt
        report["objects"][o.name] = {"verts": len(o.data.vertices), "tris": nt}
    report["total_tris"] = total
    report["r15_body_tris"] = sum(report["objects"][p + "_Geo"]["tris"] for p in BONES)
    report["offset_studs"] = list(offset)
    report["cages"] = {b: len(o.data.vertices) for b, o in part_cages.items()}
    # body GLB: rig + parts + attachments + cages
    body_set = set([rig] + list(parts.values()) + list(part_cages.values()) +
                   [o for o in coll.objects if o.name.endswith("_Att")])
    for o in bpy.context.view_layer.objects:
        o.hide_set(False)
        o.select_set(o in body_set)
    glb = os.path.join(OUT, "Exit6_Male_V3_1_Body.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_yup=True, export_apply=False, export_morph=False)
    log("exported", glb)
    # parts GLB: static customisable pieces (briefs stay skinned)
    for o in bpy.context.view_layer.objects:
        o.select_set(o in set([hair, briefs, rig] + list(pieces.values())))
    glb2 = os.path.join(OUT, "Exit6_Male_V3_1_Parts.glb")
    bpy.ops.export_scene.gltf(filepath=glb2, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_yup=True, export_apply=False, export_morph=False)
    log("exported", glb2)
    with open(os.path.join(OUT, "export_report_v31.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    src_rig.data.pose_position = "POSE"
    E.save_game_only(coll, os.path.join(OUT, "Exit6_Male_V3_1_Game.blend"))
    log("done; total tris", total, "body", report["r15_body_tris"])


if __name__ == "__main__":
    main()
