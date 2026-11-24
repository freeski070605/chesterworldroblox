"""Source guards for the Kerlin creek profile and the access-crossing pass.

* Each DesignedRoadProfiles anchor lies on a county centre line of its street
  (within 1 m), so the designed chord joins the generated road exactly.
* TileBuilderV2 consults the designed profile in both strip samplers.
* AccessCrossings waits for final terrain, gas entrances, furniture, trees
  and the dealership, splits original sidewalks (no stacked slab), and uses
  the sidewalk concrete.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TILES = ROOT / "src/shared/WorldData/Tiles"
PROFILES = ROOT / "src/shared/WorldData/DesignedRoadProfiles.lua"
TILEBUILDER = ROOT / "src/server/World/TileBuilderV2.lua"
CROSSINGS = ROOT / "src/server/World/AccessCrossings.server.lua"

failures = []

text = PROFILES.read_text(encoding="utf-8")
entries = re.findall(r'street = "([^"]+)",\s*startM = \{ ([\d.]+), ([\d.]+) \},\s*finishM = \{ ([\d.]+), ([\d.]+) \}', text)
if not entries:
    failures.append("no designed profiles parsed")
record = re.compile(r'name="([^"]*)",x1=([-\d.]+),z1=([-\d.]+),x2=([-\d.]+),z2=([-\d.]+),[^}]*bridge=(\w+)')
segments = []
for path in TILES.glob("*.lua"):
    for m in record.finditer(path.read_text(encoding="utf-8")):
        segments.append((m.group(1).lower(), *map(float, m.groups()[1:5]), m.group(6)))


def distance_to(name, x, z):
    best = math.inf
    for seg_name, x1, z1, x2, z2, _ in segments:
        if seg_name != name:
            continue
        vx, vz = x2 - x1, z2 - z1
        length2 = vx * vx + vz * vz
        t = 0 if length2 == 0 else max(0, min(1, ((x - x1) * vx + (z - z1) * vz) / length2))
        best = min(best, math.hypot(x - (x1 + vx * t), z - (z1 + vz * t)))
    return best


for street, sx, sz, ex, ez in entries:
    for label, x, z in (("start", float(sx), float(sz)), ("finish", float(ex), float(ez))):
        d = distance_to(street, x, z)
        if d > 1.0:
            failures.append(f"{street} {label} anchor is {d:.2f} m from its centre line")

builder = TILEBUILDER.read_text(encoding="utf-8")
for needle in ("local designed = designedGroundY(x,z)", "local groundMid = designedGroundY(",
               "designedStreet = type(attributes)", 'part:SetAttribute("CW_DesignedProfile"'):
    if needle not in builder:
        failures.append(f"TileBuilderV2 missing: {needle}")

crossings = CROSSINGS.read_text(encoding="utf-8")
for flag in ("CW_RoadTerrainCleared", "CW_GasStationsComplete", "CW_ParkingSurfaceComplete",
             "CW_StreetFurnitureComplete", "CW_TreesComplete", "CW_Exit6DealershipReady"):
    if f'"{flag}"' not in crossings:
        failures.append(f"AccessCrossings does not wait for {flag}")
if "walk:Destroy()" not in crossings or "cutWalks(apron" not in crossings:
    failures.append("AccessCrossings must replace (split) the original sidewalk collision")
if "Config.SIDEWALK_MATERIAL" not in crossings or "Config.SIDEWALK_COLOR" not in crossings:
    failures.append("AccessCrossings must use the sidewalk concrete")

if failures:
    print("FAIL:\n  " + "\n  ".join(failures))
    sys.exit(1)
print(f"PASS: {len(entries)} designed profile(s) anchored on source centre lines; access crossings split original sidewalks after final terrain")
