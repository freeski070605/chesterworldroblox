-- EXIT 6 final road-closure audit. Read-only: verifies physical pavement
-- AFTER highway dressing, terrain clearing, local bridges, landmarks and water.
-- It does NOT bridge uncertain riverbanks or raise roads to invented heights.
local Workspace = game:GetService("Workspace")
local World = Workspace:WaitForChild("ChesterWorld")
local TileBuilder = require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap = require(script.Parent:WaitForChild("WaterMap"))

Workspace:SetAttribute("CW_RoadFinalAuditComplete",false)
local started=os.clock()
local stages={
    "CW_BootstrapComplete","CW_RoadConformComplete","CW_HighwayFinishComplete",
    "CW_RoadTerrainCleared","CW_LocalBridgesDressed",
    "CW_LandmarksComplete","CW_WaterComplete",
}
for _,stage in ipairs(stages) do
    while Workspace:GetAttribute(stage) ~= true do task.wait(0.5) end
end

local omissions=TileBuilder.Stats()
local fragments=omissions and omissions.missingFragments or {}
local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Include
overlap.MaxParts=100
local roadFolders={}
local roadParts={}
for _,tile in ipairs(World:GetChildren()) do
    for _,folderName in ipairs({"Roads","Intersections"}) do
        local folder=tile:FindFirstChild(folderName)
        if folder then table.insert(roadFolders,folder) end
    end
    local roads=tile:FindFirstChild("Roads")
    if roads then
        for _,part in ipairs(roads:GetChildren()) do
            if part:IsA("BasePart") then table.insert(roadParts,part) end
        end
    end
end
overlap.FilterDescendantsInstances=roadFolders

local sameRoadCovered,otherRoadCovered,openCount=0,0,0
local openLand,openMappedWater,openStream=0,0,0
local exactOpen={}
local function actualPavementAt(x,z,roadName)
    local candidates=Workspace:GetPartBoundsInBox(
        CFrame.new(x,0,z),Vector3.new(2,1000,2),overlap)
    local any,same=false,false
    for _,part in ipairs(candidates) do
        if part:IsA("BasePart") and part.Transparency < 1 then
            -- GetPartBoundsInBox is a broad phase. Confirm point against
            -- the actual local part footprint so AABB overlap cannot
            -- falsely mark an uncovered diagonal gap as paved.
            local q=part.CFrame:PointToObjectSpace(Vector3.new(x,part.Position.Y,z))
            if math.abs(q.X) <= part.Size.X/2+0.4
                and math.abs(q.Z) <= part.Size.Z/2+0.4 then
                any=true
                if part.Name == roadName
                    or part:GetAttribute("ChesterStreet") == roadName then
                    same=true
                end
            end
        end
    end
    return same,any
end

for i,f in ipairs(fragments) do
    local x,z=(f.ax+f.bx)/2,(f.az+f.bz)/2
    local same,any=actualPavementAt(x,z,f.road)
    if same then
        sameRoadCovered+=1
    elseif any then
        otherRoadCovered+=1
    else
        openCount+=1
        local water=WaterMap.Classify(x,z)
        if water=="mappedPolygon" then openMappedWater+=1
        elseif water=="approxStream" then openStream+=1
        else openLand+=1 end
        table.insert(exactOpen,{
            f=f,x=x,z=z,water=water,impact=f.length*(f.width or 1)
        })
    end
    if i%30==0 then task.wait() end
end

-- Late terrain and local-bridge construction can change physical grades
-- after the earlier highway reports. Recheck actual rendered road endpoints.
local highwayPieces,highwayGradeOverLimit=0,0
local badHighways={}
local unsafeStreetPieces,gradeLimited,gradeLimitedSteep=0,0,0
for i,part in ipairs(roadParts) do
    local a=part.CFrame*Vector3.new(0,0,-part.Size.Z/2)
    local b=part.CFrame*Vector3.new(0,0,part.Size.Z/2)
    local dx,dz=b.X-a.X,b.Z-a.Z
    local run=math.sqrt(dx*dx+dz*dz)
    local grade=run>0.1 and math.abs(b.Y-a.Y)/run or 0
    local isHighway=part:GetAttribute("CW_HighwayProfiled")==true
    if isHighway then
        highwayPieces+=1
        local cls=tostring(part:GetAttribute("CW_RoadClass") or "")
        local max=cls=="motorway_link" or cls=="trunk_link" and 0.11 or 0.08
        if grade>max then
            highwayGradeOverLimit+=1
            if #badHighways<20 then table.insert(badHighways,{
                name=part.Name,x=part.Position.X,z=part.Position.Z,
                grade=grade,max=max
            }) end
        end
    elseif grade>0.4 and part:GetAttribute("CW_Rail")~=true then
        unsafeStreetPieces+=1
    end
    if part:GetAttribute("CW_GradeLimited")==true then
        gradeLimited+=1
        if grade>0.115 then gradeLimitedSteep+=1 end
    end
    if i%1000==0 then task.wait() end
end

table.sort(exactOpen,function(a,b) return a.impact>b.impact end)
for i=1,math.min(#exactOpen,30) do
    local d=exactOpen[i]
    local f=d.f
    print(("[ChesterWorld RoadFinalOpenGap] rank=%d road=%s kind=%s center=(%.1f,%.1f) length=%.1f width=%.1f GIS=%s gradePct=%s from=(%.1f,%.1f) to=(%.1f,%.1f)")
        :format(i,tostring(f.road),f.kind,d.x,d.z,f.length,f.width,d.water,
            f.grade and string.format("%.1f",f.grade*100) or "unknown",
            f.ax,f.az,f.bx,f.bz))
end
for _,h in ipairs(badHighways) do
    warn(("[ChesterWorld RoadFinalHighwayGrade] road=%s center=(%.1f,%.1f) grade=%.1f%% threshold=%.1f%%")
        :format(h.name,h.x,h.z,h.grade*100,h.max*100))
end
print(("[ChesterWorld RoadFinalAudit] fragmentCandidates=%d coveredSameRoad=%d coveredOtherRoad=%d STILL_OPEN=%d openOnUnmappedTerrain=%d openOnMappedWater=%d openOnApproxStream=%d checkedRoadParts=%d highwayParts=%d highwayAboveGradeLimit=%d nonHighwaySteep=%d bridgeFlagged=%d bridgeStillSteep=%d seconds=%.1f")
    :format(#fragments,sameRoadCovered,otherRoadCovered,openCount,
        openLand,openMappedWater,openStream,#roadParts,
        highwayPieces,highwayGradeOverLimit,unsafeStreetPieces,
        gradeLimited,gradeLimitedSteep,os.clock()-started))
Workspace:SetAttribute("CW_RoadFinalOpenGaps",openCount)
Workspace:SetAttribute("CW_RoadFinalHighwaySteep",highwayGradeOverLimit)
Workspace:SetAttribute("CW_RoadFinalAuditComplete",true)
