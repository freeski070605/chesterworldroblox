# EXIT 6 — Schools, churches and institutions

Chester's schools and churches are rebuilt from their own photographs, one
building at a time, instead of sharing a "church" or "school" template.

## Pipeline

| Step | File |
| --- | --- |
| Citywide inventory (GIS + tiles + photo manifest) | `tools/reconstruction/institution_inventory.py` → `build/institutions/inventory.{csv,json}` and review sheets `build/institutions/sheets/` |
| Photo-reviewed spec per building | `src/server/World/InstitutionReconstruction.lua` |
| Builder | `src/server/World/InstitutionArchitecture.lua`, called from `TileBuilderV2.buildFootprintBuilding` |
| Evidence rules | `tools/reconstruction/test_institutions.py` |
| Offline geometry render (when the Studio viewport cannot render) | `tools/harness/render_parts.py` |

```
py -3 tools/reconstruction/institution_inventory.py --sheets
py -3 -m unittest discover -s tools/reconstruction -p "test_*.py"
```

## Evidence rules

* Every spec cites the original local reference photo (`25_GoogleStreetView_Buildings/images/<id>/front_<pano>.jpg`)
  and its capture date. Imagery older than 2019 can be at most `medium` confidence.
* `seen` lists what the photo shows. A tower, steeple, spire, cupola, onion dome,
  clock, belfry, cross, stained glass, rose window, lancet windows, portico, porch,
  sign, curtain wall, ribbon windows, canopy … is built only when `seen` records
  it. The unit test fails otherwise.
* The builder has no feature defaults: an entry with no `tower` gets no tower.
* `front` is the photographed front bearing (camera heading + 180) when it differs
  from the street-derived tile front. `gableFront` names the photographed gable end
  of a front-gabled church; otherwise the gable goes on the narrow end nearest the
  street (corner street `fb2` as tie-break).
* Photos that cannot carry a reconstruction (trees, trucks, interior shots, wrong
  building) are listed with the reason in `PHOTO_UNUSABLE` in the inventory tool;
  those buildings stay generic.
* Identity: names come from OSM / county; conflicts seen in photos are recorded in
  the entry `note` (e.g. 45296: IHM vs. "Saint Katharine Drexel Center for
  Evangelization" signage; 170019: Saint James HS closed, occupant unverified).

## Entry kinds

| kind | effect |
| --- | --- |
| `church`, `school`, `campus` | rebuilt by `InstitutionArchitecture` |
| `ruin` | roofless fire-gutted shell (photographed 2024) |
| `demolished` | not built — photographed as an empty lot (34448) |
| `reclassified` | building type only (127978: garden apartments, not Stetser Elementary) |
| `rename` | name only (168294 is Old Main, not "WDNR-FM") |

## Massing modes

* **mass** (churches, small buildings): the nave is the largest county rectangle
  plus the slices that continue it; it gets one body and one roof (front gable,
  side gable, hip, flat, parapet, castellated, stepped, or none for ruins). Other
  rectangles become lower annexes. LiDAR height is the roof peak; the eave sits a
  rise below it (rise capped at 45% of the height).
* **wings** (large schools, campus halls): every county rectangle keeps its own
  box so courtyards stay open; each is re-dressed (material, coping / fascia /
  gable / hip roof, windows) and the front-most box carries the entrance pavilion,
  door, canopy, curtain wall, portico, cupola and sign.

## Performance

No per-brick or per-pane geometry. Repeating school windows use the existing
facade textures (`commercial`, `industrial` multi-pane, `rowhouse` sash) or one
glass strip per storey (ribbon windows). Church windows are two parts each (glass
+ arched head), at most nine per wall. Spires are four `CornerWedgePart`s.
Reconstructed institutions are built server-side inside the building's own model
(streams with it), like the reviewed storefronts; residential HouseKit is not
touched. See the final report in the commit history for the measured instance
counts.

## Photo-matched models (second pass)

Schools and church signs were redone to match the buildings themselves, not
one front photo:

| Step | File |
| --- | --- |
| More angles of a building (all sides, free metadata, billed images) | `tools/reconstruction/institution_views.py <ids> --max N --zoom` |
| Tight zoom on a sign seen in any reference image | `tools/reconstruction/sign_zoom.py <id> <image stem> <x> <y> [fov] [name]` |
| Exact county footprint + photo-ray anchors | `tools/reconstruction/institution_footprints.py` → `InstitutionFootprints.lua` |
| Aerial overlays for tracing | `tools/harness/aerial_overlay.py`, `tools/harness/plan_overlay.py` |
| Polygon geometry (walls per edge, ear-clipped roofs, rounded corners, punched windows, sign text) | `src/server/World/InstitutionShapes.lua` |
| Polygon-mode builder (`poly={...}`) and signs for any mode (`signs={...}`) | `src/server/World/InstitutionPoly.lua` |
| Bespoke model | `src/server/World/Institutions/ChesterHigh.lua` |

* An **anchor** `"<pano 8>_<heading>"` is where a named reference photo's centre
  ray meets the footprint. Entrances, projecting blocks, height zones
  (`parts`) and signs are placed at anchors, so they sit where the photo shows
  them.
* **Chester High** (155084) is traced from the 50-vertex county polygon and
  the 2025 aerial and matched to 42 views: bowed W 9th front, glazed entrance
  bay over the cantilevered balcony, terraces, rounded-corner gym/auditorium
  with its stage box, four-storey pods, Barclay St plaza, and the real
  monument and pylon signs.
* **Signs** carry only text read from a photo; illegible signs are not
  invented and individuals' names (pastors, bishops) are left out. Where a
  sign contradicts the recorded identity the building takes the
  photographed name and the note keeps the record.
* Studio preview without a full city build: `TileBuilderV2.BuildOne(tile, id,
  folder)` from a cloned World folder. If the Rojo plugin is disconnected,
  `tools/harness/studio_push_world.sh` + `studio_sync_world.luau` copy the
  sources in.

## Known limits

* County footprints are sliced into strips, not semantic parts: where a church and
  its parish hall share one polygon (e.g. 51981, 82905), the nave roof can cover
  part of the hall.
* School grounds (pitches, courts, tracks, playgrounds) come from OSM and are
  already built by `ParkBuilder`; fences, parking and bus loops are not added
  without a mapped or photographed outline.
* Chester High's curved gym roofline is not modelled (gym not separable in the
  county rectangles).
