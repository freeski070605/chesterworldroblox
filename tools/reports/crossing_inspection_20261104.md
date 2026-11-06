# Highway crossing inspection — 2026-11-04

Resolves the crossings the generator listed as `[HighwayProfileUnresolved]`, plus
the ones you flagged for review. Every decision below is checked against the 2025
aerial photo, with the county source segments drawn on top.

## Method

- **Source records.** `python tools/harness/crossing_source_report.py [radius]`
  lists every county record within the radius of each pin. It also lists every
  point where two differently named records cross or share a vertex, with layer,
  bridge flag, class and angle.
- **Aerial.** `python tools/harness/crossing_aerial.py build/aerial [site...]`
  fetches the DVRPC 2025 one-foot orthophoto (PASDA layer 4) around each site.
  It writes two images per site:
  - `<site>_raw.png`: the photo alone.
  - `<site>_src.png`: the photo with county segments drawn on top. Red means
    layer 1 / bridge-tagged, cyan means layer 0. Pins are yellow squares.
- **Coordinates.** Roblox studs convert to EPSG:3857 as
  `mx = -8397592 + 6347.889 + x/3` and `my = 4837229 + 7201.973 - z/3`. The
  origin was back-solved from the Crossing Aerial Inspector pins. It comes out as
  whole numbers, matching the floored origin in `build_regional_expansion.py`.
  Segments drawn this way land on the visible pavement.
- **Evidence used:** deck expansion joints, shadows cast by decks, a lower road
  visible on both sides of a structure, continuous lane markings, and gore
  geometry. No heights were measured, and no bridge heights were invented.

## Systemic finding: county bridge flags mark both roads

Under a structure, the county data tags the **lower** road's pieces as
`layer=1, bridge=true` too. Examples:

| Site | Lower road | Its records tagged layer 1 / bridge |
|---|---|---|
| Engle | I-95 | 681, 682, 783, 784 |
| Bullens (I-476) | I-476 | 20451, 20453, 473 |
| Bullens (I-476) | MacDade ramp | 20452 |
| 05 | Bullens | 21446, 20386 |
| 2nd St | 2nd | 26160, 26449, 26648–26651 |

So layer and bridge tags alone cannot say which road is on top. This also
explains `RoadTerrainConformer` trying to lift lower roads:
- 2nd: requested lift 56–57 studs
- MacDade Blvd to I 476: requested lift 65 studs

That conformer behaviour is not changed here.

## Decisions

Confidence levels:
- **High:** the photo shows the structure unambiguously.
- **Med-high:** the photo plus geometry or DEM agree, but no inventory record
  confirms it.
- **Hold:** not decided. The generator applies **no clearance rule** to the
  crossing.

