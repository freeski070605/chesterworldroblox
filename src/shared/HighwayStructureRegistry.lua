-- ChesterWorld highway structure registry.
--
-- Data-only module. Each entry describes one real grade-separated crossing
-- whose physical extent has been researched beyond what the road source
-- encodes. HighwayProfile uses an entry to:
--   * decide which road passes over (when layer/bridge tags are silent),
--   * set the bridge span limits along the upper road, and
--   * set the minimum underclearance that the upper profile must achieve.
--
-- Every value carries its provenance. "provisional" means the value is a
-- research estimate that still needs survey / Studio verification; the
-- generator records that status on the parts it builds from the entry.
--
-- Coordinates are Roblox studs in the LOCKED frame (+X east, -Z north,
-- 3 studs per EPSG:3857 projected metre). Vertical values are studs at
-- 3 studs per real metre. EPSG:3857 horizontal scale at Chester (lat ~39.85)
-- is ~1.302 projected metres per ground metre, so real ground lengths
-- convert at ~3.906 studs/m horizontally but 3.0 studs/m vertically.

local Registry = {}
local DVRPC2025 = "https://imagery.pasda.psu.edu/arcgis/rest/services/pasda/DVRPC2025/MapServer/4"

Registry.STRUCTURES = {
	{
		id = "KERLIN_I95",
		description = "I-95 (both carriageways) over Kerlin Street",
		-- Source records (grade_group prefixes) for the roads above and below.
		upperSources = { "county:423", "county:424", "county:425", "county:426" },
		lowerSources = { "county:2758", "county:27163", "county:20771", "county:20770" },
		-- Deck footprint, visual pick from the official DVRPC 2025 Delaware
		-- County orthophoto (KerlinFootprintSurvey.lua, corrected corner
		-- order A-left, A-right, B-right, B-left). ~69 studs along I-95,
		-- ~118 studs across both carriageways. NOT surveyed abutment faces.
		footprint = {
			{ 1939.4802780665, -37.8303143063 },
			{ 2005.5860456761, 61.3283371164 },
			{ 2061.1749866262, 33.5338666414 },
			{ 2007.8396513920, -70.8831981110 },
		},
		footprintStatus = "provisional:aerial_visual_pick",
		-- NBI structure 14892: 64 ft length, 101 ft deck width, 14 ft 1 in
		-- minimum vertical underclearance (4.293 m -> 12.88 studs vertical).
		inventoryLengthFt = 64,
		inventoryWidthFt = 101,
		inventoryUnderclearanceStuds = 12.878,
		inventoryStatus = "published_inventory:usbridges_pa_045_14892",
		references = {
			"https://usbridges.org/bridge/pa-county-045-bridge-000000000014892",
			"https://maps.pasda.psu.edu/ArcGIS/rest/services/pasda/DVRPC2025/MapServer/4",
		},
	},
}

-- Crossings identified by ROAD NAME near a location, for structures whose
-- source records disagree with each other. The county z-levels around these
-- crossings put BOTH roads at level 1, so the source alone cannot say which
-- road is on top. Each entry below is taken from the published NBI bridge
-- inventory (structure number = inventory id); underclearance is the
-- inventory minimum vertical underclearance converted at 3 studs per metre.
-- center/radius are Roblox studs and only select which source crossings the
-- entry governs; they are NOT structure footprints.
-- `source` optionally overrides the status/references for entries that are
-- not from the city-data NBI listing.
local function namedEntry(id, structure, upper, lower, cx, cz, radius, clearanceM, note, source)
	return {
		id = id,
		description = note,
		upperNames = upper,
		lowerNames = lower,
		center = { cx, cz },
		radius = radius,
		inventoryStructure = structure,
		inventoryUnderclearanceStuds = clearanceM and clearanceM * 3 or nil,
		inventoryStatus = source and source.status or ("published_inventory:nbi_" .. structure),
		references = source and source.references or {
			"https://www.city-data.com/bridges/bridges-Chester-Pennsylvania.html",
			"https://www.city-data.com/bridges/bridges-Chester-Pennsylvania2.html",
		},
	}
end

