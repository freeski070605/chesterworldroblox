# Exit 6 sports facility reconstruction (aerial-verified)

Branch `feature/basketball-court-pilot`. Baseline `bbb7a05` / `backup/parks-restored`
untouched. Data: `src/shared/Exit6VerifiedSports.luau`; builder:
`src/server/World/ParkBuilder.server.lua`; mesh calibration:
`src/shared/Exit6SportsMeshIds.luau`.

## Coordinates and imagery

* World studs: +X east, **+Z south (north = -Z)**, 3 studs per EPSG:3857 metre
  (`tools/build_parks.py: studs()`), ≈3.91 studs per ground metre at Chester.
  Parks.lua already uses this convention; the old test asserting `-1541.6` was stale.
* Imagery: DVRPC 2025 orthophoto (PASDA `DVRPC2025/MapServer`, layer 4), fetched
  per facility at 2–5 px/stud by `tools/sports/aerial.py` (cached in
  `build/sports_imagery/`). Native ground resolution ≈ 0.3 m, so court-level
  detail is ±1–2 studs.
* Tools: `tools/sports/overlay.py` (draw ParkBuilder boxes on imagery),
  `tools/sports/audit_sheets.py` (citywide contact sheets → `build/sports_audit/`),
  `tools/sports/before_after.py` (→ `build/sports_reference/before_after_*.jpg`).

## Chester Memorial Park — 2700 W 7th St (OSM "Veterans Memorial Park")

| Element | World centre (x, z) | Size (studs) | Yaw | Evidence |
|---|---|---|---|---|
| Basketball court 1 | -3437.8, 5798.5 | 99.5 × 59.3 | 124.1 | OSM outline; painted centre circle within 3 studs |
| Basketball court 2 | -3378.8, 5758.4 | 99.5 × 59.3 | 124.1 | same |
| Asphalt pad (both courts) | -3406.2, 5776.9 | 159.1 × 122.2 | 33.7 | segmented asphalt, min-area rectangle |
| Football field | -3586, 6081 | 428.5 × 190.6 (360 × 160 ft) | 124.2 | centre/axis of the 4 light-pole bases (225 × 212 rectangle); bleacher rows and west fence parallel; across-axis open ground is only ~381 studs, so the field cannot run the other way |
| Bleachers (4) | (-3506, 5984) E; (-3736, 6112), (-3689, 6181), (-3646, 6247) W | 31 × 7.5 | 124.2 | bright aluminium benches |
| Light poles | (-3552, 5931) (-3739, 6056) (-3433, 6106) (-3621, 6231) | 70 tall | — | shadow roots |
| Fence | (-3730, 5885) → (-3825, 5960) → (-3767, 6070) | 8 tall | — | chain-link line in high-pass image |

Before: field at (-3700, 5950) yaw 12 (≈90° off, centred on the NW fence corner);
hoop meshes centred 0.6 above the slab (pole ~6 studs buried, rim at ~4 not 10)
and turned so the rims faced **away** from the courts; slab at the highest of 25
samples (pad 32.0 over ground 29.2–32.1) on a 6-stud skirt.

Courts and tennis are unchanged in plan (OSM matched the aerial). Remaining
uncertainty: grass field has no visible yard lines in the 2025 image (dormant
turf), so its ends are inferred from the lit rectangle and the north fence
(±10 studs along the axis); pad edge ±4 studs.

## Chester Athletic Complex A Field — 1100 W 10th St

| Element | Value | Evidence |
|---|---|---|
| Shared axis | yaw -83.86 (long axis 6.1° east of south) | PCA of the segmented red track; field yard lines on the same axis |
| Track | infield centre (13.4, 1545.2); inner kerb 636 × 249 (straights ±193.5, radius 124.5); outer 696 × 309; 6 lanes in a 30-stud band | track segmentation (outer ±154.5 across) |
| 100 m chute | west straight continues north to local x = -303 | visible extension |
| Football field | centre (13.27, 1543.96), 431.4 × 191.7 | 21 yard-line peaks at 17.98-stud spacing; goal lines at u = -181 / +178.5 |
| West grandstand | (-178.4, 1563.0), 286 × 47, faces east | roof segmentation |
| East bleachers | (187.9, 1529.0), 203 × 24, faces west | roof segmentation |
| Surface | one level for track + field (`a_field` group, median of plateau) | Studio samples: plateau 75.0, field crown +1.4 |

Before: OSM box (17.3, 1541.6) yaw -83.3 (5 studs / 0.6° off), and the 560 × 260
oval mesh: its 94-stud inner radius scaled to the measured outer width would give
a 223-stud infield and 43-stud lanes, so the track is now built from measured radii
(24 facets per bend) instead of a stretched mesh. Remaining uncertainty:
perimeter fence/entrances are not resolvable at 0.3 m and were not invented;
lane count from the band width (30 studs ≈ 7.7 m = 6 × 1.22 m) agrees with the
school district's "current six-lane track".

## Citywide audit (64 OSM sports polygons, `build/sports_audit/sheet_*.jpg`)

