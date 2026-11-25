# Exit 6 sports reconstruction handoff

## Geographic evidence

- Chester Athletic Complex (local A Field): existing OSM football footprint at
  `(17.3, -1541.6)` after aligning the park data's Z axis with the shipped roads.
  The local DVRPC 2025 aerial shows the field, a curved oval track, and a stand
  on its west side. Chester Upland School District locates the complex at
  1100 W. 10th Street. Its November 2026 bid describes the *current* six-lane
  track and proposes expanding it to eight lanes; the eight-lane proposal is
  not represented here.
- Chester Memorial Park: City's park plan describes football, pool, tennis and
  basketball facilities and locates the park between W. 7th and W. 9th near
  Engle and Ward. The source aerial and OSM footprint place the mapped two
  basketball courts at approximately `(-3438, -5798)` and `(-3379, -5758)`.
  The hand-measured football footprint at `(-3700, -5950)` lies within the park
  polygon, clear of mapped roads and basketball polygons. It should receive a
  final field-edge check in Studio against the aerial.
- The large OSM track at `(8365, 7027)` belongs to the separate Gillespie/Quick
  Stadium area. Three small steeplechase polygons nearby are track details,
  not three more stadiums.

Source references: [Chester park plan](https://www.chestercity.com/wp-content/uploads/2018/11/Resilience_Through_Recreation_Plan_111218.pdf),
[Chester park venues](https://www.chestercity.com/venue/memorial-park/page/2/?eventDisplay=past),
[school district bid](https://resources.finalsite.net/images/v1794320934/efswgpmnix8omge7cgfg/2026_RFP_CUSD_AthleticField_UpgradesPhase_1.pdf),
and project source `E:\ChesterWorld\Data\19_Aerial` (DVRPC 2025).

## Mesh import

The runtime cannot load a local GLB from a published Roblox experience. The
five original GLBs in `assets/sports/` each contain one textured mesh primitive:

| Config key | Source file | Native size in studs |
| --- | --- | --- |
| `streetHoop` | `street_hoop.glb` | 3.8 × 13.2 × 6 |
| `courtPaint` | `court_paint_100x60.glb` | 100 × 0.2 × 60 |
| `footballPaint` | `football_paint_360x160.glb` | 360 × 0.7 × 160 |
| `sixLaneOval` | `six_lane_oval_560x260.glb` | 560 × 0.1 × 260 |
| `bleacherSection` | `bleacher_section_60.glb` | 60 × 4 × 9 |
| `sportsPalette` | `sports_palette.png` | texture |

1. Run `blender --factory-startup --background --python tools/build_sports_meshes.py`
   if the source meshes need regeneration.
2. In Roblox Studio's 3D Importer, import each GLB and upload its MeshPart mesh.
   Confirm the preview is upright and the source size is preserved in studs.
3. Upload `sports_palette.png` as an image. Copy the numeric mesh and texture
   IDs from Studio into `src/shared/Exit6SportsMeshIds.luau` (digits only).
4. Publish a test place. Confirm one mesh visual, one hidden Rim shot target per
   hoop, painted arcs, football markings, the curved track, and no grass on
   any of the 21 mapped basketball surfaces. Check the two Memorial Park courts.
5. Check Xbox draw and streaming behavior before promoting the place.

Until the IDs are populated, the builder displays its old court and track
fallback geometry. This keeps play working but does **not** complete the mesh
visual replacement. No Roblox asset IDs have been guessed.

## Source audit and performance estimate

- OSM sports data: 21 basketball courts, two football fields, four athletics
  polygons. Three small steeplechase polygons are filtered as detail features.
- One Memorial football field is added from the park plan and aerial. The
  existing A Field and Gillespie football footprints keep their surveyed
  centers; the track builder avoids adding a second football field at Gillespie.
- All basketball courts use the same hardcourt builder. It removes terrain
  inside the playing rectangle only and retains `Exit6Court` tags, court size
  attributes and the two `Rim` BasePart targets used by gameplay.
- Once IDs are configured, the shared court builder uses approximately six
  BaseParts per court versus about 28 before: about 462 fewer BaseParts over
  21 courts. This is a source count estimate, not a Studio instance count.
- `python tools/audit_sports_placement.py` checks the Memorial football polygon
  against the source park, roads and court footprints. `python -m unittest
  tools/test_sports_facilities.py -v` validates GLB structure and court wiring.

## Verification still needed in Studio

Runtime mesh loading and texture appearance, field-edge alignment, grass
collision, basketball gameplay, a complete driven route, and Xbox performance
must be checked in Roblox Studio or on device. The aerial crops under
`build/sports_reference/` are source evidence, not before/after Studio shots.
