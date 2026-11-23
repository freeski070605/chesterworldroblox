"""Make a contact sheet of mapped pilot parking lots over local DVRPC imagery."""

import json
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw
from shapely.geometry import Polygon, box


ROOT = Path(__file__).resolve().parents[1]
AERIAL = Path('E:/ChesterWorld/Data/19_Aerial')
INDEX = json.loads((AERIAL / 'index.json').read_text())
text = (ROOT / 'src/server/World/ParkingSurfaceData.lua').read_text()
rows = re.findall(r'id=(\d+),material="(\w+)",outline=\{([^}]*)\}', text)
pilot = box(1900, 800, 3500, 2300)
sheet = Image.new('RGB', (1200, 430), 'white')
draw = ImageDraw.Draw(sheet)
at = 0
for ident, material, packed in rows:
    coords = [float(v) for v in packed.split(',')]
    poly = Polygon(list(zip(coords[::2], coords[1::2])))
    if not poly.intersects(pilot):
        continue
    x, z = poly.centroid.x, poly.centroid.y
    mx = x / 3 - 8397592 + 6347.889
    my = 4837229 + 7201.973 - z / 3
    tile = next((entry for entry in INDEX if entry['xmin'] <= mx < entry['xmax'] and entry['ymin'] <= my < entry['ymax']), None)
    if tile is None:
        continue
    image = Image.open(AERIAL / tile['file'])
    px, py = int(mx - tile['xmin']), int(tile['ymax'] - my)
    crop = image.crop((px - 180, py - 180, px + 180, py + 180))
    sheet.paste(crop, (at * 400 + 20, 20))
    outline = [(at * 400 + 20 + 180 + (vx - x) / 3,
                20 + 180 + (vz - z) / 3) for vx, vz in poly.exterior.coords]
    draw.line(outline, fill='#00ffff', width=3, joint='curve')
    draw.rectangle((at * 400 + 20 + 175, 20 + 175, at * 400 + 20 + 185, 20 + 185), outline='red', width=2)
    draw.text((at * 400 + 20, 385), f'OSM {ident} ({x:.0f}, {z:.0f}) {material}', fill='black')
    at += 1
sheet.save(ROOT / 'build/pilot_parking_aerial.png')
print(f'pilot aerial crops={at}')
