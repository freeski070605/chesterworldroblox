# W 9th Street, Lincoln to Concord/five-point junction

Scope: county polygons intersecting lon -75.37465..-75.37020, lat
39.84720..39.84870 (both W 9th frontages plus the 8th-to-10th blocks), 68
ChesterBuildingIds (county OBJECTIDs). All 102 tiles, IDs, rentals, stores
and the Exit 6 Motors forecourt are unchanged in placement.

## Pipeline (repeatable, block by block)

`tools/reconstruction/property_evidence.py`

1. Indexes every county footprint (source metres, same frame as the tiles).
2. Frontage: each wall's outward normal is probed toward the county road
   centrelines (Delaware County RCL). The primary street is the nearest
   street weighted by wall length and road class. Corner = more than one
   street. The address is interpolated from the centreline address range.
3. Party walls: county polygons that share 2 m of wall or more.
4. Every camera pose in the Street View and Mapillary manifests casts 41
   rays across its field of view. The nearest polygon hit per ray wins, so
   occlusion is modelled. Each photo is attached to EVERY building it shows,
   with its field-of-view share, whether it is centred, and which wall
   (front, side or rear relative to that building's frontage) it sees. A
   photo downloaded "for" one ID that actually centres on a neighbour gets
   the verdict `views_other:<id>`.
5. Observations are kept side by side and never overwritten:
   - GIS zoning: not a building observation.
   - The old photo override, with its ray verdict.
   - The user's Google review, down-weighted because the Maps link chose the
     pano and heading. Notes such as "backyard of rowhome on Hughes" are
     resolved against the footprint's own frontage.
   - `pose_reviews.csv`: the structural review of a ray-verified, centred
     photo.

   The resolver accepts a type only from observations about that building.
   Disagreements stay in `conflicts`.
6. `--fresh-panos`: free Street View metadata calls, one probe opposite every
   street wall. Records the pano ID, camera position, date and the heading
   that points at that wall, as a keyless Google Maps link. `--fetch-images N`
   (billed, hard cap) is off by default.
7. Outputs:
   - `build/property_evidence/<block>.json` and `.csv`: full evidence records
     (git-ignored).
   - `src/server/World/PropertyReconstruction.lua`: the runtime status and
     structure per ID.

Next block: `py -3 tools/reconstruction/property_evidence.py --bbox W,S,E,N --fresh-panos --render`.
Then inspect the photos it lists as centred, add `pose_reviews.csv` rows,
and re-run. `--all` writes citywide evidence (no Lua) as the review queue.

## Applied to the live world (39 reconstructed + 1 finish)

Structure from pose-verified photos: roof form, parapet, door pattern per
unit, unit count, storeys, porch, bay, garage bays, finish, and frontage
where the photo shows the entrance wall.

- **Restored to residential from zoning storefront/commercial**: 28482 (a
  three-storey hipped Victorian, previously overridden as commercial),
  154877, 170780 and 185789 (a long flat-roof brick row; the user's "PARK"
  view was the adjacent park). Also 5723, 7613, 68468, 82547, 99994,
  121174, 142656, 162137, 164928, 178372 and 95043, which keep their
  residential reading with corrected structure.
- **Roof forms**: the 1940s-50s brick rows 34237, 37959, 39766, 113017,
  139660, 153497, 181213 and 81089 get low side-gable roofs instead of flat
  cornices. Twins with flat cornices (4639, 17385, 68468, 7613, 58981,
  184587) lose their invented gables. 94400 gets a hip with a dormer,
  121174 a front gable, 162137 a mansard and 79594 a shingled pent front.
- **Frontage corrected** (the photo faces the entrance wall): 139660 faces
  Butler, not Macdonald (eight-unit row re-oriented); 37959 and 153497 face
  Lincoln; 81089 faces Hughes; 170780 faces 9th; 415 and 20046 face 8th.
- **Doors**: 58981 and 121174 have paired centre doors, 94400 outer-end
  doors, and 82547, 99994, 142656 and 170780 their photographed position.
  164928 (house number 908) has its entrance on the west side wall; that
  single house is not rentable because the hollow interior assumes a front
  door.
- **Garages**: 23871 is a one-storey gabled single-bay garage on the Hughes
  alley (the user's "rowhouse" was the 9th St houses behind it). 44085 has
  two bays on one wall. 138612 is a one-storey brick workshop with a roll-up
  door, and at 3.5 m it cannot be the old "colonial house". 158068 is a
  shed.
- **97558**: the 9th St photo (heading 182, centred on the front) shows an
  attached red-brick and sided block with roll-up bays at grade and flats
  above. The result is three bays, the upper windows and the photographed
  street door to the flats. The user's "rowhouse" link had an unknown pose.
  The stoop house at the left of the frame is 68468's east unit.
- **147448 / 777 Food Market**: the camera on Lincoln (heading 282) centres
  on the Lincoln wall, which carries the fascia and poster-glazed windows.
  That face is now glazed with no second door. The customer door stays at
  the W 9th corner. The graffiti brick wall from the user's view is the
  west/rear side.
- **68468, 4639, 17385**: the user's "Hughes backyard" observation resolves
  to the rear of the 181213 row across W 9th. These twins front 9th and
  keep their porches.

## Unresolved, and why

- **JF Auto Sales (714 W 10th)**: no county footprint, POI or photo places
  it. 79594 is a four-unit row (the user's link landed on the neighbouring
  lot). Pano queued in `panos_to_review`.
- **164928 vs "902"**: the centred photo shows "908". The user's 902
  storefront is a different, unidentified parcel.
- **33881, 84792, 161384, 128777, 171786, 6108, 120546, 113749, 182911,
  64004, 150015, 183747**: no centred front view, the view is obstructed, or
  a tiny outbuilding. They keep their prior state with status
  supported/needs_imagery.
- Gas stations (50221, 58063, 156812, 133503) and 191030/107445 keep their
  existing builders.
- 93584: units still cannot be separated from the 2020 photo.
- Roofs are read from street views only. Google 3D tiles and LiDAR roof
  pitch are not in this pipeline yet (`roof_3d` is listed as missing on
  every record).

## Studio check

In Play, from the Server command bar:
`require(game.ServerScriptService.Server.World.ReconstructionInspector).Run({radius=600})`

Green = reconstructed, teal = finish only, yellow = older photo override,
red = conflict or needs imagery, grey = fallback. Labels show ID, style and
spec.
