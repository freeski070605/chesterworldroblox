"""Contact sheets: every mapped sports surface (Parks.lua + verified) over DVRPC 2025.

    python -m tools.sports.audit_sheets [--after]

Cyan = OSM source box, magenta = verified/corrected geometry (--after).
Writes build/sports_audit/sheet_XX.jpg and index.json.
"""
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from tools.sports.overlay import Sheet, box_corners

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build" / "sports_audit"
SPORT_KINDS = ("pitch", "track")


def features():
    text = (ROOT / "src/shared/WorldData/Parks.lua").read_text(encoding="utf-8")
    out = []
    for m in re.finditer(r'\{kind="(\w+)"(?:,sport="(\w+)")?,box=\{([^}]*)\}', text):
        kind, sport, box = m.group(1), m.group(2), [float(v) for v in m.group(3).split(",")]
        if kind in SPORT_KINDS:
            out.append({"kind": kind, "sport": sport or "pitch", "box": box})
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    feats = features()
    thumbs = []
    for i, f in enumerate(feats):
        cx, cz, L, W, yaw = f["box"]
        half = max(L, W) * 0.75 + 30
        ppx = 320 / (2 * half)
        s = Sheet(cx, cz, half, ppx, enhance=1.2)
        s.box(f["box"], "cyan", 2)
        img = s.img.resize((320, 320))
        d = ImageDraw.Draw(img)
        d.rectangle((0, 0, 320, 16), fill="black")
        d.text((3, 2), f"#{i} {f['sport']} ({cx:.0f},{cz:.0f}) {L:.0f}x{W:.0f} y{yaw:.0f}", fill="white")
        thumbs.append(img)
    per = 12
    for k in range(0, len(thumbs), per):
        sheet = Image.new("RGB", (4 * 320, 3 * 320), "white")
        for j, t in enumerate(thumbs[k:k + per]):
            sheet.paste(t, ((j % 4) * 320, (j // 4) * 320))
        sheet.save(OUT / f"sheet_{k // per:02d}.jpg", quality=88)
    (OUT / "index.json").write_text(json.dumps(feats, indent=1))
    print("features", len(feats), "sheets", (len(thumbs) + per - 1) // per)


if __name__ == "__main__":
    main()
