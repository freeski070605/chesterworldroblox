"""Fit check for the V3.1 wear bundle (layering, creases, toe shape, chain clearance).

    blender -b --factory-startup -P tools/characters/check_exit6_wear_v31.py -- <bundle_dir> <report.json>

<bundle_dir> holds Exit6_Male_V3_1_Body.glb + Exit6_{Briefs,Cargo,Puffer,Sneakers,Jewelry}.glb
(assets/characters/exit6_male/wear_v31 plus the body GLB, or an extracted older revision).

Every GLB brings its own copy of the R15 rig; all copies get the same pose, so the skinned
meshes are compared the way Roblox stacks them. Heights are measured along outward rays from
the posed skin: a layer clips when something under it reaches further out than its inner wall.

Poses: rest, stride (one thigh forward 55 deg, knee 45, the other back 20), squat (thighs 80,
knees 95), sit (90/90: driving and bikes), reach (arms raised sideways 70 deg).
"""
import bpy, os, sys, json, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ARGV = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = ARGV[0], ARGV[1]
FILES = ["Exit6_Male_V3_1_Body", "Exit6_Briefs", "Exit6_Cargo", "Exit6_Puffer", "Exit6_Sneakers", "Exit6_Jewelry"]

bpy.ops.wm.read_factory_settings(use_empty=True)
for f in FILES:
    path = os.path.join(SRC, f + ".glb")
    if os.path.exists(path):
        bpy.ops.import_scene.gltf(filepath=path)
O = bpy.data.objects
RIGS = [o for o in O if o.type == "ARMATURE"]


POSES = {   # body faces -Y; +X rotation swings a thigh backwards, so forward flex is negative
    "rest": {},
    "stride": {"LeftUpperLeg": -55, "LeftLowerLeg": 45, "RightUpperLeg": 20},
    "squat": {"LeftUpperLeg": -80, "RightUpperLeg": -80, "LeftLowerLeg": 95, "RightLowerLeg": 95},
    "sit": {"LeftUpperLeg": -90, "RightUpperLeg": -90, "LeftLowerLeg": 90, "RightLowerLeg": 90},
    "reach": {"LeftUpperArm": ("side", -70), "RightUpperArm": ("side", 70)},
}


def set_pose(spec):
    """rotate about world X (legs: forward flex) or world Y (arms: raise sideways), applied in each
    bone's own frame so every rig copy gets the identical pose"""
    for rig in RIGS:
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1, 0, 0, 0)
        bpy.context.view_layer.update()
        for name, val in spec.items():
            pb = rig.pose.bones.get(name)
            if pb is None:
                continue
            axis, deg = ("fwd", val) if not isinstance(val, tuple) else val
            world_axis = Vector((1, 0, 0)) if axis == "fwd" else Vector((0, 1, 0))
            bone_rest = (rig.matrix_world @ pb.bone.matrix_local).to_3x3().normalized()
            local_axis = (bone_rest.inverted() @ world_axis).normalized()
            pb.rotation_quaternion = Matrix.Rotation(math.radians(deg), 3, local_axis).to_quaternion()
    bpy.context.view_layer.update()


def world_mesh(names):
    """evaluated (posed) world-space verts/faces for the named mesh objects, merged"""
    dg = bpy.context.evaluated_depsgraph_get()
    V, F, off = [], [], 0
    for n in names:
        ob = O.get(n)
        if ob is None:
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        M = np.array(ev.matrix_world)
        P = np.array([v.co for v in me.vertices]).reshape(-1, 3) @ M[:3, :3].T + M[:3, 3]
        V.append(P)
        F += [tuple(i + off for i in p.vertices) for p in me.polygons]
        off += len(P)
        ev.to_mesh_clear()
    if not V:
        return None, None, None
    V = np.concatenate(V)
    return V, F, BVHTree.FromPolygons([Vector(p) for p in V], F)


def heights(points, body_bvh, layer_bvh, reach=0.6, outer=False):
    """for each point: its height above the skin (h) and the height of the layer's first wall along
    the same outward ray (t, nan where the layer does not cover that spot); outer=True takes the
    last wall within reach instead (the outside of a solidified garment)"""
    h, t = np.full(len(points), np.nan), np.full(len(points), np.nan)
    for i, p in enumerate(points):
        loc, nrm, _, _ = body_bvh.find_nearest(Vector(p))
        if loc is None:
            continue
        d = Vector(p) - loc
        n = nrm if d.dot(nrm) >= 0 else -nrm
        h[i] = d.dot(n)
        start, travelled = loc + n * 1e-4, 0.0
        while True:
            hit, _, _, dist = layer_bvh.ray_cast(start, n, reach - travelled)
            if hit is None:
                break
            travelled += dist
            t[i] = travelled
            if not outer:
                break
            start, travelled = hit + n * 1e-4, travelled + 1e-4
    return h, t


DIRS = [Vector(d) for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]


def visible(points, over_bvh, reach=3.0):
    """points that can be seen along any axis view without passing through the over layer (rays that
    hit only the body are counted visible too, so this over-counts, never under-counts)"""
    out = np.zeros(len(points), bool)
    for i, p in enumerate(points):
        for d in DIRS:
            hit, _, _, dist = over_bvh.ray_cast(Vector(p) - d * reach, d, reach - 1e-3)
            if hit is None:
                out[i] = True
                break
    return out


