"""Game-ready Exit 6 male V3 from Exit6_Male_V3.blend -> Exit6_Male_V3.glb.

    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend \
        -P tools/characters/export_exit6_male_v2.py

In-experience target (not a Marketplace body; see docs/EXIT6_CHARACTER_MALE_V3.md):
  * Body keeps the MPFB quad topology unchanged (no decimation), split into
    the 15 R15 <Part>_Geo meshes; every part stays well under the 20k-tri
    MeshPart limit. Normals are copied from the unsplit body onto each part so
    the part boundaries do not show shading seams.
  * Body colour baked onto MPFB's own UV layout (2048).
  * Hair_Geo = purpose-built low-poly twists + scalp cap, with colour and a
    tangent normal map baked from the two-strand render twists.
  * FaceDetails_Geo = eyeballs (no cornea), brows, goatee.
  * 19 Roblox accessory attachment meshes (<Name>_Att) parented to their part.
"""
import bpy, bmesh, os, sys, json, math, time
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exit6_male_spec as S

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "characters", "exit6_male")
TEX = os.path.join(OUT, "textures_v3")
os.makedirs(TEX, exist_ok=True)
K = S.HEIGHT_STUDS / (S.SOLE - S.SKULL_TOP)
T0 = time.time()
BONES = ["LowerTorso", "UpperTorso", "Head",
         "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
         "RightUpperLeg", "RightLowerLeg", "RightFoot"]


def log(*a):
    print("[export2 %6.1fs]" % (time.time() - T0), *a, flush=True)


