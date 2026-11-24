# EXIT 6 player look (mesh wardrobe)

Players wear original EXIT 6 meshes (hair, clothing, shoes, headwear, jewelry) fitted on their own R15 body, bought in city stores, kept in a saved Closet, and rebuilt on every spawn. This replaces the part-built cuts/hats, the recoloured-limb "fits" and the development Hair Test collection.

## Audit: what was generic or placeholder (before)

| Area | Before | Problem |
| --- | --- | --- |
| Hair (sold) | `Exit6Style.buildHair`: balls and cylinders welded to the head | Read as blobs, not haircuts |
| Hair (Hair Test) | 12 OBJ meshes installed in `ServerStorage.Exit6ProductionAssets.Hair` | Authored around a 2-stud R6 head box. On the real R15 head (≈1.16 studs) the afro and braids rendered as side "wings" over a bald crown, and locs sat low. Free only, phone dev tab. |
| Hats | Ball + block parts | No brim shape, no detail |
| Tops / bottoms | Recoloured `UpperTorso`/limbs plus a few detail blocks | Avatar's own body under a tint, no silhouette |
| Shoes, jewelry, eyewear | None | — |
| Clothing / barber menus | Withheld (`clothing = { "fit_own" }`) | Nothing to buy |

## How it works now

- **Meshes:** `tools/assets/build_wearables.py` procedurally generates 61 original meshes, each in the local space of one R15 part at the default body's size (measured in Studio). Output: `assets/wear/exit6_wear.glb`, `assets/wear/manifest.json`, and the generated fit table `src/shared/Exit6WearMeshes.luau`.
- **Templates:** uploaded once as Model assets and installed as MeshParts in `ServerStorage.Exit6ProductionAssets.Wear.<mesh>` by `tools/studio/install_exit6_wear.luau`.
- **Catalog:** `src/shared/Exit6Wardrobe.luau` holds 65 items across 11 slots (hair, hat, top, bottom, shoes, chain, neck, watch, bracelet, ears, eyes). Each item lists its pieces (mesh + role) and colours. `Exit6Catalog` merges them as `kind = "wear"`.
- **Fitting:** `src/server/Exit6Style.luau` clones each piece and scales it by (part size ÷ canonical size), then welds it to that part. Feet are special-cased: the vertical scale is capped and the shoe is stood on the sole, so stylised tall feet don't get stretched boots. Each slot lives in its own folder on the character (`Exit6Look_<slot>`) and is rebuilt only when it changes. The avatar's own clothing and accessories under a worn slot are hidden, not deleted.
- **Rules:** fitted caps show short cuts and locs/braids (`showsUnderCap`) and hide tall styles. Beanies, durags and the ski mask hide hair. Chains and headphones move forward over hoodies and puffers (`depth`). Waistbands slim under any top.
- **Stores:**
  - Barbershops sell hair.
  - Clothing stores sell tops, bottoms, shoes, headwear, eyewear, headphones, and the jewelry.
  - Jewellers (`jewel`/`diamond` names, plus about a third of the fictional "Neighborhood Styles" fronts, which become "Chester Gold & Time") sell the jewelry only.
  - Buying grants ownership and wears the item; buying an owned item just wears it, for free.
- **Try-on:** at a counter, the first **A**/click tries the item on (server-side, session only). The row then reads `BUY $n`, and pressing again buys it. Leaving the counter, closing the menu or **B** puts the saved look back.
- **Closet** (phone tab, replaces Hair Test) lists owned items by slot:
  - **A** on an item wears it; **A** on a worn item takes it off.
  - "Put the starter fit back on" restores the free starter fit.
  - "Wear my Roblox avatar" clears every slot.
  - Rows are chained for the gamepad.
- **Save data:** `Exit6Profile.style = { v = 2, owned = {...}, <slot> = itemId }`. Import accepts only wearables valid for their slot, drops unknown ownership entries, and maps old ids through `Wardrobe.Legacy`; mapped ids count as owned. On the first v2 load everyone owns the starter fit (white tee, black joggers, white low-tops), and it is worn in any empty top, bottom or shoes slot.
- **Remotes:** `Exit6Remotes.StyleAction` (`preview` / `cancel` / `equip` / `unequip` / `avatar` / `starter`) is server-validated, rate-limited to 0.12 s, and checks menu and reach on preview and ownership on equip. `HairTestAction` is gone.

