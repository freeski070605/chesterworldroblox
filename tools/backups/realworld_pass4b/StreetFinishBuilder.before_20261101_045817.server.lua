-- ChesterWorld — StreetFinishBuilder.server.lua
--
-- Pass 4:
--   * intersection asphalt pads at true multi-leg junctions
--   * one-piece concrete sidewalk/curb underlay for eligible streets
--   * seals many remaining terrain/road edge artifacts
--
-- Designed to run AFTER RoadTerrainConformer.
--
-- It does NOT modify Terrain.
-- It does NOT move buildings.
-- It does NOT alter the locked ChesterWorld X/Z orientation.

local Workspace = game:GetService("Workspace")

local ENABLED = true

local MIN_ROAD_WIDTH_FOR_SIDEWALK = 17.0
local MIN_ROAD_LENGTH_FOR_SIDEWALK = 22.0
local SIDEWALK_BAND_PER_SIDE = 3.5
local SIDEWALK_END_OVERLAP = 0.65
local SIDEWALK_THICKNESS = 0.55
local SIDEWALK_DROP_BELOW_ROAD_TOP = 0.18

local INTERSECTION_SNAP = 7.0
local MIN_INTERSECTION_LEGS = 3
local PAD_EXTRA = 3.0
local PAD_MIN_SIZE = 10.0
local PAD_MAX_SIZE = 58.0
local PAD_THICKNESS = 0.45
local PAD_SURFACE_LIFT = 0.06

local REQUIRED_CONFORM_RATIO = 0.95
local WAIT_STEP = 0.5
local MAX_WAIT = 90

if not ENABLED then
	return
end

local world = Workspace:WaitForChild("ChesterWorld")

local function collectRoadParts()
	local roads = {}

	for _, tileFolder in ipairs(world:GetChildren()) do
		local roadFolder = tileFolder:FindFirstChild("Roads")
		if roadFolder then
			for _, obj in ipairs(roadFolder:GetDescendants()) do
				if obj:IsA("BasePart") then
					table.insert(roads, obj)
				end
			end
		end
	end

	return roads
end

local function inferAxes(part: BasePart)
	if part.Size.X >= part.Size.Z then
		return "X", part.Size.X, part.Size.Z, part.CFrame.RightVector
	else
		return "Z", part.Size.Z, part.Size.X, part.CFrame.LookVector
	end
end

local function surfaceTop(part: BasePart)
	return part.Position + part.CFrame.UpVector * (part.Size.Y / 2)
end

local function endpointPair(part: BasePart)
	local axisKind, length, width, longVector = inferAxes(part)

	local a = part.Position - longVector * (length / 2)
	local b = part.Position + longVector * (length / 2)

	return a, b, width, axisKind, length
end

local function countConformed(roads)
	local n = 0
	for _, road in ipairs(roads) do
		if road:GetAttribute("CW_TerrainConformed") == true then
			n += 1
		end
	end
	return n
end

local function waitForConformer()
	local elapsed = 0
	local lastCount = -1
	local stableTicks = 0

	while elapsed < MAX_WAIT do
		local roads = collectRoadParts()
		local total = #roads
		local conformed = countConformed(roads)
		local ratio = total > 0 and (conformed / total) or 0

		if total > 0 and total == lastCount then
			stableTicks += 1
		else
			stableTicks = 0
			lastCount = total
		end

		if total > 0 and stableTicks >= 2 and ratio >= REQUIRED_CONFORM_RATIO then
			return roads, conformed, ratio
		end

		task.wait(WAIT_STEP)
		elapsed += WAIT_STEP
	end

	local roads = collectRoadParts()
	local conformed = countConformed(roads)
	local ratio = #roads > 0 and conformed / #roads or 0
	return roads, conformed, ratio
end

local function clearOldFinish()
	local old = world:FindFirstChild("StreetFinish")
	if old then
		old:Destroy()
	end

	local finish = Instance.new("Folder")
	finish.Name = "StreetFinish"
	finish.Parent = world

	local sidewalks = Instance.new("Folder")
	sidewalks.Name = "SidewalkBases"
	sidewalks.Parent = finish

	local intersections = Instance.new("Folder")
	intersections.Name = "IntersectionPads"
	intersections.Parent = finish

	return finish, sidewalks, intersections
end

