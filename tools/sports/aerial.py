"""Georeferenced DVRPC 2025 aerial crops in Roblox world studs.

World convention (tools/build_parks.py studs()): +X east, +Z south (north is -Z),
3 studs per EPSG:3857 metre. Crops are cached under build/sports_imagery/.

    from tools.sports.aerial import crop
    img, to_px = crop(cx, cz, half=400, px_per_stud=1.0)
"""
import hashlib
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "build" / "sports_imagery"
URL = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export"


def studs(lon, lat):
    mx = lon * 20037508.34 / 180.0
    my = math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0
    return (mx + 8397592 - 6347.889) * 3, -(my - 4837229 - 7201.973) * 3


def merc(x, z):
    return x / 3 - 8397592 + 6347.889, 4837229 + 7201.973 - z / 3


def lonlat(x, z):
    mx, my = merc(x, z)
    return mx * 180.0 / 20037508.34, math.degrees(2 * math.atan(math.exp(my / 6378137.0)) - math.pi / 2)


def crop(cx, cz, half=400, px_per_stud=1.0, half_z=None):
    """Aerial image covering x in [cx-half, cx+half], z in [cz-half_z, cz+half_z].
    Returns (PIL image, fn(x, z) -> (px, py)). Image up = north = -Z."""
    half_z = half if half_z is None else half_z
    w, h = round(2 * half * px_per_stud), round(2 * half_z * px_per_stud)
    x0, y1 = merc(cx - half, cz - half_z)   # north-west corner
    x1, y0 = merc(cx + half, cz + half_z)   # south-east corner
    bbox = f"{x0:.3f},{y0:.3f},{x1:.3f},{y1:.3f}"
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / ("dvrpc_" + hashlib.sha1(f"{bbox}|{w}|{h}".encode()).hexdigest()[:16] + ".jpg")
    if not path.exists():
        q = urllib.parse.urlencode({"bbox": bbox, "bboxSR": 3857, "imageSR": 3857, "size": f"{w},{h}",
                                    "format": "jpg", "f": "image", "layers": "show:4"})
        for attempt in range(4):
            try:
                path.write_bytes(urllib.request.urlopen(URL + "?" + q, timeout=120).read())
                break
            except OSError as error:
                print("retry", attempt + 1, error, flush=True)
                time.sleep(5 * (attempt + 1))
        else:
            raise SystemExit("aerial fetch failed")
    img = Image.open(path).convert("RGB")

    def to_px(x, z):
        return (x - (cx - half)) * px_per_stud, (z - (cz - half_z)) * px_per_stud

    return img, to_px
