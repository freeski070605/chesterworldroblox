"""Draw a bespoke plan (local u/v metres) over the aerial to check a trace.

    py -3 tools/harness/plan_overlay.py <plan.json> <out.png>
plan.json: {"origin":[x,z], "a":deg, "bid":id, "shapes":[{"name":..,"poly":[[u,v],..]}]}
u = across axis (sin a, -cos a), v = along axis (cos a, sin a), source metres.
"""
import json, math, sys
from pathlib import Path
from PIL import ImageDraw
sys.path.insert(0, str(Path(__file__).parent))
import aerial_overlay as A

plan = json.loads(Path(sys.argv[1]).read_text())
ox, oz = plan["origin"]; t = math.radians(plan["a"])
U = (math.sin(t), -math.cos(t)); V = (math.cos(t), math.sin(t))
W = lambda u, v: (ox + U[0] * u + V[0] * v, oz + U[1] * u + V[1] * v)
pts = [W(*p) for s in plan["shapes"] for p in s["poly"]]
pad = plan.get("pad", 15)
x0, x1 = min(p[0] for p in pts) - pad, max(p[0] for p in pts) + pad
z0, z1 = min(p[1] for p in pts) - pad, max(p[1] for p in pts) + pad
K = 4
img = A.mosaic(x0, z0, x1, z1).resize((int(x1 - x0) * K, int(z1 - z0) * K))
d = ImageDraw.Draw(img)
P = lambda x, z: ((x - x0) * K, (z1 - z) * K)
for gu in range(-100, 201, 10):
    for gv in range(-60, 200, 10):
        pass
for s in plan["shapes"]:
    poly = [P(*W(*p)) for p in s["poly"]]
    d.line(poly + poly[:1], fill=s.get("color", "yellow"), width=2)
    cx = sum(p[0] for p in poly) / len(poly); cy = sum(p[1] for p in poly) / len(poly)
    d.text((cx, cy), s["name"], fill="yellow", stroke_width=1, stroke_fill="black")
# u/v ticks every 10 m along the axes through the origin
for k in range(-80, 181, 10):
    d.ellipse([*(c - 2 for c in P(*W(k, 0))), *(c + 2 for c in P(*W(k, 0)))], fill="cyan")
    d.ellipse([*(c - 2 for c in P(*W(0, k))), *(c + 2 for c in P(*W(0, k)))], fill="magenta")
img.save(sys.argv[2]); print(sys.argv[2], img.size)
