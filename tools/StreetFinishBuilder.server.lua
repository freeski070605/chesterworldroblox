-- ChesterWorld - StreetFinishBuilder.server.lua
-- STREET SYSTEM V3.2
--
-- Runs ONLY after:
--   1) Bootstrap has built all 102 tiles
--   2) RoadTerrainConformer has processed the final road set
--
-- Source sidewalks remain enabled.
-- Square intersection pads are intentionally disabled in V3.2 because the
-- previous pad system created black blobs at same-street segment joins.
-- Corrected source junctions are still used to cut sidewalks back cleanly.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StreetFinishData = require(
	Shared:WaitForChild("StreetFinishData")
)

local world = Workspace:WaitForChild("ChesterWorld")
local terrain = Workspace.Terrain

local SIDEWALK_WIDTH = StreetFinishData.sidewalkWidthStuds or 4.5
local SIDEWALK_THICKNESS = 0.55
local SIDEWALK_SURFACE_LIFT = 0.34
local SIDEWALK_LONG_OVERLAP = 0.10

local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = {terrain}
rayParams.IgnoreWater = false

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

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

local function resetStreetFinish()
	local old = world:FindFirstChild("StreetFinish")
	if old then
		old:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = "StreetFinish"
	root.Parent = world

	local sidewalks = Instance.new("Folder")
	sidewalks.Name = "SourceSidewalks"
	sidewalks.Parent = root

	return sidewalks
end

local function buildSidewalk(segment, parent)
	local x1 = segment.x1
	local z1 = segment.z1
	local x2 = segment.x2
	local z2 = segment.z2

	local y1 = terrainY(x1, z1)
	local y2 = terrainY(x2, z2)

	local mx = (x1 + x2) / 2
	local mz = (z1 + z2) / 2
	local ym = terrainY(mx, mz)

	if not y1 or not y2 or not ym then
		return false
	end

	local top1 = y1 + SIDEWALK_SURFACE_LIFT
	local top2 = y2 + SIDEWALK_SURFACE_LIFT
	local topMid = ym + SIDEWALK_SURFACE_LIFT

	local expectedMid = (top1 + top2) / 2
	local extraLift = math.max(0, topMid - expectedMid)

	local p1 = Vector3.new(x1, top1, z1)
	local p2 = Vector3.new(x2, top2, z2)

	local delta = p2 - p1
	local length = delta.Magnitude

	if length < 0.5 then
		return false
	end

	local center = (p1 + p2) / 2 + Vector3.new(
		0,
		extraLift - SIDEWALK_THICKNESS / 2,
		0
	)

	local part = Instance.new("Part")
	part.Name = "CW_SourceSidewalk"
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Material = Enum.Material.Concrete
	part.Color = Color3.fromRGB(145, 145, 139)

	part.Size = Vector3.new(
		SIDEWALK_WIDTH,
		SIDEWALK_THICKNESS,
		length + SIDEWALK_LONG_OVERLAP
	)

	part.CFrame = CFrame.lookAt(
		center,
		center + delta.Unit,
		Vector3.yAxis
	)

	part:SetAttribute("CW_StreetSystemV32", true)
	part.Parent = parent

	return true
end

local roads = collectRoadParts()
local conformed = 0

for _, road in ipairs(roads) do
	if road:GetAttribute("CW_TerrainConformed") == true then
		conformed += 1
	end
end

local ratio = #roads > 0 and conformed / #roads or 0
local sidewalkFolder = resetStreetFinish()

local sidewalks = 0
local sidewalkNoTerrain = 0

for index, segment in ipairs(StreetFinishData.segments) do
	if buildSidewalk(segment, sidewalkFolder) then
		sidewalks += 1
	else
		sidewalkNoTerrain += 1
	end

	if index % 400 == 0 then
		task.wait()
	end
end

print(string.format(
	"[ChesterWorld StreetSystemV3.2] roads=%d conformed=%d ratio=%.4f sourceSidewalks=%d sidewalkNoTerrain=%d correctedJunctions=%d junctionPads=DISABLED",
	#roads,
	conformed,
	ratio,
	sidewalks,
	sidewalkNoTerrain,
	#StreetFinishData.junctions
))
