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


## Nov 13 Studio test results (post-audit baseline)

The uploaded Studio log reports:
- 229 omitted fragment candidates (181 steep, 48 no-terrain).
- 202 physically open at fragment midpoints; 3 covered by same road, 24
  covered by another road. This is a midpoint-only test and is not a
  complete driving/connectivity certification.
- 9 missing no-terrain fragments centered in mapped water polygons;
  39 are *notMapped* by available water GIS. NOT-MAPPED does not mean
  dry land. The riverfront geometry must remain unpatched pending GIS.
- The earlier 4-stud seam interpolation recovered 0 additional samples;
  5 samples recovered using the existing wider seam logic.
- The physical highway audit reports 0 highway profile grade failures
  and 0 measured low-clearance crossings. Pre-registry height constraints
  remain to be surveyed.
- Studio flagged a temporary infinite-yield warning because the audit
  waited on the ChesterWorld root before Bootstrap created it; fixed by
  waiting for Bootstrap completion first.
- The log's "RoadFinalAudit seconds=273" included city build waiting
  time. It is now reported as auditSeconds from the actual audit start.

## Dry-land grade repair (new code, unverified until next Studio run)

The new src/server/World/RoadGapRepair.server.lua runs AFTER terrain clearing,
local bridges and baked-water verification. It only considers contiguous
omitted STEEP road segments, not no-terrain shoreline segments. It may add
asphalt when ALL of the following hold:

- Segment chain <=48 studs and exactly two nonbranching terminals;
- same-name, comparable-width, nonbridge road Parts exist at BOTH ends;
- connected endpoints have a combined gradient <=11%;
- every source path segment and both shoulders have real dry terrain,
  neither a mapped water polygon nor visible native Terrain water;
- projected asphalt demands <=2.5 studs local excavation and sits
  <=3 studs above the source terrain;
- no nearby profiled highway, bridge, rail or tunnel occupies the patch.

Only after these checks does it add Part asphalt and clear up to a shallow
road-surface trench using the same local Terrain approach as the original
RoadTerrainClear. The repair is *conservative by design*: it is expected
to reject many large and geographically ambiguous problems. It does not
rewrite GIS, bridge geometry, or the saved Studio water bake.

Expected NEW logs:
  [ChesterWorld RoadGapRepaired] ...
  [ChesterWorld RoadGapRepair] evaluatedChains=... fixedChains=...
  [ChesterWorld RoadFinalAudit] ... STILL_OPEN=... auditSeconds=...
      repairStatus=complete repairParts=...

The final integrity audit waits for RoadGapRepair to finish. If it fails,
the failure is printed and the audit still runs on the original surfaces.
The unchanged 202 open-gap baseline is what the next result must beat;
do not claim improvements until the next Studio test.

Priority AFTER confirming actual repairs: riverfront GIS/DEM road footprint,
Macdade/Crum Lynne long-grade profiles, and per-crossing bridge elevation
surveys. The remaining first-pass code changes are not a license to publish
before the unverified missing roads are resolved.
