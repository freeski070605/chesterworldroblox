# Exit 6 male V3.1: approved V3, made playable

Status: **V3 approved as the base character (2026-11-25). V3.1 = V3 + polish, R15 prep, wear. Tested in a separate Studio test place. Not in the live Exit 6 place.**

V3.1 does not rebuild the face or the body. The face shape, body shape, proportions, rig, weights and hair are V3's, byte for byte. V3.1 adds the following:

- sculpted detail, baked to maps;
- small brow and eye fixes;
- clean Blender files;
- a Roblox-ready body with caps, attachments and cages;
- the first premium wear set.

## 1. Approved base and backup

- The git tag `exit6-male-v3-approved` marks commit `f615af5`. That commit holds V3's `.blend`, `.glb`, textures and reports.
- A local copy with SHA-256 sums is in `build/backups/exit6_male_v3_approved/`. That folder is gitignored.
- `Exit6_Male_V3.blend` stays the approved source. Every V3.1 step reads it and writes new files.

## 2. Skin detail and muscle definition (no proportion change)

`exit6_anatomy_v31.py` draws the relief in reference-pixel space, the way an artist paints a displacement layer in orthographic views. It uses three primitives:

- grooves, which can taper along their length;
- domes;
- blurred blocks.

Every placement was measured on the reference turnaround: front panel x = col − 165, back panel x = 966.5 − col, side panel Y = col − 700. Running the script writes overlay images (`build/exit6_v3/polish/anatomy_overlay_*.png`) that show each feature on the reference.

| Region | Features |
|---|---|
| Chest and neck | Pec masses, lower pec border, sternal furrow, clavicles, deltopectoral groove, areola and nipple, sternal notch, sternocleidomastoid |
| Abs | Rounded rectus segments, linea alba, three tapered tendinous intersections, semilunar lines, navel |
| Flanks | Serratus fingers, oblique mass, iliac V-line |
| Back | One continuous tapered spine groove, erector spinae, trapezius, infraspinatus, teres, scapula border, lats |
| Arms | Deltoid separations, biceps, brachialis line, brachioradialis, triceps horseshoe, elbow, cephalic and forearm veins |
| Legs | Rectus femoris, vastus lateralis and medialis, sartorius, patella, tibia ridge, gastrocnemius heads, Achilles tendon, malleoli. The grooves here are softer, matching the reference. |

`export_exit6_male_v31.py` turns the maps into a bake:

1. It evaluates the V3 body at subdivision level 3, about 0.85 M vertices.
2. It displaces each vertex along its normal by the relief. It uses triplanar weights (front, back, outward side) and torso, arm and leg masks taken from the R15 weights.
3. It adds cavity darkening and areola tone to the colour.
4. It bakes a 2048 colour map and a tangent normal map onto V3's unchanged game mesh. Silhouette and proportions therefore cannot change.

The old V1 `MuscleDetail` relief is left out of the bake, because it caused V3's blocky ab grid.

The skin keeps the micro-pore bump from the skin material, which the bake carries.

Review renders of the game mesh with its baked maps are in `build/exit6_v3/polish/game/`:

| File | Content |
|---|---|
| `cmp2.png` | V3 next to V3.1: torso front and three-quarter, back, legs |
| `dressed_sheet2.png` | The full outfit |

## 3. Eyes and brows (face preserved)

`polish_exit6_male_v31.py` turns `Exit6_Male_V3.blend` into `Exit6_Male_V3_1.blend`.

- **Brows:** the V3 outline is rebuilt as a feathered shell 0.85 px off the skin. V3's was a 1.5 px slab with vertical walls. The shell has strand-streak colour, a bump, and a tail tapered by geometry.
- **Eyes:** colour only. The sclera goes from sRGB (226, 216, 206) to (212, 198, 186). There is a soft shadow under the upper lid and slightly darker, warmer corners, so the eye no longer shows a bright ring of white.

## 4. Upside-down duplicate fixed

