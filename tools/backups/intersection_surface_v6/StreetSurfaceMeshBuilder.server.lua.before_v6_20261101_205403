-- ChesterWorld - StreetSurfaceMeshBuilder.server.lua
-- STREET SURFACE V5.3
--
-- Uses 2x2 sub-tile EditableMesh road surfaces so every MeshPart stays below
-- Roblox's 2048-stud extents limit.
--
-- Also includes the V5.2 junction-plane correction and integrated legacy-road
-- visibility handoff.
--
-- V3.2 remains underneath for collision, inspector identity, and fallback.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SurfaceTiles = Shared:WaitForChild("StreetSurfaceTilesV53")
local StreetFinishData = require(
	Shared:WaitForChild("StreetFinishData")
)

local world = Workspace:WaitForChild("ChesterWorld")
local terrain = Workspace.Terrain

local SURFACE_LIFT = 0.055
local JUNCTION_TERRAIN_OFFSET = 0.42

local CORE_RADIUS_MULT = 0.56
local MIN_CORE_RADIUS = 8.0
local MAX_CORE_RADIUS = 24.0

local BLEND_RING_MULT = 0.55
local MIN_BLEND_RING = 8.0
local MAX_BLEND_RING = 18.0

local MAX_PLANE_GRADE = 0.16
local JUNCTION_GRID_CELL = 80.0

local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

local roadFolders = {}

for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		table.insert(roadFolders, roads)
	end
end

local surfaceRayParams = RaycastParams.new()
surfaceRayParams.FilterType = Enum.RaycastFilterType.Include
surfaceRayParams.IgnoreWater = false

local surfaceTargets = {terrain}
for _, folder in ipairs(roadFolders) do
	table.insert(surfaceTargets, folder)
end

surfaceRayParams.FilterDescendantsInstances = surfaceTargets

local terrainRayParams = RaycastParams.new()
terrainRayParams.FilterType = Enum.RaycastFilterType.Include
terrainRayParams.FilterDescendantsInstances = {terrain}
terrainRayParams.IgnoreWater = false

local function rayY(params, x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		params
	)

	return result and result.Position.Y or nil
end

local function normalSurfaceY(x, z)
	return rayY(surfaceRayParams, x, z)
end

local function terrainY(x, z)
	return rayY(terrainRayParams, x, z)
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function smoothstep01(t)
	t = clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function gridKey(gx, gz)
	return tostring(gx) .. ":" .. tostring(gz)
end

local function gridCoord(value)
	return math.floor(value / JUNCTION_GRID_CELL)
end

local junctionGrid = {}
local validJunctionPlanes = 0

local function makeJunctionPlane(junction)
	local size = tonumber(junction.size) or 18.0

	local coreRadius = clamp(
		size * CORE_RADIUS_MULT,
		MIN_CORE_RADIUS,
		MAX_CORE_RADIUS
	)

	local blendRing = clamp(
		size * BLEND_RING_MULT,
		MIN_BLEND_RING,
		MAX_BLEND_RING
	)

	local outerRadius = coreRadius + blendRing
	local fitRadius = clamp(coreRadius * 0.70, 5.0, 13.0)

	local cy = terrainY(junction.x, junction.z)
	local east = terrainY(junction.x + fitRadius, junction.z)
	local west = terrainY(junction.x - fitRadius, junction.z)
	local south = terrainY(junction.x, junction.z + fitRadius)
	local north = terrainY(junction.x, junction.z - fitRadius)

	if not cy then
		return nil
	end

	east = east or cy
	west = west or cy
	south = south or cy
	north = north or cy

	local gradeX = (east - west) / (fitRadius * 2)
	local gradeZ = (south - north) / (fitRadius * 2)

	gradeX = clamp(gradeX, -MAX_PLANE_GRADE, MAX_PLANE_GRADE)
	gradeZ = clamp(gradeZ, -MAX_PLANE_GRADE, MAX_PLANE_GRADE)

	return {
		x = junction.x,
		z = junction.z,
		centerY = cy + JUNCTION_TERRAIN_OFFSET,
		gradeX = gradeX,
		gradeZ = gradeZ,
		coreRadius = coreRadius,
		outerRadius = outerRadius,
	}
end

