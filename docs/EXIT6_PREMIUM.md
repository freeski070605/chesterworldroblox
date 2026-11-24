# EXIT 6 Premium (Robux cosmetics)

The Premium line sells original EXIT 6 meshes for Robux: jewelry, streetwear, sneakers, hair, and two complete outfits. It is built on the mesh wardrobe in [EXIT6_PLAYER_LOOK.md](EXIT6_PLAYER_LOOK.md): same fitting, slots, Closet and saves. It adds:

- PBR textures
- developer-product purchases with permanent entitlements
- a try-on boutique

**Style reference:** the EXIT 6 concept sheets (hero, female hero, premium cosmetics, clothing and footwear, hair lineup). Every mesh is generated from original geometry code:

- The "EXIT 6" lettering is hand-drawn glyph outlines, not font data.
- The concept sheets show a famous brand's mark on the sneakers. That mark is deliberately **not** reproduced. The sneaker carries an original hex patch with a raised "6".
- No designer trademarks are used.

## Catalog

Prices are **proposals for testing**. Product IDs are **placeholders (0)** until the owner creates the developer products.

| Product (`Exit6Premium` sku) | Proposed R$ | Grants (`Exit6Wardrobe` ids) | Mesh status |
| --- | --- | --- | --- |
| Diamond Cuban Chain (`cuban_diamond`) ★ | 399 | `p_cuban_diamond` | Real mesh, Studio-verified |
| Oversized Winter Puffer (`puffer`) ★ | 299 | `p_puffer_black` | Real mesh, Studio-verified |
| EXIT 6 High-Tops (`hightops`) ★ | 199 | `p_hightops` | Real mesh, Studio-verified |
| Long Locs (`long_locs`) ★ | 199 | `p_long_locs` | Real mesh, Studio-verified |
| Founder's Full Fit (`founders_fit`) ★ | 999 | puffer, **Founder's Stacked Cargos** (bundle only), high-tops, Cuban, watch, studs, locs, cap | Real meshes, Studio-verified |
| EXIT 6 Silver Pendant Chain (`pendant_silver`) | 149 | `p_pendant_silver` | Real mesh, Studio-verified (in VIP look) |
| Premium Tracksuit Set (`tracksuit`) | 349 | `p_track_top_black`, `p_track_pants_black` | Real mesh (new body, logo, panels; base-wardrobe sleeves and pants legs) |
| Designer Cornrows (`cornrows`) | 149 | `p_designer_cornrows` | Real mesh, Studio-verified (in VIP look) |
| Diamond Stud Earrings (`studs`) | 99 | `p_studs_diamond` | Real mesh (faceted), Studio-verified |
| Iced Luxury Watch (`watch`) | 249 | `p_watch_iced` | Real mesh, Studio-verified |
| Signature Fitted Cap (`cap`) | 99 | `p_cap_fitted` | Real mesh, Studio-verified |
| VIP Nightlife Outfit (`vip_nightlife`) | 599 | **Nightlife tracksuit** + **Midnight high-tops** (bundle only), silver pendant, watch, studs, cornrows | Real meshes, Studio-verified |

★ = flagship. Every catalog item has a real uploaded mesh. None is a concept or specification only.

## Assets (owner: user 10028644772)

All assets are owned by the experience owner's account. No DFB Solutions group ID is configured. If the experience moves to a group, re-upload under that group and update [uploads.json](../assets/wear/premium/uploads.json).

| Asset | Contents |
| --- | --- |
| `79525151931765` "Exit6 Premium v1" (Model) | 36 `px_*` meshes with UVs and tangents |
| `129965163941748` "Exit6 Premium patch 1" (Model) | 9 lighter meshes (puffer body, sleeves, cuff; cargo upper and lower; high-top base, overlay, sole) that replace the v1 copies |
| 26 Image assets | 8 PBR sets; IDs in `uploads.json` |

All 28 uploads were moderation **Approved**.

The texture sets are nylon, fleece, knit, leather, rubber, pave, metal, and locs. Each has color, normal, and roughness maps; pave and metal also have metalness.

**Installed in the place:**

