-- ChesterWorld - StreetSurfaceBuilder.server.lua
-- STREET SURFACE V4
--
-- Builds compact source-derived asphalt caps over real intersections.
-- Each intersection uses short strips aligned with the distinct source streets.
-- All strips at one junction share one top elevation so rectangular road
-- segment seams/gaps are visually buried without giant square pads.
--
-- V3.2 roads, terrain conformance and sidewalks remain untouched.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SurfaceData = require(
	Shared:WaitForChild("StreetSurfaceData")
)

local world = Workspace:WaitForChild("ChesterWorld")
local terrain = Workspace.Terrain

local CAP_THICKNESS = 0.22
local CAP_LIFT = 0.045

local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

local function collectRoadFolders()
	local folders = {}

	for _, tile in ipairs(world:GetChildren()) do
		local roads = tile:FindFirstChild("Roads")
		if roads then
			table.insert(folders, roads)
		end
	end

	return folders
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = false

local rayTargets = {terrain}
for _, folder in ipairs(collectRoadFolders()) do
	table.insert(rayTargets, folder)
end

rayParams.FilterDescendantsInstances = rayTargets

local function surfaceY(x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		rayParams
	)

	return result and result.Position.Y or nil
end

local function resetFolder()
	local old = world:FindFirstChild("StreetSurfaceV4")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "StreetSurfaceV4"
	folder.Parent = world

	return folder
end

local function sampleJunctionTop(junction)
	local best = surfaceY(junction.x, junction.z)

	for _, strip in ipairs(junction.strips) do
		local hx = strip.dx * strip.length * 0.45
		local hz = strip.dz * strip.length * 0.45

		local sideX = -strip.dz * strip.width * 0.40
		local sideZ = strip.dx * strip.width * 0.40

		local samples = {
			surfaceY(junction.x + hx, junction.z + hz),
			surfaceY(junction.x - hx, junction.z - hz),
			surfaceY(junction.x + sideX, junction.z + sideZ),
			surfaceY(junction.x - sideX, junction.z - sideZ),
		}

		for _, value in ipairs(samples) do
			if value and (not best or value > best) then
				best = value
			end
		end
	end

	return best
end

local function buildStrip(junction, strip, topY, parent)
	local direction = Vector3.new(
		strip.dx,
		0,
		strip.dz
	)

	if direction.Magnitude < 0.001 then
		return false
	end

	direction = direction.Unit

	local center = Vector3.new(
		junction.x,
		topY + CAP_LIFT - CAP_THICKNESS / 2,
		junction.z
	)

	local part = Instance.new("Part")
	part.Name = "CW_IntersectionCap"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false

	part.Material = Enum.Material.Asphalt
	part.Color = Color3.fromRGB(72, 74, 78)

	part.Size = Vector3.new(
		strip.width,
		CAP_THICKNESS,
		strip.length
	)

	part.CFrame = CFrame.lookAt(
		center,
		center + direction,
		Vector3.yAxis
	)

	part:SetAttribute("CW_StreetSurfaceV4", true)
	part.Parent = parent

	return true
end

local folder = resetFolder()

local junctionsBuilt = 0
local stripsBuilt = 0
local noSurface = 0

for index, junction in ipairs(SurfaceData.junctions) do
	local topY = sampleJunctionTop(junction)

	if topY then
		local builtHere = 0

		for _, strip in ipairs(junction.strips) do
			if buildStrip(junction, strip, topY, folder) then
				builtHere += 1
				stripsBuilt += 1
			end
		end

		if builtHere >= 2 then
			junctionsBuilt += 1
		end
	else
		noSurface += 1
	end

	if index % 300 == 0 then
		task.wait()
	end
end

print(string.format(
	"[ChesterWorld StreetSurfaceV4] sourceJunctions=%d builtJunctions=%d strips=%d noSurface=%d",
	#SurfaceData.junctions,
	junctionsBuilt,
	stripsBuilt,
	noSurface
))