for _, junction in ipairs(StreetFinishData.junctions) do
	local plane = makeJunctionPlane(junction)

	if plane then
		validJunctionPlanes += 1

		local minGX = gridCoord(plane.x - plane.outerRadius)
		local maxGX = gridCoord(plane.x + plane.outerRadius)
		local minGZ = gridCoord(plane.z - plane.outerRadius)
		local maxGZ = gridCoord(plane.z + plane.outerRadius)

		for gx = minGX, maxGX do
			for gz = minGZ, maxGZ do
				local key = gridKey(gx, gz)
				local bucket = junctionGrid[key]

				if not bucket then
					bucket = {}
					junctionGrid[key] = bucket
				end

				table.insert(bucket, plane)
			end
		end
	end
end

local function junctionAdjustedY(x, z, baseY)
	local candidates = junctionGrid[
		gridKey(
			gridCoord(x),
			gridCoord(z)
		)
	]

	if not candidates then
		return baseY, false
	end

	local bestWeight = 0
	local bestPlaneY = nil

	for _, plane in ipairs(candidates) do
		local dx = x - plane.x
		local dz = z - plane.z
		local distance = math.sqrt(dx * dx + dz * dz)

		if distance <= plane.outerRadius then
			local weight

			if distance <= plane.coreRadius then
				weight = 1
			else
				local t = (
					distance - plane.coreRadius
				) / (
					plane.outerRadius - plane.coreRadius
				)

				weight = 1 - smoothstep01(t)
			end

			if weight > bestWeight then
				bestWeight = weight
				bestPlaneY = (
					plane.centerY
					+ plane.gradeX * dx
					+ plane.gradeZ * dz
				)
			end
		end
	end

	if not bestPlaneY or bestWeight <= 0 then
		return baseY, false
	end

	return (
		baseY * (1 - bestWeight)
		+ bestPlaneY * bestWeight
	), true
end

local function resetFolder()
	for _, name in ipairs({
		"StreetSurfaceV4",
		"StreetSurfaceV5",
		"StreetSurfaceV53",
	}) do
		local old = world:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local folder = Instance.new("Folder")
	folder.Name = "StreetSurfaceV53"
	folder.Parent = world

	return folder
end

local function createSurfaceMesh(surfaceData, parent)
	local verticesFlat = surfaceData.vertices
	local trianglesFlat = surfaceData.triangles

	if #verticesFlat < 6 or #trianglesFlat < 3 then
		return false, "empty", 0
	end

	local sampledY = {}
	local minY = math.huge
	local adjustedVertices = 0

	for i = 1, #verticesFlat, 2 do
		local relX = verticesFlat[i]
		local relZ = verticesFlat[i + 1]

		local worldX = surfaceData.originX + relX
		local worldZ = surfaceData.originZ + relZ

		local baseY = normalSurfaceY(worldX, worldZ)

		if not baseY then
			return false, "no_surface", adjustedVertices
		end

		baseY += SURFACE_LIFT

		local y, adjusted = junctionAdjustedY(
			worldX,
			worldZ,
			baseY
		)

		if adjusted then
			adjustedVertices += 1
		end

		table.insert(sampledY, y)
		minY = math.min(minY, y)
	end

	local editableMesh = AssetService:CreateEditableMesh()

	if not editableMesh then
		return false, "editable_mesh_failed", adjustedVertices
	end

	local vertexIds = {}

	for i = 1, #verticesFlat, 2 do
		local vertexNumber = ((i - 1) / 2) + 1
		local relX = verticesFlat[i]
		local relZ = verticesFlat[i + 1]
		local y = sampledY[vertexNumber]

		vertexIds[vertexNumber] = editableMesh:AddVertex(
			Vector3.new(
				relX,
				y - minY,
				relZ
			)
		)
	end

	for i = 1, #trianglesFlat, 3 do
		local a = vertexIds[trianglesFlat[i]]
		local b = vertexIds[trianglesFlat[i + 1]]
		local c = vertexIds[trianglesFlat[i + 2]]

		if a and b and c then
			editableMesh:AddTriangle(a, b, c)
		end
	end

	local meshPart

	local ok, errorMessage = pcall(function()
		meshPart = AssetService:CreateMeshPartAsync(
			Content.fromObject(editableMesh),
			{
				CollisionFidelity = Enum.CollisionFidelity.Box,
			}
		)
	end)

	if not ok or not meshPart then
		editableMesh:Destroy()
		return false, "meshpart_failed:" .. tostring(errorMessage), adjustedVertices
	end

	meshPart.Name = "CW_RoadSurface_" .. tostring(surfaceData.surfaceId)
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanTouch = false
	meshPart.CanQuery = true
	meshPart.CastShadow = false
	meshPart.DoubleSided = true

	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(72, 74, 78)

	meshPart.Size = meshPart.MeshSize

	meshPart.CFrame = CFrame.new(
		surfaceData.originX,
		minY,
		surfaceData.originZ
	)

	meshPart:SetAttribute("CW_StreetSurfaceV53", true)
	meshPart:SetAttribute("CW_SourceTile", tostring(surfaceData.sourceTile))
	meshPart.Parent = parent

	editableMesh:Destroy()

	return true, "created", adjustedVertices