## Uploaded assets (owner: user 10028644772)

| Asset | Contents |
| --- | --- |
| `70526844842195` "Exit6 Wear v1" | All 61 meshes |
| `111400965165098` "Exit6 Wear patch 1" | `cap_emblem`, `pendant_six` (the "6" was mirrored in v1) and `hair_afro_taper` (rounder shape). These replace the v1 copies. |

The Roblox importer turns glTF geometry 180° about Y. `Exit6Style` compensates with `MESH_TURN`; do not rotate the templates.

### Changing or adding a mesh

1. Edit `build_wearables.py`, then run it.
2. Check `python tools/assets/render_wear_sheet.py` (writes `build/wear_sheet.png` and `build/wear_heads.png`). This offline render is mirrored left-right.
3. Run `python tools/assets/validate_wear.py`.
4. Upload only the changed meshes: `python tools/assets/build_wearables.py --patch=name,name` writes `assets/wear/exit6_wear_patch.glb`.
5. Insert the uploaded model and replace those templates in `ServerStorage.Exit6ProductionAssets.Wear`. Record the asset ID above and in the install script.

## Cost

| Measure (Studio Play) | Result |
| --- | --- |
| Heaviest look (11 slots) | 28 MeshParts, 66 instances, 58.4k source triangles, applied in 4.1 ms |
| Starter fit + medium locs | 13 MeshParts, 30 instances, 33.4k triangles |
| One-slot change | 0.5 ms (only that slot rebuilds) |
| Respawn rebuild | 0.3 s after appearance load |

Templates use `RenderFidelity = Automatic`, so distant characters draw lower LODs. Every piece has CanCollide, CanQuery and CanTouch off, Massless on, and is welded (not anchored). The largest meshes are `hair_shoulder_locs` (13.6k) and `hair_medium_locs` (11.6k).

## Verification

| Check | Result |
| --- | --- |
| Static: all meshes exist, items valid, legacy map, triangle limit | **PASS** (`validate_wear.py`) |
| Upload + import: 61/61 MeshParts, 1:1 scale, moderation Approved | **Studio-verified** |
| Fit on a non-default R15 avatar (thin arms, tall feet, dynamic head), 13 looks, front and side | **Studio-verified** (screenshots in session). Fixes from these checks: mirrored "6", boot scaling, waistband at hem, own hair under beanie. |
| Starter fit on first load; legacy save migration; save → load round-trip; tampered save rejected | **Studio-verified** |
| Try-on / cancel / off-menu refusal / buy (cash deducted) / re-buy owned (free) / equip, unequip, avatar, starter / unowned equip refused | **Studio-verified** via the real remotes |
| Respawn rebuilds every slot; all pieces welded, non-colliding, massless; own hair hidden | **Studio-verified** |
| Shop menu rows and gamepad hint | **Studio-verified** (structure). The button press path itself was not clicked in Studio. |
| Walking / driving / riding animation with pieces attached | Welds follow the parts. Clones were posed only; **not watched in motion** |
| Xbox: controller navigation, rendering, frame time, memory | **NOT TESTED** |
| Avatars with layered-clothing bodies, R6 rigs | Not tested. The game is R15; R6 characters would get no pieces. |

### Xbox checklist

The place must be saved or published with `ServerStorage.Exit6ProductionAssets.Wear` installed.

1. Spawn: you are in the starter fit.
2. Barbershop: **A** on a cut tries it on, **A** again buys it, and **B** reverts an unbought try-on.
3. Clothing store: try on and buy a hoodie, a fitted cap with locs, and a chain over a puffer.
4. Phone (**View** / **D-pad Up**) → Closet: D-pad through the rows, then wear and take off items. "Wear my Roblox avatar", then "Put the starter fit back on".
5. Respawn and rejoin: the look persists.
6. Walk, sprint, drive, ride a bike: look for floating or clipping pieces.
7. Stand in a group of players: watch frame time in the perf HUD.