- `ServerStorage.Exit6ProductionAssets.Wear.px_*` (36 templates)
- `ServerStorage.Exit6ProductionAssets.Surfaces.<set>` (8 SurfaceAppearances)

These live only in the place file. **The place must be saved or published for them to exist live.**

### Pipeline

1. `python tools/assets/build_premium.py`: meshes, then `assets/wear/premium/exit6_premium.glb`, `manifest.json`, and the generated `src/shared/Exit6PremiumMeshes.luau`.
   - Reuses the `build_wearables.py` helpers.
   - Adds glyph extrusion, faceted gems, region-clipped overlays, and a GLB writer that emits per-face box UVs and tangents.
2. `python tools/assets/build_premium_textures.py`: seamless 512 px maps in `assets/wear/premium/tex/`, plus a contact sheet at `build/premium_textures.png`.
3. `python tools/assets/render_premium_sheet.py`: offline fit check at `build/premium_sheet.png` and `premium_detail.png`. The image is mirrored, so lettering reads backwards there.
4. `python tools/assets/validate_premium.py`: catalog rules, mesh and texture coverage, and triangle budgets.
5. Upload only changed meshes: `build_premium.py --patch=a,b` writes `exit6_premium_patch.glb`.
6. Insert the uploads and run `tools/studio/install_exit6_premium.luau` (Edit). Record the new IDs there and in `uploads.json`.

Blender 4.5 is installed but not needed: the GLB comes straight from the generator, and the importer's 1:1 scale was verified (all 36 sizes match the manifest).

## How it works

### Rendering

- Premium pieces use the normal wardrobe fitting: scaled per R15 part, welded, rebuilt on respawn.
- Roles such as `shell`, `ice`, `silver`, and `leather` name a texture set. `Exit6Style` clones that SurfaceAppearance onto premium meshes only, then tints it per item with `SurfaceAppearance.Color`. One set therefore serves every colorway.
- If the sets are missing, or the mesh is a base-wardrobe mesh, the piece falls back to a plain Roblox material.

### Ownership

- **Purchases:** `Exit6Receipts` owns `MarketplaceService.ProcessReceipt` and routes it by product ID. `Exit6PremiumStore.server` writes the purchase to `Exit6Entitlements_v1/u_<userId>` with `UpdateAsync`. The write is idempotent on `PurchaseId`, and only then is `PurchaseGranted` returned.
- **Failure handling:** a failed write returns `NotProcessedYet`, so Roblox re-delivers the receipt. The newest 300 receipts are kept as an audit trail (sku, product, Robux, time).
- **One source of truth:** `Exit6Profile` never grants premium ownership from a save. After the profile loads, the store grants entitlements into the session. A tampered or old save that lists premium items renders nothing for them.
- **Rendering rule:** `Exit6Style` renders a premium item only if it is owned or being tried on.
- **Studio:** products with ID 0 can be test-bought through the same grant path. Studio uses a separate `_studio` DataStore, so test grants never reach live data. Live servers refuse ID-0 products ("Coming soon").
- **Unavailable items:** a product is never sold or tried on while any of its templates is missing (`Style.ItemReady`).

### Rules

- **Cosmetic only:** a grant may contain only premium wardrobe items without `repRequired`. Both the server and the validator enforce this.
- Robux never moves cash, reputation, vehicles, or any reputation-gated content. **There is no paid bypass of earned reputation.**
- Premium items use `store = "premium"`, so no Chester Cash counter can sell them. A direct `Purchase` call answers "Not sold here".

### Boutique (`Exit6Boutique.client`)

**Where to open it:**

- Phone, Closet tab: "Open the Premium boutique".
- A store's "EXIT 6 PREMIUM (ROBUX)" rows open it on that product:
  - Barbershops show hair.
  - Jewelers show jewelry.
  - Clothing stores show clothing, shoes, outfits, and jewelry.

**Controls:**

| Action | Gamepad | Keyboard / mouse |
| --- | --- | --- |
| Browse | D-pad | Arrows |
| Try on | Automatic when a row is selected (debounced) | Click a row |
| Buy or wear | A (buys; wears if owned) | Click the row again, or the button |
| Rotate | Right stick (auto-spins when idle) | Q / E or right-drag |
| Zoom | LT / RT | Mouse wheel |
| Close | B (restores the saved look) | Backspace |

