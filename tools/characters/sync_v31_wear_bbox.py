"""Rewrite the BBOX table in tools/character_test/install_exit6_v31_wear.luau from the wear GLBs.

The Roblox importer bbox-centres every imported mesh, so the installer puts each one back at
LowerTorso.RootRigAttachment * (-x, z, y) using its Blender game-frame bbox centre. Those centres
change whenever build_exit6_wear_v31.py reshapes a garment; run this after every wear build:

    python tools/characters/sync_v31_wear_bbox.py [--check]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_v31_body_lock import parse  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WEAR = ROOT / "assets/characters/exit6_male/wear_v31"
INSTALLER = ROOT / "tools/character_test/install_exit6_v31_wear.luau"
ITEMS = {"Exit6_Puffer": "Exit6_Puffer", "Exit6_Cargo": "Exit6_Cargo", "Exit6_Sneakers": "Exit6_Sneakers",
         "Exit6_Briefs": "Exit6_Briefs", "Exit6_Chain": "Exit6_Jewelry", "Exit6_Chain_Over": "Exit6_Jewelry",
         "Exit6_Watch": "Exit6_Jewelry"}


def centre(glb, mesh_name):
    info, _ = parse((WEAR / f"{glb}.glb").read_bytes())
    for node in info["nodes"]:
        if node.get("name") != mesh_name or "mesh" not in node:
            continue
        lo, hi = [1e9] * 3, [-1e9] * 3
        for prim in info["meshes"][node["mesh"]]["primitives"]:
            acc = info["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
        t = node.get("translation", [0, 0, 0])
        c = [(a + b) / 2 + d for a, b, d in zip(lo, hi, t)]
        return c[0], -c[2], c[1]            # glTF Y-up -> Blender game frame (x, y, z)
    raise SystemExit(f"{mesh_name} not found in {glb}.glb")


def main():
    lines = []
    for name, glb in ITEMS.items():
        x, y, z = centre(glb, name)
        lines.append(f"\t{name} = Vector3.new({x:.4f}, {y:.4f}, {z:.4f}),")
    src = INSTALLER.read_text(encoding="utf8")
    pat = re.compile(r"(local BBOX = \{[^\n]*\n)(.*?)(\n\})", re.S)
    m = pat.search(src)
    assert m, "BBOX table not found"
    new = src[:m.start(2)] + "\n".join(lines) + src[m.end(2):]
    if "--check" in sys.argv:
        if new != src:
            raise SystemExit("BBOX table is stale: run python tools/characters/sync_v31_wear_bbox.py")
        print("BBOX table matches the wear GLBs")
        return
    INSTALLER.write_text(new, encoding="utf8", newline="\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
