# ChesterWorld — highway pavement continuity patch (2026-11-04)

## Why this patch exists
The running 102-tile map has missing asphalt on I-95 in addition to unresolved bridge/ramp grade problems. In `TileBuilderV2.safeGroundPair`, any terrain-following strip with an endpoint slope over `MAX_SURFACE_GRADE=0.40` is dropped before it can subdivide. This can cause an actual empty gap rather than a flagged geometry problem.

County road data sometimes labels `I 95` pieces as `secondary` (for example IDs 423/426 at Kerlin), so filtering only on `motorway` would miss relevant highway pieces.

## Changes in this branch
- Add `WorldConfig.RECOVER_STEEP_HIGHWAY_PAVEMENT` (default true **on this development branch only**) for a one-line rollback.
- In `TileBuilderV2`, exempt only highway-class or exactly named I-95/I-476 strips from the steep-endpoint **omission** rule. Other streets retain the original rule.
- Keep adaptive subdivision and actual terrain sampling.
- Flag any newly preserved steep piece with `CW_SteepHighwayFallback`, `CW_UnsafeSurfaceGrade`, and numeric `CW_ObservedSurfaceGrade`. This is a visibility/continuity recovery, **not grade correction**.
- In `TileBuilderV3`, emit one end-of-build warning with recovered highway piece count and worst observed grade.

## Safety and limitations
- No source GIS, road topology, terrain, spawn, building, or heightmap changes.
- This does **not** repair the 206 reported bridge terrain intrusions, 569 grade-limited bridge parts, missing samples for every possible cause, or the unverified Kerlin abutment geometry.
- Preserving a strip with a steep DEM baseline may create a very steep collidable road. **Do not deploy or merge without Studio inspection.**
- No Luau or Rojo build could be executed by ChatGPT remotely; only source-level preflight checks and GitHub diff inspection have been completed.

## Studio acceptance criteria (active branch only)
1. Set `RECOVER_STEEP_HIGHWAY_PAVEMENT=true` in the project and run a **fresh full** 102-tile Studio Play test.
2. Record `[ChesterWorld HighwayPavement] recoveredSteepParts=...` and check `TileBuilderV3` summary.
3. Inspect previously missing I-95 road sections, including Kerlin and straightaway segments. Confirm continuity, no terrain poking through, and no cliff-like road slabs. The warning count identifies unresolved unsafe grades.
4. Run the existing Kerlin geometry diagnostic and compare samples, source topology, and highway-finish warnings against the known baseline.
5. If road spikes appear, set `RECOVER_STEEP_HIGHWAY_PAVEMENT=false`, rebuild, and report the failing road `CW_GradeGroup` / location. Do not delete or smooth terrain.
6. Keep the existing Kerlin experimental bridge test separate until the generator-owned grade profile, bridge deck, approaches, and real clearance are validated.

## Next engineering work
A) Correct the Y profile of flagged highway sections (never simply accept a >40% grade).  
B) Integrate Kerlin overpass in the post-conform generation pipeline, with verified footprint/tie-ins and collision.  
C) Resolve corridor-level grade-limited ramps, missing asphalt from trim/junction cases, and remaining bridge intrusions.  
D) Validate geometry, markings, and clearance in Studio before merging.

This is a scoped pavement **recovery** patch, not a claim that ChesterWorld's entire highway system is finished.
