"""Make the game-ready Exit 6 male from the source .blend and export GLB/FBX.

    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_Base.blend \
        -P tools/characters/export_exit6_male.py

Steps
  1. Duplicate each source mesh at rest, apply non-deform modifiers, decimate
     to a game budget, keep at most 4 bone influences per vertex.
  2. Smart-UV the game meshes and bake base colour (and a tangent normal map
     for the body) from the high-resolution source with Cycles.
  3. Split the body into the 15 R15 parts (<Part>_Geo) by dominant bone.
  4. Build a Roblox rig (Root > HumanoidRootNode > LowerTorso ...) with Root and
     LowerTorso at the origin, move the game meshes to match, bind.
  5. Export Exit6_Male_Base.glb (+ .fbx), save the .blend with the game
     collection added, write export_report.json.
"""
import bpy, bmesh, os, sys, json, math, time
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exit6_male_spec as S

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "characters", "exit6_male")
TEX = os.path.join(OUT, "textures")
os.makedirs(TEX, exist_ok=True)
K = S.HEIGHT_STUDS / (S.SOLE - S.SKULL_TOP)
T0 = time.time()

BONES = ["LowerTorso", "UpperTorso", "Head",
         "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
         "RightUpperLeg", "RightLowerLeg", "RightFoot"]

# target triangles for the game copies (whole body before the R15 split)
BUDGET = {"Exit6_Male_Body": 14000, "Exit6_Male_Hair_Twists": 7000, "Exit6_Male_Hair_Scalp": 900,
          "Exit6_Male_Briefs": 1600, "Exit6_Male_Goatee": 300, "Exit6_Male_Brows": 160,
          "Exit6_Male_Eye_L": 240, "Exit6_Male_Eye_R": 240}
TEXSIZE = {"Exit6_Male_Body": 2048, "Exit6_Male_Hair_Twists": 512, "Exit6_Male_Hair_Scalp": 512,
           "Exit6_Male_Briefs": 1024, "Exit6_Male_Goatee": 256, "Exit6_Male_Brows": 128,
           "Exit6_Male_Eye_L": 256, "Exit6_Male_Eye_R": 256}


def log(*a):
    print("[export %6.1fs]" % (time.time() - T0), *a, flush=True)


def activate(ob):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)


