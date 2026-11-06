"""Google Street View captures of every highway structure in HighwayStructureRegistry.lua.

For each registry entry (studs -> lat/lon via the inverse of build_landmarks.studs):
  - 6-face cubemap (fov 90) of the pano nearest the structure centre
  - one view aimed at the structure from panos ~70 m N/E/S/W of it (distinct panos only)
Output: E:\\ChesterWorld\\Data\\HighwayReference\\imagery\\google\\<ID>\\ + structures_google.json
Images (c) Google - private reference only.

    py -3 tools/storefronts/google_structures.py
"""
import json
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import storefront_sweep as s  # noqa: E402
import google_streetview as g  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
REG = ROOT / "src" / "shared" / "HighwayStructureRegistry.lua"
OUT = s.DATA / "HighwayReference" / "imagery" / "google"


def unstuds(x, z):
    mx = x / 3 - 8397592 + 6347.889
    my = -z / 3 + 4837229 + 7201.973
    lon = mx / 20037508.34 * 180.0
    lat = math.degrees(2 * math.atan(math.exp(my / 6378137.0)) - math.pi / 2)
    return lat, lon


def entries():
    txt = REG.read_text(encoding="utf-8")
    out = []
    pat = re.compile(r'namedEntry\("(\w+)",\s*(?:nil|"\d+"),\s*\{[^}]*\},\s*\{[^}]*\},\s*(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?),\s*(\d+)', re.S)
    for m in pat.finditer(txt):
        out.append((m.group(1), float(m.group(2)), float(m.group(3)), float(m.group(4))))
    # KERLIN_I95 is a hand entry: use the crossings.csv anchor
    out.append(("KERLIN_I95", None, None, 60))
    return out


def main():
    k = g.key()
    meta = g.Meta(OUT / "metadata_cache.json")
    res = []
    for sid, x, z, radius in entries():
        if x is None:
            lat, lon = 39.851764, -75.37375
        else:
            lat, lon = unstuds(x, z)
        folder = OUT / sid
        rec = {"id": sid, "lat": lat, "lon": lon, "images": []}
        md = meta.get(lat, lon, 80, k)
        if md:
            base = s.bearing(md["lat"], md["lon"], lat, lon) if s.dist_m(md["lat"], md["lon"], lat, lon) > 3 else 0
            for name, dh, pitch in (("F", 0, 0), ("R", 90, 0), ("B", 180, 0), ("L", 270, 0), ("U", 0, 90), ("D", 0, -90)):
                dest = folder / "cubemap" / f"{name}_{md['pano_id']}.jpg"
                if g.fetch(md["pano_id"], (base + dh) % 360, pitch, 90, dest, k):
                    rec["images"].append({"path": str(dest.relative_to(OUT)), "role": f"cubemap_{name}", "pano_id": md["pano_id"],
                                          "date": md["date"], "heading": round((base + dh) % 360, 1), "pitch": pitch})
        used = {md["pano_id"]} if md else set()
        for label, brg in (("from_N", 0), ("from_E", 90), ("from_S", 180), ("from_W", 270)):
            d = 70
            plat = lat + d * math.cos(math.radians(brg)) / 111320
            plon = lon + d * math.sin(math.radians(brg)) / (111320 * math.cos(math.radians(lat)))
            m2 = meta.get(plat, plon, 40, k)
            if not m2 or m2["pano_id"] in used:
                continue
            dd = s.dist_m(m2["lat"], m2["lon"], lat, lon)
            if dd > 130:
                continue
            used.add(m2["pano_id"])
            hd = s.bearing(m2["lat"], m2["lon"], lat, lon)
            fov = max(60, min(110, math.degrees(2 * math.atan((radius / 3 + 10) / max(dd, 10)))))
            dest = folder / f"{label}_{m2['pano_id']}.jpg"
            if g.fetch(m2["pano_id"], hd, 3, fov, dest, k):
                rec["images"].append({"path": str(dest.relative_to(OUT)), "role": label, "pano_id": m2["pano_id"],
                                      "date": m2["date"], "heading": round(hd, 1), "pitch": 3, "fov": round(fov),
                                      "distance_m": round(dd, 1), "camera_lat": m2["lat"], "camera_lon": m2["lon"]})
        res.append(rec)
        s.log(f"{sid:38} images={len(rec['images'])}")
    meta.flush()
    s.save(OUT / "structures_google.json", {"license": g.LIC, "structures": res})
    s.log(f"done: {sum(len(r['images']) for r in res)} images for {len(res)} structures -> {OUT}")


if __name__ == "__main__":
    main()
