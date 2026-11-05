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
