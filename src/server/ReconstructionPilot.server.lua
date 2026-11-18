-- Opt-in reconstruction preview. OFF by default; existing city remains untouched.
-- In Studio set workspace attribute CW_ReconstructionPilot = true, then Play.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
if not game:GetService("RunService"):IsStudio() then return end
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
local waitStart = time()
while workspace:GetAttribute("CW_BootstrapComplete") ~= true do
    if time() - waitStart > 300 then
        warn("[CW Reconstruction] Existing world did not finish loading within 300s; preview skipped")
        return
    end
    task.wait(1)
end
local data = require(dataModule)
local associations = require(shared:WaitForChild("ReconstructionAssociations"))
local HouseKit = require(shared:WaitForChild("HouseKit"))
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
local started = os.clock()
local function partCount()
    local n = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("BasePart") then n += 1 end
    end
    return n
end
local beforeParts = partCount()
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
local roofParts = 0
local function roofTriangle(model, triangle, y)
    local a = Vector2.new(triangle[1][1], triangle[1][2])
    local b = Vector2.new(triangle[2][1], triangle[2][2])
    local c = Vector2.new(triangle[3][1], triangle[3][2])
    -- Make BC the longest side, so its perpendicular foot is inside BC.
    if (a-b).Magnitude > (b-c).Magnitude and (a-b).Magnitude > (c-a).Magnitude then
        a, b, c = c, a, b
    elseif (c-a).Magnitude > (b-c).Magnitude then
        a, b, c = b, c, a
    end
    local base = c-b
    if base.Magnitude < 0.05 then return end
    local foot = b + base.Unit * math.clamp((a-b):Dot(base.Unit), 0, base.Magnitude)
    local altitude = (a-foot).Magnitude
    if altitude < 0.05 then return end
    for _, endpoint in ipairs({b, c}) do
        local leg = (endpoint-foot).Magnitude
        if leg > 0.05 then
            local u, v = (a-foot).Unit, (endpoint-foot).Unit
            local uy = Vector3.new(u.X, 0, u.Y)
            -- Roblox wedge's right angle is at local -Y/+Z.
            local vz = Vector3.new(-v.X, 0, -v.Y)
            local middle = foot + (a-foot)/2 + (endpoint-foot)/2
            local wedge = Instance.new("WedgePart")
            wedge.Name = "RoofTriangle"
            wedge.Size = Vector3.new(0.32, altitude, leg)
            wedge.CFrame = CFrame.fromMatrix(Vector3.new(middle.X, y, middle.Y), uy:Cross(vz), uy, vz)
            wedge.Anchored = true
            wedge.CanCollide = false
            wedge.CanTouch = false
            wedge.CanQuery = false
            wedge.CastShadow = false
            wedge.Transparency = 0.38
            wedge.Material = Enum.Material.Slate
            wedge.Color = Color3.fromRGB(72, 68, 68)
            wedge.Parent = model
            roofParts += 1
        end
    end
end
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
        local baseGround = terrainY(cx, cz)
        if not baseGround then
            noTerrain += 1
            continue
        end
        inRange += 1
        local model = Instance.new("Model")
        model.Name = "Building_" .. tostring(count + 1)
        model:SetAttribute("CW_SourceId", footprint.id)
        model:SetAttribute("CW_GameBuildingId", associations[footprint.id] or "")
        model:SetAttribute("CW_HeightSource", footprint.heightSource)
        model:SetAttribute("CW_RoofSource", footprint.roofSource)
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
                local ground = baseGround
                if ground and length > 0.15 and length < 250 then
                    local center = Vector3.new(mx, ground + h/2, mz)
                    -- The wall's long axis is local Z; lookAt points local -Z
                    -- along the edge, so the wall follows that edge exactly.
                    local cf = CFrame.lookAt(center, center + Vector3.new(bx-ax, 0, bz-az))
                    local color = footprint.buildingType == "retail" and Color3.fromRGB(183, 153, 126)
                        or (footprint.buildingType == "school" and Color3.fromRGB(171, 126, 102)
                        or Color3.fromRGB(160, 92, 76))
                    local wall = HouseKit.H.part(model, "FootprintWall", Vector3.new(0.35, h, length), cf,
                        footprint.buildingType == "retail" and Enum.Material.Concrete or Enum.Material.Brick, color)
                    wall.CanCollide = false
                    wall.CanTouch = false
                    wall.CanQuery = false
                    wall.CastShadow = false
                    wall.Transparency = 0.38
                    local trim = HouseKit.H.part(model, "Cornice", Vector3.new(0.5, 0.5, length),
                        cf + Vector3.new(0, h/2 - 0.3, 0), Enum.Material.Concrete, HouseKit.H.TRIM)
                    trim.CanCollide = false
                    trim.CanTouch = false
                    trim.CanQuery = false
                    trim.CastShadow = false
                    trim.Transparency = 0.38
                end
            end
        end
        if model:GetChildren()[1] then
            local roofY = baseGround
            if roofY then
                for _, triangle in ipairs(footprint.roofTriangles or {}) do
                    roofTriangle(model, triangle, roofY + h + 0.16)
                end
            end
        end
        count += 1
    end
end
print(("[CW Reconstruction] Previewed %d/%d nearby footprints; missing terrain wall samples=%d; source=%s. Positions not field-validated.")
    :format(count, inRange, noTerrain, tostring(data.metadata and data.metadata.source or "unknown")))
local afterParts = partCount()
print(("[CW Reconstruction] parts_before=%d parts_after=%d delta=%d roof_wedges=%d elapsed_s=%.2f; " ..
    "Studio only; unknown heights and roofs are estimates")
    :format(beforeParts, afterParts, afterParts-beforeParts, roofParts, os.clock()-started))
