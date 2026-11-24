"""Static checks for the EXIT 6 Premium collection (no Studio needed).

Run: python tools/assets/validate_premium.py
- every mesh a premium item uses exists (premium or base manifest) and the
  generated Exit6PremiumMeshes.luau matches the premium manifest
- every premium item is store "premium", has no repRequired, and is granted
  by some product; bundle-only items appear only in outfit bundles
- product ids are 0 (placeholder) or unique positive integers
- every texture set a premium mesh uses has uploaded maps (uploads.json)
- triangle budget per product and for the heaviest look
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WARD = (ROOT / "src" / "shared" / "Exit6Wardrobe.luau").read_text(encoding="utf-8")
PREM = (ROOT / "src" / "shared" / "Exit6Premium.luau").read_text(encoding="utf-8")
PM_LUAU = (ROOT / "src" / "shared" / "Exit6PremiumMeshes.luau").read_text(encoding="utf-8")
PMAN = {m["name"]: m for m in json.loads((ROOT / "assets" / "wear" / "premium" / "manifest.json").read_text(encoding="utf-8"))}
BMAN = {m["name"]: m for m in json.loads((ROOT / "assets" / "wear" / "manifest.json").read_text(encoding="utf-8"))}
UPLOADS = json.loads((ROOT / "assets" / "wear" / "premium" / "uploads.json").read_text(encoding="utf-8"))
LIMBS = {"UpperArm", "LowerArm", "UpperLeg", "LowerLeg", "Foot"}
LOOK_BUDGET = 70000      # triangles for one full premium look (both limbs counted)

errors: list[str] = []

# ---------------------------------------------------------------- wardrobe premium items
section = WARD.split("-- EXIT 6 Premium (Robux)", 1)[1].split("-- skin tones", 1)[0]
local_tables = {}
for name, body in re.findall(r"^local (\w+) = \{(.*?)\}\n", section, re.M | re.S):
    local_tables[name] = re.findall(r'(?:R\(|mesh = )"(\w+)"', body)
roles_def = set(re.findall(r"^\t(\w+) = \{ material", WARD, re.M))
role_surface = dict(re.findall(r'^\t(\w+) = \{ material = [^}]*surface = "(\w+)"', WARD, re.M))

items = {}
for iid, body in re.findall(r'^premium\("(\w+)", \{(.*?)\}\)\n', section, re.M | re.S):
    meshes = re.findall(r'(?:R\(|mesh = )"(\w+)"', body)
    for ref in re.findall(r"pieces = (\w+)", body):
        meshes += local_tables.get(ref, [])
    roles = re.findall(r'R\("\w+", "(\w+)"\)|role = "(\w+)"', body)
    items[iid] = {"meshes": meshes, "bundleOnly": "bundleOnly = true" in body, "rep": "repRequired" in body,
                  "slot": (re.search(r'slot = "(\w+)"', body) or [None, None])[1]}
    if not meshes:
        errors.append(f"{iid}: no pieces")
    if items[iid]["rep"]:
        errors.append(f"{iid}: premium items may not carry repRequired")
for name, body in local_tables.items():
    pass
for role in set(re.findall(r'R\("\w+", "(\w+)"\)', section)) | set(re.findall(r'role = "(\w+)"', section)):
    if role not in roles_def:
        errors.append(f"unknown role {role}")

for iid, it in items.items():
    for mesh in it["meshes"]:
        if mesh not in PMAN and mesh not in BMAN:
            errors.append(f"{iid}: unknown mesh {mesh}")

# ---------------------------------------------------------------- generated fit table
lua_names = set(re.findall(r"^\t(px_\w+) = \{", PM_LUAU, re.M))
if lua_names != set(PMAN):
    errors.append(f"Exit6PremiumMeshes.luau out of date: {sorted(lua_names ^ set(PMAN))}")
used_px = {m for it in items.values() for m in it["meshes"] if m.startswith("px_")}
for m in sorted(set(PMAN) - used_px):
    errors.append(f"premium mesh {m} is not used by any item")

# ---------------------------------------------------------------- products
products = {}
for sku, body in re.findall(r"^\t(\w+) = \{ name = (.*?)blurb = ", PREM, re.M | re.S):
    pid = int(re.search(r"productId = (\d+)", body).group(1))
    robux = int(re.search(r"robux = (\d+)", body).group(1))
    grants = re.findall(r'"(p_\w+)"', body.split("grants = {", 1)[1])
    products[sku] = {"pid": pid, "robux": robux, "grants": grants, "outfit": "outfit = true" in body}
order = re.findall(r'"(\w+)"', PREM.split("Premium.Order = {", 1)[1].split("}", 1)[0])
if sorted(order) != sorted(products):
    errors.append(f"Premium.Order does not list every product: {sorted(set(order) ^ set(products))}")
pids = [p["pid"] for p in products.values() if p["pid"] != 0]
if len(pids) != len(set(pids)):
    errors.append("duplicate developer product ids")
granted = {}
for sku, p in products.items():
    for g in p["grants"]:
        if g not in items:
            errors.append(f"{sku}: grants {g}, which is not a premium wardrobe item")
            continue
        granted.setdefault(g, []).append(sku)
        if items[g]["bundleOnly"] and not p["outfit"]:
            errors.append(f"{sku}: bundle-only {g} sold outside an outfit")
for iid in items:
    if iid not in granted:
        errors.append(f"{iid}: not granted by any product")

# ---------------------------------------------------------------- texture sets
for iid, body in re.findall(r'^premium\("(\w+)", \{(.*?)\}\)\n', section, re.M | re.S):
    pass
sets_needed = {PMAN[m]["tex"] for m in used_px}
for s in sorted(sets_needed):
    maps = UPLOADS["images"].get(s)
    if not maps or not {"color", "normal", "roughness"} <= set(maps):
        errors.append(f"texture set {s} has no uploaded maps")
for role, surf in role_surface.items():
    if surf not in UPLOADS["images"]:
        errors.append(f"role {role} uses surface {surf} with no uploads")


# ---------------------------------------------------------------- budgets
def tris(mesh):
    m = PMAN.get(mesh) or BMAN.get(mesh)
    part = m["part"]
    return m["triangles"] * (2 if part in LIMBS else 1)


print(f"{len(items)} premium items, {len(products)} products, {len(PMAN)} premium meshes")
print(f"{'product':16s} {'R$':>5s} {'id':>14s} {'tris':>7s}")
for sku in order:
    p = products[sku]
    total = sum(tris(m) for g in p["grants"] if g in items for m in items[g]["meshes"])
    print(f"{sku:16s} {p['robux']:5d} {p['pid'] or 'placeholder':>14} {total:7d}")
    if p["outfit"] and total > LOOK_BUDGET:
        errors.append(f"{sku}: {total} triangles over the {LOOK_BUDGET} look budget")

if errors:
    print("FAIL")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("PASS")
