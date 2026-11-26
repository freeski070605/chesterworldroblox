"""Check that the approved V3.1 body (mesh, skin, rig, textures, face/hair parts, marker positions) did not change."""
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = "assets/characters/exit6_male/Exit6_Male_V3_1_Body.glb"
TAG = "exit6-male-v3.1-approved"
PARTS = [
    "assets/characters/exit6_male/Exit6_Male_V3_1_Parts.glb",
    "assets/wear/exit6_male_v31/Exit6_Male_V3_1_Parts.glb",
    "assets/characters/exit6_male/Exit6_Male_V3_1.blend",
    "assets/characters/exit6_male/textures_v3_1/Exit6V31_Body_Color.png",
    "assets/characters/exit6_male/textures_v3_1/Exit6V31_Body_Normal.png",
    "assets/characters/exit6_male/textures_v3_1/Exit6V31_FaceDetails_Color.png",
    "assets/characters/exit6_male/textures_v3_1/Exit6V31_Hair_Color.png",
    "assets/characters/exit6_male/textures_v3_1/Exit6V31_Hair_Normal.png",
]

def parse(data):
    assert data[:4] == b"glTF"
    length, kind = struct.unpack_from("<II", data, 12)
    assert kind == 0x4E4F534A
    info = json.loads(data[20:20 + length])
    start = 20 + length
    binary_length, binary_kind = struct.unpack_from("<II", data, start)
    assert binary_kind == 0x004E4942
    return info, memoryview(data)[start + 8:start + 8 + binary_length]

def meshes(data):
    info, binary = parse(data)
    result = {}
    for mesh in info["meshes"]:
        if not mesh["name"].endswith("_Geo"):
            continue
        for pi, primitive in enumerate(mesh["primitives"]):
            for name, accessor_index in {**primitive["attributes"], "indices": primitive["indices"]}.items():
                accessor = info["accessors"][accessor_index]
                view = info["bufferViews"][accessor["bufferView"]]
                begin = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
                result[(mesh["name"], pi, name)] = bytes(binary[begin:begin + view["byteLength"]])
    return result

def view_bytes(info, binary, view_index):
    view = info["bufferViews"][view_index]
    begin = view.get("byteOffset", 0)
    return bytes(binary[begin:begin + view["byteLength"]])


def rig_state(data):
    """Skin joints + inverse bind matrices, image bytes, non-marker node transforms."""
    info, binary = parse(data)
    skins = []
    for skin in info.get("skins", []):
        ibm = info["accessors"][skin["inverseBindMatrices"]]
        skins.append(([info["nodes"][j]["name"] for j in skin["joints"]], view_bytes(info, binary, ibm["bufferView"])))
    images = [view_bytes(info, binary, image["bufferView"]) for image in info.get("images", [])]
    nodes = {n["name"]: tuple(json.dumps(n.get(f)) for f in ("translation", "rotation", "scale", "matrix", "mesh", "skin"))
             for n in info["nodes"] if not n["name"].endswith("_Att")}
    return skins, images, nodes


def marker_positions(data):
    from reparent_v31_approved_body_glb import world_matrices
    info, _ = parse(data)
    worlds, _ = world_matrices(info)
    return {n["name"]: worlds[i][:3, 3] for i, n in enumerate(info["nodes"]) if n["name"].endswith("_Att")}


def main():
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    original = subprocess.check_output(["git", "show", f"{TAG}:{PATH}"], cwd=ROOT)
    current = (ROOT / PATH).read_bytes()
    before, after = meshes(original), meshes(current)
    changed = [key for key in before.keys() | after.keys() if before.get(key) != after.get(key)]
    if changed:
        raise SystemExit(f"LOCK FAILED: {len(changed)} mesh attributes changed: {changed[:8]}")
    (s0, i0, n0), (s1, i1, n1) = rig_state(original), rig_state(current)
    if s0 != s1:
        raise SystemExit("LOCK FAILED: skin joints or inverse bind matrices changed")
    if i0 != i1:
        raise SystemExit("LOCK FAILED: embedded textures changed")
    moved = [k for k in n0.keys() | n1.keys() if n0.get(k) != n1.get(k)]
    if moved:
        raise SystemExit(f"LOCK FAILED: rig/mesh node transforms changed: {moved[:8]}")
    m0, m1 = marker_positions(original), marker_positions(current)
    off = {k: float(((m0[k] - m1[k]) ** 2).sum() ** 0.5) for k in m0 if k in m1}
    bad = {k: round(v, 4) for k, v in off.items() if v > 1e-3}
    if set(m0) != set(m1) or bad:
        raise SystemExit(f"LOCK FAILED: attachment markers moved or missing: {bad or set(m0) ^ set(m1)}")
    for path in PARTS:
        if subprocess.check_output(["git", "show", f"{TAG}:{path}"], cwd=ROOT) != (ROOT / path).read_bytes():
            raise SystemExit(f"LOCK FAILED: {path} differs from {TAG}")
    print(f"LOCK OK: {len(before)} body mesh attributes, {len(n0)} rig nodes, skin, {len(i0)} textures, "
          f"{len(m0)} marker positions and {len(PARTS)} part/texture files match {TAG}")

if __name__ == "__main__":
    main()
