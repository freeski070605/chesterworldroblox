# EXIT 6 production asset audit

Status: **incomplete; no new asset is production approved**. Audit performed against source on the feature branch on November 8, 2026. Roblox Studio DataModel access was unavailable in this session. The repository has a Studio MCP configuration, but no callable Studio tool was exposed here. The live `ServerStorage.Exit6CarMeshes` contents were **not inspected**.

## Vehicle workflow

`Exit6CarBuilder.luau` looks for `ServerStorage.Exit6CarMeshes.<body>` for six bodies. If a template exists, it clones and welds every `BasePart` to an invisible chassis, adds a collision hull and seats, and uses template attributes for physics dimensions. If absent, it builds a vehicle from ordinary `Part` boxes and cylinders. Visual template parts are noncolliding, massless, and created only for a car currently in use or a dealership display. `Exit6Vehicles.server.luau` limits player calls to one spawned car per player.

`tools/harness/car_mesh_templates.luau` **normalizes already generated** `Workspace.GenCar_<body>` models. It identifies a body and four wheels by part names, scales to the catalog wheelbase, sets attributes, anchors the source parts, and moves the model to `ServerStorage.Exit6CarMeshes`. It does not create vertices, triangles, UVs, textures, or the original vehicle geometry. Source comments describe this as Studio mesh generation; the actual generation tool and its output are not in source control. The templates are saved only in the place file, because `default.project.json` does not map `ServerStorage`.

| Question | Evidence and limit |
| --- | --- |
| MeshPart, Part, UnionOperation, EditableMesh? | The fallback consists of `Part` instances. The template script accepts any `BasePart`, so source alone cannot establish the classes in Studio. |
| Original generation? | Upstream `GenCar_*` models are assumed, but their generator is absent. The normalizer only scales and stores them. |
| Triangle meshes or grouped primitives? | Unknown until Studio inspection. A `MeshPart` would carry a mesh asset; a `Part`/`UnionOperation` inventory distinguishes other cases. |
| Saved, textured, reused? | The place file stores templates under `ServerStorage`. The builder clones them. Mesh IDs, TextureIDs and `SurfaceAppearance` are unknown. |
| Suitable for hair/clothing? | The storage and clone pattern can serve rigid hair accessories. Normalization of five named car parts does not create hair. Layered clothing requires rigging and inner/outer cages, which this workflow does not provide. |
| Automatable in Studio? | Inventory, import organization, metadata, fit checks, and cloning can be scripted. Mesh creation with `EditableMesh` is possible in Studio when APIs/permissions permit, but generation, import, and visual approval require separate work. |

Run [the read-only inventory script](../tools/studio/inspect_exit6_car_meshes.luau) in the **Edit** DataModel and save its printed `EXIT6_CAR_AUDIT_JSON`. It reports model attributes, geometry classes, mesh and texture IDs, materials, size, and surface maps. It does not mutate the place. Triangle counts for uploaded meshes may need the original mesh file or an authorized `EditableMesh` load; the script makes no triangle-count claim.

## Hair work delivered

[The generator](../tools/assets/build_hair.py) writes 12 original OBJ meshes to `assets/hair`, with a [manifest](../assets/hair/manifest.json) of identifiers, category, version, geometry counts, material, pivot convention, and `candidate_unverified` status. Surfaces include a curved scalp cap; locs, twists, braids, cornrows and waves have individual tubular geometry. This is actual triangular geometry, not renamed Roblox Parts. The OBJ files use head-local studs with the face toward negative Z.

The [offline contact sheet](../assets/hair/offline_contact_sheet.png) shows front, side, and rear orthographic views against a simple head ellipsoid. This is **not a Roblox Studio screenshot or an R15 fit test**. Visual review found the low and mid fades too similar, short locs insufficiently distinct, and several long styles too sparse or jagged. The ponytail placement needs correction. Hairline, scalp intersection, import pivot, and game lighting remain unverified. None is finished.

| Asset group | Triangle range | Current status |
| --- | ---: | --- |
| Fades, afro taper | 870–2,410 | Candidate; silhouettes and edge detail need work |
| Waves | 2,790 | Candidate; ridge visibility needs Studio review |
| Locs and twists | 2,998–4,070 | Candidate; strand placement and motion clearance need work |
| Cornrows, box braids, ponytail | 5,910–7,638 | Candidate; complexity and shape need optimization |

