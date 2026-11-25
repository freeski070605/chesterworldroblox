"""Render the body parts (clay) with their *_OuterCage / *_InnerCage meshes as wireframes.

    blender -b --factory-startup <game.blend> -P tools/harness/render_cage_check.py -- <out_prefix> [cage-substring]
"""
import bpy, sys, math, os
ARGV = sys.argv[sys.argv.index("--") + 1:]
PREFIX = os.path.abspath(ARGV[0])
SUB = ARGV[1] if len(ARGV) > 1 else "_OuterCage"
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 16; sc.cycles.device = "CPU"
sc.render.film_transparent = False
clay = bpy.data.materials.new("clay"); clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.5, 0.5, 0.52, 1)
wire = bpy.data.materials.new("wire"); wire.use_nodes = True
nt = wire.node_tree; p = nt.nodes["Principled BSDF"]
p.inputs["Emission Color"].default_value = (1.0, 0.25, 0.05, 1); p.inputs["Emission Strength"].default_value = 3
zmin, zmax = 1e9, -1e9
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    o.hide_render = False
    if SUB in o.name or o.name == "Exit6V31_BodyCage":
        if o.name == "Exit6V31_BodyCage" and SUB != "BodyCage":
            o.hide_render = True; continue
        o.data.materials.clear(); o.data.materials.append(wire)
        w = o.modifiers.new("w", "WIREFRAME"); w.thickness = 0.006; w.use_replace = True
    elif o.name.endswith("_Att"):
        o.hide_render = True
    else:
        o.data.materials.clear(); o.data.materials.append(clay)
        for v in o.data.vertices:
            z = (o.matrix_world @ v.co).z; zmin = min(zmin, z); zmax = max(zmax, z)
if not bpy.data.lights:
    for az in (30, -40, 180):
        L = bpy.data.lights.new("L%d" % az, "SUN"); L.energy = 3
        ob = bpy.data.objects.new("L%d" % az, L); sc.collection.objects.link(ob)
        ob.rotation_euler = (math.radians(55), 0, math.radians(az))
cam_d = bpy.data.cameras.new("cc"); cam_d.type = "ORTHO"; cam_d.ortho_scale = (zmax - zmin) * 1.08
cam = bpy.data.objects.new("cc", cam_d); sc.collection.objects.link(cam); sc.camera = cam
sc.render.resolution_x = 900; sc.render.resolution_y = 1500
zc = (zmin + zmax) / 2
for name, az in (("front", 0), ("side", 90), ("back", 180), ("q34", 35)):
    a = math.radians(az)
    cam.location = (math.sin(a) * 20, -math.cos(a) * 20, zc)
    cam.rotation_euler = (math.radians(90), 0, a)
    sc.render.filepath = "%s_%s.png" % (PREFIX, name)
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath, flush=True)
