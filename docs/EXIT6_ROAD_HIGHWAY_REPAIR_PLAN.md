# EXIT 6 — ROAD & HIGHWAY CLOSURE PASS

Status: code and diagnostics implemented; new Studio run required to
establish how many roads actually recovered. Do NOT claim 100% road completion.

## Ground-truth baseline (from Nov 13 Studio logs)

- 102/102 regional city tiles built.
- Road pavement omissions: 181 steep pieces totaling 398 studs;
  47 absent-terrain pieces; 41 hotspot neighborhoods.
- Most longest no-terrain gaps: Chester Riverfront. Several centers have
  no solid terrain even within a 24/64-stud ring. WaterMap classifies some
  source road as mapped water and much of the rest as *not mapped*.
  No-terrain != definitely river. Don't fill guessed water or land.
- Steep omission priorities: Macdade (84%/62%/76% areas), Crum Lynne,
  6th, Incinerator, Pennell and pedestrian grades. Treat as REAL missing
  unsafe road segments until corrected by georeferenced height profiles.
- HighwayProfile reports 0 corridor grade violations. HighwayFinish
  reports 245 verified crossings with 0 measured low-clearance crossings,
  0 bridge intrusions, 0 tunnel obstructions and 0 highway slab steps
  *in its checked scope*.
- RoadTerrainConformer also reports 20 pre-registry crossing-height deficits,
  42 pre-registry terrain-height deficits, and 69 source-tagged grade-limited
  bridge parts. These are incomplete early-profile constraints, not proof
  of 20 final low-clearance physical crossings; do not ignore them.

## Code changes in this pass

1. In TileBuilderV2, when an endpoint has no solid Terrain, sample the
   immediate 4-stud surroundings. Recover an elevation ONLY when at least
   6 of 8 dry-land neighbors exist with <= 1 stud vertical variation.
   Existing 8/16-stud level seam recovery stays, but all recovery now
   rejects GIS water polygons, approximate streams, visible native Water
   and wet sample margins. It never automatically paves steep or missing
   Riverfront terrain.
2. WaterMap uses a 128-stud spatial index, avoiding 16,749 rectangle scans
   for every possible pavement sample. Mapped polygons win over overlapping
   approximate stream rectangles.
3. Store exact x/z endpoints, width, class, length, grade, and street name
   for omitted road fragments. TileBuilderV3 prints the top 35 plus
   [ChesterWorld RoadGapAudit] and [ChesterWorld SeamRecovery].
4. RoadTerrainConformer prints exact coordinates and lift deficits for
   pre-registry unsatisfied bridge requirements; these must later be
   reconciled with surveyed source levels and the final physical audit:
   [ChesterWorld BridgeSourceHeightDeficit]
   [ChesterWorld BridgeTerrainSourceDeficit]
5. RoadIntegrityFinalAudit.server runs AFTER road/highway/bridge/terrain/water
   construction. It probes whether an omitted fragment has any actual road
   surface at its center and measures the FINAL profile grades across
   all road pieces (road vs highway, flagged bridges). Outputs:
   [ChesterWorld RoadFinalAudit]
   [ChesterWorld RoadFinalOpenGap]
   [ChesterWorld RoadFinalHighwayGrade]
   The "covered" classification means a road Part footprint occupies the
   midpoint, not proof a whole segment is connected/drivable.
6. EXIT 6 loading now waits for this audit as well as the other world
   construction and gameplay-service stages.

## Next test

In PowerShell:
    cd E:\code\chesterworld-roblox
    git pull --ff-only origin main

If Rojo is running, reconnect; otherwise:
    rojo serve default.project.json

Use Roblox Studio Play (not Edit mode) and preserve full Output. Search:
    [ChesterWorld SeamRecovery]
    [ChesterWorld PavementOmissions]
    [ChesterWorld RoadGapAudit]
    [ChesterWorld RoadFinalAudit]
    [ChesterWorld RoadFinalOpenGap]
    [ChesterWorld RoadFinalHighwayGrade]
    [ChesterWorld BridgeSourceHeightDeficit]
    [ChesterWorld BridgeTerrainSourceDeficit]
    [ChesterWorld HighwayFinish]
    [EXIT6] World ready

Use the precise "open gap" and "source height deficit" locations to fix
the actual streets one at a time using GIS road centerlines, verified bank
elevation and safe approach profiles. Do not extrapolate over water or
reset grade-limit flags to cosmetically reduce warning counts.

Native baked water is untouched: do not rerun the Studio water bake.
Do not publish the live game until these physical gap audits are reviewed,
the major missing asphalt is actually repaired, and a full drivable test
has been performed across the affected corridors.
