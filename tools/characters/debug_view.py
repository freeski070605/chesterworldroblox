"""Fast Workbench close-up of parts of the saved character (debug aid).

blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_Base.blend \
    -P tools/characters/debug_view.py -- out.png az=35 cy=650 h=300 show=Body,Briefs [frame=1] [cycles]

cy/h are reference-image rows (centre row and visible height).
"""
import bpy, sys, math, os

argv = sys.argv[sys.argv.index("--") + 1:]
out = os.path.abspath(argv[0])
kw = dict(a.split("=", 1) for a in argv[1:] if "=" in a)
flags = [a for a in argv[1:] if "=" not in a]
K = 5.6 / 924.0
az = math.radians(float(kw.get("az", 0)))
cy = float(kw.get("cy", 700)); h = float(kw.get("h", 1400))
show = kw.get("show")
sc = bpy.context.scene
if show:
    keys = show.split(",")
    for ob in sc.objects:
        if ob.type == "MESH" and ob.name.startswith("Exit6_Male_"):
            ob.hide_render = not any(k in ob.name for k in keys)
if "frame" in kw:
    sc.frame_set(int(kw["frame"]))
cam = sc.camera or bpy.data.objects.get("Exit6_Camera")
if cam is None:
    cd = bpy.data.cameras.new("DbgCam"); cam = bpy.data.objects.new("DbgCam", cd)
    sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.sensor_fit = "VERTICAL"; cam.data.ortho_scale = h * K
cx = float(kw.get("cx", 0)) * K
cam.location = (math.sin(az) * 30 + math.cos(az) * cx, -math.cos(az) * 30 + math.sin(az) * cx, (1140 - cy) * K)
cam.rotation_euler = (math.radians(90), 0, az)
sc.render.resolution_x = int(kw.get("w", 800)); sc.render.resolution_y = int(kw.get("px", 800))
sc.render.resolution_percentage = 100
if "cycles" in flags:
    sc.render.engine = "CYCLES"; sc.cycles.samples = int(kw.get("samples", 32))
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices: d.use = d.type != "CPU"
    sc.cycles.device = "GPU"
else:
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"; sh.color_type = kw.get("color", "MATERIAL")
    sh.show_cavity = True; sh.cavity_type = "BOTH"
    sc.render.film_transparent = False
    sc.world and None
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("wrote", out)