**Behavior:**

- The camera frames the product: head, chest, wrist, feet, or full body.
- Movement is frozen while the boutique is open. The game has no `PlayerModule`, so it zeroes the local walk and jump, then restores them.
- The phone stops taking D-pad Up while the boutique is open.

### Outfits (loadouts)

- The Closet has 4 slots: "Save current fit as Outfit n" and "Wear Outfit n".
- They are saved in `style.outfits`.
- Wearing an outfit puts on only items the player still owns.

## Triangle budget and LOD

| Look | Triangles (both limbs counted) |
| --- | --- |
| Founder's Full Fit | 69,720 (budget 70,000; the v1 upload was 87k, so patch 1 lightened it) |
| VIP Nightlife | 60,568 |
| Tracksuit (mostly base meshes) | 32,252 |
| Heaviest single mesh | `px_hair_long_locs` 10,180 |

- Templates use `RenderFidelity = Automatic`, so distant players draw Roblox's generated LODs.
- Pieces under about 0.35 studs don't cast shadows.
- Every piece is welded, massless, and non-colliding.
- There are no separate hand-made LOD meshes; Roblox's automatic LOD is the LOD strategy.
- For reference, the heaviest base-wardrobe look is 58k.

## Not layered clothing

These are rigid MeshParts welded per R15 part, the same model as the base wardrobe. They move with animation (each piece follows its part) but do not deform across joints.

Layered clothing would need a cage that matches Roblox's reference cage topology and skinning. That is not generated here.

The game is R15. R6 characters get no pieces.

## Verification

| Check | Result |
| --- | --- |
| Static: items, products, grants, bundle-only, placeholder IDs, texture coverage, budgets | **PASS** (`validate_premium.py`); base `validate_wear.py` still **PASS** |
| Upload and import: 36 + 9 MeshParts, sizes = manifest (36/36 within 0.002), moderation Approved | **Studio-verified** |
| Founder's try-on through the real remote: 8 slots, 39 MeshParts, all welded / massless / non-colliding, 37 with tinted PBR | **Studio-verified**, with screenshots |
| Lettering reads "EXIT 6" on the cap, pendant, and sneaker "6" | **Studio-verified** |
| Refusals: equip unowned, wear unowned, cash-shop route for a premium id, buying an owned product | **Studio-verified** |
| Studio test purchase: granted, auto-worn, catalog shows owned | **Studio-verified** |
| Bundle purchase wears all 7 VIP pieces | **Studio-verified** |
| Tampered save claiming premium ownership: nothing renders; paid items re-granted | **Studio-verified** |
| Outfit save, then starter fit, then outfit wear; bad indexes refused | **Studio-verified** |
| Respawn rebuilds all slots; save round trip keeps the look | **Studio-verified** |
| Boutique opens: gamepad selection on the product, orbit camera, movement frozen | **Studio-verified** (state). The menu-to-boutique path was driven by script, not a real button press. |
| Real Robux purchase prompt and `ProcessReceipt` with a live product | **NOT TESTED**: no developer products exist yet |
| Entitlement DataStore writes | **NOT TESTED in Studio**: Studio API access is off, so the session ran unsaved. The write path is the code above. |
| Xbox: controller feel, frame time with several premium players, memory | **NOT TESTED** |
| Walking / driving with premium pieces | Welds follow the parts. **Not watched in motion.** |

## Owner checklist before live sale

1. Save or publish the place with `Wear.px_*` and `Surfaces` installed.
2. Creator Dashboard → Monetization → Developer Products: create one product per sku at your chosen price. Put each ID in `src/shared/Exit6Premium.luau` (`productId`).
3. Enable Studio API access to test DataStore persistence. A real prompt can only be tested in a live or team-test server.
4. Xbox: open the boutique from the phone (View → Closet) and from a clothing store, browse with the D-pad, rotate with the right stick, buy, then respawn and rejoin.
