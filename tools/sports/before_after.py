"""Before/after overlays of the reconstructed facilities on DVRPC 2025.

    python -m tools.sports.before_after

Red = geometry the builder used before (commit bbb7a05/8171cf5), green/yellow =
reconstructed geometry from src/shared/Exit6VerifiedSports.luau.
Writes build/sports_reference/before_after_*.jpg.
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

from tools.sports.overlay import Sheet, box_corners, local_to_world

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "sports_reference"


def oval(cx, cz, yaw, half, r, n=24):
    pts = []
    for e in (1, -1):
        for i in range(n + 1):
            a = -math.pi / 2 + i * math.pi / n
            pts.append(local_to_world(cx, cz, yaw, e * (half + r * math.cos(a)), e * r * math.sin(a)))
    return pts


def panel(title, cx, cz, half, ppx, draw_fn):
    s = Sheet(cx, cz, half, ppx, enhance=1.25)
    draw_fn(s)
    d = ImageDraw.Draw(s.img)
    d.rectangle((0, 0, s.img.width, 18), fill="black")
    d.text((4, 3), title, fill="white")
    return s.img


def hoops(s, box, color):
    L = box[2]
    rim = 45 * (L / 2 - 0.3) / 49
    for e in (1, -1):
        s.dot(*local_to_world(box[0], box[1], box[4], e * rim, 0), color, 4)


def memorial():
    old_field = (-3700, 5950, 390, 165, 12)
    new_field = (-3586, 6081, 428.5, 190.6, 124.2)
    courts = [(-3437.8, 5798.5, 99.5, 59.3, 124.1), (-3378.8, 5758.4, 99.5, 59.3, 124.1)]
    pad = (-3406.2, 5776.9, 159.1, 122.2, 33.7)
    poles = [(-3552, 5931), (-3739, 6056), (-3433, 6106), (-3621, 6231)]

    def before(s):
        s.box(old_field, "red", 3)
        for c in courts:
            s.box(c, "red", 2)
            # old hoops: mesh centred at L/2-1 and turned to face outward
            for e in (1, -1):
                s.dot(*local_to_world(c[0], c[1], c[4], e * (c[2] / 2 - 1), 0), "red", 4)

    def after(s):
        s.box(new_field, "lime", 3)
        s.box(pad, "yellow", 2)
        for c in courts:
            s.box(c, "lime", 2)
            hoops(s, c, "orange")
        for p in poles:
            s.dot(*p, "cyan", 6)
        s.poly([(-3730, 5885), (-3825, 5960), (-3767, 6070)], "magenta", 2, closed=False)

    a = panel("BEFORE  Memorial Park: field yaw 12 at fence corner; hoops at L/2-1 facing out", -3560, 5990, 330, 1.4, before)
    b = panel("AFTER  field yaw 124.2 on lit rectangle (cyan poles); pad + inward hoops", -3560, 5990, 330, 1.4, after)
    out = Image.new("RGB", (a.width * 2 + 10, a.height), "white")
    out.paste(a, (0, 0)); out.paste(b, (a.width + 10, 0))
    out.save(OUT / "before_after_memorial.jpg", quality=90)

    def court_detail(s):
        s.box(pad, "yellow", 2)
        for c in courts:
            s.box(c, "lime", 1)
            hoops(s, c, "orange")
    panel("AFTER  Memorial courts: rims (orange) on painted arcs", -3408, 5778, 95, 5, court_detail).save(
        OUT / "after_memorial_courts.jpg", quality=90)


def afield():
    old = (17.3, 1541.6, 429.6, 190.9, -83.3)
    field = (13.27, 1543.96, 431.4, 191.7, -83.86)
    c, yaw = (13.4, 1545.2), -83.86

    def before(s):
        s.box(old, "red", 3)
        # old track mesh 560x260 * (1, 1.1) centred on the football box
        s.poly(oval(old[0], old[1], old[4], 150, 130 * 1.1), "red", 2)
        s.poly(oval(old[0], old[1], old[4], 150, 94 * 1.1), "red", 2)

    def after(s):
        s.box(field, "lime", 3)
        s.poly(oval(*c, yaw, 193.5, 124.5), "yellow", 2)
        s.poly(oval(*c, yaw, 193.5, 154.5), "yellow", 2)
        chute = [local_to_world(*c, yaw, x, z) for x, z in ((-193.5, 124.5), (-303, 124.5), (-303, 154.5), (-193.5, 154.5))]
        s.poly(chute, "yellow", 2)
        for x, z, L, W in ((-178.4, 1563.0, 286, 47), (187.9, 1529.0, 203, 24)):
            s.box((x, z, L, W, yaw), "cyan", 2)
        for yd in range(-50, 51, 10):
            u = yd * 3.596
            s.poly([local_to_world(*field[:2], yaw, u, -95), local_to_world(*field[:2], yaw, u, 95)], "white", 1, closed=False)

    a = panel("BEFORE  A Field: OSM box + stretched 560x260 oval mesh", 20, 1545, 400, 1.0, before)
    b = panel("AFTER  measured infield/outer kerbs, chute, field on yard lines, stands", 20, 1545, 400, 1.0, after)
    out = Image.new("RGB", (a.width * 2 + 10, a.height), "white")
    out.paste(a, (0, 0)); out.paste(b, (a.width + 10, 0))
    out.save(OUT / "before_after_afield.jpg", quality=90)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    memorial()
    afield()
    print("written", OUT)
