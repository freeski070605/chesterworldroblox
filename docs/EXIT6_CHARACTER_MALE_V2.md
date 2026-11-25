# Exit 6 male V2: face and quality corrections

**Status: V2 pass for visual review. Not approved, not committed, not imported into Roblox.**

V2 continues from the v1 build and does not restart it. It keeps:

- the v1 R15 rig and joint positions;
- the measured spec (`exit6_male_spec.py`);
- the v1 brow and scalp-cap generators, and the briefs cutter;
- the render setup and the comparison tooling.

What changed is the skin surface. The v1 lofted, voxel-fused body gave way to an anatomical base mesh fitted onto the same measurements.

## Files

| What | Path |
|---|---|
| Editable source | `assets/characters/exit6_male/Exit6_Male_V2.blend` (24 MB; the v1 `Exit6_Male_Base.blend` is untouched) |
| Game asset | `assets/characters/exit6_male/Exit6_Male_V2.glb` (8.0 MB) |
| Baked textures | `assets/characters/exit6_male/textures_v2/` (body colour + normal 2048; hair colour + normal 1024; face details 512; briefs 1024) |
| Full-body comparisons | `renders_v2/compare_front.png`, `compare_three_quarter.png`, `compare_side.png`, `compare_back.png` |
| Face close-ups (reference / v1 / v2, same camera and scale) | `renders_v2/compare_face.png`, plus bare head without hair: `compare_face_bare.png` |
| Hair close-ups (render twists vs game twists, real geometry) | `renders_v2/compare_hair.png` |
| Pose tests | `renders_v2/pose_tests_v2.png` (walk, arms up, crouch, twist; 3/4 and front) |
| GLB re-import | `renders_v2/glb_import_sheet_v2.png` |
| Numbers | `build_stats_v2.json`, `export_report_v2.json`, `validate_report_v2.json`, `renders_v2/compare_metrics.json` |

Scripts, all in `tools/characters/`:

```
blender -b --factory-startup -P tools/characters/build_exit6_male_v2.py -- [--stage=face] [--samples=96]   # ~6 min full, ~30 s face stage
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V2.blend -P tools/characters/export_exit6_male_v2.py
blender -b --factory-startup -P tools/characters/validate_glb.py -- Exit6_Male_V2.glb renders_v2 validate_report_v2.json
python tools/characters/compose_compare.py render_v2 renders_v2
python tools/characters/compose_face_v2.py face_v2 assets/characters/exit6_male/renders_v2/compare_face.png
```

Every tuning knob lives in `exit6_male_v2_spec.py`: MPFB sliders, face targets, landmark targets, fit masks and fades. The hairstyle lives in `exit6_hair_v2.py`.

## Priority 1: face

**Approach.** The head is no longer built from primitives. It starts from the MPFB / MakeHuman hm08 base mesh, which is CC0 and installed as a Blender extension. That mesh has quad topology, real eyelids and sockets, nostrils, lips, ears and a hairline. It is then fitted in three steps:

1. **MPFB sliders and face targets.** Young male, African, high muscle. Then targets for a short nose with a broad tip and wide alae, full and wide lips, larger eyes, a square jaw and a broad chin.
2. **Landmark thin-plate warp.** 25 facial landmarks per side, about 40 points in total, were measured off 8× gridded zooms of the reference (front and side views). They cover:
   - eye centres, corners and lids;
   - glabella, sellion, nose tip, subnasale and alae;
   - lip tops and fronts, mouth corners;
   - pogonion, menton, chin corners and jaw angle;
   - zygion, ears, forehead, skull top and occiput.

   The head warps onto them with a smoothed thin-plate spline, the same idea as pin-based tools like FaceBuilder. Measured fit after the warp: mean landmark error 0.4 px, maximum 3.4 px (reference pixels).
3. **Cheek relax.** A light pass away from the eyes, nose and lips removes lumps left by the targets.

**Detail work.**

- **Eyes:** MPFB eyeballs with a transmissive cornea and a near-black-brown iris. The lash line is painted along the lid margins.
- **Brows:** v1 brow generator, re-projected onto the new head.
- **Goatee:** new generator. A soul patch widening into a broad chin patch, measured outline, about 1 px thick.

