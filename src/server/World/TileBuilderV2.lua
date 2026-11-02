local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

local TileBuilderV2 = {}

local S = WorldConfig.STUDS_PER_METER
local CENTER_X_M = WorldConfig.WORLD_CENTER_X_M
local CENTER_Z_M = WorldConfig.WORLD_CENTER_Z_M

local ROAD_YIELD_EVERY = 20
local BUILDING_YIELD_EVERY = 40
local INTERSECTION_YIELD_EVERY = 80

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {workspace.Terrain}
terrainParams.IgnoreWater = false

local prepared = false
local globalIntersectionNodes = {}

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

local function gradeKeyForRoad(road)
	return tostring(gradeLevelForRoad(road))
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

local function safeGroundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset)
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

	if (gradeOffset or 0) == 0 then
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

local function endpointKeyFromStuds(x, z, gradeKey)
	local q = WorldConfig.INTERSECTION_ENDPOINT_QUANTIZE_STUDS
	return
		tostring(math.floor(x / q + 0.5))
		.. ":"
		.. tostring(math.floor(z / q + 0.5))
		.. ":g"
		.. tostring(gradeKey or "0")
end

local function endpointKeyFromMeters(xMeters, zMeters, road)
	local x, z = sourceToStuds(xMeters, zMeters)
	return endpointKeyFromStuds(x, z, gradeKeyForRoad(road))
end

local function armKey(name, dir)
	local qx = math.floor(dir.X * 20 + (dir.X >= 0 and 0.5 or -0.5))
	local qz = math.floor(dir.Z * 20 + (dir.Z >= 0 and 0.5 or -0.5))
	return string.upper(name) .. ":" .. tostring(qx) .. ":" .. tostring(qz)
end

