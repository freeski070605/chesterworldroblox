"""Offline source checks for the generated parking-surface footprint data."""

import re
from pathlib import Path

from shapely.geometry import Polygon, box


ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / 'src/server/World/ParkingSurfaceData.lua').read_text()
matches = re.findall(r'id=(\d+),material="(\w+)",outline=\{([^}]*)\}', text)
assert len(matches) >= 170, f'parking lot inventory shrank: {len(matches)}'
assert len({row[0] for row in matches}) == len(matches), 'duplicate OSM lot id'
pilot = box(1900, 800, 3500, 2300)
pilot_lots = []
candidate_chunks = 0
for ident, material, packed in matches:
    coords = [float(value) for value in packed.split(',')]
    polygon = Polygon(list(zip(coords[::2], coords[1::2])))
    assert material in {'Asphalt', 'Gravel'}
    assert polygon.is_valid and polygon.area >= 350, f'invalid lot {ident}'
    min_x, min_z, max_x, max_z = polygon.bounds
    candidate_chunks += (int(max_x // 64) - int(min_x // 64) + 1) * (int(max_z // 64) - int(min_z // 64) + 1)
    if polygon.intersects(pilot):
        pilot_lots.append(ident)
assert candidate_chunks < 8000, f'parking pass exceeds cold-start chunk budget: {candidate_chunks}'
print(f'PASS: {len(matches)} distinct valid mapped parking lots; <= {candidate_chunks} candidate chunks; pilot intersections={len(pilot_lots)} {pilot_lots}')
