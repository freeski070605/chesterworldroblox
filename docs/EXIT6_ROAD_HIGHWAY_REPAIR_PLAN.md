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


## Nov 13 late Studio run — repair results and next stage

The uploaded 14:28–14:33 Studio log confirms:
- RoadGapRepair: 26 chains evaluated; 0 chains/0 fragments/0 Parts repaired.
- 15 unsafe anchor grades, 6 missing two anchors, 3 layer mismatches,
  1 too long for local repair, 1 above unsupported terrain.
- Final midpoint audit: 229 omissions, 3 covered by same-named road, 24
  by other-road footprints, 202 open at midpoint. 193 are GIS notMapped,
  which does not prove they are dry land; nine are mapped water.
- Mainline profile: 0 grade violations; final HighwayFinish 245 crossings,
  0 actual low clearance, 0 tunnel obstruction and 0 bridge intrusion.
- Tagged bridge source warning count still 69, but 0 of 69 had excessive
  final measured grade. Early 20 crossing and 42 terrain constraints still
  need surveyed reconciliation before calling every bridge verified.

Safety and accuracy changes now pushed:
1. Gap filler no longer modifies native Terrain with FillBlock. It only
   adds real Parts after an entirely dry, supported safe grade is proven.
2. Rejected chains now print measured start/end heights, required extra
   approach length, or exactly which anchor/source elevation is missing.
3. Final audit now checks three longitudinal points of the SAME ROAD.
   Overlapping pavement of a different road cannot certify continuity.
   New NOT_VERIFIED count is separate from legacy STILL_OPEN baseline.
4. Top 40 steep and top 40 no-terrain omitted fragments are printed
   independently, so Macdade/Crum Lynne source endpoints are visible.
5. Aerial-backed registry crossing CRUM_LYNNE_OVER_CSX at
   Roblox (14420,-10378) is allowed one exceptional elevated-deck
   restoration. It is only eligible if same-road ends align, <=11%
   grade holds, real CSX ballast Parts exist underneath, >=14-stud
   vertical clearance holds, terrain does not invade the road, all
   sample probes avoid native water, and no incompatible overpass
   overlaps. The bridge uses a Part deck plus edge parapets and does not
   modify baked Terrain. Rejected if any check fails.

This new bridge exception is NOT YET VERIFIED IN STUDIO. It is a
specific source-supported attempt, not a claim Crum Lynne was repaired.
Macdade around (7666,-7719), (7783,-7790), (9980,-9818) needs
longitudinal road approaches from surveyed road heights; Riverfront
X -1400..-900, Z 9850..10350 needs GIS shoreline/DEM alignment.

Next run must report:
[ChesterWorld RoadGapRepairRejected] details=...
[ChesterWorld RoadGapRepair] ... verifiedRailBridgeChains=...
[ChesterWorld RoadFinalAudit] ... STILL_OPEN=... NOT_VERIFIED=...
[ChesterWorld RoadGapDetail] kind=steep ...


## Nov 13 21:33 Studio result — physical first successes

The pasted 709-line Studio Output has real post-build repairs:
- RoadGapRepair evaluated 26 chains, fixed 2 chains, 20 asphalt
  fragments/pieces, all Crum Lynne near the verified CSX overpass.
  22.3-stud chain at (14453.6,-10348.7)..(14470.3,-10333.9):
  grade 6.1%; 17.3-stud chain at
  (14378.8,-10414.9)..(14391.7,-10403.4): grade 0.0%.
- 20/20 recovered pieces have 3/3 same-name pavement coverage in
  RoadIntegrityFinalAudit. This is a STATIC geometry pass, NOT a
  full drive certification or measured proof of track clearance.
- Legacy midpoint STILL_OPEN remains 202: previously 17 of these
  locations were hidden under "other-road" overlap. Compare
  coveredSameRoad=20 (was 3), coveredOtherRoad=7 (was 24).
