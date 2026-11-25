"""Gridded crop of the reference turnaround in reference-pixel coords (X = col - cx, row).
    python tools/harness/ref_grid.py <cx> <x0> <x1> <row0> <row1> <scale> <out.png> [step]
"""
import sys
from PIL import Image, ImageDraw
cx, x0, x1, r0, r1, sc = [float(a) for a in sys.argv[1:7]]
out = sys.argv[7]; step = int(sys.argv[8]) if len(sys.argv) > 8 else 10
REF = Image.open("assets/characters/reference/male_body_turnaround.png").convert("RGB")
im = REF.crop((int(cx + x0), int(r0), int(cx + x1), int(r1)))
im = im.resize((int(im.width * sc), int(im.height * sc)), Image.LANCZOS).convert("RGBA")
ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
d = ImageDraw.Draw(ov)
for x in range(int(x0) - int(x0) % step, int(x1) + 1, step):
    X = (x - x0) * sc
    d.line([(X, 0), (X, im.height)], fill=(0, 200, 255, 45) if x % 50 else (255, 0, 0, 90), width=1)
    if x % (step * 2) == 0:
        d.text((X + 2, 2), str(x), fill=(0, 0, 255, 255))
for r in range(int(r0) - int(r0) % step, int(r1) + 1, step):
    Y = (r - r0) * sc
    d.line([(0, Y), (im.width, Y)], fill=(0, 200, 255, 45) if r % 50 else (255, 0, 0, 90), width=1)
    d.text((2, Y + 2), str(r), fill=(0, 0, 255, 255))
im = Image.alpha_composite(im, ov).convert("RGB")
im.save(out)
