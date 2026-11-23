# Chester neighborhood visual audit

## Scope and evidence limits

- 18,636 residential, garage and possible mixed-use records in 79 BuildingTiles files; 21,810 total building/storefront report rows.
- 4,539 records have a linked local street photo; 14,097 do not. 826 photos were examined full size and have observation fields; 7 more were screened only in an overview sheet. All other photo links are **unverified**.
- Local 2025 aerial tiles and county footprints were joined by stable OBJECTID. Aerial tile availability is not a claim of visual inspection. Only two example footprints (13452 and 8154) were visually checked against cropped aerials.
- The 102-tile world has 86 nonempty BuildingTiles files in this checkout. Tile cells are coverage units; no authoritative neighborhood boundary file was found in the supplied sources, so municipal and tile counts below are used rather than invented neighborhood names.
- GIS archetypes, story estimates, row clusters, footprint dimensions and tile styles are **estimates or existing game data**, not visually confirmed facts. Blank observation fields mean unknown.
- Vacant parcels cannot be enumerated from a building-footprint dataset. Alley access, setbacks, yards, fences, corner entrances and road-facing doors are unknown except where a cited full-size photo states a visible fact.

## Counts

- Existing styles: {'garage': 3250, 'house': 11056, 'commercial': 259, 'rowhouse': 2040, 'twin': 649, 'storefront': 767, 'apartment': 614, 'generic': 1}. Scope: {'garage_outbuilding': 3250, 'residential': 14359, 'mixed_use_candidate': 1026, 'GIS_residential_candidate': 1}. Mixed-use is a candidate class, not a verified dwelling.
- 358 records have a tile centroid more than 5 m from the county footprint center; these are geometric review flags, not verified errors.
- Source IDs are unchanged. No tiles, HouseKit, runtime placement, doors or gameplay were edited.

## Image-supported priorities

- **13452:** a one-story lane-facing garage with a gabled shingle roof and chain-link side gate is represented as a twin. The aerial shows a small detached footprint. Resolve parcel association before changing the type.
- **8154:** street imagery shows a continuous two-story porch-front row, while the game uses an apartment form and the county footprint spans part of the run. Resolve per-house extent and entrances.
- **20770:** two front doors and a shared two-story mass are visible; county archetype says detached house. Review twin/attached segmentation.
- **4066:** several front entrances in a connected mass call for parcel and entrance review.
- **18556:** photographed corner masonry home has a stoop and bay windows; the other street face is unseen, so corner-entry direction remains unknown.

## Municipality coverage

| Municipality | Records | Linked photos | Full-size reviews | Missing photos | Placement flags >5m |
|---|---:|---:|---:|---:|---:|
| Brookhaven Borough | 3774 | 0 | 0 | 3774 | 46 |
| Chester City | 5543 | 4539 | 826 | 1004 | 260 |
| Chester Township | 797 | 0 | 0 | 797 | 52 |
| Eddystone Borough | 676 | 0 | 0 | 676 | 0 |
| Marcus Hook Borough | 854 | 0 | 0 | 854 | 0 |
| Parkside Borough | 967 | 0 | 0 | 967 | 0 |
| Trainer Borough | 1164 | 0 | 0 | 1164 | 0 |
| Upland Borough | 992 | 0 | 0 | 992 | 0 |
| Woodlyn CDP | 3869 | 0 | 0 | 3869 | 0 |

## Tile coverage (neighborhood proxy)

