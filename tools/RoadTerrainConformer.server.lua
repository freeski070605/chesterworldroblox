-- ChesterWorld - RoadTerrainConformer.server.lua
-- V3.2 deterministic ordering:
-- Bootstrap 102/102 -> conform FINAL roads -> StreetSystem.
--
-- This script does NOT modify Terrain.
-- North=-Z, South=+Z, East=+X, West=-X.

local Workspace = game:GetService("Workspace")

local SURFACE_LIFT = 0.22
local MIN_SLOPE_LENGTH = 8
local RAY_START_Y = 2048
local RAY_DISTANCE = 4096
local END_FRACTION = 0.44
local WIDTH_FRACTION = 0.38

Workspace:SetAttribute("CW_RoadConformComplete", false)

while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do
	task.wait(0.20)
end

local terrain = Workspace.Terrain
local world = Workspace:WaitForChild("ChesterWorld")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = {terrain}
rayParams.IgnoreWater = false

local function terrainY(x: number, z: number): number?
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		rayParams
	)
	return result and result.Position.Y or nil
end

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

local function horizontalUnit(v: Vector3): Vector3?
	local h = Vector3.new(v.X, 0, v.Z)
	if h.Magnitude < 0.0001 then
		return nil
	end
	return h.Unit
end

local function roadAxes(part: BasePart)
	if part.Size.X >= part.Size.Z then
		return "X", part.Size.X, part.Size.Z, part.CFrame.RightVector
	else
		return "Z", part.Size.Z, part.Size.X, part.CFrame.LookVector
	end
end

local function buildFrameForAxis(
	position: Vector3,
	axisKind: string,
	longAxis: Vector3
): CFrame
	local yAxis = Vector3.new(0, 1, 0)

	if axisKind == "X" then
		local right = longAxis.Unit
		local back = right:Cross(yAxis)
		if back.Magnitude < 0.0001 then
			return CFrame.new(position)
		end
		back = back.Unit
		local up = back:Cross(right).Unit
		return CFrame.fromMatrix(position, right, up, back)
	else
		local back = -longAxis.Unit
		local right = yAxis:Cross(back)
		if right.Magnitude < 0.0001 then
			return CFrame.new(position)
		end
		right = right.Unit
		local up = back:Cross(right).Unit
		return CFrame.fromMatrix(position, right, up, back)
	end
end

local function sampleCrossSection(
	center: Vector3,
	sideAxis: Vector3,
	halfWidth: number
): number?
	local offset = sideAxis * (halfWidth * WIDTH_FRACTION)

	local values = {
		terrainY(center.X, center.Z),
		terrainY(center.X + offset.X, center.Z + offset.Z),
		terrainY(center.X - offset.X, center.Z - offset.Z),
	}

	local best = nil
	for _, value in ipairs(values) do
		if value ~= nil and (best == nil or value > best) then
			best = value
		end
	end

	return best
end

local function conformRoad(part: BasePart)
	local axisKind, length, width, rawLongAxis = roadAxes(part)
	local longHorizontal = horizontalUnit(rawLongAxis)

	if not longHorizontal then
		return false, "bad_axis"
	end

	local sideHorizontal = Vector3.new(
		-longHorizontal.Z,
		0,
		longHorizontal.X
	)

	local centerXZ = Vector3.new(part.Position.X, 0, part.Position.Z)
	local endpointOffset = longHorizontal * (length * END_FRACTION)

	local startXZ = centerXZ - endpointOffset
	local endXZ = centerXZ + endpointOffset
	local halfWidth = width / 2

	local startGround = sampleCrossSection(startXZ, sideHorizontal, halfWidth)
	local centerGround = sampleCrossSection(centerXZ, sideHorizontal, halfWidth)
	local endGround = sampleCrossSection(endXZ, sideHorizontal, halfWidth)

	if not startGround or not centerGround or not endGround then
		return false, "no_terrain"
	end

	local halfThickness = part.Size.Y / 2
	local yOffset = halfThickness + SURFACE_LIFT

	local startY = startGround + yOffset
	local centerY = centerGround + yOffset
	local endY = endGround + yOffset

	if length < MIN_SLOPE_LENGTH then
		local targetY = math.max(startY, centerY, endY)

		part.CFrame = CFrame.new(
			part.Position.X,
			targetY,
			part.Position.Z
		) * (part.CFrame - part.CFrame.Position)

		part:SetAttribute("CW_TerrainConformed", true)
		return true, "raised"
	end

	local horizontalDistance = (endXZ - startXZ).Magnitude
	if horizontalDistance < 0.001 then
		return false, "too_short"
	end

	local rise = endY - startY
	local run = horizontalDistance

	local long3 = Vector3.new(
		longHorizontal.X * run,
		rise,
		longHorizontal.Z * run
	).Unit

	local endpointMidY = (startY + endY) / 2
	local extraLift = math.max(0, centerY - endpointMidY)

	part.CFrame = buildFrameForAxis(
		Vector3.new(
			part.Position.X,
			endpointMidY + extraLift,
			part.Position.Z
		),
		axisKind,
		long3
	)

	part:SetAttribute("CW_TerrainConformed", true)
	part:SetAttribute("CW_TerrainExtraLift", extraLift)

	return true, "sloped"
end

-- Bootstrap is now guaranteed complete. This is the FINAL road set.
local roads = collectRoadParts()
local finalRoadCount = #roads

local conformed = 0
local raised = 0
local sloped = 0
local noTerrain = 0
local failed = 0

for index, road in ipairs(roads) do
	local ok, mode = conformRoad(road)

	if ok then
		conformed += 1
		if mode == "raised" then
			raised += 1
		elseif mode == "sloped" then
			sloped += 1
		end
	else
		if mode == "no_terrain" then
			noTerrain += 1
		else
			failed += 1
		end
	end

	if index % 400 == 0 then
		task.wait()
	end
end

Workspace:SetAttribute("CW_RoadConformTotal", finalRoadCount)
Workspace:SetAttribute("CW_RoadConformedCount", conformed)
Workspace:SetAttribute("CW_RoadConformComplete", true)

print(string.format(
	"[ChesterWorld RoadTerrainConformer] final=%d current=%d conformed=%d sloped=%d raised=%d noTerrain=%d failed=%d",
	finalRoadCount,
	#roads,
	conformed,
	sloped,
	raised,
	noTerrain,
	failed
))
