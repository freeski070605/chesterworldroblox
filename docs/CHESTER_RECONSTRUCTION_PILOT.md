# Exit 6: Chester Reconstruction Pilot (9th & Kerlin)

This is **phase 0**, a non-destructive proof of the same broad data-to-world approach: real building footprints -> georeferenced Roblox preview -> later LiDAR height/roofs, image-assisted facades, procedural interiors and LODs.

## Verified against this repository
- `src/shared/WorldPlacement.lua`: 3 studs/m; +X east; -Z north.
- `src/server/Bootstrap.server.lua`: current tile loading and road building remain authoritative.
- `default.project.json`: Rojo maps `src/shared` to ReplicatedStorage.Shared and `src/server` to ServerScriptService.Server.
- This branch does **not** alter terrain, roads, the 102 tile modules, bootstrap or gameplay. The new preview script is OFF by default.

## Data inputs
Use a **legally reusable** GeoJSON FeatureCollection in WGS84 lon/lat coordinates with `building` or `building:part` tags. Export from OpenStreetMap/Overpass or a suitably licensed local government building footprint dataset. Respect source attribution and licenses. Google Maps/Earth/Street View can be researched within their terms, but do not scrape/redistribute Google's imagery, extract 3D models or use it as training data without permission.

For a real Chester 9th/Kerlin test, crop footprints to a few adjacent blocks around the intersection. This pilot **does not yet contain real Chester geometry**, because none has been downloaded or verified in this branch.

## Coordinate anchor — mandatory
The converter needs one *matching* geographic coordinate and Roblox world X/Z:
- `--anchor-lat` and `--anchor-lon`: latitude and longitude of a specific verified point, e.g. the exact center of the selected intersection.
- `--anchor-x` and `--anchor-z`: world X and Z **for that same point**, measured in the current Roblox Studio build using a position inspector.

Do **not** substitute the center of another intersection, source-grid coordinates, or an old spawn log. The current world placement may have changed since those logs. The converter uses EPSG:32618 to measure local east/north distances and then maps them to the repo's +X/-Z convention at 3 studs/m.

## Obtain real building data locally (new tool)
Once you have a **verified** geographic bounding box around the actual 9th & Kerlin intersection, run:

```powershell
py tools\reconstruction\fetch_osm_buildings.py `
  --south YOUR_SOUTH_LAT --west YOUR_WEST_LON `
  --north YOUR_NORTH_LAT --east YOUR_EAST_LON `
  --out "E:\ChesterWorld\Data\chester_9th_kerlin_buildings.geojson"
```

The download uses OpenStreetMap's Overpass API and saves a compact WGS84 GeoJSON FeatureCollection compatible with the converter below. It fetches tagged **building ways only**, not multipolygon relations; compare coverage against imagery before assuming completeness. Attribution: © OpenStreetMap contributors (ODbL). The publicly hosted endpoint may be overloaded; retry if needed. **This project has not yet fetched or validated real building data**.

## Generate preview
From repo root in Windows PowerShell:

```powershell
py -m pip install pyproj
py tools\reconstruction\geojson_to_luau.py `
  --geojson "E:\ChesterWorld\Data\chester_9th_kerlin_buildings.geojson" `
  --anchor-lat YOUR_VERIFIED_LATITUDE `
  --anchor-lon YOUR_VERIFIED_LONGITUDE `
  --anchor-x YOUR_MATCHING_STUDIO_X `
  --anchor-z YOUR_MATCHING_STUDIO_Z
```

The script writes `src/shared/ReconstructionPilot.lua`. `YOUR_...` placeholders must be replaced with actual verified numbers. It handles Polygon and MultiPolygon outer rings, explicit building heights and level estimates; unknown heights default to 9 m and are counted. No interiors or facade accuracy are claimed. It does not align roof slopes or convert imagery into textures yet.

## Preview in Studio
1. Run `rojo serve`, connect Roblox Studio and verify the correct place.
2. Set a **Workspace boolean attribute** named `CW_ReconstructionPilot` to true **before pressing Play**.
3. Press Play. New ghost-like wall outlines are under Workspace > `CW_ReconstructionPreview`, capped at 50 buildings, with collisions off.
4. Compare outlines with existing roads and terrain. If misaligned, stop and verify the anchor and GeoJSON CRS; do not manually move individual buildings.
5. Set attribute false to return to the existing world unchanged. The preview is not a city replacement.

## Acceptance criteria for pilot
- Footprint corners align to a surveyed 9th/Kerlin location and adjacent intersections.
- Correct east/west and north/south directions; no mirror or 180-degree rotation.
- Building elevations meet terrain without floating foundations.
- Existing roads, phone, vehicles, spawn and streaming remain intact.
- Only then: derive heights from licensed LiDAR, reconstruct roofs, assign style-aware facade meshes, add validated entrances and procedural interiors.
- Run an Xbox test before any citywide rollout.

## Current limitations
- This phase cannot truthfully claim a photorealistic 1:1 Chester, furnished interiors, correct roofs or visual parity with Worldcraft.
- Source elevations and imagery are **not yet downloaded**, checked, or validated.
- A single anchor across a large city can accumulate projection/survey errors; verify pilot block before scaling.
- Building tags and height values in the source may be incomplete or wrong.

Never enable this script automatically in production until pilot review is complete.

## Offline converter smoke tests
Run `py -m unittest discover -s tools/reconstruction -p 'test_*.py'` from the repository root after installing `pyproj`. The tests check GeoJSON polygon handling, local east/north orientation and Luau module formatting. Passing unit tests alone does not validate alignment in Roblox Studio.

## Audit the buildings we already generated — before replacement

The existing `src/shared/WorldData/Tiles/tile_*.lua` modules already include building rectangles with IDs, source X/Z, width, depth, rotation, and height. `src/server/World/RealBuildings.lua` already renders facades and enterable shop structures. Preserve those systems and compare new footprints against them.

Get the **current** spawn coordinates from the latest Studio output line `[ChesterWorld] Spawn ready: ... at X, Y, Z`. Then run:

```powershell
py tools\reconstruction\audit_existing_buildings.py --x YOUR_CURRENT_SPAWN_X --z YOUR_CURRENT_SPAWN_Z --radius 450 --out reconstruction_building_audit.csv
```

The CSV provides a nearest-first inventory of the **existing** geometry so that new building candidates can be compared at consistent world coordinates. It is an offline audit only; it does not use Google imagery and does not certify visual accuracy.

The opt-in preview now waits for `CW_BootstrapComplete` and displays only footprints within 450 studs of the current `ChesterCitySpawn`. It gives up after 300 seconds rather than obstructing the game if loading is broken.