**KeenTools.** Not used for the fit. It needs a licence and pinned photos, and the reference is a single stylized turnaround. The landmark warp does the same job directly from the reference measurements.

**Read of the result** (`compare_face.png`, `compare_face_bare.png`):

- **Fixed:**
  - no muzzle;
  - the nose bridge is short and the tip and nostrils are real;
  - the lips are natural and in the right place;
  - eyelids and sockets wrap the eyes;
  - cheeks are soft and the jaw is square.

  It reads as a believable face in the reference's proportions.
- **Still different from the reference:**
  - The reference eyes are larger and brighter, with more white showing. Ours sit deeper in brow shadow.
  - The reference lips are slightly fuller, with a crisper upper-lip line.
  - The jawline-to-neck separation is weaker than in the reference.
  - Skin is a touch more orange under these lights.

  These are tuning items in `exit6_male_v2_spec.py`, not structural problems.

## Priority 2: hair

`exit6_hair_v2.py` builds a dedicated twist style. It is not decimated from the render version.

- **Roots:** Poisson-spaced box parts on the scalp, 14 px apart, with a straight centre part and the v1 hairline. 78 twists in total.
- **Growth:** each twist grows with gravity and head collision. Fringe tips stop at the brows, temples at the cheeks, sides at the jaw (ears show) and the back at the nape.
- **Render twists:** two interleaved helical strands per twist, giving real two-strand and bead geometry. 384 k tris.
- **Game twists (`Hair_Geo`):** one tube per twist with a 5-sided section. There is a ring at every bead peak and waist (radius alternates 1.0 / 0.8) and the section rotates 36° per ring. Every bead keeps a full round cross-section, which removes the v1 flat ribbons.
  - 13.4 k tris for the twists, 15.0 k with the scalp cap.
  - Colour and a tangent normal map are baked from the render twists, so the strand spiral carries over in-game.
- **Separation:** the hair is its own mesh, weighted 100 % to Head, with `Hair_Att` / `Hat_Att` on the head.

`compare_hair.png` shows both versions' actual geometry, front, back 3/4 and close-up. The game twists render without their normal map in that sheet; it applies in-engine.

## Priority 3: body and rig

**Shoulders, chest, arms.** Body volume comes from a low-frequency fit onto the v1 silhouette body, which had IoU 0.91 against the reference. Muscle relief (pecs, abs, obliques, glutes, quads) comes from the v1 sculpt. It is projected after subdivision for renders, and baked into the body normal map for the game asset. The shoulder caps and armpits are excluded from both and get a Taubin relax. The v1 "shoulder pad" look is gone: the deltoid is round and slopes from the trapezius (see `pose_tests_v2.png`). Arm muscle definition is still softer than in the reference.

**Hands and feet.** MPFB anatomy: real palms, knuckles, nails, separated fingers and toes.

- Hands are scaled to the v1 hand length, posed with the palm turned 28° back and a relaxed finger curl.
- Feet are scaled to the measured foot length and sit flat on the floor, ready for sneakers.

**Rig.**

- **Joints and hierarchy:** the same v1 R15 joint positions and hierarchy (built from the same spec). The skeletal fit moves MPFB's joints onto those joints with linear-blend skinning.
- **Weights:** I tried transferring v1 weights by nearest surface first. It dragged the lats out with the arm in the arms-up test, because v1's arm shells sat close to the torso. V2 therefore uses MPFB's painted weights mapped bone-to-R15-part. That is valid because the fit put MPFB's joints on the v1 joints. Result: 0 unweighted vertices, ≤ 4 influences, nothing on Root.
- **Floating crouch:** fixed. The crouch frame drops `HumanoidRootNode` 0.684 studs and the soles land at z = 0 (residual 0.0000).
- **Part seams:** each R15 part gets its normals copied from the unsplit body, so the split boundaries shade continuously. One body texture covers all parts on MPFB's UV layout.
- **Briefs:** re-cut from the new body, with straight waistband and hem lines. The fabric stays outside both the skin and a crease-bridging smoothed skin, and the skin underneath is tucked in so it never pokes through.

**Silhouette IoU against the reference.** V1 vs V2 (from `compare_metrics.json`):

| View | V1 | V2 |
|---|---|---|
| Front | 0.910 | 0.900 |
| 3/4 | 0.832 | 0.833 |
| Side | 0.923 | 0.929 |
| Back | 0.905 | 0.902 |

