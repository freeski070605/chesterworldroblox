"""Face close-up comparison: reference | v1 | v2 at identical camera angle and scale.

    python tools/characters/compose_face_v2.py [prefix=face_v2] [out=renders_v2/compare_face.png]

The v2 close-ups come from build_exit6_male_v2.py (render_face), framed on
the same reference-pixel windows as the reference crops; v1 crops are cut
from the v1 full-body renders (same ortho scale, 600 px wide, x=0 at 300).
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
REF = os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")
D = os.path.join(REPO, "assets", "characters", "exit6_male")
CROPS = {"front": (106, 196, 226, 350), "three_quarter": (380, 196, 530, 350), "side": (630, 196, 760, 350)}
# v1 full-body render x of the crop's left edge (render centre 300 = panel centre)
V1_X0 = {"front": 300 - 60, "three_quarter": None, "side": 300 - 70}
SC = 4
BG = (232, 226, 235)


def on_bg(im):
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, BG + (255,))
    return Image.alpha_composite(bg, im).convert("RGB")


def main(prefix="face_v2", out=None):
    ref = Image.open(REF).convert("RGB")
    font = ImageFont.truetype("arial.ttf", 22) if os.name == "nt" else None
    cols = []
    for view, (x0, y0, x1, y1) in CROPS.items():
        w, h = (x1 - x0) * SC, (y1 - y0) * SC
        r = ref.crop((x0, y0, x1, y1)).resize((w, h), Image.LANCZOS)
        v1p = os.path.join(D, "renders", "render_%s.png" % view)
        if view == "three_quarter":
            # v1 3/4 render: head centred like the v2 framing
            im = Image.open(v1p)
            bbox = im.split()[-1].crop((0, y0, im.width, 300)).getbbox()
            cx = (bbox[0] + bbox[2]) // 2
            v1 = on_bg(im.crop((cx - (x1 - x0) // 2, y0, cx + (x1 - x0) // 2, y1))).resize((w, h), Image.LANCZOS)
        else:
            v1 = on_bg(Image.open(v1p).crop((V1_X0[view], y0, V1_X0[view] + x1 - x0, y1))).resize((w, h), Image.LANCZOS)
        v2 = on_bg(Image.open(os.path.join(D, "renders_v2", "%s_%s.png" % (prefix, view)))).resize((w, h), Image.LANCZOS)
        cols.append((view, r, v1, v2))
    W = sum(c[1].width for c in cols) + 20 * (len(cols) - 1)
    H = sum(cols[0][1].height for _ in range(3)) + 3 * 34
    sheet = Image.new("RGB", (W, H), (255, 255, 255))
    dr = ImageDraw.Draw(sheet)
    x = 0
    for view, r, v1, v2 in cols:
        y = 0
        for lab, im in (("reference", r), ("v1", v1), ("v2", v2)):
            dr.text((x + 6, y + 6), "%s  %s" % (view, lab), fill=(20, 20, 20), font=font)
            sheet.paste(im, (x, y + 34))
            y += im.height + 34
        x += r.width + 20
    out = out or os.path.join(D, "renders_v2", "compare_face.png")
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main(*sys.argv[1:])
