"""Full-resolution inspection sheets for local street photographs.

Each photo is pasted at native resolution (<= 640 px tiles are never
downscaled) into a 2x2 grid with a caption bar naming its path, camera
heading and the building the ray-caster says it centres on. Used for the
geographic batch reviews recorded in pose_reviews.csv; the sheet is only a
viewing aid - the cited evidence is always the original photo path.

    py -3 tools/reconstruction/photo_sheet.py OUT.jpg PHOTO[::caption] ...
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

CELL = 640
BAR = 22


def sheet(items, out, cols=2):
    rows = (len(items) + cols - 1) // cols
    canvas = Image.new("RGB", (CELL * cols, (CELL + BAR) * rows), "black")
    draw = ImageDraw.Draw(canvas)
    for k, (path, caption) in enumerate(items):
        x, y = (k % cols) * CELL, (k // cols) * (CELL + BAR)
        try:
            im = Image.open(path).convert("RGB")
        except OSError as exc:
            draw.text((x + 4, y + 4), f"MISSING {path}: {exc}", fill="red")
            continue
        if im.width > CELL or im.height > CELL:   # only larger sources shrink
            im.thumbnail((CELL, CELL))
        canvas.paste(im, (x + (CELL - im.width) // 2, y + BAR + (CELL - im.height) // 2))
        draw.rectangle([x, y, x + CELL - 1, y + BAR - 1], fill=(30, 30, 30))
        draw.text((x + 4, y + 5), f"{k + 1}. {caption}"[:104], fill="yellow")
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, quality=92)
    return out


if __name__ == "__main__":
    out, *args = sys.argv[1:]
    items = []
    for a in args:
        p, _, cap = a.partition("::")
        items.append((p, cap or Path(p).name))
    print(sheet(items, out))
