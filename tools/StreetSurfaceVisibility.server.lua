local Workspace = game:GetService("Workspace")
local world = Workspace:WaitForChild("ChesterWorld")

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do
	task.wait(0.20)
end

local surfaceFolder = world:WaitForChild("StreetSurfaceV5", 120)
if not surfaceFolder then
	warn("[ChesterWorld StreetSurfaceV5.1] StreetSurfaceV5 folder missing; legacy roads left visible.")
	return
end

local lastCount = -1
local stable = 0
local elapsed = 0

while elapsed < 120 do
	local count = 0
	for _, obj in ipairs(surfaceFolder:GetChildren()) do
		if obj:IsA("MeshPart") then
			count += 1
		end
	end

	if count > 0 and count == lastCount then
		stable += 1
	else
		stable = 0
		lastCount = count
	end

	if stable >= 4 then
		break
	end

	task.wait(0.75)
	elapsed += 0.75
end

local meshCount = 0
for _, obj in ipairs(surfaceFolder:GetChildren()) do
	if obj:IsA("MeshPart") then
		obj.CanQuery = false
		meshCount += 1
	end
end

if meshCount == 0 then
	warn("[ChesterWorld StreetSurfaceV5.1] No V5 MeshParts found; legacy roads left visible.")
	return
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {surfaceFolder}
params.IgnoreWater = true

local RAY_UP = 4.0
local RAY_DOWN = 10.0
local MAX_VERTICAL_DELTA = 2.25

local function v5CoversRoad(road)
	local result = Workspace:Raycast(
		road.Position + Vector3.new(0, RAY_UP, 0),
		Vector3.new(0, -RAY_DOWN, 0),
		params
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

local totalRoads = 0
local hidden = 0
local fallbackVisible = 0

for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, road in ipairs(roads:GetDescendants()) do
			if road:IsA("BasePart") then
				totalRoads += 1

				if v5CoversRoad(road) then
					road.Transparency = 1
					road.CastShadow = false
					road:SetAttribute("CW_HiddenByStreetSurfaceV5", true)
					hidden += 1
				else
					road:SetAttribute("CW_HiddenByStreetSurfaceV5", false)
					fallbackVisible += 1
				end
			end
		end
	end

	if totalRoads % 1000 < 60 then
		task.wait()
	end
end

Workspace:SetAttribute("CW_StreetSurfaceV51VisibilityComplete", true)

print(string.format(
	"[ChesterWorld StreetSurfaceV5.1] meshes=%d roads=%d hiddenLegacy=%d fallbackVisible=%d",
	meshCount,
	totalRoads,
	hidden,
	fallbackVisible
))
