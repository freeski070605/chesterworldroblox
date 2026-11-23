"""Median colour of a pixel box in a local photo (for photo-measured finishes).

    py -3 tools/reconstruction/sample_colour.py PHOTO x0,y0,x1,y1 [...]
Prints hex per box. Pick boxes on sunlit, unobstructed wall surface only.
"""
import sys
from statistics import median

from PIL import Image

img = Image.open(sys.argv[1]).convert("RGB")
for box in sys.argv[2:]:
    x0, y0, x1, y1 = map(int, box.split(","))
    px = list(img.crop((x0, y0, x1, y1)).get_flattened_data() if hasattr(Image.Image, "get_flattened_data") else img.crop((x0, y0, x1, y1)).getdata())
    rgb = [int(median(c[i] for c in px)) for i in range(3)]
    print(box, "%02x%02x%02x" % tuple(rgb), rgb)
