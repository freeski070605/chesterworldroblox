-- ChesterWorld - IntersectionSurfaceBuilder.server.lua
-- INTERSECTION SURFACE V6
--
-- Permanent architecture:
--   * V3.2 roads stay visible everywhere
--   * only road ends entering true junctions are trimmed back
--   * source-derived intersection meshes fill those junctions
--   * source sidewalks entering the junction are trimmed back too
--
-- No full-network visibility handoff.
-- No dirt-road failure mode.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IntersectionData = require(
	Shared:WaitForChild("IntersectionSurfaceData")
)
local SurfaceTiles = Shared:WaitForChild("IntersectionSurfaceTiles")

local world = Workspace:WaitForChild("ChesterWorld")
local terrain = Workspace.Terrain

local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

local JUNCTION_TERRAIN_OFFSET = 0.42
local MAX_PLANE_GRADE = 0.16

local JUNCTION_GRID_CELL = 90.0
local END_MATCH_EXTRA = 8.0

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

-- Wait for source sidewalks to finish because V6 trims them too.
local sidewalkFolder = nil
local waitStart = os.clock()
local lastSidewalkCount = -1
local stableTicks = 0

while os.clock() - waitStart < 90 do
	local finish = world:FindFirstChild("StreetFinish")
	local candidate = finish and finish:FindFirstChild("SourceSidewalks")

	if candidate then
		local count = 0
		for _, obj in ipairs(candidate:GetChildren()) do
			if obj:IsA("BasePart") then
				count += 1
			end
		end

		if count > 0 and count == lastSidewalkCount then
			stableTicks += 1
		else
			stableTicks = 0
			lastSidewalkCount = count
		end

		if stableTicks >= 4 then
			sidewalkFolder = candidate
			break
		end
	end

	task.wait(0.5)
end

-- Remove every old experimental runtime surface folder.
for _, name in ipairs({
	"StreetSurfaceV4",
	"StreetSurfaceV5",
	"StreetSurfaceV53",
	"IntersectionSurfaceV6",
}) do
	local folder = world:FindFirstChild(name)
	if folder then
		folder:Destroy()
	end
end

-- Restore every legacy road to visible before doing surgical junction trimming.
local roadFolders = {}

for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")

	if roads then
		table.insert(roadFolders, roads)

		for _, road in ipairs(roads:GetDescendants()) do
			if road:IsA("BasePart") then
				road.Transparency = 0
				road.CastShadow = true
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- TERRAIN / ROAD HEIGHT SAMPLING
-- ---------------------------------------------------------------------------

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {terrain}
terrainParams.IgnoreWater = false

local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
surfaceParams.IgnoreWater = false

local surfaceTargets = {terrain}

for _, folder in ipairs(roadFolders) do
	table.insert(surfaceTargets, folder)
end

surfaceParams.FilterDescendantsInstances = surfaceTargets

local function rayY(params, x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		params
	)

	return result and result.Position.Y or nil
end

local function terrainY(x, z)
	return rayY(terrainParams, x, z)
end

local function surfaceY(x, z)
	return rayY(surfaceParams, x, z)
end

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- ---------------------------------------------------------------------------
-- JUNCTION GRID / PLANES
-- ---------------------------------------------------------------------------

local grid = {}
local planes = {}

local function gridCoord(v)
	return math.floor(v / JUNCTION_GRID_CELL)
end

local function gridKey(gx, gz)
	return tostring(gx) .. ":" .. tostring(gz)
end

for index, junction in ipairs(IntersectionData.junctions) do
	local fitRadius = clamp(junction.radius * 0.35, 5, 13)

	local cy = terrainY(junction.x, junction.z)

	if cy then
		local east = terrainY(junction.x + fitRadius, junction.z) or cy
		local west = terrainY(junction.x - fitRadius, junction.z) or cy
		local south = terrainY(junction.x, junction.z + fitRadius) or cy
		local north = terrainY(junction.x, junction.z - fitRadius) or cy

		local gradeX = clamp(
			(east - west) / (fitRadius * 2),
			-MAX_PLANE_GRADE,
			MAX_PLANE_GRADE
		)

		local gradeZ = clamp(
			(south - north) / (fitRadius * 2),
			-MAX_PLANE_GRADE,
			MAX_PLANE_GRADE
		)

		local plane = {
			index = index,
			x = junction.x,
			z = junction.z,
			radius = junction.radius,
			centerY = cy + JUNCTION_TERRAIN_OFFSET,
			gradeX = gradeX,
			gradeZ = gradeZ,
		}

		planes[index] = plane

		local searchRadius = junction.radius + END_MATCH_EXTRA
		local minGX = gridCoord(junction.x - searchRadius)
		local maxGX = gridCoord(junction.x + searchRadius)
		local minGZ = gridCoord(junction.z - searchRadius)
		local maxGZ = gridCoord(junction.z + searchRadius)

		for gx = minGX, maxGX do
			for gz = minGZ, maxGZ do
				local key = gridKey(gx, gz)
				local bucket = grid[key]

				if not bucket then
					bucket = {}
					grid[key] = bucket
				end

				table.insert(bucket, plane)
			end
		end
	end
