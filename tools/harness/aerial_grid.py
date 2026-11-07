"""aerial_grid.py OUT.png CX CZ HALF_M [STEP]
Raw DVRPC 2025 orthophoto around (CX, CZ) studs with a stud grid (every STEP
studs, labelled) - for reading real positions off the aerial."""
import io, os, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw
HERE = os.path.dirname(__file__); sys.path.insert(0, HERE)
import crossing_source_report as src  # noqa
ORX, ORY = -8397592.0, 4837229.0
out, cx, cz, half = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
step = float(sys.argv[5]) if len(sys.argv) > 5 else 50
W, H = 1600, 1200
def to3857(x, z): return ORX + src.CX + x / 3.0, ORY + src.CZ - z / 3.0
mx, my = to3857(cx, cz)
bbox = (mx - half, my - half * H / W, mx + half, my + half * H / W)
q = urllib.parse.urlencode({"bbox": ",".join("%.3f" % v for v in bbox), "bboxSR": 3857, "imageSR": 3857,
                            "size": "%d,%d" % (W, H), "format": "jpg", "f": "image", "layers": "show:4"})
img = Image.open(io.BytesIO(urllib.request.urlopen(
    "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export?" + q, timeout=90).read())).convert("RGB")
d = ImageDraw.Draw(img)
def px(x, z):
    ex, ey = to3857(x, z)
    return (ex - bbox[0]) / (bbox[2] - bbox[0]) * W, (bbox[3] - ey) / (bbox[3] - bbox[1]) * H
x0 = int((cx - half * 3) // step) * step
z0 = int((cz - half * 3 * H / W) // step) * step
x = x0
while x < cx + half * 3:
    a, b = px(x, cz - half * 3), px(x, cz + half * 3)
    d.line([a, b], fill=(255, 255, 255), width=1); d.text((a[0] + 2, 2), str(int(x)), fill=(255, 255, 0))
    x += step
z = z0
while z < cz + half * 3:
    a, b = px(cx - half * 3, z), px(cx + half * 3, z)
    d.line([a, b], fill=(255, 255, 255), width=1); d.text((2, a[1] + 2), str(int(z)), fill=(255, 255, 0))
    z += step
img.save(out); print("wrote", out)
