-- EXIT 6 native Terrain water, shared by the one-time Studio bake and
-- the old live-server fallback. Only imported GIS water rectangles are used.
-- Does not excavate solid terrain or change roads/highway profiles.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain

local M = {}
local VOXEL = 4
local MAX_PATCH = 64
local HASH_MOD = 2147483647

local function hashNext(h, value)
    return (h * 131 + (math.floor(value) % HASH_MOD)) % HASH_MOD
end

function M.Dataset()
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local data = shared and shared:FindFirstChild("WaterData")
    local folder = data and data:FindFirstChild("Tiles")
    if not folder then return nil, "no-water-tiles-folder" end
    local scripts = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("ModuleScript") and child.Name:match("^tile_r%d+_c%d+$") then
            table.insert(scripts, child)
        end
    end
    table.sort(scripts, function(a,b) return a.Name < b.Name end)
    if #scripts == 0 then return nil, "no-water-tiles" end

    local result = {tiles = {}, rects = 0, patches = 0}
    local h = 1
    for _, item in ipairs(scripts) do
        local module = require(item)
        if type(module) ~= "table" or type(module.rects) ~= "table" then
            return nil, "invalid-water-tile-" .. item.Name
        end
        for i = 1, #item.Name do h = hashNext(h, string.byte(item.Name, i)) end
        local tile = {name = item.Name, rects = {}}
        for _, r in ipairs(module.rects) do
            local x,z,w,d,k = r[1],r[2],r[3],r[4],r[5]
            if type(x) ~= "number" or type(z) ~= "number"
                or type(w) ~= "number" or type(d) ~= "number"
                or type(k) ~= "number" or w <= 0 or d <= 0
                or x % VOXEL ~= 0 or z % VOXEL ~= 0
                or w % VOXEL ~= 0 or d % VOXEL ~= 0
                or (k ~= 1 and k ~= 2) then
                return nil, "bad-voxel-rectangle-" .. item.Name
            end
            for _, v in ipairs({x,z,w,d,k}) do h = hashNext(h,v) end
            result.rects += 1
            result.patches += math.ceil(w / MAX_PATCH) * math.ceil(d / MAX_PATCH)
            table.insert(tile.rects, r)
        end
        table.insert(result.tiles, tile)
    end
    local manifestScript = data:FindFirstChild("Manifest")
    if not manifestScript or not manifestScript:IsA("ModuleScript") then
        return nil, "no-water-manifest"
    end
    local manifest = require(manifestScript)
    if manifest.tiles ~= #result.tiles or manifest.rects ~= result.rects then
        return nil, "water-manifest-count-mismatch"
    end
    result.signature = string.format("exit6-water-v2:%d:%d:%d",
        #result.tiles,result.rects,h)
    return result, nil
end

local function waterVoxel(x,y,z)
    local region = Region3.new(Vector3.new(x-2,y-2,z-2),
        Vector3.new(x+2,y+2,z+2))
    local materials,occupancy = Terrain:ReadVoxels(region,VOXEL)
    return materials[1][1][1] == Enum.Material.Water
        and occupancy[1][1][1] > 0
end

-- Proof is a list of exact water-voxel CENTERS written in Edit mode.
-- A matching attribute alone is NEVER considered evidence of baked terrain.
function M.Verify(dataset)
    dataset = dataset or M.Dataset()
    if not dataset then return false, "no-dataset" end
    local stored = Terrain:GetAttribute("CW_WaterBakeSignature")
    if stored ~= dataset.signature then
        return false, stored and "signature-mismatch" or "not-baked"
    end
    local proof = Terrain:GetAttribute("CW_WaterBakeProof")
    if type(proof) ~= "string" or proof == "" then
        return false, "missing-voxel-proof"
    end
    local count = 0
    for sx,sy,sz in proof:gmatch("(-?%d+),(-?%d+),(-?%d+)") do
        local x,y,z = tonumber(sx),tonumber(sy),tonumber(sz)
        if x%4 ~= 2 or y%4 ~= 2 or z%4 ~= 2 then
            return false, "misaligned-voxel-proof"
        end
        local ok,hasWater = pcall(waterVoxel,x,y,z)
        if not ok or not hasWater then
            return false, "water-proof-missing-at-" .. sx .. "," .. sy .. "," .. sz
        end
        count += 1
    end
    local expectedProbes = Terrain:GetAttribute("CW_WaterBakeProbeCount")
    if count < math.min(12,#dataset.tiles) or expectedProbes ~= count then
        return false, "insufficient-water-proof"
    end
    return true, "verified-" .. tostring(count) .. "-water-voxels"
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {Terrain}
params.IgnoreWater = true

local function solidGroundY(x,z)
    local hit = Workspace:Raycast(
        Vector3.new(x,5000,z),Vector3.new(0,-10000,0),params)
    return hit and hit.Position.Y or nil
end

function M.ApplyWaterAppearance()
    Terrain.WaterColor = Color3.fromRGB(41,82,84)
    Terrain.WaterTransparency = 0.42
    Terrain.WaterReflectance = 0.08
    Terrain.WaterWaveSize = 0.18
    Terrain.WaterWaveSpeed = 5
end

function M.Build(dataset, progress)
    if not dataset then error("Cannot generate water without GIS dataset") end
    M.ApplyWaterAppearance()
    local written = 0
    local skippedSolid = 0
    local patches = 0
    local probes = {}

    local function patch(x0,z0,w,d)
        local y = solidGroundY(x0 + w/2, z0 + d/2)
        -- Retain the proven first-pass height behavior. Any changes to
        -- global Delaware water level require separate terrain survey.
        local top = y and (math.ceil(y/VOXEL)*VOXEL + VOXEL) or VOXEL
        local bottom = top - 20
        local region = Region3.new(Vector3.new(x0,bottom,z0),
            Vector3.new(x0+w,top,z0+d))
        local materials,occupancy = Terrain:ReadVoxels(region,VOXEL)
        local changed = false
        local proof
        local nx,ny,nz = w/VOXEL,(top-bottom)/VOXEL,d/VOXEL
        for ix = 1,nx do
            for iy = 1,ny do
                for iz = 1,nz do
                    local m = materials[ix][iy][iz]
                    if m == Enum.Material.Air or occupancy[ix][iy][iz] <= 0 then
                        materials[ix][iy][iz] = Enum.Material.Water
                        occupancy[ix][iy][iz] = 1
                        changed = true
                        written += 1
                        if not proof then
                            proof = {x0 + ix*4-2,bottom + iy*4-2,z0 + iz*4-2}
                        end
                    elseif m == Enum.Material.Water and not proof then
                        proof = {x0 + ix*4-2,bottom + iy*4-2,z0 + iz*4-2}
                    elseif m ~= Enum.Material.Water then
                        skippedSolid += 1
                    end
                end
            end
        end
        if changed then Terrain:WriteVoxels(region,VOXEL,materials,occupancy) end
        patches += 1
        if patches % 32 == 0 then
            if progress then progress(patches,dataset.patches) end
            task.wait()
        end
        return proof
    end

    for _, tile in ipairs(dataset.tiles) do
        local tileProof
        for _, r in ipairs(tile.rects) do
            local x0,z0,w,d = r[1],r[2],r[3],r[4]
            for x = x0,x0+w-VOXEL,MAX_PATCH do
                local pw = math.min(MAX_PATCH,x0+w-x)
                for z = z0,z0+d-VOXEL,MAX_PATCH do
                    local pd = math.min(MAX_PATCH,z0+d-z)
                    local found = patch(x,z,pw,pd)
                    if not tileProof then tileProof = found end
                end
            end
        end
        if tileProof then
            table.insert(probes, tileProof)
        else
            warn("[EXIT6 Water] No water proof found for " .. tile.name)
        end
    end
    if progress then progress(patches,dataset.patches) end
    if patches ~= dataset.patches then
        error("Water patch mismatch: " .. patches .. " / " .. dataset.patches)
    end
    return {
        tiles = #dataset.tiles,rects = dataset.rects,patches = patches,
        filled = written,solidProtected = skippedSolid,
        probes = probes,signature = dataset.signature
    }
end

return M
