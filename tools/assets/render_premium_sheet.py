"""Offline contact sheet of the EXIT 6 Premium meshes on the proxy R15 body.

Run: python tools/assets/render_premium_sheet.py -> build/premium_sheet.png,
     build/premium_detail.png
A painter's-algorithm geometry / fit check, not Studio QA. Like
render_wear_sheet.py the image is mirrored left-right (lettering reads
backwards here and correctly in Studio).
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_wearables as W  # noqa: E402
import build_premium as P  # noqa: E402
import render_wear_sheet as R  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BLACK, CHAR, WHITE, SILVER, ICE, HAIR = (26, 26, 30), (64, 64, 70), (236, 236, 232), (196, 200, 208), (222, 238, 250), (24, 18, 15)

FOUNDER = [("px_hair_long_locs", HAIR), ("px_loc_cuffs", SILVER), ("px_cap_crown", BLACK), ("px_cap_wordmark", SILVER),
           ("px_stud_stone", ICE), ("px_stud_setting", SILVER),
           ("px_puffer_body", BLACK), ("px_puffer_knit", BLACK), ("px_puffer_zip", SILVER), ("px_puffer_hood", CHAR),
           ("px_puffer_upper", BLACK), ("px_puffer_lower", BLACK), ("px_puffer_cuff", BLACK),
           ("px_cuban_chain", ICE), ("px_pendant_body", SILVER), ("px_pendant_face", ICE),
           ("px_watch_case", SILVER), ("px_watch_ice", ICE), ("px_watch_hands", SILVER),
           ("pants_waist", BLACK), ("px_cargo_upper", BLACK), ("px_cargo_snaps", SILVER), ("px_cargo_lower", BLACK),
           ("px_hightop_base", WHITE), ("px_hightop_overlay", BLACK), ("px_hightop_mark", BLACK),
           ("px_hightop_sole", WHITE), ("px_hightop_laces", WHITE)]
VIP = [("px_hair_designer_cornrows", HAIR), ("px_stud_stone", ICE), ("px_stud_setting", SILVER),
       ("px_track_jacket", BLACK), ("px_track_rib", BLACK), ("px_track_panels", SILVER), ("px_track_zip", SILVER),
       ("px_track_logo", SILVER), ("sleeve_upper", BLACK), ("sleeve_lower", BLACK), ("track_trim_upper", SILVER),
       ("track_trim_lower", SILVER), ("px_box_chain", SILVER), ("px_pendant_s_body", SILVER), ("px_pendant_s_face", SILVER),
       ("pants_waist", BLACK), ("pants_upper", BLACK), ("jogger_lower", BLACK), ("leg_trim_upper", SILVER),
       ("leg_trim_lower", SILVER), ("px_hightop_base", BLACK), ("px_hightop_overlay", BLACK), ("px_hightop_mark", SILVER),
       ("px_hightop_sole", BLACK), ("px_hightop_laces", BLACK)]


def items_for(pieces, base, only=None):
    items = [(R.place(m, n), m.f, col, 255) for m, n, col in base if only is None or n in only]
    for name, col in pieces:
        m = R.MESH[name]
        for t in R.targets(m):
            if only is None or t in only:
                items.append((R.place(m, t), m.f, col, 255))
    return items


def main():
    W.build_hair(); W.build_tops(); W.build_bottoms(); W.build_shoes(); W.build_hats(); W.build_jewelry()
    P.build_all()
    R.MESH = {m.name: m for m in W.MESHES + P.MESHES}
    base = R.body()
    out = ROOT / "build"
    out.mkdir(exist_ok=True)
    tiles = []
    for look in (FOUNDER, VIP):
        for yaw in (0.0, math.radians(35), math.radians(90), math.pi):
            tiles.append(R.render(items_for(look, base), yaw, size=320, scale=50))
    sheet = Image.new("RGB", (320 * 4, tiles[0].size[1] * 2), (20, 20, 24))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 4) * 320, (i // 4) * t.size[1]))
    sheet.save(out / "premium_sheet.png")

    det = []
    head = {"Head", "UpperTorso"}
    for look, yaw in ((FOUNDER, 0.0), (FOUNDER, math.radians(140)), (VIP, 0.0), (VIP, math.radians(150))):
        det.append(R.render(items_for([pc for pc in look if R.MESH[pc[0]].part == "Head"], base, head), yaw,
                            size=260, scale=95, centre_y=1.25))
    det.append(R.render(items_for([pc for pc in FOUNDER if pc[0].startswith(("px_cuban", "px_pendant"))], base, {"UpperTorso"}),
                        0.0, size=260, scale=170, centre_y=0.62))
    det.append(R.render(items_for([pc for pc in VIP if pc[0].startswith(("px_box", "px_pendant_s"))], base, {"UpperTorso"}),
                        0.0, size=260, scale=170, centre_y=0.62))
    shoe = [pc for pc in FOUNDER if pc[0].startswith("px_hightop")]
    for yaw in (math.radians(90), math.radians(-60)):
        det.append(R.render(items_for(shoe, base, {"RightFoot", "RightLowerLeg"}), yaw, size=260, scale=120, centre_y=-2.7))
    watch = [pc for pc in FOUNDER if pc[0].startswith("px_watch")]
    det.append(R.render(items_for(watch, base, {"LeftLowerArm", "LeftHand"}), math.radians(-90), size=260, scale=200,
                        centre_y=-0.55))
    cols = 5
    rows = math.ceil(len(det) / cols)
    ds = Image.new("RGB", (260 * cols, det[0].size[1] * rows), (20, 20, 24))
    for i, t in enumerate(det):
        ds.paste(t, ((i % cols) * 260, (i // cols) * t.size[1]))
    ds.save(out / "premium_detail.png")
    print("wrote build/premium_sheet.png and build/premium_detail.png")


if __name__ == "__main__":
    main()