local function makeSidewalkBase(road: BasePart, parent: Instance)
	local axisKind, length, width = inferAxes(road)

	if width < MIN_ROAD_WIDTH_FOR_SIDEWALK then
		return nil, "narrow"
	end

	if length < MIN_ROAD_LENGTH_FOR_SIDEWALK then
		return nil, "short"
	end

	local top = surfaceTop(road)
	local up = road.CFrame.UpVector

	local sidewalkTop = top - up * SIDEWALK_DROP_BELOW_ROAD_TOP
	local center = sidewalkTop - up * (SIDEWALK_THICKNESS / 2)

	local size
	if axisKind == "X" then
		size = Vector3.new(
			road.Size.X + SIDEWALK_END_OVERLAP * 2,
			SIDEWALK_THICKNESS,
			road.Size.Z + SIDEWALK_BAND_PER_SIDE * 2
		)
	else
		size = Vector3.new(
			road.Size.X + SIDEWALK_BAND_PER_SIDE * 2,
			SIDEWALK_THICKNESS,
			road.Size.Z + SIDEWALK_END_OVERLAP * 2
		)
	end

	local base = Instance.new("Part")
	base.Name = "CW_SidewalkBase"
	base.Anchored = true
	base.CanCollide = true
	base.CanTouch = false
	base.CanQuery = true
	base.CastShadow = true
	base.Material = Enum.Material.Concrete
	base.Color = Color3.fromRGB(132, 132, 126)
	base.Size = size

	local rotationOnly = road.CFrame - road.CFrame.Position
	base.CFrame = CFrame.new(center) * rotationOnly

	base:SetAttribute("CW_StreetFinish", true)
	base:SetAttribute("CW_SourceRoad", road.Name)

	base.Parent = parent

	return base, "created"
end

local function snapKey(position: Vector3)
	local sx = math.floor(position.X / INTERSECTION_SNAP + 0.5)
	local sz = math.floor(position.Z / INTERSECTION_SNAP + 0.5)
	return tostring(sx) .. ":" .. tostring(sz)
end

local function addEndpoint(nodes, position, road, width)
	local key = snapKey(position)

	local node = nodes[key]
	if not node then
		node = {
			points = {},
			roads = {},
			maxWidth = 0,
		}
		nodes[key] = node
	end

	table.insert(node.points, position)
	table.insert(node.roads, road)
	node.maxWidth = math.max(node.maxWidth, width)
end

local function uniqueRoadCount(node)
	local seen = {}
	local count = 0

	for _, road in ipairs(node.roads) do
		if not seen[road] then
			seen[road] = true
			count += 1
		end
	end

	return count
end

local function makeIntersectionPad(node, parent)
	local legs = uniqueRoadCount(node)
	if legs < MIN_INTERSECTION_LEGS then
		return nil, "not_intersection"
	end

	local sum = Vector3.zero
	local highestRoadTop = -math.huge
	local representative = nil

	for _, point in ipairs(node.points) do
		sum += point
	end

	for _, road in ipairs(node.roads) do
		local top = surfaceTop(road)
		if top.Y > highestRoadTop then
			highestRoadTop = top.Y
			representative = road
		end
	end

	if not representative then
		return nil, "no_representative"
	end

	local avg = sum / #node.points

	local sizeXZ = math.clamp(
		node.maxWidth + PAD_EXTRA * 2,
		PAD_MIN_SIZE,
		PAD_MAX_SIZE
	)

	local pad = Instance.new("Part")
	pad.Name = "CW_IntersectionPad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = true
	pad.CastShadow = true
	pad.Material = representative.Material
	pad.Color = representative.Color
	pad.Size = Vector3.new(sizeXZ, PAD_THICKNESS, sizeXZ)

	local targetTopY = highestRoadTop + PAD_SURFACE_LIFT
	pad.Position = Vector3.new(
		avg.X,
		targetTopY - PAD_THICKNESS / 2,
		avg.Z
	)

	pad:SetAttribute("CW_StreetFinish", true)
	pad:SetAttribute("CW_IntersectionLegs", legs)
	pad:SetAttribute("CW_MaxRoadWidth", node.maxWidth)

	pad.Parent = parent

	return pad, "created"
end

local roads, conformedCount, conformRatio = waitForConformer()

local _, sidewalkFolder, intersectionFolder = clearOldFinish()

local sidewalksCreated = 0
local sidewalksNarrow = 0
local sidewalksShort = 0

for index, road in ipairs(roads) do
	if road:GetAttribute("CW_TerrainConformed") == true then
		local _, status = makeSidewalkBase(road, sidewalkFolder)

		if status == "created" then
			sidewalksCreated += 1
		elseif status == "narrow" then
			sidewalksNarrow += 1
		elseif status == "short" then
			sidewalksShort += 1
		end
	end

	if index % 500 == 0 then
		task.wait()
	end
end

local nodes = {}

for index, road in ipairs(roads) do
	if road:GetAttribute("CW_TerrainConformed") == true then
		local a, b, width = endpointPair(road)

		addEndpoint(nodes, a, road, width)
		addEndpoint(nodes, b, road, width)
	end

	if index % 800 == 0 then
		task.wait()
	end
end

local nodeCount = 0
local intersectionsCreated = 0

for _, node in pairs(nodes) do
	nodeCount += 1

	local _, status = makeIntersectionPad(node, intersectionFolder)
	if status == "created" then
		intersectionsCreated += 1
	end

	if nodeCount % 500 == 0 then
		task.wait()
	end
end

print(string.format(
	"[ChesterWorld StreetFinish] roads=%d conformed=%d ratio=%.4f sidewalks=%d skippedNarrow=%d skippedShort=%d nodes=%d intersections=%d",
	#roads,
	conformedCount,
	conformRatio,
	sidewalksCreated,
	sidewalksNarrow,
	sidewalksShort,
	nodeCount,
	intersectionsCreated
))
