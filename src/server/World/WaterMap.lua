-- Read-only, GIS-derived classification for missing shoreline pavement.
-- The absence of Terrain is not proof that a road is in the Delaware River.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaterMap = {}
local cache = nil

local function load()
    if cache ~= nil then return cache end
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local data = shared and shared:FindFirstChild("WaterData")
    local tiles = data and data:FindFirstChild("Tiles")
    if not tiles then return nil end
    cache = {}
    for _, child in ipairs(tiles:GetChildren()) do
        if child:IsA("ModuleScript") and child.Name:match("^tile_r%d+_c%d+$") then
            local ok, value = pcall(require, child)
            if ok and value and value.rects then
                for _, rect in ipairs(value.rects) do
                    table.insert(cache, rect)
                end
            end
        end
    end
    return cache
end

function WaterMap.Classify(x, z)
    local rects = load()
    if rects == nil then return "notExported" end
    for _, r in ipairs(rects) do
        if x >= r[1] and x < r[1] + r[3]
            and z >= r[2] and z < r[2] + r[4] then
            return r[5] == 1 and "mappedPolygon" or "approxStream"
        end
    end
    return "notMapped"
end

return WaterMap
