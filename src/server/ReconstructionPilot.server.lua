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
-- Wait for the existing world to finish before probing terrain. This preview
-- must never block the normal loading pipeline or imply the world is ready.
local waitStart = os.clock()
while workspace:GetAttribute("CW_BootstrapComplete") ~= true do
    if os.clock() - waitStart > 300 then
        warn("[CW Reconstruction] Existing world did not finish loading within 300s; preview skipped")
        return
    end
    task.wait(1)
end
local data = require(dataModule)
local spawn = workspace:FindFirstChild("ChesterCitySpawn")
if not spawn then
    warn("[CW Reconstruction] No ChesterCitySpawn; cannot constrain preview to the pilot area")
    return
end
local pilotCenter = spawn.Position
local pilotRadius = 450 -- studs; keep demo local to current spawn
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
local inRange = 0
local noTerrain = 0
for _, footprint in ipairs(data.buildings or {}) do
    if count >= 50 then
        warn("[CW Reconstruction] Preview capped at 50 buildings to protect Studio performance")
        break
    end
    local points = footprint.points or {}
    if #points >= 3 then
        local cx, cz = 0, 0
        for _, p in ipairs(points) do
            cx += tonumber(p[1]) or 0
            cz += tonumber(p[2]) or 0
        end
        cx /= #points
        cz /= #points
        if (Vector2.new(cx, cz) - Vector2.new(pilotCenter.X, pilotCenter.Z)).Magnitude > pilotRadius then
            continue
        end
        inRange += 1
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
                if not ground then noTerrain += 1 end
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
print(("[CW Reconstruction] Previewed %d/%d nearby footprints; missing terrain wall samples=%d; source=%s. Positions not field-validated.")
    :format(count, inRange, noTerrain, tostring(data.metadata and data.metadata.source or "unknown")))
