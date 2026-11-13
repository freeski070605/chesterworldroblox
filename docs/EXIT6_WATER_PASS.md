# EXIT 6 GIS waterways: one-pass build

Run in PowerShell:

    cd E:\code\chesterworld-roblox
    .\run_exit6_water_pass.ps1

The command pulls main, reads the existing regional GIS tile JSON under
E:\ChesterWorld\Data\16_RegionalTiles\Tiles, generates the 4-stud-aligned
WaterData modules, commits/pushes only the generated GIS modules/report,
then starts Rojo. Reconnect in Studio and start a fresh Play test.

Expected logs:
- [EXIT6 Water GIS] read=... mapped polygon cells=...
- [EXIT6 Water] COMPLETE ... waterVoxels=... solidProtected=...
- [ChesterWorld PavementTerrainSurvey] ... mappedWater=mappedPolygon/notMapped/approxStream
- [EXIT6] World ready: ... roads/highway/parks/gas/water complete

Safety:
- No guessed Delaware shoreline; mapped polygon boundaries come from the
  preexisting regional GIS tile layer water_areas.
- Stream line widths are conservative approximations if the source contains
  no measured width. They are separately counted in the export report.
- East +X, north -Z, scale 3 studs/metre, 4-stud voxel grid preserved.
- Existing solid Terrain is never excavated; only Air is turned into Water.
  This protects imported land, Industrial, highway crossings, and banks.
- Deepening the mapped riverbed must be a separate, backed-up, reviewed
  operation. Shallow or partially dry areas may remain where DEM terrain
  occupies the expected water volume.
- Once the one-time Studio bake is verified, runtime skips all water generation.
  Run `require(game.ServerScriptService.Server.World.WaterBake).Run()` in the
  Studio **Edit-mode** Command Bar only, then save the place. First make a
  separate backup of the original terrain; see `docs/EXIT6_STUDIO_WATER_BAKE.md`.
  Until a bake exists, runtime generation remains available as a fallback.
- If water polygon source coverage is empty, export fails rather than
  inventing features. No data installed yet is a nonbreaking warning;
  if water generation fails with data, loading remains up with an error.

Useful attributes: CW_WaterStatus, CW_WaterPatchesDone,
CW_WaterPatchesTotal, CW_WaterFilledVoxels, CW_WaterSolidCellsProtected.
