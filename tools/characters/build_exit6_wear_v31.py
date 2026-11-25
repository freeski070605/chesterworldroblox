"""Exit 6 V3.1 premium wear, fitted to the V3.1 body: layered clothing + rigid jewellery.

    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3_1_Game.blend \
        -P tools/characters/build_exit6_wear_v31.py [-- --only=puffer,cargo] [--no-bake]

Every garment is shaped from the V3.1 body surface (region -> offset -> shaping ->
smoothing -> pushed clear of the skin), so it fits this body without a fitting pass,
then decimated to a game mesh with a colour (+ normal) map baked from the
high-resolution version.

Layered items (Roblox WrapLayer): <Item> render mesh skinned to the R15 rig,
<Item>_InnerCage = the fitted V3.1 body cage (Roblox clothing-cage template topology
and UVs), <Item>_OuterCage = that cage inflated to enclose the garment.
  Exit6_Puffer    quilted puffer jacket (channels, stand collar, zip, cuffs, hem band)
  Exit6_Cargo     cargo joggers (waistband, thigh cargo pockets with flaps, back pockets,
                  knee seams, ribbed ankle cuffs)
  Exit6_Sneakers  low-top sneakers (cupsole, toe cap, lace panel, heel tab)
  Exit6_Briefs    the V3 boxer briefs, now with cages
Rigid accessories (static meshes; the Studio installer adds Accessory + attachments):
  Exit6_Chain     curb chain around the neck (NeckAttachment)
  Exit6_Watch     watch on the left wrist (LeftWristRigAttachment)

Colour maps of the puffer and cargo are near-white so SurfaceAppearance.Color can tint
them to any colourway (see docs/EXIT6_PREMIUM.md); sneakers, chain and watch carry
their own colours. Hair, clothing and jewellery are all separate assets.

Outputs: assets/characters/exit6_male/wear_v31/<Item>.glb, textures, wear_report_v31.json
"""
import bpy, bmesh, os, sys, json, math, time
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "characters", "exit6_male", "wear_v31")
os.makedirs(OUT, exist_ok=True)
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = None
BAKE = "--no-bake" not in ARGV
for a in ARGV:
    if a.startswith("--only="):
        ONLY = a.split("=", 1)[1].split(",")
T0 = time.time()
BONES = ["LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
         "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg",
         "RightLowerLeg", "RightFoot"]
REPORT = {"items": {}}


def log(*a):
    print("[wear31 %6.1fs]" % (time.time() - T0), *a, flush=True)


