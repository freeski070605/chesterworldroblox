"""Fit Exit 6 Motors into the J&S / Boost / 5 Points front lot (building 93584).
Inputs are in-game stud geometry measured in Studio Play (server) 2026-11-22:
sidewalk slabs (centre, yaw, 5-stud width), intersection pads and the strip's
lot-facing ShopDoors. Frame: n = outward facade normal (toward 9th/Kerlin node),
t = along the facade (ENE). Prints the lot polygon and checks every layout box."""
import math
NF = (-0.4223842, -0.9064169)          # ShopDoor LookVector (x, z): bearing 335
TF = (0.9064169, -0.4223842)
def tn(x, z): return (x*TF[0] + z*TF[1], x*NF[0] + z*NF[1])
def xz(t, n): return (t*TF[0] + n*NF[0], t*TF[1] + n*NF[1])
def yawdir(yaw):  # look vector of a part with Roblox yaw (deg) -> (x, z)
    r = math.radians(yaw); return (-math.sin(r), -math.cos(r))
def edge(cx, cz, yaw, half, lot_pt):
    """sidewalk outer edge (toward lot) as (point, normal pointing into the lot)"""
    d = yawdir(yaw); nrm = (d[1], -d[0])
    if (lot_pt[0]-cx)*nrm[0] + (lot_pt[1]-cz)*nrm[1] < 0: nrm = (-nrm[0], -nrm[1])
    return (cx + nrm[0]*half, cz + nrm[1]*half), nrm
LOT_PT = (2940, 1600)
kerlin = edge(2855.3, 1574.0, 24.4, 2.5, LOT_PT)
concord = edge(2935.7, 1540.5, 65.7, 2.5, LOT_PT)
ninth = edge(2932.1, 1484.7, 117.4, 2.5, LOT_PT)
boost, js = (2927.469, 1636.098), (2972.598, 1620.487)
print("Boost door t,n = %.1f, %.1f   J&S door t,n = %.1f, %.1f" % (*tn(*boost), *tn(*js)))
FACADE_N = -2650.0 + 0.0   # outermost building point measured along NF (approx frame)
def inside(x, z, margin):
    for (p, nrm) in (kerlin, concord, ninth):
        if (x-p[0])*nrm[0] + (z-p[1])*nrm[1] < margin: return False
    return True
# intersection pads (centre, rough radius from wedge sizes)
pads = [((2849.0, 1489.0), 36.0), ((2890.1, 1507.7), 10.0)]
def clear_pads(x, z, margin):
    return all(math.hypot(x-c[0], z-c[1]) > r + margin for c, r in pads)
door_t = tn(*boost)[0], tn(*js)[0]
door_n = (tn(*boost)[1] + tn(*js)[1]) / 2
print("door line n = %.1f" % door_n)
# layout boxes in (t, n) relative to the Boost door: (name, t0, t1, n0, n1)
O_T, O_N = tn(*boost)
L = [
  ("display pad (5 bikes/quads)", -32, 14, 88, 106),
  ("car row (3 cars)", -32, 40, 60, 80),
  ("office", -34, -10, 34, 50),
  ("pylon", -36, -33, 108, 111),
  ("store aisle kept open", -40, 120, 0, 30),
]
for name, t0, t1, n0, n1 in L:
    ok = True; worst = 1e9
    for t in (t0, t1):
        for n in (n0, n1):
            x, z = xz(O_T + t, O_N + n)
            ok &= inside(x, z, 1.0) and clear_pads(x, z, 1.0)
            for (p, nrm) in (kerlin, concord, ninth):
                worst = min(worst, (x-p[0])*nrm[0] + (z-p[1])*nrm[1])
    cx, cz = xz(O_T + (t0+t1)/2, O_N + (n0+n1)/2)
    print("%-30s centre (%.1f, %.1f)  min edge clearance %.1f  %s" % (name, cx, cz, worst, "OK" if ok else "CONFLICT"))