def clip_stats(under_pts, body_bvh, over_bvh, margin=0.0):
    """poke: ray metric along the skin normal (ambiguous in concave spots such as the crotch, where the
    ray leaves the inner thigh sideways); seen: covered points visible from an axis view = what shows"""
    h, t = heights(under_pts, body_bvh, over_bvh)
    covered = ~np.isnan(t) & ~np.isnan(h)
    gap = t[covered] - h[covered]          # > 0: the under layer stays inside the over layer
    poke = gap < margin
    seen = visible(under_pts[covered][poke], over_bvh)
    return {"covered": int(covered.sum()), "poke": int(poke.sum()), "seen": int(seen.sum()),
            "min_gap": round(float(gap.min()), 4) if len(gap) else None,
            "p1_gap": round(float(np.percentile(gap, 1)), 4) if len(gap) else None}


def dihedral(V, F, sel_fn):
    """angle (deg) between neighbouring face normals, for faces whose centre passes sel_fn"""
    import collections
    Fn, C = [], []
    for f in F:
        p = V[list(f)]
        n = np.cross(p[1] - p[0], p[2] - p[0])
        Fn.append(n / max(np.linalg.norm(n), 1e-12)); C.append(p.mean(0))
    Fn, C = np.array(Fn), np.array(C)
    edge = collections.defaultdict(list)
    for fi, f in enumerate(F):
        for a, b in zip(f, list(f[1:]) + [f[0]]):
            edge[(min(a, b), max(a, b))].append(fi)
    ang = []
    for faces in edge.values():
        if len(faces) == 2 and sel_fn(C[faces[0]]) and sel_fn(C[faces[1]]):
            c = float(np.clip(np.dot(Fn[faces[0]], Fn[faces[1]]), -1, 1))
            ang.append(math.degrees(math.acos(c)))
    ang = np.array(ang) if ang else np.zeros(1)
    return {"edges": int(len(ang)), "p95": round(float(np.percentile(ang, 95)), 2),
            "p99": round(float(np.percentile(ang, 99)), 2), "max": round(float(ang.max()), 2),
            "over30": int((ang > 30).sum())}


BODY = [o.name for o in O if o.type == "MESH" and o.name.endswith("_Geo")]
report = {"src": SRC, "poses": {}}
for pose, spec in POSES.items():
    set_pose(spec)
    bV, bF, body = world_mesh(BODY)
    r = {}
    brV, _, _ = world_mesh(["Exit6_Briefs"])
    cV, cF, cargo = world_mesh(["Exit6_Cargo"])
    pV, pF, puffer = world_mesh(["Exit6_Puffer"])
    if brV is not None and cargo is not None:
        r["briefs_under_cargo"] = clip_stats(brV, body, cargo)
    if brV is not None and puffer is not None:
        r["briefs_under_puffer"] = clip_stats(brV, body, puffer)
    if cV is not None and puffer is not None:
        r["cargo_under_puffer"] = clip_stats(cV, body, puffer)
    if pose == "rest":
        # cage nesting: cargo inner cage must enclose the briefs outer cage
        bo, _, _ = world_mesh(["Exit6_Briefs_OuterCage"])
        ci, _, _ = world_mesh(["Exit6_Cargo_InnerCage"])
        if bo is not None and ci is not None and len(bo) == len(ci):
            hb, _ = heights(bo, body, cargo)
            hc, _ = heights(ci, body, cargo)
            d = hc - hb
            r["cage_nesting_cargo_over_briefs"] = {"verts": len(d), "inside_out": int((d < 0).sum()),
                                                  "min": round(float(np.nanmin(d)), 4)}
        if pV is not None:
            r["puffer_seam_dihedral"] = dihedral(pV, pF, lambda c: 0.45 < abs(c[0]) < 1.0 and 1.0 < c[2] < 1.75)
            r["puffer_body_dihedral"] = dihedral(pV, pF, lambda c: abs(c[0]) < 0.35 and 0.3 < c[2] < 1.2)
        sV, sF, _ = world_mesh(["Exit6_Sneakers"])
        if sV is not None:
            toe = sV[:, 1].min()     # glTF +Z forward imports as Blender -Y
            r["sneaker_toe_dihedral"] = dihedral(sV, sF, lambda c: c[1] < toe + 0.30)
            r["sneaker_upper_dihedral"] = dihedral(sV, sF, lambda c: toe + 0.45 < c[1] < toe + 0.75 and c[2] > -2.85)
        # chains are rigid accessories: compare rest positions only
        for chain in ("Exit6_Chain", "Exit6_Chain_Over"):
            chV, _, _ = world_mesh([chain])
            if chV is None:
                continue
            hb, _ = heights(chV, body, body)
            r[chain + "_skin_clearance_min"] = round(float(np.nanmin(hb)), 4)
            if puffer is not None:
                h, t_in = heights(chV, body, puffer)
                _, t_out = heights(chV, body, puffer, outer=True)
                covered = ~np.isnan(t_in)
                r[chain + "_vs_puffer"] = {"covered": int(covered.sum()),
                                          "under_inner_wall": int((h[covered] < t_in[covered]).sum()),
                                          "inside_shell": int(((h >= t_in) & (h < t_out))[covered].sum()),
                                          "outside": int((h[covered] >= t_out[covered]).sum()),
                                          "min_clear_inner": round(float(np.nanmin(t_in[covered] - h[covered])), 4) if covered.any() else None,
                                          "min_clear_outer": round(float(np.nanmin(h[covered] - t_out[covered])), 4) if covered.any() else None}
    report["poses"][pose] = r
    print("POSE", pose, json.dumps(r), flush=True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as fh:
    json.dump(report, fh, indent=1)
print("WROTE", OUT)
