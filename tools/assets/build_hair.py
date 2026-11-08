"""Generate original, static R15 hair meshes in head-local studs.

Run: python tools/assets/build_hair.py
These are review candidates. OBJ is source-controlled; Studio import and visual
fit checks are required before any item may be marked production ready.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "hair"
TAU = math.tau


class Mesh:
    def __init__(self, name: str):
        self.name = name
        self.vertices: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.faces: list[tuple[int, int, int]] = []

    def v(self, point, uv=(0.0, 0.0)):
        self.vertices.append(tuple(point))
        self.uvs.append(tuple(uv))
        return len(self.vertices)

    def quad(self, a, b, c, d):
        self.faces.extend(((a, b, c), (a, c, d)))

    def grid(self, rings, closed=True):
        for first, second in zip(rings, rings[1:]):
            count = len(first)
            for i in range(count if closed else count - 1):
                j = (i + 1) % count
                self.quad(first[i], first[j], second[j], second[i])

    def save(self, path):
        with path.open("w", encoding="utf-8", newline="\n") as f:
            f.write(f"# EXIT 6 original procedural hair: {self.name}\n")
            f.write("# Roblox head-local units; front faces -Z; head center is origin\n")
            for x, y, z in self.vertices:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for u, v in self.uvs:
                f.write(f"vt {u:.6f} {v:.6f}\n")
            for a, b, c in self.faces:
                f.write(f"f {a}/{a} {b}/{b} {c}/{c}\n")


def cap(mesh, height=.58, width=1.015, depth=.53, bottom=.10, rows=10, cols=32, texture=0.0):
    """Open dome with a shaped edge; the scalp lies inside this surface."""
    rings = []
    for r in range(rows + 1):
        theta = .001 + (math.pi / 2 - .001) * r / rows
        ring = []
        for c in range(cols):
            a = TAU * c / cols
            x = width * math.sin(theta) * math.cos(a)
            z = depth * math.sin(theta) * math.sin(a)
            ripple = texture * math.sin(a * 19 + theta * 13) * math.sin(theta)
            y = bottom + height * math.cos(theta) + ripple
            ring.append(mesh.v((x, y, z), (c / cols, r / rows)))
        rings.append(ring)
    mesh.grid(rings)


def line(mesh, start, end, radius=.015, sides=6):
    """A real tubular strand or seam with round cross-section."""
    pts = [tuple(start[i] + (end[i] - start[i]) * t / 8 for i in range(3)) for t in range(9)]
    tube(mesh, pts, radius, sides=sides)


def tube(mesh, points, radius, sides=7, taper=.28, phase=0.0):
    rings = []
    for k, p in enumerate(points):
        q0 = points[max(0, k - 1)]
        q1 = points[min(len(points) - 1, k + 1)]
        tangent = [q1[i] - q0[i] for i in range(3)]
        mag = math.sqrt(sum(v * v for v in tangent)) or 1
        tangent = [v / mag for v in tangent]
        helper = (0, 0, 1) if abs(tangent[2]) < .85 else (1, 0, 0)
        axis = (tangent[1] * helper[2] - tangent[2] * helper[1],
                tangent[2] * helper[0] - tangent[0] * helper[2],
                tangent[0] * helper[1] - tangent[1] * helper[0])
        norm = math.sqrt(sum(v * v for v in axis)) or 1
        axis = tuple(v / norm for v in axis)
        other = (tangent[1] * axis[2] - tangent[2] * axis[1],
                 tangent[2] * axis[0] - tangent[0] * axis[2],
                 tangent[0] * axis[1] - tangent[1] * axis[0])
        fraction = k / (len(points) - 1)
        rad = radius * (1 - taper * fraction)
        ring = []
        for i in range(sides):
            a = TAU * i / sides + phase
            ring.append(mesh.v(tuple(p[j] + rad * (math.cos(a) * axis[j] + math.sin(a) * other[j])
                                     for j in range(3)), (i / sides, fraction)))
        rings.append(ring)
    mesh.grid(rings)


def edge(mesh, sharp=True):
    # Front is negative Z. A tapered hairline and temple corners sit on the cap.
    pts = [(-.83, .145, -.30), (-.68, .125, -.415), (-.46, .13, -.483),
           (-.16, .15, -.52), (.16, .15, -.52), (.46, .13, -.483),
           (.68, .125, -.415), (.83, .145, -.30)]
    if not sharp:
        pts = [(x, y + .025, z + .012) for x, y, z in pts]
    tube(mesh, pts, .018 if sharp else .012, sides=5, taper=0)
    if sharp:
        for sign in (-1, 1):
            line(mesh, (sign * .82, .145, -.30), (sign * .88, -.025, -.235), .012, 5)


def fade(mesh, kind):
    bottom = {"low_taper": .105, "mid_skin": .19, "high_top": .24, "afro_taper": .12}[kind]
    height = {"low_taper": .50, "mid_skin": .43, "high_top": .90, "afro_taper": .73}[kind]
    cap(mesh, height=height if kind != "high_top" else .42, bottom=bottom,
        texture=.018 if kind == "afro_taper" else .005)
    edge(mesh)
    if kind == "high_top":
        # Square crown with softened vertical corners; distinct flat top.
        rings = []
        for y, scale in ((.48, .76), (.97, .80), (1.12, .70)):
            ring = []
            for i in range(32):
                a = TAU * i / 32
                x = math.copysign(abs(math.cos(a)) ** .42, math.cos(a)) * scale
                z = math.copysign(abs(math.sin(a)) ** .42, math.sin(a)) * scale * .51
                ring.append(mesh.v((x, y, z), (i / 32, y)))
            rings.append(ring)
        mesh.grid(rings)
        for i in range(1, 31):
            mesh.faces.append((rings[-1][0], rings[-1][i], rings[-1][i + 1]))
    if kind == "afro_taper":
        for j in range(7):
            theta = .2 + j * .16
            for i in range(22):
                a = TAU * (i + .31 * (j % 2)) / 22
                x, z = .95 * math.sin(theta) * math.cos(a), .5 * math.sin(theta) * math.sin(a)
                y = .14 + .7 * math.cos(theta)
                tube(mesh, [(x, y, z), (x * 1.07, y + .055, z * 1.07)], .055, sides=5)


def waves(mesh):
    cap(mesh, height=.41, bottom=.14)
    edge(mesh)
    for ring in range(4):
        theta = .28 + ring * .24
        points = []
        for i in range(49):
            a = TAU * i / 48
            th = theta + .035 * math.sin(a * 7 + ring)
            points.append((1.024 * math.sin(th) * math.cos(a),
                           .14 + .416 * math.cos(th) + .008,
                           .536 * math.sin(th) * math.sin(a)))
        tube(mesh, points, .012, sides=5, taper=0)


def hanging(mesh, kind):
    cap(mesh, height=.46, bottom=.13, texture=.008)
    edge(mesh)
    count = {"starter_locs": 19, "medium_locs": 22, "shoulder_locs": 25,
             "two_strand_twists": 20, "box_braids": 28, "braided_ponytail": 21}[kind]
    length = {"starter_locs": .30, "medium_locs": .78, "shoulder_locs": 1.35,
              "two_strand_twists": .68, "box_braids": 1.07, "braided_ponytail": 1.08}[kind]
    for i in range(count):
        a = TAU * (i + .28 * (i % 3)) / count
        x, z = .79 * math.cos(a), .40 * math.sin(a)
        stem = .04 * ((i * 7) % 5 - 2)
        points = []
        for j in range(9):
            t = j / 8
            if kind == "braided_ponytail":
                x0 = x * (1 - .72 * t) + stem * t
                z0 = z * (1 - .72 * t) + .28 * t
            else:
                x0 = x * (1 + .20 * t) + stem * t + .025 * math.sin(t * 7 + i)
                z0 = z * (1 + .28 * t) + .025 * math.sin(t * 8 + i * 2)
            y0 = .48 - length * t + .045 * math.sin(a * 3 + i)
            points.append((x0, y0, z0))
        if kind == "two_strand_twists":
            for sign in (-1, 1):
                strand = [(px + .022 * math.cos(j * 1.9 + sign * math.pi),
                           py, pz + .022 * math.sin(j * 1.9 + sign * math.pi))
                          for j, (px, py, pz) in enumerate(points)]
                tube(mesh, strand, .029, sides=5, taper=.40)
        elif kind in ("box_braids", "braided_ponytail"):
            for sign in (-1, 0, 1):
                strand = [(px + .017 * math.cos(j * 1.8 + sign * TAU / 3), py,
                           pz + .017 * math.sin(j * 1.8 + sign * TAU / 3))
                          for j, (px, py, pz) in enumerate(points)]
                tube(mesh, strand, .021, sides=5, taper=.3)
        else:
            tube(mesh, points, .045 + .007 * (i % 3), sides=7, taper=.35)


def cornrows(mesh):
    cap(mesh, height=.40, bottom=.14)
    edge(mesh)
    for row in range(-4, 5):
        x = row * .19
        points = []
        for i in range(17):
            t = i / 16
            z = -.49 + .96 * t
            cap_r = max(.1, 1 - (x / 1.02) ** 2 - (z / .53) ** 2)
            y = .14 + .40 * math.sqrt(cap_r) + .02
            points.append((x + .025 * math.sin(t * 13 + row), y, z))
        tube(mesh, points, .038, sides=6, taper=.2)
        for j in range(1, 15, 2):
            p = points[j]
            line(mesh, (p[0] - .065, p[1] - .01, p[2] - .025),
                 (p[0] + .055, p[1] + .022, p[2] + .025), .012, 5)


STYLES = {
    "sharp_low_taper": lambda m: fade(m, "low_taper"),
    "mid_skin_fade": lambda m: fade(m, "mid_skin"),
    "high_top_fade": lambda m: fade(m, "high_top"),
    "waves_360": waves,
    "starter_locs": lambda m: hanging(m, "starter_locs"),
    "medium_locs": lambda m: hanging(m, "medium_locs"),
    "shoulder_locs": lambda m: hanging(m, "shoulder_locs"),
    "two_strand_twists": lambda m: hanging(m, "two_strand_twists"),
    "cornrows": cornrows,
    "box_braids": lambda m: hanging(m, "box_braids"),
    "afro_taper": lambda m: fade(m, "afro_taper"),
    "braided_ponytail": lambda m: hanging(m, "braided_ponytail"),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    for name, build in STYLES.items():
        mesh = Mesh(name)
        build(mesh)
        mesh.save(OUT / f"{name}.obj")
        report.append({"id": name, "category": "hair", "version": 1,
                       "status": "candidate_unverified", "vertices": len(mesh.vertices),
                       "triangles": len(mesh.faces), "material": "dark_hair",
                       "pivot": "R15 Head center; front -Z"})
    (OUT / "manifest.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {len(report)} hair meshes, {sum(x['triangles'] for x in report)} triangles total")


if __name__ == "__main__":
    main()
