"""Re-parent the approved V3.1 body GLB's _Att markers from their part meshes to the R15 bones.

Roblox's importer puts mesh-parented markers on HumanoidRootPart, so the markers must hang off the
bones. This edits only the glTF JSON of the approved file (tag exit6-male-v3.1-approved): each marker
keeps its approved world transform, the BIN chunk (meshes, skin, textures) is copied byte for byte.
Local transforms are derived from the approved file itself, never from a fresh export (an export bug
once put FaceCenter_Att on the rig origin; see export_exit6_male_v31.py).

    python tools/characters/reparent_v31_approved_body_glb.py   # writes both GLB copies
"""
import json
import struct
import subprocess
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
PATH = "assets/characters/exit6_male/Exit6_Male_V3_1_Body.glb"
COPIES = [PATH, "assets/wear/exit6_male_v31/Exit6_Male_V3_1_Body.glb"]
TAG = "exit6-male-v3.1-approved"
TRANSFORMS = ("translation", "rotation", "scale", "matrix")


def parse(data):
    assert data[:4] == b"glTF"
    json_size, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A
    return json.loads(data[20:20 + json_size]), data[20 + json_size:]


def local_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    rot = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                    [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                    [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = rot * np.array(node.get("scale", [1, 1, 1]))
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


def world_matrices(info):
    parent = {c: i for i, n in enumerate(info["nodes"]) for c in n.get("children", [])}
    out = []
    for i in range(len(info["nodes"])):
        m, j = local_matrix(info["nodes"][i]), i
        while j in parent:
            j = parent[j]
            m = local_matrix(info["nodes"][j]) @ m
        out.append(m)
    return out, parent


def to_trs(m):
    scale = np.linalg.norm(m[:3, :3], axis=0)
    r = m[:3, :3] / scale
    w = np.sqrt(max(0.0, 1 + r[0, 0] + r[1, 1] + r[2, 2])) / 2
    x = np.copysign(np.sqrt(max(0.0, 1 + r[0, 0] - r[1, 1] - r[2, 2])) / 2, r[2, 1] - r[1, 2])
    y = np.copysign(np.sqrt(max(0.0, 1 - r[0, 0] + r[1, 1] - r[2, 2])) / 2, r[0, 2] - r[2, 0])
    z = np.copysign(np.sqrt(max(0.0, 1 - r[0, 0] - r[1, 1] + r[2, 2])) / 2, r[1, 0] - r[0, 1])
    q = np.array([x, y, z, w]) / np.linalg.norm([x, y, z, w])
    return {"translation": [float(v) for v in m[:3, 3]], "rotation": [float(v) for v in q],
            "scale": [float(v) for v in scale]}


def main():
    approved = subprocess.check_output(["git", "show", f"{TAG}:{PATH}"], cwd=ROOT)
    info, original_bin = parse(approved)
    names = {n["name"]: i for i, n in enumerate(info["nodes"]) if "name" in n}
    worlds, parent = world_matrices(info)
    attachments = [n for n in names if n.endswith("_Att")]
    assert len(attachments) == 19, "approved body attachment count changed"
    for name in attachments:
        idx = names[name]
        part = info["nodes"][parent[idx]]["name"]
        assert part.endswith("_Geo"), (name, part)
        bone = names[part[:-4]]
        local = np.linalg.inv(worlds[bone]) @ worlds[idx]
        info["nodes"][parent[idx]]["children"].remove(idx)
        info["nodes"][bone].setdefault("children", []).append(idx)
        node = info["nodes"][idx]
        for field in TRANSFORMS:
            node.pop(field, None)
        node.update(to_trs(local))
    # check: every marker keeps its approved world transform
    new_worlds, _ = world_matrices(info)
    for name in attachments:
        err = np.abs(new_worlds[names[name]] - worlds[names[name]]).max()
        assert err < 1e-4, f"{name} moved by {err}"
    payload = json.dumps(info, separators=(",", ":"), ensure_ascii=False).encode("utf8")
    payload += b" " * (-len(payload) % 4)
    json_chunk = struct.pack("<II", len(payload), 0x4E4F534A) + payload
    result = b"glTF" + struct.pack("<II", 2, 12 + len(json_chunk) + len(original_bin))
    for copy in COPIES:
        (ROOT / copy).write_bytes(result + json_chunk + original_bin)
    print(f"Reparented {len(attachments)} attachments to bones; world transforms within 1e-4; "
          f"approved BIN chunk preserved byte for byte -> {len(COPIES)} files")


if __name__ == "__main__":
    main()
