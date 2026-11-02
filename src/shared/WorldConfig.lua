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
WorldConfig.SIDEWALK_INTERSECTION_TRIM_STUDS = 14.0

WorldConfig.ROAD_MAX_PIECE_LENGTH_STUDS = 120
WorldConfig.ROAD_TERRAIN_ERROR_STUDS = 1.10
WorldConfig.ROAD_MAX_SUBDIVISION_DEPTH = 5

-- Reject terrain samples that would make an obviously broken road slab.
WorldConfig.MAX_SURFACE_GRADE = 0.40

WorldConfig.INTERSECTION_ENDPOINT_QUANTIZE_STUDS = 3.0
WorldConfig.INTERSECTION_MIN_DEGREE = 3
WorldConfig.INTERSECTION_SIZE_MULTIPLIER = 1.20

-- ============================================================
-- PHASE 2C — PRODUCTION STREET READABILITY
-- ============================================================

-- Only wider corridors receive center lines. Chester residential streets
-- generally remain visually clean instead of getting fake markings everywhere.
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
WorldConfig.CROSSWALK_BASE_SETBACK_STUDS = 10.0

-- Street-name poles are limited to named intersections involving a wider road.
-- This keeps the whole-city object count under control.
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
