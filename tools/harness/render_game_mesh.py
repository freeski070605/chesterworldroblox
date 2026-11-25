"""Render the GAME meshes (low-poly + baked colour / normal) of an Exit 6 character the way the
engine sees them, under one neutral light rig, for before/after comparisons.

    blender -b --factory-startup <file.blend> -P tools/harness/render_game_mesh.py -- <out_prefix> [collection-suffix]

Only objects named *_Geo (and Hair/Eyes/Brows/Goatee pieces) inside a collection ending with
the suffix (default "_Game") are rendered; everything else is hidden. Frame = game frame
(LowerTorso at origin, feet at z ~ -2.97).
"""
import bpy, sys, math, os
ARGV = sys.argv[sys.argv.index("--") + 1:]
PREFIX = os.path.abspath(ARGV[0])
SUFFIX = ARGV[1] if len(ARGV) > 1 else "_Game"
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.samples = 48
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices:
        d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
except Exception:
    pass
sc.render.film_transparent = False
for o in bpy.data.objects:
    if SUFFIX == "*":     # dressed: every game mesh (parts + wear items), no hi-res sources / cages
        keep = o.type == "MESH" and (o.name.endswith("_Geo") or o.name.startswith("Exit6_")) and not any(
            k in o.name for k in ("_Hi", "Cage", "Wear_Body"))
        keep = keep and "Briefs" not in o.name     # layered under the pants in Roblox
    else:
        keep = any(c.name.endswith(SUFFIX) for c in o.users_collection) and o.type == "MESH" and (
            o.name.endswith("_Geo") or o.name.startswith("Briefs"))
    if o.type == "LIGHT":
        bpy.data.objects.remove(o); continue
    o.hide_render = not keep
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
world = sc.world or bpy.data.worlds.new("W"); sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.78, 0.77, 0.8, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35


def area(name, az, el, dist, size, power):
    L = bpy.data.lights.new(name, "AREA"); L.size = size; L.energy = power
    ob = bpy.data.objects.new(name, L); sc.collection.objects.link(ob)
    a, e = math.radians(az), math.radians(el)
    ob.location = (math.sin(a) * math.cos(e) * dist, -math.cos(a) * math.cos(e) * dist, 0.6 + math.sin(e) * dist)
    d = -ob.location.normalized() if hasattr(ob.location, "normalized") else None
    ob.rotation_euler = (math.radians(90) - e, 0, a)
    return ob


area("Key", -35, 30, 9, 5, 900)
area("Fill", 40, 10, 9, 6, 380)
area("Rim", 170, 35, 9, 5, 500)
cam_d = bpy.data.cameras.new("gc"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("gc", cam_d); sc.collection.objects.link(cam); sc.camera = cam
SHOTS = {  # name: (azimuth, z centre, ortho height, width/height)
    "torso_front": (0, 0.95, 1.9, 0.9), "torso_q34": (35, 0.95, 1.9, 0.9), "back": (180, 0.9, 2.2, 0.9),
    "legs_front": (0, -1.75, 2.6, 0.6), "legs_back": (180, -1.75, 2.6, 0.6), "full_front": (0, -0.2, 5.9, 0.42),
    "full_q34": (35, -0.2, 5.9, 0.42), "face": (0, 2.2, 0.8, 0.85), "arm_side": (90, 0.6, 2.0, 0.6),
}
only = ARGV[2].split(",") if len(ARGV) > 2 else list(SHOTS)
for name in only:
    az, zc, h, asp = SHOTS[name]
    a = math.radians(az)
    cam.location = (math.sin(a) * 20, -math.cos(a) * 20, zc)
    cam.rotation_euler = (math.radians(90), 0, a)
    cam_d.ortho_scale = h
    sc.render.resolution_y = 1400 if h > 1 else 1000
    sc.render.resolution_x = int(sc.render.resolution_y * asp)
    # ortho_scale applies to the larger dimension
    if sc.render.resolution_x > sc.render.resolution_y:
        cam_d.ortho_scale = h * asp
    sc.render.filepath = "%s_%s.png" % (PREFIX, name)
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath, flush=True)
