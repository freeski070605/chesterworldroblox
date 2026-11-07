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
-- HIGHWAY CORRIDOR PROFILE (generator-owned, TileBuilderV2)
-- ============================================================
-- The imported terrain is a bare-earth DEM: wherever a highway rides over a
-- street, creek or rail line the DEM drops into a notch, and a terrain-
-- following strip dives into it (or is deleted by MAX_SURFACE_GRADE).
-- HighwayProfile chains every highway segment into continuous strokes and
-- solves one smooth vertical profile per stroke instead. Rollback switch:
-- false restores per-strip terrain following for highways.
WorldConfig.HIGHWAY_PROFILE_ENABLED = true

-- Station spacing for terrain sampling along a stroke.
WorldConfig.HIGHWAY_PROFILE_SAMPLE_STUDS = 6.0
-- A dip is bridged when higher ground exists on BOTH sides within this
-- distance (overpass notches are ~100-160 studs wide). Wider valleys are
-- real terrain and are followed (subject to the grade limit).
WorldConfig.HIGHWAY_PROFILE_NOTCH_WINDOW_STUDS = 240.0
-- A narrow bump with lower ground on both sides within this distance is
-- treated as a DEM artifact (e.g. a retained overpass deck) and cut.
WorldConfig.HIGHWAY_PROFILE_SPIKE_WINDOW_STUDS = 90.0
-- In-world grade limits. Horizontal studs are EPSG:3857-stretched (~1.30x at
-- Chester) while vertical studs are true metres x3, so an in-world 0.07 is
-- ~5.4% real grade and 0.10 is ~7.7%.
WorldConfig.HIGHWAY_PROFILE_MAX_GRADE_MAINLINE = 0.07
WorldConfig.HIGHWAY_PROFILE_MAX_GRADE_LINK = 0.10
-- Moving-average window that rounds vertical curves.
WorldConfig.HIGHWAY_PROFILE_SMOOTH_STUDS = 36.0
-- Maximum length of one rendered pavement piece along a stroke.
WorldConfig.HIGHWAY_PROFILE_PIECE_STUDS = 24.0
-- Minimum opening between a highway deck underside and the lower road top
-- where the highway is the upper road. A registry inventory value raises it.
WorldConfig.HIGHWAY_UNDERPASS_MIN_CLEARANCE_STUDS = 14.0
-- Minimum design clearance over a bridge-tagged span with no known lower road
-- (water, rail). Used only when the DEM rims do not already provide it.
WorldConfig.HIGHWAY_OPEN_SPAN_MIN_CLEARANCE_STUDS = 18.0
-- Classification of profiled pavement relative to the terrain below it.
WorldConfig.HIGHWAY_STRUCTURE_FILL_MIN_GAP_STUDS = 2.0
WorldConfig.HIGHWAY_STRUCTURE_NOTCH_SPAN_DEPTH_STUDS = 8.0
WorldConfig.HIGHWAY_STRUCTURE_MIN_SPAN_STUDS = 14.0
-- Lateral clearance added to each side of a lower road when sizing a span
-- that has no registry footprint (sidewalk + shoulder).
WorldConfig.HIGHWAY_SPAN_SIDE_MARGIN_STUDS = 10.0
-- Highway lane markings.
WorldConfig.HIGHWAY_LANE_WIDTH_STUDS = 12.0
WorldConfig.HIGHWAY_LANE_DASH_STUDS = 10.0
WorldConfig.HIGHWAY_LANE_DASH_PERIOD_STUDS = 36.0
WorldConfig.HIGHWAY_MARKING_WIDTH_STUDS = 0.5
WorldConfig.HIGHWAY_EDGE_INSET_STUDS = 2.5
WorldConfig.HIGHWAY_MARKING_COLOR = Color3.fromRGB(236, 236, 230)
WorldConfig.HIGHWAY_EDGE_LEFT_COLOR = Color3.fromRGB(236, 190, 54)
-- Structures built by HighwayInfrastructure from the profile classification.
WorldConfig.HIGHWAY_BARRIER_HEIGHT_STUDS = 3.2
WorldConfig.HIGHWAY_BARRIER_MIN_FILL_STUDS = 4.0
WorldConfig.HIGHWAY_PIER_MAX_SPACING_STUDS = 95.0
WorldConfig.HIGHWAY_STRUCTURE_COLOR = Color3.fromRGB(150, 148, 142)
WorldConfig.HIGHWAY_BARRIER_COLOR = Color3.fromRGB(176, 175, 168)

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

-- Tester flight / fast travel (src/client/DebugFlight.client.lua, keyboard +
-- gamepad). Always on in Studio. In a live server: everyone while
-- TESTER_FLIGHT_ALL is true (testing builds), otherwise only these user ids.
WorldConfig.TESTER_FLIGHT_ALL = true
WorldConfig.TESTER_USER_IDS = {}

-- Real-building facades (src/server/World/RealBuildings.lua): homes with a
-- front / back / side door instead of doors on every wall, walk-in stores with
-- the entrance on their address street. Studs; nil = everywhere off. First
-- region: 9th & Kerlin / 9th & Concord, for review before going citywide.
WorldConfig.REAL_BUILDINGS_REGION = { minX = 1900, maxX = 3500, minZ = 800, maxZ = 2300 }
-- every home (lite house kit) and store in the city is a real building; the
-- region above keeps the full-detail kit (modelled windows, back doors)
WorldConfig.REAL_BUILDINGS_ALL = true
-- single buildings outside the region that are built real too (walk-in
-- stores the gameplay needs): county OBJECTID -> true
WorldConfig.REAL_BUILDINGS_EXTRA = {
	["1621"] = true,    -- Cliza Boutique (clothing), 9th St east of the region
	["167270"] = true,  -- Chester Fashions (clothing)
}

return WorldConfig
