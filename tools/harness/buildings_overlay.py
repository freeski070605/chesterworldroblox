"""buildings_overlay.py OUT.png CX CZ HALF
Draw the county (red) and Overture (cyan) building footprints over the
DVRPC 2025 orthophoto around a Roblox stud position."""
import io, json, math, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw

DATA = r"E:\ChesterWorld\Data"
W, H = 1400, 1000
URL = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export"
out, cx, cz, half = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
mx, my = -8397592 + 6347.889 + cx / 3, 4837229 + 7201.973 - cz / 3
hx, hy = half / 3 * W / H, half / 3
bbox = (mx - hx, my - hy, mx + hx, my + hy)
q = urllib.parse.urlencode({"bbox": ",".join("%.3f" % v for v in bbox), "bboxSR": 3857, "imageSR": 3857,
                            "size": "%d,%d" % (W, H), "format": "jpg", "f": "image", "layers": "show:4"})
img = Image.open(io.BytesIO(urllib.request.urlopen(URL + "?" + q, timeout=60).read())).convert("RGB")
draw = ImageDraw.Draw(img)

def merc(lon, lat):
    return lon * 20037508.34 / 180, math.log(math.tan((90 + lat) * math.pi / 360)) * 6378137

def px(e, n):
    return (e - bbox[0]) / (bbox[2] - bbox[0]) * W, (bbox[3] - n) / (bbox[3] - bbox[1]) * H

counts = {}
for path, colour in ((DATA + r"\13_RegionalMaster\regional_buildings_base.geojson", (255, 40, 40)),
                     (DATA + r"\01_Buildings\overture_buildings_region_20261021.geojson", (0, 230, 255))):
    n = 0
    for f in json.load(open(path, encoding="utf-8"))["features"]:
        g = f["geometry"]
        rings = [g["coordinates"][0]] if g["type"] == "Polygon" else [p[0] for p in g["coordinates"]]
        for ring in rings:
            pts = [px(*merc(*c)) if abs(c[0]) <= 180 else px(*c) for c in ring]
            if any(0 <= x <= W and 0 <= y <= H for x, y in pts):
                draw.line(pts, fill=colour, width=2)
                n += 1
    counts[path.rsplit("\\", 1)[1]] = n
img.save(out)
print(out, counts)
