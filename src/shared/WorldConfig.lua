local WorldConfig = {}

local WorldPlacement = require(script.Parent:WaitForChild("WorldPlacement"))

WorldConfig.STUDS_PER_METER = WorldPlacement.STUDS_PER_METER
WorldConfig.WORLD_CENTER_X_M = WorldPlacement.CENTER_X_M
WorldConfig.WORLD_CENTER_Z_M = WorldPlacement.CENTER_Z_M

-- ============================================================
-- BASE ROAD / SIDEWALK GEOMETRY
-- ============================================================

WorldConfig.ROAD_THICKNESS_STUDS = 0.45
WorldConfig.ROAD_SURFACE_OFFSET_STUDS = 0.30

WorldConfig.SIDEWALK_HEIGHT_STUDS = 0.65
WorldConfig.SIDEWALK_WIDTH_STUDS = 5.0
WorldConfig.SIDEWALK_GAP_STUDS = 0.10

-- Sidewalks stop farther back than asphalt at a junction so they do not cut
-- across the intersection surface.
WorldConfig.SIDEWALK_INTERSECTION_EXTRA_TRIM_STUDS = 4.0

WorldConfig.ROAD_MAX_PIECE_LENGTH_STUDS = 120
WorldConfig.ROAD_TERRAIN_ERROR_STUDS = 1.10
WorldConfig.ROAD_MAX_SUBDIVISION_DEPTH = 5

-- Reject terrain samples that would make an obviously broken road slab.
WorldConfig.MAX_SURFACE_GRADE = 0.40

-- Highway pavement recovery: preserve a flagged strip rather than silently
-- deleting it when the bare-earth DEM implies a steep grade. This does NOT
-- make that steep grade safe; the bridge/ramp profile must still be repaired.
-- Set false to restore the previous omission behavior while diagnosing.
WorldConfig.RECOVER_STEEP_HIGHWAY_PAVEMENT = true

-- ============================================================
-- INTERSECTIONS
-- ============================================================

WorldConfig.INTERSECTION_ENDPOINT_QUANTIZE_STUDS = 3.0
WorldConfig.INTERSECTION_MIN_DEGREE = 3

-- Pads are intentionally compact. Roads are trimmed exactly to the square
-- boundary, so a large multiplier is no longer needed to hide overlaps.
WorldConfig.INTERSECTION_SIZE_MULTIPLIER = 1.05
WorldConfig.INTERSECTION_MIN_SIZE_STUDS = 12.0
WorldConfig.INTERSECTION_MAX_SIZE_STUDS = 72.0
WorldConfig.INTERSECTION_ROAD_OVERLAP_STUDS = 1.0
WorldConfig.INTERSECTION_MAX_GRADE = 0.16

-- ============================================================
-- GRADE SEPARATION / BRIDGES
-- ============================================================

-- Default deck clearance for bridge/layer +1 segments. Higher positive layers
-- stack by this amount. Ground and tunnel roads remain terrain-following.
WorldConfig.GRADE_SEPARATION_CLEARANCE_STUDS = 18.0

-- Bridge groups ramp up/down over this fraction of their source span.
WorldConfig.BRIDGE_RAMP_FRACTION = 0.38

-- Highway finishing: vertical clearance is measured over the highest ground
-- road that actually crosses the bridge, not merely against bare terrain.
WorldConfig.HIGHWAY_MIN_CLEARANCE_STUDS = 18.0
WorldConfig.HIGHWAY_MAX_DECK_LIFT_STUDS = 65.0
WorldConfig.HIGHWAY_APPROACH_LENGTH_STUDS = 300.0
WorldConfig.HIGHWAY_MAX_APPROACH_GRADE = 0.10
WorldConfig.HIGHWAY_BRIDGE_CONNECT_TOLERANCE_STUDS = 6.0
WorldConfig.HIGHWAY_DECK_THICKNESS_STUDS = 1.6
WorldConfig.HIGHWAY_GUARDRAIL_HEIGHT_STUDS = 3.2

-- ============================================================
-- PRODUCTION STREET READABILITY
-- ============================================================

WorldConfig.CENTERLINE_MIN_ROAD_WIDTH_STUDS = 30.0
WorldConfig.CENTERLINE_WIDTH_STUDS = 0.65
WorldConfig.CENTERLINE_THICKNESS_STUDS = 0.09
WorldConfig.CENTERLINE_SURFACE_OFFSET_STUDS = 0.58

-- Crosswalks are generated only at named intersections touching a wider road.
WorldConfig.CROSSWALK_TRIGGER_WIDTH_STUDS = 30.0
WorldConfig.CROSSWALK_MIN_ARM_WIDTH_STUDS = 18.0
WorldConfig.CROSSWALK_STRIPE_COUNT = 5
WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS = 1.55
WorldConfig.CROSSWALK_STRIPE_GAP_STUDS = 1.35
WorldConfig.CROSSWALK_THICKNESS_STUDS = 0.09
WorldConfig.CROSSWALK_SURFACE_OFFSET_STUDS = 0.60
WorldConfig.CROSSWALK_EDGE_CLEARANCE_STUDS = 2.0

-- Street-name poles are limited to named intersections involving a wider road.
WorldConfig.STREET_SIGN_TRIGGER_WIDTH_STUDS = 30.0
WorldConfig.STREET_SIGN_POLE_HEIGHT_STUDS = 13.0
WorldConfig.STREET_SIGN_POLE_THICKNESS_STUDS = 0.45
WorldConfig.STREET_SIGN_CORNER_CLEARANCE_STUDS = 5.0

-- ============================================================
-- BUILDINGS
-- ============================================================

WorldConfig.BUILDING_BASE_Y_STUDS = 0.20

-- ============================================================
-- MATERIALS / VISUALS
-- ============================================================

WorldConfig.ROAD_MATERIAL = Enum.Material.Asphalt
WorldConfig.SIDEWALK_MATERIAL = Enum.Material.Concrete
WorldConfig.INTERSECTION_MATERIAL = Enum.Material.Asphalt
WorldConfig.BUILDING_MATERIAL = Enum.Material.Concrete
WorldConfig.MARKING_MATERIAL = Enum.Material.SmoothPlastic
WorldConfig.SIGN_POLE_MATERIAL = Enum.Material.Metal

WorldConfig.ROAD_COLOR = Color3.fromRGB(48, 49, 50)
WorldConfig.SIDEWALK_COLOR = Color3.fromRGB(166, 165, 158)
WorldConfig.INTERSECTION_COLOR = Color3.fromRGB(48, 49, 50)
WorldConfig.CENTERLINE_COLOR = Color3.fromRGB(244, 190, 54)
WorldConfig.CROSSWALK_COLOR = Color3.fromRGB(235, 235, 228)
WorldConfig.SIGN_POLE_COLOR = Color3.fromRGB(92, 96, 91)
WorldConfig.SIGN_BACKGROUND_COLOR = Color3.fromRGB(24, 94, 55)
WorldConfig.SIGN_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

return WorldConfig
