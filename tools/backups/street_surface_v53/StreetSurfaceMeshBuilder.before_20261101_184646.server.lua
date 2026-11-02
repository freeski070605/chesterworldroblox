-- ChesterWorld - StreetSurfaceMeshBuilder.server.lua
-- STREET SURFACE V5
--
-- Continuous source-road asphalt meshes built per regional tile.
-- V3.2 remains underneath for alignment, conformance, sidewalks, and logic.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SurfaceTiles = Shared:WaitForChild("StreetSurfaceTiles")
local world = Workspace:WaitForChild("ChesterWorld")
local terrain = Workspace.Terrain

local SURFACE_LIFT = 0.055
local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

local function roadFolders()
	local folders = {}
	for _, tile in ipairs(world:GetChildren()) do
		local roads = tile:FindFirstChild("Roads")
		if roads then
			table.insert(folders, roads)
		end
	end
	return folders
end

local rayTargets = {terrain}
for _, folder in ipairs(roadFolders()) do
	table.insert(rayTargets, folder)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = rayTargets
rayParams.IgnoreWater = false

local function surfaceY(x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		rayParams
	)
	return result and result.Position.Y or nil
end

local function resetFolder()
	local oldV4 = world:FindFirstChild("StreetSurfaceV4")
	if oldV4 then
		oldV4:Destroy()
	end
	local old = world:FindFirstChild("StreetSurfaceV5")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "StreetSurfaceV5"
	folder.Parent = world
	return folder
end

local function createTileMesh(tileData, parent)
	local verticesFlat = tileData.vertices
	local trianglesFlat = tileData.triangles
	if #verticesFlat < 6 or #trianglesFlat < 3 then
		return false, "empty"
	end

	local sampledY = {}
	local minY = math.huge
	for i = 1, #verticesFlat, 2 do
		local relX = verticesFlat[i]
		local relZ = verticesFlat[i + 1]
		local worldX = tileData.originX + relX
		local worldZ = tileData.originZ + relZ
		local y = surfaceY(worldX, worldZ)
		if not y then
			return false, "no_surface"
		end
		y += SURFACE_LIFT
		table.insert(sampledY, y)
		minY = math.min(minY, y)
	end

	local editableMesh = AssetService:CreateEditableMesh()
	if not editableMesh then
		return false, "editable_mesh_failed"
	end

	local vertexIds = {}
	for i = 1, #verticesFlat, 2 do
		local vertexNumber = ((i - 1) / 2) + 1
		local relX = verticesFlat[i]
		local relZ = verticesFlat[i + 1]
		local y = sampledY[vertexNumber]
		vertexIds[vertexNumber] = editableMesh:AddVertex(
			Vector3.new(relX, y - minY, relZ)
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
			{ CollisionFidelity = Enum.CollisionFidelity.Box }
		)
	end)

	if not ok or not meshPart then
		editableMesh:Destroy()
		return false, "meshpart_failed:" .. tostring(errorMessage)
	end

	meshPart.Name = "CW_RoadSurface_" .. tostring(tileData.tileId)
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanTouch = false
	meshPart.CanQuery = true
	meshPart.CastShadow = false
	meshPart.DoubleSided = true
	meshPart.Material = Enum.Material.Asphalt
	meshPart.Color = Color3.fromRGB(72, 74, 78)
	meshPart.Size = meshPart.MeshSize
	meshPart.CFrame = CFrame.new(tileData.originX, minY, tileData.originZ)
	meshPart:SetAttribute("CW_StreetSurfaceV5", true)
	meshPart:SetAttribute("CW_SourceTile", tostring(tileData.tileId))
	meshPart.Parent = parent

	editableMesh:Destroy()
	return true, "created"
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

for index, module in ipairs(modules) do
	if module:IsA("ModuleScript") then
		local okRequire, tileData = pcall(require, module)
		if okRequire and tileData then
			local ok, status = createTileMesh(tileData, folder)
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
				warn("[ChesterWorld StreetSurfaceV5] " .. tostring(module.Name) .. " failed: " .. tostring(status))
			end
		else
			meshPartFailures += 1
			warn("[ChesterWorld StreetSurfaceV5] require failed for " .. tostring(module.Name) .. ": " .. tostring(tileData))
		end
	end
	if index % 6 == 0 then
		task.wait()
	end
end

print(string.format(
	"[ChesterWorld StreetSurfaceV5] modules=%d built=%d empty=%d noSurface=%d editableFailures=%d meshPartFailures=%d",
	#modules,
	built,
	empty,
	noSurface,
	editableFailures,
	meshPartFailures
))
