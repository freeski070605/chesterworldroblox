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
local function namedEntry(id, structure, upper, lower, cx, cz, radius, clearanceM, note)
	return {
		id = id,
		description = note,
		upperNames = upper,
		lowerNames = lower,
		center = { cx, cz },
		radius = radius,
		inventoryStructure = structure,
		inventoryUnderclearanceStuds = clearanceM and clearanceM * 3 or nil,
		inventoryStatus = "published_inventory:nbi_" .. structure,
		references = {
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
		8114, -3199, 65, 5.43, "Chestnut Street over I-95 and CSX (source wrongly tags I-95 as upper)"),
	namedEntry("MELROSE_OVER_I95", "15449", { "melrose ave" }, { "i 95", "chestnut st to i 95" },
		8901, -3688, 75, 5.33, "Melrose Avenue over I-95, ramps and CSX"),
	namedEntry("HIGHLAND_OVER_I95", "14881", { "highland ave" }, { "i 95" },
		-7366, 4463, 75, nil, "Highland Avenue (relocated) over I-95 (source tags I-95 as upper)"),
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
