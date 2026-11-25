"""Print an inventory of a .blend: collections, objects (type, verts/tris, modifiers, parent,
visibility, world bbox), armatures and materials.

    blender -b --factory-startup <file.blend> -P tools/harness/blend_inventory.py [-- --json=out.json]
"""
import bpy, sys, json
from mathutils import Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUTJ = next((a.split("=", 1)[1] for a in ARGV if a.startswith("--json=")), None)
rep = {"file": bpy.data.filepath, "collections": {}, "objects": {}}
for c in bpy.data.collections:
    rep["collections"][c.name] = {"objects": len(c.objects), "children": [k.name for k in c.children],
                                  "hide_render": c.hide_render}
dg = bpy.context.evaluated_depsgraph_get()
for o in bpy.data.objects:
    d = {"type": o.type, "parent": o.parent.name if o.parent else None,
         "colls": [c.name for c in o.users_collection], "hide_render": o.hide_render,
         "hide_viewport": o.hide_get() if o.name in bpy.context.view_layer.objects else None,
         "mods": [(m.type, m.name) for m in getattr(o, "modifiers", [])],
         "loc": [round(x, 3) for x in o.location], "rot": [round(x, 3) for x in o.rotation_euler],
         "scale": [round(x, 3) for x in o.scale]}
    if o.type == "MESH":
        me = o.data
        me.calc_loop_triangles()
        d.update(verts=len(me.vertices), tris=len(me.loop_triangles), uv=[u.name for u in me.uv_layers],
                 mats=[m.name if m else None for m in me.materials], vgroups=len(o.vertex_groups))
        if len(me.vertices):
            W = [o.matrix_world @ v.co for v in me.vertices]
            d["bbox"] = [[round(min(p[i] for p in W), 3) for i in range(3)],
                         [round(max(p[i] for p in W), 3) for i in range(3)]]
    if o.type == "ARMATURE":
        d["bones"] = [b.name for b in o.data.bones]
    rep["objects"][o.name] = d
for k, v in rep["collections"].items():
    print("COLL", k, v)
for k, v in rep["objects"].items():
    print("OBJ", k, {x: y for x, y in v.items() if x not in ("bones",)})
    if "bones" in v:
        print("   bones:", v["bones"])
if OUTJ:
    with open(OUTJ, "w") as fh:
        json.dump(rep, fh, indent=1)
