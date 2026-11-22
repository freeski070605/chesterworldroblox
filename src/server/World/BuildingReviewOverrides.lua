-- Evidence-approved citywide corrections, keyed to stable county OBJECTID.
-- Only put corrections here after matching full-size source imagery to a
-- footprint / camera position. Unknown matches must stay untouched.
-- Data carries sources and confidence for auditing; no gameplay IDs change.
return {
    ["13452"] = {
        style = "garage",
        evidence = "2026-11-21 citywide visual review: full-size photo verified garage, not twin",
        confidence = "verified_building_type",
        -- Front door/garage-door bearing is NOT established by this review.
    },
}
