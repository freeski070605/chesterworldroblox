"""Interchange ramps carry the county's mainline motorway width.

The county classes many ramp records ("Edgmont Ave to I 95", "I 95 to N I 476",
"US 13 to US 322", ...) as motorway, and the import gives every motorway record
the 25 m mainline default. 176 ramp segments (~6.2 km) were paved 75 studs
wide - wider than a three-lane I-95 carriageway - and the Edgmont ramp spread
over the CSX tracks beside I-95 (audit 2026-11-06).

Ramp records (name "X to Y", motorway class, width >= 20 m) are set to
RAMP_WIDTH_M: two lanes with shoulders. Class is kept (HighwayProfile strokes
and the Barry design profiles key on it). Idempotent; --check reports only.

Pipeline: after fix_barry_corridor, before fit_roads_to_buildings.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TILES = ROOT / "src" / "shared" / "WorldData" / "Tiles"
RAMP_WIDTH_M = 11.0
LINE_RE = re.compile(r'name="(?P<name>[^"]*)",.*?width_m=(?P<w>[-\d.]+),road_class="(?P<cls>\w+)"')


def main(check=False):
    changed_segments, changed_files = 0, 0
    for path in sorted(TILES.glob("tile_*.lua")):
        lines = path.read_text(encoding="utf-8").split("\n")
        out = []
        for line in lines:
            m = LINE_RE.search(line)
            if m and " to " in m["name"].lower() and m["cls"] == "motorway" and float(m["w"]) >= 20:
                line = line.replace("width_m=%s,road_class=" % m["w"], "width_m=%g,road_class=" % RAMP_WIDTH_M, 1)
                changed_segments += 1
            out.append(line)
        if out != lines:
            changed_files += 1
            if not check:
                path.write_text("\n".join(out), encoding="utf-8")
    print({"ramp_segments_narrowed": changed_segments, "tiles": changed_files, "check": check})


if __name__ == "__main__":
    main("--check" in sys.argv)
