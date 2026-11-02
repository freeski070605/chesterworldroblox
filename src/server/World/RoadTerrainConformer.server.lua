-- ChesterWorld - RoadTerrainConformer.server.lua
--
-- SINGLE ELEVATION OWNERSHIP:
--   * TileBuilderV2 owns all at-grade / underpass road elevation.
--   * This script ONLY shapes positive-grade bridge groups.
--
-- Bridge rule:
--   Do NOT follow terrain underneath every bridge Part. That reproduces ground
--   bumps/cuts in the elevated deck. Each bridge group now gets one continuous
--   start-to-end baseline, with a smooth clearance profile across the span.
--
-- LOCKED HANDEDNESS: north=-Z, south=+Z, east=+X, west=-X.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))

local SURFACE_LIFT = 0.22
local RAY_START_Y = 2048
local RAY_DISTANCE = 4096
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
	-- TileBuilderV2 strips use width on X and longitudinal distance on Z.
	-- Keep the generic fallback for safety.
	if part.Size.Z >= part.Size.X then
		return "Z", part.Size.Z, part.Size.X, part.CFrame.LookVector
	else
		return "X", part.Size.X, part.Size.Z, part.CFrame.RightVector
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

local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function bridgeProfile(t, clearance)
	local rampFraction = math.clamp(
		WorldConfig.BRIDGE_RAMP_FRACTION or 0.20,
		0.08,
		0.42
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

local function lerp(a, b, t)
	return a + (b - a) * math.clamp(t, 0, 1)
end

local function conformBridgeGroup(parts)
	local direction = dominantDirection(parts)
	local info = {}
	local minProjection = math.huge
	local maxProjection = -math.huge
	local startWorld = nil
	local endWorld = nil
	local startWidth = 0
	local endWidth = 0
	local clearance = 0

	for _, part in ipairs(parts) do
		local axisKind, length, width, rawAxis = roadAxes(part)
		local axis = horizontalUnit(rawAxis) or direction
		if axis:Dot(direction) < 0 then
			axis = -axis
		end

		local half = length / 2
		local center = Vector3.new(part.Position.X, 0, part.Position.Z)
		local p0 = center - axis * half
		local p1 = center + axis * half
		local proj0 = p0.X * direction.X + p0.Z * direction.Z
		local proj1 = p1.X * direction.X + p1.Z * direction.Z

		if proj1 < proj0 then
			p0, p1 = p1, p0
			proj0, proj1 = proj1, proj0
		end

		info[part] = {
			axisKind = axisKind,
			axis = axis,
			length = length,
			width = width,
			p0 = p0,
			p1 = p1,
			proj0 = proj0,
			proj1 = proj1,
		}

		if proj0 < minProjection then
			minProjection = proj0
			startWorld = p0
			startWidth = width
		end
		if proj1 > maxProjection then
			maxProjection = proj1
			endWorld = p1
			endWidth = width
		end

		clearance = math.max(
			clearance,
			tonumber(part:GetAttribute("CW_GradeClearanceStuds")) or 0
		)
	end

	if not startWorld or not endWorld then
		return 0, 0, #parts
	end

	if clearance <= 0 then
		clearance = WorldConfig.GRADE_SEPARATION_CLEARANCE_STUDS or 18
	end

	local startSide = Vector3.new(-direction.Z, 0, direction.X)
	local endSide = startSide
	local startGround = sampleCrossSection(startWorld, startSide, math.max(startWidth / 2, 1))
	local endGround = sampleCrossSection(endWorld, endSide, math.max(endWidth / 2, 1))

	if not startGround or not endGround then
		return 0, #parts, 0
	end

	local span = math.max(maxProjection - minProjection, 1)
	local conformed = 0
	local failed = 0

	for part, data in pairs(info) do
		local startT = math.clamp((data.proj0 - minProjection) / span, 0, 1)
		local endT = math.clamp((data.proj1 - minProjection) / span, 0, 1)
		local centerT = (startT + endT) / 2

		local halfThickness = part.Size.Y / 2
		local surfaceOffset = halfThickness + SURFACE_LIFT

		local startY =
			lerp(startGround, endGround, startT)
			+ surfaceOffset
			+ bridgeProfile(startT, clearance)

		local endY =
			lerp(startGround, endGround, endT)
			+ surfaceOffset
			+ bridgeProfile(endT, clearance)

		local run = (data.p1 - data.p0).Magnitude
		if run < 0.001 then
			failed += 1
		else
			local rise = endY - startY
			local long3 = Vector3.new(
				data.axis.X * run,
				rise,
				data.axis.Z * run
			).Unit

			part.CFrame = buildFrameForAxis(
				Vector3.new(
					part.Position.X,
					(startY + endY) / 2,
					part.Position.Z
				),
				data.axisKind,
				long3
			)

			part:SetAttribute("CW_TerrainConformed", true)
			part:SetAttribute("CW_BridgeProfiled", true)
			part:SetAttribute("CW_BridgeProfileT", centerT)
			part:SetAttribute("CW_ElevationOwner", "RoadTerrainConformer:SmoothBridge")
			conformed += 1
		end
	end

	return conformed, 0, failed
end

local roads = collectRoadParts()
local finalRoadCount = #roads

local bridgeGroups = {}
local groundPreserved = 0
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
		-- Ground roads and the road underneath an overpass stay exactly where
		-- TileBuilderV2 put them. This keeps junctions/sidewalks/markings aligned.
		groundPreserved += 1
		if isTunnel then
			tunnelParts += 1
		end
		road:SetAttribute("CW_TerrainConformed", true)
		road:SetAttribute("CW_ElevationOwner", "TileBuilderV2")
	end
end

local bridgeConformed = 0
local bridgeNoTerrain = 0
local bridgeFailed = 0
local bridgePartCount = 0
local bridgeGroupCount = 0

for _, parts in pairs(bridgeGroups) do
	bridgeGroupCount += 1
	bridgePartCount += #parts

	local groupConformed, groupNoTerrain, groupFailed = conformBridgeGroup(parts)
	bridgeConformed += groupConformed
	bridgeNoTerrain += groupNoTerrain
	bridgeFailed += groupFailed

	task.wait()
end

local conformed = groundPreserved + bridgeConformed

Workspace:SetAttribute("CW_RoadConformTotal", finalRoadCount)
Workspace:SetAttribute("CW_RoadConformedCount", conformed)
Workspace:SetAttribute("CW_RoadConformComplete", true)

print(string.format(
	"[ChesterWorld RoadTerrainConformer] final=%d groundPreserved=%d bridgeConformed=%d conformed=%d noTerrain=%d failed=%d bridgeGroups=%d bridgeParts=%d tunnelParts=%d smoothDecks=true",
	finalRoadCount,
	groundPreserved,
	bridgeConformed,
	conformed,
	bridgeNoTerrain,
	bridgeFailed,
	bridgeGroupCount,
	bridgePartCount,
	tunnelParts
))