end

local folder = resetFolder()

local modules = SurfaceTiles:GetChildren()
table.sort(modules, function(a, b)
	return a.Name < b.Name
end)

local built = 0
local empty = 0
local noSurface = 0
local editableFailures = 0
local meshPartFailures = 0
local adjustedVertices = 0

for index, module in ipairs(modules) do
	if module:IsA("ModuleScript") then
		local okRequire, surfaceData = pcall(require, module)

		if okRequire and surfaceData then
			local ok, status, adjusted = createSurfaceMesh(
				surfaceData,
				folder
			)

			adjustedVertices += adjusted or 0

			if ok then
				built += 1
			elseif status == "empty" then
				empty += 1
			elseif status == "no_surface" then
				noSurface += 1
			elseif status == "editable_mesh_failed" then
				editableFailures += 1
			else
				meshPartFailures += 1
				warn(
					"[ChesterWorld StreetSurfaceV5.3] "
					.. tostring(module.Name)
					.. " failed: "
					.. tostring(status)
				)
			end
		else
			meshPartFailures += 1
			warn(
				"[ChesterWorld StreetSurfaceV5.3] require failed for "
				.. tostring(module.Name)
				.. ": "
				.. tostring(surfaceData)
			)
		end
	end

	if index % 10 == 0 then
		task.wait()
	end
end

-- ---------------------------------------------------------------------------
-- LEGACY ROAD VISIBILITY HANDOFF
-- ---------------------------------------------------------------------------

local meshParts = {}

for _, obj in ipairs(folder:GetChildren()) do
	if obj:IsA("MeshPart") then
		table.insert(meshParts, obj)
	end
end

local visibilityParams = RaycastParams.new()
visibilityParams.FilterType = Enum.RaycastFilterType.Include
visibilityParams.FilterDescendantsInstances = {folder}
visibilityParams.IgnoreWater = true

local LEGACY_RAY_UP = 6.0
local LEGACY_RAY_DOWN = 14.0
local MAX_VERTICAL_DELTA = 3.0

local function meshCoversLegacyRoad(road)
	local result = Workspace:Raycast(
		road.Position + Vector3.new(0, LEGACY_RAY_UP, 0),
		Vector3.new(0, -LEGACY_RAY_DOWN, 0),
		visibilityParams
	)

	if not result then
		return false
	end

	local roadTop = (
		road.Position
		+ road.CFrame.UpVector * (road.Size.Y / 2)
	).Y

	return math.abs(result.Position.Y - roadTop) <= MAX_VERTICAL_DELTA
end

local totalLegacyRoads = 0
local hiddenLegacy = 0
local fallbackVisible = 0

for _, roadFolder in ipairs(roadFolders) do
	for _, road in ipairs(roadFolder:GetDescendants()) do
		if road:IsA("BasePart") then
			totalLegacyRoads += 1

			if meshCoversLegacyRoad(road) then
				road.Transparency = 1
				road.CastShadow = false
				road:SetAttribute("CW_HiddenByStreetSurfaceV53", true)
				hiddenLegacy += 1
			else
				road.Transparency = 0
				road:SetAttribute("CW_HiddenByStreetSurfaceV53", false)
				fallbackVisible += 1
			end
		end
	end

	task.wait()
end

-- Mesh remains visual-only. Inspector/raycast should still hit named legacy roads.
for _, meshPart in ipairs(meshParts) do
	meshPart.CanQuery = false
end

Workspace:SetAttribute("CW_StreetSurfaceV53Complete", true)

print(string.format(
	"[ChesterWorld StreetSurfaceV5.3] modules=%d built=%d empty=%d noSurface=%d editableFailures=%d meshPartFailures=%d junctionPlanes=%d adjustedVertices=%d legacyRoads=%d hiddenLegacy=%d fallbackVisible=%d",
	#modules,
	built,
	empty,
	noSurface,
	editableFailures,
	meshPartFailures,
	validJunctionPlanes,
	adjustedVertices,
	totalLegacyRoads,
	hiddenLegacy,
	fallbackVisible
))
