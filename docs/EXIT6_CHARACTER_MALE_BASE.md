# Exit 6 male base character — first pass report

Status: **first procedural pass, not approved.** The Roblox place was not touched.

## Files

| What | Path |
|---|---|
| Editable source | `assets/characters/exit6_male/Exit6_Male_Base.blend` (76 MB, not committed) |
| Game asset | `assets/characters/exit6_male/Exit6_Male_Base.glb` (5.0 MB); `Exit6_Male_Base.fbx` also written, not import-tested |
| Baked textures | `assets/characters/exit6_male/textures/` (body 2048² colour + tangent normal; hair, briefs, face pieces colour) |
| Comparison sheets | `renders/compare_front.png`, `compare_three_quarter.png`, `compare_side.png`, `compare_back.png` (reference / render / silhouette overlay) |
| Pose test | `renders/pose_tests.png` (rest, walk, arms up, crouch, twist) |
| GLB re-import renders | `renders/glb_import_sheet.png` |
| Numbers | `build_stats.json`, `export_report.json`, `validate_report.json`, `renders/compare_metrics.json` |
| References used | `assets/characters/reference/` (the four approved turnarounds) |

Scripts, all in `tools/characters/`:

```
blender -b --factory-startup -P tools/characters/build_exit6_male.py      # source .blend + 4 views + poses (~5 min)
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_Base.blend -P tools/characters/export_exit6_male.py
blender -b --factory-startup -P tools/characters/validate_glb.py
python tools/characters/compose_compare.py
```

`exit6_male_spec.py` holds every measurement, all read off `male_body_turnaround.png`. `debug_view.py` and `closeup_compare.py` are the close-up review aids.

## How it is built

1. **Measured, not guessed.** The builder works in reference-pixel space: front panel centre x=166, side panel depth origin x=700, soles on row 1140, skull top on row 216. It scales to studs at the end, at 5.6 studs from sole to skull top. The render camera uses that same scale, so front and side renders overlay the reference pixel for pixel.
2. **Anatomical shells.** Torso, neck and head are horizontal slice lofts. Their half-widths come from the front silhouette and their front/back edges from the side silhouette. Arms and legs are lofted along spline paths with measured radii. Deltoids, palms and feet are their own shells. Muscle relief is analytic displacement:
   - pecs, abs blocks and grooves, obliques, V-line, scapulae and spine;
   - deltoid, biceps, triceps and forearm;
   - quads, vastus medialis, patella, calves and malleoli.

   The face is the same kind of displacement: nose, lens-shaped lips, brow ridge, sockets, cheekbones and chin. The eyelids are constrained to hug the eyeballs.
3. **Fusion.** The shells are voxel-remeshed at 0.85 reference px into one watertight body (1.1 M verts). It is then smoothed with a mask: the face stays crisp while the body junctions round off. Fingers, thumbs and toes stay as separate clean tubes.
4. **Detail meshes**, all separate:
   - Eyeballs with sclera, iris and pupil.
   - Brows as slabs projected onto the face.
   - Goatee as a tapered volume.
   - Scalp cap whose box parts are coloured from the root Voronoi.
   - 140 two-strand twists, each with a bead/spiral cross-section, lifted off the scalp and hung per region (fringe, crown, sides, back).
   - Boxer briefs derived from the body surface, fabric-smoothed, with waistband and seams.
5. **Skin weights are analytic.** Each shell carries weights computed from its own anatomy, with smooth blends at the joints. They are carried onto the remeshed body by barycentric nearest-surface transfer.

## Actual geometry

| Object (source .blend) | Verts | Tris |
|---|---|---|
| Body (fused, incl. fingers/toes) | 1,124,318 | 2,248,552 |
| Hair twists | ~242 k | ~482 k |
| Scalp cap / briefs / goatee / brows / eyes | see `build_stats.json` | |

Game asset (GLB), 24,490 triangles total:

| Mesh | Tris | Mesh | Tris |
|---|---|---|---|
| Head_Geo | 1,715 | UpperTorso_Geo | 2,780 |
| LowerTorso_Geo | 976 | Left/Right UpperArm_Geo | 761 / 751 |
| Left/Right LowerArm_Geo | 400 / 400 | Left/Right Hand_Geo | 647 / 640 |
| Left/Right UpperLeg_Geo | 826 / 833 | Left/Right LowerLeg_Geo | 847 / 854 |
| Left/Right Foot_Geo | 790 / 780 | Hair_Geo | 7,918 |
| FaceDetails_Geo (eyes, brows, goatee) | 966 | Briefs_Geo | 1,606 |

