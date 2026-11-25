# Exit 6 male, V3: visual quality correction

Status: **built, waiting for visual review.** It is not committed, not published, and not in the Roblox place.

V3 continues V2. The rig, R15 skin weights, pose tests, export and validation pipeline are unchanged. What changed is how the face is shaped, plus the hair, goatee, eyes, body forms and hands. The review standard is resemblance to the approved reference sheet. Neutral-light renders from matching angles are the judge. Silhouette IoU and landmark error are now only sanity checks.

## Why V2 failed, and what V3 does instead

V2 warped the MPFB head onto about 40 landmarks measured off the reference, using a thin-plate spline:

- Before the warp, the base head sat 20 to 39 px from the targets. The warp therefore pushed the whole lower face outward between the landmarks, which made the face look swollen.
- Three "midline" landmark vertices were actually 3 to 6 px off the centre line. Pulling them to x = 0 twisted the mouth.
- V2's face targets added volume to the cheeks, lips and nose.

Hair, brows and the goatee hid much of this. Rendered without hair under neutral light, the V2 face had a skewed mouth and a lower lip that ran into the chin as a V. See `build/exit6_v3/iterations/face_v3_b0_*`.

The brief allowed abandoning the procedural landmark warp, and V3 does:

1. **Artist-sculpted MPFB shape targets set the face** (`FACE_TARGETS_V3B` in `tools/characters/exit6_male_v3_spec.py`). They give:
   - lean cheeks under high cheekbones, younger and smoother;
   - an angular jaw tapering to a narrower chin;
   - thinner lips with a stronger cupid's bow and less projection;
   - a narrower nose with a rounder tip, turned up so the nostrils show;
   - almond eyes with a heavier upper fold;
   - no double chin.
2. **The head is fitted by a single smooth affine transform** (`HEAD_FIT = "affine"`): a least-squares scale, shear and translation onto the reference landmarks. Nothing is pinned point by point, so the face stays anatomically coherent.
3. **Named sculpt strokes make local corrections** (`FACE_SCULPT`, engine in `tools/characters/exit6_sculpt_v3.py`):

   | Stroke | Effect |
   |---|---|
   | `under_jaw_hollow` | Hollows the soft tissue under the jaw so the mandible edge reads crisply. |
   | `gonial_angle` | Defines the jaw corner. |
   | `upper_lid_lower` | Brings the upper lid down over the top of the iris. |
   | `lower_lid_raise` | Raises the lower lid slightly. |
   | `nasolabial_soften` | Softens the nasolabial fold. |
   | `jaw_line_relax` | Relaxes the jaw line after the strokes above. |

   Every stroke and the distance it moved is logged in the build log.

## Face

- **Eyes.** The eyes are now shaded procedurally (`eye_material3`):
  - an off-white sclera;
  - a large, near-black brown iris (43° from the gaze axis) and pupil;
  - a gloss coat on the eyeball, with the grey-tinting cornea shell made invisible.

  The upper lash line is painted heavier and the lower one lighter, matching the reference's dark upper liner.
- **Lips.** The upper lip is dark and the lower lip is close to skin tone, as in the reference, with a defined mouth line.
- **Goatee.** The goatee is rebuilt from the reference outline, traced off 10× zooms (`exit6_hair_v3.goatee`):
  - a narrow soul patch from row 319.5 that opens into a wide chin patch (±17.5 px at row 327);
  - a V-shaped lower edge to row 336 that wraps under the chin back to Y −31;
  - a tapered shell, 2.6 px thick in the middle and meeting the skin at the edge, with a noise-broken alpha edge.

  It follows the chin instead of standing off it as a flat triangle.
- **Brows.** The brows keep their shape, but their relief is halved so they sit close to the skin.
- **Skin.** The skin tone is unchanged (sRGB 152, 87, 47).

## Hair

The hair runs through `exit6_hair_v3.py`, which keeps V2's growth and mesh code but changes the parameters and two functions:

- **Fewer, separated twists.** There are 58 twists, down from 78, with root spacing raised from 14 to 16.5 px, so each twist hangs separately with visible gaps.
- **Twist shape.** The radius is 4.7 px (V2: 5.2). Bead pitch is 9 px, about one bead per twist width, from two chunky strands with a light swell (`BEAD_SWELL = 0.06`), so the beads are round and regular rather than lumpy.
- **Crown volume.** Crown twists lift off the scalp before they fall (`GRAV_TOP`, `LIFT`), giving the rounded top in the reference.
- **Side flare.** Side twists flare outward instead of hugging the face.
- **Lengths.** Tips sit at the brows at the front and the jaw at the sides, and are shorter at the back than in V2 (`HAIR_TIP_ROWS`).
- **Scalp.** The scalp is dark with faint box parts, and the centre part is clearly visible, as in the reference.
- **Separate asset.** The hair is still a separate attachable mesh. The game version is 10,454 tris (V2: 14,984).

