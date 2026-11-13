-- The one active street builder: TileBuilderV2 owns the global graph,
-- all road trimming, and solid polygon junction paving in the same pass.
-- V3 keeps the Bootstrap entrypoint stable; it must NOT replace the
-- graph-defined polygon with an axis-aligned rectangle.
local BaseBuilder = require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap = require(script.Parent:WaitForChild("WaterMap"))
local TileBuilderV3 = {}
local expectedTiles = 0
local builtTiles = 0
local polygonCenters = 0
local fallbackCenters = 0
local polygonPieces = 0
local recoveredHighwayParts = 0
local steepestHighwayGrade = 0
local recoveredByRoad = {}

function TileBuilderV3.Prepare(tileModules)
    expectedTiles = #tileModules
    builtTiles = 0
    polygonCenters = 0
    fallbackCenters = 0
    polygonPieces = 0
    recoveredHighwayParts = 0
    steepestHighwayGrade = 0
    recoveredByRoad = {}
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
                local grade = tonumber(part:GetAttribute("CW_ObservedSurfaceGrade")) or 0
                steepestHighwayGrade = math.max(steepestHighwayGrade, grade)
                local name = tostring(part:GetAttribute("ChesterStreet") or part.Name)
                local entry = recoveredByRoad[name]
                if not entry then
                    entry = { name = name, parts = 0, grade = 0 }
                    recoveredByRoad[name] = entry
                end
                entry.parts += 1
                if grade > entry.grade then
                    entry.grade = grade
                    entry.x, entry.z = part.Position.X, part.Position.Z
                    entry.class = tostring(part:GetAttribute("CW_RoadClass"))
                end
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
            print(("[ChesterWorld PavementOmissions] steepPieces=%d steepLength=%.0f noTerrainPieces=%d terrainSeamSamplesRecovered=%d trimConsumed=%d")
                :format(omissions.steepPieces, omissions.steepLength, omissions.noTerrainPieces,
                    omissions.terrainRecovered or 0, omissions.trimConsumed))
            print(("[ChesterWorld SeamRecovery] recoveredAt4=%d totalRecovered=%d waterMarginRejected=%d")
                :format(omissions.seam4Recovered or 0,omissions.terrainRecovered or 0,
                    omissions.seamWaterRejected or 0))
            for index = 1, math.min(12, #omissions.samples) do
                print("[ChesterWorld PavementOmission] " .. omissions.samples[index])
            end
            -- Source-aligned segments are needed for real repairs. 80-stud
            -- hotspot coordinates identify a neighborhood, not the ends of
            -- the missing surface. Preserve the exact geometry separately.
            local fragments = omissions.missingFragments or {}
            table.sort(fragments,function(a,b)
                if a.kind ~= b.kind then return a.kind == "no-terrain" end
                if a.length ~= b.length then return a.length > b.length end
                return tostring(a.road) < tostring(b.road)
            end)
            local gisCounts={notMapped=0,mappedPolygon=0,approxStream=0}
            for _,f in ipairs(fragments) do
                if f.kind=="no-terrain" then
                    local midX,midZ=(f.ax+f.bx)/2,(f.az+f.bz)/2
                    local k=WaterMap.Classify(midX,midZ)
                    gisCounts[k]=(gisCounts[k] or 0)+1
                end
            end
            print(("[ChesterWorld RoadGapAudit] missingFragments=%d noTerrain=%d steep=%d noTerrainGISWater=%d noTerrainApproxStreams=%d noTerrainUnmapped=%d")
                :format(#fragments,omissions.noTerrainPieces,omissions.steepPieces,
                    gisCounts.mappedPolygon,gisCounts.approxStream,gisCounts.notMapped))
            -- The previous first-35 report printed almost exclusively
            -- Riverfront's no-terrain fragments, hiding exact endpoints
            -- for Macdade, Crum Lynne, 6th and other grade failures.
            -- Give each repair category its own ranked inventory.
            local detailed={steep={},["no-terrain"]={}}
            for _,f in ipairs(fragments) do
                local category=detailed[f.kind]
                if category then table.insert(category,f) end
            end
            for _,kind in ipairs({"steep","no-terrain"}) do
                local list=detailed[kind]
                print(("[ChesterWorld RoadGapDetail] kind=%s total=%d top=%d")
                    :format(kind,#list,math.min(40,#list)))
                for index=1,math.min(40,#list) do
                    local f=list[index]
                    local x,z=(f.ax+f.bx)/2,(f.az+f.bz)/2
                    print(("[ChesterWorld RoadGap] kind=%s rank=%d road=%s class=%s len=%.1f width=%.1f center=(%.1f,%.1f) from=(%.1f,%.1f) to=(%.1f,%.1f) sourceY=%s/%s gradePct=%s GIS=%s")
                        :format(f.kind,index,tostring(f.road),tostring(f.class),f.length,
                            f.width,x,z,f.ax,f.az,f.bx,f.bz,
                            f.ay and string.format("%.1f",f.ay) or "unknown",
                            f.by and string.format("%.1f",f.by) or "unknown",
                            f.grade and string.format("%.1f",f.grade*100) or "unknown",
                            WaterMap.Classify(x,z)))
                end
            end
            workspace:SetAttribute("CW_RoadGapsToReview",#fragments)
            workspace:SetAttribute("CW_RoadWaterSourceMissing",gisCounts.notMapped)
            -- Prioritize real missing length rather than raw subdivision
            -- counts; omit geometry changes until each hotspot is surveyed.
            local areas = {}
            for _, entry in pairs(omissions.byArea or {}) do
                table.insert(areas, entry)
            end
            table.sort(areas, function(a, b)
                if a.length ~= b.length then return a.length > b.length end
                return a.pieces > b.pieces
            end)
            print(("[ChesterWorld PavementHotspots] clusters=%d top=%d"):format(#areas, math.min(20, #areas)))
            for index = 1, math.min(20, #areas) do
                local entry = areas[index]
                print(("[ChesterWorld PavementHotspot] rank=%d road=%s kind=%s pieces=%d missingLength=%.1f maxGrade=%.1f%% center=(%.0f,%.0f)")
                    :format(index, entry.street, entry.kind, entry.pieces, entry.length,
                        entry.maxGrade * 100, (entry.gx + 0.5) * 80, (entry.gz + 0.5) * 80))
            end
            -- Diagnose missing pavement over the riverfront without
            -- generating floating asphalt. A raycast at the reported
            -- cluster midpoint plus two rings distinguishes isolated
            -- tile seams from extended no-terrain areas.
            local terrainOnly = RaycastParams.new()
            terrainOnly.FilterType = Enum.RaycastFilterType.Include
            terrainOnly.FilterDescendantsInstances = {workspace.Terrain}
            terrainOnly.IgnoreWater = false
            local function surfaceAt(x,z)
                return workspace:Raycast(Vector3.new(x,5000,z),
                    Vector3.new(0,-10000,0),terrainOnly)
            end
            local surveyed=0
            for _,entry in ipairs(areas) do
                if entry.kind=="no-terrain" and surveyed<12 then
                    surveyed+=1
                    local x,z=entry.sampleX or (entry.gx+0.5)*80,
                        entry.sampleZ or (entry.gz+0.5)*80
                    local near,far,water=0,0,0
                    local lo,hi=math.huge,-math.huge
                    local center=surfaceAt(x,z)
                    local directions={{1,0},{-1,0},{0,1},{0,-1},
                        {0.707,0.707},{-0.707,0.707},{0.707,-0.707},{-0.707,-0.707}}
                    for _,radius in ipairs({24,64}) do
                        for _,d in ipairs(directions) do
                            local hit=surfaceAt(x+d[1]*radius,z+d[2]*radius)
                            if hit then
                                if radius==24 then near+=1 else far+=1 end
                                if hit.Material==Enum.Material.Water then water+=1 end
                                lo=math.min(lo,hit.Position.Y)
                                hi=math.max(hi,hit.Position.Y)
                            end
                        end
                    end
                    local span=lo==math.huge and "none" or string.format("%.1f..%.1f",lo,hi)
                    local mappedWater = WaterMap.Classify(x,z)
                    local status
                    if mappedWater=="mappedPolygon" then
                        status="mappedWaterPolygonNeedsAlignmentReview"
                    elseif mappedWater=="approxStream" then
                        status="approxStreamNeedsWidthReview"
                    elseif near>=6 and hi-lo<=4 then
                        status="possibleSmallSeam"
                    elseif near<=2 then
                        status=(mappedWater=="notMapped") and "unmappedNoTerrainRequiresGISReview"
                            or "extendedNoTerrainWaterSourceUnknown"
                    else
                        status="mixedBankNeedsSurvey"
                    end
                    print(("[ChesterWorld PavementTerrainSurvey] road=%s center=(%.0f,%.0f) centerHit=%s near24=%d/8 far64=%d/8 waterHits=%d ringY=%s mappedWater=%s status=%s")
                        :format(entry.street,x,z,tostring(center~=nil),
                            near,far,water,span,mappedWater,status))
                end
            end
            -- Read-only steep-grade probe at the ACTUAL omitted road
            -- fragment, not the center of an 80-stud reporting grid.
            -- Especially important for Macdade / Walnut / Crosby / Incinerator.
            -- Do not generate asphalt on a grade this steep.
            local solidOnly = RaycastParams.new()
            solidOnly.FilterType = Enum.RaycastFilterType.Include
            solidOnly.FilterDescendantsInstances = {workspace.Terrain}
            solidOnly.IgnoreWater = true
            local function terrainHeight(x,z)
                local hit = workspace:Raycast(Vector3.new(x,5000,z),
                    Vector3.new(0,-10000,0),solidOnly)
                return hit and hit.Position.Y or nil
            end
            local gradeSurveys=0
            for _,entry in ipairs(areas) do
                if entry.kind=="steep" and gradeSurveys<15 then
                    gradeSurveys+=1
                    local x=entry.gradeX or entry.sampleX or (entry.gx+0.5)*80
                    local z=entry.gradeZ or entry.sampleZ or (entry.gz+0.5)*80
                    local values={}
                    for _,p in ipairs({{0,0},{-8,0},{8,0},{0,-8},{0,8},
                        {-24,0},{24,0},{0,-24},{0,24},
                        {-48,0},{48,0},{0,-48},{0,48}}) do
                        local y=terrainHeight(x+p[1],z+p[2])
                        table.insert(values,y and string.format("%.1f",y) or "none")
                    end
                    print(("[ChesterWorld PavementGradeSurvey] road=%s probe=(%.1f,%.1f) length=%.1f maxGrade=%.1f%% mappedWater=%s Y(center,W8,E8,N8,S8,W24,E24,N24,S24,W48,E48,N48,S48)=%s")
                        :format(entry.street,x,z,entry.length,entry.maxGrade*100,
                            WaterMap.Classify(x,z),table.concat(values,",")))
                end
            end
            workspace:SetAttribute("CW_HighwayProfiledPieces", highway.profiledPieces)
            workspace:SetAttribute("CW_PavementSteepOmissions", omissions.steepPieces)
            workspace:SetAttribute("CW_PavementNoTerrainOmissions", omissions.noTerrainPieces)
        end
        if recoveredHighwayParts > 0 then
            warn(("[ChesterWorld HighwayPavement] recoveredSteepParts=%d worstGradePct=%.1f; asphalt is restored but unsafe grade must be inspected before driving")
                :format(recoveredHighwayParts, steepestHighwayGrade * 100))
            local list = {}
            for _, entry in pairs(recoveredByRoad) do
                table.insert(list, entry)
            end
            table.sort(list, function(a, b) return a.grade > b.grade end)
            for _, entry in ipairs(list) do
                warn(("[ChesterWorld HighwayPavementRecovered] %s class=%s parts=%d worstGradePct=%.0f at (%.1f, %.1f)")
                    :format(entry.name, entry.class, entry.parts, entry.grade * 100, entry.x, entry.z))
            end
        end
    end
    return tileFolder
end

return TileBuilderV3
