# ChesterWorld highway work — handoff to Claude Code (2026-11-04)

Read this first, then `git log -1` on branch `work/highway-finish`.
Original brief: the "CHESTERWORLD ROBLOX — FULL PROJECT HANDOFF" document
(Phases A–E). This file records what has been done against it and what is next.

## Branch / how this arrived

- Base: `origin/fix/highway-pavement-continuity-20261104` (PR #2), which is
  `fix/street-owner-grade-separation` + 5 pavement-recovery commits.
- Work branch: `work/highway-finish` (one commit on top of PR #2).
- Delivered as `highway-finish-20261104.patch` (git format-patch) because the
  cloud session had no GitHub write access. Apply in `E:\code\chesterworld-roblox`:
  ```powershell
  git fetch origin
  git checkout -b work/highway-finish origin/fix/highway-pavement-continuity-20261104
  git am path\to\highway-finish-20261104.patch
  ```
- Nothing was pushed. No terrain, GIS source, tile data, spawn or orientation changed.

## Root causes found (all confirmed in code + offline harness)

1. **Bare-earth DEM notches.** Where a highway is the UPPER road (I-95 over Kerlin,
   over Chester Creek, US 322 approaches over Front/2nd/3rd/4th…), the DEM drops
   into a notch. `TileBuilderV2` followed it: I-95 dived from Y≈57 to ≈39 at
   Kerlin, and `safeGroundPair` deleted >40% pieces → the 24–34 stud holes in IDs
   424/425/426. PR #2 restores those as 45% cliff slabs (harness: cliff=12).
2. **Crossing detection never fired.** Source roads are split exactly AT their
   crossing vertex (all 108 corridor crossings touch at a segment end). Conformer
   `crossingT` and finisher `lineIntersection` required 0.02<t<0.98 → "No verified
   ground-road crossings", bridges never lifted for real lower roads.
3. **Terrain-level junction pads inside the highway.** 50 corridor-only nodes
   (merges/diverges/name changes) became flat pads; highway trimmed back to them.
4. **Steep check before subdivision.** A whole 120-stud strip dropped for one steep corner.
5. **County classes/layers unreliable.** Local overpasses classed `motorway`
   (Macdade Blvd, Bullens Ln, 2nd, 6th, Chester Pike, Amtrak, CSX…), I-95 classed
   `secondary/tertiary/residential`, `I 476` classed `primary`. Around most
   crossings BOTH roads carry z-level 1, so layers don't say who is on top.
   NBI inventory contradicts the source at Chestnut and Highland.
6. **Shared crossing vertices at Edgmont** (and other freeway vertices): I-95 and
   Edgmont share a vertex with level flips on both → V2 paved an at-grade pad
   across I-95 (same defect class as Kerlin).

## What was implemented (uncommitted-in-Studio, harness-validated)

| File | Change |
|---|---|
| `src/server/World/HighwayProfile.lua` (new) | Generator-owned corridor profile. Chains corridor segments into strokes (straightest pairing at merges), samples terrain every 6 studs, cuts narrow DEM spikes (90), fills bridged notches (rims within 240 on both sides), interpolates source-tagged bridge runs, enforces clearance over lower roads, caps under local overpasses (street rim − clearance, never below terrain), grade-limited upper envelope (mainline 0.07, ramps/connectors 0.10 in-world), smoothing, pins ramp ends to street level / previously solved strokes (local fades), classifies stations grade/fill/span, structure ids. Freeway vertex split: non-corridor roads sharing a vertex where ≥2 I-95/I-476/Barry-bridge arms meet get connection group `HWX` (generalised Kerlin fix). Crossing relation order: registry → DEM notch evidence (notch along a road ⇒ that road is upper) → unambiguous layers → unresolved (reported). |
| `src/shared/HighwayStructureRegistry.lua` (new) | KERLIN_I95 by source IDs + aerial footprint polygon (provisional) + NBI 14892 clearance. Name/location entries from NBI inventory: Edgmont (14989), Madison (14964), Upland (15445), Potter (15446), Chestnut (15448), Melrose (15449), Highland (14881) — all local street OVER I-95. |
| `src/server/World/TileBuilderV2.lua` | Calls `HighwayProfile.Prepare` on all roads before the graph; corridor-only nodes are not pads; profiled highway pieces (≤24 studs, split at structure boundaries, joint-wedge extensions) with attributes `CW_HighwayProfiled, CW_ElevationOwner=HighwayProfile, CW_StrokeId, CW_Station0/1, CW_HighwayStructure, CW_StructureId, CW_StructureBasis, CW_TerrainGapStuds`; white edge lines + station-phased lane dashes; no sidewalks/yellow centerline on profiled highway; subdivide-before-reject for all roads; omission accounting with coordinates (`TileBuilderV2.Stats()`). PR #2 steep recovery kept only as fallback for unprofiled corridor roads. |
| `src/server/World/TileBuilderV3.lua` | Prints `[HighwayPavement]` and `[PavementOmissions]` summaries; workspace attributes `CW_HighwayProfiledPieces`, `CW_PavementSteepOmissions`, `CW_PavementNoTerrainOmissions`. |
| `RoadTerrainConformer.server.lua` | Never moves `CW_HighwayProfiled` parts; keeps them as lower roads; crossing test accepts touching ends with angle filter and rejects the deck's own terminals/same-name approaches. |
| `HighwayInfrastructure.server.lua` | New `HighwayStructures` folder: spans → collidable deck, fascia, jersey barriers, abutments outside the opening, pier bents on spans >~110 (never on a road); fills → collidable retaining fill + barriers when >4 studs; continuity audit per stroke (`[HighwayHole]` with coords, `CW_HighwayHoles`); fixed crossing detection; clearance audit uses underpass rule for profiled spans. |
| `WorldConfig.lua` | `HIGHWAY_PROFILE_ENABLED` rollback switch + all tunables. |
| `Kerlin*Preview/DrivableTest` | Marked dev-only; refuse to run when production profile exists unless `{force=true}`. |
| `tools/harness/` (new) | Offline Luau harness: `roblox_mock.luau` (Vector3/CFrame/Instance/Raycast mock), `build_bundle.py`, `runner.luau` (synthetic bare-earth terrain + audits). `tools/highway/` source-data analysis scripts. |

## Harness evidence (synthetic terrain, Kerlin calibrated to Studio baseline)

Kerlin area (tiles r06–r08 × c06–c08), same terrain for every revision:

| Metric (highway corridor, 4-stud samples) | baseline branch | PR #2 | new |
|---|---|---|---|
| missing pavement samples | 16 | 0 | **0** |
| steps > 1 stud | 15 | 32 | **0** |
| samples steeper than 15% | 43 | 60 | **0** |
| cliffs > 40% | 0 | 12 | **0** |
| I-95 top at Kerlin joints | 39.2 (at grade with Kerlin) | 39.2 | **57.3** |
| opening over Kerlin | none | none | **16.0 studs** (≥ 12.9 inventory) |
| finisher crossings verified | 0 | 0 | 14 |

Drive profile across Kerlin (both carriageways, every 12 studs) is a flat 57.3;
baseline dives to 39.2 with gaps. Remaining "buried" samples ≤0.3 stud.
Full 102-tile comparison was started but NOT completed — first task below.

## Next steps for Claude Code (in order)

1. **Install tools & run the harness** (Windows): Rojo 7.7.1 (rokit), Luau CLI
   (github.com/luau-lang/luau releases). Then:
   ```powershell
   py tools\harness\build_bundle.py --rev WORKTREE --out $env:TEMP\new.luau
   luau -O2 $env:TEMP\new.luau > new.log
   py tools\harness\build_bundle.py --rev origin/fix/street-owner-grade-separation --out $env:TEMP\base.luau
   luau -O2 $env:TEMP\base.luau > base.log
   ```
   Compare `AUDIT_CORRIDOR / AUDIT_ALLROADS / AUDIT_KERLIN` lines; fix regressions
   (use `--tiles r06-r08,c06-c08` for a 5-second loop, `--extra probe.luau` for probes).
2. **`rojo build`** to a temp `.rbxlx` and a **full Studio Play** (not QuickStreetPreview).
   Record `[HighwayProfile]`, `[HighwayPavement]`, `[PavementOmissions]`,
   `[HighwayStructures]`, `[HighwayHole]`, conformer and finisher lines.
   Acceptance: holes=0, steps≈0, Kerlin opening ≥12.9, drive I-95 both directions
   and Kerlin underneath with a vehicle, check terrain does not poke through spans.
3. **Tune with REAL DEM** (only Studio has it): watch `unresolved` crossings list,
   `cutStations/worstCut` (terrain above pavement), `gradeViolations`, fill heights.
   If a notch fill misfires on a real cut, adjust `HIGHWAY_PROFILE_NOTCH_WINDOW_STUDS`
   or add a registry entry — do not edit terrain.
4. **Phase C remainder:** local overpasses over I-95 (Edgmont, Madison, Upland,
   Potter, Chestnut, Melrose, Highland) are still RoadTerrainConformer bridges; with
   crossing detection fixed they now try to clear I-95, but several were
   `BridgeGradeLimited` with `rampStart=0` (approach chains not found within 6 studs
   of trimmed terminals). Fix `findApproachChain` tolerance/pad trimming, use
   registry clearances (≈15–20 studs) instead of a flat 18.
   Verify with imagery: Highland (source says I-95 over, NBI 14881 says Highland
   over), I-95 vs "Ramp E & F to Barry" (NBI 14886: I-95 over ramps; source says
   ramp over), Engle St, Bullens Ln, Chester Pike, Macdade (no registry entry yet).
   US 322 / Commodore Barry: river span height unverified (NBI 15452).
5. **Phase D:** median treatment for dual carriageways, ramp gore markings,
   one-way direction for left (yellow) edge lines (needs oneway data).
6. **Phase E:** commit harness results as before/after report; open PR replacing
   PR #2 (it is the base of this branch; its fallback path is retained).

## Provisional values (must stay flagged)

Kerlin footprint polygon (aerial visual pick), all clearances (inventory, not
surveyed in-world), structure depth 1.6 (cosmetic), synthetic harness terrain.

## Sources
- NBI-derived Chester bridge list: https://www.city-data.com/bridges/bridges-Chester-Pennsylvania.html and …Pennsylvania2.html
- Kerlin structure 14892: https://usbridges.org/bridge/pa-county-045-bridge-000000000014892
- Edgmont over I-95 & CSX: https://bridgecondition.com/bridge/pennsylvania/pa-000000000014989
