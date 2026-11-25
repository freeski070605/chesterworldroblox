"""Crop the project's DVRPC 2025 aerial tiles around mapped sports sites."""
import math
from pathlib import Path
from PIL import Image

SOURCE = Path(r"E:\ChesterWorld\Data\19_Aerial")
OUT = Path(__file__).resolve().parents[1] / "build/sports_reference"
SITES = {"a_field": (17, -1542), "memorial_courts_candidate": (-7240, 6750),
         "memorial_west7th_candidate": (-3400, -5800),
         "memorial_address": (-4398, -7002),
         "gillespie": (8364, 7027)}


def crop(x, z, radius=350):
    mx, my = x / 3 - 8391244.111, z / 3 + 4844430.973
    tx, ty = math.floor(mx / 2000) * 2000, math.floor(my / 2000) * 2000
    tile = Image.open(SOURCE / f"dvrpc2025_1m_{tx}_{ty}.jpg")
    px, py = round(mx - tx), round(ty + 2000 - my)
    return tile.crop((px-radius, py-radius, px+radius, py+radius))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (x, z) in SITES.items():
        crop(x, z).save(OUT / f"{name}.png")
        print(OUT / f"{name}.png")
