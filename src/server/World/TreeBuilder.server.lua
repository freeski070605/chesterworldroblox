-- Trees where Chester has real tree canopy (PASDA 2013 1 m land cover).
-- Data: src/shared/WorldData/StreetTrees.lua (tools/build_street_trees.py),
-- placed clear of building rectangles, road carriageways and highway / rail
-- corridors. Built after the world so trunks stand on the final terrain.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local module = Shared:WaitForChild("WorldData"):FindFirstChild("StreetTrees")
if not module then return end

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end
if Workspace:FindFirstChild("ChesterTrees") then return end
local root = Instance.new("Folder")
root.Name = "ChesterTrees"
root.Parent = Workspace

local Trees = require(module)
local S = WorldConfig.STUDS_PER_METER
local CX, CZ = WorldConfig.WORLD_CENTER_X_M, WorldConfig.WORLD_CENTER_Z_M
local H = 1 / 1.302 -- Mercator crown metres -> real metres (vertical scale is real)

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { Workspace.Terrain }

local LEAVES = {
	Color3.fromRGB(58, 92, 40), Color3.fromRGB(70, 104, 46), Color3.fromRGB(52, 82, 44),
	Color3.fromRGB(84, 112, 52), Color3.fromRGB(64, 98, 56),
}
local BARK = Color3.fromRGB(86, 70, 58)

local built, skipped = 0, 0
local chunk
for i, t in ipairs(Trees) do
	if not chunk then
		chunk = Instance.new("Folder")
		chunk.Name = "Trees" .. i
	end
	local x, z = (t[1] - CX) * S, -(t[2] - CZ) * S
	local hit = Workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), params)
	if hit and hit.Material ~= Enum.Material.Water then
		local y = hit.Position.Y
		local crown = t[3] * H * S
		local height = t[4] * S
		local trunkH = math.max(height - crown * 0.75, 6)
		local trunk = Instance.new("Part")
		trunk.Name = "Trunk"
		trunk.Shape = Enum.PartType.Cylinder
		trunk.Size = Vector3.new(trunkH + 1, math.clamp(crown * 0.07, 1.2, 3), math.clamp(crown * 0.07, 1.2, 3))
		trunk.CFrame = CFrame.new(x, y + trunkH / 2 - 0.5, z) * CFrame.Angles(0, 0, math.rad(90))
		trunk.Anchored = true
		trunk.Material = Enum.Material.Wood
		trunk.Color = BARK
		trunk.Parent = chunk
		local leaves = Instance.new("Part")
		leaves.Name = "Crown"
		leaves.Shape = Enum.PartType.Ball
		leaves.Size = Vector3.new(crown, crown, crown)
		leaves.CFrame = CFrame.new(x, y + height - crown / 2, z)
		leaves.Anchored = true
		leaves.CanCollide = false
		leaves.Material = Enum.Material.Grass
		leaves.Color = LEAVES[i % #LEAVES + 1]
		leaves.Parent = chunk
		built += 1
	else
		skipped += 1
	end
	if i % 400 == 0 then
		chunk.Parent = root
		chunk = nil
		task.wait()
	end
end
if chunk then chunk.Parent = root end
print(("[ChesterWorld Trees] built=%d skipped=%d (water/no terrain)"):format(built, skipped))
