"""Face review sheet: reference | V3 skin | V3 bare | V3 clay, rows front / three-quarter / side.

    python tools/characters/compose_face_v3.py [tag] [out] [--with-v2]
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
REF = os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")
D = os.path.join(REPO, "assets", "characters", "exit6_male")
CROPS = {"front": (106, 196, 226, 350), "three_quarter": (380, 196, 530, 350), "side": (630, 196, 760, 350)}
BG = (232, 226, 235)


def on_bg(im):
    im = im.convert("RGBA")
    bg = Image.new("RGBA", im.size, BG + (255,))
    return Image.alpha_composite(bg, im).convert("RGB")


def main(tag="", out=None, with_v2=False, sc=4):
    ref = Image.open(REF).convert("RGB")
    font = ImageFont.truetype("arial.ttf", 20)
    rows = []
    for view, (x0, y0, x1, y1) in CROPS.items():
        w, h = (x1 - x0) * sc, (y1 - y0) * sc
        cells = [("reference", ref.crop((x0, y0, x1, y1)).resize((w, h), Image.LANCZOS))]
        if with_v2:
            cells.append(("V2", on_bg(Image.open(os.path.join(D, "renders_v2", "face_v2_%s.png" % view))).resize((w, h), Image.LANCZOS)))
        for lab, pre in (("V3", "face_v3%s" % tag), ("V3 no hair", "face_v3%s_bare" % tag), ("V3 clay", "face_v3%s_clay" % tag)):
            pth = os.path.join(D, "renders_v3", "%s_%s.png" % (pre, view))
            if os.path.exists(pth):
                cells.append((lab, on_bg(Image.open(pth)).resize((w, h), Image.LANCZOS)))
        rows.append((view, cells))
    W = max(sum(c.width for _, c in cells) + 12 * (len(cells) - 1) for _, cells in rows)
    H = sum(cells[0][1].height + 30 for _, cells in rows) + 12 * (len(rows) - 1)
    sheet = Image.new("RGB", (W, H), (255, 255, 255))
    dr = ImageDraw.Draw(sheet)
    y = 0
    for view, cells in rows:
        x = 0
        for lab, im in cells:
            dr.text((x + 4, y + 4), "%s - %s" % (view.replace("_", " "), lab), fill=(20, 20, 20), font=font)
            sheet.paste(im, (x, y + 30))
            x += im.width + 12
        y += cells[0][1].height + 30 + 12
    out = out or os.path.join(REPO, "build", "exit6_v3", "face_review%s.png" % tag)
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    main(*a, with_v2="--with-v2" in sys.argv)
