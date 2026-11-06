"""station_aerial.py [OUTDIR]
DVRPC 2025 orthophoto around each gas station with the building footprints
(yellow, county id), the fuel canopies (magenta) and the pylon sign (cyan dot)
drawn on - to pick each station's store building and check the sign spot."""
import io, os, re, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw

HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import crossing_source_report as src  # noqa: E402
import fit_roads_to_buildings as fit  # noqa: E402

ORX, ORY = -8397592.0, 4837229.0
OUT = sys.argv[1] if len(sys.argv) > 1 else "build/aerial"
W, H, HALF = 1200, 900, 75
URL = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export"
TEXT = open(os.path.join(HERE, "..", "..", "src", "shared", "WorldData", "GasStations.lua"), encoding="utf-8").read()
STATIONS = []
for line in TEXT.splitlines():
    m = re.search(r'id="(\w+)",name="([^"]+)".*?address="([^"]+)".*?sign=\{([-\d.]+),([-\d.]+),[-\d.]+\}.*?canopies=\{(.*)\}\}', line)
    if m:
        boxes = [tuple(map(float, b)) for b in re.findall(r'box=\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\}', m.group(6))]
        STATIONS.append((m.group(1), m.group(2), m.group(3), (float(m.group(4)), float(m.group(5))), boxes))
polys, keys = fit.footprints(with_keys=True)


def to3857(x, z):
    return ORX + src.CX + x / 3.0, ORY + src.CZ - z / 3.0


os.makedirs(OUT, exist_ok=True)
import math
for sid, name, address, sign, boxes in STATIONS:
    cx, cz = boxes[0][0], boxes[0][1]
    mx, my = to3857(cx, cz)
    bbox = (mx - HALF, my - HALF * H / W, mx + HALF, my + HALF * H / W)
    q = urllib.parse.urlencode({"bbox": ",".join("%.3f" % v for v in bbox), "bboxSR": 3857, "imageSR": 3857,
                                "size": "%d,%d" % (W, H), "format": "jpg", "f": "image", "layers": "show:4"})
    img = Image.open(io.BytesIO(urllib.request.urlopen(URL + "?" + q, timeout=90).read())).convert("RGB")
    d = ImageDraw.Draw(img)

    def px(x, z):
        ex, ey = to3857(x, z)
        return (ex - bbox[0]) / (bbox[2] - bbox[0]) * W, (bbox[3] - ey) / (bbox[3] - bbox[1]) * H

    def stud(sx, sz):
        return (sx - 6347.889) * 3, -(sz - 7201.973) * 3
    for poly, k in zip(polys, keys):
        pts = [px(*stud(x, z)) for x, z in poly.exterior.coords]
        if all(-50 < p[0] < W + 50 and -50 < p[1] < H + 50 for p in pts):
            d.line(pts, fill=(255, 220, 0), width=2)
            c = px(*stud(poly.centroid.x, poly.centroid.y))
            d.rectangle([c[0], c[1], c[0] + 7 * len(k[1]) + 4, c[1] + 13], fill=(0, 0, 0))
            d.text((c[0] + 2, c[1]), k[1], fill=(255, 220, 0))
    for bx, bz, L, Wd, yaw in boxes:
        a = math.radians(yaw)
        ca, sa = math.cos(a), math.sin(a)
        corners = [(bx + ca * u * L / 2 - sa * v * Wd / 2, bz + sa * u * L / 2 + ca * v * Wd / 2) for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1), (1, 1))]
        d.line([px(x, z) for x, z in corners], fill=(255, 0, 255), width=3)
    sp = px(*sign)
    d.ellipse([sp[0] - 8, sp[1] - 8, sp[0] + 8, sp[1] + 8], fill=(0, 255, 255))
    d.text((10, 10), "%s %s %s" % (sid, name, address), fill=(255, 255, 255))
    img.save(os.path.join(OUT, "station_%s.png" % sid))
    print("wrote", sid, name, address)
