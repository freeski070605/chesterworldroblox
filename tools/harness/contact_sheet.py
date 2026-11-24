"""Contact sheet of images (private review aid): contact_sheet.py out.jpg cols cell img...  """
import sys
from pathlib import Path
from PIL import Image, ImageDraw
out, cols, cell = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
files = sys.argv[4:]
rows = (len(files) + cols - 1) // cols
can = Image.new("RGB", (cols * cell, rows * (cell + 16)), "black")
d = ImageDraw.Draw(can)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB"); im.thumbnail((cell, cell))
    x, y = (i % cols) * cell, (i // cols) * (cell + 16)
    can.paste(im, (x, y + 16)); d.text((x + 2, y + 2), Path(f).stem[:60], fill="yellow")
Path(out).parent.mkdir(parents=True, exist_ok=True)
can.save(out, quality=90)