def activate(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def copy_rest(src, coll, name, keep_mods=("SOLIDIFY",), decimate=None):
    me = src.data.copy()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    for vg in src.vertex_groups:
        ob.vertex_groups.new(name=vg.name)
    for m in src.modifiers:
        if m.type in keep_mods:
            s = ob.modifiers.new(m.name, m.type); s.thickness = m.thickness; s.offset = m.offset
    if decimate:
        me.calc_loop_triangles()
        n = len(me.loop_triangles) * (2 if any(m.type == "SOLIDIFY" for m in ob.modifiers) else 1)
        if n > decimate:
            d = ob.modifiers.new("dec", "DECIMATE"); d.ratio = decimate / n; d.use_collapse_triangulate = True
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    ob.data.shade_smooth()
    return ob


def limit_weights(ob, keep=4):
    # only the R15 deform groups survive (MPFB region groups like "body" would win every face)
    for vg in list(ob.vertex_groups):
        if vg.name not in BONES:
            ob.vertex_groups.remove(vg)
    names = [vg.name for vg in ob.vertex_groups]
    me = ob.data
    W = np.zeros((len(me.vertices), len(names)))
    for v in me.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    order = np.argsort(-W, axis=1)
    mask = np.zeros_like(W, bool)
    np.put_along_axis(mask, order[:, :keep], True, axis=1)
    W = np.where(mask & (W > 0.01), W, 0)
    W /= np.maximum(W.sum(1, keepdims=True), 1e-9)
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for j, n in enumerate(names):
        vg = ob.vertex_groups.new(name=n)
        q = np.round(W[:, j] * 255).astype(int)
        for val in np.unique(q):
            if val > 0:
                vg.add(np.nonzero(q == val)[0].tolist(), val / 255.0, "REPLACE")
    return W, names


def smart_uv(ob, margin=0.003):
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake(game, sources, size, name, normal=False, extrusion=0.03, ray=0.08):
    img = bpy.data.images.new(name + "_Color", size, size, alpha=False)
    mat = bpy.data.materials.new("M_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    p = nt.nodes["Principled BSDF"]
    p.inputs["Roughness"].default_value = 0.6
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    game.data.materials.clear(); game.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.samples = 8
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = extrusion
    sc.render.bake.max_ray_distance = ray
    sc.render.bake.margin = 8
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for s in sources:
        s.hide_set(False); s.hide_render = False; s.select_set(True)
    game.select_set(True)
    bpy.context.view_layer.objects.active = game
    nt.nodes.active = tex
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    path = os.path.join(TEX, name + "_Color.png")
    img.filepath_raw = path; img.file_format = "PNG"; img.save()
    out = {"color": os.path.relpath(path, REPO)}
    if normal:
        nimg = bpy.data.images.new(name + "_Normal", size, size, alpha=False)
        nimg.colorspace_settings.name = "Non-Color"
        ntex = nt.nodes.new("ShaderNodeTexImage"); ntex.image = nimg
        nt.nodes.active = ntex
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
        npath = os.path.join(TEX, name + "_Normal.png")
        nimg.filepath_raw = npath; nimg.file_format = "PNG"; nimg.save()
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(ntex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
        out["normal"] = os.path.relpath(npath, REPO)
    return out


def split_r15(body, W, names, coll):
    me = body.data
    face_part = []
    bm = bmesh.new(); bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()
    for f in bm.faces:
        tot = {}
        for v in f.verts:
            for gi, w in v[deform].items():
                tot[names[gi]] = tot.get(names[gi], 0) + w
        face_part.append(max(tot, key=tot.get) if tot else "UpperTorso")
    bm.free()
    out = {}
    for part in BONES:
        ob = body.copy(); ob.data = me.copy(); ob.name = part + "_Geo"; ob.data.name = part + "_Geo"
        coll.objects.link(ob)
        bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.faces[i] for i, p in enumerate(face_part) if p != part], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(ob.data); bm.free()
        # seamless shading: copy the unsplit body's normals onto the part
        dt = ob.modifiers.new("normals", "DATA_TRANSFER")
        dt.object = body; dt.use_loop_data = True; dt.data_types_loops = {"CUSTOM_NORMAL"}
        dt.loop_mapping = "POLYINTERP_NEAREST"
        activate(ob)
        bpy.ops.object.modifier_apply(modifier=dt.name)
        out[part] = ob
    return out


def build_game_rig(coll, offset, src_rig):
    arm = bpy.data.armatures.new("Exit6_Male_V3_GameRig")
    rig = bpy.data.objects.new("Exit6_Male_V3_GameRig", arm)
    coll.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    off = Vector(offset)
    root = eb.new("Root"); root.head = (0, 0, 0); root.tail = (0, 0, 0.3); root.use_deform = False
    hrn = eb.new("HumanoidRootNode"); hrn.head = (0, 0, 0); hrn.tail = (0, 0, 0.35)
    hrn.parent = root; hrn.use_deform = False
    for b in src_rig.data.bones:
        if b.name == "HumanoidRootNode":
            continue
        e = eb.new(b.name)
        e.head = b.head_local + off; e.tail = b.tail_local + off
        e.align_roll(Vector((0, -1, 0)))
    for b in src_rig.data.bones:
        if b.name == "HumanoidRootNode":
            continue
        par = b.parent.name if b.parent else None
        eb[b.name].parent = eb[par] if par and par in eb else hrn
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def att_positions(parts, rig):
    """Roblox accessory attachments (create.roblox.com character body spec), studs, game space."""
    def V(ob):
        return np.array([ob.matrix_world @ v.co for v in ob.data.vertices])
    H = V(parts["Head"]); UT = V(parts["UpperTorso"]); LT = V(parts["LowerTorso"])
    bone = {b.name: (np.array(b.head_local), np.array(b.tail_local)) for b in rig.data.bones}
    top = H[:, 2].max(); hz = H[:, 2]
    eye_z = top - (S.LM_EYE_FROM_TOP if hasattr(S, "LM_EYE_FROM_TOP") else 60 * K)
    face = H[(np.abs(H[:, 0]) < 0.05) & (np.abs(hz - eye_z) < 0.05)]
    front_y = face[:, 1].min() if len(face) else H[:, 1].min()
    hc = H.mean(0)
    neck = bone["Head"][0]
    chest_z = UT[:, 2].max() - 0.55
    ch = UT[np.abs(UT[:, 2] - chest_z) < 0.04]
    waist_z = LT[:, 2].max() - 0.1
    wa = LT[np.abs(LT[:, 2] - waist_z) < 0.04]
    P = {
        ("Head", "FaceCenter"): (0, hc[1], eye_z),
        ("Head", "FaceFront"): (0, front_y + 0.02, eye_z),
        ("Head", "Hat"): (0, hc[1], top),
        ("Head", "Hair"): (0, hc[1], top),
        ("UpperTorso", "Neck"): tuple(neck),
        ("UpperTorso", "BodyFront"): (0, ch[:, 1].min(), chest_z),
        ("UpperTorso", "BodyBack"): (0, ch[:, 1].max(), chest_z),
        ("LowerTorso", "Root"): (0, 0, 0),
        ("LowerTorso", "WaistCenter"): (0, wa[:, 1].mean(), waist_z),
        ("LowerTorso", "WaistFront"): (0, wa[:, 1].min(), waist_z),
        ("LowerTorso", "WaistBack"): (0, wa[:, 1].max(), waist_z),
    }
    for side, sg in (("Left", 1), ("Right", -1)):
        sh = bone[side + "UpperArm"][0]
        P[("UpperTorso", side + "Collar")] = ((neck[0] + sh[0]) / 2, (neck[1] + sh[1]) / 2, UT[np.abs(UT[:, 0] - (neck[0] + sh[0]) / 2) < 0.05][:, 2].max())
        ua = V(parts[side + "UpperArm"])
        P[(side + "UpperArm", side + "Shoulder")] = (sh[0], sh[1], ua[:, 2].max())
        hd = V(parts[side + "Hand"])
        P[(side + "Hand", side + "Grip")] = tuple(hd.mean(0))
        ft = V(parts[side + "Foot"])
        P[(side + "Foot", side + "Foot")] = (ft[:, 0].mean(), ft[:, 1].mean(), ft[:, 2].min())
    return P


def make_attachments(parts, rig, coll):
    out = {}
    for (part, name), pos in att_positions(parts, rig).items():
        me = bpy.data.meshes.new(name + "_Att")
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=0.04); bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new(name + "_Att", me)
        coll.objects.link(ob)
        ob.location = Vector(pos)
        if name.endswith("Grip"):
            ob.rotation_euler = (math.radians(90), 0, 0)
        ob.parent = parts[part]
        ob.matrix_parent_inverse = parts[part].matrix_world.inverted()
        out[name + "_Att"] = {"part": part + "_Geo", "pos": [round(float(x), 4) for x in pos]}
    return out


def main():
    sc = bpy.context.scene
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
    sc.frame_set(1)
    src_rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.name.startswith("Exit6_Male_Rig"))
    src_rig.data.pose_position = "REST"
    old = bpy.data.collections.get("Exit6_Male_V3_Game")
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new("Exit6_Male_V3_Game")
    sc.collection.children.link(coll)
    O = bpy.data.objects
    report = {"objects": {}, "textures": {}}
    # body: unchanged topology
    body = copy_rest(O["Exit6_Male_Body"], coll, "Game_Body", keep_mods=())
    bsrc = O["Exit6_Male_Body"]
    report["textures"]["Body"] = bake(body, [bsrc], 2048, "Exit6V3_Body", normal=True, extrusion=0.02, ray=0.05)
    log("body baked")
    # hair: game twists + scalp, baked from the two-strand render twists
    hair = copy_rest(O["Exit6_Male_Hair_Game"], coll, "Game_Hair")
    scalp = copy_rest(O["Exit6_Male_Hair_Scalp"], coll, "Game_Scalp", decimate=1600)
    activate(hair); scalp.select_set(True); bpy.ops.object.join()
    smart_uv(hair)
    report["textures"]["Hair"] = bake(hair, [O["Exit6_Male_Hair_Twists"], O["Exit6_Male_Hair_Scalp"]], 1024,
                                      "Exit6V3_Hair", normal=True, extrusion=0.03, ray=0.06)
    hair.name = hair.data.name = "Hair_Geo"
    log("hair baked")
    # face details
    eyes = copy_rest(O["Exit6_Male_Eyes"], coll, "Game_Eyes", keep_mods=())
    bm = bmesh.new(); bm.from_mesh(eyes.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == 1], context="FACES")   # cornea shells
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(eyes.data); bm.free()
    brows = copy_rest(O["Exit6_Male_Brows"], coll, "Game_Brows")
    goatee = copy_rest(O["Exit6_Male_Goatee"], coll, "Game_Goatee", decimate=1200)
    activate(eyes); brows.select_set(True); goatee.select_set(True); bpy.ops.object.join()
    face = eyes
    smart_uv(face)
    report["textures"]["FaceDetails"] = bake(face, [O["Exit6_Male_Eyes"], O["Exit6_Male_Brows"], O["Exit6_Male_Goatee"]],
                                             512, "Exit6V3_FaceDetails", extrusion=0.01, ray=0.03)
    face.name = face.data.name = "FaceDetails_Geo"
    briefs = copy_rest(O["Exit6_Male_Briefs"], coll, "Briefs_Geo", decimate=3000)
    briefs.name = briefs.data.name = "Briefs_Geo"
    smart_uv(briefs)
    report["textures"]["Briefs"] = bake(briefs, [O["Exit6_Male_Briefs"]], 1024, "Exit6V3_Briefs", extrusion=0.02, ray=0.04)
    log("details baked")
    W, names = limit_weights(body)
    for o in (hair, face, briefs):
        limit_weights(o)
    parts = split_r15(body, W, names, coll)
    hips = Vector(src_rig.data.bones["LowerTorso"].head_local)
    offset = -hips
    allm = list(parts.values()) + [hair, face, briefs]
    for o in allm:
        o.data.transform(Matrix.Translation(offset))
    bpy.data.objects.remove(body)
    rig = build_game_rig(coll, offset, src_rig)
    for o in allm:
        o.parent = rig
        o.modifiers.clear()
        m = o.modifiers.new("Armature", "ARMATURE"); m.object = rig
    bpy.context.view_layer.update()
    report["attachments"] = make_attachments(parts, rig, coll)
    total = 0
    for o in allm:
        o.data.calc_loop_triangles()
        n = len(o.data.loop_triangles); total += n
        report["objects"][o.name] = {"verts": len(o.data.vertices), "tris": n}
    report["total_tris"] = total
    report["r15_body_tris"] = sum(report["objects"][p + "_Geo"]["tris"] for p in BONES)
    report["max_part_tris"] = max(report["objects"][p + "_Geo"]["tris"] for p in BONES)
    report["bones"] = [b.name for b in rig.data.bones]
    report["offset_studs"] = list(offset)
    for o in bpy.context.view_layer.objects:
        o.select_set(o.name in coll.objects)
    glb = os.path.join(OUT, "Exit6_Male_V3.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=False, export_yup=True,
                              export_apply=False, export_morph=False)
    log("exported", glb)
    src_rig.data.pose_position = "POSE"
    with open(os.path.join(OUT, "export_report_v3.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)
    log("saved; total tris", total, "body", report["r15_body_tris"])


main()
