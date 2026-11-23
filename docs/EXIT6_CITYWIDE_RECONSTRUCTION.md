# Exit 6 citywide reconstruction — rollout

## Why this exists
A building can be close to its original county footprint yet have the wrong storefront edge, mislabeled business, disconnected gameplay anchor, or a speculative shape. Stop fixing isolated signs and stores by searching UI names. Apply a consistent, source-traceable correction pipeline to all 102 tiles.

## Existing work to integrate (NOT blindly merge)
- Draft PR #4, branch `feature/chester-reconstruction-pilot`: 47 OSM polygons, 36 high-threshold matches, 10 review, 1 unmatched at 9th/Kerlin, opt-in noncolliding geometry preview, HouseKit roofs and walls.
- Existing `World/RealBuildings.lua`: shops can already carry street-front bearings and stable county building IDs. Keep those IDs stable.
- Original street index & building tiles are in the 3-studs/m source projection, world +X east / -Z north; source geometry coordinates must use exactly the project transform.
- Never infer exact front doors, business names, building height, or roof shapes solely from an OSM footprint.

## Workstream and gates
1. **Audit and manifest:** For every building, capture source polygon/county ID, existing placement, matching confidence, business names, entrance edge(s), road/sidewalk relation, corner status and confidence. Record evidence/attribution and unresolved cases. Produce machine-readable conflicts per tile.
2. **Frontage:** Use verified address, street imagery, entrance evidence and road relation to select side. A corner business may have two front faces. Do not use nearest road alone as ground truth.
3. **Geometry:** Rebuild only approved geometry within parcel polygon, ground-matched, with collision checks and no road overlap. Preserve indoor/shop links via stable ID.
4. **Named anchor corrections:** J&S at 9th/Kerlin/Concord is a **front lot placement in front of Boost Mobile and 5 Points Deli, facing W 9th**, not alongside or behind. Record parcel polygon and explicit coordinates; no hardcoded guessed marker. Check Cashing faces W 9th as an attached but independently interactive business. Street signs and light poles require sidewalk clearance.
5. **Progressive rollout:** 9th/Kerlin pilot; then district batches, never swap the entire 102-tile city without geometry and gameplay tests.
6. **Performance:** Part budgets, loading milestones, StreamingEnabled, network/physics impact, Xbox driving and business prompts. Reject improvements that make city startup hang.
7. **Bike Life:** Preserve bikes, quads, car garage, profile, phone, reputation gates and existing terrain. Building reconstruction is not a road/highway work restart.

## New audit: status and use
`src/server/World/BuildingFrontageAudit.server.luau` is a **read-only opt-in diagnostic** and does NOT automatically repair frontages.

In Studio, with this branch Rojo-synced, set Workspace boolean attribute `CW_FrontageAudit` to `true` before Play, then review Output `[CW FrontageAudit]`. It checks existing tagged shops/gas stations, measures whether storefront anchors point toward the nearest generated named road, and prints at most 80 suspicious candidates with building IDs and X/Z. It treats a wrong-facing nearest road as **review needed**, not a verified error (corner stores may face a different named road). Attribute absent/false incurs no scan.

## Status
- Pilot geometry and matching lives on separate draft branch and is not merged into the playable game.
- This branch has the read-only audit, but **has not executed in Roblox Studio** and no citywide replacements are approved.
- Exact business-to-parcel assignments and verified storefront-facing images remain to be collected/checked before automatic repairs.

## Citywide batch queue — no more one-store-at-a-time patching

The current source already includes 86 nonempty BuildingTiles files for the
102-tile game, plus local county footprints, street-view references and visual
audits. The queue is **not** proof that all 21k+ buildings have been visually
verified: it identifies missing or conflicting observations in batches by tile.

From the checked-out repository on the Windows development machine:

```powershell
cd E:\code\chesterworld-roblox
py -3 tools/storefronts/citywide_visual_audit.py
py -3 tools/reconstruction/citywide_residential_audit.py
py -3 tools/reconstruction/property_evidence.py --all
py -3 tools/reconstruction/citywide_batch_queue.py --batch-size 50
py -3 -m unittest discover -s tools/reconstruction -p test_citywide_batch_queue.py -v
```

Outputs (git-ignored, keep private imagery on E:):
- `build/citywide_reconstruction_queue.csv`: sortable property-by-property,
  including batch, stable county building ID, business identity and evidence flags
- `build/citywide_reconstruction_queue.json`: tile batches and source/photo
  references for automated downstream checks
- `build/citywide_reconstruction_queue.md`: ranked tile-level work schedule

Queue processing is geographic: for a single batch, verify **both sides of the
block, street edges, sidewalks, corner stores, lots, roofs, porches, houses and
shop entrances** from full-size sources before approving geometry. Correct the
source association and regenerate the matching geometry. Never infer a tenant
from nearest-road or centroid matching alone. Multiple storefront sections
under one county ID remain linked for parcel review (e.g., 50221 or 133692).

