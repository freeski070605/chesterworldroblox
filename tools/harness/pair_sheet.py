"""Side-by-side sheet: python tools/harness/pair_sheet.py out.png height label1=a.png label2=b.png ..."""
import sys
from PIL import Image, ImageDraw
out, h = sys.argv[1], int(sys.argv[2])
cells = []
for a in sys.argv[3:]:
    lab, p = a.split("=", 1); im = Image.open(p).convert("RGB")
    cells.append((lab, im.resize((int(im.width * h / im.height), h), Image.LANCZOS)))
W = sum(c.width for _, c in cells) + 8 * (len(cells) - 1)
sheet = Image.new("RGB", (W, h + 26), "white"); d = ImageDraw.Draw(sheet); x = 0
for lab, c in cells:
    sheet.paste(c, (x, 26)); d.text((x + 4, 6), lab, fill="black"); x += c.width + 8
sheet.save(out); print(out, sheet.size)
