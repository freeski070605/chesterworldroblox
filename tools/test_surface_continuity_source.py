"""Source topology guard for the Kerlin lower road and the full tile set.

Collision height measurements are emitted by the Roblox runtime's
IntersectionContinuity, RoadSeamJoins and FinalSurfaceAlignment checks.
"""

from collections import Counter
from pathlib import Path
import re


root = Path(__file__).resolve().parents[1]
tiles = sorted((root / "src/shared/WorldData/Tiles").glob("tile_r*_c*.lua"))
assert len(tiles) == 102, f"expected 102 city tiles, found {len(tiles)}"

groups = {"county:2758:g0", "county:27163:g0", "county:20771:g0", "county:20770:g0"}
start, finish = (7024.280, 7184.991), (7006.124, 7218.855)
dx, dz = finish[0] - start[0], finish[1] - start[1]
length2 = dx * dx + dz * dz
edges = []
for tile in tiles:
    for line in tile.read_text().splitlines():
        if 'name="Kerlin' not in line or 'grade_group="county:' not in line:
            continue
        match = re.search(
            r'x1=([\d.]+),z1=([\d.]+),x2=([\d.]+),z2=([\d.]+).*?grade_group="([^"]+)"',
            line,
        )
        if not match or match[5] not in groups:
            continue
        ax, az, bx, bz = map(float, match.group(1, 2, 3, 4))
        mx, mz = (ax + bx) / 2, (az + bz) / 2
        t = ((mx - start[0]) * dx + (mz - start[1]) * dz) / length2
        offset = abs((mx - start[0]) * dz - (mz - start[1]) * dx) / length2**0.5
        if 0 <= t <= 1 and offset < 4:
            assert "bridge=false" in line and "layer=0" in line
            edges.append(((ax, az), (bx, bz)))

degree = Counter(point for edge in edges for point in edge)
assert len(edges) == 4, f"Kerlin underpass source changed: {len(edges)} core edges"
assert degree[start] == degree[finish] == 1
assert sorted(degree.values()) == [1, 1, 2, 2, 2]
print("PASS: 102 tiles; Kerlin lower-road source is one four-edge at-grade chain")