**Hard performance requirement:** `TileBuilderV2` must continue sending
residential `Exit6Kit` metadata to the near-client house decorator. No
citywide or neighborhood-wide server-side HouseKit mass spawning. Keep stores,
vehicle ownership, roads, and buildings' stable IDs intact. Test the same
scene in Studio and on Xbox after an approved geographic batch; source-level
checks alone are not visual verification.

777 Food Market `147448` has been visually confirmed by the user as fixed.

## 2026-11-23: why visual coverage looked so low, and the batch workflow

`tools/harness/coverage_bottleneck.py` reproduces the diagnosis.

- **Counts were hard-coded.** `full_size` came only from hand-written dicts
  in the two audit scripts (3 storefront + 5 residential IDs). The 602
  ray-verified full-size reviews in `tools/reconstruction/pose_reviews.csv`
  (601 already applied in `PropertyReconstruction.lua`) were never counted.
- **Images existed but were marked not_inspected.** 5,460 Google building
  photos plus 582 Mapillary photos, with no broken paths. 4,423 county
  footprints have a ray-centred photo of their own front wall.
- **One manifest row per ID, own photo only.** A building seen only in a
  neighbour's photo was `imagery_missing`. The ray caster finds 194 such
  rows; most photos show 2-3 buildings (2,558 show two, 1,188 three).
  Mapillary keeps 185 extra photos that a dict keyed on OBJECTID dropped.
- **Mixed totals.** The "storefront" confidence counts were all 21,810
  rows (every house plus 82 extra shop-section rows), not the 364 sections.
- **Not in the audits at all:** 887 KerlinPrototype Google captures
  (`E:\ChesterWorld\ChesterWorldMapData\KerlinPrototype\03_ReconstructionReferences_Google`,
  8 views x 111 buildings), 1,387 Kerlin Mapillary frames, 745 KartaView
  (highways only).
- **86 vs 87 tiles.** The extra queue group is `unmatched`: 29 county
  OBJECTIDs with no BuildingTiles entry. 13 are Barry Bridge structure
  slivers (0-14 m2, height 0), 9 lie outside Chester City, and the rest are
  sub-15 m2 fragments, except 70596 (1,297 m2, 12.3 m, near the Barry
  Bridge approach), 105029 (405 m2, 38.6 m: bridge pier/tower) and 117265.
  This is footprint filtering, not a missing map tile; 70596 is the one
  genuine candidate for a missing building.

### Batch review (`tools/reconstruction/batch_review.py`)

1. `sheets --tiles r06_c07 --name b01` writes 2x2 sheets at native 640 px
   of every building whose own front is ray-centred (share >= 0.25).
2. Look at every sheet. Write one verdict line per cell (style, arch,
   units, roof, porch, floors, bay, garage bays, wall hex[:material],
   confidence, notes), or `SKIP` when the photo does not support a verdict
   (tree, blur, rear or side wall, low share, vacant lot, shop identity).
3. `apply` appends to `pose_reviews.csv` with the photo, heading and share,
   and logs every cell, SKIPs included, to `docs/batch_review_log.csv`.
4. `property_evidence.py --reviewed` regenerates the runtime module.

Batches applied on 2026-11-23 (535 photos inspected, 351 structures set,
184 skipped, 219 type corrections vs the tile):

| Batch | Area | Inspected | Applied |
|---|---|---:|---:|
| b01 r06_c07 | 9th/Kerlin tile, both sides of all streets | 269 | 202 |
| b02 r06_c06 | Lincoln/Concord side, Carlas Lane estate | 128 | 71 |
| b03 r05_c07 | W 2nd-5th, Lloyd, Pennell, riverside | 84 | 39 |
| b04 r07_c06+c07 | Butler/Kerlin/Parker 1000-1400, Villa Dr, W 11th-14th | 54 | 39 |

The most common correction was a 3-storey "rowhouse" that the photo shows
is a 2-storey porch twin (112 cases). `spec floors=N` now sets the storey
split for every style (TileBuilderV2), not only HouseKit homes.

NY Fried Chicken `111566` (1039 Kerlin, OSM node 5696730964 inside the
footprint) was rebuilt from four 2024-09 views. The door, awning, blade
sign and oriel are on the Kerlin face, and the W 11th wall is a side wall.

### Still unverified / open

- Vacant lots seen in photos that the tiles still build on: 122482,
  169550, 122555, 203072, 34448. These need an aerial check before removal.
- Store identities skipped for a store pass: Stop One Deli 203108, Koch's
  Food Market 65797, the 189198 Check Cashing corner, the corner shops
  29515 and 146770, and the 3105 W 9th "NYFC & Grill" (not modelled).
- 3278 (W 2nd factory) is 3 storeys; the tile says 2.
- 916 Kerlin: photo 58063 (heading 356) shows Krispy Krunchy on the left
  and Eagle on the right, which matches GasStationBuilder (locked by
  `test_batch_reviews`).
- Batches b02-b04 were checked at source level and through the same
  runtime path Play-tested with b01. They have not each been rendered in
  Studio. The Xbox session test is still owed.
