"""Exit 6 male V3.1 source polish, on top of the approved V3 (no rebuild).

    # strip the game copy out of a source file in place (fixes the upside-down duplicate)
    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend \
        -P tools/characters/polish_exit6_male_v31.py -- --strip-only

    # V3.blend -> Exit6_Male_V3_1.blend
    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend \
        -P tools/characters/polish_exit6_male_v31.py

What it changes (face shape, body shape, hair, rig and weights are untouched):
  * removes the *_Game collection that the old export saved into the source
    (split R15 parts on the game rig: they showed up as an inverted duplicate);
  * brows: same outline as V3, rebuilt as a feathered shell that sits ~0.8 px
    off the skin (V3: 1.5 px slab with vertical walls), with hair-strand colour
    and skin-toned edges so the bake reads as hair, not a block;
  * eyes: slightly warmer / darker sclera, a soft shadow under the upper lid and
    darker corners, so the eye no longer shows a bright ring of white.
The muscle / skin relief is baked at export time (export_exit6_male_v31.py),
so the source stays small.
"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exit6_male_spec as S
import build_exit6_male as B

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "characters", "exit6_male")
V31_BLEND = os.path.join(OUT, "Exit6_Male_V3_1.blend")
K = S.HEIGHT_STUDS / (S.SOLE - S.SKULL_TOP)
SOLE = S.SOLE
SKIN_SRGB = (152, 87, 47)
BROW_SRGB = (18, 12, 9)
SCLERA_SRGB = (212, 198, 186)        # V3: (226, 216, 206)
LOG = []


def log(*a):
    s = " ".join(str(x) for x in a)
    LOG.append(s)
    print("[polish31]", s, flush=True)


def strip_game_copies():
    n = 0
    for c in list(bpy.data.collections):
        if c.name.endswith("_Game"):
            for o in list(c.objects):
                for ch in list(o.children):
                    if not any(cc.name.endswith("_Game") for cc in ch.users_collection):
                        ch.parent = None
                bpy.data.objects.remove(o); n += 1
            bpy.data.collections.remove(c)
    for blk in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
        for d in list(blk):
            if d.users == 0:
                blk.remove(d)
    log("removed %d game-copy objects" % n)
    return n


# ------------------------------------------------------------------ brows
def head_bvh_px():
    """BVH of the rest-pose body in reference-pixel space (world / K)"""
    body = bpy.data.objects["Exit6_Male_Body"]
    me = body.data
    P = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3)
    W = np.array(body.matrix_world)
    P = (P @ W[:3, :3].T + W[:3, 3]) / K
    polys = [tuple(p.vertices) for p in me.polygons]
    return BVHTree.FromPolygons([Vector(p) for p in P], polys)


def hit(bvh, x, row):
    loc, n, _, _ = bvh.ray_cast(Vector((x, -200.0, SOLE - row)), Vector((0, 1.0, 0)))
    if loc is None:
        return None, None
    n = np.array(n)
    if n[1] > 0:
        n = -n
    return np.array(loc), n


# V3 outline (x, centre row, thickness) from build_brows3, outer tail -> inner head
BROW_PTS = [(-29, 262.5, 5.2), (-24, 262.0, 6.8), (-18, 262.8, 7.6),
            (-12.5, 264.6, 8.0), (-8.0, 266.8, 8.2), (-5.2, 268.2, 7.6)]
# feathered cross-section: (v across the brow, height px, hair weight 0..1); closed under the skin
PROFILE = [(-0.56, -0.5, 0.0), (-0.47, 0.25, 0.35), (-0.32, 0.65, 1.0), (-0.08, 0.85, 1.0),
           (0.18, 0.85, 1.0), (0.38, 0.6, 1.0), (0.5, 0.2, 0.45), (0.58, -0.5, 0.0), (0.0, -1.0, 0.0)]


def build_brows():
    old = bpy.data.objects.get("Exit6_Male_Brows")
    rig = old.parent if old else None
    colls = list(old.users_collection) if old else [bpy.context.scene.collection]
    mats = list(old.data.materials) if old else []
    bvh = head_bvh_px()
    # densify along the brow (12 rings) with Catmull-like interpolation of the outline
    xs = np.array([p[0] for p in BROW_PTS]); ys = np.array([p[1] for p in BROW_PTS]); ts = np.array([p[2] for p in BROW_PTS])
    xx = np.linspace(xs[0] - 1.0, xs[-1], 12)
    yy = np.interp(xx, xs, ys); tt = np.interp(xx, xs, ts)
    taper = np.clip((xx - (xs[0] - 1.0)) / 5.0, 0.15, 1.0)          # thin tail (geometry, not colour)
    rings, hairw = [], []
    for x, yc, t, tp in zip(xx, yy, tt, taper):
        ring, hw = [], []
        for vv, h, w in PROFILE:
            p, n = hit(bvh, x, yc + vv * t * (0.45 + 0.55 * tp))
            if p is None:
                raise RuntimeError("brow ray missed at x=%.1f" % x)
            ring.append(p + n * h * (0.55 + 0.45 * tp))
            hw.append(w)
        rings.append(ring); hairw.append(hw)
    v, f = B.rings_mesh(np.array(rings))
    hw = np.array(hairw).ravel()
    if len(v) > len(hw):                               # cap centre vertices
        hw = np.concatenate([hw, np.ones(len(v) - len(hw))])
    v2 = v.copy(); v2[:, 0] *= -1
    f2 = [list(reversed(ff)) for ff in f]
    V_ = np.vstack([v, v2]) * K
    F_ = f + [[i + len(v) for i in ff] for ff in f2]
    HW = np.concatenate([hw, hw])
    if old:
        bpy.data.objects.remove(old)
    ob = B.make_obj("Exit6_Male_Brows", V_, F_, colls[0])
    for c in colls[1:]:
        c.objects.link(ob)
    W = B.wmat(len(V_)); W[:, B.BI["Head"]] = 1
    B.assign_groups(ob, W)
    if rig:
        ob.parent = rig
        m = ob.modifiers.new("Armature", "ARMATURE"); m.object = rig
    # colour: hair where hw = 1, skin at the feathered edges
    skin = B.srgb_lin(SKIN_SRGB); hair = B.srgb_lin(BROW_SRGB)
    col = skin[None] * (1 - HW[:, None]) + hair[None] * HW[:, None]
    B.set_colors(ob, col)
    ob.data.materials.append(brow_material())
    log("brows rebuilt: %d verts, max height %.2f px" % (len(V_), max(p[1] for p in PROFILE)))
    return ob


def brow_material():
    m = bpy.data.materials.get("M_Exit6_BrowStrands") or bpy.data.materials.new("M_Exit6_BrowStrands")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    p = nt.nodes["Principled BSDF"]
    col = nt.nodes.new("ShaderNodeVertexColor"); col.layer_name = "Col"
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (6.0, 6.0, 260.0)       # streaks run along the brow (X)
    mp.inputs["Rotation"].default_value = (0, math.radians(8), 0)
    nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 4.0
    nz.inputs["Detail"].default_value = 4.0; nz.inputs["Roughness"].default_value = 0.6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35; ramp.color_ramp.elements[0].color = (0.55, 0.5, 0.48, 1)
    ramp.color_ramp.elements[1].position = 0.65; ramp.color_ramp.elements[1].color = (1.5, 1.45, 1.4, 1)
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(col.outputs["Color"], mix.inputs[6])
    nt.links.new(ramp.outputs["Color"], mix.inputs[7])
    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.62
    p.inputs["Specular IOR Level"].default_value = 0.3
    bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.25
    nt.links.new(nz.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    return m


# ------------------------------------------------------------------ eyes
def tweak_eyes():
    eyes = bpy.data.objects["Exit6_Male_Eyes"]
    me = eyes.data
    ca = me.color_attributes["Col"]
    col = np.zeros(len(me.vertices) * 4, np.float32); ca.data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    P = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    ball = np.zeros(len(me.vertices), bool)
    for poly in me.polygons:
        if poly.material_index == 0:
            ball[list(poly.vertices)] = True
    old = B.srgb_lin((226, 216, 206)); new = B.srgb_lin(SCLERA_SRGB)
    n_scl = 0
    for side in (1, -1):
        idx = np.nonzero(ball & (np.sign(P[:, 0]) == side))[0]
        c = P[idx].mean(0)
        d = P[idx] - c; d /= np.linalg.norm(d, axis=1, keepdims=True)
        ang = np.degrees(np.arccos(np.clip(-d[:, 1], -1, 1)))
        scl = ang > 44.5                                          # outside the iris + limbus
        n_scl += int(scl.sum())
        cc = col[idx, :3]
        cc[scl] = cc[scl] / old * new                              # retint the sclera
        # soft shadow under the upper lid and darker corners (the lid occludes the top of the ball)
        up = np.clip((d[:, 2] - 0.05) / 0.5, 0, 1)
        corner = np.clip((np.abs(d[:, 0]) - 0.45) / 0.4, 0, 1)
        shade = 1 - 0.45 * up ** 1.5 - 0.3 * corner
        cc *= shade[:, None]
        # a slightly pink inner corner (caruncle side)
        inner = np.clip((-np.sign(P[idx, 0]) * d[:, 0] - 0.55) / 0.3, 0, 1) * scl
        cc = cc * (1 - 0.35 * inner[:, None]) + B.srgb_lin((150, 80, 72))[None] * 0.35 * inner[:, None]
        col[idx, :3] = cc
    ca.data.foreach_set("color", col.ravel())
    log("eyes: sclera sRGB %s on %d verts, lid shadow + corners" % (SCLERA_SRGB, n_scl))


def main():
    strip = strip_game_copies()
    if "--strip-only" in ARGV:
        bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)
        log("saved", bpy.data.filepath)
        return
    rig = bpy.data.objects["Exit6_Male_Rig"]
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    build_brows()
    tweak_eyes()
    rig.data.pose_position = "POSE"
    bpy.ops.wm.save_as_mainfile(filepath=V31_BLEND, compress=True)
    with open(os.path.join(OUT, "polish_report_v31.json"), "w") as fh:
        json.dump({"source": "Exit6_Male_V3.blend (tag exit6-male-v3-approved)", "log": LOG}, fh, indent=1)
    log("saved", V31_BLEND)


main()
