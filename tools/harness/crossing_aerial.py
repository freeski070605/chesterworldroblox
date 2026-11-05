"""crossing_aerial.py OUTDIR [SITE...]
Fetch the DVRPC 2025 orthophoto around each crossing site and write two PNGs
per site: <site>_raw.png and <site>_src.png (county source segments drawn on
top: red = layer 1 / bridge-tagged, cyan = layer 0; each record labelled once
with its county id). Pins are yellow squares.
Roblox studs -> EPSG:3857: mx = ORX + CX + x/3, my = ORY + CZ - z/3 (origin
back-solved from the inspector pins; integer like build_regional_expansion)."""
import io, os, sys, urllib.parse, urllib.request
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import crossing_source_report as src  # noqa: E402

ORX, ORY = -8397592.0, 4837229.0
OUT = sys.argv[1] if len(sys.argv) > 1 else "build/aerial"
W, H = 1400, 1000
SITES = {
    "conchester_barry": (-2700, 2090, 105),
    "engle": (-4624, 3108, 70),
    "i95_i476_bullens": (10589, -5484, 70),
    "sixth": (-1040, 5228, 60),
    "second": (16, 6798, 70),
    "macdade_merge": (9510, -12229, 60),
    "bullens_i476": (9515, -11625, 60),
    "sixth_wide": (-1000, 5200, 150),
    "exit4_wide": (-2850, 2080, 170),
    "macdade_wide": (9530, -11950, 160),
    "chester_pke": (13730, -6985, 130),
    "flower": (-1330, 4680, 80),
    "riverfront": (1050, 8180, 90),
    "crosby": (5800, -2020, 80),
    "csx_crum": (14420, -10378, 70),
    "csx_476": (12138, -7638, 70),
    "park_vallei": (280, -8670, 90),
    "i476_flyover": (12180, -6850, 110),
    "n476_merge": (12250, -7250, 200),
    "barry_7th": (-1200, 4870, 90),
}
ONLY = set(sys.argv[2:])
URL = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export"


def to3857(x, z):
    return ORX + src.CX + x / 3.0, ORY + src.CZ - z / 3.0


os.makedirs(OUT, exist_ok=True)
for site, (cx, cz, half) in SITES.items():
    if ONLY and site not in ONLY:
        continue
    mx, my = to3857(cx, cz)
    hx, hy = half, half * H / W
    bbox = (mx - hx, my - hy, mx + hx, my + hy)
    q = urllib.parse.urlencode({"bbox": ",".join("%.3f" % v for v in bbox), "bboxSR": 3857, "imageSR": 3857,
                                "size": "%d,%d" % (W, H), "format": "jpg", "f": "image", "layers": "show:4"})
    img = Image.open(io.BytesIO(urllib.request.urlopen(URL + "?" + q, timeout=90).read())).convert("RGB")
    img.save(os.path.join(OUT, site + "_raw.png"))

    def px(x, z):
        ex, ey = to3857(x, z)
        return (ex - bbox[0]) / (bbox[2] - bbox[0]) * W, (bbox[3] - ey) / (bbox[3] - bbox[1]) * H

    draw = ImageDraw.Draw(img)
    labelled = {}
    for s in src.segs:
        a, b = px(s["ax"], s["az"]), px(s["bx"], s["bz"])
        if max(a[0], b[0]) < 0 or min(a[0], b[0]) > W or max(a[1], b[1]) < 0 or min(a[1], b[1]) > H:
            continue
        up = s.get("layer") not in (None, "0") or s.get("bridge") == "true"
        draw.line([a, b], fill=(255, 40, 40) if up else (0, 230, 255), width=3)
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        score = (mid[0] - W / 2) ** 2 + (mid[1] - H / 2) ** 2
        g = s["grade_group"]
        if g not in labelled or score < labelled[g][0]:
            labelled[g] = (score, mid, "%s %s" % (g.split(":")[1], s["name"]))
    for _, mid, text in labelled.values():
        draw.rectangle([mid[0], mid[1], mid[0] + 7 * len(text), mid[1] + 13], fill=(0, 0, 0))
        draw.text((mid[0] + 2, mid[1]), text, fill=(255, 255, 255))
    for pid, x, z in src.PINS:
        p = px(x, z)
        if 0 <= p[0] <= W and 0 <= p[1] <= H:
            draw.rectangle([p[0] - 6, p[1] - 6, p[0] + 6, p[1] + 6], outline=(255, 230, 0), width=3)
            draw.text((p[0] + 9, p[1] - 18), pid, fill=(255, 230, 0))
    img.save(os.path.join(OUT, site + "_src.png"))
    print("wrote", site)
