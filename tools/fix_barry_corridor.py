"""Commodore Barry Bridge / US 322 approach: county records the profiler skipped.

DVRPC 2025 orthophoto (tools/harness/crossing_aerial.py barry_1..barry_7):
the approach is one elevated freeway from the Amtrak line over 4th, 3rd, 2nd,
Front, the Conrail track, Delaware Ave and Chester Riverfront to the truss
over the Delaware, with ramp loops to 2nd St (PA 291), US 13 and Flower St.
The county data classes ~50 of those records as local / residential /
tertiary / primary streets with 3.6-10 m widths, so HighwayProfile left them
out of the corridor and TileBuilder laid them on the ground: 20-stud steps
where the elevated mainline handed over to them (2nd St, Riverfront, the
US 13 ramp) and ramps that merged at the wrong level.

This tool
  * reclasses every non-freeway record named "Commodore John Barry" to
    motorway and every Barry ramp ("Pa 291 to Wb US 322", "US 322 to PA 291",
    "US 13 to US 322", "US 322 to US 13") to motorway_link,
  * raises their widths to one real carriageway / ramp lane pair,
  * drops the records over the river (county 18252 / 20298 and OSM
    302552041): LandmarkBuilder builds the river bridge from the end of the
    approach.
Idempotent.  py -3 tools/fix_barry_corridor.py   (run before fit_roads_to_buildings.py)
"""
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TILES = ROOT / "src" / "shared" / "WorldData" / "Tiles"

MAINLINE = "Commodore John Barry"
RAMPS = {"Pa 291 to Wb US 322", "US 322 to PA 291", "US 13 to US 322", "US 322 to US 13"}
FREEWAY = {"motorway", "motorway_link", "trunk", "trunk_link"}
MAINLINE_MIN_W = 11.0   # source m: one carriageway of the 5-lane approach
RAMP_MIN_W = 7.5
RIVER_SOURCES = {"county:18252", "county:20298", "osm:302552041"}
# Flower St at the US 322 / Flower St ramp terminal (crossing_aerial.py
# barry_flower): a local street at ground passing under the Barry deck
# (registry BARRY_OVER_FLOWER). The county classes it motorway / motorway_link
# and tags the piece under the deck as a 25 m layer-1 bridge, which made the
# profiler treat it as freeway and step 4.6 studs where the two met.
FLOWER_SOURCES = {"county:18152", "county:20475", "county:21224", "county:20476"}
FLOWER_W = 9.0

ROAD_RE = re.compile(r'^(?P<head>\s*\{name="(?P<name>[^"]*)",x1=[-\d.]+,z1=[-\d.]+,x2=[-\d.]+,z2=[-\d.]+,)'
                     r'width_m=(?P<w>[-\d.]+),road_class="(?P<cls>\w+)",(?P<rest>.*grade_group="(?P<gg>[^"]*)".*)$')


def fmt(v):
    return ("%.3f" % v).rstrip("0").rstrip(".")


def main(check=False):
    stats = Counter()
    for path in sorted(TILES.glob("tile_*.lua")):
        lines = path.read_text(encoding="utf-8").split("\n")
        out = []
        for line in lines:
            m = ROAD_RE.match(line)
            if not m or not (m["name"] == MAINLINE or m["name"] in RAMPS or m["name"] == "Flower St"
                             or m["name"] == "Commodore John Barry Bridge"):
                out.append(line)
                continue
            source = ":".join(m["gg"].split(":")[:2])
            if m["name"] == "Flower St" and source in FLOWER_SOURCES:
                rest = re.sub(r"bridge=\w+,tunnel=\w*,layer=-?\d+", "bridge=false,tunnel=false,layer=0", m["rest"])
                new = '%swidth_m=%s,road_class="tertiary",%s' % (m["head"], fmt(min(float(m["w"]), FLOWER_W)), rest)
                if new != line:
                    stats["flower_st_grounded"] += 1
                out.append(new)
                continue
            if source in RIVER_SOURCES:
                stats["river_records_dropped"] += 1
                continue
            cls, w = m["cls"], float(m["w"])
            if m["name"] == MAINLINE:
                new_cls, min_w = (cls if cls in FREEWAY else "motorway"), MAINLINE_MIN_W
            elif m["name"] in RAMPS:
                new_cls, min_w = (cls if cls in FREEWAY else "motorway_link"), RAMP_MIN_W
            else:
                out.append(line)
                continue
            new_w = max(w, min_w)
            if new_cls != cls:
                stats["reclassed_" + new_cls] += 1
            if new_w != w:
                stats["widened"] += 1
            out.append('%swidth_m=%s,road_class="%s",%s' % (m["head"], fmt(new_w), new_cls, m["rest"]))
        if out != lines and not check:
            path.write_text("\n".join(out), encoding="utf-8")
    print(dict(stats))


if __name__ == "__main__":
    main("--check" in sys.argv)
