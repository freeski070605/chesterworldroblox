-- Source-GIS water classification for road gap/shoreline safety.
-- Spatially index 4-stud mapped water rectangles: previously every road
-- seam check scanned all 16,749 rectangles, multiplied by nearby probes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaterMap = {}
local cache = nil
local CELL = 128

local function key(cx,cz)
    return tostring(cx) .. ":" .. tostring(cz)
end
local function load()
    if cache ~= nil then return cache end
    local shared=ReplicatedStorage:FindFirstChild("Shared")
    local data=shared and shared:FindFirstChild("WaterData")
    local tiles=data and data:FindFirstChild("Tiles")
    if not tiles then return nil end
    local index={}
    for _,child in ipairs(tiles:GetChildren()) do
        if child:IsA("ModuleScript") and child.Name:match("^tile_r%d+_c%d+$") then
            local ok,value=pcall(require,child)
            if ok and value and value.rects then
                for _,r in ipairs(value.rects) do
                    local x1=math.floor(r[1]/CELL)
                    local z1=math.floor(r[2]/CELL)
                    local x2=math.floor((r[1]+r[3]-0.0001)/CELL)
                    local z2=math.floor((r[2]+r[4]-0.0001)/CELL)
                    for cx=x1,x2 do
                        for cz=z1,z2 do
                            local k=key(cx,cz)
                            local list=index[k]
                            if not list then
                                list={}
                                index[k]=list
                            end
                            table.insert(list,r)
                        end
                    end
                end
            end
        end
    end
    cache=index
    return cache
end

function WaterMap.Classify(x,z)
    local cells=load()
    if cells==nil then return "notExported" end
    local list=cells[key(math.floor(x/CELL),math.floor(z/CELL))]
    if not list then return "notMapped" end
    local stream=false
    for _,r in ipairs(list) do
        if x>=r[1] and x<r[1]+r[3]
            and z>=r[2] and z<r[2]+r[4] then
            if r[5]==1 then return "mappedPolygon" end
            stream=true
        end
    end
    return stream and "approxStream" or "notMapped"
end

return WaterMap