end

local function nearbyJunctions(x, z)
	return grid[
		gridKey(
			gridCoord(x),
			gridCoord(z)
		)
	] or {}
end

local function planeYForVertex(x, z, baseY)
	local best = nil
	local bestDistance = math.huge

	for _, plane in ipairs(nearbyJunctions(x, z)) do
		local dx = x - plane.x
		local dz = z - plane.z
		local distance = math.sqrt(dx * dx + dz * dz)

		if distance <= plane.radius + 2 and distance < bestDistance then
			bestDistance = distance
			best = plane
		end
	end

	if not best then
		return baseY
	end

	return (
		best.centerY
		+ best.gradeX * (x - best.x)
		+ best.gradeZ * (z - best.z)
	)
end

-- ---------------------------------------------------------------------------
-- TRIM ROAD / SIDEWALK ENDS
-- ---------------------------------------------------------------------------

local function inferLongAxis(part)
	if part.Size.X >= part.Size.Z then
		return "X", part.CFrame.RightVector, part.Size.X
	else
		return "Z", part.CFrame.LookVector, part.Size.Z
	end
end

local function horizontalDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function trimPartAtJunctions(part, overlapStuds)
	local axisKind, longAxis, length = inferLongAxis(part)

	local half = length / 2

	local startPoint = part.Position - longAxis * half
	local endPoint = part.Position + longAxis * half

	local startTrim = 0
	local endTrim = 0

	for _, plane in ipairs(nearbyJunctions(part.Position.X, part.Position.Z)) do
		local center = Vector3.new(plane.x, part.Position.Y, plane.z)
		local desiredDistance = math.max(0, plane.radius - overlapStuds)

		local startDistance = horizontalDistance(startPoint, center)
		local endDistance = horizontalDistance(endPoint, center)

		if startDistance <= plane.radius + END_MATCH_EXTRA then
			startTrim = math.max(
				startTrim,
				desiredDistance - startDistance
			)
		end

		if endDistance <= plane.radius + END_MATCH_EXTRA then
			endTrim = math.max(
				endTrim,
				desiredDistance - endDistance
			)
		end
	end

	startTrim = math.max(0, startTrim)
	endTrim = math.max(0, endTrim)

	if startTrim <= 0 and endTrim <= 0 then
		return false, false
	end

	local newLength = length - startTrim - endTrim

	if newLength < 1.5 then
		part.Transparency = 1
		part.CanCollide = false
		part:SetAttribute("CW_TrimmedByIntersectionV6", true)
		return true, true
	end

	local shift = longAxis * ((startTrim - endTrim) / 2)

	local rotationOnly = part.CFrame - part.CFrame.Position
	part.CFrame = CFrame.new(part.Position + shift) * rotationOnly

	if axisKind == "X" then
		part.Size = Vector3.new(
			newLength,
			part.Size.Y,
			part.Size.Z
		)
	else
		part.Size = Vector3.new(
			part.Size.X,
			part.Size.Y,
			newLength
		)
	end

	part:SetAttribute("CW_TrimmedByIntersectionV6", true)

	return true, false
end

local roadsTrimmed = 0
local roadsHidden = 0
local totalRoads = 0

for _, folder in ipairs(roadFolders) do
	for _, road in ipairs(folder:GetDescendants()) do
		if road:IsA("BasePart") then
			totalRoads += 1

			local changed, hidden = trimPartAtJunctions(
				road,
				IntersectionData.roadOverlapStuds or 1.5
			)

			if changed then
				roadsTrimmed += 1
			end

			if hidden then
				roadsHidden += 1
			end

			if totalRoads % 500 == 0 then
				task.wait()
			end
		end
	end
end