| Building tile | Records | Linked photos | Full-size reviews | Missing photos | Placement flags >5m |
|---|---:|---:|---:|---:|---:|
| tile_r00_c01.lua | 69 | 0 | 0 | 69 | 0 |
| tile_r00_c02.lua | 3 | 0 | 0 | 3 | 0 |
| tile_r01_c00.lua | 75 | 0 | 0 | 75 | 0 |
| tile_r01_c01.lua | 85 | 0 | 0 | 85 | 0 |
| tile_r01_c02.lua | 162 | 0 | 0 | 162 | 0 |
| tile_r01_c03.lua | 21 | 0 | 0 | 21 | 0 |
| tile_r02_c00.lua | 3 | 0 | 0 | 3 | 0 |
| tile_r02_c01.lua | 72 | 0 | 0 | 72 | 0 |
| tile_r02_c02.lua | 285 | 0 | 0 | 285 | 0 |
| tile_r02_c03.lua | 91 | 0 | 0 | 91 | 0 |
| tile_r02_c04.lua | 11 | 0 | 0 | 11 | 0 |
| tile_r03_c02.lua | 154 | 0 | 0 | 154 | 0 |
| tile_r03_c03.lua | 218 | 0 | 0 | 218 | 0 |
| tile_r03_c04.lua | 107 | 5 | 3 | 102 | 0 |
| tile_r03_c05.lua | 2 | 0 | 0 | 2 | 0 |
| tile_r04_c02.lua | 68 | 0 | 0 | 68 | 0 |
| tile_r04_c03.lua | 606 | 47 | 3 | 559 | 2 |
| tile_r04_c04.lua | 312 | 271 | 43 | 41 | 13 |
| tile_r04_c05.lua | 273 | 215 | 44 | 58 | 11 |
| tile_r04_c06.lua | 21 | 19 | 8 | 2 | 3 |
| tile_r05_c03.lua | 102 | 43 | 0 | 59 | 5 |
| tile_r05_c04.lua | 444 | 283 | 2 | 161 | 27 |
| tile_r05_c05.lua | 382 | 185 | 10 | 197 | 15 |
| tile_r05_c06.lua | 207 | 178 | 29 | 29 | 13 |
| tile_r05_c07.lua | 111 | 87 | 59 | 24 | 7 |
| tile_r06_c03.lua | 141 | 0 | 0 | 141 | 1 |
| tile_r06_c04.lua | 224 | 11 | 0 | 213 | 11 |
| tile_r06_c05.lua | 192 | 94 | 1 | 98 | 5 |
| tile_r06_c06.lua | 291 | 239 | 141 | 52 | 22 |
| tile_r06_c07.lua | 467 | 409 | 306 | 58 | 27 |
| tile_r06_c08.lua | 112 | 88 | 14 | 24 | 6 |
| tile_r06_c10.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r07_c03.lua | 3 | 0 | 0 | 3 | 0 |
| tile_r07_c04.lua | 135 | 0 | 0 | 135 | 23 |
| tile_r07_c05.lua | 186 | 0 | 0 | 186 | 12 |
| tile_r07_c06.lua | 286 | 46 | 33 | 240 | 2 |
| tile_r07_c07.lua | 107 | 55 | 42 | 52 | 8 |
| tile_r07_c08.lua | 229 | 188 | 21 | 41 | 19 |
| tile_r07_c09.lua | 142 | 112 | 25 | 30 | 8 |
| tile_r07_c10.lua | 92 | 0 | 0 | 92 | 0 |
| tile_r07_c11.lua | 9 | 0 | 0 | 9 | 0 |
| tile_r07_c12.lua | 22 | 0 | 0 | 22 | 0 |
| tile_r08_c02.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r08_c04.lua | 38 | 0 | 0 | 38 | 5 |
| tile_r08_c05.lua | 756 | 0 | 0 | 756 | 2 |
| tile_r08_c06.lua | 686 | 79 | 0 | 607 | 1 |
| tile_r08_c07.lua | 453 | 318 | 12 | 135 | 16 |
| tile_r08_c08.lua | 233 | 186 | 3 | 47 | 6 |
| tile_r08_c09.lua | 249 | 222 | 7 | 27 | 24 |
| tile_r08_c10.lua | 401 | 0 | 0 | 401 | 0 |
| tile_r08_c11.lua | 50 | 0 | 0 | 50 | 0 |
| tile_r08_c12.lua | 77 | 0 | 0 | 77 | 0 |
| tile_r09_c03.lua | 267 | 0 | 0 | 267 | 2 |
| tile_r09_c04.lua | 510 | 0 | 0 | 510 | 7 |
| tile_r09_c05.lua | 827 | 0 | 0 | 827 | 4 |
| tile_r09_c06.lua | 1096 | 143 | 0 | 953 | 3 |
| tile_r09_c07.lua | 568 | 473 | 1 | 95 | 10 |
| tile_r09_c08.lua | 503 | 407 | 19 | 96 | 6 |
| tile_r09_c09.lua | 277 | 63 | 0 | 214 | 4 |
| tile_r09_c10.lua | 149 | 0 | 0 | 149 | 0 |
| tile_r09_c11.lua | 171 | 0 | 0 | 171 | 0 |
| tile_r10_c03.lua | 255 | 0 | 0 | 255 | 3 |
| tile_r10_c04.lua | 265 | 0 | 0 | 265 | 4 |
| tile_r10_c05.lua | 360 | 0 | 0 | 360 | 3 |
| tile_r10_c06.lua | 186 | 23 | 0 | 163 | 2 |
| tile_r10_c08.lua | 67 | 50 | 0 | 17 | 2 |
| tile_r10_c09.lua | 170 | 0 | 0 | 170 | 0 |
| tile_r10_c10.lua | 615 | 0 | 0 | 615 | 0 |
| tile_r10_c11.lua | 136 | 0 | 0 | 136 | 0 |
| tile_r11_c04.lua | 42 | 0 | 0 | 42 | 7 |
| tile_r11_c05.lua | 250 | 0 | 0 | 250 | 7 |
| tile_r11_c09.lua | 256 | 0 | 0 | 256 | 0 |
| tile_r11_c10.lua | 831 | 0 | 0 | 831 | 0 |
| tile_r11_c11.lua | 448 | 0 | 0 | 448 | 0 |
| tile_r12_c05.lua | 10 | 0 | 0 | 10 | 0 |
| tile_r12_c09.lua | 486 | 0 | 0 | 486 | 0 |
| tile_r12_c10.lua | 357 | 0 | 0 | 357 | 0 |
| tile_r12_c11.lua | 20 | 0 | 0 | 20 | 0 |
| tile_r13_c10.lua | 47 | 0 | 0 | 47 | 0 |

## Staged reconstruction use

Work from full-size image and aerial citations in the CSV. Review type conflicts and large position deltas first, then fill entrance, roof, facade, garage, yard, fence and setback fields only where visible. Missing or obscured facts remain unknown. Preserve ChesterBuildingId/OBJECTID while resolving conflicts.
