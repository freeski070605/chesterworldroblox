"""Render a tight close-up from a saved v2 lab/source .blend (debug aid).

blender -b file.blend -P tools/characters/debug_closeup_v2.py -- out.png az row_top row_bottom x_center width [hide=Name1,Name2]
"""
import bpy, sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exit6_male_spec as S
K = S.HEIGHT_STUDS / (S.SOLE - S.SKULL_TOP)
a = sys.argv[sys.argv.index("--") + 1:]
out, az, top, bot, xc, width = a[0], float(a[1]), float(a[2]), float(a[3]), float(a[4]), float(a[5])
hide = []
for x in a[6:]:
    if x.startswith("hide="):
        hide = x[5:].split(",")
for ob in bpy.data.objects:
    if any(ob.name.startswith(h) for h in hide):
        ob.hide_render = True
sc = bpy.context.scene
cam = sc.camera
r = math.radians(az)
zc = (S.SOLE - (top + bot) / 2) * K
right = (math.cos(r), math.sin(r), 0)
cam.location = (math.sin(r) * 30 + right[0] * xc * K, -math.cos(r) * 30 + right[1] * xc * K, zc)
cam.rotation_euler = (math.radians(90), 0, r)
cam.data.ortho_scale = (bot - top) * K
cam.data.sensor_fit = "VERTICAL"
sc.render.resolution_y = 800
sc.render.resolution_x = int(800 * width / (bot - top))
sc.cycles.samples = 64
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