- **Cause:** `export_exit6_male_v3.py` saved its game copy (collection `Exit6_Male_V3_Game`: split parts on a game rig moved 2.97 studs down, plus `_Att` cubes) back into the source `.blend`.
- **Fix:** the export now writes the game copy only to `Exit6_Male_V3_Game.blend` and never saves the source. The V3.1 export does the same, writing `Exit6_Male_V3_1_Game.blend`.
- **Cleanup:** `polish_exit6_male_v31.py --strip-only` removes an old game copy from any source file. It was run on the approved `Exit6_Male_V3.blend` (38 objects removed; only the `Exit6_Male_V3` and `Exit6_Studio` collections remain). `Exit6_Male_V3_1.blend` is clean. The tagged commit and the backup keep the original file.

## 5. R15 body preparation (`Exit6_Male_V3_1_Body.glb`)

- **Parts:** 15 `<Part>_Geo` meshes on the standard R15 rig (Root, HumanoidRootNode, 15 bones), with at most 4 influences per vertex and no root influence.
- **Closed boundaries:** every part is capped with fans. The caps are oriented from the adjacent face and use a skin texel for UVs. The export report shows 0 open edges and 0 non-manifold edges on all 15 parts.
- **Attachments:** 19 `<Name>_Att` markers. The importer put them on HumanoidRootPart. The test-place installer moves them to the right parts, and the exporter now parents them to their R15 bone, as Roblox's templates do. That change takes effect on the next export.
- **Cages:** 15 `<Part>_OuterCage` meshes, built from Roblox's **Body Cage Template**, so the topology and UVs are Roblox's own. The fit runs in two steps:
  1. A bone warp maps the template's A-pose onto V3.1's pose, with feet mapped box to box.
  2. 40 rounds of surface projection, each part onto its own part, keep the cage 0.015 to 0.038 studs outside the skin, with Taubin smoothing between rounds. Each part cage copies the displacement of its matching template vertex, as the template's own Geometry Nodes setup does.
- **Clothing inner cage:** the fitted 1,358-vertex cage, `Exit6V31_BodyCage` in `Exit6_Male_V3_1_Game.blend`, is the inner cage for all V3.1 clothing.

| | Triangles |
|---|---|
| Body, 15 parts with caps | 27,576 |
| Largest part (Head) | 8,494 |

In-experience limits are met. The Marketplace body budget (10,742) is still not a target.

## 6. Studio test place (not the live game)

The test place is `E:\RobloxStudio\Exit6_CharacterTest.rbxl`, built from `tools/character_test/character_test.project.json`. The live Exit 6 place was not modified. Its Studio session was used only for Open Cloud upload calls, because the unpublished test file has no Open Cloud scopes.

| Asset | Id | Revision |
|---|---|---|
| Body | 117787451658215 | |
| Parts | 140044725594011 | |
| Puffer | 81194856608492 | r3 |
| Cargo | 89644224757994 | r3 |
| Sneakers | 131700232142869 | r2 |
| Briefs | 121101325988526 | |
| Jewelry | 136482874183839 | |

The installers are run from Studio in this order:

1. `tools/character_test/install_exit6_v31.luau`
2. `tools/character_test/install_exit6_v31_wear.luau`
3. `install_exit6_v31.luau` again, to dress the StarterCharacter.

### Results

| Check | Result |
|---|---|
| Import | Full R15 avatar: Humanoid, HumanoidRootPart, 15 MeshParts with SurfaceAppearance (colour and normal), and 15 WrapTargets, so the cages were recognised. |
| Height | 5.57 studs, feet on the ground, HipHeight 2.73 |
| Play | Spawns as StarterCharacter, R15 rig type, runs at 16 studs/s with the default R15 animations. Accessories are joined with AccessoryRigidConstraint. |
| Layered clothing | Puffer, cargo, sneakers and briefs import as WrapLayer MeshParts. They wrap the V3.1 body in edit mode and in play, and follow the walk and run cycles. |
| Importer quirks | A plain glTF arrives turned 180° about Y and centred on its bounding box; skinned bodies are not turned. The installers place pieces at `LowerTorso.RootRigAttachment * (-x, z, y)`. |

