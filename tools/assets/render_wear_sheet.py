"""Offline contact sheet of EXIT 6 wearables on a proxy R15 body.

Run: python tools/assets/render_wear_sheet.py  ->  build/wear_sheet.png
Painter's-algorithm flat render; a geometry/fit check, not Studio QA.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_wearables as W  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

# root-space centres of the default R15 parts (Studio measurement)
LAYOUT = {
    "Head": (0, 1.586, 0), "UpperTorso": (0, 0.2, 0), "LowerTorso": (0, -0.8, 0),
    "RightUpperArm": (1.5, 0.369, 0), "RightLowerArm": (1.5, -0.224, 0), "RightHand": (1.5, -0.85, 0),
    "LeftUpperArm": (-1.5, 0.369, 0), "LeftLowerArm": (-1.5, -0.224, 0), "LeftHand": (-1.5, -0.85, 0),
    "RightUpperLeg": (0.5, -1.421, 0), "RightLowerLeg": (0.5, -2.201, 0), "RightFoot": (0.5, -2.85, 0),
    "LeftUpperLeg": (-0.5, -1.421, 0), "LeftLowerLeg": (-0.5, -2.201, 0), "LeftFoot": (-0.5, -2.85, 0),
}
SIZES = dict(W.CANON)
SIZES["Hand"] = (0.984, 0.316, 1.028)
SKIN = (128, 88, 64)


def body():
    """Proxy body parts as (mesh, colour)."""
    parts = []
    for name, c in LAYOUT.items():
        key = name.replace("Left", "").replace("Right", "")
        sz = SIZES[key]
        m = W.Mesh(name, name)
        if key == "Head":
            W.head_cap(m, lambda az: -0.55, lambda az, v: 0.0, rows=12, rim=False)
            W.rounded_box(m, (0, -0.25, 0), (0.56, 0.32, 0.56), 0.2)
        else:
            W.rounded_box(m, (0, 0, 0), tuple(s / 2 for s in sz), 0.1, n_mid=2, n_r=2)
        parts.append((m, name, SKIN))
    return parts


def place(mesh, part_name):
    c = LAYOUT[part_name]
    generic = mesh.part in ("UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot")
    turn = generic and part_name.startswith("Left") and mesh.part != "Foot"
    out = []
    for p in mesh.v:
        q = W.rot_y(p, math.pi) if turn else p
        out.append((q[0] + c[0], q[1] + c[1], q[2] + c[2]))
    return out


def targets(mesh):
    if mesh.part in ("UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot"):
        return ["Left" + mesh.part, "Right" + mesh.part]
    return [mesh.part]


def render(items, yaw, size=300, scale=48, centre_y=-0.4, alpha_parts=()):
    img = Image.new("RGB", (size, int(size * 1.45)), (34, 36, 42))
    dr = ImageDraw.Draw(img, "RGBA")
    light = W.norm((-0.4, 0.8, -0.6))
    tris = []
    for verts, faces, col, alpha in items:
        rv = [W.rot_y(p, yaw) for p in verts]
        for a, b, c in faces:
            pa, pb, pc = rv[a], rv[b], rv[c]
            n = W.cross(W.sub(pb, pa), W.sub(pc, pa))
            if n[2] > 0:  # camera looks along +Z from -Z; keep faces pointing at it
                continue
            n = W.norm(n)
            shade = 0.35 + 0.65 * max(0.0, W.dot(n, light))
            depth = (pa[2] + pb[2] + pc[2]) / 3
            tris.append((depth, pa, pb, pc, tuple(int(ch * shade) for ch in col), alpha))
    tris.sort(key=lambda t: -t[0])
    h = img.size[1]
    for _, pa, pb, pc, col, alpha in tris:
        pts = [(size / 2 + p[0] * scale, h / 2 - (p[1] - centre_y) * scale) for p in (pa, pb, pc)]
        dr.polygon(pts, fill=col + (alpha,))
    return img


def outfit(pieces, base):
    items = [(place(m, n), m.f, col, 255) for m, n, col in base]
    for name, col, alpha in pieces:
        m = MESH[name]
        for t in targets(m):
            items.append((place(m, t), m.f, col, alpha))
    return items


BLACK, WHITE, GREY, NAVY, RED, GOLD = (28, 28, 32), (236, 236, 232), (130, 130, 136), (30, 40, 72), (170, 28, 36), (212, 175, 70)
HAIR = (24, 18, 15)
LOOKS = {
    "locs hoodie": [("hair_medium_locs", HAIR, 255), ("hoodie_torso", BLACK, 255), ("sleeve_upper", BLACK, 255),
                    ("sleeve_lower", BLACK, 255), ("pants_waist", GREY, 255), ("pants_upper", GREY, 255),
                    ("jogger_lower", GREY, 255), ("sneaker_upper", WHITE, 255), ("sneaker_sole", WHITE, 255),
                    ("chain_cuban", GOLD, 255), ("pendant_six", GOLD, 255)],
    "cap tee boots": [("hair_medium_locs", HAIR, 255), ("cap_fitted", RED, 255), ("cap_emblem", WHITE, 255),
                      ("tee_torso", WHITE, 255), ("tee_sleeve", WHITE, 255), ("pants_waist", NAVY, 255),
                      ("pants_upper", NAVY, 255), ("jeans_stacked_lower", NAVY, 255), ("boot_upper", (196, 150, 80), 255),
                      ("boot_sole", (60, 40, 30), 255), ("shades_frame", BLACK, 255), ("shades_lens", (20, 20, 24), 255),
                      ("chain_rope", GOLD, 255)],
    "track bun": [("hair_high_bun", HAIR, 255), ("earring_hoops", GOLD, 255), ("track_torso", GREY, 255),
                  ("track_trim_torso", WHITE, 255), ("sleeve_upper", GREY, 255), ("sleeve_lower", GREY, 255),
                  ("track_trim_upper", WHITE, 255), ("track_trim_lower", WHITE, 255), ("pants_waist", BLACK, 255),
                  ("pants_upper", BLACK, 255), ("jogger_lower", BLACK, 255), ("leg_trim_upper", WHITE, 255),
                  ("leg_trim_lower", WHITE, 255), ("sneaker_upper", WHITE, 255), ("sneaker_sole", WHITE, 255)],
    "puffer beanie": [("beanie", BLACK, 255), ("puffer_torso", (40, 44, 50), 255), ("puffer_upper", (40, 44, 50), 255),
                      ("puffer_lower", (40, 44, 50), 255), ("pants_waist", NAVY, 255), ("pants_upper", NAVY, 255),
                      ("jeans_stacked_lower", NAVY, 255), ("boot_upper", (196, 150, 80), 255),
                      ("boot_sole", (60, 40, 30), 255), ("watch_case", GOLD, 255), ("watch_dial", (180, 220, 240), 255)],
    "afro shorts": [("hair_afro_taper", HAIR, 255), ("fade_afro", HAIR, 120), ("tee_torso", RED, 255), ("tee_sleeve", RED, 255),
                    ("pants_waist", BLACK, 255), ("shorts_upper", BLACK, 255), ("sneaker_upper", BLACK, 255),
                    ("sneaker_sole", WHITE, 255), ("headphones_neck", WHITE, 255), ("bracelet_cuban", GOLD, 255)],
}
HAIRS = ["hair_sharp_low_taper", "hair_mid_skin_fade", "hair_high_top_fade", "hair_waves_360", "hair_afro_taper",
         "hair_starter_locs", "hair_medium_locs", "hair_shoulder_locs", "hair_two_strand_twists", "hair_cornrows",
         "hair_box_braids", "hair_braided_ponytail", "hair_high_bun", "hair_space_buns", "hair_long_silk_press",
         "durag", "ski_mask", "cap_fitted", "beanie", "shades_frame", "earring_studs"]


def main():
    W.build_hair(); W.build_tops(); W.build_bottoms(); W.build_shoes(); W.build_hats(); W.build_jewelry()
    global MESH
    MESH = {m.name: m for m in W.MESHES}
    base = body()
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    tiles = []
    for name, pieces in LOOKS.items():
        for yaw in (0.0, math.radians(90), math.pi):
            tiles.append(render(outfit(pieces, base), yaw))
    sheet = Image.new("RGB", (300 * 6, tiles[0].size[1] * 3), (20, 20, 24))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 6) * 300, (i // 6) * t.size[1]))
    sheet.save(out / "wear_sheet.png")
    # head close-ups
    head_base = [b for b in base if b[1] in ("Head", "UpperTorso")]
    heads = []
    for n in HAIRS:
        for yaw in (0.0, math.radians(120)):
            items = [(place(m, nm), m.f, col, 255) for m, nm, col in head_base]
            m = MESH[n]
            items.append((place(m, "Head"), m.f, HAIR if n.startswith("hair") else RED, 255))
            heads.append(render(items, yaw, size=200, scale=70, centre_y=1.35))
    cols = 8
    rows = math.ceil(len(heads) / cols)
    hs = Image.new("RGB", (200 * cols, heads[0].size[1] * rows), (20, 20, 24))
    for i, t in enumerate(heads):
        hs.paste(t, ((i % cols) * 200, (i // cols) * t.size[1]))
    hs.save(out / "wear_heads.png")
    print("wrote build/wear_sheet.png and build/wear_heads.png")


if __name__ == "__main__":
    main()