Registry.NAMED = {
	namedEntry("EDGMONT_OVER_I95", "14989", { "edgmont ave" }, { "i 95", "edgmont ave to i 95" },
		6223, -2232, 75, 5.15, "Edgmont Avenue (PA 352) over I-95 and CSX"),
	namedEntry("MADISON_OVER_I95", "14964", { "madison st" }, { "i 95" },
		6372, -2256, 55, 5.18, "Madison Street (PA 320 NB) over CSX and I-95"),
	namedEntry("UPLAND_OVER_I95", "15445", { "upland st", "upland" }, { "i 95" },
		6802, -2509, 65, 5.03, "Upland Street over I-95 and CSX"),
	namedEntry("POTTER_OVER_I95", "15446", { "potter st" }, { "i 95" },
		7280, -2752, 65, 5.21, "Potter Street over I-95 and CSX"),
	namedEntry("CHESTNUT_OVER_I95", "15448", { "chestnut st" }, { "i 95", "i 95 to edgmont ave" },
		8114, -3199, 90, 5.43, "Chestnut Street over I-95 and CSX (source wrongly tags I-95 as upper)"),
	namedEntry("MELROSE_OVER_I95", "15449", { "melrose ave" }, { "i 95", "chestnut st to i 95" },
		8901, -3688, 75, 5.33, "Melrose Avenue over I-95, ramps and CSX"),
	namedEntry("HIGHLAND_OVER_I95", "14881", { "highland ave" }, { "i 95" },
		-7366, 4463, 75, nil, "Highland Avenue (relocated) over I-95 (source tags I-95 as upper)"),
	-- Added 2026-11-04 from the crossing inspection (user research package plus
	-- the DVRPC 2025 orthophoto with county segments overlaid; see
	-- tools/harness/crossing_aerial.py). No underclearance values, so the default
	-- underpass rule applies. The county data tags the LOWER road's pieces
	-- under a structure as layer 1 / bridge too, so its layer tags cannot decide
	-- these crossings.
	namedEntry("ENGLE_OVER_I95", nil, { "engle st" }, { "i 95" },
		-4624, 3108, 60, nil,
		"Engle Street over I-95, both carriageways (county 21206/21207 over 681/682/783/784). "
			.. "Aerial: Engle deck shadow across both carriageways. Confidence high.",
		{ status = "published_inventory:dvrpc_highway_inventory+aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("BULLENS_OVER_I476", nil, { "bullens ln" }, { "i 476", "macdade blvd to i 476" },
		9515, -11626, 70, nil,
		"Bullens Lane over I-476 and the MacDade ramp lane: one structure (county 20931/21560/21561/21562 "
			.. "over 437/474/20453 and 18298/20451/20452/473). Aerial: one deck spans the whole cut. Confidence high.",
		{ status = "published_inventory:bridge_inventory_and_photos+aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("I95_OVER_COMM_BARRY_RAMP", "14886", { "i 95" }, { "i 95 to comm barry" },
		-2538, 2040, 60, nil,
		"I-95 over the I-95 to Commodore Barry ramp at both carriageways: (-2564, 2078) county 21257/21259 "
			.. "over 26663/26562, and (-2513, 2003) 21256/21258 over 26562/26563. One skewed I-95 span between "
			.. "deck joints covers both; the ramp's own structure (26563, layer 1) starts at the second "
			.. "crossing, which made the layer rule put the ramp on top. Confidence high.",
		{ status = "published_inventory:usbridges_nbi_14886+aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("I95_OVER_CONCHESTER", nil, { "i 95" }, { "conchester" },
		-2811, 2150, 50, nil,
		"I-95 (dual bridges) over Conchester / US 322 at both carriageways: (-2838, 2132) county "
			.. "21255/21256 over 20524/21254, and (-2785, 2168) 16139/21257 over 21254/20525. Aerial: Conchester "
			.. "passes between I-95 deck joints and emerges on both sides. Confidence high.",
		{ status = "published_inventory:dvrpc_dual_i95_bridges+aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("EXIT4_RAMP_OVER_CONCHESTER", nil, { "i 95 from exit 4" }, { "conchester" },
		-2912, 2097, 25, nil,
		"I 95 From Exit 4 (county 26664 -> 22858) over Conchester (20523/20524). Aerial: the ramp leaves the "
			.. "I-95 deck and continues as the elevated flyover; Conchester runs beneath in its shadow. The "
			.. "real DEM puts the ramp ~52 studs above Conchester here. Not inventory-verified; confidence medium-high.",
		{ status = "provisional:aerial_dvrpc2025+dem", references = { DVRPC2025 } }),
	namedEntry("BARRY_MAINLINE_OVER_SECOND", nil, { "commodore john barry" }, { "2nd" },
		15, 6815, 70, nil,
		"Commodore Barry Bridge approach mainline (county 21239/21240/21212/21230) over 2nd Street / PA 291 "
			.. "(26648-26651). Aerial: approach decks cast shadows onto 2nd, which is at ground level on both "
			.. "sides. The ramp tie-ins at (80, 6754) and (-48, 6842) are NOT covered. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("I95_OVER_BULLENS", nil, { "i 95", "i 95 to n i 476", "i 476 to i 95" }, { "bullens ln", "bullens" },
		10580, -5503, 45, nil,
		"I-95 and its I-476 ramps over Bullens Lane: (10589, -5484) county 559/428/26098 over 21446/20386, "
			.. "(10571, -5522) 854/26181 over Bullens. Aerial: concrete I-95 deck, Bullens visible beneath on "
			.. "both sides. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	-- Added 2026-11-05 from the offline LOW CLEARANCE audit; every one checked
	-- against the DVRPC 2025 orthophoto (crossing_aerial.py sites in brackets).
	-- Source layer tags had the relation backwards at most of these.
	namedEntry("I95_OVER_CHESTER_PKE", nil, { "i 95", "i 95 to i 476", "i 476 to i 95" }, { "chester pke" },
		13730, -6985, 115, nil,
		"I-95 and the I-476 ramps over Chester Pike (county 1451/20526/21450/21449) [chester_pke]. Aerial: "
			.. "three concrete decks with shadows; Chester Pike hidden beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("BARRY_OVER_FLOWER", nil, { "commodore john barry" }, { "flower st", "flower" },
		-1330, 4680, 60, nil,
		"Barry approach over Flower St (county 20475/21224/20476) [flower]. Aerial: elevated deck casting a "
			.. "shadow, Flower visible on both sides. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("BARRY_OVER_7TH", nil, { "commodore john barry" }, { "7th" },
		-1195, 4865, 60, nil,
		"Barry approach over 7th St (county 21223/21244/21219/20300 with 22739/26638) [barry_7th]. Aerial: "
			.. "Barry lanes and markings continuous, no 7th pavement across them, so not an at-grade junction; "
			.. "7th under the Barry is inferred from the Barry being elevated over Flower 200 studs north. "
			.. "Confidence medium.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("BARRY_OVER_RIVERFRONT", nil, { "commodore john barry" }, { "chester riverfront" },
		1058, 8172, 50, nil,
		"Barry approach over Chester Riverfront (county 22418/27083) [riverfront]. Aerial: Barry deck "
			.. "shadow, Riverfront continuous beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("CROSBY_FOOTBRIDGE_OVER_I95", nil, { "crosby st pedestrian" }, { "i 95", "edgmont ave to i 95" },
		5800, -2020, 90, nil,
		"Crosby St pedestrian bridge over I-95, the Edgmont ramp and CSX (county 21308/21309/21286/21310) "
			.. "[crosby]. Aerial: continuous footbridge deck and shadow. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("I95_N476_RAMP_OVER_CSX", nil, { "i 95 to n i 476" }, { "csx phila subdivision" },
		12138, -7638, 40, nil,
		"I 95 to N I 476 over CSX (county 26688/26691 over 21158) [csx_476]. Aerial: ramp deck continuous, "
			.. "tracks pass beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("CRUM_LYNNE_OVER_CSX", nil, { "crum lynne" }, { "csx phila subdivision" },
		14420, -10378, 50, nil,
		"Crum Lynne Rd over CSX (county 21737 over 762/763) [csx_crum]. Aerial: road deck with shadow, "
			.. "tracks beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("N476_FLYOVER_OVER_I95", nil, { "i 95 to n i 476" }, { "i 95" },
		12256, -6888, 100, nil,
		"I 95 to N I 476 flyover over I-95 (county 26689/26690 over 21447/20367) [i476_flyover]. Aerial: "
			.. "curved flyover deck continuous across both carriageways. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("N476_FLYOVER_OVER_I95_TO_I476_RAMP", nil, { "i 95 to n i 476" }, { "i 95 to i 476" },
		12256, -7360, 50, nil,
		"I 95 to N I 476 flyover over the I 95 to I 476 ramp (county 26687/26691 over 26504/1177; they share "
			.. "a source vertex but do not merge) [n476_merge]. Aerial: flyover deck continuous with shadow, "
			.. "ramp passes beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("N476_FLYOVER_OVER_I476_TO_I95_RAMP", nil, { "i 95 to n i 476" }, { "i 476 to i 95" },
		12238, -6790, 45, nil,
		"I 95 to N I 476 flyover over the I 476 to I 95 ramp (county 26689 over 26686/18307) [i476_flyover]. "
			.. "Aerial: curved flyover deck continuous, ramp passes beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
	namedEntry("I95_OVER_I476_TO_I95_RAMP", nil, { "i 95" }, { "i 476 to i 95" },
		12107, -6814, 100, nil,
		"I-95 decks over the I 476 to I 95 ramp (county 855/856 over 26684/26685) [i476_flyover]. Aerial: "
			.. "light concrete I-95 decks, ramp passes beneath. Confidence high.",
		{ status = "aerial_dvrpc2025", references = { DVRPC2025 } }),
}

-- Bridge-tagged source records that are at grade on the ground (no
-- structure). RoadTerrainConformer keeps them on the terrain.
Registry.GROUNDED = {
	{
		id = "PARK_VALLEI_PHANTOM_BRIDGE",
		sources = { "county:21295", "county:21296" },
		description = "Park Vallei bridge tags inside an apartment parking lot [park_vallei]. Aerial 2025: "
			.. "flat paved lot, no structure.",
		status = "aerial_dvrpc2025",
	},
}
local groundedIndex = {}
for _, entry in ipairs(Registry.GROUNDED) do
	for _, id in ipairs(entry.sources) do
		groundedIndex[id] = entry
	end
end

-- Source records for structures that do not exist on the ground. The tile
-- data is left untouched; the builder skips these records at runtime.
Registry.SUPPRESSED = {
	{
		id = "SIXTH_PHANTOM_BRIDGE",
		sources = { "county:26640", "county:26641", "county:7819", "county:26529" },
		description = "6th Street bridge across the US 322 / Barry approach. Aerial 2025: 6th ends at the west "
			.. "barrier wall, lane markings run through, no deck; only vegetation between the highway and Flower St.",
		status = "aerial_dvrpc2025",
	},
}
local suppressedIndex = {}
for _, entry in ipairs(Registry.SUPPRESSED) do
	for _, id in ipairs(entry.sources) do
		suppressedIndex[id] = entry
	end
end

-- Shared source vertices that are genuine same-level merges / diverges, not
-- crossings, even though the arm angle exceeds the freeway-crossing split
-- threshold. HighwayProfile keeps these arms on the through road's node and
-- applies no clearance rule between the pair.
Registry.AT_GRADE = {
	{
		id = "I95_I476_RAMP_GORES",
		namesA = { "i 95" },
		namesB = { "i 95 to n i 476", "i 476 to i 95" },
		center = { 10580, -5503 },
		radius = 45,
		description = "I 95 to N I 476 diverges from I-95 (county 559 -> 26098, 36 deg) and I 476 to I 95 merges "
			.. "(854 <- 26181) on the I-95 deck over Bullens Lane. Aerial: same deck surface. Confidence high.",
		status = "aerial_dvrpc2025",
	},
	{
		id = "US322_TO_US13_AT_7TH",
		namesA = { "us 322 to us 13" },
		namesB = { "7th" },
		center = { -1157, 4840 },
		radius = 30,
		description = "US 322 to US 13 ends at a signalised junction with 7th St (aerial 2025 [flower]: "
			.. "crosswalks at the ramp terminal); the county layer-1 tag is not a structure.",
		status = "aerial_dvrpc2025",
	},
	{
		id = "MACDADE_RAMP_MERGE_I476",
		namesA = { "i 476" },
		namesB = { "macdade blvd to i 476" },
		center = { 9510, -12229 },
		radius = 25,
		description = "MacDade ramp lane (county 20452) merges into I-476 NB (65/473) at 16-18 deg. Aerial: "
			.. "auxiliary lane inside the NB carriageway, no separate structure. Confidence high.",
		status = "aerial_dvrpc2025",
	},
}

local function normName(name)
	local value = string.lower(tostring(name or ""))
	value = value:gsub("[^%w]", " ")
	value = value:gsub("%s+", " ")
	value = value:gsub("^%s+", "")
	value = value:gsub("%s+$", "")
	return value
end

local function listHas(list, value)
	for _, item in ipairs(list or {}) do
		if item == value then
			return true
		end
	end
	return false
end

-- Name/location relation: returns the entry when the road named `upper`
-- passes over the road named `lower` at (x, z).
function Registry.NamedRelation(upper, lower, x, z)
	local u, l = normName(upper), normName(lower)
	for _, entry in ipairs(Registry.NAMED) do
		local dx, dz = x - entry.center[1], z - entry.center[2]
		if dx * dx + dz * dz <= entry.radius * entry.radius
			and listHas(entry.upperNames, u) and listHas(entry.lowerNames, l) then
			return entry
		end
	end
	return nil
end

-- Returns the AT_GRADE entry when roads `a` and `b` (either order) merge or
-- diverge at the same level at (x, z).
function Registry.AtGrade(a, b, x, z)
	local na, nb = normName(a), normName(b)
	for _, entry in ipairs(Registry.AT_GRADE) do
		local dx, dz = x - entry.center[1], z - entry.center[2]
		if dx * dx + dz * dz <= entry.radius * entry.radius
			and ((listHas(entry.namesA, na) and listHas(entry.namesB, nb))
				or (listHas(entry.namesA, nb) and listHas(entry.namesB, na))) then
			return entry
		end
	end
	return nil
end

-- Index helpers -------------------------------------------------------------

local function sourcePrefix(gradeGroup)
	-- "county:425:g0" -> "county:425"
	local a, b = string.match(tostring(gradeGroup or ""), "^([^:]+):([^:]+)")
	if not a then
		return nil
	end
	return a .. ":" .. b
end
Registry.sourcePrefix = sourcePrefix

-- Returns the SUPPRESSED entry when a source record must not be built.
function Registry.Suppressed(gradeGroup)
	local prefix = sourcePrefix(gradeGroup)
	return prefix and suppressedIndex[prefix] or nil
end

function Registry.Grounded(gradeGroup)
	local prefix = sourcePrefix(gradeGroup)
	return prefix and groundedIndex[prefix] or nil
end

local upperIndex, lowerIndex = {}, {}
for _, entry in ipairs(Registry.STRUCTURES) do
	for _, id in ipairs(entry.upperSources or {}) do
		upperIndex[id] = upperIndex[id] or {}
		table.insert(upperIndex[id], entry)
	end
	for _, id in ipairs(entry.lowerSources or {}) do
		lowerIndex[id] = lowerIndex[id] or {}
		table.insert(lowerIndex[id], entry)
	end
end

-- Returns the registry entry if `upperGroup` is recorded as passing over
-- `lowerGroup`, else nil.
function Registry.Relation(upperGroup, lowerGroup)
	local u, l = sourcePrefix(upperGroup), sourcePrefix(lowerGroup)
	if not u or not l then
		return nil
	end
	for _, entry in ipairs(upperIndex[u] or {}) do
		for _, candidate in ipairs(lowerIndex[l] or {}) do
			if candidate == entry then
				return entry
			end
		end
	end
	return nil
end

function Registry.PointInFootprint(entry, x, z)
	local poly = entry and entry.footprint
	if not poly or #poly < 3 then
		return false
	end
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, zi = poly[i][1], poly[i][2]
		local xj, zj = poly[j][1], poly[j][2]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

return Registry
