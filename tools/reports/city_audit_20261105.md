# ChesterWorld city audit (2026-11-05)

Method: live Studio play run on the real terrain (inventory of every built part,
screenshots at downtown/City Hall, 8th & Kerlin rowhouses, Subaru Park waterfront),
the tile data in `src/shared/WorldData/Tiles`, and the source data in
`E:\ChesterWorld\Data`, compared with the DVRPC 2025 orthophoto
(`tools/harness/crossing_aerial.py`, images in `build/aerial`).

## What the game builds today

| Built content | Parts | State |
|---|---|---|
| Terrain (land layout) | - | correct (user-confirmed) |
| Roads / intersections / markings / sidewalks | 37.5k / 33.3k / 37.0k / 50.6k | broadly right; highways audited separately |
| Street signs | 597 | present |
| Buildings | 21.7k | **plain grey boxes; most of Chester missing** |
| Highway structures | 12.1k | done (highway audit) |
| Trees, parks, water, parking, rail, landmarks, props | 0 | **nothing built** |

## Findings, worst first

1. **Building data is complete; the rendering is not.** (Corrected: an earlier note here
   said most buildings were missing. That compared mismatched extents. Overlaying the
   footprints on the aerial (`tools/harness/buildings_overlay.py`) shows the county
   layer covers almost every building; a rowhouse row is one footprint, so counts look
   low. Overture Maps 2026-10-21 (30,787 in the bbox) adds almost nothing inside the
   world boundary (`build/aerial/overture_extras_map.png`); its lidar heights can
   fill the 5,709 county buildings stuck at the default height.)
2. **Every building is one rotated box.** The tile packer keeps only width/depth/yaw of
   each footprint; 2/3 of footprints are not rectangles (L-shapes, row blocks, the
   stadium). 205 boxes exceed 5,000 m2: Subaru Park is a solid 764x449x95-stud block.
   Heights: 5,709 buildings use the 9.15 m default; the source has `BuildingHeightM`
   and story probabilities for most others.
3. **No building identity.** All the same material and colour; no roofs, windows, or
   type (rowhouse / church / school / warehouse / commercial). Source data for type
   exists and is unused: OSM POI areas (534) and points (1,121), address areas (366),
   zoning (37 districts), schools (9), parks (43).
4. **The ground is bare.** One terrain material everywhere; no grass/lawn vs paved
   lots vs dirt. Unused: OSM land use (417 areas incl. parking), parks (43).
5. **No vegetation.** Tree canopy masks exist (`12_Vegetation/Canopy_2013`, 30 tiles);
   the aerial shows street trees and wooded lots everywhere.
6. **No water features.** Streams (15) and water polygons (8): Chester Creek,
   Ridley Creek, the Delaware waterfront.
7. **No rail.** Amtrak NEC / CSX / Conrail lines exist only as road-like strips; no
   ballast, rails, or catenary. PennDOT rail layer (30) unused.
8. **Atmosphere.** Default sky; the view fogs out a few hundred studs away
   (streaming radius + atmosphere), so the city reads as empty from any height.
9. **No street life.** No lights, poles, hydrants, benches, cars, or fences; the aerial
   is full of parked cars, poles and chain-link.

## Plan (each step is a generator pass, verified in Studio through the MCP)

| # | Step | Data | Effort |
|---|---|---|---|
| 1 | **Heights**: fill the 5,709 default-height buildings from overlapping Overture lidar heights | Overture 2026-10-21 (downloaded) | small |
| 2 | **Real footprints**: pack polygons into the tiles and build each building as its footprint (rectangle decomposition / wedge prisms), real heights, flat or pitched roofs by size | county footprints + `BuildingHeightM` | medium |
| 3 | **Building types + looks**: classify (rowhouse, detached house, church, school, commercial, industrial, civic) from POI/zoning/size/shape; per-type material, colour palette, roof, window bands | POI, zoning, footprint shape | medium |
| 4 | **Ground cover**: paint terrain materials from land use: grass for lawns/parks, asphalt for parking, concrete for plazas, mud/sand at the waterfront | land use, parks | small |
| 5 | **Trees** from the canopy masks plus street trees along residential streets | canopy masks | small |
| 6 | **Water**: creeks and river as terrain water | streams, water polygons | small |
| 7 | **Rail**: ballast + rails along the rail lines; catenary on the NEC | rail layer | small |
| 8 | **Atmosphere + streaming**: lighting preset, atmosphere, larger streaming radius / low-detail distant buildings | - | small |
| 9 | **Street dressing**: street lights, poles, hydrants, parked cars on residential streets | road graph | medium |
| 10 | **Landmarks**: hand-detailed City Hall, Subaru Park, Harrah's, Widener, Barry Bridge | aerial reference | per item |

All steps use data already on disk (Overture downloaded 2026-11-05 to
`E:\ChesterWorld\Data\01_Buildings`). Steps 2-4 change the city the most.

Environment: C: has 24 MB free. Studio and Windows need headroom; free space on C:
before long Studio sessions. Tooling here keeps its caches on E: (`build/duckdb`).