## Body

The following strokes are applied to the skin. They are also applied to the muscle-relief shrinkwrap target, because that projection would otherwise pull the skin back to the V1 forms:

| Stroke | Purpose |
|---|---|
| `pec_mass`, `pec_outer`, `pec_shelf`, `pec_lower_border` | Broad, square pecs with a shadowed lower edge. |
| `deltoid_cap`, `deltoid_front` | Round shoulder caps. |
| `upper_arm_mass`, `biceps_peak`, `forearm_mass` | Thicker arms; the reference arms were 4 to 8 px wider per side. |
| `quad_mass`, `calf_mass` | Fuller legs. |
| `lat_fin_*`, `waist_taper_blend` | Remove the sagging lat "fins" at the torso sides that V2 had. |

The hands were also corrected:

| Setting | Value |
|---|---|
| Hand scale | ×1.22 |
| Finger spread | 65% closed toward the middle finger |
| Thumb | Swung 55% toward the hand axis (V2's stuck out at about 75°) |
| Finger curl | Reduced to (6°, 14°, 10°) |

The hands now hang relaxed, with the fingers together, as in the reference.

Height, proportions, the R15 joints, the weights and the crouch fix are unchanged. In the pose tests (walk, arms up, crouch, twist) the shoulders and torso deform cleanly.

## Numbers

These are sanity checks only, not the success measure.

| | V2 | V3 |
|---|---|---|
| Silhouette IoU, front / 3/4 / side / back | 0.900 / 0.833 / 0.929 / 0.902 | 0.904 / 0.830 / 0.916 / 0.901 |
| GLB triangles, total | 47,144 | 42,558 |
| Body (15 R15 parts) | 26,756 | 26,756 |
| Head_Geo | 8,444 | 8,444 |
| Hair_Geo | 14,984 | 10,454 |
| FaceDetails (eyes, brows, goatee) | 2,488 | 2,428 |
| Briefs | 2,916 | 2,920 |
| Largest single mesh (in-experience limit 20k) | Hair 14,984 | Hair 10,454 |

`validate_report_v3.json` covers the GLB:

- one skin with 17 joints;
- 19 `_Att` attachments;
- at most 4 influences per vertex;
- a clean re-import.

Marketplace limits are unchanged from V2's analysis: the body is still far over the 10,742-tri Marketplace body budget, and a Marketplace version needs its own reduced model.

## Review files (`assets/characters/exit6_male/renders_v3/`)

| File | Content |
|---|---|
| `sheet_face_v3.png` | Reference, V2 (rejected), V3, V3 without hair and V3 clay; front, three-quarter and side at 6× reference scale. |
| `sheet_body_v3.png` | Reference, V3 and V3 clay; front, three-quarter and side. |
| `sheet_torso_v3.png`, `sheet_limbs_hair_v3.png`, `sheet_legs_v3.png` | Close-ups next to matching reference crops. |
| `compare_front/three_quarter/side/back.png` | Silhouette overlays. |
| `pose_tests_v3.png` | Walk, arms up, crouch and twist. |
| `review_*.png` | The raw high-resolution renders. |

## Rebuild

```
blender -b --factory-startup -P tools/characters/build_exit6_male_v3.py -- --stage=full --samples=96
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend -P tools/characters/export_exit6_male_v3.py
blender -b --factory-startup -P tools/characters/validate_glb.py -- Exit6_Male_V3.glb renders_v3 validate_report_v3.json
blender -b --factory-startup assets/characters/exit6_male/Exit6_Male_V3.blend -P tools/characters/render_review_v3.py
python tools/characters/compose_review_v3.py
python tools/characters/compose_compare.py render_v3 renders_v3
```

For fast face iteration, run `--stage=face [--no-hair] --tag=_x`, then `python tools/characters/compose_face_v3.py _x` and `sh tools/characters/closeups_v3.sh _x`. For fast body iteration, run `--stage=full --quick`.

## Known gaps

- **Muscle definition.** The reference has crisper, higher-contrast muscle definition, especially in the chest, deltoids, obliques and quads. V3 adds the mass in the right places, but the forms are softer. The next step is a baked high-frequency normal map: sculpted detail on a subdivided copy, baked to the game mesh.
- **Brows.** The brows are still V1's generated blocks. They have the right shape but look like slabs up close.
- **Briefs.** The briefs are still V2's loose cut, not the reference's fitted boxer briefs (not in the V3 brief).
- **Roblox import items.** These are still open from V2: outer cages, capped part seams, `_Att` import verification in Studio, and SurfaceAppearance.
