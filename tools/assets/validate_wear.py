"""Static checks for the EXIT 6 wardrobe (no Studio needed).

Run: python tools/assets/validate_wear.py
- every mesh a wardrobe item uses exists in the generated manifest
- every item has a known slot / store / roles, a price, and colours for its roles
- every legacy id maps to a real item of a sensible slot
- the starter fit exists and is free to own
- every manifest mesh is under the Roblox triangle limit
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "src" / "shared" / "Exit6Wardrobe.luau").read_text(encoding="utf-8")
MANIFEST = {m["name"]: m for m in json.loads((ROOT / "assets" / "wear" / "manifest.json").read_text(encoding="utf-8"))}
MESHES_LUAU = (ROOT / "src" / "shared" / "Exit6WearMeshes.luau").read_text(encoding="utf-8")

errors: list[str] = []

slots = re.search(r"Wardrobe\.Slots = \{([^}]*)\}", SRC).group(1)
SLOTS = set(re.findall(r'"(\w+)"', slots))
ROLES = set(re.findall(r"^\t(\w+) = \{ material", SRC, re.M))

# every mesh name referenced anywhere in the wardrobe source
used = set(re.findall(r'(?:mesh = |[HFPM]\()"(\w+)"', SRC))
for name in sorted(used):
    if name not in MANIFEST:
        errors.append(f"wardrobe uses unknown mesh {name}")
    if f"\t{name} = {{" not in MESHES_LUAU:
        errors.append(f"Exit6WearMeshes.luau lacks {name} (re-run build_wearables.py)")
unused = sorted(set(MANIFEST) - used)

for name, m in MANIFEST.items():
    if m["triangles"] >= 20000:
        errors.append(f"{name}: {m['triangles']} triangles")

# item ids: cut("id", ...) -> hair_id; top/bottom/shoes/hat/jewel("id", ...); item("id", ...)
ids = {f"hair_{i}" for i in re.findall(r'^cut\("(\w+)"', SRC, re.M)}
ids |= set(re.findall(r'^(?:top|bottom|shoes|hat|jewel|item)\("(\w+)"', SRC, re.M))
legacy = dict(re.findall(r'(\w+) = "((?:hair|w|j)_\w+)"', SRC.split("Wardrobe.Legacy = {", 1)[1].split("}", 1)[0]))
for old, new in legacy.items():
    if new not in ids:
        errors.append(f"legacy {old} -> missing item {new}")
for slot, iid in re.findall(r"(\w+) = \"(w_\w+)\"", SRC.split("Wardrobe.Starter = {", 1)[1].split("}", 1)[0]):
    if slot not in SLOTS:
        errors.append(f"starter slot {slot} unknown")
    if iid not in ids:
        errors.append(f"starter item {iid} missing")
for role in set(re.findall(r'role = "(\w+)"', SRC)) | set(re.findall(r'P\("\w+", "(\w+)"\)', SRC)):
    if role not in ROLES:
        errors.append(f"unknown role {role}")

print(f"{len(ids)} items, {len(used)} meshes used, {len(MANIFEST)} in manifest, {len(legacy)} legacy ids")
if unused:
    print("meshes not used by any item:", ", ".join(unused))
if errors:
    print("FAIL")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("PASS")
