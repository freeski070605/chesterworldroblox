"""After-sheet for the citywide audit corrections (red = OSM, green = corrected,
orange = diamond from the home-plate corner). -> build/sports_audit/corrections_after.jpg"""
import re
from pathlib import Path

from PIL import Image, ImageDraw

from tools.sports.overlay import Sheet, local_to_world

ROOT = Path(__file__).resolve().parents[2]
V = (ROOT / "src/shared/Exit6VerifiedSports.luau").read_text(encoding="utf-8")
P = (ROOT / "src/shared/WorldData/Parks.lua").read_text(encoding="utf-8")
corr = V.split("corrections = {")[1].split("facilities = {")[0]


def nums(s):
    return [float(v) for v in s.split(",")]


def source_box(x, z):
    for m in re.finditer(r"box=\{([^}]*)\}", P):
        b = nums(m.group(1))
        if abs(b[0] - x) < 1 and abs(b[1] - z) < 1:
            return b


def diamond(s, b, home, base):
    hx, hz = home[0] * b[2] / 2, home[1] * b[3] / 2
    d1, d2 = (-home[0], 0), (0, -home[1])
    hx, hz = hx + (d1[0] + d2[0]) * 0.3 * base, hz + (d1[1] + d2[1]) * 0.3 * base
    pts = [(hx, hz), (hx + d1[0] * base, hz), (hx + (d1[0] + d2[0]) * base, hz + d2[1] * base), (hx, hz + d2[1] * base)]
    s.poly([local_to_world(b[0], b[1], b[4], *p) for p in pts], "orange", 3)
    s.dot(*local_to_world(b[0], b[1], b[4], hx, hz), "white", 5)


tiles = []
for line in corr.splitlines():
    m = re.search(r"\{ at = \{ (-?[\d.]+), (-?[\d.]+) \}, (.*)", line)
    if not m:
        continue
    x, z, rest = float(m.group(1)), float(m.group(2)), m.group(3)
    src = source_box(x, z)
    if not src or "trackColor" in rest or "group =" in rest:
        continue
    block = corr[corr.index(line):].split("\n\t\t{ at")[0] if "replace" in rest else line
    news = [nums(b) for b in re.findall(r"box = \{ ([^}]*) \}", block)]
    homes = re.findall(r"home = \{ (-?1), (-?1) \}, base = (\d+)", block)
    half = max(src[2], src[3]) * 0.75 + 40
    s = Sheet(src[0], src[1], half, 360 / (2 * half), enhance=1.2)
    s.box(src, "red", 2)
    if "drop" in rest:
        s.draw.line([(0, 0), (360, 360)], fill="red", width=3)
    for i, b in enumerate(news or ([src] if homes else [])):
        s.box(b, "lime", 2)
    for i, (hx, hz, base) in enumerate(homes):
        diamond(s, (news or [src])[i], (int(hx), int(hz)), float(base))
    if "halfCourt" in rest:
        s.dot(*local_to_world(src[0], src[1], src[4], -src[2] / 2 + 3, 0), "orange", 5)
    img = s.img.resize((360, 360))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 360, 14), fill="black")
    label = rest.split("--")[0][:52]
    d.text((3, 1), f"({x:.0f},{z:.0f}) {label}", fill="white")
    tiles.append(img)
cols = 5
sheet = Image.new("RGB", (cols * 360, ((len(tiles) + cols - 1) // cols) * 360), "white")
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * 360, (i // cols) * 360))
sheet.save(ROOT / "build/sports_audit/corrections_after.jpg", quality=88)
print("tiles", len(tiles))
