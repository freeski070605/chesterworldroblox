"""Side-by-side review sheets for V3: reference crop | V3 renders at the same angle and scale.

    python tools/characters/compose_review_v3.py

Inputs: renders_v3/review_*.png (render_review_v3.py), renders_v2/face_v2_*.png.
Outputs (renders_v3/): sheet_face_v3.png, sheet_body_v3.png, sheet_closeups_v3.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
REF = Image.open(os.path.join(REPO, "assets", "characters", "reference", "male_body_turnaround.png")).convert("RGB")
D = os.path.join(REPO, "assets", "characters", "exit6_male")
R3 = os.path.join(D, "renders_v3")
BG = (232, 226, 235)
FONT = ImageFont.truetype("arial.ttf", 26)


def load(path, size=None):
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, BG + (255,))
    im = Image.alpha_composite(bg, im).convert("RGB")
    return im.resize(size, Image.LANCZOS) if size else im


def ref_crop(x0, y0, x1, y1, size):
    c = Image.new("RGB", (x1 - x0, y1 - y0), BG)
    sx0, sx1 = max(x0, 0), min(x1, REF.width)
    c.paste(REF.crop((sx0, y0, sx1, y1)), (sx0 - x0, 0))
    return c.resize(size, Image.LANCZOS)


def sheet(rows, out, gap=14):
    """rows: [(row_label, [(label, image), ...])]"""
    W = max(sum(im.width for _, im in cells) + gap * (len(cells) - 1) for _, cells in rows)
    H = sum(max(im.height for _, im in cells) + 40 for _, cells in rows) + gap * (len(rows) - 1)
    sh = Image.new("RGB", (W, H), (255, 255, 255))
    dr = ImageDraw.Draw(sh)
    y = 0
    for rl, cells in rows:
        x = 0
        for lab, im in cells:
            dr.text((x + 6, y + 6), "%s - %s" % (rl, lab), fill=(20, 20, 20), font=FONT)
            sh.paste(im, (x, y + 40))
            x += im.width + gap
        y += max(im.height for _, im in cells) + 40 + gap
    sh.save(out)
    print(out, sh.size)


# ---------------------------------------------------------------- face
FACE = {"front": (106, 226), "three_quarter": (380, 530), "side": (630, 760)}
rows = []
for v, (x0, x1) in FACE.items():
    size = ((x1 - x0) * 6, 154 * 6)
    rows.append((v.replace("_", " "), [
        ("reference", ref_crop(x0, 196, x1, 350, size)),
        ("V2 (rejected)", load(os.path.join(D, "renders_v2", "face_v2_%s.png" % v), size)),
        ("V3", load(os.path.join(R3, "review_face_%s.png" % v), size)),
        ("V3 no hair", load(os.path.join(R3, "review_face_bare_%s.png" % v), size)),
        ("V3 clay", load(os.path.join(R3, "review_face_clay_%s.png" % v), size)),
    ]))
sheet(rows, os.path.join(R3, "sheet_face_v3.png"))

# ---------------------------------------------------------------- body
def body(path, size):
    """render_views framing (rows 0..1402, centre column 300) at 2x -> crop rows 180..1175, cols 150..450"""
    im = load(path)
    f = im.width / 600
    return im.crop((int(150 * f), int(180 * f), int(450 * f), int(1175 * f))).resize(size, Image.LANCZOS)


BODY = {"front": 166, "three_quarter": 462, "side": 700}
rows = []
for v, cx in BODY.items():
    size = (600, 1990)
    rows.append((v.replace("_", " "), [
        ("reference", ref_crop(cx - 150, 180, cx + 150, 1175, size)),
        ("V3", body(os.path.join(R3, "review_body_%s.png" % v), size)),
        ("V3 clay", body(os.path.join(R3, "review_body_clay_%s.png" % v), size)),
    ]))
# one row: put the three views side by side
cells = []
for rl, c in rows:
    cells += [("%s %s" % (rl, lab), im) for lab, im in c]
sheet([("body", cells[:6]), ("body", cells[6:])], os.path.join(R3, "sheet_body_v3.png"))

# ------------------------------------------------------------- close-ups
def pair(name, ref_box, render, scale):
    x0, y0, x1, y1 = ref_box
    size = ((x1 - x0) * scale, (y1 - y0) * scale)
    return [("reference", ref_crop(x0, y0, x1, y1, size)), ("V3", load(os.path.join(R3, render), size))]


sheet([
    ("torso front", pair("tf", (16, 380, 316, 720), "review_torso_front.png", 3)),
    ("torso 3/4", pair("t3", (312, 380, 612, 720), "review_torso_three_quarter.png", 3)),
], os.path.join(R3, "sheet_torso_v3.png"))
sheet([
    ("arm", pair("arm", (11, 400, 101, 700), "review_arm_front.png", 4)),
    ("hand", pair("hand", (-9, 640, 81, 800), "review_hand_front.png", 6)),
    ("hair back 3/4", [("reference back", ref_crop(889, 196, 1039, 350, (900, 924))),
                       ("V3", load(os.path.join(R3, "review_hair_back34.png"), (960, 924)))]),
], os.path.join(R3, "sheet_limbs_hair_v3.png"))
sheet([("legs", pair("legs", (46, 700, 286, 1140), "review_legs_front.png", 3))],
      os.path.join(R3, "sheet_legs_v3.png"))
