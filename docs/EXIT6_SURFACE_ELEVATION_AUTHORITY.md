# Surface elevation authority

Road collision Parts are the finished elevation reference. `TileBuilderV2`
initially samples Terrain at road endpoints; `HighwayProfile` owns motorway
grades. `RoadTerrainConformer` subsequently moves bridge decks, approaches,
registry overpasses, selected embankments, and short road seams. The Kerlin
lower road under `KERLIN_I95` is now profiled on its four original county
segments between source vertices (7024.280, 7184.991) and
(7006.124, 7218.855), with grade and correction limits. Its road Parts remain
the driving collision geometry.

| Surface | Initial source | Final owner |
| --- | --- | --- |
| At-grade roads | Terrain endpoint samples | RoadTerrainConformer road Parts |
| Bridges and highway | Source tags, registry, HighwayProfile | Existing bridge/highway road Parts |
| Junction wedges | Terrain plane | Refit in place from finished at-grade road ends |
| Sidewalks | Road-center Terrain samples | Finished adjacent road Parts |
| Centerlines and crosswalks | Terrain samples | Finished same-street road Parts |
| Mapped parking | Existing Terrain collision; OSM material polygons | Existing Terrain collision, material only |
| Gas forecourts | Terrain under canopy | Nearby finished road where within two studs; Terrain takes collision where a slab overlaps a road, walk, another canopy, or uneven ground |
| Gas entrances | Forecourt and finished road tops | Graded ramp Parts; intersecting sidewalk Parts are split around the entrance |
| Kerlin over Chester Creek (Crozer Park) | `WorldData/DesignedRoadProfiles` chord between bank anchors | TileBuilderV2 strip sampling (road, sidewalks, centre line); LocalBridgeDressing dresses it |
| Lot access crossings | Finished road top, walk top, final lot Terrain | `AccessCrossings`: curb-cut apron replaces the split walk; two eased strips to the lot at <= 12 % |

`RoadTerrainClear` removes Terrain protruding above road, junction, and walk
footprints after road conformance; `WaterBuilder` restores mapped water after
that pass. `RoadGapRepair` runs later and inserts asphalt only for dry,
two-anchor omitted chains passing its existing terrain and grade checks.
`LocalBridgeDressing` decks remain visual support below a collidable road,
without an extra deck collider.

When the Roblox server builds the city, Output reports measured collision
height differences before and after under `RoadSeamJoins`,
`IntersectionContinuity`, and `FinalSurfaceAlignment`. Workspace attributes
`CW_RoadSeamBeforeMax/AfterMax`,
`CW_IntersectionContinuityBeforeMax/AfterMax/Failures`, and
`CW_SidewalkAlignmentBeforeMax/AfterMax` retain the maxima. The junction
check raycasts actual collidable intersection wedges at road mouths. It warns
for residual gaps over 0.65 studs. `KerlinSourceProfile` reports whether its
source correction applied and its maximum deviation.

These are runtime measurements; numerical before/after results require a
Roblox run. The source topology guard is
`python tools/test_surface_continuity_source.py`.
