# Chester citywide visual audit

## Scope and limits

- 21,810 building/storefront rows represent 21,728 stable ChesterBuildingId/OBJECTID records across 86 nonempty BuildingTiles files. The game world has 102 tiles; 16 have no BuildingTiles file in this checkout.
- 364 storefront sections on 282 buildings across 47 building tiles; 1,374 storefront/commercial building-level records across 60 tiles.
- 175 storefront sections link to a local street image; 189 have no matched image. 172 were screened only as overview contact-sheet images, and 3 were examined full size. Overview screening cannot verify small signs, exact doors, colors or tenant identity.
- The 2025 aerial index and county GIS footprints are local references. Footprint centers, source orientations and projected game coordinates were joined by OBJECTID. A footprint match or nearest road is not facade proof. Three cropped aerial examples were visually checked; the rest of the city aerial coverage remains uninspected.
- 92 storefront sections have a tile centroid more than 5 m from the county footprint center; 102 have no matched county footprint. These are review flags, not certified placement errors.
- `confidence=probable` means an overview image and footprint position support a structure at the ID, **not** a verified frontage or facade. `unresolved` means an image exists but its view or geometry cannot support even that limited conclusion. `conflicting` records an observed source mismatch. All empty verified fields remain unknown.

## Source-grounded priority findings

- **93584, 9th / Kerlin / Concord:** A 2020-11 Google view shows a long low corner strip, glazed Concord-facing storefront and white painted side wall. It does not prove which unit is Boost Mobile, 5 Points Deli or J&S, nor the J&S front-lot position. The current tile combines Boost Mobile and J & S sections under one ID. Resolve separate parcel/building association and obtain a direct W 9th view before facade or door edits.
- **50221, US Gas:** A 2024-09 Google view visibly shows the US GAS canopy and a separate D & D Laundry fascia to its left. The tile assigns the laundry shop section to the US Gas building ID. Review the attached structures and separate footprints before any split or door placement.
- **189198, Shad Check Cashing & Wireless:** The 2026-04 Google view shows a two-story corner row building with brick upper story and pale painted ground floor. No legible Check Cashing sign or exact entrance is visible. The county address is 1200 W 9th Street, while US Gas 50221 is 610 W 9th Street; the supplied IDs do not establish that these two are attached.
- **Sherylynn at 9th & Lincoln:** No Sherylynn storefront name or stable ID appears in the current BuildingTiles or the matched local places CSV. The existing identity script records owner-provided W 9th frontage, but this audit cannot associate a current tile section or verify a door/image. Resolve source identity before placing it.
- **All corner stores:** Corner geometry was screened in available overview images. Exact corner entrances, two-face glazing, sign locations and unit boundaries remain open except the limited full-size observations above. Do not apply a nearest-road rule to them.

## Coverage by building tile

| Tile | Storefront sections | Linked images | Full-size reviews | Missing images | >5 m footprint flags |
|---|---:|---:|---:|---:|---:|
| tile_r02_c02.lua | 7 | 0 | 0 | 7 | 0 |
| tile_r03_c02.lua | 2 | 0 | 0 | 2 | 0 |
| tile_r03_c03.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r03_c04.lua | 2 | 2 | 0 | 0 | 2 |
| tile_r03_c05.lua | 2 | 0 | 0 | 2 | 2 |
| tile_r04_c03.lua | 7 | 0 | 0 | 7 | 0 |
| tile_r04_c04.lua | 19 | 19 | 0 | 0 | 4 |
| tile_r04_c05.lua | 16 | 15 | 0 | 1 | 7 |
| tile_r05_c03.lua | 2 | 1 | 0 | 1 | 0 |
| tile_r05_c04.lua | 10 | 10 | 0 | 0 | 3 |
| tile_r05_c05.lua | 3 | 2 | 0 | 1 | 1 |
| tile_r05_c06.lua | 4 | 4 | 0 | 0 | 1 |
| tile_r05_c07.lua | 6 | 6 | 0 | 0 | 1 |
| tile_r05_c08.lua | 1 | 1 | 0 | 0 | 0 |
| tile_r06_c03.lua | 2 | 0 | 0 | 2 | 1 |
| tile_r06_c04.lua | 2 | 0 | 0 | 2 | 0 |
| tile_r06_c05.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r06_c06.lua | 6 | 6 | 0 | 0 | 2 |
| tile_r06_c07.lua | 23 | 22 | 3 | 1 | 3 |
| tile_r06_c08.lua | 27 | 26 | 0 | 1 | 21 |
| tile_r07_c02.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r07_c05.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r07_c06.lua | 4 | 0 | 0 | 4 | 0 |
| tile_r07_c08.lua | 18 | 17 | 0 | 1 | 5 |
| tile_r07_c09.lua | 11 | 11 | 0 | 0 | 6 |
| tile_r07_c10.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r07_c11.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r08_c05.lua | 3 | 0 | 0 | 3 | 0 |
| tile_r08_c06.lua | 6 | 0 | 0 | 6 | 0 |
| tile_r08_c07.lua | 9 | 8 | 0 | 1 | 4 |
| tile_r08_c08.lua | 12 | 12 | 0 | 0 | 6 |
| tile_r08_c09.lua | 10 | 10 | 0 | 0 | 5 |
| tile_r08_c10.lua | 14 | 0 | 0 | 14 | 0 |
| tile_r08_c11.lua | 1 | 0 | 0 | 1 | 0 |
| tile_r09_c05.lua | 13 | 0 | 0 | 13 | 6 |
| tile_r09_c06.lua | 15 | 0 | 0 | 15 | 2 |
| tile_r09_c07.lua | 3 | 3 | 0 | 0 | 1 |
| tile_r09_c08.lua | 3 | 0 | 0 | 3 | 0 |
| tile_r09_c09.lua | 7 | 0 | 0 | 7 | 0 |
| tile_r09_c10.lua | 20 | 0 | 0 | 20 | 0 |
| tile_r09_c11.lua | 2 | 0 | 0 | 2 | 0 |
| tile_r10_c03.lua | 2 | 0 | 0 | 2 | 0 |
| tile_r10_c04.lua | 20 | 0 | 0 | 20 | 3 |
| tile_r10_c05.lua | 26 | 0 | 0 | 26 | 4 |
| tile_r10_c10.lua | 12 | 0 | 0 | 12 | 0 |
| tile_r11_c04.lua | 4 | 0 | 0 | 4 | 2 |
| tile_r11_c10.lua | 2 | 0 | 0 | 2 | 0 |

## Reconstruction queue

1. Resolve the named 9th Street and Kerlin source-ID/tenant conflicts with direct photos and parcel boundaries.
2. Review storefront sections with >5 m centroid differences and any missing county footprint.
3. Inspect each linked full-size photo plus aerial/footprint before entering a verified frontage, door, sign or facade correction.
4. Keep imagery-missing sections and uninspected building photos as unknown until local evidence exists.

This pass changed no BuildingTiles, runtime placement, doors, signs, roads, player data or gameplay. Images remain on the local E: drive and are not committed.
