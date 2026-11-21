# Exit 6 — Street furniture corrections (exception to road work pause)

Requested November 21, 2026. Keep the road/highway reconstruction project paused. This task addresses misplaced street signs and streetlight props only.

## Local corrections

### W 9th Street & Concord Avenue
- Move the "9th & Concord" street-name sign assembly to the curb/sidewalk corner, fully outside the vehicle travel surface.
- Prefer mounting signs on an existing streetlight/utility pole when the real-world arrangement supports it; avoid duplicate poles.
- Ensure sign text remains oriented to approaching traffic and doesn't clip sidewalk or road.

### W 9th Street & Kerlin Street
- Move the streetlight currently standing in the middle of the street to the sidewalk on the opposite side of the street from the sign, following the user's stated real-world reference.
- Keep pole base and collision entirely outside the vehicle travel surface.
- Preserve driving clearance and avoid blocking crosswalk/pedestrian path.

## Citywide placement policy
- Street-name blades should attach to light/utility poles when those poles are present in the matching real-world corner configuration, with correctly oriented cross-street names.
- When no suitable pole exists, use a single curbside signpost rather than a road-center post.
- Ground the final side/corner and orientation in verified Chester reference imagery or survey data; do not guess coordinates or claim every sign is on a light pole.
- Reuse an existing pole whenever possible. Do not change actual street geometry or highway ramps.

## Implementation guidance
1. Locate source code that instantiates StreetSign, StreetLight, LampPost, or their road/furniture equivalents and inspect active generated tiles.
2. Identify the authoritative coordinates for W 9th/Concord and W 9th/Kerlin and the traffic-facing pole/sidewalk locations in ChesterWorld's coordinate system.
3. Apply precise local overrides for those intersections after the common generation step; keep them idempotent under tile streaming.
4. Update shared street furniture placement to anchor signs to existing curbside poles where verified, otherwise use curbside fallback; avoid writing overrides that shift roads.
5. Run Rojo/Studio test, verify no pole/sign collision boxes intersect the road drivable region, and validate from multiple camera approaches.
6. Xbox drive through both intersections. Check signs remain stable after streaming in/out.

## Status
Requested and specified. **Not yet implemented or verified.** Do not describe the in-world poles/signs as moved until source changes and Studio tests confirm them.
