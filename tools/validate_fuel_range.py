"""Measure a reproducible city circuit from shipped street segments and check tanks.

The route visits the outer reaches of the largest connected road component,
returning to its start. It is a source-data range test, not a Studio drive test.
"""
from __future__ import annotations

import heapq
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELLS = ROOT / "src/shared/StreetCells"
CATALOG = ROOT / "src/shared/Exit6Catalog.luau"
SEGMENT = re.compile(r'\{name="([^"]+)",x1=([\d.-]+),z1=([\d.-]+),x2=([\d.-]+),z2=([\d.-]+)')
VEHICLE = re.compile(r'\b(\w+)\s*=\s*\{[^{}]*?\btank\s*=\s*([\d.]+)\s*,\s*perGallon\s*=\s*([\d.]+)', re.S)


def graph():
    edges: dict[tuple[float, float], dict[tuple[float, float], float]] = {}
    names: dict[tuple[float, float], set[str]] = {}
    segment_count = 0
    for path in CELLS.glob("*.lua"):
        for name, *values in SEGMENT.findall(path.read_text(encoding="utf-8")):
            if re.search(r"csx|rail|amtrak|septa|chester secondary", name, re.I):
                continue
            x1, z1, x2, z2 = map(float, values)
            a, b = (x1, z1), (x2, z2)
            length = math.dist(a, b)
            if length < 0.01:
                continue
            edges.setdefault(a, {})[b] = length
            edges.setdefault(b, {})[a] = length
            names.setdefault(a, set()).add(name)
            names.setdefault(b, set()).add(name)
            segment_count += 1
    return edges, names, segment_count


def component(edges, start):
    seen = {start}
    stack = [start]
    while stack:
        for neighbor in edges[stack.pop()]:
            if neighbor not in seen:
                seen.add(neighbor)
                stack.append(neighbor)
    return seen


def distances(edges, source):
    dist = {source: 0.0}
    todo = [(0.0, source)]
    while todo:
        length, node = heapq.heappop(todo)
        if length != dist[node]:
            continue
        for neighbor, edge_length in edges[node].items():
            new = length + edge_length
            if new < dist.get(neighbor, math.inf):
                dist[neighbor] = new
                heapq.heappush(todo, (new, neighbor))
    return dist


def measure():
    edges, names, count = graph()
    remaining = set(edges)
    largest = set()
    while remaining:
        part = component(edges, next(iter(remaining)))
        remaining -= part
        if len(part) > len(largest):
            largest = part
    # Fixed geographic anchors cover the western, northern, eastern and southern
    # reaches of the connected road network, plus central Chester. Nearest road
    # nodes are used because parks and intersections do not always share vertices.
    anchors = [(-9000, -5000), (-6000, 7000), (3000, 8500),
               (9500, 3000), (9000, -7500), (0, -9000), (-9000, -5000)]
    stops = [min(largest, key=lambda p: math.dist(p, a)) for a in anchors]
    legs = []
    for a, b in zip(stops, stops[1:]):
        d = distances(edges, a).get(b)
        if d is None:
            raise AssertionError(f"Disconnected route leg: {a} to {b}")
        legs.append(d)
    return sum(legs), stops, legs, names, count, len(largest)


def vehicles():
    return {name: (float(tank), float(per_gallon)) for name, tank, per_gallon
            in VEHICLE.findall(CATALOG.read_text(encoding="utf-8"))}


def main():
    route, stops, legs, names, count, connected = measure()
    target = route * 1.25
    print(f"street segments: {count}; largest connected component: {connected} nodes")
    print(f"circuit: {route:.0f} studs; target with 25% reserve: {target:.0f} studs")
    for i, (stop, leg) in enumerate(zip(stops, legs), 1):
        print(f"  leg {i}: {stop} [{', '.join(sorted(names[stop]))}] {leg:.0f} studs")
    data = vehicles()
    assert len(data) == 11, f"Expected all 11 catalog vehicles, found {len(data)}"
    failed = []
    for model, (tank, per_gallon) in sorted(data.items()):
        full = tank * per_gallon
        reserve = (full / route - 1) * 100
        print(f"  {model:8} {full:8.0f} studs  {reserve:6.1f}% reserve")
        if full < target:
            failed.append(model)
    if failed:
        raise AssertionError(f"Insufficient full-tank range: {', '.join(failed)}")


if __name__ == "__main__":
    main()