| Result | Features |
|---|---|
| Matches aerial, unchanged | all other basketball (incl. #46/#47 cross court), tennis, volleyball, soccer (#19, #33, #55, #56), Subaru Park, Widener stadium |
| Dropped — nothing there in 2025 | tennis (-3745.6,-13188.7), (-3855.5,-13146.3), (-3801.6,-13167.6); basketball (-3690.9,-13210.3); tennis on a building roof (5285.3, 4459.1); baseball meadow (9645.6,-5766.6) |
| Split | soccer (-547.9, 8780.3) 833 × 589 → three 414 × 225 pitches; baseball (-2026.1,-6723.4) → two fields |
| Remeasured | baseball (-12559, -1938.6): box covered only the infield half → home plate (-12674, -1789), 366-stud foul lines |
| Home plate corrected | every baseball diamond now has home plate at the imaged box corner and foul lines on the box edges (was: middle of one end) |
| Half courts | (-4466.6,-9617.9), (-4499.6,-9657.7): one hoop, two Rim targets on it |
| Track | Widener (8364.9,-7026.5): curved 8-lane blue oval from the box (was four straight strips) |
| Filter fix | the three steeplechase fragments were built as tracks (key was `track`, not `athletics`); now filtered as documented |

## Elevation and terrain

* Level = median of terrain samples on a ~12-stud grid (courts level; fields a
  least-squares plane clamped to ≤1% along their length, no cross slope).
* Terrain conform, per surface or group: inside → level − 0.6 (Ground material,
  so grass decoration cannot clip through), then a smoothstep feather over 12
  (courts) / 20–24 (fields) studs back to the original ground. A column is never
  changed by more than 9 studs, and columns within 3 studs of roads, sidewalks,
  intersections, buildings, rail, highway structures, landmarks, gas stations,
  bridges, or any water are left alone.
* Voxel heights are calibrated per site against raycasts: Chester's rendered
  terrain surface sits 2.0 studs above `bottom + occupancy × 4` (the first run
  without calibration left every surface 1.4 below the grass). Verified after
  calibration: terrain − surface median −0.59/−0.60/−0.61 (target −0.60), never
  above the surface, edge gap ≤ 0.8 at Memorial pad / Memorial field / A Field.
* Runtime-only: the saved place terrain is untouched. All writes are
  snapshotted; `game.ServerStorage.Exit6SportsTerrain:Invoke("restore")` puts
  them back, `:Invoke("report")` lists them. `workspace:SetAttribute("Exit6SportsConform", false)`
  before ParkBuilder runs disables conforming.
* Base surfaces hang only as deep as the post-conform edge requires (1.6–8 studs)
  instead of the old blanket 6-stud skirt.
* Playgrounds, pools and cemeteries keep their original placement code and are
  built after sports so they sit on the final ground.

## Meshes

All five uploaded meshes load (`AssetService:CreateEditableMeshAsync` in Studio,
2026-11-25). Measured from vertices: hoop 3.785 × 13.15 × 6, rim centre at
(+0.7875, +3.425, 0) from the bounds centre (rim faces +X after the importer's
180° turn), pole base (-1.6125, -6.575, 0). SpecialMesh scale = wanted ÷ MeshSize.
The +X hoop is turned π, the −X hoop 0, both carriers at rim − offset; the
gameplay `Rim` part sits on the visible rim (10 studs). Court paint (lines at
±49 × ±29, arc centre ±45) and football paint (±179 × ±79) are scaled to each
court/field; bleachers use the section mesh with rows rising away from the field.
The six-lane oval mesh is no longer used.

**Texture defect in the uploads.** The uploaded meshes kept Blender's primitive
unwrap UVs (e.g. the hoop's UVs span 0–1 in both axes) instead of the
`Palette UV` layer `build_sports_meshes.py` adds, so the palette texture
(verified intact: 256 × 32, seven swatches) is sampled at arbitrary colours —
red/black dashes on court lines, a red backboard. Until the GLBs are re-exported
with the palette layer as `TEXCOORD_0` and re-uploaded, `plainMeshes = true`
renders every sports mesh untextured in its carrier colour (paint white,
hoop/bleachers galvanised 191,199,199) and each hoop gets an 8-segment orange
rim ring over the mesh rim.

Rendering details found in Studio: thin track strips 0.06 above a coplanar grass
pad lost the depth test beyond ~400 studs, so oval facilities now have an
infield-only grass base and the track band is its own 1.6-deep surface; field
conform extents equal the grass surface so no bare-Ground band shows.

## Studio commands

```lua
-- report terrain conform sites / undo them
print(game.ServerStorage.Exit6SportsTerrain:Invoke("report"))
print(game.ServerStorage.Exit6SportsTerrain:Invoke("restore"))
-- teleport (Server context; replace the player name)
local function go(x, y, z) game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(x, y, z)) end
go(-3406, 40, 5777)   -- Memorial courts
go(-3586, 40, 6081)   -- Memorial football
go(13, 85, 1545)      -- A Field
go(8364, 40, -7027)   -- Widener stadium track
-- list verified models
for _, m in ipairs(workspace.ChesterParks.Features:GetChildren()) do
	if m:GetAttribute("Facility") or m:GetAttribute("Verified") then print(m.Name, m:GetAttribute("Facility"), m:GetPivot().Position) end
end
```
