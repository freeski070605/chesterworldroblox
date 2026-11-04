# Kerlin / I-95 geometry hold

Date: 2026-11-04. Decision: **do not enable or model a bridge yet**. The
topology is corrected, but the available records do not locate the physical
abutment faces, deck edges, structural depth, or an actual deck underside.
Using the two shared road vertices as span ends would invent a footprint.

## Evidence and baseline

The complete 331-line Studio diagnostic from the 2026-11-04 13:33:28 UTC run
is saved in `tools/backups/kerlin_geometry_hold_20261104/studio_baseline_diagnostic.txt`.
The checkpoint also contains the current relevant runtime scripts, generated
tile, upstream source tile, SHA-256 manifest, and a baseline Rojo build.
The baseline was a full Play run: bootstrap, road conformer, and highway
finisher were complete. No preview geometry was created.

The runtime order is `Bootstrap.server.lua` -> `TileBuilderV3` ->
`TileBuilderV2.Build` -> `RoadTerrainConformer.server.lua` ->
`HighwayInfrastructure.server.lua`. V3 delegates road creation to V2.
V2 terrain-samples and creates the collidable road strips. The conformer
preserves Y for these eight `bridge=false`, `layer=0` Kerlin/I-95 records and
marks them `CW_ElevationOwner=TileBuilderV3`. For roads tagged as bridges, the
conformer *does* replace Part CFrames and may reshape adjacent approach
Parts. The highway finisher runs afterward, creates decorative noncolliding
deck slabs for eligible profiled bridges, and does not move road Parts. A
future preview that changes road Y before the conformer completes would be
overwritten unless explicitly integrated with that pass.

| Studio location | I-95 top Y | Kerlin top Y | Terrain Y | Result |
| --- | ---: | ---: | ---: | --- |
| South source joint `(1990.695,-20.670)` | 38.751-38.753 | 38.749 (underpass), 38.525 (approach) | 38.225 | 4/4 collidable road comparisons overlap |
| North source joint `(2015.268,25.443)` | 39.561 | 39.561 (approach), 39.338 (underpass) | 39.036 | 3/4 comparisons overlap; the fourth has only 0.006 stud vertical gap |
| Kerlin underpass records' mutual vertex `(2002.581,1.635)` | not sampled | 39.137 / 38.910 | 38.612 | Two lower Parts have different sampled top Y at the vertex; test actual wheel path |
| Inventory vicinity anchor `(2029.925,19.862)` | 39.666 on ID 425 | 39.645 on ID 2758 | 39.079 | Anchor is not a span endpoint or bridge center survey |

Both source graph joints and all four same-road runtime path joins pass. No
intersection pad was hit at either joint. There is no measured `BridgeDeck`
underside at either joint. Hence **physical opening, deck collision, and
vehicle passability remain UNKNOWN**. The diagnostic's 7/8 comparison failures
prove overlapping sampled road collision volumes; the one PASS is not usable
clearance.

The county IDs are verified in the upstream regional source and generated
`tile_r07_c07.lua`:

| Route | IDs and source extent | Relevant neighbor |
| --- | --- | --- |
| I-95 first carriageway | 424 ends and 425 begins at the north Kerlin joint; 424 extends 21.92 m in r07c07 and 402.44 m west into r07c06; 425 continues 295.22 m east in r07c07 | 424 continues into r06c06 farther west |
| I-95 second carriageway | 423 ends and 426 begins at the south Kerlin joint; 423 extends 12.68 m in r07c07 and 376.43 m west into r07c06; 426 continues 292.11 m east in r07c07 | 423 continues into r07c06 |
| Kerlin | 2758 approaches the north joint; 27163 and 20771 are county `Underpass/UPAS` records between the joints; 20770 leaves the south joint | 2758 connects toward 12th; 20770 continues into r07c06, then source 20772 |

The two Kerlin underpass source records total about 17.4 m (52.25 studs)
between the I-95 carriageway centerline joints. They mark road topology, not
abutment faces. Inventory structure length is 64 ft (58.52 studs) and deck
width is 101 ft (92.35 studs), but neither inventory value supplies a surveyed
orientation or endpoint. The generated I-95 source widths are 25 m and 12 m;
the second carriageway is even exported as `secondary`. Those generalized
road strips cannot be substituted for measured deck edges. The 14 ft 1 in
(12.878 studs) inventory minimum is a provisional clear opening to the lowest
member above the lower road, **not** a deck-top elevation. Actual structural
thickness remains unknown; the configured 1.6-stud cosmetic slab is not a
verified girder depth.

