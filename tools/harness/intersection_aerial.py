"""intersection_aerial.py OUT.png CX CZ HALF_M
DVRPC 2025 orthophoto around (CX, CZ) studs with road centrelines (name),
building footprints (yellow, id / name) and gas station canopies (magenta) +
pylons (cyan) drawn on."""
import io, math, os, re, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw
HERE = os.path.dirname(__file__)
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
import crossing_source_report as src  # noqa
import fit_roads_to_buildings as fit  # noqa
ORX, ORY = -8397592.0, 4837229.0
out, cx, cz, half = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
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
def stud(sx, sz): return (sx - 6347.889) * 3, -(sz - 7201.973) * 3
names = {}
for path in sorted(fit.TILES.glob("tile_*.lua")):
    for line in path.read_text(encoding="utf-8").split("\n"):
        m = fit.ROAD_RE.match(line)
        if not m: continue
        a, b = px(*stud(float(m["x1"]), float(m["z1"]))), px(*stud(float(m["x2"]), float(m["z2"])))
        if max(a[0], b[0]) < 0 or min(a[0], b[0]) > W or max(a[1], b[1]) < 0 or min(a[1], b[1]) > H: continue
        d.line([a, b], fill=(0, 230, 255), width=2)
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        if m["name"] not in names or abs(mid[0] - W / 2) + abs(mid[1] - H / 2) < names[m["name"]][0]:
            names[m["name"]] = (abs(mid[0] - W / 2) + abs(mid[1] - H / 2), mid)
for n, (_, mid) in names.items():
    d.rectangle([mid[0], mid[1], mid[0] + 7 * len(n) + 4, mid[1] + 13], fill=(0, 60, 90)); d.text((mid[0] + 2, mid[1]), n, fill=(255, 255, 255))
polys, keys = fit.footprints(with_keys=True)
bnames = {}
for p in (fit.BUILDINGS).glob("*.lua"):
    for m in re.finditer(r'\["(\d+)"\]=\{[^\n]*?name="([^"]*)"', p.read_text(encoding="utf-8")): bnames[m.group(1)] = m.group(2)
for poly, k in zip(polys, keys):
    pts = [px(*stud(x, z)) for x, z in poly.exterior.coords]
    if all(-50 < p[0] < W + 50 and -50 < p[1] < H + 50 for p in pts):
        d.line(pts, fill=(255, 220, 0), width=2)
        c = px(*stud(poly.centroid.x, poly.centroid.y)); t = k[1] + (" " + bnames[k[1]] if k[1] in bnames else "")
        d.rectangle([c[0], c[1], c[0] + 6 * len(t) + 4, c[1] + 12], fill=(0, 0, 0)); d.text((c[0] + 2, c[1]), t, fill=(255, 220, 0))
gs = open(os.path.join(HERE, "..", "..", "src", "shared", "WorldData", "GasStations.lua"), encoding="utf-8").read()
for line in gs.splitlines():
    m = re.search(r'name="([^"]+)".*?sign=\{([-\d.]+),([-\d.]+)', line)
    if not m: continue
    p = px(float(m.group(2)), float(m.group(3)))
    d.ellipse([p[0] - 9, p[1] - 9, p[0] + 9, p[1] + 9], fill=(0, 255, 255)); d.text((p[0] + 11, p[1] - 6), m.group(1) + " pylon", fill=(0, 255, 255))
    for b in re.findall(r'box=\{([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\}', line.split("canopies=")[1].split("store=")[0]):
        x, z, L, Wd, yaw = map(float, b); t = math.radians(yaw); ex, ez = (math.cos(t), -math.sin(t)), (math.sin(t), math.cos(t))
        cs = [(x + ex[0] * u * L / 2 + ez[0] * v * Wd / 2, z + ex[1] * u * L / 2 + ez[1] * v * Wd / 2) for u, v in ((1, 1), (1, -1), (-1, -1), (-1, 1), (1, 1))]
        d.line([px(*c) for c in cs], fill=(255, 0, 255), width=3)
img.save(out); print("wrote", out)
