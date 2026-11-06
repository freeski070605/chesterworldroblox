# Crossing inspection, phase 3 (2026-11-05): LOW CLEARANCE 49 -> 0 (offline)

All relations below were checked against the DVRPC 2025 orthophoto
(`tools/harness/crossing_aerial.py OUTDIR <site>`; images in build/aerial).

| Site | Finding | Change |
|---|---|---|
| chester_pke | I-95 + I-476 ramps on decks over Chester Pike (layer tags reversed) | `I95_OVER_CHESTER_PKE` |
| flower | Barry approach over Flower St | `BARRY_OVER_FLOWER`; county 21223/21244 (Barry, mis-classed residential) made corridor |
| riverfront | Barry approach over Chester Riverfront | `BARRY_OVER_RIVERFRONT` |
| crosby | Footbridge over I-95, Edgmont ramp, CSX | `CROSBY_FOOTBRIDGE_OVER_I95` |
| csx_476 | I 95 to N I 476 ramp over CSX (tags reversed) | `I95_N476_RAMP_OVER_CSX` |
| csx_crum | Crum Lynne over CSX | `CRUM_LYNNE_OVER_CSX` |
| i476_flyover | Flyover over I-95; I 476 to I 95 ramp under I-95 decks | `N476_FLYOVER_OVER_I95`, `I95_OVER_I476_TO_I95_RAMP` |
| park_vallei | Parking lot, no structure | `Registry.GROUNDED` PARK_VALLEI_PHANTOM_BRIDGE |

Generator changes
- HighwayProfile: under a registry-confirmed local overpass the highway may go
  below terrain (cut); registry pairs meeting at a shared vertex on separate
  level nodes are kept as crossings; `LocalOverpasses()` export;
  `CORRIDOR_SOURCES` for mis-classed corridor records.
- RoadTerrainConformer: `[RegistryOverpass]` pass holds registry overpass
  streets at deck level (street rim, >= highway top + clearance), easing out at
  MAX_GRADE, only raising; registry relations also ground lower roads under
  profiled highways; `Registry.GROUNDED` components stay on terrain.
- HighwayInfrastructure: audit uses the underpass rule for registry overpass
  decks; LOW CLEARANCE lists every pair with location and requirement.

Offline: lowClearance 0 (was 49 / 101 before phase 3), registry 176,
gradeViolations 0, pinConflicts 0, buried 24, steps 5, Kerlin 16.03.
Open: profile clearanceShort for the N I 476 flyover over I-95 (-3.9) on the
synthetic interchange terrain; needs the real DEM (Studio) to judge.

## Studio run with real DEM (2026-11-05, driven through the Studio MCP)

The first real-terrain run exposed what the synthetic harness could not:

| Problem (real DEM) | Cause | Fix |
|---|---|---|
| N I 476 flyover ~15 studs *below* I-95 (hidden: the audit skips pairs where the "upper" is >1.5 below) | Notch fill raised the I 476 to I 95 ramp out of its real DEM cut under the I-95 embankment, pushing I-95 to 61-67 | Registry "under" crossings cap the lower highway at (upper rim - clearance) even before the upper stroke is solved; no cut under another highway (the upper rises instead) |
| Flyover dragged down over the I 476 to I 95 ramp | ramp relation undecided | `N476_FLYOVER_OVER_I476_TO_I95_RAMP` |
| Flyover pinned to the valley floor at its "merge" (12256, -7360) -> CSX 9.3, I-95 4.2 | shares a source vertex with the I 95 to I 476 ramp but crosses over it [n476_merge] | `N476_FLYOVER_OVER_I95_TO_I476_RAMP`; county 1177 made corridor |
| US 322 to US 13 "over" 7th (10.0) and a 12-stud step | ramp ends at a signalised junction with 7th [flower] | `Registry.AT_GRADE` US322_TO_US13_AT_7TH |
| Barry over Flower 9.8 / 11.5 | Barry pinned to grade at 7th 200 studs on | `BARRY_OVER_7TH` (medium confidence: no 7th pavement across the Barry lanes); county 21219/20300 made corridor |
| Bullens Ln over MacDade ramp 4.2, 11-stud step | county 21560 not corridor while its neighbours are | county 21560 made corridor |

Final Studio run: HighwayProfile clearanceShort=0, gradeViolations=0, pinConflicts=0,
registry=198; HighwayFinish lowClearance=0, minClearance=14.0; HighwayStructures steps=0,
holes=0; HighwayCuts deepest 21.3 (Edgmont).
Still reported (not clearance): 40 bridge terrain intrusions (worst Bullens Ln west bridge
county 20931, 8.7), 21 unprofiled bridge parts, 1 tunnel obstruction.

## Bridge terrain intrusions and the Amtrak underpass (Studio, real DEM)

The 40 "bridge segments intersect terrain" were county bridge tags that cover
a structure's approach embankments (aerial [bullens_west], [highland],
[upland]): the conformer's straight deck line between a component's ends ran
under that fill (Bullens Ln from Governors Rd, 8.7 studs).

- RoadTerrainConformer `[BridgeEmbankment]`: a non-profiled bridge piece's
  surface never sits below the terrain (two-pass endpoint plan keyed by street
  and position so neighbouring pieces stay joined; markings follow). Pieces left
  resting on the ground are `CW_OnEmbankment` approaches.
- HighwayInfrastructure: embankment approaches are not counted as decks through
  terrain (`embankmentApproachParts`); tunnel/underpass pieces with terrain over
  them are cut open like the highway (`CW_TunnelCutDepth`).
- Bug found on the way: keying shared endpoints by position alone let another
  street's piece lift Upland St 46 studs; keys now include the street name (also
  in the RegistryOverpass pass).

Studio: bridgeTerrainIntrusions 40 -> 0, tunnelObstructions 1 -> 0 (Amtrak at
(-9012, 10610) cut open), embankment max lift 7.4 (Bullens Ln), lowClearance 0,
minClearance 14.0. The 21 "unprofiled" bridge parts are over creeks where the
DEM has no terrain (9th St over Chester Creek, Industrial, Morton); harmless.
