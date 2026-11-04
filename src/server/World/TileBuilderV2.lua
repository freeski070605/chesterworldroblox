local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

local HighwayProfile = require(script.Parent:WaitForChild("HighwayProfile"))

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

local function shouldBuildSidewalk(road)
	if truthy(road.bridge) or truthy(road.tunnel) then
		return false
	end
	local cls = roadClass(road)
	return cls ~= "motorway"
		and cls ~= "motorway_link"
		and cls ~= "trunk"
		and cls ~= "trunk_link"
		and cls ~= "service"
		and cls ~= "alley"
end

-- Only the highway corridor may recover terrain-rejected strips. County source
-- sometimes labels I-95 as "secondary"; match its exact name as well as class.
-- Keep the original steep-grade rejection for neighborhood roads/sidewalks.
local function isHighwayCorridor(attributes)
    if type(attributes) ~= "table" then return false end
    local cls = string.lower(tostring(attributes.CW_RoadClass or ""))
    local name = string.lower(tostring(attributes.ChesterStreet or ""))
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
					table.insert(entries, { road = road, tileId = tileId })
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
	if HighwayProfile.Enabled() then
		print(("[ChesterWorld HighwayProfile] %s seconds=%.1f"):format(HighwayProfile.Summary(), os.clock() - profileStart))
		for _, line in ipairs(HighwayProfile.Stats().pinConflictList) do
			warn("[ChesterWorld HighwayProfilePinConflict] " .. line)
		end
	end
	for index, entry in ipairs(entries) do
		local road = entry.road
		addEndpoint(globalIntersectionNodes, entry.tileId, road.x1, road.z1, road.x2, road.z2, road, 1)
		addEndpoint(globalIntersectionNodes, entry.tileId, road.x2, road.z2, road.x1, road.z1, road, 2)
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
	local a, b, grade = groundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset)
	if not a or not b then
		if parent.Name == "Roads" and math.abs(x2 - x1) + math.abs(z2 - z1) > 0.1 then
			omissions.noTerrainPieces += 1
			noteOmission("no-terrain", (x1 + x2) / 2, (z1 + z2) / 2, " " .. tostring(name))
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
	}
end

local function buildSidewalkPair(sidewalksFolder, streetName, a2D, b2D, roadWidth)
	if not a2D or not b2D then return end
	local perpendicular = horizontalPerpendicular(a2D, b2D)
	local sidewalkWidth = WorldConfig.SIDEWALK_WIDTH_STUDS
	local offsetDistance = roadWidth / 2 + WorldConfig.SIDEWALK_GAP_STUDS + sidewalkWidth / 2
	local sidewalkSurfaceOffset = WorldConfig.SIDEWALK_HEIGHT_STUDS / 2 + 0.15
	for _, sign in ipairs({ -1, 1 }) do
		local offset = perpendicular * offsetDistance * sign
		buildAdaptiveCenterStrip(
			sidewalksFolder, "Sidewalk",
			a2D.X + offset.X, a2D.Z + offset.Z,
			b2D.X + offset.X, b2D.Z + offset.Z,
			sidewalkWidth,
			WorldConfig.SIDEWALK_HEIGHT_STUDS,
			WorldConfig.SIDEWALK_MATERIAL,
			WorldConfig.SIDEWALK_COLOR,
			sidewalkSurfaceOffset, 0, 0,
			{ ChesterStreet = streetName, Side = sign < 0 and "Left" or "Right", CW_TileBuilderSidewalk = true }
		)
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
    buildAdaptiveCenterStrip(
        markingsFolder, "CenterLine",
        a2D.X, a2D.Z, b2D.X, b2D.Z,
        WorldConfig.CENTERLINE_WIDTH_STUDS,
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

local function buildBuilding(parent, building)
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
		buildRoad(roadsFolder, sidewalksFolder, markingsFolder, road)
		if index % ROAD_YIELD_EVERY == 0 then task.wait() end
	end
	buildIntersections(intersectionsFolder, markingsFolder, signsFolder, tileId)
	for index, building in ipairs(tile.buildings or {}) do
		buildBuilding(buildingsFolder, building)
		if index % BUILDING_YIELD_EVERY == 0 then task.wait() end
	end
	return tileFolder
end

return TileBuilderV2
