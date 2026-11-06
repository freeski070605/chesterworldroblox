"""Download the DVRPC 2025 orthophoto at 1 m/px over the building extent.

    python tools/fetch_aerial_mosaic.py

Tiles of 2000 x 2000 m (EPSG:3857) go to E:/ChesterWorld/Data/19_Aerial with an
index.json of their bounds. Existing tiles are skipped.
"""
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

URL = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/export"
OUT = Path(r"E:\ChesterWorld\Data\19_Aerial")
BUILDINGS = Path(r"E:\ChesterWorld\Data\13_RegionalMaster\regional_buildings_base.geojson")
TILE_M, PX = 2000, 2000


def merc(lon, lat):
    return lon * 20037508.34 / 180.0, math.log(math.tan((90.0 + lat) * math.pi / 360.0)) * 6378137.0


def main():
    xs, ys = [], []
    for f in json.loads(BUILDINGS.read_text(encoding="utf-8"))["features"]:
        for lon, lat in f["geometry"]["coordinates"][0][:1]:
            x, y = merc(lon, lat)
            xs.append(x)
            ys.append(y)
    x0 = math.floor((min(xs) - 100) / TILE_M) * TILE_M
    y0 = math.floor((min(ys) - 100) / TILE_M) * TILE_M
    x1 = math.ceil((max(xs) + 100) / TILE_M) * TILE_M
    y1 = math.ceil((max(ys) + 100) / TILE_M) * TILE_M
    OUT.mkdir(parents=True, exist_ok=True)
    index = []
    for tx in range(int(x0), int(x1), TILE_M):
        for ty in range(int(y0), int(y1), TILE_M):
            name = f"dvrpc2025_1m_{tx}_{ty}.jpg"
            path = OUT / name
            if not path.exists():
                q = urllib.parse.urlencode({"bbox": f"{tx},{ty},{tx + TILE_M},{ty + TILE_M}", "bboxSR": 3857,
                                            "imageSR": 3857, "size": f"{PX},{PX}", "format": "jpg",
                                            "f": "image", "layers": "show:4"})
                for attempt in range(5):
                    try:
                        path.write_bytes(urllib.request.urlopen(URL + "?" + q, timeout=120).read())
                        break
                    except OSError as error:
                        print("retry", name, attempt + 1, error, flush=True)
                        time.sleep(10 * (attempt + 1))
                else:
                    print("FAILED", name, flush=True)
                    continue
            index.append({"file": name, "xmin": tx, "ymin": ty, "xmax": tx + TILE_M, "ymax": ty + TILE_M})
    (OUT / "index.json").write_text(json.dumps(index), encoding="utf-8")
    print("tiles", len(index))


if __name__ == "__main__":
    main()
