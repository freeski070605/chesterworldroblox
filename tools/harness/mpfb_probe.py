"""Probe: can MPFB create a human headless under --factory-startup?

blender -b --factory-startup -P tools/harness/mpfb_probe.py
"""
import bpy, addon_utils, sys, os, math, json, time
from mathutils import Vector

T0 = time.time()
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "exit6_v2")
os.makedirs(OUT, exist_ok=True)

mods = [m.__name__ for m in addon_utils.modules()]
print("mpfb modules:", [m for m in mods if "mpfb" in m or "keentools" in m])
name = [m for m in mods if m.endswith("mpfb")][0]
addon_utils.enable(name, default_set=True)
mp = sys.modules[name]
from importlib import import_module
HS = import_module(name + ".services.humanservice").HumanService
TS = import_module(name + ".services.targetservice").TargetService
LS = import_module(name + ".services.locationservice").LocationService

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
macro = TS.get_default_macro_info_dict()
macro.update({"gender": 1.0, "age": 0.5, "muscle": 0.9, "weight": 0.5, "proportions": 0.8, "height": 0.6})
macro["race"] = {"african": 1.0, "asian": 0.0, "caucasian": 0.0}
bm = HS.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True, feet_on_ground=True,
                     scale=0.1, macro_detail_dict=macro)
print("basemesh", bm.name, len(bm.data.vertices), "keys", [k.name for k in bm.data.shape_keys.key_blocks][:20])
print("vgroups", len(bm.vertex_groups), [g.name for g in bm.vertex_groups][:80])
print("dims", tuple(bm.dimensions))
udata = LS.get_user_data("eyes")
print("user eyes", udata)
eyes = os.path.join(udata, "high-poly", "high-poly.mhclo")
try:
    e = HS.add_mhclo_asset(eyes, bm, asset_type="Eyes", subdiv_levels=0, material_type="PROCEDURAL_EYES")
    print("eyes ok", e)
except Exception as ex:
    import traceback; traceback.print_exc()
print("objects", [(o.name, o.type) for o in bpy.data.objects])
print("time", time.time() - T0)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "mpfb_probe.blend"))
