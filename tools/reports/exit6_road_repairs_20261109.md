# Exit 6 road repair review (2026-11-09)

Branch: `fix/chesterworld-highway-road-repairs`. No source road tile, terrain
asset, Rojo mapping, or gameplay script was changed.

## Evidence and diagnosis

| Site | Source evidence | Generator finding | Current certainty |
| --- | --- | --- | --- |
| 9th / Commodore Barry | `county:26532:g0` is the 9th Street link between two Barry carriageway junctions at approximately `(-1622,4248)` and `(-1586,4222)` studs. [DVRPC's Chester ramp study](https://www.dvrpc.org/Reports/03003.pdf) describes a partial 9th Street interchange. | Highway abutments and pier caps previously checked only a point or rail; a solid could extend into the 9th Street pavement. The exact reported beam instance has not been identified in a current Studio run. | Structural collision path confirmed in code; beam identity and removal await Studio. |
| Barry ramps near 9th | County Barry segments `21213`, `21215`, `21247`, `21248` meet the 9th link at source nodes. | `barrierPair` built a full barrier along every profiled span/fill edge without testing for another road at the same elevation. A ramp gore can therefore acquire a barrier across its merge. | Source topology confirmed; particular ramp elevation and collision await Studio. |
| Grass through pavement | Prior real-terrain audit in `RoadTerrainClear.server.lua` recorded 0.4% residual street-surface samples after clearing. | Clearing began two studs below the pavement top, half a terrain voxel; a partly filled four-stud voxel can remain visible. The pass now starts one voxel below, within each existing slab footprint. | Source fix and Rojo build confirmed; real DEM resampling awaits Studio. |
| Edgmont / I-95 southbound | Eight connected `Edgmont Ave to I 95` source segments run from Edgmont `(6210,-2281)` to the I-95 southbound side `(4547,-1361)` in Roblox X/Z. The 2003 [DVRPC study](https://www.dvrpc.org/Reports/03003.pdf) called this a missing southbound movement; the present county tile contains it. [PennDOT's 2024 interchange inventory](https://docs.penndot.pa.gov/Public/Bureaus/BOO/Asset%20Management%20Division/Roadway%20Inventory%20and%20Testing%20Unit/Interchanges/Individual%20Interchanges%20all%20Districts/District%2006/County%2023/23.pdf) lists Exit 6 ramp records. | The source connection is present, so adding a new synthetic ramp would duplicate it. Solid fill and edge barriers could block an existing connection; these generators now check lower pavement and same-level joins. | Source chain confirmed; whether pavement is omitted or blocked in Studio is unresolved. |
| Kerlin / I-95 southbound | 24 connected `Kerlin St to I 95` segments run from Kerlin `(1946,-104)` toward the southbound collector road `(-1807,1615)`. The 19-piece I-95-to-Kerlin exit is a separate movement. `validate_kerlin_topology.py` confirms the Kerlin underpass graph split. Prior Studio samples in `kerlin_geometry_hold_20261104.md` found overlapping upper/lower pavement before the subsequent profile work. | Solid fill, abutments, pier caps, and full edge barriers previously lacked full-volume road conflict checks. The support and barrier guards cover the surrounding merge and overpass, while the existing HighwayProfile retains the measured 16.03-stud offline opening. | Source graph and static guards confirmed; current clearance, collision, and drive pass await Studio. |

## Changes

- `HighwayInfrastructure.server.lua`: reject abutments and piers whose whole
  volume intersects a lower street; use an open deck instead of solid fill
  where lower pavement passes beneath; omit a barrier edge overlapping a
  same-level paved merge. Log each skipped or converted structure.
- `LocalBridgeDressing.server.lua`: test the full abutment and pier-cap volume
  against lower roads before creating collidable support.
- `RoadTerrainClear.server.lua`: start terrain clearance one voxel below the
  road top without widening the footprint.
- `tools/highway/tiledata.py`: count tile road indices in linear time so the
  full source audit can run promptly.
- `tools/validate_exit6_road_sources.py`: check the real source chains and
  Barry/9th source junctions.
- `tools/validate_kerlin_topology.py`: compare only its eight crossing records
  with the upstream export; later unrelated width/sidewalk edits made the
  previous whole-tile byte comparison fail on an unchanged tile.

## Validation

- `py tools/validate_exit6_road_sources.py`: PASS, all three ramp chains and
  both 9th/Barry junctions.
- `py tools/validate_kerlin_topology.py`: PASS, underpass graph separation and
  same-road continuity.
- `py -m py_compile` on changed Python files: PASS.
- `git diff --check`: PASS.
- `rojo build default.project.json --output build/exit6-road-repairs.rbxmx`:
  PASS. The model was built locally and was not published.

## Required Studio verification before merging

1. Run the branch in the existing Studio place and wait for
   `CW_HighwayFinishComplete`, `CW_RoadTerrainCleared`, and
   `CW_LocalBridgesDressed`. Record the new `supportsOnRoadSkipped`,
   `fillsOverRoadAsDeck`, `barriersAtMergesSkipped`, and
   `supportsSkippedForRoads` counts. Inspect every reported skip.
2. At 9th/Barry near `(-1604,4235)`, identify the original beam by full part
   path and `CW_StructureId` / `CW_StructureBasis`. Verify it is absent with
   this branch, then drive 9th through both Barry junctions and the actual
   permitted ramp movements.
3. Drive from Edgmont `(6210,-2281)` down the existing southbound ramp and
   through its merge near `(4547,-1361)`. Sample pavement top and part
   coverage along the whole ramp, including tile seams. Check ramps at 9th.
4. Drive the Kerlin southbound connector from `(1946,-104)` to the collector
   road near `(-1807,1615)`. Run `KerlinGeometryDiagnostic` at the two Kerlin
   underpass joints and measure actual deck underside minus Kerlin pavement
   top at matching X/Z. Inspect the adjacent I-95 exit and both carriageways.
5. Sample road center and wheel tracks over I-95, Barry, Edgmont, and Kerlin
   for terrain/grass above pavement. Inspect terrain immediately outside the
   pavement and sidewalks to ensure it remains intact. Confirm no solid
   support or barrier enters any driving envelope.

Static topology and a Rojo build cannot establish vehicle passability or
clearance. This branch should remain a draft review until those Studio checks
pass; no interchange is claimed repaired solely from the offline checks.
