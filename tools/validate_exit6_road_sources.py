"""Check the county road chains used at 9th/Barry and the Exit 5/6 ramps.

This is a source topology check. It cannot establish Roblox Y, collision, or
whether a generated barrier blocks a vehicle; those require a Studio run.
"""
from collections import Counter, defaultdict

from highway.tiledata import load_roads, to_studs


def point(road, end):
    return (round(road[f"x{end}"], 3), round(road[f"z{end}"], 3))


def chain(roads, name, endpoints):
    members = [road for road in roads if road["name"] == name]
    assert members, f"Missing {name}"
    degree = Counter()
    neighbours = defaultdict(list)
    for road in members:
        a, b = point(road, 1), point(road, 2)
        assert a != b, f"Zero-length {name} record"
        degree[a] += 1
        degree[b] += 1
        neighbours[a].append(b)
        neighbours[b].append(a)
    terminals = [node for node, count in degree.items() if count == 1]
    assert len(terminals) == 2, f"{name}: expected one unbranched chain, got {len(terminals)} terminals"
    seen, stack = set(), [terminals[0]]
    while stack:
        node = stack.pop()
        if node not in seen:
            seen.add(node)
            stack.extend(neighbours[node])
    assert len(seen) == len(degree), f"{name}: disconnected source pieces"
    actual = {tuple(round(v, 1) for v in to_studs(*node)) for node in terminals}
    assert actual == endpoints, f"{name}: terminals changed: {actual}"
    return members


def main():
    roads = load_roads()
    nine = [road for road in roads if road["grade_group"] == "county:26532:g0"]
    assert len(nine) == 1 and nine[0]["name"] == "9th"
    for node in (point(nine[0], 1), point(nine[0], 2)):
        barry = [road for road in roads if road["name"] == "Commodore John Barry"
                 and node in (point(road, 1), point(road, 2))]
        assert len(barry) >= 2, f"9th/Barry source junction missing at {node}"
    edgmont = chain(roads, "Edgmont Ave to I 95", {(6210.2, -2281.4), (4547.1, -1360.5)})
    kerlin = chain(roads, "Kerlin St to I 95", {(1946.1, -104.3), (-1806.5, 1614.7)})
    off = chain(roads, "I 95 to Kerlin St", {(801.2, 648.5), (1789.3, 422.7)})
    for label, members in (("Edgmont southbound", edgmont), ("Kerlin southbound", kerlin),
                           ("Kerlin exit", off)):
        print(f"PASS {label}: {len(members)} connected source segments")
    print("PASS 9th/Barry: source street joins both Barry carriageways")


if __name__ == "__main__":
    main()
