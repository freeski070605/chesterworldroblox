local Workspace = game:GetService("Workspace")

local world = Workspace:WaitForChild("ChesterWorld")

while Workspace:GetAttribute("CW_StreetSurfaceV53Complete") ~= true do
	task.wait(0.20)
end

local surfaceFolder = world:WaitForChild("StreetSurfaceV53", 60)

if not surfaceFolder then
	warn("[ChesterWorld StreetSurfaceV5.4] StreetSurfaceV53 folder missing.")
	return
end

local meshes = {}

for _, obj in ipairs(surfaceFolder:GetChildren()) do
	if obj:IsA("MeshPart") then
		obj.CanQuery = true
		table.insert(meshes, obj)
	end
end

if #meshes == 0 then
	warn("[ChesterWorld StreetSurfaceV5.4] No V5.3 MeshParts found.")
	return
end

local meshRayParams = RaycastParams.new()
meshRayParams.FilterType = Enum.RaycastFilterType.Include
meshRayParams.FilterDescendantsInstances = {surfaceFolder}
meshRayParams.IgnoreWater = true

local RAY_START_Y = 2048
local RAY_DISTANCE = 4096

local function meshAtXZ(x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, RAY_START_Y, z),
		Vector3.new(0, -RAY_DISTANCE, 0),
		meshRayParams
	)

	return result ~= nil
end

local function roadAxes(road)
	if road.Size.X >= road.Size.Z then
		return road.CFrame.RightVector, road.CFrame.LookVector, road.Size.X, road.Size.Z
	else
		return road.CFrame.LookVector, road.CFrame.RightVector, road.Size.Z, road.Size.X
	end
end

local function coveredByV53(road)
	local longAxis, sideAxis, length, width = roadAxes(road)

	local samples = {
		road.Position,
		road.Position + longAxis * (length * 0.30),
		road.Position - longAxis * (length * 0.30),
	}

	if width >= 8 then
		table.insert(samples, road.Position + sideAxis * (width * 0.25))
		table.insert(samples, road.Position - sideAxis * (width * 0.25))
	end

	for _, p in ipairs(samples) do
		if meshAtXZ(p.X, p.Z) then
			return true
		end
	end

	return false
end

local totalRoads = 0
local hidden = 0
local visibleFallback = 0

for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")

	if roads then
		for _, road in ipairs(roads:GetDescendants()) do
			if road:IsA("BasePart") then
				totalRoads += 1

				if coveredByV53(road) then
					road.Transparency = 1
					road.CastShadow = false
					road:SetAttribute("CW_HiddenByStreetSurfaceV54", true)
					hidden += 1
				else
					road.Transparency = 0
					road:SetAttribute("CW_HiddenByStreetSurfaceV54", false)
					visibleFallback += 1
				end

				if totalRoads % 500 == 0 then
					task.wait()
				end
			end
		end
	end
end

for _, mesh in ipairs(meshes) do
	mesh.CanQuery = false
end

Workspace:SetAttribute("CW_StreetSurfaceV54VisibilityComplete", true)

print(string.format(
	"[ChesterWorld StreetSurfaceV5.4] meshes=%d roads=%d hiddenLegacy=%d fallbackVisible=%d hiddenPct=%.2f",
	#meshes,
	totalRoads,
	hidden,
	visibleFallback,
	totalRoads > 0 and (hidden / totalRoads * 100) or 0
))
