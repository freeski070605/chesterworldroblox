-- ChesterWorld — StreetFinishBuilder.server.lua
-- Pass 4B: corrected street edge treatment.
--
-- Replaces the wide concrete-underlay experiment with:
--   * narrow left/right sidewalk strips OUTSIDE the road footprint
--   * smaller intersection pads
--   * automatic cleanup of prior StreetFinish output
--
-- Runs after RoadTerrainConformer by waiting for terrain-conformed road attrs.

local Workspace = game:GetService("Workspace")

local world = Workspace:WaitForChild("ChesterWorld")

local ENABLED = true

-- Wait for road terrain conformance.
local REQUIRED_CONFORM_RATIO = 0.95
local WAIT_STEP = 0.5
local MAX_WAIT = 90

-- Sidewalk eligibility.
local MIN_ROAD_WIDTH = 17.0
local MIN_ROAD_LENGTH = 28.0

-- Narrow, believable sidewalk geometry.
local SIDEWALK_WIDTH = 4.6
local SIDEWALK_THICKNESS = 0.45
local SIDEWALK_GAP_FROM_ASPHALT = 0.45
local SIDEWALK_END_OVERLAP = 0.35
local SIDEWALK_DROP_FROM_ROAD_TOP = 0.08

-- Intersection clustering.
local NODE_SNAP = 6.0
local MIN_INTERSECTION_LEGS = 3

-- Small asphalt fill only. No giant squares.
local PAD_EXTRA = 1.0
local PAD_MIN = 7.0
local PAD_MAX = 34.0
local PAD_THICKNESS = 0.35
local PAD_LIFT = 0.035

if not ENABLED then
	return
end

local function collectRoadParts()
	local roads = {}

	for _, tile in ipairs(world:GetChildren()) do
		local folder = tile:FindFirstChild("Roads")
		if folder then
			for _, obj in ipairs(folder:GetDescendants()) do
				if obj:IsA("BasePart") then
					table.insert(roads, obj)
				end
			end
		end
	end

	return roads
end

local function conformedCount(roads)
	local n = 0
	for _, road in ipairs(roads) do
		if road:GetAttribute("CW_TerrainConformed") == true then
			n += 1
		end
	end
	return n
end

local function waitForRoads()
	local elapsed = 0
	local lastTotal = -1
	local stable = 0

	while elapsed < MAX_WAIT do
		local roads = collectRoadParts()
		local total = #roads
		local good = conformedCount(roads)
		local ratio = total > 0 and good / total or 0

		if total > 0 and total == lastTotal then
			stable += 1
		else
			stable = 0
			lastTotal = total
		end

		if total > 0 and stable >= 2 and ratio >= REQUIRED_CONFORM_RATIO then
			return roads, good, ratio
		end

		task.wait(WAIT_STEP)
		elapsed += WAIT_STEP
	end

	local roads = collectRoadParts()
	local good = conformedCount(roads)
	local ratio = #roads > 0 and good / #roads or 0
	return roads, good, ratio
end

local function inferRoadAxes(road)
	if road.Size.X >= road.Size.Z then
		return {
			longAxis = road.CFrame.RightVector,
			sideAxis = road.CFrame.LookVector,
			length = road.Size.X,
			width = road.Size.Z,
			axisKind = "X",
		}
	else
		return {
			longAxis = road.CFrame.LookVector,
			sideAxis = road.CFrame.RightVector,
			length = road.Size.Z,
			width = road.Size.X,
			axisKind = "Z",
		}
	end
end

local function roadTopCenter(road)
	return road.Position + road.CFrame.UpVector * (road.Size.Y / 2)
end

local function ensureFinishFolders()
	local old = world:FindFirstChild("StreetFinish")
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "StreetFinish"
	root.Parent = world

	local sidewalks = Instance.new("Folder")
	sidewalks.Name = "Sidewalks"
	sidewalks.Parent = root

	local pads = Instance.new("Folder")
	pads.Name = "IntersectionPads"
	pads.Parent = root

	return sidewalks, pads
end

local function sidewalkCFrame(road, position)
	local rotationOnly = road.CFrame - road.CFrame.Position
	return CFrame.new(position) * rotationOnly
end

local function makeSidewalkStrip(road, axes, sideSign, parent)
	local up = road.CFrame.UpVector
	local top = roadTopCenter(road)

	local horizontalOffset =
		(axes.width / 2)
		+ SIDEWALK_GAP_FROM_ASPHALT
		+ (SIDEWALK_WIDTH / 2)

	local sideOffset = axes.sideAxis.Unit * horizontalOffset * sideSign

	local sidewalkTop =
		top
		- up * SIDEWALK_DROP_FROM_ROAD_TOP
		+ sideOffset

	local center =
		sidewalkTop
		- up * (SIDEWALK_THICKNESS / 2)

	local size
	if axes.axisKind == "X" then
		size = Vector3.new(
			axes.length + SIDEWALK_END_OVERLAP * 2,
			SIDEWALK_THICKNESS,
			SIDEWALK_WIDTH
		)
	else
		size = Vector3.new(
			SIDEWALK_WIDTH,
			SIDEWALK_THICKNESS,
			axes.length + SIDEWALK_END_OVERLAP * 2
		)
	end

	local part = Instance.new("Part")
	part.Name = sideSign < 0 and "CW_Sidewalk_L" or "CW_Sidewalk_R"
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.Concrete
	part.Color = Color3.fromRGB(145, 145, 139)
	part.Size = size
	part.CFrame = sidewalkCFrame(road, center)

	part:SetAttribute("CW_StreetFinish", true)
	part:SetAttribute("CW_SourceRoad", road.Name)

	part.Parent = parent

	return part