local sidewalksTrimmed = 0
local sidewalksHidden = 0
local totalSidewalks = 0

if sidewalkFolder then
	for _, sidewalk in ipairs(sidewalkFolder:GetDescendants()) do
		if sidewalk:IsA("BasePart") then
			totalSidewalks += 1

			local changed, hidden = trimPartAtJunctions(
				sidewalk,
				IntersectionData.sidewalkOverlapStuds or 0.5
			)

			if changed then
				sidewalksTrimmed += 1
			end

			if hidden then
				sidewalksHidden += 1
			end

			if totalSidewalks % 500 == 0 then
				task.wait()
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- BUILD INTERSECTION-ONLY MESHES
-- ---------------------------------------------------------------------------

local surfaceFolder = Instance.new("Folder")
surfaceFolder.Name = "IntersectionSurfaceV6"
surfaceFolder.Parent = world

local modules = SurfaceTiles:GetChildren()
table.sort(modules, function(a, b)
	return a.Name < b.Name
end)

local built = 0
local noSurface = 0
local meshFailures = 0

for index, module in ipairs(modules) do
	if module:IsA("ModuleScript") then
		local okRequire, data = pcall(require, module)

		if okRequire and data then
			local verticesFlat = data.vertices
			local trianglesFlat = data.triangles

			local sampledY = {}
			local minY = math.huge
			local valid = true

			for i = 1, #verticesFlat, 2 do
				local worldX = data.originX + verticesFlat[i]
				local worldZ = data.originZ + verticesFlat[i + 1]

				local baseY = surfaceY(worldX, worldZ)

				if not baseY then
					valid = false
					break
				end

				local y = planeYForVertex(
					worldX,
					worldZ,
					baseY + 0.08
				)

				table.insert(sampledY, y)
				minY = math.min(minY, y)
			end

			if valid then
				local editableMesh = AssetService:CreateEditableMesh()

				if editableMesh then
					local ids = {}

					for i = 1, #verticesFlat, 2 do
						local n = ((i - 1) / 2) + 1

						ids[n] = editableMesh:AddVertex(
							Vector3.new(
								verticesFlat[i],
								sampledY[n] - minY,
								verticesFlat[i + 1]
							)
						)
					end

					for i = 1, #trianglesFlat, 3 do
						local a = ids[trianglesFlat[i]]
						local b = ids[trianglesFlat[i + 1]]
						local c = ids[trianglesFlat[i + 2]]

						if a and b and c then
							editableMesh:AddTriangle(a, b, c)
						end
					end

					local meshPart
					local okMesh = pcall(function()
						meshPart = AssetService:CreateMeshPartAsync(
							Content.fromObject(editableMesh),
							{
								CollisionFidelity = Enum.CollisionFidelity.Box,
							}
						)
					end)

					if okMesh and meshPart then
						meshPart.Name = "CW_IntersectionSurface_" .. tostring(data.surfaceId)
						meshPart.Anchored = true
						meshPart.CanCollide = false
						meshPart.CanTouch = false
						meshPart.CanQuery = false
						meshPart.CastShadow = false
						meshPart.DoubleSided = true
						meshPart.Material = Enum.Material.Asphalt
						meshPart.Color = Color3.fromRGB(72, 74, 78)
						meshPart.Size = meshPart.MeshSize
						meshPart.CFrame = CFrame.new(
							data.originX,
							minY,
							data.originZ
						)
						meshPart:SetAttribute("CW_IntersectionSurfaceV6", true)
						meshPart.Parent = surfaceFolder
						built += 1
					else
						meshFailures += 1
					end

					editableMesh:Destroy()
				else
					meshFailures += 1
				end
			else
				noSurface += 1
			end
		else
			meshFailures += 1
		end
	end

	if index % 10 == 0 then
		task.wait()
	end
end

Workspace:SetAttribute("CW_IntersectionSurfaceV6Complete", true)

print(string.format(
	"[ChesterWorld IntersectionSurfaceV6] junctionPlanes=%d meshModules=%d built=%d noSurface=%d meshFailures=%d roads=%d roadsTrimmed=%d roadsHidden=%d sidewalks=%d sidewalksTrimmed=%d sidewalksHidden=%d",
	#IntersectionData.junctions,
	#modules,
	built,
	noSurface,
	meshFailures,
	totalRoads,
	roadsTrimmed,
	roadsHidden,
	totalSidewalks,
	sidewalksTrimmed,
	sidewalksHidden
))
