"""Draw Exit 6 Motors' in-game footprints (exported from a Studio Play server:
dealer parts, display rides, roads, sidewalks, building 93584 and its doors)
over the DVRPC 2025 orthophoto rendered by intersection_aerial.py
(build/aerial/js_lot_93584.png, centre studs (2960, 1630), half 75 m).
usage: python dealer_overlay.py footprints.json out.png"""
import json, sys
from PIL import Image, ImageDraw
rows = json.load(open(sys.argv[1]))
img = Image.open("build/aerial/js_lot_93584.png").convert("RGB")
over = Image.new("RGBA", img.size, (0, 0, 0, 0))
d = ImageDraw.Draw(over)
S = 1600 / 150 / 3   # px per stud
def px(x, z): return (800 + (x - 2960) * S, 600 + (z - 1630) * S)
style = {"Roads": ((80, 80, 255, 60), (80, 80, 255, 200)), "Sidewalks": ((200, 200, 200, 90), (230, 230, 230, 220)),
         "building": ((255, 220, 0, 40), (255, 220, 0, 255)), "door": ((0, 255, 0, 255), (0, 255, 0, 255)),
         "dealer": ((255, 120, 0, 110), (255, 140, 0, 255)), "display": ((255, 0, 200, 150), (255, 0, 200, 255)),
         "Intersection": ((80, 80, 255, 50), (80, 80, 255, 160))}
for kind in ["Roads", "Intersection", "Sidewalks", "building", "dealer", "display", "door"]:
    for r in rows:
        if r["k"] != kind: continue
        pts = [px(*c) for c in r["c"]]
        fill, line = style[kind]
        d.polygon(pts, fill=fill, outline=line)
img = Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")
d = ImageDraw.Draw(img)
for name, (x, z) in {"EXIT 6 MOTORS pad (bikes/quads)": (2878, 1552), "car row": (2901, 1571), "office": (2894, 1604),
                     "W 9th / Kerlin node": (2849, 1489), "Concord Ave": (2990, 1548), "Kerlin St": (2852, 1600),
                     "Boost": (2927, 1645), "J&S": (2972, 1630), "5 Points": (3030, 1640)}.items():
    p = px(x, z); d.text((p[0] + 4, p[1] - 6), name, fill=(255, 255, 255))
# facing arrow: bearing 335 from the pad centre
import math
p0 = px(2878, 1552); b = math.radians(335)
p1 = px(2878 + 40 * math.sin(b), 1552 - 40 * math.cos(b))
d.line([p0, p1], fill=(255, 0, 0), width=4); d.ellipse([p1[0] - 6, p1[1] - 6, p1[0] + 6, p1[1] + 6], fill=(255, 0, 0))
img.save(sys.argv[2]); print("wrote", sys.argv[2])
