# Kerlin / I-95 Studio geometry measurement plan

Date: 2026-11-04. This is a read-only diagnostic for the topology-corrected
`tile_r07_c07`. No world geometry, terrain, grades, collision settings, spawn,
or coordinate mapping was changed. Live Studio measurements have **not** yet
been collected in this checkout.

## Source and runtime trace

- Source: `E:\ChesterWorld\Data\18_RegionalTiles_StreetV3\Tiles\tile_r07_c07.json`,
  county OBJECTIDs 424/425 (I-95 northbound side), 423/426 (I-95 southbound
  side), 2758/27163/20771/20770 (Kerlin). The generated counterpart is
  `src/shared/WorldData/Tiles/tile_r07_c07.lua`. The source export validator
  confirms the generated module matches the source and that the two graph
  joints use separate endpoint connection groups.
- Active placement: `src/shared/WorldPlacement.lua` and
  `src/server/World/TileBuilderV2.lua` map local meters to
  `X = 3(x - 6347.889)`, `Z = -3(z - 7201.973)`. The north joint is source
  `(7019.645, 7193.492)` near Studio `(2015.268, 25.443)`; the south joint is
  `(7011.454, 7208.863)` near `(1990.695, -20.670)`. Source coordinates are
  rounded in the generated module, so the diagnostic calculates their current
  projected positions at runtime. The inventory anchor `(2029.925, 19.862)`
  is a vicinity point, not either road joint or a surveyed bridge endpoint.
- Runtime: `Bootstrap.server.lua` prepares the global graph and builds tiles
  through `TileBuilderV3`/`TileBuilderV2`; `RoadTerrainConformer.server.lua`
  finishes elevation profiles; `HighwayInfrastructure.server.lua` optionally
  creates bridge components. The diagnostic waits for all three completion
  attributes and rejects quick preview. `TileBuilderV2` creates collidable
  strip Parts under each tile's `Roads` folder. Their `CW_GradeGroup` contains
  the county ID, with `ChesterStreet`, `CW_Bridge`, `CW_GradeLevel`, and
  `CW_ElevationOwner` metadata. RoadPart `Position.Y` is its center, not its
  surface. The diagnostic raycasts the actual surfaces instead.
- The current eight source features remain `layer=0`, `bridge=false`, and
  `tunnel=false`. The exporter records a topological upper/lower relationship,
  but no physical vertical dimensions. The highway finish only creates
  `BridgeDeck` components for profiled bridge/ramp Parts. No deck at this
  crossing should be assumed.

## Installation and one-command run

The new Rojo-synced ModuleScript is
`src/server/World/KerlinGeometryDiagnostic.lua`. Sync `default.project.json`,
start a **full Play session** in Studio with `CW_QuickStreetPreview` unset or
false, and wait until Output shows bootstrap, road conformer, and highway
finish completion. In the **Server** Command Bar, run:

```lua
require(game.ServerScriptService.Server.World.KerlinGeometryDiagnostic).Run()
```

Open **View > Output** and copy all lines beginning `KERLIN |` into the
measurement record. Each line has a section and `PASS`, `FAIL`, `UNKNOWN`,
`MEASURED`, `VERIFIED`, or `REFERENCE` label. `MISSING` is printed for an absent
ray hit, rather than an inferred height. The module creates no Instances,
changes no properties or attributes, and does no filesystem writes. It does
not run automatically during ordinary Play.

For scene inspection, select a reported `workspace.ChesterWorld.tile_r07_c07`
road Part path in Explorer, press **F** to frame it, and orbit to an overhead
and a low side view. Inspect both source joints and the Kerlin underpass
midpoint; compare any reported `HighwayInfrastructure.BridgeDeck` path in the
same side view. Capture screenshots with the Output values visible or named
in a matching measurement table. Do not substitute the reference anchor for
the actual joints.

## What the report establishes

`IDENTITY` and `PART` list every matched source ID, built Part, path, grade
metadata, `CanCollide`, and `CanQuery`. `SOURCE_POINT` shows the projected
joints and anchor distances; `ANCHOR_TERRAIN` and `ANCHOR_ROAD` test the
reference vicinity against the current loaded tile. `SOURCE_GRAPH` checks
the two split source nodes;
`SOURCE_NAVIGATION` and `RUNTIME_NAVIGATION` keep source graph evidence
separate from unavailable runtime pathfinding evidence. `PATH_JOIN` compares
the nearest runtime Part endpoints on each road at both joints.

`SAMPLE` records the downward pavement hit, downward collidable road hit,
upward collidable road underside hit, and Terrain hit at a shared X/Z.
`CROSSING` compares collidable volumes for vertical overlap. `PAD` checks
for a collidable intersection pad at either joint. `PROFILE`, `SLOPE`,
`SEGMENT_JOIN`, and `SOURCE_SEGMENT_JOIN` inspect every source record, each
neighboring generated piece, and boundaries between records sharing an ID
at about 10 stud spacing, detecting missing pavement, Terrain above pavement,
grades over 40%, Part gaps over 1 stud, or Part overlaps over 1 stud. Source
record endpoints that can be intentionally trimmed at junctions are assessed
with `PATH_JOIN` instead of being counted as interior profile gaps.

`DECK` only prints an underside when an actual runtime `BridgeDeck` Part
covers a source joint. It uses an upward raycast when `CanQuery` permits it;
otherwise it solves the Part's bottom face from its measured `CFrame` and
`Size` (`method=PART_FACE_GEOMETRY`). The current highway finisher makes
decorative deck Parts `CanQuery=false`, so a missing ray hit alone is not
evidence that the slab is absent. `OVERHEAD_CLEARANCE` compares that underside
with a same-X/Z Kerlin pavement hit and checks Terrain and other collidable
Parts inside the opening. A road collision underside and a cosmetic deck
underside are reported separately; `deckCollide` reveals if the slab itself
is decorative. If no deck exists, physical bridge clearance is `UNKNOWN`,
even though a collision vertical gap can still be measured.

These are point and sampled-path checks, not a vehicle drive test or a
surveyed span/edge measurement. At any `UNKNOWN` or `FAIL`, inspect the
reported object paths and capture an additional side view or finer manual
raycast before selecting grades or cutting Terrain. The inventory minimum
clearance, span, and width remain reference targets, not observed Studio Y.

## Verification

- `python tools/validate_kerlin_topology.py`: passed, including source tile
  match and both split graph joints.
- `rojo build default.project.json --output
  tools/backups/kerlin_topology_20261104_080846/kerlin_measurement_diagnostic.rbxmx`:
  passed. The model remains in the existing checkpoint.
- Static read-only audit: the diagnostic has no `Instance.new`, `Destroy`,
  `ClearAllChildren`, `SetAttribute`, world property assignments, or network
  calls. Execution requires an explicit Studio Server Command Bar call.
- Studio runtime measurements: pending a fully loaded Play session. No Y,
  underside, collision clearance, or passability has been asserted from the
  static build.