## 7. Premium wear pipeline (`build_exit6_wear_v31.py`)

Every garment is shaped from the V3.1 body surface, so it fits this body without a fitting pass. The steps are:

1. Region mask.
2. Drape smoothing at base resolution, which removes the anatomy.
3. Offset and shaping.
4. Push clear of the skin.
5. Decimate to the game mesh.
6. Bake colour and normal at 1024, filling bake-miss texels.
7. Skin to the R15 rig by weight transfer from the body.
8. Build cages: the inner cage is the fitted body cage; the outer cage is the inner cage inflated around the garment.

| Item | Kind | Notes |
|---|---|---|
| `Exit6_Puffer` | Layered, order 6 | Quilted channels, stand collar, zip, banded cuffs and hem. Near-white colour map, tinted with `SurfaceAppearance.Color` (test: 34, 34, 38). |
| `Exit6_Cargo` | Layered, order 4 | Joggers: waistband, thigh cargo pockets with flaps, back pockets, knee seams, ankle stacking, ribbed cuffs. Tintable (test: olive 92, 96, 70). |
| `Exit6_Sneakers` | Layered, order 3 | Low-top: cupsole, foxing band, laces on the top panel, heel tab. Generic design with no brand marks. Coloured map. |
| `Exit6_Briefs` | Layered, order 1 | The V3 briefs, now with cages. |
| `Exit6_Chain` | Rigid, NeckAttachment | 60-link curb chain draped on the trapezius and chest. Gold. |
| `Exit6_Watch` | Rigid, `Exit6WatchAttachment` on LeftLowerArm | Case, bezel, dial and band on the back of the wrist. |

Hair (`Exit6_Hair_Twists`, HairAttachment), brows (`Exit6_Brows`) and goatee (`Exit6_Goatee`, both FaceFrontAttachment) are separate Accessories. The eyes are welded to the Head. Hair, clothing and jewellery are all separate, swappable assets.

## Rebuild

```
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend -P tools/characters/polish_exit6_male_v31.py
python tools/characters/exit6_anatomy_v31.py
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3_1.blend -P tools/characters/export_exit6_male_v31.py
blender -b --factory-startup -P tools/characters/validate_glb.py -- Exit6_Male_V3_1_Body.glb renders_v3_1 validate_report_v31.json
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3_1_Game.blend -P tools/characters/build_exit6_wear_v31.py
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3_1_Game.blend -P tools/harness/render_cage_check.py -- build/exit6_v3/polish/cage
blender -b --factory-startup assets/characters/exit6_male/wear_v31/Exit6_Wear_V31.blend -P tools/harness/render_game_mesh.py -- build/exit6_v3/polish/game/dressed "*"
```

The Roblox templates are downloaded to `build/roblox_templates/` (gitignored), from `prod.docsiteassets.roblox.com/assets/modeling/meshes/reference-files/Body_Cage_Templates.zip`.

## Known gaps / next steps

**Puffer**

- A dark crease where the sleeves press against the body shell at the armpits. It needs separate sleeve and body shells, or an armpit gap.

**Sneakers**

- The toes are slightly lumpy under the cupsole. A purpose-built shoe last would be cleaner than a smoothed foot.

**Briefs**

- The briefs' outer cage is coarse, so under the cargos their hem pokes through. The test place wears the briefs only when no pants are on (`OnlyWithoutPants` attribute). The builder now uses a 0.035 gap for the next export.

**Chain**

- The chain sits under the puffer collar. It reads best with no jacket or with the jacket open.

**Tinting**

- Only the puffer and cargo are tintable. Sneaker colourways need their own colour maps.

**Before integrating into Exit 6**

- The current Exit6Style / premium system (`px_*`) fits the standard R15 body. V3.1 wear is layered clothing for the V3.1 body, so the integration has to switch the player look to the V3.1 rig and these WrapLayer accessories.
- Before integrating, re-export the body with bone-parented `_Att`, and upload it as a new version of 117787451658215.
- The importer lists the outer cages' InitialPoses `_Node` names. This is harmless.