Front and back drop by 0.01. The cause is deliberate: the v1 shoulder pads matched the outline better than the rounded deltoids do, and the reference arms are thicker than ours.

## Priority 4: Roblox readiness

### In-experience vs Marketplace

**In-experience (what this asset targets).**

- Roblox's MeshPart import limit is **20,000 triangles per mesh**. The largest V2 mesh is `Head_Geo` at 8,444 tris (face topology kept whole) and `Hair_Geo` is 14,984.
- The 15 body parts total 26,756 tris, and the whole asset is 47,144 tris.
- The body topology is MPFB's, undecimated, so the face loops survive.

**Marketplace body (not targeted).** Six assets with a 10,742-tri total: DynamicHead 4,000, torso 1,750, each arm and leg 1,248.

- V2 is over every one of those budgets: head 8,444; torso 3,260; each arm about 4,260; each leg about 3,270.
- Most of that is hands (3.2 k each) and feet (2.1 k each).
- A Marketplace version would need its own retopologised LOD; it shouldn't be produced by decimating this one. It would also need a skin-tone-transparent texture, Plastic material, and Roblox's template cages.

### Done in `Exit6_Male_V2.glb`

- **Meshes:** the 15 `<Part>_Geo` meshes plus `Hair_Geo`, `FaceDetails_Geo` (eyeballs without cornea, brows, goatee) and `Briefs_Geo`.
- **Rig:** `Root > HumanoidRootNode > LowerTorso > …`, with Root and LowerTorso at the origin.
- **Orientation:** the face points glTF +Z, matching the importer turn the existing wear pipeline expects.
- **Skinning:** ≤ 4 influences, no Root weights, 0 unweighted vertices. Height is 5.66 studs including hair.
- **Attachments:** the 19 accessory attachments named per the current character-body spec, as small `_Att` meshes parented to their part:

  | Part | Attachments |
  |---|---|
  | Head | `FaceCenter_Att`, `FaceFront_Att`, `Hat_Att`, `Hair_Att` |
  | UpperTorso | `Neck_Att`, `LeftCollar_Att`, `RightCollar_Att`, `BodyFront_Att`, `BodyBack_Att` |
  | LowerTorso | `Root_Att` (0, 0, 0), `WaistFront_Att`, `WaistCenter_Att`, `WaistBack_Att` |
  | Upper arms | `LeftShoulder_Att`, `RightShoulder_Att` |
  | Hands | `LeftGrip_Att`, `RightGrip_Att` (rotated 90, 0, 0) |
  | Feet | `LeftFoot_Att`, `RightFoot_Att` |

- **Validation:** `validate_report_v2.json` covers the clean-session re-import: bone tree, influence count, bounding box, face direction, and all 19 attachments present.

### Remaining before Roblox import

1. **Outer cages for layered clothing.** `<Part>_OuterCage` meshes are needed for each of the 15 parts. They should be built from Roblox's body cage template (Avatar Setup or the template project), keeping its vertices and UVs, and fitted over this body. That is the next task, and it pairs with the wearables.
2. **Watertight parts.** The spec wants capped limbs and watertight parts. The V2 parts are open at the split boundaries; capping is still to do.
3. **Attachment import behaviour.** The Roblox Importer only converts `_Att` meshes when importing bodies with caging data. The attachments therefore need re-checking in Studio once cages exist.

   Blender's own glTF re-import turns each parent part with children into an Empty plus a mesh. Roblox's importer may treat that hierarchy differently, so it should be verified in Studio. The alternative is to parent attachments to the rig bones.
4. **SurfaceAppearance.** Colour and normal maps are baked and ready. The SurfaceAppearance setup in Studio is not done.
5. **Studio import test.** Held until visual approval, as requested.

## Known gaps

- **Face (see Priority 1):** eye size and brightness, upper-lip crispness, and jaw-to-neck definition are the visible remaining differences.
- **Arms:** less muscle definition than the reference. Arm relief is excluded from the v1 projection, because projecting across the arm–torso gap created fins.
- **Briefs:** no stitching or waistband detail yet; the v1 vertex-colour seams are too coarse on this mesh.
- **Hair:** strand separation and length match; the reference's crown is slightly fuller.
