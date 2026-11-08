local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Registry = require(Shared:WaitForChild("HighwayStructureRegistry"))

local HighwayProfile = require(script.Parent:WaitForChild("HighwayProfile"))
local RailProfile = require(script.Parent:WaitForChild("RailProfile"))
local RealBuildings = require(script.Parent:WaitForChild("RealBuildings"))
RealBuildings.stats = { frontDoors = 0, backDoors = 0, sideDoors = 0, storefronts = 0, shops = 0, homes = 0, stores = 0 }

local TileBuilderV2 = {}

-- Pavement omission accounting. Every strip that is NOT built is counted and
-- the first few are reported with coordinates, so missing asphalt can never
-- again be silent.
local omissions = {
	steepPieces = 0, steepLength = 0, noTerrainPieces = 0,
	trimConsumed = 0, trimConsumedHighway = 0, samples = {},
}
local highwayStats = {
	profiledPieces = 0, profiledLength = 0, spanPieces = 0, fillPieces = 0,
	markingParts = 0, suppressedHighwayPads = 0, fallbackHighwayRoads = 0,
}
local function noteOmission(kind, x, z, extra)
	if #omissions.samples < 60 then
		table.insert(omissions.samples, string.format("%s at (%.1f, %.1f)%s", kind, x, z, extra or ""))
	end
end

local S = WorldConfig.STUDS_PER_METER
local CENTER_X_M = WorldConfig.WORLD_CENTER_X_M
local CENTER_Z_M = WorldConfig.WORLD_CENTER_Z_M

local ROAD_YIELD_EVERY = 20
local BUILDING_YIELD_EVERY = 40
local INTERSECTION_YIELD_EVERY = 40

local POLYGON_CORE_MIN = 3.5
local POLYGON_CORE_MAX = 9.0
local POLYGON_MOUTH_MIN = 6.0
local POLYGON_MOUTH_MAX = 38.0
local POLYGON_MOUTH_OVERLAP = 1.25
local POLYGON_LATERAL_OVERLAP = 0.75

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { workspace.Terrain }
terrainParams.IgnoreWater = false

local prepared = false
local globalIntersectionNodes = {}
local globalJunctionGroups = {}
local proximityGrid = {}
local PROXIMITY_CELL_STUDS = 160

local function proximityCell(x, z)
    return math.floor(x / PROXIMITY_CELL_STUDS), math.floor(z / PROXIMITY_CELL_STUDS)
end
local function proximityKey(x, z)
    local gx, gz = proximityCell(x, z)
    return tostring(gx) .. ":" .. tostring(gz)
end

-- LOCKED CHESTERWORLD HANDEDNESS:
-- +X = east, -Z = north.
local function sourceToStuds(xMeters, zMeters)
	return
		(xMeters - CENTER_X_M) * S,
		-(zMeters - CENTER_Z_M) * S
end

local function terrainY(xStuds, zStuds)
	local hit = workspace:Raycast(
		Vector3.new(xStuds, 5000, zStuds),
		Vector3.new(0, -10000, 0),
		terrainParams
	)
	return hit and hit.Position.Y or nil
end

local function makeFolder(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:ClearAllChildren()
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function horizontalLength(a, b)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function horizontalPerpendicular(a, b)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.001 then
		return Vector3.new(1, 0, 0)
	end
	return Vector3.new(-dz / length, 0, dx / length)
end

local function truthy(value)
	if value == true then
		return true
	end
	local text = string.lower(tostring(value or ""))
	return text ~= ""
		and text ~= "0"
		and text ~= "false"
		and text ~= "no"
		and text ~= "none"
		and text ~= "nil"
end

local function gradeLevelForRoad(road)
	local level = tonumber(road.layer) or 0
	if truthy(road.bridge) and level <= 0 then
		level = 1
	elseif truthy(road.tunnel) and level >= 0 then
		level = -1
	end
	return math.clamp(math.round(level), -5, 5)
end

local function gradeOffsetForRoad(road)
	local level = gradeLevelForRoad(road)
	if level > 0 then
		return level * WorldConfig.GRADE_SEPARATION_CLEARANCE_STUDS
	end
	return 0
end

local function roadClass(road)
	return string.lower(tostring(road.road_class or ""))
end

-- County centrelines that are railways, not streets (any class tag).
local RAIL_LINES = {
	["Cr Chester Secondary"] = true,
	["Amtrak Ne Corridor"] = true,
	["Linwood Industrial Track"] = true,
	["Csx Phila Subdivision"] = true,
}

local function shouldBuildSidewalk(road)
	if RAIL_LINES[tostring(road.name or "")] then
		return false
	end
	if truthy(road.bridge) or truthy(road.tunnel) then
		return false
	end
	-- tools/fit_roads_to_buildings.py: back streets whose houses are built to
	-- the edge of the lane have no room for sidewalks
	if road.sidewalk == false then
		return false
	end
	local cls = roadClass(road)
	return cls ~= "motorway"
		and cls ~= "motorway_link"
		and cls ~= "trunk"
		and cls ~= "trunk_link"
		and cls ~= "service"
		and cls ~= "alley"
		and cls ~= "footway"
end

-- Only the highway corridor may recover terrain-rejected strips. County source
-- sometimes labels I-95 as "secondary"; match its exact name as well as class.
-- Keep the original steep-grade rejection for neighborhood roads/sidewalks.
-- Rail and pedestrian records classed as motorways (CSX Phila Subdivision is
-- motorway_link) keep the rejection too, like Amtrak.
local function isHighwayCorridor(attributes)
    if type(attributes) ~= "table" then return false end
    local cls = string.lower(tostring(attributes.CW_RoadClass or ""))
    local name = string.lower(tostring(attributes.ChesterStreet or ""))
    if HighwayProfile.IsExcludedName(name) then return false end
    return cls == "motorway" or cls == "motorway_link"
        or cls == "trunk" or cls == "trunk_link"
        or name:match("^i[%s%-]*95$") ~= nil
        or name:match("^i[%s%-]*476$") ~= nil
end

-- Terrain-following endpoint pair WITHOUT grade rejection. Returns the pair
-- and its grade so callers can subdivide BEFORE deciding to omit anything.
local function groundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset)
	local y1 = terrainY(x1, z1)
	local y2 = terrainY(x2, z2)
	if y1 == nil and y2 == nil then
		return nil, nil, 0
	end
	if y1 == nil then
		y1 = y2
	elseif y2 == nil then
		y2 = y1
	end
	local totalOffset = surfaceOffset + (gradeOffset or 0)
	local a = Vector3.new(x1, y1 + totalOffset, z1)
	local b = Vector3.new(x2, y2 + totalOffset, z2)
	local run = horizontalLength(a, b)
	if run < 0.05 then
		return nil, nil, 0
	end
	return a, b, math.abs(b.Y - a.Y) / run
end

local function safeGroundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset, allowSteepHighway)
	local y1 = terrainY(x1, z1)
	local y2 = terrainY(x2, z2)
	if y1 == nil and y2 == nil then
		return nil, nil
	end
	if y1 == nil then
		y1 = y2
	elseif y2 == nil then
		y2 = y1
	end
	local totalOffset = surfaceOffset + (gradeOffset or 0)
	local a = Vector3.new(x1, y1 + totalOffset, z1)
	local b = Vector3.new(x2, y2 + totalOffset, z2)
	local run = horizontalLength(a, b)
	if run < 0.05 then
		return nil, nil
	end
	if (gradeOffset or 0) == 0 and not allowSteepHighway then
        local grade = math.abs(b.Y - a.Y) / run
        if grade > WorldConfig.MAX_SURFACE_GRADE then
            return nil, nil
        end
    end
	return a, b
end

local function colorForParent(parent)
	if parent.Name == "Roads" then
		return WorldConfig.ROAD_COLOR
	elseif parent.Name == "Sidewalks" then
		return WorldConfig.SIDEWALK_COLOR
	elseif parent.Name == "RoadMarkings" then
		return WorldConfig.CROSSWALK_COLOR
	end
	return nil
end

local function makeStripPart(parent, name, a, b, width, thickness, material, color)
	if not a or not b then
		return nil
	end
	local delta = b - a
	local length = delta.Magnitude
	if length < 0.05 then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = parent.Name ~= "RoadMarkings"
	part.CanTouch = parent.Name ~= "RoadMarkings"
	part.CanQuery = true
	part.CastShadow = parent.Name ~= "RoadMarkings"
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(width, thickness, length)
	part.CFrame = CFrame.lookAt((a + b) / 2, b, Vector3.yAxis)
	local finalColor = color or colorForParent(parent)
	if finalColor then
		part.Color = finalColor
	end
	part.Parent = parent
	return part
end

local function endpointKeyFromStuds(x, z, gradeLevel, connectionGroup)
	local q = WorldConfig.INTERSECTION_ENDPOINT_QUANTIZE_STUDS
	local key = tostring(math.floor(x / q + 0.5))
		.. ":" .. tostring(math.floor(z / q + 0.5))
		.. ":g" .. tostring(gradeLevel or 0)
	-- A source crossing may share X/Z and numeric layer without being a
	-- routable junction. The optional group separates only that endpoint;
	-- it does not change the road's vertical position.
	if connectionGroup and connectionGroup ~= "" then
		return key .. ":c" .. tostring(connectionGroup)
	end
	return key
end

local function endpointConnectionGroup(road, endpointIndex)
	local explicit
	if endpointIndex == 1 then
		explicit = road.node1_connection_group
	else
		explicit = road.node2_connection_group
	end
	if explicit then
		return explicit
	end
	-- Freeway-interior vertex splits decided by HighwayProfile.Prepare.
	return HighwayProfile.ConnectionGroup(road, endpointIndex)
end

local function endpointKeyFromMeters(xMeters, zMeters, road, endpointIndex)
	local x, z = sourceToStuds(xMeters, zMeters)
	return endpointKeyFromStuds(x, z, gradeLevelForRoad(road), endpointConnectionGroup(road, endpointIndex))
end

local function armKey(name, dir)
	local qx = math.floor(dir.X * 20 + (dir.X >= 0 and 0.5 or -0.5))
	local qz = math.floor(dir.Z * 20 + (dir.Z >= 0 and 0.5 or -0.5))
	return string.upper(name) .. ":" .. tostring(qx) .. ":" .. tostring(qz)
end

local function cross2(a, b, c)
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

local function convexHull(points)
	if #points < 3 then
		return points
	end
	local unique = {}
	local seen = {}
	for _, p in ipairs(points) do
		local key = tostring(math.floor(p.X * 100 + 0.5)) .. ":" .. tostring(math.floor(p.Y * 100 + 0.5))
		if not seen[key] then
			seen[key] = true
			table.insert(unique, p)
		end
	end
	if #unique < 3 then
		return unique
	end
	table.sort(unique, function(a, b)
		if a.X == b.X then
			return a.Y < b.Y
		end
		return a.X < b.X
	end)
	local lower = {}
	for _, p in ipairs(unique) do
		while #lower >= 2 and cross2(lower[#lower - 1], lower[#lower], p) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end
	local upper = {}
	for i = #unique, 1, -1 do
		local p = unique[i]
		while #upper >= 2 and cross2(upper[#upper - 1], upper[#upper], p) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	for _, p in ipairs(upper) do
		table.insert(lower, p)
	end
	return lower
end

local function polygonFromNode(node)
	local points = {}
	local center = Vector3.new(node.x, 0, node.z)
	local coreRadius = math.clamp(node.maxWidth * 0.28, POLYGON_CORE_MIN, POLYGON_CORE_MAX)
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		table.insert(points, Vector2.new(
			node.x + math.cos(angle) * coreRadius,
			node.z + math.sin(angle) * coreRadius
		))
	end
	local baseMouthDistance = math.clamp(
		node.maxWidth * 0.58,
		POLYGON_MOUTH_MIN,
		POLYGON_MOUTH_MAX
	)
	for _, arm in ipairs(node.arms) do
		local dir = arm.dir
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local mouthDistance = math.max(baseMouthDistance, arm.width * 0.55) + POLYGON_MOUTH_OVERLAP
		local halfWidth = arm.width / 2 + POLYGON_LATERAL_OVERLAP
		local mouth = center + dir * mouthDistance
		table.insert(points, Vector2.new(mouth.X + perp.X * halfWidth, mouth.Z + perp.Z * halfWidth))
		table.insert(points, Vector2.new(mouth.X - perp.X * halfWidth, mouth.Z - perp.Z * halfWidth))
	end
	return convexHull(points)
end