The 15 R15 body parts total 14,000 tris. Roblox's Marketplace body budget is 10,742, with per-asset caps such as 1,750 for the torso; this asset is over both. That doesn't matter for an in-game character, but it would have to drop for a Marketplace body.

## Rigging

- **Hierarchy:** Root > HumanoidRootNode > LowerTorso > UpperTorso > Head / arms, and LowerTorso > legs. This follows Roblox's R15 character-body spec. Root and LowerTorso sit at (0, 0, 0). Every limb bone's Z axis points forward, so +X rotation bends forward on every bone.
- **Weights:** at most 3 influences per vertex (the spec allows 4). No weights on Root. No unweighted vertices in the exported meshes.
- **Orientation:** the face points -Y in Blender, which exports as glTF +Z. That matches the "+Z front, +Y up" spec and the 180° turn the Roblox importer applies, which the existing wear pipeline already accounts for.
- **Pose test:** `Exit6_PoseTest` action with walk, arms up, crouch and twist. The limbs bend at the right joints with no tearing. The shoulders hold up at 82° abduction. The crouch keeps the root fixed, so the body floats in that test.
- **GLB validation:** parsed raw, then re-imported in a clean Blender session. The validator found:
  - 18 meshes, each with skin joints, weights and UVs;
  - 1 skin with 17 joints and 9 embedded images;
  - a height of 5.67 studs including hair.

## Visual review against the reference

The silhouette IoU numbers are measured; the rest is my own read of the comparison sheets.

| View | Silhouette IoU | Mean row-width error |
|---|---|---|
| Front | 0.910 | 12.7 px |
| 3/4 | 0.832 | 14.8 px (reference has perspective, render is ortho) |
| Side | 0.923 | 5.6 px |
| Back | 0.905 | 13.0 px |

**Close to the reference:**
- Overall proportions and height: head-to-body ratio, leg length, calf and thigh shapes, glute and chest profile in side view.
- Skin tone, black briefs placement.
- Beaded twist hairstyle with a centre part, and the bold angled brows.
- The six-pack layout.

**Not there yet. It does not pass as the reference character:**
- **Face.** This is the biggest gap. The reference has an appealing stylized face: soft cheeks, defined but gentle lips, big dark almond eyes, a short broad nose. Ours is harder and more mask-like. The mouth reads as a muzzle, the eyes are small, and the nose bridge is too long. The lofted-head approach has hit its limit here. The likely path is a hand- or photo-guided head sculpt (the KeenTools add-on is installed in this Blender) or a quad head base mesh shaped by these same measurements.
- **Shoulders.** Still a squarish "shoulder-pad" read where the trapezius meets the deltoid. The reference shoulders are rounder and slope more.
- **Pecs, arms, back.** Less defined than the reference: pec mass, the biceps/deltoid split, and back musculature.
- **Hands.** Recognisable but thin and stiff. The thumb hangs like a rod, and there are no knuckle or nail details.
- **Feet.** Blocky, with toes only faintly separated.
- **Game-asset hair.** Decimating 482 k tris down to 8 k flattens the beaded twists into ribbons (see `glb_import_sheet.png`). It needs a purpose-built low-poly twist LOD, plus probably a normal map, rather than decimation.
- **Ears.** Mostly hidden by twists, which matches the reference, but they are simple shapes.

## Remaining work

1. Face rebuild (see above), then re-run the comparison sheets.
2. A low-poly twist LOD generator with a baked normal or AO map for `Hair_Geo`.
3. Shoulder, pec and arm definition pass. Hands and feet pass: knuckles, nails, toe separation.
4. Roblox-specific items not done yet:
   - 19 `_Att` attachment meshes;
   - `_OuterCage` meshes for layered clothing;
   - capped part boundaries (the spec wants each part watertight when separated; ours are open at the seams);
   - SurfaceAppearance setup;
   - an actual Studio import test of the GLB. This is held back until the model is approved, as requested.
5. Wearables, which come after the base is approved:
   - puffer, cargo/jeans, high-top sneakers, chain with the EXIT 6 pendant, watch;
   - built against the same body, with cages.
6. The female base from `female_body_turnaround.png`. The spec-table approach carries over directly.
