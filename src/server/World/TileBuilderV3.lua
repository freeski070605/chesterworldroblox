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
local recoveredHighwayParts = 0
local steepestHighwayGrade = 0

function TileBuilderV3.Prepare(tileModules)
    expectedTiles = #tileModules
    builtTiles = 0
    polygonCenters = 0
    fallbackCenters = 0
    polygonPieces = 0
    recoveredHighwayParts = 0
    steepestHighwayGrade = 0
    BaseBuilder.Prepare(tileModules)
    print(("[ChesterWorld TileBuilderV3] polygon paving uses solid WedgeParts; tiles=%d noEditableMesh=true"):format(expectedTiles))
end

-- Used only for the optional 5-tile Studio preview. Global graph
-- preparation still receives all 102 modules.
function TileBuilderV3.SetExpectedTiles(count)
    expectedTiles = math.max(1, math.min(expectedTiles, count))
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
    local roads = tileFolder:FindFirstChild("Roads")
    if roads then
        for _, part in ipairs(roads:GetChildren()) do
            if part:IsA("BasePart") and part:GetAttribute("CW_SteepHighwayFallback") == true then
                recoveredHighwayParts += 1
                steepestHighwayGrade = math.max(steepestHighwayGrade,
                    tonumber(part:GetAttribute("CW_ObservedSurfaceGrade")) or 0)
            end
        end
    end
    builtTiles += 1
    if builtTiles == expectedTiles then
        print(("[ChesterWorld TileBuilderV3] complete tiles=%d polygonCenters=%d wedgeParts=%d fallbacks=%d noEditableMesh=true")
            :format(builtTiles, polygonCenters, polygonPieces, fallbackCenters))
        if BaseBuilder.Stats then
            local omissions, highway = BaseBuilder.Stats()
            print(("[ChesterWorld HighwayPavement] profiledPieces=%d profiledLength=%.0f spanPieces=%d fillPieces=%d markingParts=%d suppressedHighwayPads=%d fallbackHighwayRoads=%d trimConsumedHighway=%d")
                :format(highway.profiledPieces, highway.profiledLength, highway.spanPieces, highway.fillPieces,
                    highway.markingParts, highway.suppressedHighwayPads, highway.fallbackHighwayRoads,
                    omissions.trimConsumedHighway))
            print(("[ChesterWorld PavementOmissions] steepPieces=%d steepLength=%.0f noTerrainPieces=%d trimConsumed=%d")
                :format(omissions.steepPieces, omissions.steepLength, omissions.noTerrainPieces, omissions.trimConsumed))
            for index = 1, math.min(12, #omissions.samples) do
                print("[ChesterWorld PavementOmission] " .. omissions.samples[index])
            end
            workspace:SetAttribute("CW_HighwayProfiledPieces", highway.profiledPieces)
            workspace:SetAttribute("CW_PavementSteepOmissions", omissions.steepPieces)
            workspace:SetAttribute("CW_PavementNoTerrainOmissions", omissions.noTerrainPieces)
        end
        if recoveredHighwayParts > 0 then
            warn(("[ChesterWorld HighwayPavement] recoveredSteepParts=%d worstGradePct=%.1f; asphalt is restored but unsafe grade must be inspected before driving")
                :format(recoveredHighwayParts, steepestHighwayGrade * 100))
        end
    end
    return tileFolder
end

return TileBuilderV3
