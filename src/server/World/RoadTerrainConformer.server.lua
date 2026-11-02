-- ChesterWorld - RoadTerrainConformer.server.lua
-- Single elevation owner for the street system.
--
-- Ground/tunnel roads conform to Terrain.
-- Bridge / positive-layer roads receive a smooth elevated deck profile.
-- Geometry ownership stays in TileBuilderV2.
--
-- LOCKED HANDEDNESS: north=-Z, south=+Z, east=+X, west=-X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

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

local function terrainY(x, z)
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

local function horizontalUnit(v)
	local h = Vector3.new(v.X, 0, v.Z)
	if h.Magnitude < 0.0001 then
		return nil
	end
	return h.Unit
end

local function roadAxes(part)
	if part.Size.X >= part.Size.Z then
		return "X", part.Size.X, part.Size.Z, part.CFrame.RightVector
	else
		return "Z", part.Size.Z, part.Size.X, part.CFrame.LookVector
	end
end

local function buildFrameForAxis(position, axisKind, longAxis)
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

local function sampleCrossSection(center, sideAxis, halfWidth)
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

local function conformWithOffsets(part, startOffset, centerOffset, endOffset)
	local axisKind, length, width, rawLongAxis = roadAxes(part)
	local longHorizontal = horizontalUnit(rawLongAxis)

	if not longHorizontal then
		return false, "bad_axis"
	end

	local sideHorizontal = Vector3.new(-longHorizontal.Z, 0, longHorizontal.X)
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

	local startY = startGround + yOffset + (startOffset or 0)
	local centerY = centerGround + yOffset + (centerOffset or 0)
	local endY = endGround + yOffset + (endOffset or 0)

	if length < MIN_SLOPE_LENGTH then
		local targetY = math.max(startY, centerY, endY)
		part.CFrame = CFrame.new(part.Position.X, targetY, part.Position.Z)
			* (part.CFrame - part.CFrame.Position)
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

local function conformGroundRoad(part)
	return conformWithOffsets(part, 0, 0, 0)
end

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function bridgeProfile(t, clearance)
	local rampFraction = math.clamp(
		WorldConfig.BRIDGE_RAMP_FRACTION or 0.20,
		0.05,
		0.45
	)

	if t <= rampFraction then
		return clearance * smoothstep(t / rampFraction)
	elseif t >= 1 - rampFraction then
		return clearance * smoothstep((1 - t) / rampFraction)
	end

	return clearance
end

local function bridgeGroupKey(part)
	local value = tostring(part:GetAttribute("CW_GradeGroup") or "")
	if value ~= "" then
		return value
	end

	return tostring(part:GetAttribute("ChesterStreet") or "Bridge")
		.. ":"
		.. tostring(part:GetAttribute("CW_GradeLevel") or 1)
end

local function dominantDirection(parts)
	local sum = Vector3.zero
	local reference = nil

	for _, part in ipairs(parts) do
		local _, _, _, rawAxis = roadAxes(part)
		local axis = horizontalUnit(rawAxis)
		if axis then
			if not reference then
				reference = axis
			end
			if reference and axis:Dot(reference) < 0 then
				axis = -axis
			end
			sum += axis
		end
	end

	if sum.Magnitude > 0.001 then
		return sum.Unit
	end

	return reference or Vector3.new(1, 0, 0)
end

local function conformBridgeGroup(parts)
	local direction = dominantDirection(parts)
	local projections = {}
	local minProjection = math.huge
	local maxProjection = -math.huge
	local clearance = 0

	for _, part in ipairs(parts) do
		local projection = part.Position.X * direction.X + part.Position.Z * direction.Z
		projections[part] = projection
		minProjection = math.min(minProjection, projection)
		maxProjection = math.max(maxProjection, projection)
		clearance = math.max(
			clearance,
			tonumber(part:GetAttribute("CW_GradeClearanceStuds")) or 0
		)
	end

	if clearance <= 0 then
		clearance = WorldConfig.GRADE_SEPARATION_CLEARANCE_STUDS or 18
	end

	local span = math.max(maxProjection - minProjection, 1)
	local conformed = 0
	local noTerrain = 0
	local failed = 0

	for _, part in ipairs(parts) do
		local _, length, _, rawAxis = roadAxes(part)
		local axis = horizontalUnit(rawAxis) or direction
		if axis:Dot(direction) < 0 then
			axis = -axis
		end

		local halfProjected = math.abs(axis:Dot(direction)) * length * END_FRACTION
		local centerProjection = projections[part]
		local startT = math.clamp((centerProjection - halfProjected - minProjection) / span, 0, 1)
		local centerT = math.clamp((centerProjection - minProjection) / span, 0, 1)
		local endT = math.clamp((centerProjection + halfProjected - minProjection) / span, 0, 1)

		local ok, mode = conformWithOffsets(
			part,
			bridgeProfile(startT, clearance),
			bridgeProfile(centerT, clearance),
			bridgeProfile(endT, clearance)
		)

		if ok then
			conformed += 1
			part:SetAttribute("CW_BridgeProfiled", true)
		else
			if mode == "no_terrain" then
				noTerrain += 1
			else
				failed += 1
			end
		end
	end

	return conformed, noTerrain, failed
end

local roads = collectRoadParts()
local finalRoadCount = #roads

local normalRoads = {}
local bridgeGroups = {}
local tunnelParts = 0

for _, road in ipairs(roads) do
	local level = tonumber(road:GetAttribute("CW_GradeLevel")) or 0
	local isBridge = road:GetAttribute("CW_Bridge") == true or level > 0
	local isTunnel = road:GetAttribute("CW_Tunnel") == true or level < 0

	if isBridge then
		local key = bridgeGroupKey(road)
		bridgeGroups[key] = bridgeGroups[key] or {}
		table.insert(bridgeGroups[key], road)
	else
		table.insert(normalRoads, road)
		if isTunnel then
			tunnelParts += 1
		end
	end
end

local conformed = 0
local raised = 0
local sloped = 0
local noTerrain = 0
local failed = 0
local bridgePartCount = 0
local bridgeGroupCount = 0

for index, road in ipairs(normalRoads) do
	local ok, mode = conformGroundRoad(road)

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

for _, parts in pairs(bridgeGroups) do
	bridgeGroupCount += 1
	bridgePartCount += #parts
	local groupConformed, groupNoTerrain, groupFailed = conformBridgeGroup(parts)
	conformed += groupConformed
	noTerrain += groupNoTerrain
	failed += groupFailed
	task.wait()
end

Workspace:SetAttribute("CW_RoadConformTotal", finalRoadCount)
Workspace:SetAttribute("CW_RoadConformedCount", conformed)
Workspace:SetAttribute("CW_RoadConformComplete", true)

print(string.format(
	"[ChesterWorld RoadTerrainConformer] final=%d conformed=%d sloped=%d raised=%d noTerrain=%d failed=%d bridgeGroups=%d bridgeParts=%d tunnelParts=%d",
	finalRoadCount,
	conformed,
	sloped,
	raised,
	noTerrain,
	failed,
	bridgeGroupCount,
	bridgePartCount,
	tunnelParts
))
