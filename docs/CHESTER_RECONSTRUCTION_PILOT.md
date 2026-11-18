# Chester 9th & Kerlin footprint pilot

## Phase 2 architecture preview (issue #6)

The preview now assembles noncolliding polygon wall shells, HouseKit cornice parts, and triangulated flat roof slabs over the 47 OSM outlines. It runs only in Studio with `CW_ReconstructionPilot = true` set on Workspace before Play. The attribute is absent by default. It does not touch the live `ChesterBuildingId` models, doors, shops, roads, or rental behavior. The shell is translucent so existing gameplay remains visible during comparison. The roof is a **procedural flat preview**, not a surveyed roof shape; the generic brick finish and cornice are stylistic approximations. OSM tags identify one `retail` and one `school` building; the other 45 are only `building=yes`, so HouseKit residential archetypes, windows, porches, and doors are deliberately not assigned by guessed type.

`tools/reconstruction/build_associations.py` rebuilds `chester_9th_kerlin_associations.json` and `src/shared/ReconstructionAssociations.lua` from the 232 checked-in legacy rectangles and 47 source polygons. It requires polygon intersection over union ≥0.55, source area coverage ≥0.80, at least 0.10 IoU margin over the runner-up, and unique gameplay ID ownership. Current output: **36 associated, 10 review, 1 unmatched**. This is an automated geometry association, not visual identity confirmation. `osm_way_836649737_0` has no overlapping rectangle and remains explicitly unresolved; review it in Studio against the nearby live model, road, and terrain before assigning an ID. The JSON retains rejected candidate IDs and scores. Rebuild or delete the Luau map to reverse all associations; no live model data is rewritten.

All 47 heights remain **estimated 9 m (27 studs)**, with `heightSource=estimated_default` and low confidence. All 47 roofs have `roofSource=procedural_estimate`, `roofType=flat_preview`, and low confidence. Each building carries an OSM way reference; the collection retains © OpenStreetMap contributors / ODbL attribution. The [Delaware County footprint layer](https://gis.delcopa.gov/arcgis/rest/services/DataLayers_911/Delaware_County_Building_Footprints/MapServer/0) lists `BuildingHeightM`, but its public metadata does not establish measurement method or a reuse grant for these derived heights. The [USGS 3DEP download page](https://www.usgs.gov/the-national-map-data-delivery/gis-data-download) and [LidarExplorer](https://www.usgs.gov/tools/lidarexplorer) provide a path to investigate point clouds; no per-building point cloud extraction has been completed. A [bare-earth DEM strips structures and vegetation](https://www.usgs.gov/faqs/what-lidar-data-and-where-can-i-download-it), so it cannot alone measure roof height. No aerial image was copied or used for roof attribution.

Reproduce from repo root:

```powershell
py tools/reconstruction/geojson_to_luau.py --geojson tools/reconstruction/data/chester_9th_kerlin_osm.geojson --out src/shared/ReconstructionPilot.lua
py tools/reconstruction/build_associations.py
py -m unittest discover -s tools/reconstruction -p 'test_*.py'
rojo build default.project.json -o "$env:TEMP\chester_reconstruction_issue6.rbxmx"
```

On this branch: `associated=36 review=10 unmatched=1`; `Ran 10 tests ... OK`; Rojo reported `Built project to chester_reconstruction_issue6.rbxmx`. The preview estimates up to 297 wall edges, 297 cornice strips, and roughly 406 roof wedges before the 450-stud pilot radius filter. It logs actual `parts_before`, `parts_after`, `delta`, roof wedge count, and elapsed seconds after bootstrap. Xbox never instantiates the preview because it is Studio-gated. Studio/Xbox visual checks remain required: Play with flag absent and confirm normal spawn, 9th/Kerlin roads, houses, shops and doors; Play with flag true and inspect all shell edges, roof seams, and the unmatched footprint; record F9 errors, parts delta, frame rate and loading time; repeat default-off on Xbox, including driving, shops, and controller movement. Capture real Studio screenshots if adding images to PR #4. Keep the PR draft until these checks pass.

This branch includes a real, opt-in OpenStreetMap footprint preview. It does not replace the 102 tiles, roads, stores, rentals, or gameplay IDs. The Workspace `CW_ReconstructionPilot` attribute defaults to off.

## Geographic correspondence

The existing street index was built from WGS84 roads projected to EPSG:3857 using the source manifest origin `(-8397592, 4837229)` meters. `WorldPlacement.lua` uses center `(6347.889, 7201.973)` local meters and 3 studs per source meter, with world +X east and -Z north. `StreetData.spawn` is `(2810.205, -1518.823)` in street-index X/Z; `Bootstrap.server.lua` negates the street Z for the actual spawn, `(2810.205, 1518.823)`. This source-grid point transforms to WGS84 **39.848318096, -75.371413543**, the county road intersection used for 9th & Kerlin in Chester city, Delaware County, PA. It is a source road junction, not a field-surveyed curb or road center.

For any WGS84 footprint vertex, the converter uses the same EPSG:3857 projection as the source roads:

```text
world_x = (mercator_e - origin_e - center_x) * 3
world_z = -(mercator_n - origin_n - center_z) * 3
```

This matches the repo's source grid and avoids a separate guessed Studio anchor. The local projection has Web Mercator scale distortion; this deliberately matches the existing generated world geometry. Studio must still verify the road and footprint outlines visually.

## Actual import and audit

The checked-in `tools/reconstruction/data/chester_9th_kerlin_osm.geojson` contains 47 building ways in WGS84 within `(south 39.8469, west -75.3731, north 39.8497, east -75.3697)`. Source: © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright). The collection contains source IDs and building tags, no imagery. A separate building-relation query found zero relations in this box, so the ways-only export has no known building multipolygon omission here. This is an OSM coverage check, not a proof that every real building is mapped.