def game_copy(src, coll):
    """Rest-pose copy with solidify applied, decimated, weights kept."""
    me = src.data.copy()
    ob = bpy.data.objects.new(src.name.replace("Exit6_Male_", "Game_"), me)
    coll.objects.link(ob)
    for vg in src.vertex_groups:
        ob.vertex_groups.new(name=vg.name)
    for m in src.modifiers:
        if m.type == "SOLIDIFY":
            s = ob.modifiers.new(m.name, "SOLIDIFY"); s.thickness = m.thickness; s.offset = m.offset
    me.calc_loop_triangles()
    tris = len(me.loop_triangles) * (2 if any(m.type == "SOLIDIFY" for m in src.modifiers) else 1)
    target = BUDGET[src.name]
    if tris > target:
        d = ob.modifiers.new("decimate", "DECIMATE"); d.ratio = max(target / tris, 0.0005)
        d.use_collapse_triangulate = True
    activate(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    ob.data.shade_smooth()
    return ob


def limit_weights(ob, keep=4):
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


def smart_uv(ob):
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


def bake_material(game, src, size, normal=False):
    name = game.name
    img = bpy.data.images.new(name + "_Color", size, size, alpha=False)
    mat = bpy.data.materials.new("M_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    p = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
    nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    game.data.materials.clear(); game.data.materials.append(mat)
    srcmat = src.data.materials[0]
    p.inputs["Roughness"].default_value = srcmat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.03
    sc.render.bake.max_ray_distance = 0.08
    sc.render.bake.margin = 6
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    src.hide_set(False); src.hide_render = False
    src.select_set(True)
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
    """One <Part>_Geo per R15 part by the dominant bone of each face."""
    me = body.data
    vdom = np.array(names)[W.argmax(1)]
    parts = {}
    bm = bmesh.new(); bm.from_mesh(me)
    deform = bm.verts.layers.deform.verify()
    face_part = []
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
        kill = [bm.faces[i] for i, p in enumerate(face_part) if p != part]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bm.to_mesh(ob.data); bm.free()
        ob.data.calc_loop_triangles()
        out[part] = ob
    bpy.data.objects.remove(body)
    return out


def build_game_rig(coll, offset):
    arm = bpy.data.armatures.new("Exit6_Male_GameRig")
    rig = bpy.data.objects.new("Exit6_Male_GameRig", arm)
    coll.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones
    src = bpy.data.objects["Exit6_Male_Rig"].data
    off = Vector(offset)

    root = eb.new("Root"); root.head = (0, 0, 0); root.tail = (0, 0, 0.3); root.use_deform = False
    hrn = eb.new("HumanoidRootNode"); hrn.head = (0, 0, 0); hrn.tail = (0, 0, 0.35)
    hrn.parent = root; hrn.use_deform = False
    for b in src.bones:
        if b.name == "HumanoidRootNode":
            continue
        e = eb.new(b.name)
        e.head = b.head_local + off; e.tail = b.tail_local + off
        e.align_roll(Vector((0, -1, 0)))
    for b in src.bones:
        if b.name == "HumanoidRootNode":
            continue
        par = b.parent.name if b.parent else None
        eb[b.name].parent = eb[par] if par and par in eb else hrn
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def main():
    sc = bpy.context.scene
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
    sc.frame_set(1)
    src_rig = bpy.data.objects["Exit6_Male_Rig"]
    src_rig.data.pose_position = "REST"
    old = bpy.data.collections.get("Exit6_Male_Game")
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(old)
    coll = bpy.data.collections.new("Exit6_Male_Game")
    sc.collection.children.link(coll)
    report = {"objects": {}, "textures": {}}
    games = {}
    for name in BUDGET:
        src = bpy.data.objects[name]
        g = game_copy(src, coll)
        log("decimated", name, "->", len(g.data.polygons), "faces")
        games[name] = (g, src)
    for name, (g, src) in games.items():
        smart_uv(g)
        report["textures"][g.name] = bake_material(g, src, TEXSIZE[name], normal=(name == "Exit6_Male_Body"))
        log("baked", name)
    # merge face pieces and hair pieces
    def join(target, others, new_name):
        activate(target)
        for o in others:
            o.select_set(True)
        bpy.ops.object.join()
        target.name = new_name; target.data.name = new_name
        return target
    g = {n: games[n][0] for n in games}
    hair = join(g["Exit6_Male_Hair_Twists"], [g["Exit6_Male_Hair_Scalp"]], "Hair_Geo")
    face = join(g["Exit6_Male_Eye_L"], [g["Exit6_Male_Eye_R"], g["Exit6_Male_Brows"], g["Exit6_Male_Goatee"]], "FaceDetails_Geo")
    briefs = g["Exit6_Male_Briefs"]; briefs.name = briefs.data.name = "Briefs_Geo"
    body = g["Exit6_Male_Body"]
    W, names = limit_weights(body)
    for o in (hair, face, briefs):
        limit_weights(o)
    parts = split_r15(body, W, names, coll)
    # Root and LowerTorso at the origin
    hips = Vector(src_rig.data.bones["LowerTorso"].head_local)
    offset = -hips
    for o in list(parts.values()) + [hair, face, briefs]:
        o.data.transform(Matrix.Translation(offset))
    rig = build_game_rig(coll, offset)
    for o in list(parts.values()) + [hair, face, briefs]:
        o.parent = rig
        o.modifiers.clear()
        m = o.modifiers.new("Armature", "ARMATURE"); m.object = rig
    total = 0
    for o in list(parts.values()) + [hair, face, briefs]:
        o.data.calc_loop_triangles()
        n = len(o.data.loop_triangles); total += n
        report["objects"][o.name] = {"verts": len(o.data.vertices), "tris": n,
                                     "materials": [m.name for m in o.data.materials]}
    report["total_tris"] = total
    report["r15_body_tris"] = sum(report["objects"][p + "_Geo"]["tris"] for p in BONES)
    report["bones"] = [b.name for b in rig.data.bones]
    report["offset_studs"] = list(offset)
    # export only the game collection
    for o in bpy.context.view_layer.objects:
        o.select_set(o.name in coll.objects)
    glb = os.path.join(OUT, "Exit6_Male_Base.glb")
    bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", use_selection=True,
                              export_skins=True, export_animations=False, export_yup=True,
                              export_apply=False, export_morph=False)
    log("exported", glb)
    fbx = os.path.join(OUT, "Exit6_Male_Base.fbx")
    bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, add_leaf_bones=False, bake_anim=False,
                             apply_scale_options="FBX_SCALE_UNITS", path_mode="COPY", embed_textures=True,
                             object_types={"ARMATURE", "MESH"})
    log("exported", fbx)
    src_rig.data.pose_position = "POSE"
    # keep the source collection visible, game collection alongside
    with open(os.path.join(OUT, "export_report.json"), "w") as fh:
        json.dump(report, fh, indent=1)
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath, compress=True)
    log("saved", bpy.data.filepath, "total tris", total)


main()
