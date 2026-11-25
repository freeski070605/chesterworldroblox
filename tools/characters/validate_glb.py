"""Validate Exit6_Male_Base.glb in a clean Blender session and render it.

blender -b --factory-startup -P tools/characters/validate_glb.py

Checks: meshes / triangles / skins / joints / textures from the raw glTF JSON,
then a fresh import (objects, bone hierarchy, vertex-group influence counts,
bounding box in studs, which way the face points) plus front and 3/4 renders
of the imported game asset. Writes validate_report.json next to the GLB.
"""
import bpy, json, os, struct, sys, math
import numpy as np
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "assets", "characters", "exit6_male")
_A = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
# optional: -- <glb name> <render dir name> <report name>
GLB = os.path.join(OUT, _A[0] if _A else "Exit6_Male_Base.glb")
REN_SUB = _A[1] if len(_A) > 1 else "renders"
REPORT = _A[2] if len(_A) > 2 else "validate_report.json"
rep = {"file": os.path.relpath(GLB, REPO), "bytes": os.path.getsize(GLB)}

with open(GLB, "rb") as fh:
    magic, ver, length = struct.unpack("<4sII", fh.read(12))
    clen, ctype = struct.unpack("<I4s", fh.read(8))
    gl = json.loads(fh.read(clen))
assert magic == b"glTF" and ver == 2
acc = gl["accessors"]
meshes = {}
atts = []
for m in gl["meshes"]:
    tris = 0; verts = 0
    if m["name"].endswith("_Att") or m["name"].endswith("_OuterCage"):
        atts.append(m["name"]); continue
    for p in m["primitives"]:
        verts += acc[p["attributes"]["POSITION"]]["count"]
        tris += acc[p["indices"]]["count"] // 3
        assert "JOINTS_0" in p["attributes"] and "WEIGHTS_0" in p["attributes"], m["name"]
        assert "TEXCOORD_0" in p["attributes"], m["name"]
    meshes[m["name"]] = {"verts": verts, "tris": tris}
rep["gltf"] = {"meshes": meshes, "skins": [{"name": s.get("name"), "joints": len(s["joints"])} for s in gl.get("skins", [])],
               "images": [i.get("name") for i in gl.get("images", [])],
               "materials": [m.get("name") for m in gl.get("materials", [])],
               "total_tris": sum(v["tris"] for v in meshes.values()),
               "attachment_meshes": sorted(atts)}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
objs = [o for o in bpy.context.scene.objects
        if not any(c.name == "glTF_not_exported" for c in o.users_collection)]  # importer bone-shape helper
arm = [o for o in objs if o.type == "ARMATURE"][0]
def tree(b, d=0):
    return [("  " * d) + b.name] + sum((tree(c, d + 1) for c in b.children), [])
roots = [b for b in arm.data.bones if b.parent is None]
rep["import"] = {"objects": sorted(o.name for o in objs if o.type == "MESH"),
                 "bone_tree": sum((tree(r) for r in roots), [])}
lo = np.full(3, 1e9); hi = np.full(3, -1e9); maxinf = 0; zero = 0
for o in objs:
    if o.type != "MESH" or o.name.endswith("_Att"):
        continue
    for v in o.data.vertices:
        w = [g for g in v.groups if g.weight > 1e-4]
        maxinf = max(maxinf, len(w)); zero += (len(w) == 0)
        p = np.array(o.matrix_world @ v.co); lo = np.minimum(lo, p); hi = np.maximum(hi, p)
rep["import"]["max_influences"] = maxinf
rep["import"]["unweighted_verts"] = zero
rep["import"]["bbox_min_studs"] = [round(x, 3) for x in lo]
rep["import"]["bbox_max_studs"] = [round(x, 3) for x in hi]
rep["import"]["height_studs"] = round(hi[2] - lo[2], 3)
head = next(o for o in objs if o.type == "MESH" and o.name.startswith("Head_Geo") and len(o.data.vertices) > 100)
hv = np.array([head.matrix_world @ v.co for v in head.data.vertices])
nose = hv[hv[:, 1].argmin()]
rep["import"]["object_types"] = sorted("%s:%s" % (o.name, o.type) for o in objs if o.type != "ARMATURE")
rep["import"]["face_direction_blender"] = "-Y (glTF +Z, Roblox front after import turn)" if nose[1] < hv[:, 1].mean() - 0.1 else "unexpected"
lb = arm.data.bones["LowerTorso"].head_local
rep["import"]["lowertorso_head"] = [round(x, 4) for x in lb]
rep["import"]["root_head"] = [round(x, 4) for x in arm.data.bones["Root"].head_local]

# render the imported asset (attachment marker meshes hidden)
for o in objs:
    if o.name.endswith("_Att"):
        o.hide_render = True
sc = bpy.context.scene
sc.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
prefs.compute_device_type = "OPTIX"; prefs.get_devices()
for d in prefs.devices:
    d.use = d.type != "CPU"
sc.cycles.device = "GPU"; sc.cycles.samples = 48
sc.view_settings.view_transform = "Standard"
sc.render.film_transparent = True
sc.render.resolution_x, sc.render.resolution_y = 600, 1100
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
for name, loc, power in (("Key", (-4, -6.5, 9), 1300), ("Fill", (7, -7.5, 1), 280), ("Rim", (5, 7, 5), 400)):
    ld = bpy.data.lights.new(name, "AREA"); ld.size = 4; ld.energy = power
    lo_ = bpy.data.objects.new(name, ld); sc.collection.objects.link(lo_); lo_.location = loc
    lo_.rotation_euler = (Vector((0, 0, 0.3)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 6.6
cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
zc = (lo[2] + hi[2]) / 2
rep["renders"] = []
for vname, az in (("front", 0), ("three_quarter", 35)):
    a = math.radians(az)
    cam.location = (math.sin(a) * 30, -math.cos(a) * 30, zc); cam.rotation_euler = (math.radians(90), 0, a)
    p = os.path.join(OUT, REN_SUB, "glb_import_%s.png" % vname)
    sc.render.filepath = p; bpy.ops.render.render(write_still=True)
    rep["renders"].append(os.path.relpath(p, REPO))
with open(os.path.join(OUT, REPORT), "w") as fh:
    json.dump(rep, fh, indent=1)
print("VALIDATE", json.dumps(rep["import"], indent=1))
print("GLTF_TOTAL_TRIS", rep["gltf"]["total_tris"], "skins", rep["gltf"]["skins"], "images", len(rep["gltf"]["images"]))