def srgb_lin(c):
    c = np.asarray(c, float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def activate(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def get_P(me):
    a = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("co", a); return a.reshape(-1, 3)


def set_P(me, P):
    me.vertices.foreach_set("co", np.asarray(P, np.float32).ravel()); me.update()


def get_N(me):
    me.update()
    a = np.zeros(len(me.vertices) * 3); me.vertices.foreach_get("normal", a); return a.reshape(-1, 3)


def edges_of(me):
    e = np.zeros(len(me.edges) * 2, np.int64); me.edges.foreach_get("vertices", e); return e.reshape(-1, 2)


def laplacian(P, E, n, fixed=None):
    S = np.zeros((n, 3)); deg = np.zeros(n)
    np.add.at(S, E[:, 0], P[E[:, 1]]); np.add.at(S, E[:, 1], P[E[:, 0]])
    np.add.at(deg, E[:, 0], 1); np.add.at(deg, E[:, 1], 1)
    L = S / np.maximum(deg, 1)[:, None] - P
    if fixed is not None:
        L[fixed] = 0
    return L


def taubin(P, E, iters, lam=0.5, mu=-0.53, w=None, fixed=None):
    n = len(P)
    w = np.ones(n) if w is None else w
    for _ in range(iters):
        P = P + lam * w[:, None] * laplacian(P, E, n, fixed)
        P = P + mu * w[:, None] * laplacian(P, E, n, fixed)
    return P


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ body
def whole_body():
    """the 15 capped game parts joined back into one skinned surface (caps removed)"""
    objs = []
    for b in BONES:
        src = bpy.data.objects[b + "_Geo"]
        ob = src.copy(); ob.data = src.data.copy(); ob.modifiers.clear(); ob.parent = None
        ob.matrix_world = src.matrix_world.copy()
        bpy.context.scene.collection.objects.link(ob); objs.append(ob)
    activate(objs[0])
    for o in objs[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    body = objs[0]; body.name = body.data.name = "Wear_Body"
    bm = bmesh.new(); bm.from_mesh(body.data)
    uv = bm.loops.layers.uv.active
    caps = [f for f in bm.faces if len({tuple(l[uv].uv) for l in f.loops}) == 1]
    bmesh.ops.delete(bm, geom=caps, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(body.data); bm.free()
    body.data.transform(body.matrix_world); body.matrix_world = Matrix()
    body.hide_render = True
    log("whole body: %d verts (%d cap faces removed)" % (len(body.data.vertices), len(caps)))
    return body


def part_of(body):
    """dominant R15 part per vertex"""
    names = [vg.name for vg in body.vertex_groups]
    W = np.zeros((len(body.data.vertices), len(BONES)))
    for v in body.data.vertices:
        for g in v.groups:
            if names[g.group] in BONES:
                W[v.index, BONES.index(names[g.group])] = g.weight
    return np.array(BONES)[W.argmax(1)], W


def body_bvh(body):
    P = get_P(body.data)
    return BVHTree.FromPolygons([Vector(p) for p in P], [tuple(p.vertices) for p in body.data.polygons])


def push_out(P, bvh, gap):
    out = 0
    for i in range(len(P)):
        loc, n, _, _ = bvh.find_nearest(Vector(P[i]))
        if loc is None:
            continue
        loc = np.array(loc); n = np.array(n)
        sd = (P[i] - loc) @ n
        if sd < gap:
            P[i] = P[i] + n * (gap - sd); out += 1
    return P, out


# ------------------------------------------------------------------ garment shell
def shell_from_body(body, vmask, name, subdiv=2, pre_smooth=0):
    ob = body.copy(); ob.data = body.data.copy(); ob.name = ob.data.name = name
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not all(vmask[v.index] for v in f.verts)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # drop tiny islands (stray faces at the region border)
    islands = []
    seen = set()
    for f in bm.faces:
        if f in seen:
            continue
        stack = [f]; isl = []
        while stack:
            g = stack.pop()
            if g in seen:
                continue
            seen.add(g); isl.append(g)
            for e in g.edges:
                stack.extend(e.link_faces)
        islands.append(isl)
    keep = max(len(i) for i in islands)
    small = [f for isl in islands if len(isl) < max(40, 0.02 * keep) for f in isl]
    bmesh.ops.delete(bm, geom=small, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data); bm.free()
    ob.hide_render = False
    if pre_smooth:          # drape: remove the anatomy at base resolution (one iteration reaches far here)
        P = taubin(get_P(ob.data), edges_of(ob.data), pre_smooth)
        set_P(ob.data, P)
    if subdiv:
        m = ob.modifiers.new("sub", "SUBSURF"); m.levels = subdiv; m.render_levels = subdiv
        m.subdivision_type = "SIMPLE"
        activate(ob); bpy.ops.object.modifier_apply(modifier="sub")
    return ob


def boundary_mask(me):
    bm = bmesh.new(); bm.from_mesh(me)
    m = np.zeros(len(me.vertices), bool)
    for e in bm.edges:
        if e.is_boundary:
            for v in e.verts:
                m[v.index] = True
    bm.free()
    return m


def set_colors(ob, col, name="Col"):
    me = ob.data
    if name in me.color_attributes:
        me.color_attributes.remove(me.color_attributes[name])
    ca = me.color_attributes.new(name, "FLOAT_COLOR", "POINT")
    rgba = np.ones((len(col), 4), np.float32); rgba[:, :3] = col
    ca.data.foreach_set("color", rgba.ravel())


def vc_material(name, rough=0.6, spec=0.4, sheen=0.0, metal=0.0, coat=0.0, bump=None):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; p = nt.nodes["Principled BSDF"]
    a = nt.nodes.new("ShaderNodeVertexColor"); a.layer_name = "Col"
    nt.links.new(a.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough; p.inputs["Specular IOR Level"].default_value = spec
    p.inputs["Metallic"].default_value = metal
    if sheen:
        p.inputs["Sheen Weight"].default_value = sheen
    if coat:
        p.inputs["Coat Weight"].default_value = coat
    if bump:
        nz = nt.nodes.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = bump[0]
        nz.inputs["Detail"].default_value = 8
        bp = nt.nodes.new("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump[1]
        nt.links.new(nz.outputs["Fac"], bp.inputs["Height"]); nt.links.new(bp.outputs["Normal"], p.inputs["Normal"])
    return m


# ------------------------------------------------------------------ garments
def build_puffer(body, part, bvh, rig):
    P0 = get_P(body.data); N0 = get_N(body.data)
    torso = np.isin(part, ["UpperTorso", "LowerTorso"])
    arms = np.isin(part, ["LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm"])
    neck = (part == "Head") & (P0[:, 2] < 1.80) & (P0[:, 1] > -0.33)
    HEM = -0.14
    m = (torso & (P0[:, 2] > HEM)) | (arms & (P0[:, 2] > -0.17)) | neck
    ob = shell_from_body(body, m, "Exit6_Puffer", subdiv=2, pre_smooth=45)
    me = ob.data; P = get_P(me); E = edges_of(me); n = len(P)
    # base garment surface: drape (smooth away anatomy), then offset
    P = taubin(P, E, 8)
    N = get_N_from(P, me)
    z = P[:, 2]
    is_arm = np.abs(P[:, 0]) > 0.52 + 0.1 * np.clip((1.2 - z) / 1.0, 0, 1)
    t = np.where(is_arm, 0.055, 0.07)
    t = np.where(z > 1.62, 0.06, t)                              # collar
    cuff = is_arm & (z < -0.17 + 0.1)
    hem = (~is_arm) & (z < HEM + 0.09)
    wc = is_arm * smoothstep(-0.05, -0.09, z)                     # soft bands: hard steps fold the shell
    wh = (~is_arm) * smoothstep(HEM + 0.11, HEM + 0.07, z)
    t = t * (1 - wc) + 0.03 * wc
    t = t * (1 - wh) + 0.04 * wh
    P = P + N * t[:, None]
    # quilted channels: horizontal on the body, around the sleeve
    pitch = np.where(is_arm, 0.21, 0.27)
    s = np.where(is_arm, (z - (-0.07)) / pitch, (z - (HEM + 0.09)) / pitch)
    puff = 0.042 * np.sin(np.pi * np.mod(s, 1.0)) ** 0.6
    puff *= (1 - wc) * (1 - wh)
    puff *= np.where(z > 1.5, np.clip((1.62 - z) / 0.12, 0, 1), 1)  # no channels into the collar
    front = N[:, 1] < -0.3
    wz = smoothstep(-0.15, -0.35, N[:, 1]) * (~is_arm) * smoothstep(0.04, 0.012, np.abs(P[:, 0]))
    puff *= 1 - wz
    N = get_N_from(P, me)
    P = P + N * puff[:, None]
    P = taubin(P, E, 3)
    P, nout = push_out(P, bvh, 0.03)
    P = taubin(P, E, 1)
    set_P(me, P)
    # colour (near-white, tintable): cavity in the channel seams, dark zip, darker inside collar/hem bands
    col = np.ones((n, 3)) * 0.92
    seam = 1 - np.sin(np.pi * np.mod(s, 1.0)) ** 0.6
    col *= (1 - 0.35 * seam * ~(cuff | hem))[:, None]
    col[cuff | hem] *= 0.8
    zipc = front & (np.abs(P[:, 0]) < 0.012) & ~is_arm & (P[:, 2] < 1.82)
    col[zipc] = srgb_lin((40, 40, 42))
    set_colors(ob, col)
    ob.data.materials.clear(); ob.data.materials.append(vc_material("M_Puffer_Hi", rough=0.42, spec=0.55, coat=0.15,
                                                                     bump=(400, 0.05)))
    log("puffer hi: %d verts, %d pushed out" % (n, nout))
    return ob


def get_N_from(P, me):
    set_P(me, P)
    return get_N(me)


def build_cargo(body, part, bvh, rig):
    P0 = get_P(body.data)
    legs = np.isin(part, ["LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"])
    lt = part == "LowerTorso"
    WAIST = 0.18; ANKLE = -2.56
    m = (lt & (P0[:, 2] < WAIST)) | (legs & (P0[:, 2] > ANKLE))
    ob = shell_from_body(body, m, "Exit6_Cargo", subdiv=2, pre_smooth=40)
    me = ob.data; P = get_P(me); E = edges_of(me); n = len(P)
    P = taubin(P, E, 8)
    N = get_N_from(P, me)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    t = 0.035 + 0.035 * smoothstep(-0.2, -0.7, z) - 0.02 * smoothstep(-2.25, -2.5, z)
    band = z > WAIST - 0.11
    wb = smoothstep(WAIST - 0.13, WAIST - 0.10, z)
    t = t * (1 - wb) + 0.028 * wb
    wi = smoothstep(0.19, 0.12, np.abs(x)) * smoothstep(-0.12, -0.25, z) * smoothstep(-1.5, -1.35, z)
    t = t * (1 - 0.45 * wi)
    cuff = z < ANKLE + 0.13
    wcf = smoothstep(ANKLE + 0.16, ANKLE + 0.12, z)
    t = t * (1 - wcf) + 0.024 * wcf
    P = P + N * t[:, None]
    # leg hang: pull the lower leg cross-section a little toward a cylinder around the leg axis
    side = np.sign(x)
    for sx in (1, -1):
        sel = (side == sx) & (z < -0.25)
        if not sel.any():
            continue
        zz = P[sel, 2]
        cx = np.interp(zz, [-2.6, -1.3, -0.25], [0.39 * sx, 0.34 * sx, 0.28 * sx][::1]) if sx > 0 else \
            np.interp(zz, [-2.6, -1.3, -0.25], [-0.39, -0.34, -0.28])
        cy = np.interp(zz, [-2.6, -1.3, -0.25], [0.09, 0.0, -0.01])
        d = P[sel, :2] - np.stack([cx, cy], 1)
        r = np.linalg.norm(d, axis=1)
        rm = np.median(r)
        w = 0.25 * smoothstep(-0.6, -1.2, zz) * (1 - smoothstep(-2.3, -2.5, zz))
        P[sel, :2] += d / np.maximum(r, 1e-6)[:, None] * ((rm - r) * w)[:, None] * (r < rm)[:, None]
    N = get_N_from(P, me)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    outer = N[:, 0] * np.sign(x)
    # cargo pockets on the outer thigh with a flap
    edge = (smoothstep(0.3, 0.55, outer) * smoothstep(-1.13, -1.07, z) * smoothstep(-0.71, -0.77, z)
            * smoothstep(0.55, 0.35, N[:, 1]) * smoothstep(-0.8, -0.55, N[:, 1]))
    pk = edge > 0.05
    disp = 0.028 * edge
    disp += 0.01 * edge * smoothstep(-0.81, -0.785, z)                     # flap
    # back pockets
    bp = (N[:, 1] > 0.55) & (z > -0.52) & (z < -0.22) & (np.abs(x) > 0.08) & (np.abs(x) < 0.4)
    disp += 0.008 * bp * smoothstep(0.08, 0.11, np.abs(x)) * smoothstep(0.4, 0.37, np.abs(x)) * \
        smoothstep(-0.52, -0.49, z)
    # knee seams + ankle stacking
    disp -= 0.006 * np.exp(-((z + 1.18) / 0.012) ** 2) * smoothstep(-0.1, -0.3, N[:, 1])
    disp += 0.007 * np.sin((z + 2.6) * 70) * smoothstep(-2.2, -2.35, z) * (1 - wcf)
    P = P + N * disp[:, None]
    P = taubin(P, E, 2)
    P, nout = push_out(P, bvh, 0.022)
    P = taubin(P, E, 1)
    set_P(me, P)
    col = np.ones((n, 3)) * 0.9
    col[band] *= 0.82
    col[cuff] *= 0.78
    seams = (np.abs(np.abs(z + 0.785) - 0.0) < 0.006) & pk
    col[seams] *= 0.6
    col[pk] *= (1 - 0.18 * (1 - edge[pk]))[:, None]
    sideseam = np.abs(outer - 0.97) < 0.02
    col[sideseam] *= 0.8
    set_colors(ob, col)
    ob.data.materials.clear(); ob.data.materials.append(vc_material("M_Cargo_Hi", rough=0.85, spec=0.25, sheen=0.3,
                                                                    bump=(900, 0.06)))
    log("cargo hi: %d verts, %d pushed out" % (n, nout))
    return ob


def build_sneakers(body, part, bvh, rig):
    P0 = get_P(body.data)
    feet = np.isin(part, ["LeftFoot", "RightFoot"])
    ll = np.isin(part, ["LeftLowerLeg", "RightLowerLeg"])
    COLLAR = -2.60
    m = feet | (ll & (P0[:, 2] < COLLAR))
    ob = shell_from_body(body, m, "Exit6_Sneakers", subdiv=2, pre_smooth=30)
    me = ob.data; P = get_P(me); E = edges_of(me); n = len(P)
    SOLE = -2.97
    P = taubin(P, E, 20)                                         # toes -> one shoe volume
    N = get_N_from(P, me)
    z = P[:, 2]
    t = np.full(n, 0.045)
    P = P + N * t[:, None]
    # cupsole: flat bottom, slight lip, toe spring
    low = z < SOLE + 0.09
    lip = smoothstep(SOLE + 0.09, SOLE + 0.03, z)
    hor = N.copy(); hor[:, 2] = 0
    hor /= np.maximum(np.linalg.norm(hor, axis=1, keepdims=True), 1e-6)
    P += hor * (0.018 * lip)[:, None]
    P[:, 2] = np.maximum(P[:, 2], SOLE - 0.025)
    for sx in (1, -1):
        sel = np.sign(P[:, 0]) == sx
        ymin = P[sel, 1].min()
        toe = smoothstep(ymin + 0.16, ymin, P[sel, 1])
        P[sel, 2] += 0.03 * toe * smoothstep(SOLE + 0.06, SOLE - 0.03, P[sel, 2])
    P, nout = push_out(P, bvh, 0.03)
    set_P(me, P)
    N = get_N_from(P, me)
    z = P[:, 2]
    # colours: white cupsole + stitched midline, black upper, white side panel, laces
    sole = z < SOLE + 0.055
    col = np.tile(srgb_lin((26, 26, 28)), (n, 1))
    col[sole] = srgb_lin((236, 234, 228))
    col[np.abs(z - (SOLE + 0.055)) < 0.004] = srgb_lin((150, 148, 140))
    for sx in (1, -1):
        sel = np.sign(P[:, 0]) == sx
        yc = P[sel, 1]
        ymin, ymax = yc.min(), yc.max()
        u = (yc - ymin) / (ymax - ymin)
        h = P[sel, 2] - SOLE
        fox = (h > 0.058) & (h < 0.072)                              # plain foxing band above the cupsole
        cc = col[sel]; cc[fox] = srgb_lin((120, 120, 124)); col[sel] = cc
        xm = np.median(P[sel, 0])
        tongue = (N[sel, 2] > 0.55) & (u > 0.18) & (u < 0.55) & (np.abs(P[sel, 0] - xm) < 0.05)
        lace = tongue & (np.abs(P[sel, 0] - xm) < 0.035) & (np.sin(u * 90) > 0.55)
        cc = col[sel]; cc[tongue] = srgb_lin((44, 44, 48)); cc[lace] = srgb_lin((210, 208, 202)); col[sel] = cc
        heel = (u > 0.93) & (h > 0.08)
        cc = col[sel]; cc[heel] = srgb_lin((236, 234, 228)); col[sel] = cc
    set_colors(ob, col)
    ob.data.materials.clear(); ob.data.materials.append(vc_material("M_Sneaker_Hi", rough=0.55, spec=0.4,
                                                                     bump=(700, 0.04)))
    log("sneakers hi: %d verts, %d pushed out" % (n, nout))
    return ob


# ------------------------------------------------------------------ rigid jewellery
def torus_link(c, tangent, normal, R, r, segs=8, sides=4, flat=0.6):
    """one chain link: torus around `normal`, long axis along `tangent`"""
    t = tangent / np.linalg.norm(tangent); nn = normal - t * (normal @ t); nn /= np.linalg.norm(nn)
    b = np.cross(t, nn)
    V, F = [], []
    for i in range(segs):
        a = 2 * np.pi * i / segs
        ring_c = c + (t * np.cos(a) * R * 1.35 + b * np.sin(a) * R)
        radial = (t * np.cos(a) * 1.35 + b * np.sin(a)); radial /= np.linalg.norm(radial)
        for j in range(sides):
            q = 2 * np.pi * j / sides + np.pi / 4
            V.append(ring_c + radial * np.cos(q) * r + nn * np.sin(q) * r * flat)
    for i in range(segs):
        for j in range(sides):
            a0 = i * sides + j; a1 = i * sides + (j + 1) % sides
            b0 = ((i + 1) % segs) * sides + j; b1 = ((i + 1) % segs) * sides + (j + 1) % sides
            F.append((a0, b0, b1, a1))
    return np.array(V), F


def make_mesh(name, V, F, coll=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(f) for f in F]); me.update()
    ob = bpy.data.objects.new(name, me)
    (coll or bpy.context.scene.collection).objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def build_chain(body, bvh):
    """curb chain lying on the trapezius at the back and dipping onto the chest in front"""
    neck_c = np.array([0.0, 0.08, 1.66])
    path = []
    for k in range(240):
        a = 2 * np.pi * k / 240                       # a = 0 at the front (-Y)
        dx, dy = np.sin(a), -np.cos(a)
        front = max(0.0, np.cos(a)) ** 2.2
        zt = neck_c[2] + 0.01 - 0.30 * front
        o = np.array([dx * 1.2, neck_c[1] + dy * 1.2, zt + 0.25])
        tgt = np.array([0.0, neck_c[1], zt - 0.05 * front])
        d = tgt - o; d /= np.linalg.norm(d)
        loc, nrm, _, _ = bvh.ray_cast(Vector(o), Vector(d), 3.0)
        if loc is None:
            continue
        path.append(np.array(loc) + np.array(nrm) * 0.022)
    path = np.array(path)
    for _ in range(30):                                # smooth the drape
        path = 0.5 * path + 0.25 * (np.roll(path, 1, 0) + np.roll(path, -1, 0))
    seg = np.linalg.norm(np.diff(np.vstack([path, path[:1]]), axis=0), axis=1)
    L = seg.sum(); cum = np.concatenate([[0], np.cumsum(seg)])
    pitch = 0.034; nlink = int(L / pitch)
    V, F = [], []
    for i in range(nlink):
        s_ = i * pitch
        c = np.array([np.interp(s_, cum, np.append(path[:, k], path[0, k])) for k in range(3)])
        c2 = np.array([np.interp(s_ + 0.01, cum, np.append(path[:, k], path[0, k])) for k in range(3)])
        tan = c2 - c
        out = c - np.array([0, neck_c[1], c[2]]); out[2] = 0.0
        out = out / max(np.linalg.norm(out), 1e-6) + np.array([0, 0, 0.4])
        side = np.cross(tan, out)
        nrm = out if i % 2 == 0 else side             # alternate link planes (curb twist)
        v, f = torus_link(c, tan, nrm, 0.016, 0.0065)
        F += [tuple(x + len(V) for x in ff) for ff in f]; V += list(v)
    ob = make_mesh("Exit6_Chain", V, F)
    col = np.tile(srgb_lin((214, 168, 72)), (len(V), 1))
    set_colors(ob, col)
    ob.data.materials.append(vc_material("M_Chain", rough=0.22, spec=0.6, metal=1.0))
    log("chain: %d links, %d tris" % (nlink, 2 * len(F)))
    return ob


def build_watch(body, part, bvh, rig):
    """case + bezel + dial + strap on the back of the left wrist"""
    b = rig.data.bones
    elbow = np.array(b["LeftLowerArm"].head_local); wrist = np.array(b["LeftLowerArm"].tail_local)
    ax = wrist - elbow; ax /= np.linalg.norm(ax)
    c0 = wrist - ax * 0.085
    P0 = get_P(body.data)
    sel = np.isin(part, ["LeftLowerArm", "LeftHand"]) & (np.abs((P0 - c0) @ ax) < 0.02)
    ring = P0[sel]
    rad = np.linalg.norm((ring - c0) - np.outer((ring - c0) @ ax, ax), axis=1)
    R = np.median(rad) + 0.014
    up = np.array([1.0, 0, 0]) - ax * ax[0]; up /= np.linalg.norm(up)   # back of the left wrist faces +X
    side = np.cross(ax, up)
    V, F = [], []
    # strap: elliptical band following the wrist section
    segs, w = 40, 0.075
    rx = np.max(np.abs((ring - c0) @ up)) + 0.014; ry = np.max(np.abs((ring - c0) @ side)) + 0.014
    for i in range(segs):
        a = 2 * np.pi * i / segs
        d = up * np.cos(a) * rx + side * np.sin(a) * ry
        dn = d / np.linalg.norm(d)
        for (h, o) in ((-w / 2, 0), (w / 2, 0), (w / 2, 0.016), (-w / 2, 0.016)):
            V.append(c0 + d + dn * o + ax * h)
    for i in range(segs):
        for j in range(4):
            a0 = i * 4 + j; a1 = i * 4 + (j + 1) % 4; b0 = ((i + 1) % segs) * 4 + j; b1 = ((i + 1) % segs) * 4 + (j + 1) % 4
            F.append((a0, a1, b1, b0))
    nstrap = len(V)
    # case: short cylinder on the back of the wrist
    cc = c0 + up * (rx + 0.012)
    cr, ch, cs = 0.072, 0.034, 32

    def cyl(center, r, h, base_z, name_off):
        start = len(V)
        for k in range(cs):
            a = 2 * np.pi * k / cs
            d = ax * np.cos(a) * r + side * np.sin(a) * r
            V.append(center + d + up * base_z); V.append(center + d + up * (base_z + h))
        for k in range(cs):
            a0 = start + 2 * k; a1 = start + 2 * ((k + 1) % cs)
            F.append((a0, a1, a1 + 1, a0 + 1))
        top_c = len(V); V.append(center + up * (base_z + h))
        for k in range(cs):
            F.append((start + 2 * k + 1, start + 2 * ((k + 1) % cs) + 1, top_c))
        return start
    cyl(cc, cr, ch, 0.0, "case")
    bez = cyl(cc, cr * 1.04, 0.012, ch, "bezel")
    dial0 = len(V)
    cyl(cc, cr * 0.82, 0.004, ch + 0.004, "dial")
    crown = cyl(cc + side * (cr + 0.008), 0.012, 0.022, ch * 0.3, "crown")
    ob = make_mesh("Exit6_Watch", V, F)
    col = np.tile(srgb_lin((196, 198, 204)), (len(V), 1))
    col[:nstrap] = srgb_lin((196, 198, 204))
    col[dial0:dial0 + 2 * cs + 1] = srgb_lin((18, 20, 24))
    set_colors(ob, col)
    ob.data.materials.append(vc_material("M_Watch", rough=0.25, spec=0.6, metal=0.9))
    log("watch: %d tris" % sum(len(f) - 2 for f in F))
    return ob


# ------------------------------------------------------------------ game mesh, bake, skin, cages
def game_mesh(hi, target_tris, name, solid=0.0):
    hi.name = hi.data.name = name + "_Hi"          # free the name first: cages pair with <name>_InnerCage
    ob = hi.copy(); ob.data = hi.data.copy(); ob.name = ob.data.name = name
    bpy.context.scene.collection.objects.link(ob)
    assert ob.name == name, ob.name
    ob.data.calc_loop_triangles()
    n = len(ob.data.loop_triangles) * (2 if solid else 1)
    if n > target_tris:
        d = ob.modifiers.new("dec", "DECIMATE"); d.ratio = target_tris / n; d.use_collapse_triangulate = True
        activate(ob); bpy.ops.object.modifier_apply(modifier="dec")
    if solid:
        s = ob.modifiers.new("solid", "SOLIDIFY"); s.thickness = solid; s.offset = -1; s.use_rim = True
        activate(ob); bpy.ops.object.modifier_apply(modifier="solid")
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def fill_black(img, thresh=10 / 255.0, iters=24):
    """bake rays that miss the hi-res mesh leave pure-black texels: grow the surrounding colour into them"""
    w, h = img.size
    A = np.array(img.pixels[:], np.float32).reshape(h, w, 4)
    miss = (A[:, :, :3].max(2) < thresh)
    n0 = int(miss.sum())
    for _ in range(iters):
        if not miss.any():
            break
        acc = np.zeros((h, w, 3), np.float32); cnt = np.zeros((h, w), np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.roll(np.roll(A[:, :, :3], dy, 0), dx, 1); ok = ~np.roll(np.roll(miss, dy, 0), dx, 1)
            acc += sh * ok[:, :, None]; cnt += ok
        grow = miss & (cnt > 0)
        A[grow, :3] = acc[grow] / cnt[grow][:, None]
        miss &= ~grow
    img.pixels[:] = A.ravel()
    log("filled %d bake-miss texels in %s" % (n0, img.name))


def bake_maps(low, hi, size, name, normal=True, fill_misses=False):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.samples = 8
    img = bpy.data.images.new(name + "_Color", size, size)
    mat = bpy.data.materials.new("M_" + name); mat.use_nodes = True
    nt = mat.node_tree; p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    low.data.materials.clear(); low.data.materials.append(mat)
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.05; sc.render.bake.max_ray_distance = 0.12; sc.render.bake.margin = 8
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    hi.hide_render = False; hi.hide_set(False); hi.select_set(True); low.select_set(True)
    bpy.context.view_layer.objects.active = low
    nt.nodes.active = tex
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    if fill_misses:
        fill_black(img)
    out = {}
    path = os.path.join(OUT, name + "_Color.png"); img.filepath_raw = path; img.file_format = "PNG"; img.save()
    out["color"] = os.path.relpath(path, REPO)
    if normal:
        nimg = bpy.data.images.new(name + "_Normal", size, size); nimg.colorspace_settings.name = "Non-Color"
        nt2 = nt.nodes.new("ShaderNodeTexImage"); nt2.image = nimg; nt.nodes.active = nt2
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
        path = os.path.join(OUT, name + "_Normal.png"); nimg.filepath_raw = path; nimg.file_format = "PNG"; nimg.save()
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nt2.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
        out["normal"] = os.path.relpath(path, REPO)
    return out


def skin_to(ob, body, rig):
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for b in BONES:
        ob.vertex_groups.new(name=b)
    dt = ob.modifiers.new("w", "DATA_TRANSFER"); dt.object = body
    dt.use_vert_data = True; dt.data_types_verts = {"VGROUP_WEIGHTS"}; dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
    activate(ob); bpy.ops.object.modifier_apply(modifier="w")
    # 4 influences
    names = [vg.name for vg in ob.vertex_groups]
    W = np.zeros((len(ob.data.vertices), len(names)))
    for v in ob.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    order = np.argsort(-W, 1); mask = np.zeros_like(W, bool); np.put_along_axis(mask, order[:, :4], True, 1)
    W = np.where(mask & (W > 0.01), W, 0); W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for j, nme in enumerate(names):
        vg = ob.vertex_groups.new(name=nme)
        q = np.round(W[:, j] * 255).astype(int)
        for val in np.unique(q):
            if val > 0:
                vg.add(np.nonzero(q == val)[0].tolist(), val / 255.0, "REPLACE")
    ob.parent = rig
    m = ob.modifiers.new("Armature", "ARMATURE"); m.object = rig


def cage_normals(P, me):
    tri = []
    for p in me.polygons:
        v = list(p.vertices)
        for k in range(1, len(v) - 1):
            tri.append((v[0], v[k], v[k + 1]))
    tri = np.array(tri)
    fn = np.cross(P[tri[:, 1]] - P[tri[:, 0]], P[tri[:, 2]] - P[tri[:, 0]])
    N = np.zeros_like(P)
    for k in range(3):
        np.add.at(N, tri[:, k], fn)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def make_item_cages(item, garment, body_cage, inner_in=0.004, gap=0.02):
    """inner = the fitted body cage (slightly in), outer = inner inflated to enclose the garment"""
    C = get_P(body_cage.data) @ np.array(body_cage.matrix_world)[:3, :3].T + np.array(body_cage.matrix_world)[:3, 3]
    Nc = cage_normals(C, body_cage.data)
    inner = C - Nc * inner_in
    Pg = get_P(garment.data)
    gb = BVHTree.FromPolygons([Vector(p) for p in Pg], [tuple(p.vertices) for p in garment.data.polygons])
    outer = inner + Nc * 0.004
    hit = 0
    for i in range(len(C)):
        best = 0.0
        for d in (Nc[i], -Nc[i]):
            loc, _, _, dist = gb.ray_cast(Vector(inner[i] - d * 0.05), Vector(d), 0.6)
            if loc is not None:
                along = (np.array(loc) - inner[i]) @ Nc[i]
                best = max(best, along)
        loc, _, _, dist = gb.find_nearest(Vector(inner[i]), 0.25)
        if loc is not None:
            best = max(best, (np.array(loc) - inner[i]) @ Nc[i])
        if best > 0:
            outer[i] = inner[i] + Nc[i] * (best + gap); hit += 1
    E = np.array([tuple(e.vertices) for e in body_cage.data.edges])
    D = outer - inner
    # smooth the inflation so the outer cage has no spikes, never shrinking below what encloses the garment
    for _ in range(4):
        Ds = D + 0.5 * laplacian(D, E, len(D))
        D = np.where((np.linalg.norm(Ds, axis=1) >= np.linalg.norm(D, axis=1))[:, None], Ds, D)
    outer = inner + D
    objs = []
    for nm, P in (("_InnerCage", inner), ("_OuterCage", outer)):
        me = body_cage.data.copy(); me.name = item + nm
        set_P(me, P)
        ob = bpy.data.objects.new(item + nm, me); bpy.context.scene.collection.objects.link(ob)
        ob.hide_render = True
        objs.append(ob)
    log("%s cages: %d of %d cage verts inflated" % (item, hit, len(C)))
    return objs


def export_glb(objs, path):
    for o in bpy.context.view_layer.objects:
        o.hide_set(False)
        o.select_set(o in set(objs))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_yup=True, export_apply=False, export_morph=False)
    log("exported", os.path.relpath(path, REPO))


def tris(ob):
    ob.data.calc_loop_triangles(); return len(ob.data.loop_triangles)


def main():
    sc = bpy.context.scene
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"; prefs.get_devices()
        for d in prefs.devices:
            d.use = d.type != "CPU"
        sc.cycles.device = "GPU"
    except Exception:
        pass
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    rig.data.pose_position = "REST"
    body_cage = bpy.data.objects["Exit6V31_BodyCage"]
    body = whole_body()
    part, _ = part_of(body)
    bvh = body_bvh(body)
    layered = {"puffer": ("Exit6_Puffer", build_puffer, 9000, 0.012, True),
               "cargo": ("Exit6_Cargo", build_cargo, 7000, 0.01, True),
               "sneakers": ("Exit6_Sneakers", build_sneakers, 4000, 0.0, True)}
    for key, (item, fn, budget, solid, normal) in layered.items():
        if ONLY and key not in ONLY:
            continue
        hi = fn(body, part, bvh, rig)
        low = game_mesh(hi, budget, item, solid=solid)
        rep = {"hi_verts": len(hi.data.vertices)}
        if BAKE:
            rep["textures"] = bake_maps(low, hi, 1024, item, normal=normal, fill_misses=key in ("puffer", "cargo"))
        skin_to(low, body, rig)
        inner, outer = make_item_cages(item, low, body_cage)
        rep["tris"] = tris(low)
        export_glb([rig, low, inner, outer], os.path.join(OUT, item + ".glb"))
        REPORT["items"][item] = rep
        hi.hide_render = True
    if not ONLY or "briefs" in ONLY:
        br = bpy.data.objects["Briefs_Geo"]
        br.name = br.data.name = "Exit6_Briefs"
        inner, outer = make_item_cages("Exit6_Briefs", br, body_cage, gap=0.035)   # coarse cage: generous gap
        export_glb([rig, br, inner, outer], os.path.join(OUT, "Exit6_Briefs.glb"))
        REPORT["items"]["Exit6_Briefs"] = {"tris": tris(br), "textures": "textures_v3_1/Exit6V31_Briefs_Color.png"}
    if not ONLY or "jewelry" in ONLY:
        chain = build_chain(body, bvh)
        watch = build_watch(body, part, bvh, rig)
        for ob, size in ((chain, 256), (watch, 256)):
            hi = ob.copy(); hi.data = ob.data.copy(); sc.collection.objects.link(hi); hi.name = ob.name + "_Hi"
            E_ = ob.modifiers.new("bev", "BEVEL")
            activate(ob)
            bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
            bpy.ops.object.mode_set(mode="OBJECT")
            ob.modifiers.remove(E_)
            if BAKE:
                REPORT["items"][ob.name] = {"textures": bake_maps(ob, hi, size, ob.name, normal=False)}
            REPORT["items"].setdefault(ob.name, {})["tris"] = tris(ob)
            hi.hide_render = True
        export_glb([chain, watch], os.path.join(OUT, "Exit6_Jewelry.glb"))
        att = {}
        for b in ("LeftLowerArm", "LeftHand"):
            pass
        bones = {b.name: (list(b.head_local), list(b.tail_local)) for b in rig.data.bones}
        REPORT["jewelry_frame"] = {"Exit6_Chain": "NeckAttachment", "Exit6_Watch": "LeftWristRigAttachment",
                                   "bones": bones}
    with open(os.path.join(OUT, "wear_report_v31.json"), "w") as fh:
        json.dump(REPORT, fh, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Exit6_Wear_V31.blend"), compress=True)
    log("done")


if __name__ == "__main__":
    main()
