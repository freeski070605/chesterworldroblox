"""Offline geometry contact sheet. Not a substitute for Studio R15 QA."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from build_hair import Mesh, STYLES, OUT
import math

SIZE = 260
SCALE = 86


def head_mesh():
    m = Mesh("head")
    rings = []
    for j in range(1, 16):
        t = math.pi * j / 16
        ring = []
        for i in range(32):
            a = math.tau * i / 32
            ring.append(m.v((.96 * math.sin(t) * math.cos(a),
                             .50 * math.cos(t), .50 * math.sin(t) * math.sin(a))))
        rings.append(ring)
    m.grid(rings)
    return m


HEAD = head_mesh()


def projected(p, view):
    x, y, z = p
    if view == "front":
        return x, y, -z
    if view == "side":
        return z, y, x
    return -x, y, z


def render(mesh, view):
    im = Image.new("RGB", (SIZE, SIZE), (223, 225, 226))
    draw = ImageDraw.Draw(im)
    polys = []
    for obj, base in ((HEAD, (126, 86, 61)), (mesh, (23, 19, 17))):
        for face in obj.faces:
            pts = [projected(obj.vertices[i - 1], view) for i in face]
            depth = sum(p[2] for p in pts) / 3
            a, b, c = pts
            light = .82 + .18 * abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
            color = tuple(min(255, int(v * light)) for v in base)
            pixel = [(SIZE / 2 + p[0] * SCALE, SIZE * .55 - p[1] * SCALE) for p in pts]
            polys.append((depth, pixel, color))
    for _, pixel, color in sorted(polys, reverse=True):
        draw.polygon(pixel, fill=color)
    return im


def main():
    sheet = Image.new("RGB", (SIZE * 3, (SIZE + 30) * len(STYLES)), "white")
    d = ImageDraw.Draw(sheet)
    for row, (name, build) in enumerate(STYLES.items()):
        m = Mesh(name)
        build(m)
        for col, view in enumerate(("front", "side", "rear")):
            sheet.paste(render(m, view), (col * SIZE, row * (SIZE + 30) + 30))
            d.text((col * SIZE + 8, row * (SIZE + 30) + 8),
                   f"{name} / {view}", fill="black")
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / "offline_contact_sheet.png")
    print(OUT / "offline_contact_sheet.png")


if __name__ == "__main__":
    main()