local function addEndpoint(nodes, tileId, xMeters, zMeters, otherXMeters, otherZMeters, road)
	local x, z = sourceToStuds(xMeters, zMeters)
	local ox, oz = sourceToStuds(otherXMeters, otherZMeters)
	local gradeLevel = gradeLevelForRoad(road)
	local key = endpointKeyFromStuds(x, z, tostring(gradeLevel))

	local node = nodes[key]
	if not node then
		node = {
			xSum = 0,
			zSum = 0,
			count = 0,
			maxWidth = 0,
			names = {},
			rawArms = {},
			arms = {},
			distinctNames = 0,
			isIntersection = false,
			isNamedIntersection = false,
			gradeLevel = gradeLevel,
			ownerTile = tileId,
			padSize = 0,
		}
		nodes[key] = node
	elseif tileId < node.ownerTile then
		node.ownerTile = tileId
	end

	local roadWidth = math.max((road.width_m or 7) * S, 3)

	node.xSum += x
	node.zSum += z
	node.count += 1
	node.maxWidth = math.max(node.maxWidth, roadWidth)

	local name = tostring(road.name or "")
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

		local uniqueArms = {}
		local armMap = {}

		for _, arm in ipairs(node.rawArms) do
			local key = armKey(arm.name, arm.dir)
			local existing = armMap[key]

			if not existing or arm.width > existing.width then
				armMap[key] = arm
			end
		end

		for _, arm in pairs(armMap) do
			table.insert(uniqueArms, arm)
		end

		table.sort(uniqueArms, function(a, b)
			local aa = math.atan2(a.dir.Z, a.dir.X)
			local ba = math.atan2(b.dir.Z, b.dir.X)
			return aa < ba
		end)

		node.arms = uniqueArms
		node.rawArms = nil
		node.distinctNames = distinctNames
		node.isNamedIntersection = distinctNames >= 2
		node.isIntersection =
			node.gradeLevel == 0
			and (#uniqueArms >= WorldConfig.INTERSECTION_MIN_DEGREE or node.isNamedIntersection)

		node.padSize = math.clamp(
			node.maxWidth * WorldConfig.INTERSECTION_SIZE_MULTIPLIER,
			WorldConfig.INTERSECTION_MIN_SIZE_STUDS,
			WorldConfig.INTERSECTION_MAX_SIZE_STUDS
		)
	end
end

function TileBuilderV2.Prepare(tileModules)
	globalIntersectionNodes = {}

	for moduleIndex, tileModule in ipairs(tileModules) do
		if tileModule:IsA("ModuleScript") then
			local ok, tile = pcall(require, tileModule)
			if ok and tile then
				local tileId = tostring(tile.tile_id or tileModule.Name)

				for roadIndex, road in ipairs(tile.roads or {}) do
					addEndpoint(globalIntersectionNodes, tileId, road.x1, road.z1, road.x2, road.z2, road)
					addEndpoint(globalIntersectionNodes, tileId, road.x2, road.z2, road.x1, road.z1, road)

					if roadIndex % 250 == 0 then
						task.wait()
					end
				end
			end
		end

		if moduleIndex % 8 == 0 then
			task.wait()
		end
	end

	finalizeNodes(globalIntersectionNodes)
	prepared = true

	local nodeCount = 0
	local intersections = 0
	for _, node in pairs(globalIntersectionNodes) do
		nodeCount += 1
		if node.isIntersection then
			intersections += 1
		end
	end

	print(("[ChesterWorld TileBuilderV2] prepared global road graph: nodes=%d intersections=%d"):format(
		nodeCount,
		intersections
	))
end

local function pointAlong2D(a, b, distanceFromA)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local length = math.sqrt(dx * dx + dz * dz)

	if length < 0.001 then
		return a
	end

	local t = math.clamp(distanceFromA / length, 0, 1)
	return Vector3.new(a.X + dx * t, 0, a.Z + dz * t)
end

local function distanceToSquareEdge(node, dir)
	if not node or not node.isIntersection then
		return 0
	end

	local half = node.padSize / 2
	local dominant = math.max(math.abs(dir.X), math.abs(dir.Z), 0.001)
	return half / dominant
end

local function trimDistanceForNode(node, dir, extraClearance)
	if not node or not node.isIntersection then
		return 0
	end

	return math.max(
		0,
		distanceToSquareEdge(node, dir)
			- WorldConfig.INTERSECTION_ROAD_OVERLAP_STUDS
			+ (extraClearance or 0)
	)
end

local function trimmedEndpoints(road, extraClearance)
	local x1, z1 = sourceToStuds(road.x1, road.z1)
	local x2, z2 = sourceToStuds(road.x2, road.z2)

	local a = Vector3.new(x1, 0, z1)
	local b = Vector3.new(x2, 0, z2)
	local length = horizontalLength(a, b)

	if length < 0.05 then
		return nil, nil
	end

	local startNode = globalIntersectionNodes[endpointKeyFromMeters(road.x1, road.z1, road)]
	local endNode = globalIntersectionNodes[endpointKeyFromMeters(road.x2, road.z2, road)]

	local startDir = (b - a).Unit
	local endDir = (a - b).Unit

	local trimStart = trimDistanceForNode(startNode, startDir, extraClearance)
	local trimEnd = trimDistanceForNode(endNode, endDir, extraClearance)

	if trimStart + trimEnd >= length - 1.0 then
		return nil, nil
	end

	local ta = pointAlong2D(a, b, trimStart)
	local tb = pointAlong2D(b, a, trimEnd)
	return ta, tb
end

local function shouldSplit(a, b, depth, surfaceOffset, gradeOffset)
	if depth >= WorldConfig.ROAD_MAX_SUBDIVISION_DEPTH then
		return false
	end

	if horizontalLength(a, b) > WorldConfig.ROAD_MAX_PIECE_LENGTH_STUDS then
		return true
	end

	local midX = (a.X + b.X) / 2
	local midZ = (a.Z + b.Z) / 2
	local groundMid = terrainY(midX, midZ)

	if groundMid == nil then
		return false
	end

	local terrainMidY = groundMid + surfaceOffset + (gradeOffset or 0)
	local linearMidY = (a.Y + b.Y) / 2

	return math.abs(terrainMidY - linearMidY) > WorldConfig.ROAD_TERRAIN_ERROR_STUDS
end

local function buildAdaptiveCenterStrip(
	parent,
	name,
	x1,
	z1,
	x2,
	z2,
	width,
	thickness,
	material,
	color,
	surfaceOffset,
	gradeOffset,
	depth,
	attributes
)
	depth = depth or 0
	gradeOffset = gradeOffset or 0

	local a, b = safeGroundPair(x1, z1, x2, z2, surfaceOffset, gradeOffset)
	if not a or not b then
		return
	end

	if shouldSplit(a, b, depth, surfaceOffset, gradeOffset) then
		local midX = (x1 + x2) / 2
		local midZ = (z1 + z2) / 2

		buildAdaptiveCenterStrip(
			parent, name,
			x1, z1, midX, midZ,
			width, thickness, material, color,
			surfaceOffset, gradeOffset,
			depth + 1, attributes
		)

		buildAdaptiveCenterStrip(
			parent, name,
			midX, midZ, x2, z2,
			width, thickness, material, color,
			surfaceOffset, gradeOffset,
			depth + 1, attributes
		)
		return
	end

	local part = makeStripPart(parent, name, a, b, width, thickness, material, color)

	if part and attributes then
		for key, value in pairs(attributes) do
			part:SetAttribute(key, value)
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
	if not a2D or not b2D then
		return
	end

	local perpendicular = horizontalPerpendicular(a2D, b2D)
	local sidewalkWidth = WorldConfig.SIDEWALK_WIDTH_STUDS
	local offsetDistance =
		roadWidth / 2
		+ WorldConfig.SIDEWALK_GAP_STUDS
		+ sidewalkWidth / 2

	local sidewalkSurfaceOffset = WorldConfig.SIDEWALK_HEIGHT_STUDS / 2 + 0.15

	for _, sign in ipairs({-1, 1}) do
		local offset = perpendicular * offsetDistance * sign

		buildAdaptiveCenterStrip(
			sidewalksFolder,
			"Sidewalk",
			a2D.X + offset.X,
			a2D.Z + offset.Z,
			b2D.X + offset.X,
			b2D.Z + offset.Z,
			sidewalkWidth,
			WorldConfig.SIDEWALK_HEIGHT_STUDS,
			WorldConfig.SIDEWALK_MATERIAL,
			WorldConfig.SIDEWALK_COLOR,
			sidewalkSurfaceOffset,
			0,
			0,
			{
				ChesterStreet = streetName,
				Side = sign < 0 and "Left" or "Right",
				CW_TileBuilderSidewalk = true,
			}
		)
	end
end

local function buildCenterLine(markingsFolder, road, roadWidth)
	if roadWidth < WorldConfig.CENTERLINE_MIN_ROAD_WIDTH_STUDS then
		return
	end

	local streetName = tostring(road.name or "")
	if streetName == "" or streetName == "Road" then
		return
	end

	local a2D, b2D = trimmedEndpoints(road, 0.5)
	if not a2D or not b2D then
		return
	end

	buildAdaptiveCenterStrip(
		markingsFolder,
		"CenterLine",
		a2D.X, a2D.Z,
		b2D.X, b2D.Z,
		WorldConfig.CENTERLINE_WIDTH_STUDS,
		WorldConfig.CENTERLINE_THICKNESS_STUDS,
		WorldConfig.MARKING_MATERIAL,
		WorldConfig.CENTERLINE_COLOR,
		WorldConfig.CENTERLINE_SURFACE_OFFSET_STUDS,
		gradeOffsetForRoad(road),
		0,
		{
			ChesterStreet = streetName,
			MarkingType = "CenterLine",
			CW_GradeLevel = gradeLevelForRoad(road),
		}
	)
end

local function buildRoad(roadsFolder, sidewalksFolder, markingsFolder, road)
	local roadWidth = math.max((road.width_m or 7) * S, 3)
	local streetName = tostring(road.name or "")
	local a2D, b2D = trimmedEndpoints(road, 0)

	if a2D and b2D then
		buildAdaptiveCenterStrip(
			roadsFolder,
			streetName ~= "" and streetName or "Road",
			a2D.X, a2D.Z,
			b2D.X, b2D.Z,
			roadWidth,
			WorldConfig.ROAD_THICKNESS_STUDS,
			WorldConfig.ROAD_MATERIAL,
			WorldConfig.ROAD_COLOR,
			WorldConfig.ROAD_SURFACE_OFFSET_STUDS,
			gradeOffsetForRoad(road),
			0,
			roadAttributes(road, roadWidth)
		)
	end

	if streetName ~= "" and streetName ~= "Road" and shouldBuildSidewalk(road) then
		local sidewalkA, sidewalkB = trimmedEndpoints(
			road,
			WorldConfig.SIDEWALK_INTERSECTION_EXTRA_TRIM_STUDS
		)

		buildSidewalkPair(sidewalksFolder, streetName, sidewalkA, sidewalkB, roadWidth)
	end

	buildCenterLine(markingsFolder, road, roadWidth)
end

local function uniqueIntersectionNames(node)
	local labels = {}
	for name in pairs(node.names) do
		table.insert(labels, name)
	end
	table.sort(labels)
	return labels
end

local function buildCrosswalkForArm(markingsFolder, node, arm)
	if arm.width < WorldConfig.CROSSWALK_MIN_ARM_WIDTH_STUDS then
		return
	end

	local dir = arm.dir
	if dir.Magnitude < 0.001 then
		return
	end

	local x = node.xSum / node.count
	local z = node.zSum / node.count
	local perpendicular = Vector3.new(-dir.Z, 0, dir.X)

	local baseSetback =
		distanceToSquareEdge(node, dir)
		+ WorldConfig.CROSSWALK_EDGE_CLEARANCE_STUDS

	local usableWidth = math.max(arm.width - 2.0, 4.0)
	local halfAcross = usableWidth / 2

	for stripe = 0, WorldConfig.CROSSWALK_STRIPE_COUNT - 1 do
		local along =
			baseSetback
			+ stripe
				* (
					WorldConfig.CROSSWALK_STRIPE_DEPTH_STUDS
					+ WorldConfig.CROSSWALK_STRIPE_GAP_STUDS
				)

		local center = Vector3.new(x, 0, z) + dir * along
		local p1 = center - perpendicular * halfAcross
		local p2 = center + perpendicular * halfAcross

		local a, b = safeGroundPair(
			p1.X, p1.Z,
			p2.X, p2.Z,
			WorldConfig.CROSSWALK_SURFACE_OFFSET_STUDS,
			0
		)

		local stripePart = makeStripPart(
			markingsFolder,
			"Crosswalk",
			a,
			b,
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
	local bestA = nil
	local bestB = nil
	local bestScore = math.huge

	for i = 1, #node.arms do
		local a = node.arms[i]
		if a.name ~= "" and a.name ~= "Road" then
			for j = i + 1, #node.arms do
				local b = node.arms[j]
				if b.name ~= "" and b.name ~= "Road" and b.name ~= a.name then
					local score = math.abs(a.dir:Dot(b.dir))
					if score < bestScore then
						bestScore = score
						bestA = a
						bestB = b
					end
				end
			end
		end
	end

	return bestA, bestB
end

local function buildStreetSign(signsFolder, node, labels)
	if
		not node.isNamedIntersection
		or node.maxWidth < WorldConfig.STREET_SIGN_TRIGGER_WIDTH_STUDS
		or #labels < 2
	then
		return
	end

	local armA, armB = bestPerpendicularArmPair(node)
	if not armA or not armB then
		return
	end

	local cornerDir = armA.dir + armB.dir
	if cornerDir.Magnitude < 0.001 then
		cornerDir = Vector3.new(1, 0, 1)
	end
	cornerDir = cornerDir.Unit

	local x = node.xSum / node.count
	local z = node.zSum / node.count
	local distance = node.padSize / 2 + WorldConfig.STREET_SIGN_CORNER_CLEARANCE_STUDS

	local signX = x + cornerDir.X * distance
	local signZ = z + cornerDir.Z * distance
	local ground = terrainY(signX, signZ)

	if ground == nil then
		return
	end

	local poleHeight = WorldConfig.STREET_SIGN_POLE_HEIGHT_STUDS

	local pole = Instance.new("Part")
	pole.Name = "StreetSign"
	pole.Anchored = true
	pole.CanCollide = false
	pole.Material = WorldConfig.SIGN_POLE_MATERIAL
	pole.Color = WorldConfig.SIGN_POLE_COLOR
	pole.Size = Vector3.new(
		WorldConfig.STREET_SIGN_POLE_THICKNESS_STUDS,
		poleHeight,
		WorldConfig.STREET_SIGN_POLE_THICKNESS_STUDS
	)
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

local function intersectionFrame(x, z, padSize)
	local centerGround = terrainY(x, z)
	if centerGround == nil then
		return nil
	end

	local sample = math.clamp(padSize * 0.28, 4, 12)
	local east = terrainY(x + sample, z) or centerGround
	local west = terrainY(x - sample, z) or centerGround
	local south = terrainY(x, z + sample) or centerGround
	local north = terrainY(x, z - sample) or centerGround

	local gradeX = math.clamp(
		(east - west) / (sample * 2),
		-WorldConfig.INTERSECTION_MAX_GRADE,
		WorldConfig.INTERSECTION_MAX_GRADE
	)
	local gradeZ = math.clamp(
		(south - north) / (sample * 2),
		-WorldConfig.INTERSECTION_MAX_GRADE,
		WorldConfig.INTERSECTION_MAX_GRADE
	)

	local up = Vector3.new(-gradeX, 1, -gradeZ).Unit
	local right = Vector3.new(1, gradeX, 0).Unit
	local back = right:Cross(up).Unit
	right = up:Cross(back).Unit

	return CFrame.fromMatrix(
		Vector3.new(x, centerGround + WorldConfig.ROAD_SURFACE_OFFSET_STUDS, z),
		right,
		up,
		back
	)
end

local function buildIntersections(parent, markingsFolder, signsFolder, tileId)
	local processed = 0

	for _, node in pairs(globalIntersectionNodes) do
		if node.ownerTile == tileId and node.isIntersection then
			processed += 1

			local x = node.xSum / node.count
			local z = node.zSum / node.count
			local frame = intersectionFrame(x, z, node.padSize)

			if frame then
				local pad = Instance.new("Part")
				pad.Name = "Intersection"
				pad.Anchored = true
				pad.CanCollide = true
				pad.CanTouch = true
				pad.CanQuery = true
				pad.Material = WorldConfig.INTERSECTION_MATERIAL
				pad.Color = WorldConfig.INTERSECTION_COLOR
				pad.TopSurface = Enum.SurfaceType.Smooth
				pad.BottomSurface = Enum.SurfaceType.Smooth
				pad.Size = Vector3.new(
					node.padSize,
					WorldConfig.ROAD_THICKNESS_STUDS + 0.08,
					node.padSize
				)
				pad.CFrame = frame
				pad:SetAttribute("CW_IntersectionPad", true)
				pad:SetAttribute("CW_GradeLevel", 0)
				pad.Parent = parent

				local labels = uniqueIntersectionNames(node)
				if #labels > 0 then
					pad:SetAttribute("Intersection", table.concat(labels, " & "))
				end

				if node.isNamedIntersection and node.maxWidth >= WorldConfig.CROSSWALK_TRIGGER_WIDTH_STUDS then
					for _, arm in ipairs(node.arms) do
						buildCrosswalkForArm(markingsFolder, node, arm)
					end
				end

				buildStreetSign(signsFolder, node, labels)
			end
		end

		if processed > 0 and processed % INTERSECTION_YIELD_EVERY == 0 then
			task.wait()
		end
	end
end

local function buildBuilding(parent, building)
	local heightStuds = math.max((building.height_m or 9.15) * S, 2)
	local widthStuds = math.max((building.width_m or 5) * S, 1)
	local depthStuds = math.max((building.depth_m or 8) * S, 1)

	local x, z = sourceToStuds(building.x_m, building.z_m)
	local groundY = terrainY(x, z)
	if groundY == nil then
		return
	end

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

function TileBuilderV2.Build(tileModule)
	if not prepared then
		error("TileBuilderV2.Prepare(modules) must run before Build")
	end

	local tile = require(tileModule)
	local tileId = tostring(tile.tile_id or tileModule.Name)

	local workspaceRoot = workspace:FindFirstChild("ChesterWorld")
	if not workspaceRoot then
		workspaceRoot = Instance.new("Folder")
		workspaceRoot.Name = "ChesterWorld"
		workspaceRoot.Parent = workspace
	end

	local tileFolder = workspaceRoot:FindFirstChild(tileId)
	if tileFolder then
		tileFolder:Destroy()
	end

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

		if index % ROAD_YIELD_EVERY == 0 then
			task.wait()
		end
	end

	buildIntersections(intersectionsFolder, markingsFolder, signsFolder, tileId)

	for index, building in ipairs(tile.buildings or {}) do
		buildBuilding(buildingsFolder, building)

		if index % BUILDING_YIELD_EVERY == 0 then
			task.wait()
		end
	end

	return tileFolder
end

return TileBuilderV2
