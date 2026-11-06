-- ChesterWorld | Highway corridor vertical profile.
--
-- OWNER of highway pavement elevation. TileBuilderV2 calls Prepare() once with
-- every tile road, before the junction graph is finalized, and then asks this
-- module for the elevation of each highway pavement piece it builds.
--
-- Why this exists: the imported terrain is a bare-earth DEM. Wherever a
-- highway is the UPPER road (I-95 over Kerlin, over Highland, over Chestnut,
-- US 322 over Front/3rd/4th...) the DEM drops into a notch where the real
-- structure was removed. A terrain-following strip dives into that notch, or
-- is deleted outright by MAX_SURFACE_GRADE, leaving a hole. Per-strip logic
-- cannot see the embankments on both sides, so this module works on whole
-- continuous strokes of highway instead:
--
--   1. chain highway segments into strokes (through merges/diverges),
--   2. sample the terrain every HIGHWAY_PROFILE_SAMPLE_STUDS,
--   3. cut narrow DEM spikes, fill narrow DEM notches (bridged dips),
--   4. interpolate across source-tagged bridge spans,
--   5. enforce underclearance over every lower road the highway crosses,
--   6. enforce a maximum grade (upper envelope), round vertical curves,
--   7. pin ramp ends to the local street level / already-solved strokes,
--   8. classify every station as "grade", "fill" or "span".
--
-- Nothing here edits Terrain, source data, spawn, or ground intersections.
-- Orientation lock: +X east, -Z north (positions arrive already in studs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Registry = require(Shared:WaitForChild("HighwayStructureRegistry"))

local HighwayProfile = {}

local function cfg(name, default)
	local value = WorldConfig[name]
	if value == nil then
		return default
	end
	return value
end

local STEP = cfg("HIGHWAY_PROFILE_SAMPLE_STUDS", 6)
local NOTCH_WINDOW = cfg("HIGHWAY_PROFILE_NOTCH_WINDOW_STUDS", 240)
local SPIKE_WINDOW = cfg("HIGHWAY_PROFILE_SPIKE_WINDOW_STUDS", 90)
local GRADE_MAIN = cfg("HIGHWAY_PROFILE_MAX_GRADE_MAINLINE", 0.07)
local GRADE_LINK = cfg("HIGHWAY_PROFILE_MAX_GRADE_LINK", 0.10)
local SMOOTH = cfg("HIGHWAY_PROFILE_SMOOTH_STUDS", 36)
local UNDER_CLEARANCE = cfg("HIGHWAY_UNDERPASS_MIN_CLEARANCE_STUDS", 14)
local OPEN_CLEARANCE = cfg("HIGHWAY_OPEN_SPAN_MIN_CLEARANCE_STUDS", 6)
local FILL_MIN = cfg("HIGHWAY_STRUCTURE_FILL_MIN_GAP_STUDS", 2)
local NOTCH_SPAN_DEPTH = cfg("HIGHWAY_STRUCTURE_NOTCH_SPAN_DEPTH_STUDS", 8)
local MIN_SPAN = cfg("HIGHWAY_STRUCTURE_MIN_SPAN_STUDS", 14)
local SIDE_MARGIN = cfg("HIGHWAY_SPAN_SIDE_MARGIN_STUDS", 10)
local ROAD_THICKNESS = cfg("ROAD_THICKNESS_STUDS", 0.45)
local DECK = cfg("HIGHWAY_DECK_THICKNESS_STUDS", 1.6)

-- Grade line G is the "ground-equivalent" height that TileBuilderV2 adds
-- ROAD_SURFACE_OFFSET to. Deck underside = G + offset - thickness/2 - deck.
-- Lower road top = Glower + offset + thickness/2. So the opening equals
-- G - Glower - (thickness + deck), and the requirement on G is:
local DECK_STACK = ROAD_THICKNESS + DECK + 0.05

-- ---------------------------------------------------------------------------
-- Corridor membership
-- ---------------------------------------------------------------------------

local HIGHWAY_CLASSES = {
	motorway = true, motorway_link = true, trunk = true, trunk_link = true,
}
local LINK_CLASSES = { motorway_link = true, trunk_link = true }
-- Exact mainline names that are corridor regardless of a (wrong) county class.
local MAINLINE_NAMES = {
	["i 95"] = true, ["i 476"] = true, ["us 322"] = true,
	["commodore john barry bridge"] = true, ["conchester"] = true,
}
-- Source records the county data mis-classes that belong to a corridor. A
-- mis-classed piece ends the stroke and pins it to the terrain as if a local
-- street joined there.
local CORRIDOR_SOURCES = {
	-- Barry approach over Flower St and on toward 6th ("residential")
	["county:21223"] = true, ["county:21244"] = true,
	["county:21219"] = true, ["county:20300"] = true,
	-- I 95 to I 476 at its merge with the N I 476 flyover ("primary")
	["county:1177"] = true,
	-- Bullens Ln deck east of I-476 over the MacDade ramp: its motorway-classed
	-- neighbours are profiled, so it stepped 11 studs down at the joint
	["county:21560"] = true,
}
-- County data assigns motorway classes to rail and pedestrian structures.
local EXCLUDE_TOKENS = { "pedestrian", "amtrak", "csx", "subdivision", "railroad", "rail" }

local function normName(name)
	local value = string.lower(tostring(name or ""))
	value = value:gsub("[^%w]", " ")
	value = value:gsub("%s+", " ")
	value = value:gsub("^%s+", "")
	value = value:gsub("%s+$", "")
	return value
end
HighwayProfile.normName = normName

local function hasRouteToken(n)
	local padded = " " .. n .. " "
	return padded:find(" i %d+ ") ~= nil
		or padded:find(" us %d+ ") ~= nil
		or padded:find(" pa %d+ ") ~= nil
		or padded:find(" barry ") ~= nil
		or padded:find(" conchester ") ~= nil
end

local function excluded(n)
	local padded = " " .. n .. " "
	for _, token in ipairs(EXCLUDE_TOKENS) do
		if padded:find(" " .. token .. " ", 1, true) then
			return true
		end
	end
	-- "Cr Chester Secondary" is a Conrail line.
	return string.sub(n, 1, 3) == "cr "
end
-- True for rail / pedestrian records the county data classes as motorways.
function HighwayProfile.IsExcludedName(name)
	return excluded(normName(name))
end

-- `level` is the V2 grade level (bridge => >=1).
function HighwayProfile.IsCorridorRoad(road, level)
	local n = normName(road.name)
	if n == "" or excluded(n) then
		return false
	end
	if MAINLINE_NAMES[n] then
		return true
	end
	local source = string.match(tostring(road.grade_group or ""), "^([^:]+:[^:]+)")
	if source and CORRIDOR_SOURCES[source] then
		return true
	end
	local cls = string.lower(tostring(road.road_class or ""))
	if not HIGHWAY_CLASSES[cls] then
		return false
	end
	-- A motorway-classed record with a purely local name that is ELEVATED is
	-- a county mislabel of a local overpass (Macdade Blvd, Bullens Ln, 2nd,
	-- 6th, Chester Pike...). Those remain RoadTerrainConformer bridges.
	if (level or 0) > 0 and not hasRouteToken(n) then
		return false
	end
	return true
end

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------

local enabled = false
local roadInfo = {} -- road table -> info
local strokes = {}
local corridorKeys = {} -- V2 endpoint key -> number of corridor arms
local overrides = {} -- road -> { [endpointIndex] = connection group }
local stats = {}

local function resetStats()
	stats = {
		corridorSegments = 0, strokes = 0, samples = 0, unprofilable = 0,
		nodes = 0, mixedNodes = 0, levelCrossNodesKept = 0,
		crossingsOver = 0, crossingsUnder = 0, crossingsRegistry = 0, crossingsAtGrade = 0,
		crossingsCorridor = 0, crossingsUnresolved = 0, crossingsDem = 0,
		crossingsLayer = 0, vertexSplits = 0, freewayCrossNodeSplits = 0,
		notchFilledStations = 0, spikeCutStations = 0, cutStationsKept = 0, bridgeTagsDropped = 0,
		bridgeTagStations = 0, maxNotchFill = 0, maxSpikeCut = 0,
		spanStations = 0, fillStations = 0, gradeStations = 0,
		spans = 0, cutStations = 0, worstCut = 0,
		gradeViolations = 0, worstGrade = 0,
		clearanceShort = 0, worstClearanceShort = 0, pins = 0, pinConflicts = 0,
		pinConflictList = {}, gradeList = {}, cutList = {},
		unresolvedList = {}, clearanceList = {}, spanList = {},
	}
end
resetStats()

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function vkey(x, z)
	return tostring(math.floor(x * 10 + 0.5)) .. ":" .. tostring(math.floor(z * 10 + 0.5))
end

local function segIntersect(ax, az, bx, bz, cx, cz, dx, dz)
	local rx, rz = bx - ax, bz - az
	local sx, sz = dx - cx, dz - cz
	local det = rx * sz - rz * sx
	if math.abs(det) < 1e-9 then
		return nil
	end
	local qx, qz = cx - ax, cz - az
	local t = (qx * sz - qz * sx) / det
	local u = (qx * rz - qz * rx) / det
	local e = 1e-6
	if t >= -e and t <= 1 + e and u >= -e and u <= 1 + e then
		local l1 = math.sqrt(rx * rx + rz * rz)
		local l2 = math.sqrt(sx * sx + sz * sz)
		return math.clamp(t, 0, 1), math.clamp(u, 0, 1), math.abs(det) / math.max(l1 * l2, 1e-9)
	end
	return nil
end

-- Sliding-window max/min over index window [i-w, i] and [i, i+w].
local function windowExtremes(values, w, useMax)
	local n = #values
	local left, right = table.create(n), table.create(n)
	local better = useMax and math.max or math.min
	for i = 1, n do
		local best = values[i]
		for j = math.max(1, i - w), i - 1 do
			best = better(best, values[j])
		end
		left[i] = best
		best = values[i]
		for j = i + 1, math.min(n, i + w) do
			best = better(best, values[j])
		end
		right[i] = best
	end
	return left, right
end

-- ---------------------------------------------------------------------------
-- Prepare
-- ---------------------------------------------------------------------------
-- entries: array of { road = <tile road table>, tileId = string }
-- opts:
--   sourceToStuds(xm, zm) -> x, z
--   terrainY(x, z) -> y or nil
--   gradeLevel(road) -> integer
--   endpointKey(road, endpointIndex) -> V2 graph key

function HighwayProfile.Prepare(entries, opts)
	roadInfo, strokes, corridorKeys, overrides = {}, {}, {}, {}
	resetStats()
	enabled = WorldConfig.HIGHWAY_PROFILE_ENABLED == true
	if not enabled then
		return
	end
	local toStuds = opts.sourceToStuds
	local terrainY = opts.terrainY
	local gradeLevel = opts.gradeLevel
	local endpointKey = opts.endpointKey
	local yield = opts.yield or function() end

	-- 1. Corridor segments and a spatial grid of every road.
	local segs = {}
	local all = {}
	local otherArmsAtKey = {}
	local GRID = 80
	local grid = {}
	local function gridAdd(item)
		for gx = math.floor(math.min(item.ax, item.bx) / GRID), math.floor(math.max(item.ax, item.bx) / GRID) do
			for gz = math.floor(math.min(item.az, item.bz) / GRID), math.floor(math.max(item.az, item.bz) / GRID) do
				local k = gx .. ":" .. gz
				local bucket = grid[k]
				if not bucket then
					bucket = {}
					grid[k] = bucket
				end
				table.insert(bucket, item)
			end
		end
	end

	for index, entry in ipairs(entries) do
		local road = entry.road
		local ax, az = toStuds(road.x1, road.z1)
		local bx, bz = toStuds(road.x2, road.z2)
		local level = gradeLevel(road)
		local item = {
			road = road, tileId = entry.tileId,
			ax = ax, az = az, bx = bx, bz = bz,
			len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2),
			level = level,
			k1 = endpointKey(road, 1), k2 = endpointKey(road, 2),
			width = math.max((tonumber(road.width_m) or 7) * 3, 3),
			group = tostring(road.grade_group or ""),
			nameKey = normName(road.name),
		}
		item.corridor = item.len > 0.05 and HighwayProfile.IsCorridorRoad(road, level)
		table.insert(all, item)
		gridAdd(item)
		if item.corridor then
			table.insert(segs, item)
			corridorKeys[item.k1] = (corridorKeys[item.k1] or 0) + 1
			corridorKeys[item.k2] = (corridorKeys[item.k2] or 0) + 1
		elseif not excluded(item.nameKey) then
			-- (a rail line or footpath sharing a vertex with a freeway is a
			-- grade separation, never an at-grade junction to pin to: the
			-- Conrail track under the Barry approach pinned it to the ground)
			otherArmsAtKey[item.k1] = (otherArmsAtKey[item.k1] or 0) + 1
			otherArmsAtKey[item.k2] = (otherArmsAtKey[item.k2] or 0) + 1
		end
		if index % 2000 == 0 then
			yield()
		end
	end
	stats.corridorSegments = #segs

	-- 2. Profile nodes. Arms meeting at one physical vertex are one node unless
	-- two different grade levels each carry a through road (a crossing).
	local vertexArms = {}
	for _, seg in ipairs(segs) do
		seg.vk = { vkey(seg.ax, seg.az), vkey(seg.bx, seg.bz) }
		for e = 1, 2 do
			local k = seg.vk[e]
			vertexArms[k] = vertexArms[k] or {}
			table.insert(vertexArms[k], { seg = seg, e = e })
		end
	end
	local nodes = {}
	for vk, arms in pairs(vertexArms) do
		local byLevel, levels = {}, 0
		for _, arm in ipairs(arms) do
			local l = arm.seg.level
			if not byLevel[l] then
				byLevel[l] = {}
				levels += 1
			end
			table.insert(byLevel[l], arm)
		end
		local through = 0
		for _, list in pairs(byLevel) do
			if #list >= 2 then
				through += 1
			end
		end
		local groups = {}
		if levels > 1 and through >= 2 then
			stats.levelCrossNodesKept += 1
			for l, list in pairs(byLevel) do
				table.insert(groups, { key = vk .. ":L" .. l, arms = list })
			end
		else
			table.insert(groups, { key = vk, arms = arms })
		end
		for _, group in ipairs(groups) do
			local first = group.arms[1]
			local x = first.e == 1 and first.seg.ax or first.seg.bx
			local z = first.e == 1 and first.seg.az or first.seg.bz
			local node = { id = group.key, x = x, z = z, arms = group.arms, mixed = false, height = nil }
			for _, arm in ipairs(group.arms) do
				arm.node = node
				arm.seg.nodes = arm.seg.nodes or {}
				arm.seg.nodes[arm.e] = node
				arm.seg.arms = arm.seg.arms or {}
				arm.seg.arms[arm.e] = arm
				local ox = arm.e == 1 and arm.seg.bx or arm.seg.ax
				local oz = arm.e == 1 and arm.seg.bz or arm.seg.az
				local dx, dz = ox - x, oz - z
				local len = math.sqrt(dx * dx + dz * dz)
				arm.dx, arm.dz = dx / len, dz / len
				local key = arm.e == 1 and arm.seg.k1 or arm.seg.k2
				if (otherArmsAtKey[key] or 0) > 0 then
					node.mixed = true
				end
			end
			stats.nodes += 1
			if node.mixed then
				stats.mixedNodes += 1
			end
			table.insert(nodes, node)
		end
	end

	-- 3. Pair arms into through-movements (straightest continuation first).
	for _, node in ipairs(nodes) do
		local arms = node.arms
		if #arms == 2 then
			arms[1].pair, arms[2].pair = arms[2], arms[1]
		elseif #arms >= 3 then
			local candidates = {}
			for i = 1, #arms do
				for j = i + 1, #arms do
					local a, b = arms[i], arms[j]
					local dot = a.dx * b.dx + a.dz * b.dz
					if dot < -0.6 then
						local score = -dot
						if normName(a.seg.road.name) == normName(b.seg.road.name) then
							score += 0.25
						end
						if LINK_CLASSES[string.lower(tostring(a.seg.road.road_class))]
							== LINK_CLASSES[string.lower(tostring(b.seg.road.road_class))] then
							score += 0.1
						end
						score += math.min(a.seg.width, b.seg.width) / 400
						table.insert(candidates, { a = a, b = b, score = score })
					end
				end
			end
			table.sort(candidates, function(p, q)
				return p.score > q.score
			end)
			for _, c in ipairs(candidates) do
				if not c.a.pair and not c.b.pair then
					c.a.pair, c.b.pair = c.b, c.a
				end
			end
		end
	end

	-- 3b. Freeways have no at-grade junctions, and ramps merge at shallow
	-- angles. Another corridor road meeting a freeway through-movement at a
	-- shared vertex at >= 30 degrees is a crossing the county data encodes as
	-- a shared vertex (I 95 to Comm Barry and Conchester over/under both I-95
	-- carriageways, Bullens Ln at I-476). Detach it into its own node so the
	-- two roads get independent heights, and let step 6 resolve the crossing.
	local forcedCross = {}
	local function isFreewayName(nk)
		return nk == "i 95" or nk == "i 476" or nk == "commodore john barry bridge"
	end
	-- The registry can also name a crossing at a shared vertex of two
	-- non-freeway roads (I 95 From Exit 4 over Conchester); there only the
	-- named lower/upper road is detached. Registry AT_GRADE gores stay joined.
	local function registryCrosses(a, b, x, z)
		return Registry.NamedRelation(a.seg.road.name, b.seg.road.name, x, z) ~= nil
			or Registry.NamedRelation(b.seg.road.name, a.seg.road.name, x, z) ~= nil
	end
	local splitNodes = {}
	for _, node in ipairs(nodes) do
		local through = nil
		for _, arm in ipairs(node.arms) do
			if arm.pair and isFreewayName(arm.seg.nameKey) and isFreewayName(arm.pair.seg.nameKey) then
				through = arm
				break
			end
		end
		local namedOnly = false
		if not through then
			for _, arm in ipairs(node.arms) do
				if arm.pair then
					for _, other in ipairs(node.arms) do
						if other.seg.nameKey ~= arm.seg.nameKey and registryCrosses(arm, other, node.x, node.z) then
							through, namedOnly = arm, true
							break
						end
					end
				end
				if through then
					break
				end
			end
		end
		if through and #node.arms >= 3 then
			local fx, fz = through.dx - through.pair.dx, through.dz - through.pair.dz
			local fl = math.sqrt(fx * fx + fz * fz)
			local keep, detached = {}, {}
			for _, arm in ipairs(node.arms) do
				local sine = 0
				if fl > 1e-6 then
					sine = math.abs(arm.dx * fz - arm.dz * fx) / fl
				end
				local partnerSine = 0
				if arm.pair and fl > 1e-6 then
					partnerSine = math.abs(arm.pair.dx * fz - arm.pair.dz * fx) / fl
				end
				local eligible = arm ~= through and arm ~= through.pair
					and not Registry.AtGrade(through.seg.road.name, arm.seg.road.name, node.x, node.z)
					and (not namedOnly or registryCrosses(through, arm, node.x, node.z))
				if eligible and math.max(sine, partnerSine) > 0.5 then
					table.insert(detached, arm)
				else
					table.insert(keep, arm)
				end
			end
			if #detached > 0 then
				node.arms = keep
				local new = { id = node.id .. ":X", x = node.x, z = node.z, arms = detached, mixed = false, height = nil }
				for _, arm in ipairs(detached) do
					arm.node = new
					arm.seg.nodes[arm.e] = new
					for _, other in ipairs(keep) do
						forcedCross[arm.seg] = forcedCross[arm.seg] or {}
						forcedCross[other.seg] = forcedCross[other.seg] or {}
						forcedCross[arm.seg][other.seg] = true
						forcedCross[other.seg][arm.seg] = true
					end
				end
				table.insert(splitNodes, new)
				stats.freewayCrossNodeSplits += 1
			end
		end
	end
	for _, node in ipairs(splitNodes) do
		table.insert(nodes, node)
	end

	-- 4. Strokes.
	local used = {}
	local function walk(seg, exitEnd)
		local list = {}
		local cur, e = seg, exitEnd
		while true do
			local arm = cur.arms[e]
			local partner = arm and arm.pair
			if not partner or used[partner.seg] then
				break
			end
			local nxt = partner.seg
			used[nxt] = true
			table.insert(list, { seg = nxt, enter = partner.e })
			cur, e = nxt, 3 - partner.e
		end
		return list
	end
	for _, seg in ipairs(segs) do
		if not used[seg] then
			used[seg] = true
			local back = walk(seg, 1)
			local fwd = walk(seg, 2)
			local ordered = {}
			for i = #back, 1, -1 do
				table.insert(ordered, { seg = back[i].seg, flip = back[i].enter == 1 })
			end
			table.insert(ordered, { seg = seg, flip = false })
			for _, item in ipairs(fwd) do
				table.insert(ordered, { seg = item.seg, flip = item.enter == 2 })
			end
			table.insert(strokes, { id = "HW" .. tostring(#strokes + 1), parts = ordered })
		end
	end
	stats.strokes = #strokes

	-- 5. Stroke geometry, rank and sampling positions.
	for _, stroke in ipairs(strokes) do
		local px, pz, ps = {}, {}, {}
		local s = 0
		local isLink, maxWidth, mainline, freeway = true, 0, false, false
		for index, part in ipairs(stroke.parts) do
			local seg = part.seg
			local x0, z0, x1, z1
			if part.flip then
				x0, z0, x1, z1 = seg.bx, seg.bz, seg.ax, seg.az
			else
				x0, z0, x1, z1 = seg.ax, seg.az, seg.bx, seg.bz
			end
			if index == 1 then
				table.insert(px, x0)
				table.insert(pz, z0)
				table.insert(ps, 0)
			end
			part.s0 = s
			s += seg.len
			part.s1 = s
			table.insert(px, x1)
			table.insert(pz, z1)
			table.insert(ps, s)
			-- station at the source road's own (x1,z1) and (x2,z2)
			local sA = part.flip and part.s1 or part.s0
			local sB = part.flip and part.s0 or part.s1
			local cls = string.lower(tostring(seg.road.road_class or ""))
			if not LINK_CLASSES[cls] then
				isLink = false
			end
			if MAINLINE_NAMES[normName(seg.road.name)] then
				mainline = true
			end
			local nk = seg.nameKey
			if nk == "i 95" or nk == "i 476" or nk == "commodore john barry bridge" then
				freeway = true
			end
			maxWidth = math.max(maxWidth, seg.width)
			seg.stroke = stroke
			seg.part = part
			roadInfo[seg.road] = { stroke = stroke, seg = seg, part = part, sA = sA, sB = sB }
		end
		stroke.px, stroke.pz, stroke.ps = px, pz, ps
		stroke.length = s
		-- A stroke is MAINLINE only if it carries a mainline route name. County
		-- classes are unreliable ("Edgmont Ave to I 95" is "motorway"), so
		-- named connectors ("X to Y") get ramp grades even when classed
		-- motorway. Only I-95 / I-476 / the Barry Bridge are access-controlled
		-- freeways for the vertex-split rule.
		stroke.isLink = not mainline
		stroke.freeway = freeway
		stroke.grade = stroke.isLink and GRADE_LINK or GRADE_MAIN
		stroke.rank = (mainline and 0 or (stroke.isLink and 2 or 1))
		stroke.width = maxWidth
		-- joint bends: extension needed at each interior vertex to close the
		-- outer wedge between two rectangular pieces of the same stroke.
		for index, part in ipairs(stroke.parts) do
			local function dir(p)
				local seg = p.seg
				local dx, dz = seg.bx - seg.ax, seg.bz - seg.az
				if p.flip then
					dx, dz = -dx, -dz
				end
				return dx / seg.len, dz / seg.len
			end
			local dx, dz = dir(part)
			local function ext(other)
				local ox, oz = dir(other)
				local cosine = math.clamp(dx * ox + dz * oz, -1, 1)
				local bend = math.acos(cosine)
				if bend > math.rad(60) then
					return 0.1
				end
				return math.min(part.seg.width / 2 * math.tan(bend / 2), 8) + 0.1
			end
			local startExt = index > 1 and ext(stroke.parts[index - 1]) or 0
			local endExt = index < #stroke.parts and ext(stroke.parts[index + 1]) or 0
			-- convert to the source road's own end numbering
			local info = roadInfo[part.seg.road]
			if part.flip then
				info.ext1, info.ext2 = endExt, startExt
			else
				info.ext1, info.ext2 = startExt, endExt
			end
		end
	end
	yield()

	-- 5b. A freeway mainline has no at-grade junctions. Where a non-corridor
	-- road shares a source vertex with the INTERIOR of a freeway stroke, the
	-- county data is encoding a crossing (Kerlin, Edgmont...). Give that
	-- road end its own connection group so TileBuilderV2 does not pave a
	-- terrain-level junction pad across the freeway; the vertical relation
	-- is resolved with the other crossings below.
	local otherByVertex = {}
	for _, item in ipairs(all) do
		if not item.corridor then
			for e = 1, 2 do
				local k = e == 1 and vkey(item.ax, item.az) or vkey(item.bx, item.bz)
				otherByVertex[k] = otherByVertex[k] or {}
				table.insert(otherByVertex[k], { item = item, e = e })
			end
		end
	end
	-- every vertex where at least two freeway-stroke arms meet (inside a
	-- stroke OR where two freeway strokes join at a merge/diverge)
	local freewayVertices = {}
	for _, node in ipairs(nodes) do
		local freewayArms = 0
		for _, arm in ipairs(node.arms) do
			if arm.seg.stroke and arm.seg.stroke.freeway then
				freewayArms += 1
			end
		end
		if freewayArms >= 2 then
			freewayVertices[vkey(node.x, node.z)] = true
		end
	end
	-- Rail lines and pedestrian structures never meet ANY corridor road at
	-- grade either (I 476 to I 95 shares a vertex with CSX Phila Subdivision),
	-- nor does a road the structure registry names as crossing a corridor road
	-- at that vertex (2nd Street under the Barry approach).
	local function registryCrossing(vertex, ref)
		local x = ref.e == 1 and ref.item.ax or ref.item.bx
		local z = ref.e == 1 and ref.item.az or ref.item.bz
		for _, arm in ipairs(vertexArms[vertex]) do
			local a, b = arm.seg.road.name, ref.item.road.name
			if Registry.NamedRelation(a, b, x, z) or Registry.NamedRelation(b, a, x, z) then
				return true
			end
		end
		return false
	end
	for vertex in pairs(vertexArms) do
		for _, ref in ipairs(otherByVertex[vertex] or {}) do
			if freewayVertices[vertex] or excluded(ref.item.nameKey) or registryCrossing(vertex, ref) then
				local road = ref.item.road
				local explicit = ref.e == 1 and road.node1_connection_group or road.node2_connection_group
				overrides[road] = overrides[road] or {}
				if not explicit and not overrides[road][ref.e] then
					overrides[road][ref.e] = "HWX"
					local oldKey = ref.e == 1 and ref.item.k1 or ref.item.k2
					otherArmsAtKey[oldKey] = (otherArmsAtKey[oldKey] or 1) - 1
					local newKey = endpointKey(road, ref.e)
					if ref.e == 1 then
						ref.item.k1 = newKey
					else
						ref.item.k2 = newKey
					end
					otherArmsAtKey[newKey] = (otherArmsAtKey[newKey] or 0) + 1
					stats.vertexSplits += 1
				end
			end
		end
	end
	stats.mixedNodes = 0
	for _, node in ipairs(nodes) do
		node.mixed = false
		for _, arm in ipairs(node.arms) do
			local key = arm.e == 1 and arm.seg.k1 or arm.seg.k2
			if (otherArmsAtKey[key] or 0) > 0 then
				node.mixed = true
			end
		end
		if node.mixed then
			stats.mixedNodes += 1
		end
	end

	-- 6. Crossings: every place a corridor segment crosses another road in
	-- plan WITHOUT sharing an at-grade graph node with it.
	local crossingsBySeg = {}
	local seen = {}
	for _, seg in ipairs(segs) do
		local visited = {}
		for gx = math.floor(math.min(seg.ax, seg.bx) / GRID), math.floor(math.max(seg.ax, seg.bx) / GRID) do
			for gz = math.floor(math.min(seg.az, seg.bz) / GRID), math.floor(math.max(seg.az, seg.bz) / GRID) do
				for _, other in ipairs(grid[gx .. ":" .. gz] or {}) do
					if other ~= seg and not visited[other] then
						visited[other] = true
						local forced = forcedCross[seg] ~= nil and forcedCross[seg][other] == true
						local sharesNode = not forced and (other.k1 == seg.k1 or other.k1 == seg.k2
							or other.k2 == seg.k1 or other.k2 == seg.k2)
						-- Collinear continuation across levels (bridge end) is not
						-- a crossing either.
						if not sharesNode and other.len > 0.05 then
							local t, u, sine = segIntersect(seg.ax, seg.az, seg.bx, seg.bz,
								other.ax, other.az, other.bx, other.bz)
							local x, z
							if t then
								x = seg.ax + (seg.bx - seg.ax) * t
								z = seg.az + (seg.bz - seg.az) * t
							end
							-- Vertex-to-vertex contact where the other road joins
							-- this corridor AT GRADE through a sibling arm (a ramp
							-- terminal at a bridge end) is a junction, not a
							-- crossing.
							-- A pair the registry names as crossing here stays a crossing
							-- (I-476 ramps meeting I-95 on separate level nodes).
							if t and not forced and (t < 1e-4 or t > 1 - 1e-4) and (u < 1e-4 or u > 1 - 1e-4)
								and not Registry.NamedRelation(seg.road.name, other.road.name, x, z)
								and not Registry.NamedRelation(other.road.name, seg.road.name, x, z) then
								for _, arm in ipairs(vertexArms[vkey(x, z)] or {}) do
									local armKey = arm.e == 1 and arm.seg.k1 or arm.seg.k2
									if armKey == other.k1 or armKey == other.k2 then
										t = nil
										break
									end
								end
							end
							if t and sine > 0.26 then
								local pairKey = (tostring(seg) < tostring(other)) and (tostring(seg) .. tostring(other))
									or (tostring(other) .. tostring(seg))
								local dedupe = pairKey .. math.floor(x / 4) .. ":" .. math.floor(z / 4)
								if not seen[dedupe] then
									seen[dedupe] = true
									-- The vertical relation is decided once per crossing
									-- (shared with the mirror entry) when the first of the
									-- two strokes is solved.
									local shared = { decided = false }
									local c = {
										seg = seg, other = other, t = t, u = u, sine = sine,
										x = x, z = z, shared = shared,
									}
									crossingsBySeg[seg] = crossingsBySeg[seg] or {}
									table.insert(crossingsBySeg[seg], c)
									if other.corridor then
										local mirror = {
											seg = other, other = seg, t = u, u = t, sine = sine,
											x = x, z = z, shared = shared,
										}
										crossingsBySeg[other] = crossingsBySeg[other] or {}
										table.insert(crossingsBySeg[other], mirror)
										stats.crossingsCorridor += 1
									end
								end
							end
						end
					end
				end
			end
		end
	end
	yield()

	-- 6b. Crossing relation evidence.
	-- Bare-earth DEM: a road whose terrain profile has a notch AT the
	-- crossing is the upper road (its structure was removed from the DEM and
	-- the other road runs through the gap). Measured with the same bilateral
	-- rim test as the profile notch fill, along each road's own direction.
	local function demNotch(item, x, z)
		local dx, dz = (item.bx - item.ax) / item.len, (item.bz - item.az) / item.len
		local center = terrainY(x, z)
		if not center then
			return 0
		end
		local reach = math.floor(NOTCH_WINDOW / STEP)
		local left, right = -math.huge, -math.huge
		for k = 1, reach do
			local yl = terrainY(x - dx * k * STEP, z - dz * k * STEP)
			local yr = terrainY(x + dx * k * STEP, z + dz * k * STEP)
			if yl and yl > left then
				left = yl
			end
			if yr and yr > right then
				right = yr
			end
		end
		local rim = math.min(left, right)
		return math.max(0, rim - center), rim
	end
	-- Range of source grade levels of same-name segments near a point.
	local function levelsNear(item, x, z, radius)
		local lo, hi = item.level, item.level
		for gx = math.floor((x - radius) / GRID), math.floor((x + radius) / GRID) do
			for gz = math.floor((z - radius) / GRID), math.floor((z + radius) / GRID) do
				for _, o in ipairs(grid[gx .. ":" .. gz] or {}) do
					if o.nameKey == item.nameKey and o.len > 0.05 then
						local ux, uz = o.bx - o.ax, o.bz - o.az
						local f = math.clamp(((x - o.ax) * ux + (z - o.az) * uz) / (o.len * o.len), 0, 1)
						local px, pz = o.ax + ux * f, o.az + uz * f
						if (px - x) ^ 2 + (pz - z) ^ 2 <= radius * radius then
							lo = math.min(lo, o.level)
							hi = math.max(hi, o.level)
						end
					end
				end
			end
		end
		return lo, hi
	end
	local unresolvedSeen = {}
	local function decide(cross)
		local shared = cross.shared
		if shared.decided then
			return
		end
		shared.decided = true
		local seg, other, x, z = cross.seg, cross.other, cross.x, cross.z
		local function set(upper, basis, entry)
			shared.upper, shared.basis, shared.entry = upper, basis, entry
		end
		-- a registry merge/diverge gore: same level, no clearance rule
		local gore = Registry.AtGrade(seg.road.name, other.road.name, x, z)
		if gore then
			shared.basis, shared.entry = "at_grade", gore
			stats.crossingsAtGrade += 1
			return
		end
		local e = Registry.Relation(seg.group, other.group)
		if e then
			set(seg, "registry", e)
		else
			e = Registry.Relation(other.group, seg.group)
			if e then
				set(other, "registry", e)
			elseif Registry.NamedRelation then
				e = Registry.NamedRelation(seg.road.name, other.road.name, x, z)
				if e then
					set(seg, "registry", e)
				else
					e = Registry.NamedRelation(other.road.name, seg.road.name, x, z)
					if e then
						set(other, "registry", e)
					end
				end
			end
		end
		do
			-- rim (street level at the structure) of each road, for clearance caps
			local _, mineRim = demNotch(seg, x, z)
			local _, otherRim = demNotch(other, x, z)
			shared.rims = { [seg] = mineRim, [other] = otherRim }
		end
		if not shared.basis then
			local mine, theirs = demNotch(seg, x, z), demNotch(other, x, z)
			shared.notches = string.format("%.1f/%.1f", mine, theirs)
			if mine > 6 and theirs < 3 then
				set(seg, "dem")
			elseif theirs > 6 and mine < 3 then
				set(other, "dem")
			else
				local _, segHi = levelsNear(seg, x, z, 40)
				local _, otherHi = levelsNear(other, x, z, 40)
				if segHi > 0 and otherHi <= 0 then
					set(seg, "layer")
				elseif otherHi > 0 and segHi <= 0 then
					set(other, "layer")
				end
			end
		end
		if shared.basis == "registry" then
			stats.crossingsRegistry += 1
		elseif shared.basis == "dem" then
			stats.crossingsDem += 1
		elseif shared.basis == "layer" then
			stats.crossingsLayer += 1
		else
			stats.crossingsUnresolved += 1
			-- one line per physical crossing (both carriageway records and
			-- the mirrored entry share a location)
			local key = string.format("%s|%s|%d|%d", seg.nameKey, other.nameKey, math.floor(x / 20), math.floor(z / 20))
			if not unresolvedSeen[key] and #stats.unresolvedList < 40 then
				unresolvedSeen[key] = true
				table.insert(stats.unresolvedList, string.format("%s x %s at (%.1f, %.1f) notches=%s",
					tostring(seg.road.name), tostring(other.road.name), x, z, tostring(shared.notches)))
			end
		end
		if shared.upper then
			stats.crossingsOver += 1
		end
	end
	local function relationOf(cross)
		local upper = cross.shared.upper
		if not upper then
			return "unresolved"
		end
		return upper == cross.seg and "over" or "under"
	end
	HighwayProfile._decide = decide

	-- 7. Solve strokes: mainline first, then other highway, then links.
	local order = table.clone(strokes)
	table.sort(order, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.length > b.length
	end)

	local function stationOf(seg, t)
		local info = roadInfo[seg.road]
		return info.sA + (info.sB - info.sA) * t
	end

	local function positionAt(stroke, s)
		local ps = stroke.ps
		local lo, hi = 1, #ps
		while hi - lo > 1 do
			local mid = (lo + hi) // 2
			if ps[mid] <= s then
				lo = mid
			else
				hi = mid
			end
		end
		local span = ps[hi] - ps[lo]
		local f = span > 1e-6 and math.clamp((s - ps[lo]) / span, 0, 1) or 0
		local x = lerp(stroke.px[lo], stroke.px[hi], f)
		local z = lerp(stroke.pz[lo], stroke.pz[hi], f)
		local dx, dz = stroke.px[hi] - stroke.px[lo], stroke.pz[hi] - stroke.pz[lo]
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-6 then
			dx, dz, len = 1, 0, 1
		end
		return x, z, dx / len, dz / len
	end

	local function profileG(stroke, s)
		local G = stroke.G
		local n = #G
		if n == 1 then
			return G[1]
		end
		local f = math.clamp(s / stroke.ds, 0, n - 1)
		local i = math.min(math.floor(f), n - 2)
		return lerp(G[i + 1], G[i + 2], f - i)
	end
	HighwayProfile._profileG = profileG

	for orderIndex, stroke in ipairs(order) do
		local n = math.max(1, math.ceil(stroke.length / STEP))
		local ds = stroke.length / n
		stroke.ds = ds
		local count = n + 1
		local t, tl = table.create(count), table.create(count)
		local xs, zs = table.create(count), table.create(count)
		local bridgeMask = table.create(count, false)
		local known = 0
		local halfWidth = stroke.width * 0.42
		local partIndex = 1
		for i = 1, count do
			local s = (i - 1) * ds
			local x, z, dx, dz = positionAt(stroke, s)
			xs[i], zs[i] = x, z
			local y = terrainY(x, z)
			t[i] = y
			if y then
				known += 1
				local yl = terrainY(x - dz * halfWidth, z + dx * halfWidth)
				local yr = terrainY(x + dz * halfWidth, z - dx * halfWidth)
				tl[i] = math.max(y, yl or y, yr or y)
			end
			while partIndex < #stroke.parts and stroke.parts[partIndex].s1 < s do
				partIndex += 1
			end
			bridgeMask[i] = stroke.parts[partIndex].seg.level > 0
		end
		stats.samples += count
		if known == 0 then
			stroke.unprofilable = true
			stats.unprofilable += 1
			stroke.G = nil
		else
			-- fill missing samples by interpolation / nearest
			local lastKnown = nil
			for i = 1, count do
				if t[i] then
					if lastKnown and lastKnown < i - 1 then
						for j = lastKnown + 1, i - 1 do
							t[j] = lerp(t[lastKnown], t[i], (j - lastKnown) / (i - lastKnown))
						end
					elseif not lastKnown and i > 1 then
						for j = 1, i - 1 do
							t[j] = t[i]
						end
					end
					lastKnown = i
				end
			end
			for j = (lastKnown or count) + 1, count do
				t[j] = t[lastKnown]
			end
			for i = 1, count do
				tl[i] = tl[i] or t[i]
			end

			-- a. cut narrow spikes (DEM artifacts / retained decks)
			local spikeW = math.max(1, math.floor(SPIKE_WINDOW / ds + 0.5))
			local minL, minR = windowExtremes(t, spikeW, false)
			local c = table.create(count)
			for i = 1, count do
				local cut = math.min(t[i], math.max(minL[i], minR[i]))
				c[i] = cut
				if t[i] - cut > 1 then
					stats.spikeCutStations += 1
					stats.maxSpikeCut = math.max(stats.maxSpikeCut, t[i] - cut)
				end
			end

			-- b. fill narrow notches (bridged dips)
			local notchW = math.max(1, math.floor(NOTCH_WINDOW / ds + 0.5))
			local maxL, maxR = windowExtremes(c, notchW, true)
			local f = table.create(count)
			for i = 1, count do
				f[i] = math.max(c[i], math.min(maxL[i], maxR[i]))
			end

			-- b2. Where a LOCAL road passes over this highway, the highway is in
			-- a cut under the overpass. Neither a bridge tag on the highway
			-- (county data tags both roads level 1 at Edgmont, Chestnut...) nor
			-- the dip around the crossing may lift it: the cap in step d only
			-- covers the crossing width and leaves a kink at its edge.
			for _, part in ipairs(stroke.parts) do
				for _, cross in ipairs(crossingsBySeg[part.seg] or {}) do
					decide(cross)
					if relationOf(cross) == "under" and not cross.other.corridor then
						local k0 = math.clamp(math.floor(stationOf(part.seg, cross.t) / ds + 0.5) + 1, 1, count)
						local reach = math.ceil((cross.other.width / 2 + SIDE_MARGIN) / math.max(cross.sine, 0.35) / ds)
						for k = math.max(1, k0 - reach), math.min(count, k0 + reach) do
							if bridgeMask[k] then
								local lo, hi = k, k
								while lo > 1 and bridgeMask[lo - 1] do
									lo -= 1
								end
								while hi < count and bridgeMask[hi + 1] do
									hi += 1
								end
								for m = lo, hi do
									bridgeMask[m] = false
									stats.bridgeTagsDropped += 1
								end
							end
						end
						if f[k0] - c[k0] > 1 then
							local lo, hi = k0, k0
							while lo > 1 and f[lo - 1] - c[lo - 1] > 0.5 do
								lo -= 1
							end
							while hi < count and f[hi + 1] - c[hi + 1] > 0.5 do
								hi += 1
							end
							for k = lo, hi do
								if f[k] > c[k] then
									f[k] = c[k]
									stats.cutStationsKept += 1
								end
							end
						end
					end
				end
			end

			-- c. source-tagged bridge runs: interpolate between rims with no
			-- window limit (long spans over water / rail yards).
			local i = 1
			while i <= count do
				if bridgeMask[i] then
					local j = i
					while j < count and bridgeMask[j + 1] do
						j += 1
					end
					local rimL = i > 1 and f[i - 1] or nil
					local rimR = j < count and f[j + 1] or nil
					rimL = rimL or rimR or f[i]
					rimR = rimR or rimL
					for k = i, j do
						local w = (j > i) and (k - i) / (j - i) or 0.5
						f[k] = math.max(f[k], lerp(rimL, rimR, w), t[k] + OPEN_CLEARANCE + DECK_STACK)
						stats.bridgeTagStations += 1
					end
					i = j + 1
				else
					i += 1
				end
			end

			-- d. crossings: minimum (and maximum) constraints
			local minReq = table.create(count, -math.huge)
			local maxReq = table.create(count, math.huge)
			stroke.crossings = {}
			for _, part in ipairs(stroke.parts) do
				for _, cross in ipairs(crossingsBySeg[part.seg] or {}) do
					local s = stationOf(part.seg, cross.t)
					cross.station = s
					decide(cross)
					local other = cross.other
					cross.relation = relationOf(cross)
					cross.entry = cross.shared.entry
					cross.basis = cross.shared.basis
					table.insert(stroke.crossings, cross)
					local lowerG
					if cross.relation == "over" then
						if other.corridor and other.stroke and other.stroke.G then
							local oi = roadInfo[other.road]
							lowerG = profileG(other.stroke, oi.sA + (oi.sB - oi.sA) * cross.u)
						else
							lowerG = terrainY(cross.x, cross.z) or t[math.clamp(math.floor(s / ds + 0.5) + 1, 1, count)]
						end
						local clearance = UNDER_CLEARANCE
						if cross.entry and cross.entry.inventoryUnderclearanceStuds then
							clearance = math.max(clearance, cross.entry.inventoryUnderclearanceStuds)
						end
						cross.lowerG = lowerG
						cross.clearance = clearance
						local need = lowerG + clearance + DECK_STACK
						local half = (other.width / 2 + SIDE_MARGIN) / math.max(cross.sine, 0.35)
						cross.half = half
						for k = math.max(1, math.floor((s - half) / ds) + 1), math.min(count, math.ceil((s + half) / ds) + 1) do
							minReq[k] = math.max(minReq[k], need)
						end
					elseif cross.relation == "under" and (not other.corridor
						or (cross.basis == "registry" and not (other.stroke and other.stroke.G))) then
						-- A local street (or a registry-confirmed highway not solved
						-- yet: the I 476 to I 95 ramp in its real DEM cut under the
						-- I-95 embankment) passes OVER the highway here. Never let a
						-- notch fill raise the highway into that structure: cap it
						-- at (street rim - clearance). A registry-confirmed overpass
						-- keeps its street at grade and the highway drops into a cut
						-- (HighwayInfrastructure clears the terrain); weaker evidence
						-- never goes below the terrain.
						local rim = cross.shared.rims and cross.shared.rims[other]
						if rim and rim > -math.huge then
							local clearance = UNDER_CLEARANCE
							if cross.entry and cross.entry.inventoryUnderclearanceStuds then
								clearance = math.max(clearance, cross.entry.inventoryUnderclearanceStuds)
							end
							local cap = rim - clearance - DECK_STACK
							local half = (other.width / 2 + SIDE_MARGIN) / math.max(cross.sine, 0.35)
							-- only under a local street: an upper highway rises instead
							local cutAllowed = cross.basis == "registry" and not other.corridor
							for k = math.max(1, math.floor((s - half) / ds) + 1), math.min(count, math.ceil((s + half) / ds) + 1) do
								maxReq[k] = math.min(maxReq[k], cutAllowed and cap or math.max(cap, t[k]))
							end
						end
					elseif cross.relation == "under" and other.corridor and other.stroke and other.stroke.G then
						local oi = roadInfo[other.road]
						local upperG = profileG(other.stroke, oi.sA + (oi.sB - oi.sA) * cross.u)
						local cap = upperG - UNDER_CLEARANCE - DECK_STACK
						local half = (other.width / 2 + SIDE_MARGIN) / math.max(cross.sine, 0.35)
						for k = math.max(1, math.floor((s - half) / ds) + 1), math.min(count, math.ceil((s + half) / ds) + 1) do
							maxReq[k] = math.min(maxReq[k], cap)
						end
					end
				end
			end
			-- d2. design grade lines (Registry.DESIGN_PROFILES): long viaducts
			-- the DEM and the county tags cannot describe are held at their
			-- designed height (minimum and maximum) where this stroke runs
			-- along them.
			local designMask = table.create(count, false)
			do
				local partAt = 1
				for k = 1, count do
					local s = (k - 1) * ds
					while partAt < #stroke.parts and stroke.parts[partAt].s1 < s do
						partAt += 1
					end
					local roadName = normName(stroke.parts[partAt].seg.road.name)
					for _, design in ipairs(Registry.DESIGN_PROFILES or {}) do
						local named = false
						for _, n in ipairs(design.names) do
							if n == roadName then named = true break end
						end
						if named then
							local best, bestY = math.huge, nil
							local pts = design.points
							for p = 1, #pts - 1 do
								local ax, az, ay = pts[p][1], pts[p][2], pts[p][3]
								local bx, bz, by = pts[p + 1][1], pts[p + 1][2], pts[p + 1][3]
								local vx, vz = bx - ax, bz - az
								local u = math.clamp(((xs[k] - ax) * vx + (zs[k] - az) * vz) / (vx * vx + vz * vz), 0, 1)
								local px, pz = ax + vx * u, az + vz * u
								local d = math.sqrt((xs[k] - px) ^ 2 + (zs[k] - pz) ^ 2)
								if d < best then
									best, bestY = d, ay + (by - ay) * u
								end
							end
							if bestY and best <= design.lateral then
								designMask[k] = true
								minReq[k] = math.max(minReq[k], bestY)
								-- the design is authoritative: a crossing cap (the
								-- Conrail track judged to pass over from the DEM)
								-- may not pull the viaduct under it
								maxReq[k] = math.max(math.min(maxReq[k], bestY + 0.5), minReq[k] + 0.5)
								stats.designStations = (stats.designStations or 0) + 1
							end
						end
					end
				end
			end
			for k = 1, count do
				f[k] = math.max(f[k], minReq[k])
			end

			-- e. grade-limited upper envelope (Lipschitz cone hull)
			local g = stroke.grade
			local e = table.clone(f)
			for k = 2, count do
				e[k] = math.max(e[k], e[k - 1] - g * ds)
			end
			for k = count - 1, 1, -1 do
				e[k] = math.max(e[k], e[k + 1] - g * ds)
			end

			-- Every later step keeps G g-Lipschitz (|dG/ds| <= g): G is only
			-- ever combined with min/max of cones of slope g, and min/max of
			-- g-Lipschitz functions are g-Lipschitz.
			local function raiseHull(arr, slope)
				for k = 2, count do
					arr[k] = math.max(arr[k], arr[k - 1] - slope * ds)
				end
				for k = count - 1, 1, -1 do
					arr[k] = math.max(arr[k], arr[k + 1] - slope * ds)
				end
			end
			local function movingAverage(arr, w)
				local prefix = table.create(count + 1, 0)
				for k = 1, count do
					prefix[k + 1] = prefix[k] + arr[k]
				end
				local out = table.create(count)
				for k = 1, count do
					local lo = math.max(1, k - w)
					local hi = math.min(count, k + w)
					out[k] = (prefix[hi + 1] - prefix[lo]) / (hi - lo + 1)
				end
				return out
			end

			-- f. maximum constraints (pass under an already-solved corridor or
			-- a local overpass): lower cone hull of the caps.
			local capHull = table.clone(maxReq)
			for k = 2, count do
				capHull[k] = math.min(capHull[k], capHull[k - 1] + g * ds)
			end
			for k = count - 1, 1, -1 do
				capHull[k] = math.min(capHull[k], capHull[k + 1] + g * ds)
			end
			for k = 1, count do
				e[k] = math.min(e[k], capHull[k])
			end

			-- g. round vertical curves. Crests may round down by up to 0.35
			-- but never below terrain or into a clearance requirement.
			local smoothW = math.max(1, math.floor(SMOOTH / ds / 2 + 0.5))
			local G = table.clone(e)
			for _ = 1, 2 do
				local avg = movingAverage(G, smoothW)
				for k = 1, count do
					local tolerance = 0
					if minReq[k] == -math.huge then
						tolerance = math.clamp(e[k] - c[k], 0, 0.35)
					end
					G[k] = math.min(math.max(avg[k], e[k] - tolerance), capHull[k])
				end
			end
			-- the tolerance varies per station; restore the grade limit
			raiseHull(G, g)
			for k = 1, count do
				G[k] = math.min(G[k], capHull[k])
			end

			-- h. pins: every node shared with a local street is an at-grade
			-- junction (V2 paves a terrain-level pad there), including nodes
			-- inside a stroke where a ramp runs on into a motorway-classed
			-- street. Any node already owned by a solved stroke is matched
			-- exactly.
			local pins = {}
			local function addPin(s, target)
				table.insert(pins, { s = s, target = target })
			end
			for _, part in ipairs(stroke.parts) do
				for _, which in ipairs({ 1, 2 }) do
					local node = part.seg.nodes[which]
					local s = stationOf(part.seg, which == 1 and 0 or 1)
					if node.height then
						addPin(s, node.height)
					elseif node.mixed then
						local k = math.clamp(math.floor(s / ds + 0.5) + 1, 1, count)
						-- a county street ending on a designed viaduct passes
						-- under it: no at-grade pin there
						if not designMask[k] then
							addPin(s, terrainY(node.x, node.z) or t[k])
						end
					end
				end
			end
			table.sort(pins, function(a, b)
				return a.s < b.s
			end)
			-- de-duplicate pins at the same station
			local unique = {}
			for _, pin in ipairs(pins) do
				local last = unique[#unique]
				if last and math.abs(last.s - pin.s) < 0.5 then
					last.target = (last.target + pin.target) / 2
				else
					table.insert(unique, pin)
				end
			end
			pins = unique
			if #pins > 0 then
				stats.pins += #pins
				-- Where two pins are closer than the grade allows, that interval
				-- alone gets the slope it needs (up to 3g) so the climb is spread
				-- evenly instead of piling into the fade at one pin; the conflict
				-- is still counted. w is the cumulative allowed rise along s.
				local wAtPin = { pins[1].s * g }
				for m = 2, #pins do
					local run = pins[m].s - pins[m - 1].s
					local rise = math.abs(pins[m].target - pins[m - 1].target)
					local slope = g
					if rise > g * run + 0.05 then
						slope = math.min(rise / run, 3 * g)
						stats.pinConflicts += 1
						if #stats.pinConflictList < 20 then
							table.insert(stats.pinConflictList, string.format("%s %s s=%.0f..%.0f dy=%.1f",
								stroke.id, tostring(stroke.parts[1].seg.road.name), pins[m - 1].s, pins[m].s,
								pins[m].target - pins[m - 1].target))
						end
					end
					pins[m - 1].slopeAfter = slope
					wAtPin[m] = wAtPin[m - 1] + slope * run
				end
				local w = table.create(count)
				local m = 1
				for k = 1, count do
					local s = (k - 1) * ds
					while m < #pins and s > pins[m + 1].s do
						m += 1
					end
					if s <= pins[1].s then
						w[k] = s * g
					elseif s >= pins[#pins].s then
						w[k] = wAtPin[#pins] + (s - pins[#pins].s) * g
					else
						w[k] = wAtPin[m] + (s - pins[m].s) * pins[m].slopeAfter
					end
				end
				-- Clamp G into the slope cones of every pin, first at 0.85 of the
				-- allowed rise and smoothed (rounded vertical curves where G meets
				-- a cone), then at the full allowed rise.
				local function pinClamp(scale)
					for k = 1, count do
						local lo, up = -math.huge, math.huge
						for index, pin in ipairs(pins) do
							local d = scale * math.abs(w[k] - wAtPin[index])
							lo = math.max(lo, pin.target - d)
							up = math.min(up, pin.target + d)
						end
						G[k] = math.min(math.max(G[k], lo), up)
					end
				end
				pinClamp(0.85)
				G = movingAverage(G, smoothW)
				pinClamp(1)
				for k = 1, count do
					G[k] = math.min(G[k], capHull[k])
				end
				-- The fade below now only absorbs the residual between a pin's
				-- exact station and its nearest sample (<= g * ds / 2).
				local function gAt(s)
					local fIndex = math.clamp(s / ds, 0, count - 1)
					local i0 = math.min(math.floor(fIndex), count - 2)
					if count == 1 then
						return G[1]
					end
					return lerp(G[i0 + 1], G[i0 + 2], fIndex - i0)
				end
				for _, pin in ipairs(pins) do
					pin.delta = pin.target - gAt(pin.s)
				end
				local corrected = table.create(count)
				for k = 1, count do
					local s = (k - 1) * ds
					local delta
					if s <= pins[1].s then
						local fade = math.clamp(math.abs(pins[1].delta) / (g * 0.5), 40, 400)
						delta = pins[1].delta * (1 - smoothstep((pins[1].s - s) / fade))
					elseif s >= pins[#pins].s then
						local p = pins[#pins]
						local fade = math.clamp(math.abs(p.delta) / (g * 0.5), 40, 400)
						delta = p.delta * (1 - smoothstep((s - p.s) / fade))
					else
						local a, b
						for m = 1, #pins - 1 do
							if pins[m].s <= s and s <= pins[m + 1].s then
								a, b = pins[m], pins[m + 1]
								break
							end
						end
						local span = math.max(b.s - a.s, 1e-6)
						local fadeA = math.clamp(math.abs(a.delta) / (g * 0.5), 40, 400)
						local fadeB = math.clamp(math.abs(b.delta) / (g * 0.5), 40, 400)
						if span < fadeA + fadeB then
							-- close pins: blend across the whole interval
							delta = lerp(a.delta, b.delta, smoothstep((s - a.s) / span))
						else
							-- far apart: each pin only bends its own neighbourhood
							delta = a.delta * (1 - smoothstep((s - a.s) / fadeA))
								+ b.delta * (1 - smoothstep((b.s - s) / fadeB))
						end
					end
					corrected[k] = G[k] + delta
				end
				G = corrected
			end
			stroke.G = G
			stroke.t, stroke.tl, stroke.c, stroke.f = t, tl, c, f
			stroke.xs, stroke.zs = xs, zs
			stroke.minReq = minReq
			stroke.bridgeMask = bridgeMask

			-- i. record node heights for strokes solved later
			for _, part in ipairs(stroke.parts) do
				for _, which in ipairs({ 1, 2 }) do
					local node = part.seg.nodes[which]
					if not node.height then
						node.height = profileG(stroke, stationOf(part.seg, which == 1 and 0 or 1))
					end
				end
			end

			-- j. diagnostics
			local strokeGrade, strokeGradeK, strokeCut, strokeCutK = 0, nil, 0, nil
			for k = 1, count do
				local fill = f[k] - c[k]
				if fill > 1 then
					stats.notchFilledStations += 1
					stats.maxNotchFill = math.max(stats.maxNotchFill, fill)
				end
				if k > 1 then
					local grade = math.abs(G[k] - G[k - 1]) / ds
					if grade > g * 1.25 then
						stats.gradeViolations += 1
						if grade > strokeGrade then
							strokeGrade, strokeGradeK = grade, k
						end
					end
					stats.worstGrade = math.max(stats.worstGrade, grade)
				end
				local cutDepth = tl[k] - (G[k] - 0.2)
				if cutDepth > 0.5 then
					stats.cutStations += 1
					stats.worstCut = math.max(stats.worstCut, cutDepth)
					if cutDepth > strokeCut then
						strokeCut, strokeCutK = cutDepth, k
					end
				end
			end
			-- worst location per stroke, so Studio output says WHERE
			local strokeName = tostring(stroke.parts[1].seg.road.name)
			if strokeGradeK then
				table.insert(stats.gradeList, { value = strokeGrade, text = string.format(
					"%s %s grade=%.1f%% at (%.1f, %.1f) s=%.0f", stroke.id, strokeName, strokeGrade * 100,
					xs[strokeGradeK], zs[strokeGradeK], (strokeGradeK - 1) * ds) })
			end
			if strokeCutK and strokeCut > 3 then
				local k = strokeCutK
				table.insert(stats.cutList, { value = strokeCut, text = string.format(
					"%s %s terrainAbovePavement=%.1f at (%.1f, %.1f) s=%.0f centerTerrain=%.1f grade=%.1f",
					stroke.id, strokeName, strokeCut, xs[k], zs[k], (k - 1) * ds, t[k], G[k]) })
			end
			for _, cross in ipairs(stroke.crossings) do
				if cross.relation == "over" and cross.lowerG then
					local opening = profileG(stroke, cross.station) - DECK_STACK - cross.lowerG
					cross.opening = opening
					if opening + 0.25 < cross.clearance then
						stats.clearanceShort += 1
						stats.worstClearanceShort = math.max(stats.worstClearanceShort, cross.clearance - opening)
						if #stats.clearanceList < 40 then
							table.insert(stats.clearanceList, string.format("%s over %s at (%.1f, %.1f) opening=%.1f need=%.1f",
								tostring(cross.seg.road.name), tostring(cross.other.road.name), cross.x, cross.z,
								opening, cross.clearance))
						end
					end
				end
			end
		end
		if orderIndex % 10 == 0 then
			yield()
		end
	end

	-- 8. Classification of stations into grade / fill / span.
	for _, stroke in ipairs(strokes) do
		if stroke.G then
			local count = #stroke.G
			local ds = stroke.ds
			local kind = table.create(count, "grade")
			local basis = table.create(count, "")
			local lowerNames = {}
			for k = 1, count do
				local gap = stroke.G[k] - stroke.t[k]
				if gap > FILL_MIN then
					kind[k] = "fill"
				end
				if stroke.bridgeMask[k] and gap > FILL_MIN then
					kind[k], basis[k] = "span", "source_bridge_tag"
				elseif gap >= NOTCH_SPAN_DEPTH and stroke.f[k] - stroke.c[k] > 4 then
					kind[k], basis[k] = "span", "dem_notch"
				end
			end
			for _, cross in ipairs(stroke.crossings or {}) do
				if cross.relation == "over" then
					local entry = cross.entry
					local label = entry and ("registry:" .. entry.id)
						or (cross.basis == "dem" and "dem_crossing" or "source_layer")
					local marked = false
					if entry and entry.footprint then
						for k = 1, count do
							if Registry.PointInFootprint(entry, stroke.xs[k], stroke.zs[k]) then
								kind[k], basis[k] = "span", label
								lowerNames[k] = tostring(cross.other.road.name)
								marked = true
							end
						end
					end
					if not marked then
						local s, half = cross.station, cross.half or 12
						for k = math.max(1, math.floor((s - half) / ds) + 1), math.min(count, math.ceil((s + half) / ds) + 1) do
							kind[k], basis[k] = "span", label
							lowerNames[k] = tostring(cross.other.road.name)
						end
					end
				end
			end
			-- remove slivers: short span runs become fill, short gaps between
			-- spans become span, isolated fills shorter than a piece become grade
			local function runs()
				local list, k = {}, 1
				while k <= count do
					local j = k
					while j < count and kind[j + 1] == kind[k] do
						j += 1
					end
					table.insert(list, { a = k, b = j, kind = kind[k] })
					k = j + 1
				end
				return list
			end
			for _, run in ipairs(runs()) do
				local length = (run.b - run.a + 1) * ds
				if run.kind == "fill" and length < MIN_SPAN and run.a > 1 and run.b < count
					and kind[run.a - 1] == "span" and kind[run.b + 1] == "span" then
					for k = run.a, run.b do
						kind[k] = "span"
						basis[k] = basis[run.a - 1]
					end
				end
			end
			for _, run in ipairs(runs()) do
				local length = (run.b - run.a + 1) * ds
				local forced = false
				for k = run.a, run.b do
					if basis[k]:sub(1, 9) == "registry:" or basis[k] == "source_layer" or basis[k] == "dem_crossing" then
						forced = true
					end
				end
				if run.kind == "span" and length < MIN_SPAN and not forced then
					for k = run.a, run.b do
						kind[k] = "fill"
					end
				end
			end
			stroke.kind, stroke.basis, stroke.lowerNames = kind, basis, lowerNames
			-- structure ids per span run
			local structureId = table.create(count, "")
			local serial = 0
			for _, run in ipairs(runs()) do
				if run.kind == "span" then
					serial += 1
					local id = stroke.id .. "/S" .. serial
					local names, b = {}, ""
					for k = run.a, run.b do
						structureId[k] = id
						if lowerNames[k] then
							names[lowerNames[k]] = true
						end
						if basis[k] ~= "" then
							b = basis[k]
						end
					end
					local list = {}
					for name in pairs(names) do
						table.insert(list, name)
					end
					table.sort(list)
					stats.spans += 1
					if #stats.spanList < 400 then
						local mid = (run.a + run.b) // 2
						table.insert(stats.spanList, {
							id = id, basis = b, over = table.concat(list, "/"),
							x = stroke.xs[mid], z = stroke.zs[mid],
							length = (run.b - run.a + 1) * ds,
							deckG = stroke.G[mid], groundG = stroke.t[mid],
							name = tostring(stroke.parts[1].seg.road.name),
						})
					end
				end
			end
			stroke.structureId = structureId
			for k = 1, count do
				if kind[k] == "span" then
					stats.spanStations += 1
				elseif kind[k] == "fill" then
					stats.fillStations += 1
				else
					stats.gradeStations += 1
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Queries used by TileBuilderV2
-- ---------------------------------------------------------------------------

-- Connection-group override for a non-corridor road end that shares a source
-- vertex with a freeway interior (see step 5b). nil when not overridden.
function HighwayProfile.ConnectionGroup(road, endpointIndex)
	local o = overrides[road]
	return o and o[endpointIndex] or nil
end

function HighwayProfile.Enabled()
	return enabled
end

-- Number of corridor arms at a V2 endpoint key (0 when not corridor).
function HighwayProfile.CorridorArmsAtKey(key)
	return corridorKeys[key] or 0
end

-- Info for a profiled road, or nil when the road is not corridor / has no
-- terrain to profile against (V2 then falls back to terrain following).
function HighwayProfile.Lookup(road)
	if not enabled then
		return nil
	end
	local info = roadInfo[road]
	if info and info.stroke.G then
		return info
	end
	return nil
end

function HighwayProfile.IsCorridor(road)
	return enabled and roadInfo[road] ~= nil
end

local function stationAt(info, f)
	return info.sA + (info.sB - info.sA) * f
end
HighwayProfile.StationAt = stationAt

local function sampleIndex(stroke, s)
	return math.clamp(math.floor(s / stroke.ds + 0.5) + 1, 1, #stroke.G)
end

-- Grade line at fraction f along the source road (0 at x1/z1, 1 at x2/z2).
function HighwayProfile.GradeAt(info, f)
	return HighwayProfile._profileG(info.stroke, stationAt(info, f))
end

function HighwayProfile.TerrainAt(info, f)
	local stroke = info.stroke
	return stroke.t[sampleIndex(stroke, stationAt(info, f))]
end

function HighwayProfile.KindAt(info, f)
	local stroke = info.stroke
	local k = sampleIndex(stroke, stationAt(info, f))
	return stroke.kind[k], stroke.structureId[k], stroke.basis[k]
end

-- Fractions in (f0, f1) where the structure classification changes.
function HighwayProfile.Boundaries(info, f0, f1)
	local stroke = info.stroke
	local s0, s1 = stationAt(info, f0), stationAt(info, f1)
	local lo, hi = math.min(s0, s1), math.max(s0, s1)
	local result = {}
	local ds = stroke.ds
	local kind = stroke.kind
	local first = math.max(1, math.floor(lo / ds) + 1)
	local last = math.min(#kind - 1, math.floor(hi / ds) + 1)
	for k = first, last do
		if kind[k] ~= kind[k + 1] or stroke.structureId[k] ~= stroke.structureId[k + 1] then
			local s = (k - 1) * ds + ds / 2
			if s > lo + 0.25 and s < hi - 0.25 then
				local span = info.sB - info.sA
				if math.abs(span) > 1e-6 then
					table.insert(result, (s - info.sA) / span)
				end
			end
		end
	end
	table.sort(result)
	return result
end

-- Outer-wedge extension needed at the source road's own end (1 or 2).
function HighwayProfile.JointExtension(info, endIndex)
	if endIndex == 1 then
		return info.ext1 or 0
	end
	return info.ext2 or 0
end

function HighwayProfile.StrokeLink(info)
	return info.stroke.isLink
end

function HighwayProfile.Stats()
	return stats
end

function HighwayProfile.Strokes()
	return strokes
end

-- Registry-confirmed local streets passing over the highway: one record per
-- carriageway crossing, with the street rim the highway was capped under.
-- RoadTerrainConformer holds the street at deck level across the crossing.
function HighwayProfile.LocalOverpasses()
	local list = {}
	if not enabled then
		return list
	end
	for _, stroke in ipairs(strokes) do
		for _, cross in ipairs(stroke.G and stroke.crossings or {}) do
			local other = cross.other
			local rim = cross.shared.rims and cross.shared.rims[other]
			if cross.relation == "under" and cross.basis == "registry" and not other.corridor
				and rim and rim > -math.huge then
				table.insert(list, {
					name = other.road.name, x = cross.x, z = cross.z, rim = rim,
					clearance = math.max(UNDER_CLEARANCE,
						cross.entry and cross.entry.inventoryUnderclearanceStuds or 0),
				})
			end
		end
	end
	return list
end

function HighwayProfile.Summary()
	return string.format(
		"corridorSegments=%d strokes=%d samples=%d unprofilable=%d nodes=%d mixedNodes=%d vertexSplits=%d freewayCrossNodeSplits=%d crossingsHighwayOver=%d registry=%d atGrade=%d dem=%d layer=%d unresolved=%d notchFilledStations=%d maxNotchFill=%.1f cutStationsKept=%d bridgeTagsDropped=%d spikeCutStations=%d maxSpikeCut=%.1f spans=%d spanStations=%d fillStations=%d gradeStations=%d cutStations=%d worstCut=%.1f gradeViolations=%d worstGradePct=%.1f clearanceShort=%d pins=%d pinConflicts=%d",
		stats.corridorSegments, stats.strokes, stats.samples, stats.unprofilable,
		stats.nodes, stats.mixedNodes, stats.vertexSplits, stats.freewayCrossNodeSplits, stats.crossingsOver,
		stats.crossingsRegistry, stats.crossingsAtGrade, stats.crossingsDem, stats.crossingsLayer, stats.crossingsUnresolved, stats.notchFilledStations,
		stats.maxNotchFill, stats.cutStationsKept, stats.bridgeTagsDropped, stats.spikeCutStations, stats.maxSpikeCut, stats.spans,
		stats.spanStations, stats.fillStations, stats.gradeStations, stats.cutStations,
		stats.worstCut, stats.gradeViolations, stats.worstGrade * 100,
		stats.clearanceShort, stats.pins, stats.pinConflicts)
end

return HighwayProfile
