-- Opt-in reconstruction preview. OFF by default; existing city remains untouched.
-- In Studio set workspace attribute CW_ReconstructionPilot = true, then Play.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if workspace:GetAttribute("CW_ReconstructionPilot") ~= true then
    return
end
local shared = ReplicatedStorage:WaitForChild("Shared")
local dataModule = shared:FindFirstChild("ReconstructionPilot")
if not dataModule then
    warn("[CW Reconstruction] Missing src/shared/ReconstructionPilot.lua; run GeoJSON converter first")
    return
end
local data = require(dataModule)
local folder = Instance.new("Folder")
folder.Name = "CW_ReconstructionPreview"
folder.Parent = workspace
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }
params.IgnoreWater = true
local function terrainY(x, z)
    local hit = workspace:Raycast(Vector3.new(x, 5000, z), Vector3.new(0, -10000, 0), params)
    return hit and hit.Position.Y or nil
end
local count = 0
for _, footprint in ipairs(data.buildings or {}) do
    if count >= 50 then
        warn("[CW Reconstruction] Preview capped at 50 buildings to protect Studio performance")
        break
    end
    local points = footprint.points or {}
    if #points >= 3 then
        local model = Instance.new("Model")
        model.Name = "Building_" .. tostring(count + 1)
        model:SetAttribute("CW_SourceId", footprint.id)
        model:SetAttribute("CW_PreviewOnly", true)
        model.Parent = folder
        local h = math.clamp(tonumber(footprint.height) or 27, 6, 300)
        for index = 1, #points do
            local a, b = points[index], points[index % #points + 1]
            local ax, az = tonumber(a[1]), tonumber(a[2])
            local bx, bz = tonumber(b[1]), tonumber(b[2])
            if ax and az and bx and bz then
                local mx, mz = (ax + bx) / 2, (az + bz) / 2
                local length = math.sqrt((bx-ax)^2 + (bz-az)^2)
                local ground = terrainY(mx, mz)
                if ground and length > 0.15 and length < 250 then
                    local wall = Instance.new("Part")
                    wall.Name = "FootprintWall"
                    wall.Size = Vector3.new(0.35, h, length)
                    wall.Anchored = true
                    wall.CanCollide = false
                    wall.Material = Enum.Material.SmoothPlastic
                    wall.Color = Color3.fromRGB(220, 175, 100)
                    local center = Vector3.new(mx, ground + h/2, mz)
                    wall.CFrame = CFrame.lookAt(center, center + Vector3.new(bx-ax, 0, bz-az))
                    wall.Parent = model
                end
            end
        end
        count += 1
    end
end
print(("[CW Reconstruction] Previewed %d georeferenced footprint(s), source=%s. Geometry is NOT validated against aerials.")
    :format(count, tostring(data.metadata and data.metadata.source or "unknown")))