Total source geometry is 43,178 triangles **across all 12 files**. This is a library total, not per-avatar cost; candidates remain outside Workspace until equipped. No draw-call, memory, streaming, or Xbox measurements were made.

## Garments and customization

The current `Exit6Style.luau` builds hair and hats from welded primitives and recolors R15 body parts for tops and bottoms. It hides existing classic and layered clothing rather than deleting it, so old profiles can restore the player's own appearance. `Exit6Profile.luau` saves catalog item IDs in `style` and imports known IDs. `Exit6Shop.server.luau` checks the actual store menu, reach, and cash on purchase. `Exit6Phone.client.luau` already supports gamepad selection and purchase via the shop menu, but has no live avatar preview, view rotation, outfit composition, or separate confirmation.

Legacy item IDs remain in `Catalog.Items` to preserve saved appearance restoration. The barber and clothing menus now offer only the bald/own-hair and own-fit actions; unfinished part-based styles are withheld from new sales. No new hair assets are advertised or sold. Finished layered garments, cages, skinned R15 fitting, clothing library entries, preview UI, and outfit purchase flow are **not delivered**. Body recoloring is not treated as layered clothing.

Roblox's [layered clothing specifications](https://create.roblox.com/docs/art/accessories/clothing-specifications) require inner/outer cages, and the [import workflow](https://create.roblox.com/docs/art/accessories/import-clothing) validates clothing assets. Producing credible hoodies, jeans, jackets, hats, and shoes with correct deformation needs a modeled and caged R15 clothing set and Studio import/animation review; no such source assets or rigging tools were available locally. It would be misleading to ship rigid meshes as finished layered garments.

## Studio import and QA handoff

1. Save a copy of the existing place before importing. Run the read-only vehicle inspection script and archive its JSON output with this audit.
2. Run `python tools/assets/build_hair.py` and `python tools/assets/validate_hair.py`. Import each `assets/hair/*.obj` with Studio's 3D Importer, retaining its source name and scale. Confirm the import origin, head-local axes, and face direction. Do not upload as a marketplace asset.
3. Place the 12 imported `MeshPart`s under one selected Folder/Model and run [the candidate installer](../tools/studio/install_exit6_hair_candidates.luau) in the Edit DataModel. It clones them into `ServerStorage.Exit6ProductionAssets.Hair` as `Accessory` instances with version/status attributes. It will reject missing or duplicate names. Save the place or export a `.rbxm` for source control; Rojo will not save `ServerStorage` objects in this project.
4. Fit each accessory on representative R15 heads and body scales. Capture front, side and rear Studio screenshots, then run walking, running, sitting and driving animations. Record clipping and attachment offsets. Only after review, explicitly change asset status, connect it to the catalog and profile, and expose it for sale.
5. For garments, use an R15 clothing template, rig and inner/outer cages, validate with Studio's 3D Importer, test deformation, and capture the same views/animations. Keep any failed item out of the menu.

`Workspace.StreamingEnabled` stays true in `default.project.json`. The new OBJ library is offline and the installer targets `ServerStorage`; no 12-style Workspace preload or per-frame generation was added.

## Verification matrix

| Check | Result |
| --- | --- |
| OBJ syntax, finite coordinates, counts, broad size bounds | See validator output; local check only |
| Offline front/side/rear visual sheet | Reviewed; multiple quality defects remain |
| Rojo project build | Passed locally |
| Studio DataModel vehicle inventory | **NOT TESTED**: Studio connection unavailable |
| R15 import, attachment, animations, screenshots | **NOT TESTED** |
| Layered clothing import and deformation | **NOT TESTED** |
| City runtime, purchase/persistence, streaming metrics | **NOT TESTED** |
| Xbox performance and controller QA | **NOT TESTED** |

References: Roblox Creator Hub [EditableMesh](https://create.roblox.com/docs/reference/engine/classes/EditableMesh), [AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService/CreateEditableMesh), and [layered accessories](https://create.roblox.com/docs/avatar/layered-accessories).
