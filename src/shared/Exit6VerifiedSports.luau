-- Exit 6 verified sports reconstruction (v2).
--
-- Every value here was measured from the georeferenced DVRPC 2025 orthophoto
-- (PASDA DVRPC2025 MapServer, EPSG:3857) with tools/sports/*.py, in Roblox
-- world studs: +X east, +Z south (north is -Z), 3 studs per EPSG:3857 metre.
-- Boxes are { centreX, centreZ, length, width, yaw } exactly as Parks.lua:
-- local +X runs along `length`, rotation CFrame.Angles(0, rad(yaw), 0).
-- Measurement notes and before/after overlays: docs/EXIT6_SPORTS_RECONSTRUCTION.md
--
-- ParkBuilder applies, in order: `corrections` to OSM features (matched by
-- box centre within 1 stud), then adds `facilities`. Terrain conforming is
-- runtime-only and bounded to each surface plus a feather ring; set
-- Workspace attribute Exit6SportsConform=false before ParkBuilder runs to
-- disable it, or invoke ServerStorage.Exit6SportsTerrain("restore").

local MEMORIAL_SOURCE = "DVRPC 2025 orthophoto; OSM 'Veterans Memorial Park' (Q49574680); City of Chester park plan"
local AFIELD_SOURCE = "DVRPC 2025 orthophoto (track segmentation + yard-line profile); Chester Upland SD 2026 RFP"

return {
	version = 2,

	-- Shared finished-surface levels: members are built on one level plane
	-- sampled over `box`, and the terrain under `box` is conformed once.
	levelGroups = {
		memorial_courts = { box = { -3406.2, 5776.9, 159.1, 122.2, 33.7 }, margin = 14,
			pad = { material = "Asphalt", color = { 62, 64, 66 } } },
		-- outer kerb 696 x 309 (+3): conform and grass base follow the oval
		a_field = { box = { 13.4, 1545.2, 700, 312, -83.86 }, margin = 24, shape = "oval",
			pad = { material = "Grass", color = { 86, 124, 58 }, half = 193.5, radius = 124.5 } },
	},

	corrections = {
		-- Chester Memorial Park: both OSM court outlines match the painted
		-- courts (centre circles within 3 studs); they share one asphalt pad.
		{ at = { -3437.8, 5798.5 }, set = { group = "memorial_courts", facility = "Chester Memorial Park" } },
		{ at = { -3378.8, 5758.4 }, set = { group = "memorial_courts", facility = "Chester Memorial Park" } },
		-- Chester Athletic Complex: OSM football box is 5 studs / 0.6 deg off
		-- the measured field; replaced by the facility below.
		{ at = { 17.3, 1541.6 }, drop = "replaced by verified A Field reconstruction" },

		-- Citywide audit: mapped surfaces with nothing on the ground in 2025.
		{ at = { -3745.6, -13188.7 }, drop = "no tennis court in 2025 aerial (grass)" },
		{ at = { -3855.5, -13146.3 }, drop = "no tennis court in 2025 aerial (grass)" },
		{ at = { -3801.6, -13167.6 }, drop = "no tennis court in 2025 aerial (grass)" },
		{ at = { -3690.9, -13210.3 }, drop = "no basketball court in 2025 aerial (grass)" },
		{ at = { 5285.3, 4459.1 }, drop = "footprint is a building roof in 2025 aerial" },
		{ at = { 9645.6, -5766.6 }, drop = "no diamond in 2025 aerial (overgrown meadow)" },

		-- One 833 x 589 OSM pitch covers three separate pitches.
		{ at = { -547.9, 8780.3 }, replace = {
			{ kind = "pitch", sport = "soccer", box = { -814, 8893, 414, 225, -56.6 } },
			{ kind = "pitch", sport = "soccer", box = { -585, 8754, 414, 225, -56.6 } },
			{ kind = "pitch", sport = "soccer", box = { -339, 8607, 414, 225, -56.6 }, note = "covered/white surface in 2025" },
		} },
		-- One OSM baseball box covers two skinned infields.
		{ at = { -2026.1, -6723.4 }, replace = {
			{ kind = "pitch", sport = "baseball", box = { -2046.2, -6718.6, 210, 210, 87.0 }, home = { -1, -1 }, base = 71 },
			{ kind = "pitch", sport = "baseball", box = { -1962.1, -6742.5, 170, 170, -93.4 }, home = { -1, -1 }, base = 71 },
		} },
		-- OSM box covers only the infield half; remeasured from home plate
		-- and both foul lines.
		{ at = { -12559.0, -1938.6 }, replace = {
			{ kind = "pitch", sport = "baseball", box = { -12596.8, -2036.0, 366, 366, 117.6 }, home = { -1, -1 }, base = 107 },
		} },

		-- Baseball: home plate corner read from each aerial (local sign of X, Z).
		{ at = { 9877.5, -5361.3 }, set = { home = { -1, 1 }, base = 107 } },
		{ at = { -2963.5, -13783.1 }, set = { home = { 1, 1 }, base = 83 } },
		{ at = { -2767.2, -14026.0 }, set = { home = { -1, -1 }, base = 71 } },
		{ at = { -2540.4, -14119.3 }, set = { home = { 1, 1 }, base = 83 } },
		{ at = { -2801.0, -13832.7 }, set = { home = { -1, 1 }, base = 55, infieldOnly = true } },
		{ at = { -2577.6, -13804.4 }, set = { home = { -1, 1 }, base = 71 } },
		{ at = { 452.0, 1320.2 }, set = { home = { 1, 1 }, base = 107 } },

		-- Schoolyard half courts: one hoop, on the side toward the curb.
		{ at = { -4466.6, -9617.9 }, set = { halfCourt = -1 } },
		{ at = { -4499.6, -9657.7 }, set = { halfCourt = -1 } },

		-- Widener / Gillespie stadium track is a blue eight-lane oval.
		{ at = { 8364.9, -7026.5 }, set = { lanes = 8, trackColor = { 74, 92, 126 } } },
	},

	facilities = {
		{
			id = "memorial_park", name = "Chester Memorial Park", address = "2700 W 7th St", source = MEMORIAL_SOURCE,
			-- Four light-pole bases (shadow roots) give a 225 x 212 lit
			-- rectangle; centre and axis are the field's. Bleacher rows and the
			-- west fence run on the same NNW-SSE axis as the courts.
			features = {
				{ kind = "pitch", sport = "american_football", facility = "Chester Memorial Park",
					box = { -3586, 6081, 428.5, 190.6, 124.2 }, grade = 0.01, paintMesh = true },
			},
			stands = {
				{ at = { -3506, 5984 }, length = 31, depth = 7.5, face = { -3586, 6081 }, axisYaw = 124.2 },
				{ at = { -3736, 6112 }, length = 31, depth = 7.5, face = { -3586, 6081 }, axisYaw = 124.2 },
				{ at = { -3689, 6181 }, length = 31, depth = 7.5, face = { -3586, 6081 }, axisYaw = 124.2 },
				{ at = { -3646, 6247 }, length = 31, depth = 7.5, face = { -3586, 6081 }, axisYaw = 124.2 },
			},
			lightPoles = { { -3552, 5931 }, { -3739, 6056 }, { -3433, 6106 }, { -3621, 6231 } },
			fences = { { -3730, 5885, -3825, 5960, -3767, 6070 } },
		},
		{
			id = "a_field", name = "Chester Athletic Complex A Field", address = "1100 W 10th St", source = AFIELD_SOURCE,
			track = { group = "a_field", centre = { 13.4, 1545.2 }, yaw = -83.86,
				-- infield 636 x 249 (inner kerb), six lanes in a 30-stud band
				straightHalf = 193.5, innerRadius = 124.5, lanes = 6, band = 30,
				color = { 158, 72, 54 },
				-- 100 m chute: west straight (local +Z) continues north (local -X)
				chute = { fromX = -193.5, toX = -303, side = 1 } },
			features = {
				-- 21 yard lines at 17.98-stud spacing: goal lines at u = -181 and
				-- +178.5 along the track axis, so the field shares its yaw.
				{ kind = "pitch", sport = "american_football", facility = "Chester Athletic Complex A Field",
					box = { 13.27, 1543.96, 431.4, 191.7, -83.86 }, group = "a_field", paintMesh = true },
			},
			stands = {
				{ at = { -178.4, 1563.0 }, length = 286, depth = 47, face = { 13.27, 1543.96 }, axisYaw = -83.86, name = "WestGrandstand" },
				{ at = { 187.9, 1529.0 }, length = 203, depth = 24, face = { 13.27, 1543.96 }, axisYaw = -83.86, name = "EastBleachers" },
			},
		},
	},
}