`src/shared/ReconstructionPilot.lua` is the actual generated 47-footprint candidate module. All 47 heights are labeled `default` at 9 m because these OSM features contain no height or level tags. The local county layer has a `BuildingHeightM` field, but its ArcGIS metadata does not establish that these are LiDAR-measured roof elevations or grant a clear reuse license for committing derived heights. The available USGS 3DEP raster is bare-earth elevation, which cannot yield building height alone. No measured roofs or facades are claimed or previewed.

`tools/reconstruction/data/chester_9th_kerlin_existing.csv` audits 232 existing tile building rectangles within 1,000 studs of spawn. `chester_9th_kerlin_alignment.csv` compares each candidate polygon with the existing oriented rectangles using shared area, intersection over union, footprint gap, and centroid error. It reports **46 overlap candidates and 1 unmatched**; the median centroid error among overlap candidates is **4.93 studs**. An overlap is a review candidate, not a verified building identity. The unmatched candidate `osm_way_836649737_0` is 25.68 studs from its nearest existing rectangle. No automatic replacement occurred. Broad overlap supports the source-grid transform, while low overlap scores and the unmatched outline require Studio review.

## Reproduce

From repo root, with `pyproj` and `shapely` installed:

```powershell
py -m unittest discover -s tools/reconstruction -p 'test_*.py'
py tools/reconstruction/geojson_to_luau.py --geojson tools/reconstruction/data/chester_9th_kerlin_osm.geojson --out src/shared/ReconstructionPilot.lua
py tools/reconstruction/audit_existing_buildings.py --x 2810.205 --z 1518.823 --radius 1000 --out tools/reconstruction/data/chester_9th_kerlin_existing.csv
py tools/reconstruction/compare_building_alignment.py --existing tools/reconstruction/data/chester_9th_kerlin_existing.csv --candidate src/shared/ReconstructionPilot.lua --out tools/reconstruction/data/chester_9th_kerlin_alignment.csv
```

To refresh OSM data, run `fetch_osm_buildings.py` with the box above, review relation IDs in the GeoJSON metadata, then regenerate the module and report. Overpass availability varies. The generated module must be reviewed before committing refreshed data.

## Studio and Xbox verification

Studio and Xbox were unavailable in this coding environment, so no runtime, frame-rate, loading, or controller result is asserted. To reproduce in Studio: sync this branch with Rojo; confirm `CW_ReconstructionPilot` is absent or false and Play once to verify normal spawn and roads. Then set it true before Play. Wait for `[ChesterWorld] Spawn ready` and `CW_BootstrapComplete`; expect a `[CW Reconstruction] Previewed ...` log and non-colliding walls in `Workspace.CW_ReconstructionPreview` near 9th & Kerlin. The renderer caps at 50 buildings and skips preview after 300 seconds if bootstrap has not completed. Inspect wall edges against road junctions and terrain, especially `osm_way_836649737_0`, and record F9 errors, loading time, and frame rate. Disable the attribute and repeat the road/spawn check. On Xbox, check spawn, driving and shops, preview off, and capture loading/frame-rate evidence. Do not merge or enable by default until these checks pass.
