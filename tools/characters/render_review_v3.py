"""High-resolution review renders of Exit6_Male_V3.blend (neutral studio light saved in the file).

    blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend \
        -P tools/characters/render_review_v3.py [-- --samples=N]

Writes renders_v3/review_*.png; compose_review_v3.py turns them into the
side-by-side sheets against the reference.
  * face: front / three-quarter / side at 8x reference scale (skin, no-hair, clay)
  * body: front / three-quarter / side at 2x reference scale
  * close-ups: torso front + three-quarter, arm, hand, hair back three-quarter
"""
import bpy, os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exit6_male_spec as S
import build_exit6_male as B

K = B.K
SOLE = S.SOLE
OUT = os.path.join(HERE, "..", "..", "assets", "characters", "exit6_male", "renders_v3")
ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SAMPLES = 128
for a in ARGV:
    if a.startswith("--samples="):
        SAMPLES = int(a.split("=")[1])
sc = bpy.context.scene
cam = sc.camera
sc.cycles.samples = SAMPLES
sc.frame_set(1)
FACE_CAMS = {"front": (0.0, 0.0, 120), "three_quarter": (-35.0, None, 150), "side": (90.0, -5.0, 130)}


def shot(path, az, top, bot, xc, width, px_per_ref):
    a = math.radians(az)
    right = (math.cos(a), math.sin(a), 0)
    if xc is None:      # head axis
        u = 12 * K * right[1]
    else:
        u = xc * K
    zc = (SOLE - (top + bot) / 2) * K
    cam.location = (math.sin(a) * 30 + right[0] * u, -math.cos(a) * 30 + right[1] * u, zc)
    cam.rotation_euler = (math.radians(90), 0, a)
    cam.data.ortho_scale = (bot - top) * K
    cam.data.sensor_fit = "VERTICAL"
    sc.render.resolution_percentage = 100
    sc.render.resolution_x = int(width * px_per_ref)
    sc.render.resolution_y = int((bot - top) * px_per_ref)
    sc.render.filepath = os.path.join(OUT, path)
    bpy.ops.render.render(write_still=True)
    print("rendered", path, flush=True)


hair_like = [o for o in bpy.data.objects if o.type == "MESH" and any(
    k in o.name for k in ("Hair_Twists", "Hair_Scalp", "Brows", "Goatee"))]
# face, three variants
for name, (az, xc, w) in FACE_CAMS.items():
    shot("review_face_%s.png" % name, az, 196, 350, xc, w, 8)
for o in hair_like:
    o.hide_render = True
for name, (az, xc, w) in FACE_CAMS.items():
    shot("review_face_bare_%s.png" % name, az, 196, 350, xc, w, 8)
clay = bpy.data.materials.new("M_ReviewClay"); clay.use_nodes = True
p = clay.node_tree.nodes["Principled BSDF"]
p.inputs["Base Color"].default_value = (0.42, 0.42, 0.43, 1); p.inputs["Roughness"].default_value = 0.55
bpy.context.view_layer.material_override = clay
for name, (az, xc, w) in FACE_CAMS.items():
    shot("review_face_clay_%s.png" % name, az, 196, 350, xc, w, 8)
# body clay (form only)
for name, az in (("front", 0.0), ("three_quarter", 35.0), ("side", 90.0)):
    shot("review_body_clay_%s.png" % name, az, 180, 1175, 0.0, 300, 2)
bpy.context.view_layer.material_override = None
for o in hair_like:
    o.hide_render = False
# full body, 2x
for name, az in (("front", 0.0), ("three_quarter", 35.0), ("side", 90.0), ("back", 180.0)):
    shot("review_body_%s.png" % name, az, 180, 1175, 0.0, 300, 2)
# close-ups
shot("review_torso_front.png", 0.0, 380, 720, 0.0, 300, 4)
shot("review_torso_three_quarter.png", 35.0, 380, 720, 0.0, 300, 4)
shot("review_arm_front.png", 0.0, 400, 700, -110, 90, 4)
shot("review_hand_front.png", 0.0, 640, 800, -130, 90, 6)
shot("review_hair_back34.png", 145.0, 196, 350, None, 160, 6)
shot("review_legs_front.png", 0.0, 700, 1140, 0.0, 240, 3)
