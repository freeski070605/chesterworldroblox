"""crossing_source_report.py [RADIUS]
For each investigated crossing pin, list the county/OSM road records whose
segments pass within RADIUS studs (default 40), and every 2D intersection or
shared vertex between differently named records near the pin, with layer /
bridge / grade_group. Coordinates are Roblox studs (x = (x_m - CX) * 3,
z = -(z_m - CZ) * 3)."""
import glob, math, re, sys

S, CX, CZ = 3.0, 6347.889, 7201.973
RADIUS = float(sys.argv[1]) if __name__ == "__main__" and len(sys.argv) > 1 else 40.0
PINS = [
    ("01a", -2838, 2132), ("01b", -2785, 2168), ("02", -2912, 2097),
    ("03a", -2564, 2078), ("03b", -2513, 2003), ("04a", -4650, 3087),
    ("04b", -4598, 3128), ("05", 10589, -5484), ("06", -1055, 5237),
    ("07a", 80, 6754), ("07b", -48, 6842), ("08a", 9510, -12229),
    ("08b", 9460, -11610), ("08c", 9570, -11643),
]
ROW = re.compile(r"\{name=\"([^\"]*)\",x1=([-\d.]+),z1=([-\d.]+),x2=([-\d.]+),z2=([-\d.]+),([^}]*)\}")
FIELD = re.compile(r"(\w+)=(\"[^\"]*\"|[^,]+)")

segs = []
for path in sorted(glob.glob("src/shared/WorldData/Tiles/tile_*.lua")):
    for m in ROW.finditer(open(path, encoding="utf-8").read()):
        rest = dict((k, v.strip('"')) for k, v in FIELD.findall(m.group(6)))
        if "grade_group" not in rest:
            continue
        x1, z1, x2, z2 = (float(m.group(i)) for i in range(2, 6))
        segs.append({
            "name": m.group(1), "ax": (x1 - CX) * S, "az": -(z1 - CZ) * S,
            "bx": (x2 - CX) * S, "bz": -(z2 - CZ) * S, **rest,
        })


def dist_point_seg(px, pz, s):
    ux, uz = s["bx"] - s["ax"], s["bz"] - s["az"]
    l2 = ux * ux + uz * uz
    f = 0 if l2 == 0 else max(0, min(1, ((px - s["ax"]) * ux + (pz - s["az"]) * uz) / l2))
    return math.hypot(s["ax"] + ux * f - px, s["az"] + uz * f - pz)


def intersect(a, b):
    rx, rz = a["bx"] - a["ax"], a["bz"] - a["az"]
    sx, sz = b["bx"] - b["ax"], b["bz"] - b["az"]
    den = rx * sz - rz * sx
    if abs(den) < 1e-9:
        return None
    qx, qz = b["ax"] - a["ax"], b["az"] - a["az"]
    t, u = (qx * sz - qz * sx) / den, (qx * rz - qz * rx) / den
    if -1e-6 <= t <= 1 + 1e-6 and -1e-6 <= u <= 1 + 1e-6:
        sine = abs(den) / (math.hypot(rx, rz) * math.hypot(sx, sz))
        return a["ax"] + rx * t, a["az"] + rz * t, t, u, sine
    return None


def tag(s):
    return "%s[%s L%s%s %s]" % (s["name"], s["grade_group"], s.get("layer", "?"),
                                " BR" if s.get("bridge") == "true" else "", s.get("road_class", "?"))


for pid, px, pz in (PINS if __name__ == "__main__" else []):
    near =[s for s in segs if dist_point_seg(px, pz, s) <= RADIUS]
    print("=== %s (%d, %d): %d segments within %.0f" % (pid, px, pz, len(near), RADIUS))
    groups = {}
    for s in near:
        groups.setdefault(s["grade_group"], []).append(s)
    for g, lst in sorted(groups.items()):
        s = lst[0]
        print("   %-55s segs=%d" % (tag(s), len(lst)))
    seen = set()
    for i, a in enumerate(near):
        for b in near[i + 1:]:
            if a["name"] == b["name"] or a["grade_group"] == b["grade_group"]:
                continue
            hit = intersect(a, b)
            if not hit:
                continue
            x, z, t, u, sine = hit
            end_a = t < 1e-3 or t > 1 - 1e-3
            end_b = u < 1e-3 or u > 1 - 1e-3
            kind = "shared-vertex" if end_a and end_b else ("T-vertex" if end_a or end_b else "crossing")
            key = (a["grade_group"], b["grade_group"], round(x / 5), round(z / 5))
            if key in seen:
                continue
            seen.add(key)
            print("   %-13s at (%.1f, %.1f) angle=%2.0fdeg  %s  x  %s" % (
                kind, x, z, math.degrees(math.asin(min(1, sine))), tag(a), tag(b)))