- New full-length stricter 3-point verification:
  NOT_VERIFIED=209 of 229 candidate fragments. The 209 remaining
  include 200 with unknown GIS-water mapping, nine on mapped water;
  neither count proves a segment is dry or actually drivable.
- Highway: 7,305 profiled parts, 0 profile grade violations, final 245
  crossings with 0 measured low-clearance / bridge intrusion / tunnel
  obstruction; 69 source-flagged bridge parts had 0 final steep parts.
  Twenty *early* height deficits and 42 terrain constraints remain.
- Saved water signature verified 52/52 probes. Full loading 234.4s.
  RoadTerrainClear 52.2s for 117,234 surfaces.
- Remaining auto-repair blockers: 15 unsafe anchor-grade, six missing
  real pavement anchors, one layer mismatch, one terrain-float, and
  one chain too long.

Read-only independent post-build check:
  [ChesterWorld RoadFinalRailDeck] ... intersectingCSXBed=...
  minConservativeClearanceStuds=... clearanceBelow14=...
The independent value is not guaranteed to be a whole-crossing
clearance measurement when an individual repaired approach slab does not
geometrically overlap a CSX bed. Drive across the entire crossing in
Studio and check the real bridge deck and approach joints.

## MacDade bridge inventory and profile engineering

DO NOT fill Macdade's 50.8-stud hole by extending the 48-stud generic
repair threshold. A 50.8-stud dip at (7665,-7719) changes source elevation
abruptly; another 13.4-stud dip at (9979,-9818) has 9.09 studs difference
between the existing road anchors. The latter requires ~82.6 studs at an
11% game-grade instead of the currently missing 13.4 studs; the actual
road and bridge must be profiled over a longer chain.

External bridge-inventory evidence:
- Macdade Boulevard over Ridley Creek, NBI 15224, concrete deck arch,
  100-foot length, coordinates 39.86958,-75.35671. Source:
  https://usbridges.org/bridge/pa-county-045-bridge-000000000015224
- Macdade Boulevard over Crum Creek, NBI 15226, culvert, 95-foot length,
  just east of I-476. Source:
  https://usbridges.org/states/pennsylvania/delaware-county
- PennDOT confirms a separate pedestrian bridge across Crum Creek next
  to MacDade Boulevard was replaced/repositioned as part of the I-476
  interchange project. Do NOT mistake it for an asphalt carriageway:
  https://www.pa.gov/agencies/penndot/news-and-media/newsroom/district-6/2026/pavement-marking-installation-tuesday-on-macdade-boulevard-in-ri

NEW read-only Road survey module:
  src/server/World/MacdadeBridgeProfileSurvey.server.lua

It samples rendered same-road pavement top vs actual Terrain bank and
native water at 15 longitudinal stations around the two candidate
source breaks. The center X/Z are approximate **missing-fragment
coordinates**, not surveyed bridge-center positions. This records
whether enough dry bank/pavement exists across 320 studs each direction
to design a long profile and real structure. It does not alter existing
road Parts, water or Terrain, and does not invent deck heights.

Logs to inspect in next Studio run:
  [ChesterWorld MacdadeBridgeSurvey] id=MACDADE_RIDLEY_CREEK ...
  [ChesterWorld MacdadeBridgeStations] id=MACDADE_RIDLEY_CREEK ...
  [ChesterWorld MacdadeBridgeSurvey] id=MACDADE_CRUM_CREEK ...
  [ChesterWorld MacdadeBridgeStations] id=MACDADE_CRUM_CREEK ...
  [ChesterWorld RoadFinalRailDeck] ...

Next geometry work (after profile proof):
- Rebuild Macdade's continuous longitudinal road centerline over the
  documented bridge/culvert footprints, grade-limited across the FULL
  approach, with real abutments / existing road joining.
- Restore Pennell over NEC and other surveyed rail-grade crossings.
- Resolve 9 mapped-water and 39 other no-terrain omitted fragments
  using verified riverbank GIS/DEM, not fill blocks on unknown shoreline.