end

local function addSidewalks(road, parent)
	if road:GetAttribute("CW_TerrainConformed") ~= true then
		return false, "not_conformed"
	end

	local axes = inferRoadAxes(road)

	if axes.width < MIN_ROAD_WIDTH then
		return false, "narrow"
	end

	if axes.length < MIN_ROAD_LENGTH then
		return false, "short"
	end

	makeSidewalkStrip(road, axes, -1, parent)
	makeSidewalkStrip(road, axes, 1, parent)

	return true, "created"
end

local function roadEndpoints(road)
	local axes = inferRoadAxes(road)

	local a = road.Position - axes.longAxis * (axes.length / 2)
	local b = road.Position + axes.longAxis * (axes.length / 2)

	return a, b, axes.width
end

local function nodeKey(p)
	local sx = math.floor(p.X / NODE_SNAP + 0.5)
	local sz = math.floor(p.Z / NODE_SNAP + 0.5)
	return tostring(sx) .. ":" .. tostring(sz)
end

local function addNode(nodes, p, road, width)
	local key = nodeKey(p)

	local node = nodes[key]
	if not node then
		node = {
			points = {},
			roads = {},
			maxWidth = 0,
		}
		nodes[key] = node
	end

	table.insert(node.points, p)
	table.insert(node.roads, road)
	node.maxWidth = math.max(node.maxWidth, width)
end

local function uniqueRoads(node)
	local seen = {}
	local list = {}

	for _, road in ipairs(node.roads) do
		if not seen[road] then
			seen[road] = true
			table.insert(list, road)
		end
	end

	return list
end

local function makeIntersectionPad(node, parent)
	local roads = uniqueRoads(node)
	if #roads < MIN_INTERSECTION_LEGS then
		return false
	end

	local avg = Vector3.zero
	for _, p in ipairs(node.points) do
		avg += p
	end
	avg /= #node.points

	local topY = -math.huge
	local representative = roads[1]

	for _, road in ipairs(roads) do
		local top = roadTopCenter(road)
		if top.Y > topY then
			topY = top.Y
			representative = road
		end
	end

	local size = math.clamp(
		node.maxWidth + PAD_EXTRA * 2,
		PAD_MIN,
		PAD_MAX
	)

	local pad = Instance.new("Part")
	pad.Name = "CW_IntersectionPad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = true
	pad.CastShadow = false
	pad.Material = representative.Material
	pad.Color = representative.Color
	pad.Size = Vector3.new(size, PAD_THICKNESS, size)

	pad.Position = Vector3.new(
		avg.X,
		topY + PAD_LIFT - PAD_THICKNESS / 2,
		avg.Z
	)

	pad:SetAttribute("CW_StreetFinish", true)
	pad:SetAttribute("CW_IntersectionLegs", #roads)
	pad.Parent = parent

	return true
end

local roads, good, ratio = waitForRoads()
local sidewalkFolder, padFolder = ensureFinishFolders()

local strips = 0
local roadsWithSidewalks = 0
local skippedNarrow = 0
local skippedShort = 0

for i, road in ipairs(roads) do
	local ok, reason = addSidewalks(road, sidewalkFolder)

	if ok then
		roadsWithSidewalks += 1
		strips += 2
	elseif reason == "narrow" then
		skippedNarrow += 1
	elseif reason == "short" then
		skippedShort += 1
	end

	if i % 500 == 0 then
		task.wait()
	end
end

local nodes = {}

for i, road in ipairs(roads) do
	if road:GetAttribute("CW_TerrainConformed") == true then
		local a, b, width = roadEndpoints(road)
		addNode(nodes, a, road, width)
		addNode(nodes, b, road, width)
	end

	if i % 800 == 0 then
		task.wait()
	end
end

local nodeCount = 0
local pads = 0

for _, node in pairs(nodes) do
	nodeCount += 1

	if makeIntersectionPad(node, padFolder) then
		pads += 1
	end

	if nodeCount % 500 == 0 then
		task.wait()
	end
end

print(string.format(
	"[ChesterWorld StreetFinish 4B] roads=%d conformed=%d ratio=%.4f sidewalkRoads=%d strips=%d skippedNarrow=%d skippedShort=%d nodes=%d pads=%d",
	#roads,
	good,
	ratio,
	roadsWithSidewalks,
	strips,
	skippedNarrow,
	skippedShort,
	nodeCount,
	pads
))