## Progress (2026-11-05)

- Step 2/3 (footprints + building looks) implemented:
  `tools/build_building_tiles.py` writes `src/shared/WorldData/BuildingTiles/<tile>.lua`
  (21,757 buildings -> 48,652 rectangles along each building's axis, positions matching
  the old tiles to 2 cm). Styles: house 10,946, garage 3,258, rowhouse 2,318 (merged
  rows recognised by shape), generic 1,486, storefront 1,104, industrial 705,
  apartment 615, twin 540, commercial 419, warehouse 207, church 86, school 73.
  TileBuilderV2 builds each as a Model: walls per rectangle (foundation to lowest
  corner), gable roofs for houses/twins/churches, cornice caps for rows/storefronts/
  commercial, per-style material and palette. Old tile modules untouched; a building
  without a shape falls back to its box.
- Studio run 1: 21,467 footprint buildings / 93,428 parts; 8th & Kerlin reads as brick
  rows and gabled houses. Fixed after it: Luau string escaping in two tiles; Metal
  material (looked like blue glass) replaced; more brick downtown.
- Blocked: run 2 ended mid-build (40/102 tiles) with no script error, and Rojo stopped
  syncing. C: had 13 MB free. Free space on C: before the next run.
- Step 4 (ground cover) baked into the place terrain: PASDA 2013 1 m land cover
  (Chester City, Chester Twp, Brookhaven) -> 3 m majority grid
  (`tools/build_ground_cover.py`, 26 tiles, 1.12 M runs) -> surface voxel materials
  (`tools/studio/bake_ground_cover.luau`, run through the MCP over a local HTTP server):
  grass -> Grass, tree canopy -> LeafyGrass, paved/structures -> Pavement,
  roads -> Asphalt, water edges -> Mud, barren -> Ground. Occupancy written back
  unchanged (shape untouched). ~18k blocks, ~2.5 min. Terrain material colours tuned.
  Persists only when the place is saved; ChangeHistory waypoint "Before ground cover bake".
  Not covered by the land cover (regional ring outside those three municipalities):
  still plain Ground.
- Roof colours: DVRPC 2025 orthophoto mosaic at 1 m (`tools/fetch_aerial_mosaic.py`, 56 tiles,
  `E:\ChesterWorld\Data\19_Aerial`); each footprint's median roof colour (inset 0.8 m,
  darkest fifth dropped) -> `rc=` in BuildingTiles; all 21,757 buildings measured. Builder
  uses it for gable roofs, cornice caps and a roof slab on flat roofs.
- Parks (step 10a): `tools/build_parks.py` -> `src/shared/WorldData/Parks.lua` (50 parks,
  41 named; 95 OSM features) built by `ParkBuilder.server.lua`: name signs at the
  road-side edge, inset walking loops with benches and lamps, basketball/tennis/volleyball
  courts, baseball diamonds, soccer/football pitches, athletics tracks, playgrounds,
  pools, cemetery headstones. Features sit at the highest ground under them with a skirt
  so slopes neither bury nor float them. Studio: 18,265 parts, no errors.
- Facades: three window textures drawn by `tools/make_facade_textures.py` (residential
  double-hung, commercial three-pane, industrial strip; transparent around the window),
  uploaded to the user's Roblox account (rbxassetid://87121421598977 /
  125405099207126 / 112532330474936). TileBuilderV2 tiles them on each wall face
  (bay 8 or 12 studs, storey = height / floors, clamped 8-13), from the roofline down;
  garages and churches stay plain. Studio: 161,806 textures, no errors.
- Ground storeys: door+window (rbxassetid://134036168835861) for rowhouse/twin/house/
  apartment, shopfront with sign band (rbxassetid://113770832567908) for storefront/
  commercial. Walls split into a ground storey (exactly one texture tile tall from street
  level) and upper floors (window texture); a concrete foundation fills sloping lots.
  Studio: 22,337 ground storeys, 158,803 building parts total, no errors.
- Landmarks (step 10): `tools/build_landmarks.py` -> `src/shared/WorldData/Landmarks.lua`
  (OSM area outline, oriented box and county building ids per landmark), built by
  `LandmarkBuilder.server.lua` after the highway finish: City Hall (brick, white portico
  on the street face, cupola, sign), Widener Old Main (stone, mansard, clock tower),
  Deshong Museum (marble temple front), Subaru Park (9 footprint boxes replaced: pitch,
  navy/gold tiers, canopies, outer wall, scoreboard; terrain cleared above pitch level),
  Quick Stadium (football field, track, stands), Harrah's (dark casino, neon band, sign)
  plus the harness track measured off the orthophoto, Commodore Barry Bridge (deck from
  the approach road across the river, cantilever through-truss over the main span,
  piers, closed at the world edge), and signed restyles of Chester High, Crozer North,
  Crozer Building, Wolfgram Library and the Wharf at Rivertown. Studio: 13 built,
  1,666 parts, no errors. Verified by screenshot: Subaru Park, the bridge, the racetrack,
  City Hall's portico/sign; Old Main, Deshong and the restyles not yet inspected close up.