| Pin | Roblox (x, z) | County records | Upper | Lower | Evidence | Confidence | Registry |
|---|---|---|---|---|---|---|---|
| 01a | (-2838, 2132) | I-95 21255/21256 × Conchester 20524/21254 (shared vertex, 51–55°) | I-95 | Conchester | Conchester passes between I-95 deck joints and comes out on both sides. DVRPC: dual I-95 bridges over the US 322 approaches. The source is an X (both roads run straight through), not a merge. | High | `I95_OVER_CONCHESTER` |
| 01b | (-2785, 2168) | I-95 16139/21257 × Conchester 21254/20525 (59–64°) | I-95 | Conchester | Same structure, other carriageway. | High | `I95_OVER_CONCHESTER` |
| 02 | (-2912, 2097) | I 95 From Exit 4 26664→22858 × Conchester 20523/20524 (48–51°) | I 95 From Exit 4 | Conchester | The ramp leaves the I-95 deck and carries on as the elevated flyover (22858). Conchester runs beneath in its shadow. The real DEM puts the ramp ~52 studs above Conchester (`HighwayProfilePinConflict HW6 dy=52.5`). **Not at grade**, which overturns the earlier call. | Med-high (no inventory record) | `EXIT4_RAMP_OVER_CONCHESTER` (provisional) |
| 03a | (-2564, 2078) | I-95 21257 / 21259 × ramp 26663→26562 (37–41°) | I-95 | I 95 to Comm Barry | One skewed I-95 span between deck joints covers both 03a and 03b. NBI 14886: I-95 over the Barry ramps. | High | `I95_OVER_COMM_BARRY_RAMP` |
| 03b | (-2513, 2003) | I-95 21256 / 21258 × ramp 26562→26563 (29–32°) | I-95 | I 95 to Comm Barry | Same span. The ramp's own elevated structure (26563, layer 1) starts *at* this vertex, so the layer rule put the ramp on top. That reading was wrong. **14886 explains both crossings. The county data did not merge two ramp movements.** | High | `I95_OVER_COMM_BARRY_RAMP` |
| 04a/04b | (-4650, 3087), (-4598, 3128) | Engle 21206/21207 (/18057) × I-95 681/682/783/784 (69°) | Engle St | I-95 | The Engle deck casts its shadow across both carriageways, with sign gantries under it. DVRPC inventory. | High | `ENGLE_OVER_I95` |
| 05 | (10589, -5484), (10571, -5522) | I-95 559/428, 854/427 × Bullens 21446/20386 (70–74°). Ramps 26098 (diverge, 36°) and 26181 (merge). | I-95 + I-476 ramps | Bullens Ln | Concrete I-95 deck, with Bullens visible beneath on both sides. Both ramps split from or join I-95 **on the deck**, at the same level. | High | `I95_OVER_BULLENS`. Gores: `AT_GRADE I95_I476_RAMP_GORES` |
| 06 | (-1055, 5237) | 6th 26640/26641/7819/26529 (layer 1 / bridge) × US 13 to US 322 18253, Barry 21220/20299/18081 | — | — | **No structure carries 6th across the approach.** 6th St ends at the west barrier wall. Lane markings run straight through. Between the highway and Flower St there is only vegetation. The source's 6th bridge records describe a structure the 2025 photo does not show. Nothing raises 6th; the LOW CLEARANCE line is a report only. | High (no crossing) | none (hold). The records are tile data, left unchanged. |
| 07a | (80, 6754) | 2nd 26160/26647 × PA 291 to WB US 322 21232 (layer 0) / 21238 (layer 1) | — | — | The Barry mainline (21239/21240/21212/21230) is clearly elevated over 2nd. The ramp changes from layer 0 to layer 1 at this vertex, consistent with the ramp starting at grade at 2nd. Not resolvable at this photo resolution. | Hold | none |
| 07b | (-48, 6842) | 2nd 25087/26648 × US 322 to PA 291 26652 (layer 1) / 22591 (layer 0) | — | — | Same pattern: the ramp seems to come down to grade at 2nd. Not resolvable. | Hold | none |
| 08a | (9510, -12229) | I-476 65/473 × MacDade Blvd to I 476 20452 (shared vertex, **16–18°**) | — | — | **Same-level merge.** The ramp is an extra lane inside the I-476 northbound carriageway, with no separate structure. The NBI 15481 "I-476 over ramp" structure is not at this point. | High | `AT_GRADE MACDADE_RAMP_MERGE_I476` |
| 08b | (9459, -11609) | Bullens 20931/21562 × I-476 437/474/20453 (73–74°) | Bullens Ln | I-476 | One Bullens deck spans the whole I-476 cut and casts a large shadow on it. | High | `BULLENS_OVER_I476` |
| 08c | (9570, -11643) | Bullens 21560/21561 × MacDade ramp 18298/20452 (75–76°) | Bullens Ln | MacDade ramp | The same deck. The ramp lane is visible under it on both sides. | High | `BULLENS_OVER_I476` (lower names extended) |

## Generator changes

- `src/shared/HighwayStructureRegistry.lua`
  - New `NAMED` entries:
    - `I95_OVER_CONCHESTER`
    - `EXIT4_RAMP_OVER_CONCHESTER` (provisional)
    - `I95_OVER_COMM_BARRY_RAMP`
    - `I95_OVER_BULLENS`
  - `BULLENS_OVER_I476` now covers the MacDade ramp too.
  - New `AT_GRADE` list and `Registry.AtGrade()`.
  - No underclearance values were added anywhere, so the default underpass rule
    applies.
- `src/server/World/HighwayProfile.lua`
  - The crossing split at a freeway vertex keeps `AT_GRADE` gore arms joined
    to the through road. Before, the 36° I-476 ramp gores at 05 were detached
    from I-95.
  - The split also applies at a non-freeway vertex when the registry names a
    crossing there (02).
  - `decide()` records `AT_GRADE` pairs as `atGrade`, with no clearance rule.
  - New summary field: `atGrade=`.

## Offline results (synthetic-terrain harness, full map)