Reference provenance: [US Bridges structure 14892](https://usbridges.org/bridge/pa-county-045-bridge-000000000014892)
reports the inventory length and width;
[MyTownView's Chester bridge inventory](https://mytownview.com/pennsylvania/delaware/chester/infrastructure/bridges)
reports the 14 ft 1 in low underclearance. The
[FHWA NBI item list](https://www.fhwa.dot.gov/bridge/nbi/checks/items.cfm)
distinguishes structure length, deck width, and minimum vertical
underclearance as separate fields. The exact measurement point for this
structure has not been established in the Roblox world.

## Road-profile investigation

The diagnostic measured three internal Part interval gaps on I-95: 24.662
studs in 424, 34.252 in 425, and 27.386 in 426. Their corresponding samples
have no road collision hits, so these are plausible **real missing road
collision**, not merely a raycast against Terrain. V2's `safeGroundPair`
returns without a Part when a recursively divided terrain-following piece
still exceeds the configured 40% grade or both endpoint Terrain rays miss.
The baseline log has Terrain hits at the gap sample coordinates, making the
grade rejection a strong hypothesis; exact rejected endpoints still need a
Studio Part-boundary or builder trace. Do not close these gaps by raising a
short bridge segment.

Of 12 missing profile sample hits, nine lie in those three internal I-95 gaps.
One is near the start of 423 and two near the start of Kerlin 2758. Those
three may result from intentional trimming at a neighboring junction or from
missing Parts; the current profile output lacks trim boundary and intersection
pad coverage at those samples. Verify each with nearby Parts, `CanCollide`,
and a path sweep before classifying it.

Fourteen I-95 samples have Terrain within 0.10 stud below or above the road
top; maximum sampled excess is 2.828 studs on 426. The
values may be localized voxel/linear-strip differences. Confirm with a
centerline and both wheel-track sweeps through each cluster and record actual
collision contact. The current diagnostic checks vertical sample points,
not a vehicle envelope. No terrain change is authorized by this evidence.

## Required measurements before a geometry preview

1. Identify the physical structure in an authoritative plan, georeferenced
   aerial/orthophoto with visible abutments, survey, or a verified Studio
   reference. Record the two abutment faces along **each** I-95 carriageway,
   deck lateral edges, skew, and source/version. Check the 64 ft by 101 ft
   inventory dimensions against that footprint. Keep the source joint points
   and vicinity anchor separate.
2. At those exact bounds and across the Kerlin opening, measure lower pavement
   and Terrain Y on center and wheel paths, any existing lowest structural
   member, and all solid obstacles. Tie the 14 ft 1 in inventory field to its
   measurement definition and location. Set deck pavement Y only after lower
   top Y, required opening, and structural depth are known at matching X/Z.
3. Profile both I-95 carriageways continuously through IDs 423-426 and the
   r07c06 continuations, including source and Part boundaries. Record start
   and end tie-in Y and available approach distance. Apply a highway grade
   limit to the **combined existing grade and added lift**, checking slope
   through each boundary. At 10% grade, an illustrative 15-stud lift alone
   needs at least 150 studs of linear run, and a smoothstep transition needs
   about 225 studs; neither is an approved local design. Expand the measured
   source scope if necessary.
4. Recheck the three I-95 gap intervals, the other three missing samples, and
   the 14 terrain points with Part-boundary and collision sweeps. Record
   whether the failures are missing geometry, trimming, or voxel sampling.

## Scoped implementation after those measurements

- Use one Studio-only, default-false `CW_KerlinBridgePreview` toggle. Recheck
  all eight county IDs and source joint coordinates at runtime. Limit edits to
  the verified footprint and necessary same-road approach records, including
  r07c06 if the measured tie-ins require it. Preserve Kerlin's source X/Z and
  measured vertical profile.
- Run after the road conformer and highway finisher, or integrate explicitly
  into their ordered stages. Snapshot affected Part CFrames, sizes,
  collision settings, and markings. Create the preview's structural geometry
  in a dedicated folder. Give the slab a **physical collidable underside**;
  do not count a noncolliding decorative `BridgeDeck` as structure. Check
  barrier/support placement outside Kerlin's usable envelope.
- Provide a restore command that destroys only preview-owned Instances and
  restores each snapshotted property. A fresh full Play run with the toggle
  false must match the baseline. No global height, terrain, spawn, GIS,
  heightmap, unrelated street, or source-data mutation is part of the preview.
- Add a completion attribute so the diagnostic runs only after the preview
  has finished. Re-run it at center and wheel paths, then drive both I-95
  directions and Kerlin in Studio. Require a measured opening to the physical
  underside, continuous collidable pavement, safe crossing envelope, Terrain
  clear of the route, and usable approach grades across every Part boundary.
  Save before/after measurements and screenshots; do not recommend permanent
  activation until all checks pass.

## Verification performed now

- `python tools/validate_kerlin_topology.py`: PASS.
- `python -m py_compile tools/validate_kerlin_topology.py tools/package_roblox_street_v4_world.py`: PASS.
- `rojo build default.project.json --output tools/backups/kerlin_geometry_hold_20261104/baseline_build.rbxmx`: PASS.
- Preview versus baseline: **no preview exists or was enabled**; after values
  and after Studio drive tests are UNKNOWN. The working world source files
  were not edited for geometry.
