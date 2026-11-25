"""Check proposed Memorial Park football footprint against source park and roads."""
import json
import sys
from pathlib import Path
from shapely.affinity import rotate
from shapely.geometry import LineString, box, shape

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_parks import LANDUSE, to_studs
from validate_fuel_range import graph

features = json.loads(LANDUSE.read_text(encoding="utf-8"))["features"]
park = next(to_studs(shape(f["geometry"])) for f in features
            if f["properties"].get("name") == "Veterans Memorial Park")
courts = [to_studs(shape(f["geometry"])) for f in features
          if f["properties"].get("sport") == "basketball"]
edges, names, _ = graph()
segments = {(min(a, b), max(a, b)) for a, nexts in edges.items() for b in nexts}
roads = [(LineString((a, b)), names[a] | names[b]) for a, b in segments]

def check(x, z, L=390, W=165, yaw=12):
    footprint = rotate(box(x-L/2, z-W/2, x+L/2, z+W/2), -yaw, origin=(x,z))
    hit = [label for road, label in roads if road.intersects(footprint)]
    return park.contains(footprint), hit, sum(court.intersects(footprint) for court in courts)


if __name__ == "__main__":
    print("current", check(-3700, -5950))
    for x in range(-3900, -3199, 50):
        for z in range(-6300, -5749, 50):
            inside, roads_hit, courts_hit = check(x, z)
            if inside and not roads_hit and not courts_hit:
                print("candidate", x, z)