| Metric | Before (HEAD registry: Engle + Bullens) | After |
|---|---|---|
| registry decisions | 77 | 110 |
| atGrade | 0 | 2 |
| unresolved | 72 | 43 |
| clearanceShort | 2 | 3 |
| buried samples | 876 | 901 |
| corridor steps / cliffs / missing | 5 / 2 / 0 | 5 / 2 / 0 |
| pin conflicts | 0 | 0 |
| Kerlin opening | 16.03 | 16.03 |

The 25 extra buried samples all lie on the Barry ramp next to 03a, at most
0.37 studs deep.

The harness terrain is **synthetic**. It carves a notch wherever the source
tags say a highway passes over, so burial numbers at re-decided crossings are
partly artifacts. Real burial has to come from Studio.

### Remaining conflicts

1. **Engle St over I-95.** I-95 and its ramps are cut up to 14.9 studs below the
   terrain at (-4533, 3088), the largest burial cluster (about 300 samples).
   Studio showed no DEM notch at Engle (0.0/0.0), so the real terrain is likely
   similar. The fix needs one of:
   - an Engle overpass lift, or
   - a terrain cut, which the handoff forbids.
2. **Bullens Ln over I-476 / MacDade ramp.** The required clearance is 14, but
   the opening is only:
   - 6.5 over I-476 at (9459, -11609)
   - -2.1 over the MacDade ramp at (9570, -11643)

   I-476 is buried up to 12 studs beside the bridge. This needs a Bullens
   overpass lift; it's the same open item as Edgmont, Melrose and Madison.
3. **The conformer lifts lower roads that the county tagged as bridges**: 2nd,
   the MacDade ramp, and possibly others. See the systemic finding above.
4. **Held:** 06 (6th, no structure), 07a/07b (2nd ramp tie-ins). Rail and
   pedestrian crossings also remain unresolved, by design.

## Phase 2: terrain cuts and lower-road grounding (same day)

You approved terrain cuts ("if we have to cut terrain we can"); Engle needs no
raising.

- **Highway cuts** (`HighwayInfrastructure.server.lua`, `[ChesterWorld HighwayCuts]`).
  Wherever profiled grade/fill pavement sits below the terrain:
  - terrain is cleared with `Terrain:FillBlock(Air)` over the road width plus
    4 studs each side, from 0.4 stud below the pavement top to above the ground;
  - cuts deeper than 3 studs get concrete retaining walls, except where
    another piece of pavement (a ramp gore) runs along the wall line;
  - spans are never cut, and depth is capped at 32 studs.
- **Lower roads are no longer lifted** (`RoadTerrainConformer`,
  `[ChesterWorld LowerRoadNotLifted]`). A county bridge-tagged component that
  passes under a highway span, under a highway more than 8 studs above the
  terrain, or under a registry-named upper road is dropped back onto the terrain.
  `BridgeGradeLimited` now reports `drivenBy=`.
- **Registry crossings at shared vertices are not junctions** (`HighwayProfile`
  step 5b). Previously a county vertex shared by the Barry mainline and 2nd made
  an "at-grade junction" and pinned the Barry to the terrain.
- **New registry entry** `BARRY_MAINLINE_OVER_SECOND`.
- **6th Street phantom bridge** (26640 / 26641 / 7819 / 26529) is skipped at
  build time via `Registry.SUPPRESSED`. The tile data is unchanged.

| Offline metric | Phase 1 | Phase 2 |
|---|---|---|
| buried samples | 901 | 36 (all < 0.5 stud) |
| clearanceShort | 3 | 0 |
| registry decisions | 110 | 122 |
| unprofiled bridge parts | 21 (Studio) | 0 |
| corridor steps / cliffs / missing | 5 / 2 / 0 | 5 / 2 / 0 |
| Kerlin opening | 16.03 | 16.03 |

The cut pass covers 954 pieces with 303 wall segments; the deepest cut is
16.4 studs, at (9151, -4019).

Left for the next pass, driven by the real DEM:
- Edgmont, Madison and Melrose over I-95: clearance is 2.5–2.8 studs.
- Chester and Chester Riverfront: the terrain inside the span drives a 65-stud
  lift request.

## Studio check

In the `[ChesterWorld HighwayProfile]` line, expect:
- `atGrade=2`
- fewer `unresolved=`
- `pinConflicts=0`: the HW6 conflict should disappear now that 02 is split.

Then look for `[HighwayProfileCut]` lines near Engle (-4600, 3080) and Bullens
(9459, -11550).
