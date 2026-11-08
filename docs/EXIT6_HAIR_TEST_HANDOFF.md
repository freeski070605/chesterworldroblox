# EXIT 6 Hair Test handoff

Status: source and Xbox controller UI are implemented. **The Roblox place has not been updated or published from this session. Xbox build NOT READY.** Studio and Xbox were unavailable, so no statement here certifies attachment, clipping, or console performance.

## The 12 test styles

| ID | In-game label | Triangles |
| --- | --- | ---: |
| `sharp_low_taper` | Low taper fade | 2,300 |
| `mid_skin_fade` | Mid skin fade | 1,940 |
| `high_top_fade` | High-top fade | 1,378 |
| `waves_360` | 360 waves | 2,820 |
| `starter_locs` | Short starter locs | 5,300 |
| `medium_locs` | Medium locs | 6,020 |
| `shoulder_locs` | Shoulder-length locs | 6,980 |
| `two_strand_twists` | Two-strand twists | 8,420 |
| `cornrows` | Cornrows | 7,668 |
| `box_braids` | Box braids | 10,340 |
| `afro_taper` | Afro taper | 2,760 |
| `braided_ponytail` | Braided ponytail | 3,092 |

The generator now adds a defined hairline and fade stubble, distributes loc and braid roots over the scalp, thickens long styles, and routes the ponytail behind the head. All are original triangular OBJ geometry. [The contact sheet](../assets/hair/offline_contact_sheet.png) was reviewed offline from front, side, and rear. It is a diagnostic render, not a Studio screenshot. The fade texture remains subtle and the scalp and attachment fit need Studio review. These are **test assets**, not approved merchandise.

## One batch Studio import and installation

1. On `feature/exit6-phase-f-citywide-properties`, run:

   ```powershell
   python tools/assets/build_hair.py
   python tools/assets/validate_hair.py
   python tools/assets/validate_hair_integration.py
   rojo build default.project.json -o build/exit6_hair_test.rbxlx
   ```

2. Open the existing EXIT 6 Studio place. Sync the Rojo source to that place; do **not** replace the existing place with the fresh Rojo build. Save a local backup of the place first.
3. In Studio **File → Import**, select all 12 `assets/hair/*.obj` files in one multi-file selection. The [Studio Importer](https://create.roblox.com/docs/studio/importer) queues multiple files; apply one scale preset to all. Use the experience owner as Creator, keep **Upload to Roblox** and **Add to Workspace** enabled so the published experience can load the mesh IDs. Confirm each preview has a single `MeshPart`, correct forward direction (face is negative Z), and head-sized dimensions (about 2 studs wide). Import all 12 in the queue.
4. Group the 12 imported Models/MeshParts under one temporary Folder in Workspace. Each MeshPart must have its manifest ID as its exact `Name`. Select that Folder, then run [the batch installer](../tools/studio/install_exit6_hair_candidates.luau) in Studio Edit mode. It refuses missing/duplicate/empty-mesh inputs and creates `ServerStorage.Exit6ProductionAssets.Hair.<id>` accessories with `MeshPart` handles, `HairAttachment`, version and test-status attributes. It does not overwrite existing assets.
5. Run [the read-only place verification script](../tools/studio/verify_exit6_hair_test.luau). Require `12/12 installed; 0 extra`. Save the place and export `Exit6ProductionAssets` as an `.rbxm` or commit a place copy if your asset policy permits. Rojo does not map ServerStorage in `default.project.json`.
6. Remove the temporary Workspace imports after the ServerStorage copies are verified. Test each style on representative R15 avatars with head scale variation, then walk, run, jump, sit, and drive. Capture Studio front, side, rear screenshots and record any offset, floating, clipping, or missing texture. Fix imports or geometry before publishing.
7. Publish the updated existing place as a **test build** accessible to the Xbox account. Verify asset permission/moderation and all 12 `MeshId` loads on Xbox. Publish only after Studio checks; the source commit alone cannot make the console build ready.

The installer assumes the OBJ origin remains at the head center. It creates `HairAttachment` at `(0, 0.5, 0)` in the imported handle. If the Importer recenters a mesh or applies a different unit scale, adjust it in Studio and repeat fit checks before publishing. Do not silently approve the default fit.

## In-game Hair Test controls

With the test place published and all meshes installed: on Xbox, press **View/Select** or **D-pad Up** to open the phone, select **Hair Test**, press **D-pad Down** to enter the list, and **A** on any installed style to preview it on the live character. Select **Equip preview (save)** and press **A** to save it at no charge. Select **Restore my Roblox hair** to clear the test selection. **B** closes the phone and cancels an unsaved preview. Reopening the phone shows the saved selection. The server rejects a style whose MeshPart is missing, and the UI marks it `MISSING`.

Test entries exist in `Catalog.HairTest` and use stable `test_hair_*` profile IDs. They are absent from paid barbershop merchandise menus. The existing `Exit6Profile.style.hair` field persists the chosen ID; `Style.Apply` restores it after character appearance load, removes the prior test accessory, and uses the existing own-hair restoration path. Only one test accessory is intended to be attached at a time.

## Verification

| Check | Result |
| --- | --- |
| All 12 OBJ files, syntax, counts and broad bounds | PASS locally |
| Exactly 12 catalog IDs matching the OBJ manifest and installer | PASS locally |
| Rojo build | PASS locally |
| Offline front/side/rear mesh review | Reviewed; diagnostic only |
| Studio import, installed MeshIds, R15 fit, attachment, animation | **NOT TESTED** |
| Runtime profile round-trip and existing gameplay | **NOT TESTED** |
| Xbox controller and rendering/performance | **NOT TESTED** |
| Published Xbox-accessible test build | **NOT DONE** |

Only one hair asset is equipped per player. Box braids are the largest at 10,340 source triangles; actual draw calls, GPU memory and Xbox frame time require measurement in the test place. `Workspace.StreamingEnabled` remains enabled. No hairstyle library is preloaded into Workspace by source code.
