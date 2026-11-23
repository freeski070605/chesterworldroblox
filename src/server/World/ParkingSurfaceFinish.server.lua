-- Surface-only finish for mapped OSM ground and parking lots across the city.
-- Paint existing Terrain voxels; preserve occupancy, height and collision.
-- This adds no Parts and never guesses that an empty residential parcel is paved.
local Workspace = game:GetService("Workspace")
local Terrain = Workspace.Terrain
local groundAreas = require(script.Parent:WaitForChild("MappedGroundSurfaceData"))
local parkingLots = require(script.Parent:WaitForChild("ParkingSurfaceData"))
local treatments = {}
for _, area in ipairs(groundAreas) do table.insert(treatments, area) end
for _, lot in ipairs(parkingLots) do table.insert(treatments, lot) end

while Workspace:GetAttribute("CW_RoadTerrainCleared") ~= true
    or Workspace:GetAttribute("CW_WaterComplete") ~= true do
    task.wait(0.5)
end
if Workspace:GetAttribute("CW_ParkingSurfaceComplete") then return end

local VOXEL, CHUNK = 4, 64
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { Terrain }
params.IgnoreWater = false

local function inside(x, z, ring)
    local hit = false
    local j = #ring - 1
    for i = 1, #ring - 1, 2 do
        local xi, zi, xj, zj = ring[i], ring[i + 1], ring[j], ring[j + 1]
        if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
            hit = not hit
        end
        j = i
    end
    return hit
end

local function groundY(x, z)
    local hit = Workspace:Raycast(Vector3.new(x, 3000, z),
        Vector3.new(0, -6000, 0), params)
    return hit and hit.Position.Y or nil
end

local writable = {
    [Enum.Material.Grass] = true,
    [Enum.Material.Ground] = true,
    [Enum.Material.Concrete] = true,
    [Enum.Material.Asphalt] = true,
    [Enum.Material.Pavement] = true,
}
local changed, chunks, skippedWater, skippedGrade = 0, 0, 0, 0
local started = os.clock()

for lotIndex, lot in ipairs(treatments) do
    local ring = lot.outline
    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, #ring, 2 do
        minX, maxX = math.min(minX, ring[i]), math.max(maxX, ring[i])
        minZ, maxZ = math.min(minZ, ring[i + 1]), math.max(maxZ, ring[i + 1])
    end
    local target = ({
        Gravel = Enum.Material.Pebble,
        Asphalt = Enum.Material.Asphalt,
        Concrete = Enum.Material.Concrete,
        Grass = Enum.Material.Grass,
        Ground = Enum.Material.Ground,
    })[lot.material]
    local xStart = math.floor(minX / CHUNK) * CHUNK
    local zStart = math.floor(minZ / CHUNK) * CHUNK
    for x0 = xStart, maxX, CHUNK do
        for z0 = zStart, maxZ, CHUNK do
            -- One-stud corner checks keep each voxel inside its mapped
            -- footprint without leaving a four-stud gray border at lot edges.
            local mask = {}
            local any = false
            for ix = 1, CHUNK / VOXEL do
                mask[ix] = {}
                for iz = 1, CHUNK / VOXEL do
                    local x = x0 + (ix - 0.5) * VOXEL
                    local z = z0 + (iz - 0.5) * VOXEL
                    local covered = inside(x, z, ring)
                        and inside(x - 1, z - 1, ring)
                        and inside(x - 1, z + 1, ring)
                        and inside(x + 1, z - 1, ring)
                        and inside(x + 1, z + 1, ring)
                    mask[ix][iz] = covered
                    any = any or covered
                end
            end
            if any then
                local low, high = math.huge, -math.huge
                for _, p in ipairs({
                    {x0 + 4, z0 + 4}, {x0 + CHUNK - 4, z0 + 4},
                    {x0 + 4, z0 + CHUNK - 4}, {x0 + CHUNK - 4, z0 + CHUNK - 4},
                    {x0 + CHUNK / 2, z0 + CHUNK / 2},
                }) do
                    local y = groundY(p[1], p[2])
                    if y then low, high = math.min(low, y), math.max(high, y) end
                end
                if high > -math.huge and high - low <= 16 then
                    local y0 = math.floor((low - 8) / VOXEL) * VOXEL
                    local y1 = math.ceil((high + 8) / VOXEL) * VOXEL
                    local region = Region3.new(Vector3.new(x0, y0, z0),
                        Vector3.new(x0 + CHUNK, y1, z0 + CHUNK))
                    local materials, occupancy = Terrain:ReadVoxels(region, VOXEL)
                    local dirty = false
                    for ix = 1, CHUNK / VOXEL do
                        for iz = 1, CHUNK / VOXEL do
                            if mask[ix][iz] then
                                local top = nil
                                for iy = (y1 - y0) / VOXEL, 1, -1 do
                                    if occupancy[ix][iy][iz] > 0.05 then
                                        top = iy
                                        break
                                    end
                                end
                                if top then
                                    local old = materials[ix][top][iz]
                                    if old == Enum.Material.Water then
                                        skippedWater += 1
                                    elseif writable[old] and old ~= target then
                                        -- Change material only. Terrain shape and
                                        -- vehicle collision remain identical.
                                        materials[ix][top][iz] = target
                                        changed += 1
                                        dirty = true
                                    end
                                end
                            end
                        end
                    end
                    if dirty then Terrain:WriteVoxels(region, VOXEL, materials, occupancy) end
                    chunks += 1
                    if chunks % 24 == 0 then task.wait() end
                elseif high > -math.huge then
                    skippedGrade += 1
                end
            end
        end
    end
    if lotIndex % 12 == 0 then task.wait() end
end

print(("[ChesterWorld MappedSurface] groundAreas=%d parkingLots=%d chunks=%d voxelsPainted=%d waterPreserved=%d steepChunksSkipped=%d seconds=%.1f")
    :format(#groundAreas, #parkingLots, chunks, changed, skippedWater, skippedGrade, os.clock() - started))
Workspace:SetAttribute("CW_ParkingSurfaceVoxels", changed)
Workspace:SetAttribute("CW_ParkingSurfaceComplete", true)
