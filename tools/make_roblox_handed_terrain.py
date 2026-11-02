#!/usr/bin/env python3
from pathlib import Path
import json, shutil
from PIL import Image, ImageOps

PROJECT = Path(r"E:\code\chesterworld-roblox")

if (PROJECT / "terrain_import_corrected").exists():
    SOURCE = PROJECT / "terrain_import_corrected"
else:
    SOURCE = PROJECT / "terrain_import"

OUTPUT = PROJECT / "terrain_import_roblox_handed"

manifest_path = SOURCE / "terrain_import_manifest.json"
if not manifest_path.exists():
    raise SystemExit(f"Missing manifest: {manifest_path}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
chunks = manifest.get("chunks") or []
if not chunks:
    raise SystemExit("Terrain manifest has no chunks.")

if OUTPUT.exists():
    shutil.rmtree(OUTPUT)
OUTPUT.mkdir(parents=True)

for chunk in chunks:
    filename = chunk["file"]
    src = SOURCE / filename
    if not src.exists():
        raise SystemExit(f"Missing terrain PNG: {src}")

    with Image.open(src) as im:
        ImageOps.flip(im).save(OUTPUT / filename)

    pos = chunk["roblox_selection"]["position_studs"]
    pos["z"] = -float(pos["z"])

manifest["roblox_handedness_fixed"] = True
manifest["geographic_axes"] = {
    "north": "-Z",
    "south": "+Z",
    "east": "+X",
    "west": "-X",
}
manifest["orientation_note"] = (
    "Terrain reflected across Roblox Z=0: PNG vertically flipped "
    "and chunk center Z negated."
)

(OUTPUT/"terrain_import_manifest.json").write_text(
    json.dumps(manifest, indent=2), encoding="utf-8"
)

lines = [
    "CHESTERWORLD — ROBLOX HANDEDNESS TERRAIN",
    "="*72,
    "",
    "TRUE GAME AXES:",
    "NORTH = -Z",
    "SOUTH = +Z",
    "EAST  = +X",
    "WEST  = -X",
    "",
    "Clear CURRENT Terrain before importing these PNGs.",
    "",
]

for i, chunk in enumerate(chunks, 1):
    s = chunk["roblox_selection"]["size_studs"]
    p = chunk["roblox_selection"]["position_studs"]
    lines += [
        f"{i}. {chunk['file']}",
        f"   SIZE     X={float(s['x']):.3f}  Y={float(s['y']):.3f}  Z={float(s['z']):.3f}",
        f"   POSITION X={float(p['x']):.3f}  Y={float(p['y']):.3f}  Z={float(p['z']):.3f}",
        "",
    ]

(OUTPUT/"IMPORT_INSTRUCTIONS.txt").write_text(
    "\n".join(lines), encoding="utf-8"
)

print("="*72)
print("CHESTERWORLD ROBLOX HANDEDNESS TERRAIN READY")
print("="*72)
print(f"Source: {SOURCE}")
print(f"Output: {OUTPUT}")
for chunk in chunks:
    p = chunk["roblox_selection"]["position_studs"]
    print(f"{chunk['file']}: Z position {float(p['z']):.3f}")
print("="*72)