-- Query the EXACT convex paving polygon at any lateral offset.
-- Used for both full-width road mouths and correctly set-back zebra crossings.
local function rayPolygonExitAtOffset(node, dir, offset)
    local polygon = node.polygon
    if not polygon or #polygon < 3 then return nil end
    local perpendicular = Vector3.new(-dir.Z, 0, dir.X)
    local px = node.x + perpendicular.X * offset
    local pz = node.z + perpendicular.Z * offset
    local rx, rz = dir.X, dir.Z
    local farthest = nil
    for i = 1, #polygon do
        local a = polygon[i]
        local b = polygon[(i % #polygon) + 1]
        local sx, sz = b.X - a.X, b.Y - a.Y
        local denom = rx * sz - rz * sx
        if math.abs(denom) > 1e-7 then
            local qx, qz = a.X - px, a.Y - pz
            local t = (qx * sz - qz * sx) / denom
            local u = (qx * rz - qz * rx) / denom
            if t >= 0 and u >= -1e-5 and u <= 1 + 1e-5 then
                if not farthest or t > farthest then farthest = t end
            end
        end
    end
    return farthest
end

local function polygonArmBoundary(node, dir, halfWidth, useFarthest)
    local middle = rayPolygonExitAtOffset(node, dir, 0)
    if not middle then return node.maxWidth * 0.55 end
    if not halfWidth or halfWidth < 0.1 then return middle end
    local left = rayPolygonExitAtOffset(node, dir, -halfWidth) or middle
    local right = rayPolygonExitAtOffset(node, dir, halfWidth) or middle
    if useFarthest then
        return math.max(middle, left, right)
    end
    -- For the pavement approach, the nearest polygon edge determines where
    -- a full-width rectangular road can begin without leaving a dirt wedge.
    return math.min(middle, left, right)
end

local function rayPolygonDistance(node, dir)
	local polygon = node.polygon
	if not polygon or #polygon < 3 then
		return 0
	end
	local px = node.x
	local pz = node.z
	local rx = dir.X
	local rz = dir.Z
	local best = math.huge
	for i = 1, #polygon do
		local a = polygon[i]
		local b = polygon[(i % #polygon) + 1]
		local sx = b.X - a.X
		local sz = b.Y - a.Y
		local denom = rx * sz - rz * sx
		if math.abs(denom) > 1e-7 then
			local qx = a.X - px
			local qz = a.Y - pz
			local t = (qx * sz - qz * sx) / denom
			local u = (qx * rz - qz * rx) / denom
			if t >= 0 and u >= -1e-5 and u <= 1 + 1e-5 and t < best then
				best = t
			end
		end
	end
	if best == math.huge then
		return node.maxWidth * 0.55
	end
	return best
end

local function addEndpoint(nodes, tileId, xMeters, zMeters, otherXMeters, otherZMeters, road, endpointIndex)
	local x, z = sourceToStuds(xMeters, zMeters)
	local ox, oz = sourceToStuds(otherXMeters, otherZMeters)
	local gradeLevel = gradeLevelForRoad(road)
	local key = endpointKeyFromStuds(x, z, gradeLevel, endpointConnectionGroup(road, endpointIndex))
	local node = nodes[key]
	if not node then
		node = {
			xSum = 0,
			zSum = 0,
			count = 0,
			maxWidth = 0,
			names = {},
			rawArms = {},
            links = {},
			arms = {},
			polygon = nil,
			distinctNames = 0,
			isIntersection = false,
			isNamedIntersection = false,
			gradeLevel = gradeLevel,
			ownerTile = tileId,
			corridorArms = 0,
		}
		nodes[key] = node
	elseif tileId < node.ownerTile then
		node.ownerTile = tileId
	end
	local roadWidth = math.max((tonumber(road.width_m) or 7) * S, 3)
	if HighwayProfile.IsCorridor(road) then
		node.corridorArms += 1
	end
	node.xSum += x
	node.zSum += z
	node.count += 1
    local peerKey = endpointKeyFromStuds(ox, oz, gradeLevel, endpointConnectionGroup(road, 3 - endpointIndex))
    node.links[peerKey] = math.sqrt((ox-x)^2 + (oz-z)^2)
	node.maxWidth = math.max(node.maxWidth, roadWidth)
	local name = tostring(road.junction_name or road.name or "")
	if name ~= "" and name ~= "Road" then
		node.names[name] = true
	end
	local dx = ox - x
	local dz = oz - z
	local length = math.sqrt(dx * dx + dz * dz)
	if length > 0.001 then
		table.insert(node.rawArms, {
			name = name,
			width = roadWidth,
			length = length,
            peerKey = peerKey,
			dir = Vector3.new(dx / length, 0, dz / length),
		})
	end
end

local function finalizeNodes(nodes)
	for _, node in pairs(nodes) do
		local distinctNames = 0
		for _ in pairs(node.names) do
			distinctNames += 1
		end
		local armMap = {}
		for _, arm in ipairs(node.rawArms) do
			local key = armKey(arm.name, arm.dir)
			local current = armMap[key]
			if not current or arm.width > current.width
                or (arm.width == current.width and arm.length > current.length) then
				armMap[key] = arm
			end
		end
		local arms = {}
		for _, arm in pairs(armMap) do
			table.insert(arms, arm)
		end
		table.sort(arms, function(a, b)
			return math.atan2(a.dir.Z, a.dir.X) < math.atan2(b.dir.Z, b.dir.X)
		end)
		node.rawArms = nil
		node.arms = arms
		node.distinctNames = distinctNames
		node.isNamedIntersection = distinctNames >= 2
		node.isIntersection = node.gradeLevel == 0
			and (#arms >= WorldConfig.INTERSECTION_MIN_DEGREE or node.isNamedIntersection)
		-- A merge, diverge or name change INSIDE the highway corridor is not a
		-- street intersection: a terrain-planar pad there would sit below the
		-- profiled pavement and trim the highway back to it. Corridor strips
		-- overlap at these gores instead.
		if node.isIntersection and node.count > 0 and node.corridorArms == node.count then
			node.isIntersection = false
			highwayStats.suppressedHighwayPads += 1
		end
		node.x = node.xSum / math.max(node.count, 1)
		node.z = node.zSum / math.max(node.count, 1)
		if node.isIntersection then
			node.polygon = polygonFromNode(node)
            local r = 0
            for _, p in ipairs(node.polygon) do
                local dx, dz = p.X - node.x, p.Y - node.z
                r = math.max(r, math.sqrt(dx * dx + dz * dz))
            end
            node.outerRadius = r
		end
	end
end

-- Join directly connected, tightly spaced same-grade junctions so they
-- share ONE asphalt polygon instead of three overlapping intersection pads.
-- This is essential for the 9th/Kerlin-Concord triangle (~20m apart).
local function prepareJunctionGroups(nodes)
    local parent = {}
    for key, node in pairs(nodes) do
        if node.isIntersection then parent[key] = key end
    end

    local function root(key)
        if parent[key] == nil then return nil end
        while parent[key] ~= key do
            parent[key] = parent[parent[key]]
            key = parent[key]
        end
        return key
    end

    for key, node in pairs(nodes) do
        if parent[key] then
            for peerKey, linkLength in pairs(node.links or {}) do
                local other = nodes[peerKey]
                if other and parent[peerKey] and other.gradeLevel == node.gradeLevel then
                    if linkLength <= 0.95 * (node.maxWidth + other.maxWidth) then
                        local a, b = root(key), root(peerKey)
                        if a and b and a ~= b then parent[b] = a end
                    end
                end
            end
        end
    end

    local candidateGroups = {}
    for key, node in pairs(nodes) do
        if node.isIntersection then
            local groupKey = root(key)
            local group = candidateGroups[groupKey]
            if not group then
                group = { members = {}, memberKeys = {} }
                candidateGroups[groupKey] = group
            end
            table.insert(group.members, node)
            group.memberKeys[key] = true
        end
    end

    local groups = {}
    local mergedGroups, mergedNodes = 0, 0
    local groupSerial = 0
    for _, candidate in pairs(candidateGroups) do
        local members = candidate.members
        local maxWidth, diameter = 0, 0
        for i, a in ipairs(members) do
            maxWidth = math.max(maxWidth, a.maxWidth)
            for j = i + 1, #members do
                local b = members[j]
                diameter = math.max(diameter,
                    math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2))
            end
        end
        local canMerge = #members > 1
            and diameter <= math.max(120, 2.8 * maxWidth)
        if canMerge then
            local points, names, approaches = {}, {}, {}
            local xSum, zSum, owner = 0, 0, nil
            for _, member in ipairs(members) do
                xSum += member.x
                zSum += member.z
                if not owner or member.ownerTile < owner then
                    owner = member.ownerTile
                end
                for name in pairs(member.names) do names[name] = true end
                for _, p in ipairs(member.polygon or {}) do
                    table.insert(points, p)
                end
                for _, arm in ipairs(member.arms) do
                    if not candidate.memberKeys[arm.peerKey] then
                        table.insert(approaches, {
                            name = arm.name,
                            width = arm.width,
                            length = arm.length,
                            dir = arm.dir,
                            originNode = member,
                        })
                    end
                end
            end
            local polygon = convexHull(points)
            if #polygon >= 3 then
                groupSerial += 1
                for _, member in ipairs(members) do
                    member.polygon = polygon
                    member.clusterId = groupSerial
                end
                local x = xSum / #members
                local z = zSum / #members
                local renderNode = {
                    x = x, z = z, polygon = polygon,
                    maxWidth = maxWidth, names = names,
                    arms = approaches, isIntersection = true,
                    isNamedIntersection = true, clusterId = groupSerial,
                }
                table.insert(groups, {
                    ownerTile = owner, renderNode = renderNode,
                    members = members, merged = true,
                })
                mergedGroups += 1
                mergedNodes += #members
            else
                canMerge = false
            end
        end
        if not canMerge then
            for _, member in ipairs(members) do
                groupSerial += 1
                member.clusterId = groupSerial
                table.insert(groups, {
                    ownerTile = member.ownerTile,
                    renderNode = member,
                    members = {member}, merged = false,
                })
            end
        end
    end
    for _, group in ipairs(groups) do
        local node = group.renderNode
        local radius = 0
        for _, p in ipairs(node.polygon or {}) do
            radius = math.max(radius,
                math.sqrt((p.X - node.x)^2 + (p.Y - node.z)^2))
        end
        node.outerRadius = radius
    end
    return groups, mergedGroups, mergedNodes
end

function TileBuilderV2.Prepare(tileModules)
	globalIntersectionNodes = {}
	omissions = {
		steepPieces = 0, steepLength = 0, noTerrainPieces = 0,
		trimConsumed = 0, trimConsumedHighway = 0, samples = {},
	}
	highwayStats = {
		profiledPieces = 0, profiledLength = 0, spanPieces = 0, fillPieces = 0,
		markingParts = 0, suppressedHighwayPads = 0, fallbackHighwayRoads = 0,
	}
	local entries = {}
	for moduleIndex, tileModule in ipairs(tileModules) do
		if tileModule:IsA("ModuleScript") then
			local ok, tile = pcall(require, tileModule)
			if ok and tile then
				local tileId = tostring(tile.tile_id or tileModule.Name)
				for _, road in ipairs(tile.roads or {}) do
					if not Registry.Suppressed(road.grade_group) then
						table.insert(entries, { road = road, tileId = tileId })
					end
				end
			end
		end
		if moduleIndex % 8 == 0 then task.wait() end
	end
	-- Highway corridor profile is solved on the WHOLE network first, so every
	-- tile builds its highway pieces from one continuous vertical profile.
	local profileStart = os.clock()
	HighwayProfile.Prepare(entries, {
		sourceToStuds = sourceToStuds,
		terrainY = terrainY,
		gradeLevel = gradeLevelForRoad,
		endpointKey = function(road, endpointIndex)
			if endpointIndex == 1 then
				return endpointKeyFromMeters(road.x1, road.z1, road, 1)
			end
			return endpointKeyFromMeters(road.x2, road.z2, road, 2)
		end,
		yield = function() task.wait() end,
	})
	-- Railway vertical profile (embankments and girder bridges over streets)
	local railStart = os.clock()
	RailProfile.Prepare(entries, {
		sourceToStuds = sourceToStuds,
		terrainY = terrainY,
		isRail = function(name) return RAIL_LINES[name] == true end,
		yield = function() task.wait() end,
	})
	do
		local rs = RailProfile.Stats()
		print(("[ChesterWorld RailProfile] strokes=%d segments=%d streetBridges=%d spanStations=%d fillStations=%d maxFill=%.1f seconds=%.1f")
			:format(rs.strokes, rs.segments, rs.streetBridges, rs.spanStations, rs.fillStations, rs.maxFill, os.clock() - railStart))
	end
	if HighwayProfile.Enabled() then
		print(("[ChesterWorld HighwayProfile] %s seconds=%.1f"):format(HighwayProfile.Summary(), os.clock() - profileStart))
		local profileStats = HighwayProfile.Stats()
		for _, line in ipairs(profileStats.pinConflictList) do
			warn("[ChesterWorld HighwayProfilePinConflict] " .. line)
		end
		for _, line in ipairs(profileStats.designMissList or {}) do
			warn("[ChesterWorld HighwayProfileDesignMiss] " .. line)
		end
		for _, line in ipairs(profileStats.unresolvedList) do
			warn("[ChesterWorld HighwayProfileUnresolved] " .. line)
		end
		for _, line in ipairs(profileStats.clearanceList) do
			warn("[ChesterWorld HighwayProfileClearanceShort] " .. line)
		end
		-- worst locations first, at most 12 of each
		for _, pair in ipairs({ { "HighwayProfileGrade", profileStats.gradeList }, { "HighwayProfileCut", profileStats.cutList } }) do
			table.sort(pair[2], function(a, b)
				return a.value > b.value
			end)
			for index = 1, math.min(12, #pair[2]) do
				warn("[ChesterWorld " .. pair[1] .. "] " .. pair[2][index].text)
			end
		end
	end
	-- Bridge approaches: same-name records joining a bridge-tagged record at a
	-- shared vertex, and the record after that (two deep).
	do
		local function vk(x, z) return math.floor(x * 2 + 0.5) .. ":" .. math.floor(z * 2 + 0.5) end
		local frontier = {}
		for _, entry in ipairs(entries) do
			local road = entry.road
			if truthy(road.bridge) then
				local name = tostring(road.name or "")
				frontier[name .. "|" .. vk(road.x1, road.z1)] = true
				frontier[name .. "|" .. vk(road.x2, road.z2)] = true
			end
		end
		for _ = 1, 2 do
			local nextFrontier = {}
			for _, entry in ipairs(entries) do
				local road = entry.road
				if not truthy(road.bridge) and not road.__bridgeApproach then
					local name = tostring(road.name or "")
					local k1, k2 = name .. "|" .. vk(road.x1, road.z1), name .. "|" .. vk(road.x2, road.z2)
					if frontier[k1] or frontier[k2] then
						road.__bridgeApproach = true
						nextFrontier[frontier[k1] and k2 or k1] = true
					end
				end
			end
			frontier = nextFrontier
		end
	end
	for index, entry in ipairs(entries) do
		local road = entry.road
		-- level crossings are not street junctions: no asphalt pad or zebra
		-- crosswalks across the tracks (audit 2026-11-06)
		if not RAIL_LINES[tostring(road.name or "")] then
			addEndpoint(globalIntersectionNodes, entry.tileId, road.x1, road.z1, road.x2, road.z2, road, 1)
			addEndpoint(globalIntersectionNodes, entry.tileId, road.x2, road.z2, road.x1, road.z1, road, 2)
		end
		if index % 250 == 0 then task.wait() end
	end
	finalizeNodes(globalIntersectionNodes)
    local mergedGroups, mergedNodes
    globalJunctionGroups, mergedGroups, mergedNodes =
        prepareJunctionGroups(globalIntersectionNodes)
    proximityGrid = {}
    for _, group in ipairs(globalJunctionGroups) do
        local node = group.renderNode
        local key = proximityKey(node.x, node.z)
        if not proximityGrid[key] then proximityGrid[key] = {} end
        table.insert(proximityGrid[key], node)
    end
	prepared = true
	local nodeCount = 0
	local intersections = 0
	for _, node in pairs(globalIntersectionNodes) do
		nodeCount += 1
		if node.isIntersection then intersections += 1 end
	end
	print(("[ChesterWorld TileBuilderV2] prepared global road graph: nodes=%d intersections=%d junctionSurfaces=%d mergedGroups=%d mergedNodes=%d polygonOwned=true"):format(nodeCount, intersections, #globalJunctionGroups, mergedGroups, mergedNodes))
end

local function pointAlong2D(a, b, distanceFromA)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.001 then return a end
	local t = math.clamp(distanceFromA / length, 0, 1)
	return Vector3.new(a.X + dx * t, 0, a.Z + dz * t)
end

local function trimDistanceForNode(node, dir, extraClearance, halfWidth)
    if not node or not node.isIntersection then return 0 end
    -- Roads must reach the nearest edge across their FULL width. Centerline-
    -- only trimming previously left triangular holes on diagonal approaches.
    local boundary = polygonArmBoundary(node, dir, halfWidth or 0, false)
    return math.max(0,
        boundary - WorldConfig.INTERSECTION_ROAD_OVERLAP_STUDS
        + (extraClearance or 0))
end

local function trimmedEndpoints(road, extraClearance)
	local x1, z1 = sourceToStuds(road.x1, road.z1)
	local x2, z2 = sourceToStuds(road.x2, road.z2)
	local a = Vector3.new(x1, 0, z1)
	local b = Vector3.new(x2, 0, z2)
	local length = horizontalLength(a, b)
	if length < 0.05 then return nil, nil end
	local startNode = globalIntersectionNodes[endpointKeyFromMeters(road.x1, road.z1, road, 1)]
	local endNode = globalIntersectionNodes[endpointKeyFromMeters(road.x2, road.z2, road, 2)]
	local startDir = (b - a).Unit
	local endDir = (a - b).Unit
	local startClearance = extraClearance
    local endClearance = extraClearance
    if type(extraClearance) == "table" then
        startClearance = extraClearance.start or 0
        endClearance = extraClearance.finish or 0
    end
    -- A painted centerline has negligible width. Asphalt/sidewalk approaches
    -- use both pavement edges to prevent gaps beside skewed junctions.
    local halfWidth = 0
    if type(extraClearance) ~= "table" then
        halfWidth = math.max((tonumber(road.width_m) or 7) * S / 2 - 0.25, 1)
    end
	local trimStart = trimDistanceForNode(startNode, startDir, startClearance, halfWidth)
	local trimEnd = trimDistanceForNode(endNode, endDir, endClearance, halfWidth)
	if trimStart + trimEnd >= length - 1.0 then return nil, nil end
	return pointAlong2D(a, b, trimStart), pointAlong2D(b, a, trimEnd)
end

local function shouldSplit(a, b, depth, surfaceOffset, gradeOffset)
	if depth >= WorldConfig.ROAD_MAX_SUBDIVISION_DEPTH then return false end
	if horizontalLength(a, b) > WorldConfig.ROAD_MAX_PIECE_LENGTH_STUDS then return true end
	local midX = (a.X + b.X) / 2
	local midZ = (a.Z + b.Z) / 2
	local groundMid = terrainY(midX, midZ)
	if groundMid == nil then return false end
	local terrainMidY = groundMid + surfaceOffset + (gradeOffset or 0)
	local linearMidY = (a.Y + b.Y) / 2
	return math.abs(terrainMidY - linearMidY) > WorldConfig.ROAD_TERRAIN_ERROR_STUDS
end

local function buildAdaptiveCenterStrip(parent, name, x1, z1, x2, z2, width, thickness, material, color, surfaceOffset, gradeOffset, depth, attributes)
	depth = depth or 0
	gradeOffset = gradeOffset or 0
	local allowSteepHighway = WorldConfig.RECOVER_STEEP_HIGHWAY_PAVEMENT == true and isHighwayCorridor(attributes)
	-- the approach of a creek / ravine bridge climbs the valley side on the
	-- bare-earth DEM; RoadTerrainConformer lifts it onto the bridge line, so
	-- it must exist (omitting it left gaps at Chestnut / Brookhaven)
	if type(attributes) == "table" and attributes.CW_BridgeApproach then
		allowSteepHighway = true
	end
	local a, b, grade = groundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset)
	if not a or not b then
		if parent.Name == "Roads" and math.abs(x2 - x1) + math.abs(z2 - z1) > 0.1 then
			omissions.noTerrainPieces += 1
			noteOmission("no-terrain", (x1 + x2) / 2, (z1 + z2) / 2, " " .. tostring(name))
		end
		return
	end
	-- bridge approach: one straight piece between its two ends (no splitting
	-- along the valley side, which made saw-teeth once some slivers were
	-- lifted onto the bridge line and others were not)
	if type(attributes) == "table" and attributes.CW_BridgeApproach then
		local part = makeStripPart(parent, name, a, b, width, thickness, material, color)
		if part then
			for key, value in pairs(attributes) do part:SetAttribute(key, value) end
		end
		return
	end
	local steep = gradeOffset == 0 and grade > WorldConfig.MAX_SURFACE_GRADE
	-- Split a steep piece first: only the genuinely steep sub-piece may be
	-- omitted, never a whole 120-stud strip with one steep corner.
	if steep and depth < WorldConfig.ROAD_MAX_SUBDIVISION_DEPTH + 2 and horizontalLength(a, b) > 3 then
		local midX = (x1 + x2) / 2
		local midZ = (z1 + z2) / 2
		buildAdaptiveCenterStrip(parent, name, x1, z1, midX, midZ, width, thickness, material, color, surfaceOffset, gradeOffset, depth + 1, attributes)
		buildAdaptiveCenterStrip(parent, name, midX, midZ, x2, z2, width, thickness, material, color, surfaceOffset, gradeOffset, depth + 1, attributes)
		return
	end
	if steep and not allowSteepHighway then
		if parent.Name == "Roads" then
			omissions.steepPieces += 1
			omissions.steepLength += horizontalLength(a, b)
			noteOmission("steep", (x1 + x2) / 2, (z1 + z2) / 2,
				string.format(" grade=%.0f%% %s", grade * 100, tostring(name)))
		end
		return
	end
	if shouldSplit(a, b, depth, surfaceOffset, gradeOffset) then
		local midX = (x1 + x2) / 2
		local midZ = (z1 + z2) / 2
		buildAdaptiveCenterStrip(parent, name, x1, z1, midX, midZ, width, thickness, material, color, surfaceOffset, gradeOffset, depth + 1, attributes)
		buildAdaptiveCenterStrip(parent, name, midX, midZ, x2, z2, width, thickness, material, color, surfaceOffset, gradeOffset, depth + 1, attributes)
		return
	end
	local part = makeStripPart(parent, name, a, b, width, thickness, material, color)
    if part and attributes then
        for key, value in pairs(attributes) do part:SetAttribute(key, value) end
        if allowSteepHighway and gradeOffset == 0 then
            local run = horizontalLength(a, b)
            local grade = run > 0 and math.abs(b.Y - a.Y) / run or 0
            if grade > WorldConfig.MAX_SURFACE_GRADE then
                -- Keep a real pavement strip instead of silently leaving a
                -- hole. Flag it as an UNSAFE terrain-following piece; bridge
                -- profiling or manual source correction still must repair Y.
                part:SetAttribute("CW_SteepHighwayFallback", true)
                part:SetAttribute("CW_UnsafeSurfaceGrade", true)
                part:SetAttribute("CW_ObservedSurfaceGrade", grade)
            end
        end
    end
end

local function roadAttributes(road, roadWidth)
	local level = gradeLevelForRoad(road)
	local bridge = truthy(road.bridge)
	local tunnel = truthy(road.tunnel)
	return {
		ChesterStreet = tostring(road.name or ""),
		RoadWidthStuds = roadWidth,
		CW_RoadClass = tostring(road.road_class or ""),
		CW_GradeLevel = level,
		CW_Bridge = bridge,
		CW_Tunnel = tunnel,
		CW_GradeSeparated = level ~= 0 or bridge or tunnel,
		CW_GradeGroup = tostring(road.grade_group or ""),
		CW_GradeClearanceStuds = math.max(level, 0) * WorldConfig.GRADE_SEPARATION_CLEARANCE_STUDS,
		-- same-street record joining a bridge (see markBridgeApproaches)
		CW_BridgeApproach = road.__bridgeApproach == true or nil,
	}
end

-- Road-relative sidewalks: sampling the terrain at the OUTER sidewalk edge
-- creates artificial curbs/vertical walls on cross-sloped Chester streets.
-- Sample the street centerline instead and follow its height in short pieces.
-- This keeps normal sidewalks solid, with a small tire-friendly curb lip.
local function buildSidewalkPair(sidewalksFolder, streetName, a2D, b2D, roadWidth)
	if not a2D or not b2D then return end
	local run = horizontalLength(a2D, b2D)
	if run < 0.1 then return end
	local perpendicular = horizontalPerpendicular(a2D, b2D)
	local sidewalkWidth = WorldConfig.SIDEWALK_WIDTH_STUDS
	local offsetDistance = roadWidth / 2 + WorldConfig.SIDEWALK_GAP_STUDS + sidewalkWidth / 2
	local thickness = WorldConfig.SIDEWALK_HEIGHT_STUDS
	local curbLip = 0.12
	local centerOffset = WorldConfig.ROAD_SURFACE_OFFSET_STUDS
		+ WorldConfig.ROAD_THICKNESS_STUDS / 2 + curbLip - thickness / 2
	local pieces = math.max(1, math.ceil(run / 18))
	for _, sign in ipairs({ -1, 1 }) do
		local offset = perpendicular * offsetDistance * sign
		for i = 1, pieces do
			local t0, t1 = (i - 1) / pieces, i / pieces
			local x0, z0 = a2D.X + (b2D.X - a2D.X) * t0, a2D.Z + (b2D.Z - a2D.Z) * t0
			local x1, z1 = a2D.X + (b2D.X - a2D.X) * t1, a2D.Z + (b2D.Z - a2D.Z) * t1
			local y0, y1 = terrainY(x0, z0), terrainY(x1, z1)
			if y0 and y1 then
				local p0 = Vector3.new(x0 + offset.X, y0 + centerOffset, z0 + offset.Z)
				local p1 = Vector3.new(x1 + offset.X, y1 + centerOffset, z1 + offset.Z)
				local part = makeStripPart(sidewalksFolder, "Sidewalk", p0, p1, sidewalkWidth,
					thickness, WorldConfig.SIDEWALK_MATERIAL, WorldConfig.SIDEWALK_COLOR)
				if part then
					part:SetAttribute("ChesterStreet", streetName)
					part:SetAttribute("Side", sign < 0 and "Left" or "Right")
					part:SetAttribute("CW_TileBuilderSidewalk", true)
					part:SetAttribute("CW_RoadRelativeElevation", true)
				end
			end
		end
	end
end

local function buildCenterLine(markingsFolder, road, roadWidth)
    if roadWidth < WorldConfig.CENTERLINE_MIN_ROAD_WIDTH_STUDS then return end
    local streetName = tostring(road.name or "")
    if streetName == "" or streetName == "Road" then return end
    local sx, sz = sourceToStuds(road.x1, road.z1)
    local ex, ez = sourceToStuds(road.x2, road.z2)
    local delta = Vector3.new(ex - sx, 0, ez - sz)
    if delta.Magnitude < 0.05 then return end
    local startDir = delta.Unit
    local endDir = -startDir

    local function clearance(node, dir)
        if not node or not node.isIntersection then return 0.5 end
        if node.isNamedIntersection
            and node.maxWidth >= WorldConfig.CROSSWALK_TRIGGER_WIDTH_STUDS
            and roadWidth >= WorldConfig.CROSSWALK_MIN_ARM_WIDTH_STUDS
        then
            local stripes = WorldConfig.CROSSWALK_STRIPE_COUNT
            local span = stripes * WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS
                + (stripes - 1) * WorldConfig.CROSSWALK_STRIPE_GAP_STUDS
            local centerEdge = polygonArmBoundary(node, dir, 0, false)
            local outerEdge = polygonArmBoundary(node, dir,
                math.max(roadWidth - 2.0, 4.0) / 2, true)
            -- Matches the actual FULL-WIDTH crosswalk setback. Yellow lines
            -- stop BEFORE the zebra, including on a strongly skewed corner.
            return math.max(0, outerEdge - centerEdge)
                + WorldConfig.CROSSWALK_EDGE_CLEARANCE_STUDS
                + span + 2.0
        end
        return 2.0
    end

    local startNode = globalIntersectionNodes[
        endpointKeyFromMeters(road.x1, road.z1, road, 1)]
    local endNode = globalIntersectionNodes[
        endpointKeyFromMeters(road.x2, road.z2, road, 2)]
    local a2D, b2D = trimmedEndpoints(road, {
        start = clearance(startNode, startDir),
        finish = clearance(endNode, endDir),
    })
    if not a2D or not b2D then return end
    -- arterials (primary / secondary / trunk: Kerlin, 9th, Concord ...) carry a
    -- double yellow centre line, as on Street View; other streets a single one
    local roadClass = tostring(road.road_class or "")
    local double = roadClass == "primary" or roadClass == "secondary" or roadClass == "trunk"
    local offsets = { 0 }
    local lineWidth = WorldConfig.CENTERLINE_WIDTH_STUDS
    local px, pz = 0, 0
    if double then
        local dx, dz = b2D.X - a2D.X, b2D.Z - a2D.Z
        local len = math.sqrt(dx * dx + dz * dz)
        if len > 1e-3 then
            px, pz = -dz / len, dx / len
            offsets = { -0.55, 0.55 }
            lineWidth = math.min(lineWidth, 0.45)
        end
    end
    for _, o in ipairs(offsets) do
    buildAdaptiveCenterStrip(
        markingsFolder, "CenterLine",
        a2D.X + px * o, a2D.Z + pz * o, b2D.X + px * o, b2D.Z + pz * o,
        lineWidth,
        WorldConfig.CENTERLINE_THICKNESS_STUDS,
        WorldConfig.MARKING_MATERIAL,
        WorldConfig.CENTERLINE_COLOR,
        WorldConfig.CENTERLINE_SURFACE_OFFSET_STUDS,
        gradeOffsetForRoad(road), 0,
        {
            ChesterStreet = streetName,
            MarkingType = "CenterLine",
            CW_GradeLevel = gradeLevelForRoad(road),
            CW_GradeGroup = tostring(road.grade_group or ""),
            CW_Bridge = truthy(road.bridge),
            CW_Tunnel = truthy(road.tunnel),
            CW_RoadClass = tostring(road.road_class or ""),
        }
    )
    end
end

-- ---------------------------------------------------------------------------
-- Highway corridor pavement (elevation owned by HighwayProfile)
-- ---------------------------------------------------------------------------

local function laneLayout(width)
	local shoulder = math.clamp(width * 0.12, 2, 9)
	local driving = math.max(width - 2 * shoulder, 4)
	local lanes = math.clamp(math.floor(driving / WorldConfig.HIGHWAY_LANE_WIDTH_STUDS + 0.25), 1, 4)
	return shoulder, driving, lanes
end

local function makeMarking(markingsFolder, kind, a, b, width, color, attributes)
	local part = makeStripPart(markingsFolder, kind, a, b, width,
		WorldConfig.CENTERLINE_THICKNESS_STUDS, WorldConfig.MARKING_MATERIAL, color)
	if part then
		part:SetAttribute("MarkingType", kind)
		for key, value in pairs(attributes) do
			part:SetAttribute(key, value)
		end
		highwayStats.markingParts += 1
	end
	return part
end

-- Lane lines are anchored to stroke stations, so dashes stay in phase across
-- piece, segment and tile boundaries.
local function buildHighwayMarkings(markingsFolder, info, pa, pb, s0, s1, width, attributes)
	local delta = pb - pa
	local length = delta.Magnitude
	if length < 0.5 then return end
	local along = delta / length
	local flat = Vector3.new(along.X, 0, along.Z)
	if flat.Magnitude < 1e-3 then return end
	flat = flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local lift = Vector3.new(0, WorldConfig.ROAD_THICKNESS_STUDS / 2 + 0.05, 0)
	local shoulder, driving, lanes = laneLayout(width)
	local color = WorldConfig.HIGHWAY_MARKING_COLOR
	local markWidth = WorldConfig.HIGHWAY_MARKING_WIDTH_STUDS
	-- solid edge lines at both shoulders
	for _, side in ipairs({ -1, 1 }) do
		local offset = right * side * (width / 2 - shoulder)
		makeMarking(markingsFolder, "HighwayEdgeLine", pa + offset + lift, pb + offset + lift,
			markWidth, color, attributes)
	end
	if lanes < 2 then return end
	local dash = WorldConfig.HIGHWAY_LANE_DASH_STUDS
	local period = WorldConfig.HIGHWAY_LANE_DASH_PERIOD_STUDS
	local lo, hi = math.min(s0, s1), math.max(s0, s1)
	local first = math.floor(lo / period)
	for k = first, math.floor(hi / period) do
		local d0 = math.max(lo, k * period)
		local d1 = math.min(hi, k * period + dash)
		if d1 - d0 > 0.75 then
			-- station -> distance from pa along this piece
			local f0 = (d0 - s0) / (s1 - s0)
			local f1 = (d1 - s0) / (s1 - s0)
			local qa = pa:Lerp(pb, math.clamp(f0, 0, 1))
			local qb = pa:Lerp(pb, math.clamp(f1, 0, 1))
			for lane = 1, lanes - 1 do
				local offset = right * (-driving / 2 + lane * driving / lanes)
				makeMarking(markingsFolder, "HighwayLaneLine", qa + offset + lift, qb + offset + lift,
					markWidth, color, attributes)
			end
		end
	end
end

local function buildProfiledHighway(roadsFolder, markingsFolder, road, info)
	local roadWidth = math.max((tonumber(road.width_m) or 7) * S, 3)
	local streetName = tostring(road.name or "")
	local a2D, b2D = trimmedEndpoints(road, 0)
	local ax, az = sourceToStuds(road.x1, road.z1)
	local bx, bz = sourceToStuds(road.x2, road.z2)
	local full = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	-- An end standing well above the ground (a viaduct over a street that the
	-- county joins to it at a shared vertex: the Barry approach over Delaware
	-- Ave / Flower St left 39-stud holes) is not cut back for that street's
	-- junction pad: the street passes underneath.
	if full >= 0.05 then
		for index, f in ipairs({ 0, 1 }) do
			local g, t = HighwayProfile.GradeAt(info, f), HighwayProfile.TerrainAt(info, f)
			if g and t and g - t > 6 then
				local p = Vector3.new(index == 1 and ax or bx, 0, index == 1 and az or bz)
				if index == 1 then a2D = p else b2D = p end
			end
		end
	end
	if not a2D or not b2D or full < 0.05 then
		omissions.trimConsumed += 1
		omissions.trimConsumedHighway += 1
		noteOmission("trim-consumed-highway", (ax + bx) / 2, (az + bz) / 2, " " .. streetName)
		return
	end
	local function fractionOf(point)
		return math.clamp(((point.X - ax) * (bx - ax) + (point.Z - az) * (bz - az)) / (full * full), 0, 1)
	end
	local f0, f1 = fractionOf(a2D), fractionOf(b2D)
	local breaks = { f0 }
	for _, f in ipairs(HighwayProfile.Boundaries(info, f0, f1)) do
		table.insert(breaks, f)
	end
	table.insert(breaks, f1)
	local pieceMax = WorldConfig.HIGHWAY_PROFILE_PIECE_STUDS
	local attributes = roadAttributes(road, roadWidth)
	attributes.CW_HighwayProfiled = true
	attributes.CW_ElevationOwner = "HighwayProfile"
	attributes.CW_TerrainConformed = true
	attributes.CW_StrokeId = info.stroke.id
	attributes.CW_HighwayLink = HighwayProfile.StrokeLink(info) == true
	local markAttributes = {
		ChesterStreet = streetName, CW_HighwayProfiled = true,
		CW_ElevationOwner = "HighwayProfile", CW_StrokeId = info.stroke.id,
	}
	for index = 1, #breaks - 1 do
		local fa, fb = breaks[index], breaks[index + 1]
		local runLength = (fb - fa) * full
		if runLength > 0.05 then
			local pieces = math.max(1, math.ceil(runLength / pieceMax))
			for piece = 1, pieces do
				local ga = fa + (fb - fa) * (piece - 1) / pieces
				local gb = fa + (fb - fa) * piece / pieces
				local kind, structureId, basis = HighwayProfile.KindAt(info, (ga + gb) / 2)
				local ya = HighwayProfile.GradeAt(info, ga) + WorldConfig.ROAD_SURFACE_OFFSET_STUDS
				local yb = HighwayProfile.GradeAt(info, gb) + WorldConfig.ROAD_SURFACE_OFFSET_STUDS
				local pa = Vector3.new(ax + (bx - ax) * ga, ya, az + (bz - az) * ga)
				local pb = Vector3.new(ax + (bx - ax) * gb, yb, az + (bz - az) * gb)
				-- Close joint wedges: extend along the piece direction. At the
				-- untrimmed source ends use the stroke's bend extension.
				local dir = (pb - pa).Unit
				local extA = (piece == 1 and index == 1 and ga < 1e-4) and HighwayProfile.JointExtension(info, 1) or 0.05
				local extB = (piece == pieces and index == #breaks - 1 and gb > 1 - 1e-4) and HighwayProfile.JointExtension(info, 2) or 0.05
				local part = makeStripPart(roadsFolder, streetName ~= "" and streetName or "Highway",
					pa - dir * extA, pb + dir * extB, roadWidth,
					WorldConfig.ROAD_THICKNESS_STUDS, WorldConfig.ROAD_MATERIAL, WorldConfig.ROAD_COLOR)
				if part then
					for key, value in pairs(attributes) do
						part:SetAttribute(key, value)
					end
					local sa = HighwayProfile.StationAt(info, ga)
					local sb = HighwayProfile.StationAt(info, gb)
					local terrainMid = HighwayProfile.TerrainAt(info, (ga + gb) / 2)
					part:SetAttribute("CW_Station0", math.min(sa, sb))
					part:SetAttribute("CW_Station1", math.max(sa, sb))
					part:SetAttribute("CW_HighwayStructure", kind)
					part:SetAttribute("CW_StructureId", structureId)
					part:SetAttribute("CW_StructureBasis", basis)
					part:SetAttribute("CW_TerrainGapStuds", (ya + yb) / 2 - WorldConfig.ROAD_SURFACE_OFFSET_STUDS - terrainMid)
					highwayStats.profiledPieces += 1
					highwayStats.profiledLength += (pb - pa).Magnitude
					if kind == "span" then
						highwayStats.spanPieces += 1
					elseif kind == "fill" then
						highwayStats.fillPieces += 1
					end
				end
				buildHighwayMarkings(markingsFolder, info, pa, pb,
					HighwayProfile.StationAt(info, ga), HighwayProfile.StationAt(info, gb),
					roadWidth, markAttributes)
			end
		end
	end
end

local RAIL_BED_STUDS = 4.2 * S
local RAIL_HALF_GAUGE_STUDS = 0.72 * S
local BALLAST_COLOR = Color3.fromRGB(112, 104, 96)
local RAIL_COLOR = Color3.fromRGB(92, 70, 58)

-- Tracks per line (DVRPC 2025 aerial): the NEC is four tracks through Chester,
-- the CSX two, the Conrail / Linwood branches one. Track centres 4 m real.
local RAIL_TRACKS = {
	["Amtrak Ne Corridor"] = 4, ["Csx Phila Subdivision"] = 2,
	["Cr Chester Secondary"] = 1, ["Linwood Industrial Track"] = 1,
}
local TRACK_SPACING_STUDS = 4.0 * 1.302 * S   -- real metres -> Mercator studs
local EMBANKMENT_COLOR = Color3.fromRGB(122, 112, 100)
local GIRDER_COLOR = Color3.fromRGB(62, 64, 66)
local CATENARY_COLOR = Color3.fromRGB(96, 98, 94)
local PIER_EVERY = 72

-- Profiled track (RailProfile): ballast, rails, and the structure under the
-- line: stone embankment walls where it stands on fill, steel girder spans
-- with stone abutments and piers where it bridges a street or a dip, and
-- NEC catenary masts. One straight piece every ~30 studs along the profile.
local function buildProfiledRail(roadsFolder, name, a2D, b2D, road, info)
	local tracks = RAIL_TRACKS[name] or 1
	local bed = RAIL_BED_STUDS + (tracks - 1) * TRACK_SPACING_STUDS
	local attrs = roadAttributes(road, bed)
	attrs.CW_Rail = true
	attrs.CW_RailProfiled = true
	attrs.CW_Bridge = false
	attrs.CW_GradeLevel = 0
	attrs.CW_GradeSeparated = false
	local tile = roadsFolder.Parent
	local structures = tile:FindFirstChild("RailStructures")
	if not structures then
		structures = Instance.new("Folder")
		structures.Name = "RailStructures"
		structures.Parent = tile
	end
	local ax, az = sourceToStuds(road.x1, road.z1)
	local bx, bz = sourceToStuds(road.x2, road.z2)
	local full = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	if full < 0.5 then return end
	local function fractionOf(p)
		return math.clamp(((p.X - ax) * (bx - ax) + (p.Z - az) * (bz - az)) / (full * full), 0, 1)
	end
	local f0, f1 = fractionOf(a2D), fractionOf(b2D)
	local function pointAt(f, yOffset)
		local y = RailProfile.HeightAt(info, f)
		return Vector3.new(ax + (bx - ax) * f, y + yOffset, az + (bz - az) * f), y
	end
	local dir = Vector3.new(bx - ax, 0, bz - az).Unit
	local perp = Vector3.new(-dir.Z, 0, dir.X)
	local length = full * math.abs(f1 - f0)
	local n = math.max(1, math.ceil(length / 30))
	local offset = WorldConfig.ROAD_SURFACE_OFFSET_STUDS - 0.08
	local thickness = WorldConfig.ROAD_THICKNESS_STUDS
	local function stripPart(parent, partName, a, b, width, height, material, color)
		local p = makeStripPart(parent, partName, a, b, width, height, material, color)
		if p then p.Color = color end
		return p
	end
	local prevKind
	for k = 0, n - 1 do
		local fa = f0 + (f1 - f0) * k / n
		local fb = f0 + (f1 - f0) * (k + 1) / n
		local pa, ya = pointAt(fa, offset)
		local pb, yb = pointAt(fb, offset)
		local bedPart = stripPart(roadsFolder, name, pa, pb, bed, thickness, Enum.Material.Pebble, BALLAST_COLOR)
		if bedPart then
			for key, value in pairs(attrs) do bedPart:SetAttribute(key, value) end
		end
		-- two rails per track
		for t = 1, tracks do
			local centre = (t - (tracks + 1) / 2) * TRACK_SPACING_STUDS
			for side = -1, 1, 2 do
				local o = perp * (centre + side * RAIL_HALF_GAUGE_STUDS)
				local rail = stripPart(roadsFolder, "Rail", pa + o + Vector3.new(0, 0.53, 0), pb + o + Vector3.new(0, 0.53, 0),
					0.3, 0.5, Enum.Material.Metal, RAIL_COLOR)
				if rail then rail:SetAttribute("CW_Rail", true) end
			end
		end
		-- structure under this piece
		local fm = (fa + fb) / 2
		local kind = RailProfile.KindAt(info, fm)
		local ga, gb = RailProfile.GroundAt(info, fa), RailProfile.GroundAt(info, fb)
		local ground = math.min(ga or ya, gb or yb)
		local bottomA, bottomB = pa.Y - thickness / 2, pb.Y - thickness / 2
		local mid = (pa + pb) / 2
		local segLen = (Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)).Magnitude
		local look = CFrame.lookAt(Vector3.zero, dir).Rotation
		if kind == "fill" then
			local top = (bottomA + bottomB) / 2
			local h = top - (ground - 1)
			if h > 0.5 then
				local wall = Instance.new("Part")
				wall.Name = "RailEmbankment"
				wall.Anchored = true
				wall.Material = Enum.Material.Cobblestone
				wall.Color = EMBANKMENT_COLOR
				wall.Size = Vector3.new(bed + 3, h, segLen + 0.3)
				wall.CFrame = CFrame.new(mid.X, top - h / 2, mid.Z) * look
				wall.Parent = structures
			end
		elseif kind == "span" then
			-- deck plate and two through-girders along the outer edges
			local deck = stripPart(structures, "RailDeck", pa - Vector3.new(0, thickness / 2 + 0.5, 0),
				pb - Vector3.new(0, thickness / 2 + 0.5, 0), bed + 1.5, 1.0, Enum.Material.Metal, GIRDER_COLOR)
			for side = -1, 1, 2 do
				local o = perp * side * (bed / 2 + 0.6)
				stripPart(structures, "RailGirder", pa + o + Vector3.new(0, -0.6, 0), pb + o + Vector3.new(0, -0.6, 0),
					0.8, 4.2, Enum.Material.Metal, GIRDER_COLOR)
			end
			-- piers inside long spans, never in a street opening
			local st = RailProfile.StationAt(info, fm)
			if math.floor(RailProfile.StationAt(info, fa) / PIER_EVERY) ~= math.floor(RailProfile.StationAt(info, fb) / PIER_EVERY)
				and not RailProfile.OverStreet(info, st) and RailProfile.ClearOfStreets(mid.X, mid.Z, bed / 2 + 1) then
				local top = (bottomA + bottomB) / 2 - 1.0
				local h = top - (ground - 2)
				if h > 3 then
					local pier = Instance.new("Part")
					pier.Name = "RailPier"
					pier.Anchored = true
					pier.Material = Enum.Material.Cobblestone
					pier.Color = EMBANKMENT_COLOR
					pier.Size = Vector3.new(bed + 2, h, 4)
					pier.CFrame = CFrame.new(mid.X, top - h / 2, mid.Z) * look
					pier.Parent = structures
				end
			end
		end
		-- stone abutment where a span meets fill / grade
		if prevKind and (prevKind == "span") ~= (kind == "span") then
			local top = bottomA - 0.6
			local h = top - (ga or ya) + 2
			if h > 2 and RailProfile.ClearOfStreets(pa.X, pa.Z, bed / 2 + 2.5) then
				local abut = Instance.new("Part")
				abut.Name = "RailAbutment"
				abut.Anchored = true
				abut.Material = Enum.Material.Cobblestone
				abut.Color = EMBANKMENT_COLOR
				abut.Size = Vector3.new(bed + 5, h, 3)
				abut.CFrame = CFrame.new(pa.X, top - h / 2, pa.Z) * look
				abut.Parent = structures
			end
		end
		prevKind = kind
		-- NEC catenary: a mast beside the tracks with a cross arm and wire
		if name == "Amtrak Ne Corridor" then
			local stA, stB = RailProfile.StationAt(info, fa), RailProfile.StationAt(info, fb)
			if math.floor(stA / 60) ~= math.floor(stB / 60) then
				local base = pa + perp * (bed / 2 + 1.5)
				local mast = Instance.new("Part")
				mast.Name = "CatenaryMast"
				mast.Anchored = true
				mast.CanCollide = false
				mast.Material = Enum.Material.Metal
				mast.Color = CATENARY_COLOR
				mast.Size = Vector3.new(0.8, 22, 0.8)
				mast.CFrame = CFrame.new(base + Vector3.new(0, 11, 0))
				mast.Parent = structures
				local armEnd = pa - perp * (bed / 2) + Vector3.new(0, 20, 0)
				local armStart = base + Vector3.new(0, 20, 0)
				local arm = stripPart(structures, "CatenaryArm", armStart, armEnd, 0.5, 0.5, Enum.Material.Metal, CATENARY_COLOR)
				if arm then arm.CanCollide = false end
			end
			for t = 1, tracks do
				local o = perp * ((t - (tracks + 1) / 2) * TRACK_SPACING_STUDS) + Vector3.new(0, 17, 0)
				local wire = stripPart(structures, "CatenaryWire", pa + o, pb + o, 0.12, 0.12, Enum.Material.Metal, Color3.fromRGB(40, 40, 40))
				if wire then wire.CanCollide = false end
			end
		end
	end
end

local function buildRailTrack(roadsFolder, name, a2D, b2D, road)
	local info = RailProfile.Info(road)
	if info and info.stroke.G then
		buildProfiledRail(roadsFolder, name, a2D, b2D, road, info)
		return
	end
	local attrs = roadAttributes(road, RAIL_BED_STUDS)
	attrs.CW_Rail = true
	buildAdaptiveCenterStrip(roadsFolder, name, a2D.X, a2D.Z, b2D.X, b2D.Z,
		RAIL_BED_STUDS, WorldConfig.ROAD_THICKNESS_STUDS, Enum.Material.Pebble, BALLAST_COLOR,
		WorldConfig.ROAD_SURFACE_OFFSET_STUDS - 0.08, gradeOffsetForRoad(road), 0, attrs)
	if truthy(road.bridge) or truthy(road.tunnel) then
		-- the bed may be lifted onto a bridge later; loose rail strips would
		-- stay behind at ground level
		return
	end
	local dx, dz = b2D.X - a2D.X, b2D.Z - a2D.Z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.5 then return end
	local px, pz = -dz / len * RAIL_HALF_GAUGE_STUDS, dx / len * RAIL_HALF_GAUGE_STUDS
	for side = -1, 1, 2 do
		buildAdaptiveCenterStrip(roadsFolder, "Rail", a2D.X + px * side, a2D.Z + pz * side,
			b2D.X + px * side, b2D.Z + pz * side, 0.3, 0.5, Enum.Material.Metal, RAIL_COLOR,
			WorldConfig.ROAD_SURFACE_OFFSET_STUDS + 0.45, gradeOffsetForRoad(road), 0, { CW_Rail = true })
	end
end

local function buildRoad(roadsFolder, sidewalksFolder, markingsFolder, road)
	local profiled = HighwayProfile.Lookup(road)
	if profiled then
		buildProfiledHighway(roadsFolder, markingsFolder, road, profiled)
		return
	elseif HighwayProfile.IsCorridor(road) then
		highwayStats.fallbackHighwayRoads += 1
	end
	local roadWidth = math.max((tonumber(road.width_m) or 7) * S, 3)
	local streetName = tostring(road.name or "")
	local a2D, b2D = trimmedEndpoints(road, 0)
	if not a2D or not b2D then
		omissions.trimConsumed += 1
	end
	if roadClass(road) == "footway" then
		-- pedestrian paths / footbridges (tools/fit_roads_to_buildings.py)
		if a2D and b2D then
			buildAdaptiveCenterStrip(roadsFolder, streetName ~= "" and streetName or "Footway",
				a2D.X, a2D.Z, b2D.X, b2D.Z, roadWidth, WorldConfig.ROAD_THICKNESS_STUDS,
				WorldConfig.SIDEWALK_MATERIAL, WorldConfig.SIDEWALK_COLOR,
				WorldConfig.ROAD_SURFACE_OFFSET_STUDS, gradeOffsetForRoad(road), 0,
				roadAttributes(road, roadWidth))
		end
		return
	end
	if RAIL_LINES[streetName] then
		-- county centrelines for rail lines: ballast bed + two rails, no
		-- sidewalks or road markings (audit 2026-11-06: were paved as streets)
		if a2D and b2D then
			buildRailTrack(roadsFolder, streetName, a2D, b2D, road)
		end
		return
	end
	if a2D and b2D then
		buildAdaptiveCenterStrip(
			roadsFolder,
			streetName ~= "" and streetName or "Road",
			a2D.X, a2D.Z, b2D.X, b2D.Z,
			roadWidth,
			WorldConfig.ROAD_THICKNESS_STUDS,
			WorldConfig.ROAD_MATERIAL,
			WorldConfig.ROAD_COLOR,
			WorldConfig.ROAD_SURFACE_OFFSET_STUDS,
			gradeOffsetForRoad(road), 0,
			roadAttributes(road, roadWidth)
		)
	end
	if streetName ~= "" and streetName ~= "Road" and shouldBuildSidewalk(road) then
		local sidewalkA, sidewalkB = trimmedEndpoints(road, WorldConfig.SIDEWALK_INTERSECTION_EXTRA_TRIM_STUDS)
		buildSidewalkPair(sidewalksFolder, streetName, sidewalkA, sidewalkB, roadWidth)
	end
	buildCenterLine(markingsFolder, road, roadWidth)
end

local function uniqueIntersectionNames(node)
	local labels = {}
	for name in pairs(node.names) do table.insert(labels, name) end
	table.sort(labels)
	return labels
end

local function buildCrosswalkForArm(markingsFolder, node, arm)
	if arm.width < WorldConfig.CROSSWALK_MIN_ARM_WIDTH_STUDS then return end
	local dir = arm.dir
	if dir.Magnitude < 0.001 then return end
	local perpendicular = Vector3.new(-dir.Z, 0, dir.X)
    -- Start AFTER the farthest polygon corner across the complete zebra width.
    -- Measuring only the center previously let half the crosswalk sit on the
    -- junction asphalt at diagonal/skewed approaches.
    local usableWidth = math.max(arm.width - 2.0, 4.0)
    local halfAcross = usableWidth / 2
    local baseSetback = polygonArmBoundary(node, dir, halfAcross, true)
        + WorldConfig.CROSSWALK_EDGE_CLEARANCE_STUDS
    local stripeSpan = WorldConfig.CROSSWALK_STRIPE_COUNT * WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS
        + (WorldConfig.CROSSWALK_STRIPE_COUNT - 1) * WorldConfig.CROSSWALK_STRIPE_GAP_STUDS
    -- A short source segment cannot fit a crosswalk before its next junction.
    if arm.length and arm.length < baseSetback + stripeSpan + 4 then return end
    -- The connected road can run through another very nearby intersection.
    -- Never paint a crosswalk across a second junction's asphalt.
    local midpoint = Vector3.new(node.x, 0, node.z)
        + dir * (baseSetback + stripeSpan / 2)
    local gx, gz = proximityCell(midpoint.X, midpoint.Z)
    for ix = gx - 1, gx + 1 do
        for iz = gz - 1, gz + 1 do
            local bucket = proximityGrid[tostring(ix) .. ":" .. tostring(iz)]
            for _, other in ipairs(bucket or {}) do
                if other.clusterId ~= node.clusterId then
                    local dx, dz = midpoint.X - other.x, midpoint.Z - other.z
                    local required = (other.outerRadius or 0) + stripeSpan / 2 + 3
                    if dx * dx + dz * dz < required * required then return end
                end
            end
        end
    end
	for stripe = 0, WorldConfig.CROSSWALK_STRIPE_COUNT - 1 do
		local along = baseSetback + stripe * (WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS + WorldConfig.CROSSWALK_STRIPE_GAP_STUDS)
		local center = Vector3.new(node.x, 0, node.z) + dir * along
		local p1 = center - perpendicular * halfAcross
		local p2 = center + perpendicular * halfAcross
		local a, b = safeGroundPair(p1.X, p1.Z, p2.X, p2.Z, WorldConfig.CROSSWALK_SURFACE_OFFSET_STUDS, 0)
		local stripePart = makeStripPart(
			markingsFolder, "Crosswalk", a, b,
			WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS,
			WorldConfig.CROSSWALK_THICKNESS_STUDS,
			WorldConfig.MARKING_MATERIAL,
			WorldConfig.CROSSWALK_COLOR
		)
		if stripePart then
			stripePart:SetAttribute("MarkingType", "Crosswalk")
			stripePart:SetAttribute("ChesterStreet", tostring(arm.name or ""))
		end
	end
end

local function bestPerpendicularArmPair(node)
	local bestA, bestB = nil, nil
	local bestScore = math.huge
	for i = 1, #node.arms do
		local a = node.arms[i]
		if a.name ~= "" and a.name ~= "Road" then
			for j = i + 1, #node.arms do
				local b = node.arms[j]
				if b.name ~= "" and b.name ~= "Road" and b.name ~= a.name then
					local score = math.abs(a.dir:Dot(b.dir))
					if score < bestScore then bestScore, bestA, bestB = score, a, b end
				end
			end
		end
	end
	return bestA, bestB
end

local function polygonMaxRadius(node)
	local best = 0
	for _, p in ipairs(node.polygon or {}) do
		local dx = p.X - node.x
		local dz = p.Y - node.z
		best = math.max(best, math.sqrt(dx * dx + dz * dz))
	end
	return best
end

local function buildStreetSign(signsFolder, node, labels)
	-- replaced by real blade signs on poles (StreetFurniture.server.lua); the
	-- old floating billboard labels read as boards hanging over the street
	if WorldConfig.LEGACY_BILLBOARD_STREET_SIGNS ~= true then return end
	if not node.isNamedIntersection or node.maxWidth < WorldConfig.STREET_SIGN_TRIGGER_WIDTH_STUDS or #labels < 2 then return end
	local armA, armB = bestPerpendicularArmPair(node)
	if not armA or not armB then return end
	local cornerDir = armA.dir + armB.dir
	if cornerDir.Magnitude < 0.001 then cornerDir = Vector3.new(1, 0, 1) end
	cornerDir = cornerDir.Unit
	local distance = polygonMaxRadius(node) + WorldConfig.STREET_SIGN_CORNER_CLEARANCE_STUDS
	local signX = node.x + cornerDir.X * distance
	local signZ = node.z + cornerDir.Z * distance
	local ground = terrainY(signX, signZ)
	if ground == nil then return end
	local poleHeight = WorldConfig.STREET_SIGN_POLE_HEIGHT_STUDS
	local pole = Instance.new("Part")
	pole.Name = "StreetSign"
	pole.Anchored = true
	pole.CanCollide = false
	pole.Material = WorldConfig.SIGN_POLE_MATERIAL
	pole.Color = WorldConfig.SIGN_POLE_COLOR
	pole.Size = Vector3.new(WorldConfig.STREET_SIGN_POLE_THICKNESS_STUDS, poleHeight, WorldConfig.STREET_SIGN_POLE_THICKNESS_STUDS)
	pole.Position = Vector3.new(signX, ground + poleHeight / 2, signZ)
	pole.Parent = signsFolder
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StreetNames"
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 360
	billboard.Size = UDim2.fromOffset(190, 48)
	billboard.StudsOffset = Vector3.new(0, poleHeight / 2 + 2.5, 0)
	billboard.Parent = pole
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = WorldConfig.SIGN_BACKGROUND_COLOR
	label.BackgroundTransparency = 0.03
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = WorldConfig.SIGN_TEXT_COLOR
	label.TextSize = 15
	label.TextWrapped = true
	label.Text = string.upper(labels[1] .. " / " .. labels[2])
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = label
	pole:SetAttribute("Intersection", labels[1] .. " & " .. labels[2])
end

local function intersectionFrame(x, z, radius)
	local centerGround = terrainY(x, z)
	if centerGround == nil then return nil end
	local sample = math.clamp(radius * 0.28, 4, 12)
	local east = terrainY(x + sample, z) or centerGround
	local west = terrainY(x - sample, z) or centerGround
	local south = terrainY(x, z + sample) or centerGround
	local north = terrainY(x, z - sample) or centerGround
	local gradeX = math.clamp((east - west) / (sample * 2), -WorldConfig.INTERSECTION_MAX_GRADE, WorldConfig.INTERSECTION_MAX_GRADE)
	local gradeZ = math.clamp((south - north) / (sample * 2), -WorldConfig.INTERSECTION_MAX_GRADE, WorldConfig.INTERSECTION_MAX_GRADE)
	local up = Vector3.new(-gradeX, 1, -gradeZ).Unit
	local right = Vector3.new(1, gradeX, 0).Unit
	local back = right:Cross(up).Unit
	right = up:Cross(back).Unit
	return CFrame.fromMatrix(
		Vector3.new(x, centerGround + WorldConfig.ROAD_SURFACE_OFFSET_STUDS, z),
		right, up, back
	)
end

local function planeYAtFrame(frame, x, z, yOffset)
	local normal = frame.UpVector
	local planePoint = frame.Position + normal * (yOffset or 0)
	if math.abs(normal.Y) < 0.001 then return planePoint.Y end
	return planePoint.Y - (normal.X * (x - planePoint.X) + normal.Z * (z - planePoint.Z)) / normal.Y
end


-- Solid convex polygon, built from ordinary Roblox WedgeParts.
-- Two wedges fill each triangle (the standard 3D-triangle decomposition).
-- This avoids EditableMesh API permissions, winding problems and MeshPart pivots.
local function fillTriangleWithWedges(parent, a, b, c, thickness, labels)
    local ab, ac, bc = b - a, c - a, c - b
    local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
    if abd > acd and abd > bcd then
        c, a = a, c
    elseif acd > bcd and acd > abd then
        a, b = b, a
    end
    ab, ac, bc = b - a, c - a, c - b
    local normal = ac:Cross(ab)
    if normal.Magnitude < 0.01 or bc.Magnitude < 0.1 then return 0 end
    local right = normal.Unit
    local up = bc:Cross(right).Unit
    local back = bc.Unit
    local height = math.abs(ab:Dot(up))
    if height < 0.08 then return 0 end
    local count = 0

    local function buildWedge(position, xAxis, yAxis, zAxis, depth)
        if depth < 0.08 then return end
        local wedge = Instance.new("WedgePart")
        wedge.Name = "IntersectionAsphalt"
        wedge.Anchored = true
        wedge.CanCollide = true
        wedge.CanTouch = true
        wedge.CanQuery = true
        -- Separate wedge pieces would otherwise shadow one another at
        -- their internal shared edges and draw dark zigzag seams.
        wedge.CastShadow = false
        wedge.TopSurface = Enum.SurfaceType.Smooth
        wedge.BottomSurface = Enum.SurfaceType.Smooth
        wedge.Material = WorldConfig.INTERSECTION_MATERIAL
        wedge.Color = WorldConfig.INTERSECTION_COLOR
        wedge.Size = Vector3.new(thickness, height, depth)
        wedge.CFrame = CFrame.fromMatrix(position, xAxis, yAxis, zAxis)
        wedge:SetAttribute("CW_IntersectionPad", true)
        wedge:SetAttribute("CW_IntersectionSolid", true)
        wedge:SetAttribute("CW_IntersectionOwner", "TileBuilderV3")
        wedge:SetAttribute("CW_GradeLevel", 0)
        if #labels > 0 then wedge:SetAttribute("Intersection", table.concat(labels, " & ")) end
        wedge.Parent = parent
        count += 1
    end
    buildWedge((a + b) / 2, right, up, back, math.abs(ab:Dot(back)))
    buildWedge((a + c) / 2, -right, up, -back, math.abs(ac:Dot(back)))
    return count
end

local function makeIntersectionMesh(parent, node, labels)
    local polygon = node.polygon
    if not polygon or #polygon < 3 then return nil end
    local radius = polygonMaxRadius(node)
    local frame = intersectionFrame(node.x, node.z, radius)
    if not frame then return nil end
    local thickness = WorldConfig.ROAD_THICKNESS_STUDS + 0.12
    local surfaceOffset = thickness / 2 + 0.10

    -- Build from the SAME node.polygon used by rayPolygonDistance and trimming.
    -- A center fan of a convex polygon has no holes and no oversized bbox.
    local function pointAt(x, z)
        local topY = planeYAtFrame(frame, x, z, surfaceOffset)
        return Vector3.new(x, topY - thickness / 2, z)
    end
    local center = pointAt(node.x, node.z)
    local group = Instance.new("Model")
    group.Name = "Intersection"
    group:SetAttribute("CW_IntersectionPad", true)
    group:SetAttribute("CW_IntersectionSolid", true)
    group:SetAttribute("CW_IntersectionOwner", "TileBuilderV3")
    group:SetAttribute("CW_IntersectionPolygon", true)
    if #labels > 0 then group:SetAttribute("Intersection", table.concat(labels, " & ")) end
    local count = 0
    for i = 1, #polygon do
        local b = polygon[i]
        local c = polygon[(i % #polygon) + 1]
        count += fillTriangleWithWedges(
            group, center, pointAt(b.X, b.Y), pointAt(c.X, c.Y),
            thickness, labels
        )
    end
    -- If all triangles were degenerate, use the existing visible fallback.
    if count < 3 then group:Destroy(); return nil end
    group.Parent = parent
    return group
end

local function makeIntersectionFallback(parent, node, labels)
	local radius = math.max(node.maxWidth * 0.55, 6)
	local frame = intersectionFrame(node.x, node.z, radius)
	if not frame then return nil end
	local pad = Instance.new("Part")
	pad.Name = "IntersectionFallback"
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = true
	pad.CanQuery = true
	pad.Material = WorldConfig.INTERSECTION_MATERIAL
	pad.Color = WorldConfig.INTERSECTION_COLOR
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	pad.Size = Vector3.new(radius * 2, WorldConfig.ROAD_THICKNESS_STUDS + 0.08, radius * 2)
	pad.CFrame = frame
	pad:SetAttribute("CW_IntersectionPad", true)
	pad:SetAttribute("CW_IntersectionFallback", true)
	if #labels > 0 then pad:SetAttribute("Intersection", table.concat(labels, " & ")) end
	pad.Parent = parent
	return pad
end

local function buildIntersections(parent, markingsFolder, signsFolder, tileId)
    local processed = 0
    -- Render ONE polygon for an entire connected nearby-junction group.
    -- Each member's source-road ends are trimmed to that same polygon.
    for _, group in ipairs(globalJunctionGroups) do
        if group.ownerTile == tileId then
            local node = group.renderNode
            local labels = uniqueIntersectionNames(node)
            local pad = makeIntersectionMesh(parent, node, labels)
            if not pad then makeIntersectionFallback(parent, node, labels) end
            if node.isNamedIntersection
                and node.maxWidth >= WorldConfig.CROSSWALK_TRIGGER_WIDTH_STUDS
            then
                local physicalApproaches = {}
                for _, arm in ipairs(node.arms) do
                    local originNode = arm.originNode or node
                    local matchingIndex = nil
                    for index, existing in ipairs(physicalApproaches) do
                        local previousOrigin = existing.originNode or node
                        local dx = originNode.x - previousOrigin.x
                        local dz = originNode.z - previousOrigin.z
                        if existing.dir:Dot(arm.dir) > 0.985
                            and dx * dx + dz * dz <
                                math.max(existing.width, arm.width)^2
                        then
                            matchingIndex = index
                            break
                        end
                    end
                    if matchingIndex then
                        if arm.width > physicalApproaches[matchingIndex].width then
                            physicalApproaches[matchingIndex] = arm
                        end
                    else
                        table.insert(physicalApproaches, arm)
                    end
                end
                for _, arm in ipairs(physicalApproaches) do
                    buildCrosswalkForArm(markingsFolder, arm.originNode or node, arm)
                end
            end
            buildStreetSign(signsFolder, node, labels)
            processed += 1
            if processed % INTERSECTION_YIELD_EVERY == 0 then task.wait() end
        end
    end
end

-- Footprint buildings (tools/build_building_tiles.py). Each building is a set of
-- rectangles along its own axis; style picks material, palette and roof.
local BuildingTiles = Shared:WaitForChild("WorldData"):FindFirstChild("BuildingTiles")

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local BUILDING_STYLES = {
	rowhouse = { material = Enum.Material.Brick, roof = "cornice",
		walls = { rgb(138, 62, 48), rgb(156, 79, 58), rgb(120, 58, 46), rgb(170, 96, 74), rgb(112, 72, 62), rgb(196, 186, 168) },
		top = rgb(58, 54, 52) },
	storefront = { material = Enum.Material.Brick, roof = "cornice",
		walls = { rgb(150, 82, 62), rgb(176, 160, 138), rgb(128, 70, 56), rgb(196, 190, 176), rgb(105, 98, 92) },
		top = rgb(64, 60, 58) },
	apartment = { material = Enum.Material.Brick, roof = "cornice",
		walls = { rgb(146, 76, 58), rgb(168, 112, 86), rgb(186, 176, 160), rgb(122, 92, 80) },
		top = rgb(66, 62, 60) },
	-- downtown and mill buildings are mostly brick; `alt` gives some concrete
	-- (Metal reflects the sky and reads as blue glass, so it is not used)
	commercial = { material = Enum.Material.Brick, roof = "cornice", alt = Enum.Material.Concrete,
		walls = { rgb(150, 86, 66), rgb(176, 160, 138), rgb(132, 74, 58), rgb(196, 190, 176), rgb(168, 120, 92) },
		top = rgb(70, 66, 62) },
	generic = { material = Enum.Material.Concrete, roof = "flat", alt = Enum.Material.Brick,
		walls = { rgb(186, 178, 164), rgb(160, 150, 138), rgb(150, 92, 72), rgb(198, 188, 168) } },
	industrial = { material = Enum.Material.Brick, roof = "flat", alt = Enum.Material.Concrete,
		walls = { rgb(140, 78, 60), rgb(156, 146, 134), rgb(120, 82, 68), rgb(170, 164, 152) } },
	warehouse = { material = Enum.Material.Concrete, roof = "flat",
		walls = { rgb(176, 174, 166), rgb(150, 152, 150), rgb(190, 184, 170), rgb(132, 138, 140) } },
	school = { material = Enum.Material.Brick, roof = "flat",
		walls = { rgb(158, 88, 68), rgb(170, 104, 80) } },
	church = { material = Enum.Material.Cobblestone, roof = "gable",
		walls = { rgb(150, 140, 128), rgb(132, 118, 104), rgb(160, 90, 70) },
		roofs = { rgb(70, 72, 76), rgb(84, 66, 58) } },
	house = { material = Enum.Material.SmoothPlastic, roof = "gable",
		walls = { rgb(226, 220, 204), rgb(200, 210, 214), rgb(230, 224, 196), rgb(190, 200, 180), rgb(216, 200, 184), rgb(176, 168, 158), rgb(154, 84, 64) },
		roofs = { rgb(70, 62, 58), rgb(92, 54, 46), rgb(62, 66, 72), rgb(110, 102, 92) } },
	twin = { material = Enum.Material.Brick, roof = "gable",
		walls = { rgb(150, 80, 62), rgb(196, 188, 170), rgb(132, 74, 60), rgb(214, 206, 186) },
		roofs = { rgb(70, 62, 58), rgb(62, 66, 72), rgb(96, 60, 50) } },
	garage = { material = Enum.Material.SmoothPlastic, roof = "flat",
		walls = { rgb(214, 208, 196), rgb(180, 176, 168), rgb(150, 146, 140) } },
}

-- Facade window textures (tools/make_facade_textures.py, uploaded 2026-11-05):
-- one bay x one storey each, transparent around the window. Tiled from the
-- roofline down so the top storey lines up with the cornice.
local FACADES = {
	residential = { texture = "rbxassetid://87121421598977", bay = 8 },
	commercial = { texture = "rbxassetid://125405099207126", bay = 12 },
	industrial = { texture = "rbxassetid://112532330474936", bay = 12 },
}
local FACADE_FOR_STYLE = {
	rowhouse = "residential", house = "residential", twin = "residential", apartment = "residential",
	storefront = "commercial", commercial = "commercial", school = "commercial", generic = "commercial",
	industrial = "industrial",
	-- warehouses stay windowless: blank walls in the 2026-11-06 Street View audit
}
-- Front/Back faces span the part's X size, Left/Right its Z size
local FACES = {
	{ Enum.NormalId.Front, "x" }, { Enum.NormalId.Back, "x" },
	{ Enum.NormalId.Left, "z" }, { Enum.NormalId.Right, "z" },
}

-- onlyFaces: optional { [Enum.NormalId] = true } (the house kit skips the
-- party walls between row units: ~40k textures city-wide)
local function applyFacade(block, styleKey, storey, onlyFaces)
	local facade = FACADES[FACADE_FOR_STYLE[styleKey] or ""]
	if not facade then return end
	local spans = { x = block.Size.X, z = block.Size.Z }
	for _, face in ipairs(FACES) do
		if spans[face[2]] >= facade.bay * 0.8 and (not onlyFaces or onlyFaces[face[1]]) then
			local texture = Instance.new("Texture")
			texture.Texture = facade.texture
			texture.Face = face[1]
			texture.StudsPerTileU = facade.bay
			texture.StudsPerTileV = storey
			texture.Parent = block
		end
	end
end

-- Ground storey textures: front door + window per rowhouse bay, shopfront glass
-- with a sign band. Stretched to the part's height (one tile).
local GROUND_STOREYS = {
	residential = { texture = "rbxassetid://134036168835861", bay = 15 },
	storefront = { texture = "rbxassetid://113770832567908", bay = 16 },
}
local GROUND_FOR_STYLE = {
	rowhouse = "residential", twin = "residential", house = "residential", apartment = "residential",
	storefront = "storefront", commercial = "storefront",
}

local function applyGroundStorey(block, kind)
	local ground = GROUND_STOREYS[kind]
	local spans = { x = block.Size.X, z = block.Size.Z }
	for _, face in ipairs(FACES) do
		if spans[face[2]] >= ground.bay * 0.7 then
			local texture = Instance.new("Texture")
			texture.Texture = ground.texture
			texture.Face = face[1]
			texture.StudsPerTileU = ground.bay
			texture.StudsPerTileV = block.Size.Y
			texture.Parent = block
		end
	end
end

local function pick(list, seed, salt)
	local n = #list
	return list[((seed * 7919 + salt * 104729) % n) + 1]
end

local function newPart(parent, name, size, cframe, material, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Material = material
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Gable roof over one rectangle: two wedges meeting at the ridge along the
-- long side.
local function buildGable(parent, name, cframe, along, across, rise, color)
	local alongX = along >= across
	local span = alongX and across or along
	local length = alongX and along or across
	for side = -1, 1, 2 do
		local wedge = Instance.new("WedgePart")
		wedge.Name = name
		wedge.Anchored = true
		wedge.Material = Enum.Material.Slate
		wedge.Color = color
		-- a wedge's tall edge is at its +Z face; turn each half so that edge
		-- meets the other half at the ridge
		wedge.Size = Vector3.new(length, rise, span / 2)
		local offset = Vector3.new(0, rise / 2, side * span / 4)
		local facing = side == 1 and math.pi or 0
		local base = alongX and cframe or cframe * CFrame.Angles(0, math.pi / 2, 0)
		wedge.CFrame = base * CFrame.new(offset) * CFrame.Angles(0, facing, 0)
		wedge.Parent = parent
	end
end

-- Sign band over the shopfront of a street-imagery verified corner store /
-- deli / market: on the face of its largest block that looks toward the
-- frontage bearing (sb, compass degrees) recorded by the storefront sweep.
local function hexColor(value)
	return Color3.fromRGB(math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
end
local SIGN_COLORS = {
	{ Color3.fromRGB(176, 32, 36), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(24, 74, 140), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(30, 110, 60), Color3.fromRGB(255, 255, 255) },
	{ Color3.fromRGB(240, 196, 40), Color3.fromRGB(30, 30, 30) },
	{ Color3.fromRGB(245, 245, 240), Color3.fromRGB(180, 30, 30) },
}
-- local face normal of a footprint rectangle that looks toward a compass bearing
local function faceToward(frame, bearingDeg)
	local rad = math.rad(bearingDeg)
	local front = Vector3.new(math.sin(rad), 0, -math.cos(rad))
	local best, bestDot
	for _, n in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local d = frame:VectorToWorldSpace(n):Dot(front)
		if not bestDot or d > bestDot then
			best, bestDot = n, d
		end
	end
	return best
end

-- Front porch (tools/add_porches.py: pb = bearing of the street front, pd =
-- depth in source metres, sized to stay clear of the sidewalk): floor, shed
-- roof at the ground-storey top and corner posts.
local PORCH_TRIM = Color3.fromRGB(226, 224, 216)
local PORCH_ROOF = Color3.fromRGB(78, 80, 84)
local PORCH_FLOOR = Color3.fromRGB(150, 146, 140)
local function buildPorch(model, shapeData, rect, yaw)
	local frame = CFrame.new(rect.x, 0, rect.z) * yaw
	local n = faceToward(frame, shapeData.pb)
	local depth = (n.X ~= 0) and rect.along or rect.across
	local span = (n.X ~= 0) and rect.across or rect.along
	local porchDepth = shapeData.pd * S
	local width = span * 0.96
	local base, top = rect.streetLevel, rect.porchTop
	if top - base < 7 then return end
	local out = frame:VectorToWorldSpace(n)
	local look = CFrame.lookAt(Vector3.new(), out)
	local centre = Vector3.new(rect.x, 0, rect.z) + out * (depth / 2 + porchDepth / 2)
	-- lookAt: local -Z = outward, local X = along the face
	local function at(y, o)
		return CFrame.new(centre.X, y, centre.Z) * look.Rotation * CFrame.new(o or Vector3.zero)
	end
	local floor = newPart(model, "PorchFloor", Vector3.new(width, 1.4, porchDepth), at(base + 0.5),
		Enum.Material.Concrete, PORCH_FLOOR)
	floor.CanCollide = true
	local roof = newPart(model, "PorchRoof", Vector3.new(width + 0.6, 0.7, porchDepth + 0.6),
		at(top + 0.35) * CFrame.Angles(math.rad(-6), 0, 0), Enum.Material.SmoothPlastic, PORCH_ROOF)
	roof.CanCollide = false
	for _, side in ipairs({ -1, 1 }) do
		local post = newPart(model, "PorchPost", Vector3.new(0.7, top - base - 1.2, 0.7),
			at((top + base + 1.2) / 2, Vector3.new(side * (width / 2 - 0.5), 0, -(porchDepth / 2 - 0.5))),
			Enum.Material.SmoothPlastic, PORCH_TRIM)
		post.CanCollide = false
	end
end

-- Hand-detailed landmark front (tools/add_porches.py LANDMARKS: lm, lb =
-- bearing of the street front). 5-7 W 5th St: rusticated granite with tall
-- round-arched windows on every floor and projecting stone sill courses.
local LANDMARK_STYLES = {
	granite = {
		material = Enum.Material.Granite,
		wall = Color3.fromRGB(150, 147, 140),
		trim = Color3.fromRGB(122, 119, 113),
		glass = Color3.fromRGB(38, 44, 52),
	},
}
local function buildArchedFront(model, rect, yaw, bearing)
	local frame = CFrame.new(rect.x, 0, rect.z) * yaw
	local n = faceToward(frame, bearing)
	local depth = (n.X ~= 0) and rect.along or rect.across
	local span = (n.X ~= 0) and rect.across or rect.along
	if span < 8 then return end
	local out = frame:VectorToWorldSpace(n)
	local centre = Vector3.new(rect.x, 0, rect.z) + out * (depth / 2)
	local face = CFrame.lookAt(centre, centre + out)   -- local X runs along the face
	local style = LANDMARK_STYLES.granite
	local storey = rect.storey
	local floors = math.max(1, math.floor((rect.wallTop - rect.streetLevel) / storey + 0.2))
	local bays = math.max(1, math.floor(span / 10))
	local pitch = span / bays
	local w = math.min(4.2, pitch * 0.5)
	for f = 0, floors - 1 do
		local sill = rect.streetLevel + f * storey + (f == 0 and 2.5 or 1.6)
		local h = math.min(storey * 0.68, rect.wallTop - sill - 1.5)
		if h > w then
			local course = newPart(model, "StoneCourse", Vector3.new(span + 0.4, 0.7, 0.8),
				CFrame.new(centre.X, sill - 0.35, centre.Z) * face.Rotation, style.material, style.trim)
			course.CanCollide = false
			for b = 0, bays - 1 do
				local u = -span / 2 + pitch * (b + 0.5)
				local straight = h - w / 2
				local glass = newPart(model, "ArchWindow", Vector3.new(w, straight, 0.3),
					face * CFrame.new(u, 0, -0.1) + Vector3.new(0, sill + straight / 2, 0),
					Enum.Material.Glass, style.glass)
				glass.CanCollide = false
				glass.Reflectance = 0.15
				local arch = newPart(model, "ArchWindow", Vector3.new(0.3, w, w),
					(face * CFrame.new(u, 0, -0.1) + Vector3.new(0, sill + straight, 0)) * CFrame.Angles(0, math.pi / 2, 0),
					Enum.Material.Glass, style.glass)
				arch.Shape = Enum.PartType.Cylinder
				arch.CanCollide = false
				arch.Reflectance = 0.15
				-- voussoir ring around the arch
				local ring = newPart(model, "ArchStone", Vector3.new(0.25, w + 1.2, w + 1.2),
					(face * CFrame.new(u, 0, 0.02) + Vector3.new(0, sill + straight, 0)) * CFrame.Angles(0, math.pi / 2, 0),
					style.material, style.trim)
				ring.Shape = Enum.PartType.Cylinder
				ring.CanCollide = false
			end
		end
	end
end

-- a business's own sign on its section of the building (tools/storefronts/
-- add_store_identity.py: Overture places -> ss={{name, rect, bearing, bg, text}})
local function buildShopSign(model, rect, yaw, name, bearing, bg, fg)
	local frame = CFrame.new(rect.x, rect.bandY, rect.z) * yaw
	local best = faceToward(frame, bearing)
	local depth = (best.X ~= 0) and rect.along or rect.across
	local span = (best.X ~= 0) and rect.across or rect.along
	if span < 6 then return end
	local width = math.clamp(span * 0.85, 6, 36)
	local centre = frame * CFrame.new(best * (depth / 2 + 0.35))
	local look = CFrame.lookAt(centre.Position, centre.Position + frame:VectorToWorldSpace(best))
	local board = newPart(model, "ShopSign", Vector3.new(width, 2.6, 0.5), look, Enum.Material.SmoothPlastic, hexColor(bg))
	board.CanCollide = false
	board:SetAttribute("ShopName", name)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.4
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(0.94, 0.86)
	text.Position = UDim2.fromScale(0.03, 0.07)
	text.BackgroundTransparency = 1
	text.Text = string.upper(name)
	text.TextColor3 = hexColor(fg)
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.Parent = gui
end

local function buildStoreSign(model, shapeData, rect, yaw)
	local frame = CFrame.new(rect.x, rect.bandY, rect.z) * yaw
	local best = faceToward(frame, shapeData.sb)
	local depth = (best.X ~= 0) and rect.along or rect.across
	local span = (best.X ~= 0) and rect.across or rect.along
	local width = math.clamp(span * 0.85, 8, 40)
	local centre = frame * CFrame.new(best * (depth / 2 + 0.35))
	local look = CFrame.lookAt(centre.Position, centre.Position + frame:VectorToWorldSpace(best))
	local colors = SIGN_COLORS[(tonumber(model:GetAttribute("ChesterBuildingId")) or 0) % #SIGN_COLORS + 1]
	if shapeData.sc and shapeData.st then
		-- read off the store's Street View front (tools/storefronts/store_colours.csv)
		colors = { hexColor(shapeData.sc), hexColor(shapeData.st) }
	end
	local board = newPart(model, "StoreSign", Vector3.new(width, 2.6, 0.5), look, Enum.Material.SmoothPlastic, colors[1])
	board.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.4
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = string.upper(shapeData.name)
	text.TextColor3 = colors[2]
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.Parent = gui
	model:SetAttribute("StoreName", shapeData.name)
end

local function buildFootprintBuilding(parent, building, shapeData)
	local style = BUILDING_STYLES[shapeData.style] or BUILDING_STYLES.generic
	local seed = tonumber(building.id) or 1
	local wall = pick(style.walls, seed, 1)
	local material = style.material
	if style.alt and seed % 3 == 0 then
		material = style.alt
	end
	-- facade colour / material measured from street imagery
	-- (tools/storefronts/facade_from_streetview.py -> build_building_tiles.py)
	if shapeData.wc then
		wall = Color3.fromRGB(
			math.floor(shapeData.wc / 65536) % 256 * 0.95,
			math.floor(shapeData.wc / 256) % 256 * 0.95,
			shapeData.wc % 256 * 0.95)
		if shapeData.wm == "b" then
			material = Enum.Material.Brick
		elseif shapeData.wm == "s" then
			material = Enum.Material.SmoothPlastic
		end
	end
	local landmark = shapeData.lm and LANDMARK_STYLES[shapeData.lm]
	if landmark then
		wall, material = landmark.wall, landmark.material
	end
	local heightStuds = math.max(shapeData.h * S, 6)
	local yaw = CFrame.Angles(0, math.rad(shapeData.a), 0)
	local model = Instance.new("Model")
	model.Name = tostring(shapeData.name or building.id)
	model:SetAttribute("ChesterBuildingId", tostring(building.id))
	model:SetAttribute("BuildingStyle", shapeData.style)
	model:SetAttribute("SourceHeightMeters", shapeData.h)
	local gable = style.roof == "gable" and #shapeData.r <= 3
	local roofColor = style.roofs and pick(style.roofs, seed, 2)
	-- measured roof colour from the 2025 aerial (tools/build_building_tiles.py),
	-- slightly darkened: the orthophoto is brighter than in-game lighting
	local measured = shapeData.rc and Color3.fromRGB(
		math.floor(shapeData.rc / 65536) % 256 * 0.9,
		math.floor(shapeData.rc / 256) % 256 * 0.9,
		shapeData.rc % 256 * 0.9)
	if measured then
		roofColor = measured
	end
	local built = 0
	local signRect
	local builtRects = {}
	local kitRects, kitHomes = nil, false
	-- real-building facades (RealBuildings.lua) inside WorldConfig.REAL_BUILDINGS_REGION
	local realCtx
	local region = WorldConfig.REAL_BUILDINGS_REGION
	if region and not landmark and shapeData.r[1] then
		local fx, fz = sourceToStuds(shapeData.r[1][1], shapeData.r[1][2])
		local extra = WorldConfig.REAL_BUILDINGS_EXTRA and WorldConfig.REAL_BUILDINGS_EXTRA[tostring(building.id)]
		local core = extra or (fx >= region.minX and fx <= region.maxX and fz >= region.minZ and fz <= region.maxZ)
		-- city-wide (WorldConfig.REAL_BUILDINGS_ALL): every home and store; full
		-- detail in the core, the lite house kit everywhere else
		if core or WorldConfig.REAL_BUILDINGS_ALL then
			local rects = {}
			for _, rc in ipairs(shapeData.r) do
				local rx, rz = sourceToStuds(rc[1], rc[2])
				table.insert(rects, { frame = CFrame.new(rx, 0, rz) * yaw, along = math.max(rc[3] * S, 1),
					across = math.max(rc[4] * S, 1), x = rx, z = rz })
			end
			local shops = {}
			local sbIndex
			for _, sh in ipairs(shapeData.ss or {}) do
				shops[sh[2]] = { name = sh[1], front = sh[3], corner = shapeData.fb2, placeId = sh[6], signBg = hexColor(sh[4]) }
			end
			if shapeData.sb and shapeData.name then
				-- the verified store: the section reaching furthest toward its street front
				local rad = math.rad(shapeData.sb)
				local frontDir = Vector3.new(math.sin(rad), 0, -math.cos(rad))
				local best, bestScore
				for i, rr in ipairs(rects) do
					-- (not a sliver section: 5 Points is the strip's east-end store)
					if not shops[i - 1] and math.min(rr.along, rr.across) >= 12 then
						local n = faceToward(rr.frame, shapeData.sb)
						local extent = (n.X ~= 0) and rr.along / 2 or rr.across / 2
						local score = Vector3.new(rr.x, 0, rr.z):Dot(frontDir) + extent
						if not best or score > bestScore then best, bestScore = i - 1, score end
					end
				end
				if best then
					-- (fb: the face of the building nearest its street, from
					-- tools/add_building_fronts.py; sb is only a direction)
					shops[best] = { name = shapeData.name, front = shapeData.fb or shapeData.sb, corner = shapeData.fb2,
						placeId = "survey", signBg = shapeData.sc and hexColor(shapeData.sc) or nil }
					sbIndex = best
				end
			end
			if shapeData.gs and next(shops) == nil and shapeData.fb then
				-- a main-street shopfront ground floor with no named business
				local big, bigArea = 0, -1
				for i, rr in ipairs(rects) do
					if rr.along * rr.across > bigArea then big, bigArea = i - 1, rr.along * rr.across end
				end
				shops[big] = { front = shapeData.fb, corner = shapeData.fb2 }
			end
			realCtx = { sbIndex = sbIndex, rects = rects, shops = shops, front = shapeData.fb, corner = shapeData.fb2,
				porch = shapeData.pb ~= nil, porchDepth = shapeData.pd and shapeData.pd * S or nil,
				style = shapeData.style, material = material, wall = wall,
				seed = seed, buildingId = tostring(building.id), applyFacade = applyFacade, stats = RealBuildings.stats,
				lite = not core }
		end
	end
	for rectIndex, rect in ipairs(shapeData.r) do
		local x, z = sourceToStuds(rect[1], rect[2])
		local along, across = math.max(rect[3] * S, 1), math.max(rect[4] * S, 1)
		local frame = CFrame.new(x, 0, z) * yaw
		-- ground: centre for the roofline, lowest corner for the foundation
		local centreGround = terrainY(x, z)
		if centreGround then
			local lowest = centreGround
			for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
				local p = frame * Vector3.new(corner[1] * along / 2, 0, corner[2] * across / 2)
				local g = terrainY(p.X, p.Z)
				if g and g < lowest then lowest = g end
			end
			local rise = gable and math.clamp(math.min(along, across) * 0.32, 3, 14) or 0
			local wallTop = centreGround + WorldConfig.BUILDING_BASE_Y_STUDS + heightStuds - rise * 0.6
			local base = lowest - 1.5
			local floors = shapeData.floors or math.max(1, math.floor(shapeData.h / 3.2 + 0.5))
			local storey = math.clamp(heightStuds / floors, 8, 13)
			local groundKind = GROUND_FOR_STYLE[shapeData.style]
			if shapeData.gs then
				-- main-street block built to the sidewalk (tools/add_porches.py)
				groundKind = "storefront"
			end
			if landmark then
				groundKind = nil   -- the arched front replaces the generic textures
			end
			local streetLevel = centreGround - 0.4
			local groundTop = streetLevel + (groundKind == "storefront" and math.max(storey, 12) or storey)
			local realShop = realCtx and realCtx.shops[rectIndex - 1]
			if realShop and math.min(along, across) < 12 then
				realShop = nil   -- a sliver section: too small to walk into (sign only)
			end
			local realHome = realCtx and not realShop and GROUND_FOR_STYLE[shapeData.style] == "residential"
			-- outside the core the house kit is built on the clients near it
			-- (Exit6HouseDecor.client); the server keeps the plain block and
			-- leaves the description (Exit6Kit) - Xbox could not hold it city-wide
			local decorHome = realHome and realCtx.lite
			if decorHome then realHome = false end
			if realHome then realCtx.homeBuilt = true end
			if realCtx and realCtx.lite then
				kitRects = kitRects or {}
				table.insert(kitRects, string.format("%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d", x, z, along, across, streetLevel, base,
					wallTop, storey, decorHome and 1 or 0))
				if decorHome then kitHomes = true end
			end
			if realShop or realHome then
				local rr = { frame = frame, along = along, across = across, streetLevel = streetLevel, base = base,
					wallTop = wallTop, storey = storey }
				if realShop then
					RealBuildings.Store(model, rr, realCtx, realShop)
					RealBuildings.stats.stores += 1
				else
					RealBuildings.Home(model, rr, realCtx)
					RealBuildings.stats.homes += 1
				end
			elseif groundKind and wallTop - groundTop >= 4 and math.min(along, across) >= 10 then
				-- ground storey (doors / shopfronts) is exactly one texture tile
				-- tall from street level; the floors above keep the windows
				local ground = newPart(model, "GroundStorey", Vector3.new(along, groundTop - streetLevel, across),
					CFrame.new(x, (groundTop + streetLevel) / 2, z) * yaw, material, wall)
				if shapeData.gc then
					-- painted shopfront storey seen in the store's Street View capture
					ground.Color = hexColor(shapeData.gc)
					ground.Material = Enum.Material.SmoothPlastic
				end
				ground:SetAttribute("GroundY", centreGround)
				applyGroundStorey(ground, groundKind)
				local upper = newPart(model, "Walls", Vector3.new(along, wallTop - groundTop, across),
					CFrame.new(x, (wallTop + groundTop) / 2, z) * yaw, material, wall)
				applyFacade(upper, shapeData.style, storey)
				if streetLevel - base > 0.3 then
					newPart(model, "Foundation", Vector3.new(along, streetLevel - base, across),
						CFrame.new(x, (streetLevel + base) / 2, z) * yaw, Enum.Material.Concrete, Color3.fromRGB(128, 124, 118))
				end
			else
				local block = newPart(model, "Walls", Vector3.new(along, wallTop - base, across),
					CFrame.new(x, (wallTop + base) / 2, z) * yaw, material, wall)
				block:SetAttribute("GroundY", centreGround)
				if shapeData.gc then
					-- one-storey store: the painted shopfront is the whole wall
					block.Color = hexColor(shapeData.gc)
					block.Material = Enum.Material.SmoothPlastic
				end
				if not landmark then
					applyFacade(block, shapeData.style, storey)
				end
			end
			if realHome then
				-- the house kit built this section's roof (HouseKit.lua)
			elseif style.roof == "cornice" then
				newPart(model, "Cornice", Vector3.new(along + 0.8, 0.9, across + 0.8),
					CFrame.new(x, wallTop + 0.45, z) * yaw, Enum.Material.Concrete, roofColor or style.top)
			elseif gable then
				buildGable(model, "Roof", CFrame.new(x, wallTop, z) * yaw, along + 1.2, across + 1.2, rise,
					roofColor or Color3.fromRGB(70, 66, 62))
			elseif measured then
				newPart(model, "Roof", Vector3.new(along, 0.4, across),
					CFrame.new(x, wallTop + 0.2, z) * yaw, Enum.Material.Concrete, measured)
			end
			built += 1
			local area = along * across
			local info = { index = rectIndex - 1, x = x, z = z, along = along, across = across, area = area,
				bandY = math.min(streetLevel + math.max(storey, 12) - 1.4, wallTop - 1.6),
				streetLevel = streetLevel, porchTop = math.min(streetLevel + storey, wallTop - 1),
				wallTop = wallTop, storey = storey }
			table.insert(builtRects, info)
			if not signRect or area > signRect.area then
				signRect = info
			end
		end
	end
	if built > 0 and shapeData.sb and shapeData.name and signRect and realCtx and realCtx.sbIndex then
		-- real buildings: the verified sign goes on the store's own section, on
		-- its entrance face
		for _, r in ipairs(builtRects) do
			if r.index == realCtx.sbIndex then
				local view = setmetatable({ sb = realCtx.shops[realCtx.sbIndex].front }, { __index = shapeData })
				buildStoreSign(model, view, r, yaw)
				break
			end
		end
	elseif built > 0 and shapeData.sb and shapeData.name and signRect then
		-- the sign goes on the block that reaches furthest toward the street front
		local rad = math.rad(shapeData.sb)
		local front = Vector3.new(math.sin(rad), 0, -math.cos(rad))
		local best, bestScore = signRect, -math.huge
		for _, r in ipairs(builtRects) do
			local frame = CFrame.new(r.x, 0, r.z) * yaw
			local n = faceToward(frame, shapeData.sb)
			local extent = (n.X ~= 0) and r.along / 2 or r.across / 2
			local span = (n.X ~= 0) and r.across or r.along
			local score = Vector3.new(r.x, 0, r.z):Dot(front) + extent
			if span >= 8 and score > bestScore + 0.5 then
				best, bestScore = r, score
			end
		end
		buildStoreSign(model, shapeData, best, yaw)
	end
	if built > 0 and shapeData.ss then
		local names = {}
		for _, shop in ipairs(shapeData.ss) do
			for _, r in ipairs(builtRects) do
				if r.index == shop[2] then
					buildShopSign(model, r, yaw, shop[1], shop[3], shop[4], shop[5])
					table.insert(names, shop[1])
					break
				end
			end
		end
		if #names > 0 then model:SetAttribute("Shops", table.concat(names, " | ")) end
	end
	if built > 0 and shapeData.pb and shapeData.pd and signRect and not (realCtx and realCtx.homeBuilt) then
		buildPorch(model, shapeData, signRect, yaw)
	end
	if built > 0 and shapeData.lm and shapeData.lb then
		for _, r in ipairs(builtRects) do
			buildArchedFront(model, r, yaw, shapeData.lb)
		end
	end
	if built > 0 and kitHomes and realCtx then
		model:SetAttribute("Exit6Kit", string.format("%s|%s|%d|%.2f|%s|%s|%d,%d,%d|%.3f", tostring(realCtx.front or ""),
			tostring(realCtx.corner or ""), realCtx.porch and 1 or 0, realCtx.porchDepth or 0, tostring(shapeData.style),
			realCtx.material.Name, math.floor(realCtx.wall.R * 255 + 0.5), math.floor(realCtx.wall.G * 255 + 0.5),
			math.floor(realCtx.wall.B * 255 + 0.5), shapeData.a) .. ";" .. table.concat(kitRects, ";"))
	end
	if built > 0 then
		model.Parent = parent
		return true
	end
	model:Destroy()
	return false
end

local function buildBuilding(parent, building, shapes)
	local shapeData = shapes and shapes[tostring(building.id)]
	if shapeData and buildFootprintBuilding(parent, building, shapeData) then
		return
	end
	local heightStuds = math.max((building.height_m or 9.15) * S, 2)
	local widthStuds = math.max((building.width_m or 5) * S, 1)
	local depthStuds = math.max((building.depth_m or 8) * S, 1)
	local x, z = sourceToStuds(building.x_m, building.z_m)
	local groundY = terrainY(x, z)
	if groundY == nil then return end
	local y = groundY + WorldConfig.BUILDING_BASE_Y_STUDS + heightStuds / 2
	local part = Instance.new("Part")
	part.Name = building.name or building.id or "Building"
	part.Anchored = true
	part.CanCollide = true
	part.Material = WorldConfig.BUILDING_MATERIAL
	part.Size = Vector3.new(widthStuds, heightStuds, depthStuds)
	part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(building.yaw_deg or 0), 0)
	part.Parent = parent
	part:SetAttribute("ChesterBuildingId", tostring(building.id or ""))
	part:SetAttribute("SourceHeightMeters", building.height_m or 9.15)
	part:SetAttribute("GroundY", groundY)
end

function TileBuilderV2.Stats()
	return omissions, highwayStats
end

function TileBuilderV2.Build(tileModule)
	if not prepared then error("TileBuilderV2.Prepare(modules) must run before Build") end
	local tile = require(tileModule)
	local tileId = tostring(tile.tile_id or tileModule.Name)
	local workspaceRoot = workspace:FindFirstChild("ChesterWorld")
	if not workspaceRoot then
		workspaceRoot = Instance.new("Folder")
		workspaceRoot.Name = "ChesterWorld"
		workspaceRoot.Parent = workspace
	end
	local tileFolder = workspaceRoot:FindFirstChild(tileId)
	if tileFolder then tileFolder:Destroy() end
	tileFolder = Instance.new("Folder")
	tileFolder.Name = tileId
	tileFolder:SetAttribute("TileId", tileId)
	tileFolder.Parent = workspaceRoot
	local roadsFolder = makeFolder(tileFolder, "Roads")
	local sidewalksFolder = makeFolder(tileFolder, "Sidewalks")
	local intersectionsFolder = makeFolder(tileFolder, "Intersections")
	local markingsFolder = makeFolder(tileFolder, "RoadMarkings")
	local signsFolder = makeFolder(tileFolder, "StreetSigns")
	local buildingsFolder = makeFolder(tileFolder, "Buildings")
	for index, road in ipairs(tile.roads or {}) do
		if not Registry.Suppressed(road.grade_group) then
			buildRoad(roadsFolder, sidewalksFolder, markingsFolder, road)
		end
		if index % ROAD_YIELD_EVERY == 0 then task.wait() end
	end
	buildIntersections(intersectionsFolder, markingsFolder, signsFolder, tileId)
	local shapeModule = BuildingTiles and BuildingTiles:FindFirstChild(tileId)
	local shapes = shapeModule and require(shapeModule)
	-- yield on a time budget as well as a count: a live server must keep
	-- answering the network while the city builds (Xbox error 279)
	local sliceStart = os.clock()
	for index, building in ipairs(tile.buildings or {}) do
		buildBuilding(buildingsFolder, building, shapes)
		if index % BUILDING_YIELD_EVERY == 0 or os.clock() - sliceStart > 0.015 then
			task.wait()
			sliceStart = os.clock()
		end
	end
	return tileFolder
end

return TileBuilderV2
