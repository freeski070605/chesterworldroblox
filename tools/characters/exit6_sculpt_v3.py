"""Scripted sculpt brushes for the Exit 6 male V3 (guided sculpt, headless).

Each brush is the kind of stroke a sculptor makes by hand: grab (move),
inflate / deflate along the normal, flatten onto a plane, smooth, or scale
about a point, with a smooth ellipsoidal falloff. Brushes work in reference
pixel space (x, Y, row): x to the character's left, Y depth (negative = in
front of the face), row = 1140 - z like the reference sheet. Brushes are
mirrored across x = 0 unless ``mirror`` is False.

Rigid parts (eyeballs, teeth, tongue helpers) move with the mean of the
displacement over their vertices so they never deform.

The brush lists live in exit6_male_v3_spec.py (FACE_SCULPT, BODY_SCULPT) and
are applied in order; every brush is named so a reviewer can find the stroke
responsible for a form.
"""
import numpy as np


def falloff(Q, c, r, power=2.0):
    """smooth ellipsoidal falloff: 1 at the centre, 0 at radius (r scalar or (rx, rY, rrow))"""
    r = np.broadcast_to(np.asarray(r, float), (3,))
    t = np.linalg.norm((Q - np.asarray(c, float)) / r, axis=1)
    w = np.clip(1 - t * t, 0, 1) ** power
    return w


def vertex_normals(P, F_tris):
    N = np.zeros_like(P)
    a, b, c = P[F_tris[:, 0]], P[F_tris[:, 1]], P[F_tris[:, 2]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(N, F_tris[:, k], fn)
    n = np.linalg.norm(N, axis=1, keepdims=True)
    return N / np.maximum(n, 1e-12)


def laplacian(P, edges, deg):
    acc = np.zeros_like(P)
    np.add.at(acc, edges[:, 0], P[edges[:, 1]])
    np.add.at(acc, edges[:, 1], P[edges[:, 0]])
    return acc / np.maximum(deg, 1)[:, None] - P


class Sculptor:
    def __init__(self, Q, edges, tris, movable, rigid_groups=()):
        """Q: (n,3) ref-px coords (x, Y, row); movable: bool mask; rigid_groups: index arrays"""
        self.Q = Q.copy()
        self.edges = edges
        self.tris = tris
        self.deg = np.bincount(edges.ravel(), minlength=len(Q)).astype(float)
        self.movable = movable.astype(float)
        self.rigid = [np.asarray(g) for g in rigid_groups if len(g)]
        self.log = []

    # --- helpers
    def _w(self, b, side=1):
        if b["kind"] == "push_seg":
            a = np.array(b["a"], float) * [side, 1, 1]; e = np.array(b["b"], float) * [side, 1, 1]
            ab = e - a
            t = np.clip(((self.Q - a) @ ab) / (ab @ ab), 0, 1)
            dist = np.linalg.norm(self.Q - (a + t[:, None] * ab), axis=1)
            prof = np.interp(t, np.linspace(0, 1, len(b.get("profile", [1, 1]))), b.get("profile", [1, 1]))
            w = np.clip(1 - (dist / b["r"]) ** 2, 0, 1) ** b.get("power", 2.0) * prof * self.movable
            if "mask" in b:
                w = w * b["mask"](self.Q, side)
            return w, a
        c = np.array(b["c"], float) * [side, 1, 1]
        w = falloff(self.Q, c, b["r"], b.get("power", 2.0)) * self.movable
        if "mask" in b:
            w = w * b["mask"](self.Q, side)
        return w, c

    def _apply(self, D):
        for g in self.rigid:
            D[g] = D[g].mean(0)
        self.Q += D

    def normals(self):
        # normals in a space with +row downwards: flip handedness so outward stays outward
        P = self.Q * [1, 1, -1]
        N = vertex_normals(P, self.tris)
        return N * [1, 1, -1]

    # --- strokes
    def stroke(self, b):
        cx = b["c"][0] if "c" in b else b["a"][0]
        sides = (1, -1) if b.get("mirror", True) and cx != 0 else (1,)
        kind = b["kind"]
        total = 0.0
        for side in sides:
            w, c = self._w(b, side)
            if not w.any():
                continue
            D = np.zeros_like(self.Q)
            if kind == "move":
                d = np.array(b["d"], float) * [side, 1, 1]
                D = w[:, None] * d
            elif kind in ("push", "push_seg"):   # + inflates, - deflates (along the vertex normal)
                N = self.normals()
                D = (w * b["amount"])[:, None] * N
            elif kind == "scale":
                s = np.broadcast_to(np.asarray(b["s"], float), (3,))
                D = w[:, None] * (self.Q - c) * (s - 1)
            elif kind == "flatten":         # pull toward the plane through c with normal n
                n = np.array(b["n"], float) * [side, 1, 1]; n /= np.linalg.norm(n)
                h = (self.Q - c) @ n
                if b.get("only") == "above":
                    h = np.maximum(h, 0)
                elif b.get("only") == "below":
                    h = np.minimum(h, 0)
                D = -(w * h * b.get("strength", 1.0))[:, None] * n
            elif kind == "smooth":
                for _ in range(b.get("iters", 4)):
                    L = laplacian(self.Q, self.edges, self.deg)
                    Dk = (w * b.get("strength", 0.5))[:, None] * L
                    self._apply(Dk)
                    total = max(total, float(np.abs(Dk).max()))
                continue
            elif kind == "taubin":          # smooth without shrinking
                for _ in range(b.get("iters", 6)):
                    for lam in (0.5, -0.53):
                        L = laplacian(self.Q, self.edges, self.deg)
                        self._apply((w * lam)[:, None] * L)
                continue
            else:
                raise ValueError(kind)
            self._apply(D)
            total = max(total, float(np.linalg.norm(D, axis=1).max()))
        self.log.append((b["name"], round(total, 2)))

    def run(self, brushes):
        for b in brushes:
            self.stroke(b)
        return self.Q


def conform_to_sphere(Q, centre, radius, idx, gap, weight):
    """pull points in front of an eyeball back onto its surface (+gap) along Y"""
    c = np.asarray(centre, float)
    d = Q[idx] - c
    rr = d[:, 0] ** 2 + d[:, 2] ** 2
    inside = rr < (radius + gap) ** 2
    yS = c[1] - np.sqrt(np.maximum((radius + gap) ** 2 - rr, 0))
    out = Q.copy()
    front = inside & (Q[idx, 1] < yS)          # floating in front of the ball
    sel = idx[front]
    out[sel, 1] = Q[sel, 1] + (yS[front] - Q[sel, 1]) * weight[front]
    return out
