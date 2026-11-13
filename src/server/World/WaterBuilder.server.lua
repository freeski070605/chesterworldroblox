-- EXIT 6 mapped water: only sources from WaterData/Tile modules.
-- Wait until road/highway/park/gas construction is complete so terrain
-- operations never interrupt Industrial or elevation/bridge repairs.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = Workspace.Terrain
Workspace:SetAttribute("CW_WaterComplete", false)
Workspace:SetAttribute("CW_WaterStatus", "waiting")
Workspace:SetAttribute("CW_WaterPatchesDone", 0)
Workspace:SetAttribute("CW_WaterPatchesTotal", 0)

local function readyForWater()
    return Workspace:GetAttribute("CW_BootstrapComplete") == true
        and Workspace:GetAttribute("CW_RoadConformComplete") == true
        and Workspace:GetAttribute("CW_HighwayFinishComplete") == true
        and Workspace:GetAttribute("CW_ParksComplete") == true
        and Workspace:GetAttribute("CW_GasStationsComplete") == true
        and Workspace:GetAttribute("CW_RoadTerrainCleared") == true
        and Workspace:GetAttribute("CW_LandmarksComplete") == true
        and Workspace:GetAttribute("CW_LocalBridgesDressed") == true
end
local previousStage = ""
while not readyForWater() do
    local stage = "waiting-for-structures"
    if Workspace:GetAttribute("CW_RoadTerrainCleared") ~= true then
        stage = "waiting-for-road-terrain-clear"
    elseif Workspace:GetAttribute("CW_LandmarksComplete") ~= true then
        stage = "waiting-for-landmarks"
    elseif Workspace:GetAttribute("CW_LocalBridgesDressed") ~= true then
        stage = "waiting-for-local-bridges"
    end
    if stage ~= previousStage then
        Workspace:SetAttribute("CW_WaterStatus", stage)
        previousStage = stage
    end
    task.wait(0.5)
end

local Shared = ReplicatedStorage:FindFirstChild("Shared")
local waterData = Shared and Shared:FindFirstChild("WaterData")
local folder = waterData and waterData:FindFirstChild("Tiles")
if not folder or #folder:GetChildren() == 0 then
    -- Preserve existing live games until the one-pass GIS export has been run.
    warn("[EXIT6 Water] GIS tiles have not been exported. Run build_exit6_water.py on E:; no fake shorelines generated.")
    Workspace:SetAttribute("CW_WaterStatus", "source-not-exported")
    Workspace:SetAttribute("CW_WaterComplete", true)
    return
end

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = {Terrain}
terrainRay.IgnoreWater = true

local function groundY(x, z)
    local hit = Workspace:Raycast(Vector3.new(x, 5000, z),
        Vector3.new(0, -10000, 0), terrainRay)
    return hit and hit.Position.Y or nil
end

local VOXEL = 4
local MAX_PATCH = 64  -- bounded ReadVoxels/WriteVoxels allocations
local writtenVoxels = 0
local skippedSolid = 0
local patchCount = 0

-- Only write into AIR: existing terrain, riverbanks, roads, and
-- imported heightmaps are never excavated or overwritten. Water
-- naturally occupies gaps and space above the riverbed.
local function fillAirOnly(x0, z0, w, d)
    local mx, mz = x0 + w / 2, z0 + d / 2
    local y = groundY(mx, mz)
    local top = (y and (math.ceil(y / VOXEL) * VOXEL + VOXEL) or VOXEL)
    local bottom = top - 20
    local region = Region3.new(
        Vector3.new(x0, bottom, z0),
        Vector3.new(x0 + w, top, z0 + d))
    local materials, occupancy = Terrain:ReadVoxels(region, VOXEL)
    local changed = false
    local nx, ny, nz = math.floor(w / VOXEL),
        math.floor((top - bottom) / VOXEL), math.floor(d / VOXEL)
    for ix = 1, nx do
        for iy = 1, ny do
            for iz = 1, nz do
                if materials[ix][iy][iz] == Enum.Material.Air
                        or occupancy[ix][iy][iz] <= 0 then
                    materials[ix][iy][iz] = Enum.Material.Water
                    occupancy[ix][iy][iz] = 1
                    changed = true
                    writtenVoxels += 1
                elseif materials[ix][iy][iz] ~= Enum.Material.Water then
                    skippedSolid += 1
                end
            end
        end
    end
    if changed then
        Terrain:WriteVoxels(region, VOXEL, materials, occupancy)
    end
    patchCount += 1
    if patchCount % 32 == 0 then
        Workspace:SetAttribute("CW_WaterPatchesDone", patchCount)
        task.wait()
    end
end

local function build()
    Terrain.WaterColor = Color3.fromRGB(41, 82, 84)
    Terrain.WaterTransparency = 0.42
    Terrain.WaterReflectance = 0.08
    Terrain.WaterWaveSize = 0.18
    Terrain.WaterWaveSpeed = 5

    local modules = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ModuleScript") and child.Name:match("^tile_r%d+_c%d+$") then
            table.insert(modules, child)
        end
    end
    table.sort(modules, function(a, b) return a.Name < b.Name end)
    local rectangles = {}
    local totalPatches = 0
    for _, module in ipairs(modules) do
        local data = require(module)
        for _, r in ipairs(data.rects or {}) do
            local w, d = r[3], r[4]
            if w > 0 and d > 0
                and w % VOXEL == 0 and d % VOXEL == 0
                and r[1] % VOXEL == 0 and r[2] % VOXEL == 0 then
                table.insert(rectangles, r)
                totalPatches += math.ceil(w / MAX_PATCH) * math.ceil(d / MAX_PATCH)
            else
                warn("[EXIT6 Water] Invalid voxel-alignment skipped in " .. module.Name)
            end
        end
    end
    if #rectangles == 0 then error("No valid water rectangles in GIS modules") end
    Workspace:SetAttribute("CW_WaterPatchesTotal", totalPatches)
    Workspace:SetAttribute("CW_WaterStatus", "building")
    print(("[EXIT6 Water] mapped water modules=%d rectangles=%d patches=%d, preserveSolid=true")
        :format(#modules, #rectangles, totalPatches))
    for _, r in ipairs(rectangles) do
        local x0, z0, w, d = r[1], r[2], r[3], r[4]
        for x = x0, x0 + w - VOXEL, MAX_PATCH do
            local pw = math.min(MAX_PATCH, x0 + w - x)
            for z = z0, z0 + d - VOXEL, MAX_PATCH do
                local pd = math.min(MAX_PATCH, z0 + d - z)
                fillAirOnly(x, z, pw, pd)
            end
        end
    end
    Workspace:SetAttribute("CW_WaterPatchesDone", patchCount)
    Workspace:SetAttribute("CW_WaterSolidCellsProtected", skippedSolid)
    Workspace:SetAttribute("CW_WaterFilledVoxels", writtenVoxels)
    Workspace:SetAttribute("CW_WaterStatus", "complete")
    Workspace:SetAttribute("CW_WaterComplete", true)
    print(("[EXIT6 Water] COMPLETE modules=%d patches=%d waterVoxels=%d solidProtected=%d")
        :format(#modules, patchCount, writtenVoxels, skippedSolid))
end

local ok, err = xpcall(build, debug.traceback)
if not ok then
    Workspace:SetAttribute("CW_WaterStatus", "failed")
    Workspace:SetAttribute("CW_WaterError", tostring(err):sub(1, 800))
    warn("[EXIT6 Water] FAILED: " .. tostring(err))
    -- Deliberately do not mark complete; loading screen shows the failure.
end
