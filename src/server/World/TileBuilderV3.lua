-- The one active street builder: TileBuilderV2 owns the global graph,
-- all road trimming, and solid polygon junction paving in the same pass.
-- V3 keeps the Bootstrap entrypoint stable; it must NOT replace the
-- graph-defined polygon with an axis-aligned rectangle.
local BaseBuilder = require(script.Parent:WaitForChild("TileBuilderV2"))
local TileBuilderV3 = {}
local expectedTiles = 0
local builtTiles = 0
local polygonCenters = 0
local fallbackCenters = 0
local polygonPieces = 0

function TileBuilderV3.Prepare(tileModules)
    expectedTiles = #tileModules
    builtTiles = 0
    polygonCenters = 0
    fallbackCenters = 0
    polygonPieces = 0
    BaseBuilder.Prepare(tileModules)
    print(("[ChesterWorld TileBuilderV3] polygon paving uses solid WedgeParts; tiles=%d noEditableMesh=true"):format(expectedTiles))
end

function TileBuilderV3.Build(tileModule)
    local tileFolder = BaseBuilder.Build(tileModule)
    local intersections = tileFolder:FindFirstChild("Intersections")
    if intersections then
        for _, item in ipairs(intersections:GetChildren()) do
            if item:IsA("Model") and item:GetAttribute("CW_IntersectionPolygon") then
                polygonCenters += 1
                polygonPieces += #item:GetChildren()
            elseif item:IsA("BasePart") and item:GetAttribute("CW_IntersectionFallback") then
                fallbackCenters += 1
            end
        end
    end
    builtTiles += 1
    if builtTiles == expectedTiles then
        print(("[ChesterWorld TileBuilderV3] complete tiles=%d polygonCenters=%d wedgeParts=%d fallbacks=%d noEditableMesh=true")
            :format(builtTiles, polygonCenters, polygonPieces, fallbackCenters))
    end
    return tileFolder
end

return TileBuilderV3
