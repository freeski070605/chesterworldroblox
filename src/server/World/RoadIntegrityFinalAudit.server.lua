-- EXIT 6 final road-closure audit. Read-only: verifies physical pavement
-- AFTER highway dressing, terrain clearing, local bridges, landmarks and water.
-- It does NOT bridge uncertain riverbanks or raise roads to invented heights.
local Workspace = game:GetService("Workspace")
-- An audit error is diagnostic, not grounds for an infinite loading screen.
-- World-build and bridge construction have their own completion flags.
Workspace:SetAttribute("CW_RoadFinalAuditComplete",false)
Workspace:SetAttribute("CW_RoadFinalAuditStatus","running")

local function runAudit()
-- The city root is created by Bootstrap AFTER this script starts.
-- Wait for the stage attribute first so Studio does not report a false
-- infinite yield warning while the first tile is being prepared.
local TileBuilder = require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap = require(script.Parent:WaitForChild("WaterMap"))
local StructureRegistry = require(game:GetService("ReplicatedStorage")
    :WaitForChild("Shared"):WaitForChild("HighwayStructureRegistry"))

local started=os.clock()
local stages={
    "CW_BootstrapComplete","CW_RoadConformComplete","CW_HighwayFinishComplete",
    "CW_RoadTerrainCleared","CW_LocalBridgesDressed",
    "CW_LandmarksComplete","CW_WaterComplete","CW_RoadGapRepairComplete",
    "CW_MacdadeCrumDeckComplete",
}
for _,stage in ipairs(stages) do
    local deadline=os.clock()+720 -- cold 102-tile Studio starts can be slow
    local nextNotice=os.clock()+60
    while Workspace:GetAttribute(stage) ~= true do
        if os.clock()>deadline then
            error("road audit timed out waiting for "..stage..
                "; all finished stages must explicitly set their own flags")
        end
        if os.clock()>nextNotice then
            warn("[ChesterWorld RoadFinalAudit] Waiting for stage "..stage..
                " (audit still pending)")
            nextNotice=os.clock()+60
        end
        task.wait(0.5)
    end
end

local World=Workspace:FindFirstChild("ChesterWorld")
if not World then error("Final road audit: city missing after bootstrap completion") end
local auditStarted=os.clock()
local repairStatus=tostring(Workspace:GetAttribute("CW_RoadGapRepairStatus") or "unknown")
if repairStatus=="failed" then
    warn("[ChesterWorld RoadFinalAudit] Automatic dry-gap repair failed; auditing unmodified surfaces")
end
local omissions=TileBuilder.Stats()
local fragments=omissions and omissions.missingFragments or {}
local overlap=OverlapParams.new()
overlap.FilterType=Enum.RaycastFilterType.Include
overlap.MaxParts=0 -- unlimited: prevent false open-road reports in dense junctions
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

-- Preserve the previous midpoint check for comparison, but ALSO test
-- multiple longitudinal stations on the SAME named road. An overlapping
-- cross street / elevated bridge is not proof of a drivable repair.
local sameRoadCovered,otherRoadCovered,openCount=0,0,0
local fullOwnRoad,partialOwnRoad,otherRoadOnly,unverified=0,0,0,0
local openLand,openMappedWater,openStream=0,0,0
local exactOpen={}
local function actualPavementAt(x,z,roadName)
    local candidates=Workspace:GetPartBoundsInBox(
        CFrame.new(x,0,z),Vector3.new(1.2,1000,1.2),overlap)
    local any,same=false,false
    for _,part in ipairs(candidates) do
        if part:IsA("BasePart") and part.Transparency < 1
            and part.CanCollide and part.Size.X>2 then
            -- AABB is only the broadphase. Confirm the local footprint;
            -- terrain and elevated crossing parts must not masquerade as
            -- physical road continuity on a different source street.
            local q=part.CFrame:PointToObjectSpace(
                Vector3.new(x,part.Position.Y,z))
            if math.abs(q.X)<=part.Size.X/2+0.15
                and math.abs(q.Z)<=part.Size.Z/2+0.15 then
                any=true
                if part.Parent and part.Parent.Name=="Roads"
                    and (part.Name==roadName
                        or part:GetAttribute("ChesterStreet")==roadName) then
                    same=true
                end
            end
        end
    end
    return same,any
end

for i,f in ipairs(fragments) do
    local x,z=(f.ax+f.bx)/2,(f.az+f.bz)/2
    local middleSame,middleAny=actualPavementAt(x,z,f.road)
    -- Keep original 202-open-baseline semantics for measured comparisons.
    if middleSame then
        sameRoadCovered+=1
    elseif middleAny then
        otherRoadCovered+=1
    else
        openCount+=1
    end
    local ownStations,anyStations=0,0
    for _,t in ipairs({0.25,0.5,0.75}) do
        local sx=f.ax+(f.bx-f.ax)*t
        local sz=f.az+(f.bz-f.az)*t
        local own,any=actualPavementAt(sx,sz,f.road)
        if own then ownStations+=1 end
        if any then anyStations+=1 end
    end
    if ownStations==3 then
        fullOwnRoad+=1
    else
        unverified+=1
        if ownStations>0 then
            partialOwnRoad+=1
        elseif anyStations>0 then
            otherRoadOnly+=1
        end
        local water=WaterMap.Classify(x,z)
        if water=="mappedPolygon" then openMappedWater+=1
        elseif water=="approxStream" then openStream+=1
        else openLand+=1 end
        table.insert(exactOpen,{
            f=f,x=x,z=z,water=water,impact=f.length*(f.width or 1),
            ownStations=ownStations,anyStations=anyStations
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
        local max=(part:GetAttribute("CW_HighwayLink")==true) and 0.11 or 0.08
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

-- The 20 repaired Crum Lynne pieces are APPROACH pieces on either side
-- of the CSX bridge. Querying only beneath those approach Parts found no
-- rail at all, and "0 failures" was not a legitimate clearance check.
-- Survey the registered, aerial-backed road-over-rail center,
-- NOT the offset previous guess at (14411,-10367). Samples outside
-- the actual roadway footprint must not be counted as deck holes.
local railEntry=nil
for _,entry in ipairs(StructureRegistry.NAMED or {}) do
    if entry.id=="CRUM_LYNNE_OVER_CSX" then
        railEntry=entry
        break
    end
end
if not railEntry or not railEntry.center then
    error("Road rail audit: named Crum Lynne / CSX registry missing")
end
local railRegistryX,railRegistryZ=railEntry.center[1],railEntry.center[2]
local repairedDecks=0
for _,part in ipairs(roadParts) do
    if part.Name=="Crum Lynne"
        and part:GetAttribute("CW_RailOverpassRepair")==true then
        repairedDecks+=1
    end
end

local function slabTopAtXZ(part,x,z)
    local up=part.CFrame.UpVector
    if math.abs(up.Y)<0.75 then return nil end
    local top=part.Position+up*(part.Size.Y/2)
    local y=top.Y-(up.X*(x-top.X)+up.Z*(z-top.Z))/up.Y
    local q=part.CFrame:PointToObjectSpace(Vector3.new(x,y,z))
    if math.abs(q.X)>part.Size.X/2+0.3
        or math.abs(q.Z)>part.Size.Z/2+0.3 then
        return nil
    end
    return y
end

-- Resolve the road-centerline projection using rendered SAME-STREET
-- slab geometry. Extending at most 75 studs from a slab endpoint lets
-- us identify an actual missing deck without mistaking the railbed
-- beside a narrow road for a missing pavement section.
local crumRoads={}
for _,part in ipairs(roadParts) do
    if part.Name=="Crum Lynne" and part:IsA("BasePart")
        and part.CanCollide and part.Transparency<1
        and part.Size.Z>2 then
        local dx=part.Position.X-railRegistryX
        local dz=part.Position.Z-railRegistryZ
        if dx*dx+dz*dz<150*150 then
            table.insert(crumRoads,part)
        end
    end
end
local function centerlineDistance(x,z)
    local best=math.huge
    local width=0
    for _,part in ipairs(crumRoads) do
        local q=part.CFrame:PointToObjectSpace(
            Vector3.new(x,part.Position.Y,z))
        if math.abs(q.Z)<=part.Size.Z/2+75
            and math.abs(q.X)<best then
            best=math.abs(q.X)
            width=part.Size.X
        end
    end
    return best,width
end

local railSamples,offRoadRailSamples,overlappingDeckSamples,clearanceFailures=0,0,0,0
local noRoadAtRailSamples=0
local minClearance=math.huge
local worstPosition=nil
local checked={}
for _,rail in ipairs(roadParts) do
    if rail:IsA("BasePart") and rail.Name=="Csx Phila Subdivision"
        and rail:GetAttribute("CW_Rail")==true then
        -- Nearby rail can be long; sample the actual longitudinal strip,
        -- not only its center or a broad bounding box.
        local distX,distZ=rail.Position.X-railRegistryX,
            rail.Position.Z-railRegistryZ
        if distX*distX+distZ*distZ<100*100 then
            for _,fraction in ipairs({-0.45,-0.36,-0.27,-0.18,-0.09,0,0.09,0.18,0.27,0.36,0.45}) do
                local p=rail.CFrame*Vector3.new(
                    0,0,rail.Size.Z*fraction*2)
                local x,z=p.X,p.Z
                local dx,dz=x-railRegistryX,z-railRegistryZ
                -- Only the named crossing, not nearby rail alongside.
                -- A 12-stud survey core stays inside the named road
                -- corridor; 24 studs included rail beyond its edges.
                if dx*dx+dz*dz<=12*12 then
                    local key=math.floor(x*2)..":"..math.floor(z*2)
                    if not checked[key] then
                        checked[key]=true
                        local railTop=slabTopAtXZ(rail,x,z)
                        if railTop then
                            local centerDistance,roadWidth=centerlineDistance(x,z)
                            if roadWidth==0 then
                                warn(("[ChesterWorld RoadRailProbe] cannot establish Crum Lynne roadline near rail=(%.2f,%.2f)")
                                    :format(x,z))
                            elseif centerDistance>roadWidth/2+1.2 then
                                offRoadRailSamples+=1
                                print(("[ChesterWorld RoadRailOffRoadProbe] rail=(%.2f,%.2f,%.2f) distanceFromRoadCenter=%.2f halfRoadWidth=%.2f notCountedAsDeckGap=true")
                                    :format(x,railTop,z,centerDistance,roadWidth/2))
                            else
                            railSamples+=1
                            local candidates=Workspace:GetPartBoundsInBox(
                                CFrame.new(x,90,z),
                                Vector3.new(2,400,2),overlap)
                            local lowestDeckUnderside=math.huge
                            for _,part in ipairs(candidates) do
                                if part:IsA("BasePart") and part.Name=="Crum Lynne"
                                    and part.Transparency<1 and part.CanCollide then
                                    local top=slabTopAtXZ(part,x,z)
                                    if top then
                                        local underside=top-
                                            part.Size.Y/math.abs(part.CFrame.UpVector.Y)
                                        if underside>railTop-5 then
                                            lowestDeckUnderside=math.min(
                                                lowestDeckUnderside,underside)
                                        end
                                    end
                                end
                            end
                            if lowestDeckUnderside==math.huge then
                                noRoadAtRailSamples+=1
                                -- Sampled rail may extend outside the true
                                -- road footprint, or be a real missing deck.
                                -- Exact XYZ is needed to tell those apart.
                                warn(("[ChesterWorld RoadRailUncoveredProbe] rail=(%.2f,%.2f,%.2f) sourceRoad=Crum Lynne registry=(%d,%d) distanceFromRoadCenter=%.2f halfRoadWidth=%.2f noCollidableDeckAtXZ=true")
                                    :format(x,railTop,z,
                                        railRegistryX,railRegistryZ,
                                        centerDistance,roadWidth/2))
                            else
                                overlappingDeckSamples+=1
                                local clearance=lowestDeckUnderside-railTop
                                if clearance<minClearance then
                                    minClearance=clearance
                                    worstPosition=Vector2.new(x,z)
                                end
                                if clearance<14 then clearanceFailures+=1 end
                            end
                            end -- sample aligned with the named road
                        end
                    end
                end
            end
        end
    end
end

local clearanceVerified=railSamples>=3
    and overlappingDeckSamples>=3
    and noRoadAtRailSamples==0
    and clearanceFailures==0
local status=clearanceVerified and "measured-local-clearance-passing"
    or (railSamples==0 and "no-on-road-rail-samples"
        or overlappingDeckSamples==0 and "no-road-over-rail"
        or noRoadAtRailSamples>0 and "road-gaps-over-rail"
        or overlappingDeckSamples<3 and "too-few-road-rail-overlap-samples"
        or "insufficient-clearance")
Workspace:SetAttribute("CW_RailDeckClearanceVerified",clearanceVerified)
Workspace:SetAttribute("CW_RailDeckClearanceStatus",status)
Workspace:SetAttribute("CW_RailDeckClearanceFailures",clearanceFailures)
Workspace:SetAttribute("CW_RailDeckUncoveredRailSamples",noRoadAtRailSamples)
if not clearanceVerified then
    warn(("[ChesterWorld RoadFinalRailDeck] NOT VERIFIED status=%s onRoadRailSamples=%d deckSamples=%d uncoveredSamples=%d offRoadSamples=%d clearanceFailures=%d")
        :format(status,railSamples,overlappingDeckSamples,
            noRoadAtRailSamples,offRoadRailSamples,clearanceFailures))
end
print(("[ChesterWorld RoadFinalRailDeck] repairedApproachParts=%d atNamedCSXCrossing=(%d,%d) onRoadRailSamples=%d offRoadRailSamples=%d roadDeckSamples=%d missingRoadOverRail=%d minActualClearanceStuds=%s clearanceBelow14=%d status=%s NOTE=driving-test-still-required")
    :format(repairedDecks,railRegistryX,railRegistryZ,railSamples,
        offRoadRailSamples,overlappingDeckSamples,noRoadAtRailSamples,
        minClearance<math.huge and string.format("%.2f",minClearance)
            or "unmeasured",clearanceFailures,status))
if worstPosition then
    print(("[ChesterWorld RoadFinalRailDeckWorst] at=(%.1f,%.1f) clearance=%.2f studs")
        :format(worstPosition.X,worstPosition.Y,minClearance))
end

-- Independently summarize any new Macdade Crum Creek highway-free
-- carriageway bridge. A generated deck is not by itself a driving test.
local macdadePieces=0
local maxMacdadeGrade=0
local macdadeSteep=0
local retiredPieces=0
for _,part in ipairs(roadParts) do
    if part.Name=="Macdade"
        and part:GetAttribute("CW_MacdadeCrumDeck")==true then
        macdadePieces+=1
        local a=part.CFrame*Vector3.new(0,0,-part.Size.Z/2)
        local b=part.CFrame*Vector3.new(0,0,part.Size.Z/2)
        local run=math.sqrt((b.X-a.X)^2+(b.Z-a.Z)^2)
        local pct=run>0.1 and math.abs(b.Y-a.Y)/run*100 or 999
        maxMacdadeGrade=math.max(maxMacdadeGrade,pct)
        if pct>10.1 then macdadeSteep+=1 end
    end
end
for _,part in ipairs(roadParts) do
    if part:GetAttribute("CW_MacdadeOldRoadTemporarilyRetired")==true then
        retiredPieces+=1
        if part.CanCollide or part.Transparency<1 then
            warn(("[ChesterWorld MacdadeFinalDeckAudit] OLD PAVEMENT NOT RETIRED at (%.1f,%.1f) name=%s")
                :format(part.Position.X,part.Position.Z,tostring(part.Name)))
        end
    end
end
-- Real geometric connection check at BOTH edges of a built culvert.
-- A count of 14 rendered deck Parts cannot prove the two bank joins.
local jointFailures=0
local jointDetails={}
local function macdadeSurfaceAt(x,z,wantDeck)
    local found=nil
    for _,part in ipairs(roadParts) do
        if part.Name=="Macdade" and part:IsA("BasePart")
            and part.CanCollide and part.Transparency<1
            and (part:GetAttribute("CW_MacdadeCrumDeck")==true)==wantDeck
            and (part.Position.X-x)^2+(part.Position.Z-z)^2<90*90 then
            local top=slabTopAtXZ(part,x,z)
            if top and (not found or top>found) then found=top end
        end
    end
    return found
end
if macdadePieces>0 then
    local cx=Workspace:GetAttribute("CW_MacdadeCrumCenterX")
    local cz=Workspace:GetAttribute("CW_MacdadeCrumCenterZ")
    local ax=Workspace:GetAttribute("CW_MacdadeCrumAxisX")
    local az=Workspace:GetAttribute("CW_MacdadeCrumAxisZ")
    if cx and cz and ax and az then
        for _,bank in ipairs({-1,1}) do
            local outer=bank*140+bank*0.65
            local inner=bank*140-bank*0.65
            local outX,outZ=cx+ax*outer,cz+az*outer
            local inX,inZ=cx+ax*inner,cz+az*inner
            local outsideY=macdadeSurfaceAt(outX,outZ,false)
            local insideY=macdadeSurfaceAt(inX,inZ,true)
            if not outsideY or not insideY
                or math.abs(outsideY-insideY)>0.65 then
                jointFailures+=1
                local msg=string.format(
                    "bank=%d exterior=(%.1f,%.1f) oldY=%s interior=(%.1f,%.1f) newY=%s gapTolerance=0.65",
                    bank,outX,outZ,outsideY and string.format("%.2f",outsideY) or "missing",
                    inX,inZ,insideY and string.format("%.2f",insideY) or "missing")
                table.insert(jointDetails,msg)
                warn("[ChesterWorld MacdadeBankJoint] FAIL "..msg)
            end
        end
    else
        jointFailures=2
        warn("[ChesterWorld MacdadeBankJoint] Missing built-deck station frame")
    end
end
Workspace:SetAttribute("CW_MacdadeBankJointFailures",jointFailures)

-- Re-sample central driving positions for a stacked, collidable
-- second copy of Macdade. A still-collidable old lower road is a
-- collision issue even if the top deck looks smooth from above.
local duplicateLayers=0
if macdadePieces>0 then
    local cx=Workspace:GetAttribute("CW_MacdadeCrumCenterX")
    local cz=Workspace:GetAttribute("CW_MacdadeCrumCenterZ")
    local ax=Workspace:GetAttribute("CW_MacdadeCrumAxisX")
    local az=Workspace:GetAttribute("CW_MacdadeCrumAxisZ")
    if cx and cz and ax and az then
        for s=-130,130,10 do
            local x,z=cx+ax*s,cz+az*s
            local original=macdadeSurfaceAt(x,z,false)
            local newDeck=macdadeSurfaceAt(x,z,true)
            if original and newDeck and math.abs(original-newDeck)>0.65 then
                duplicateLayers+=1
                if duplicateLayers<=12 then
                    warn(("[ChesterWorld MacdadeDoubleRoad] station=%d oldY=%.2f newDeckY=%.2f bothCollidable=true")
                        :format(s,original,newDeck))
                end
            end
        end
    end
end
local pierCount=0
for _,tile in ipairs(World:GetChildren()) do
    local folder=tile:FindFirstChild("Roads")
    if folder then
        for _,part in ipairs(folder:GetChildren()) do
            if part:IsA("BasePart")
                and part:GetAttribute("CW_MacdadeCrumSupport")==true then
                pierCount+=1
            end
        end
    end
end
Workspace:SetAttribute("CW_MacdadeDoubleRoadSamples",duplicateLayers)
Workspace:SetAttribute("CW_MacdadeDryBankSupportsAudited",pierCount)
local macdadeStatus=tostring(
    Workspace:GetAttribute("CW_MacdadeCrumDeckStatus") or "not-run")
print(("[ChesterWorld MacdadeFinalDeckAudit] status=%s builtPieces=%d maxGradePct=%.2f above10Pct=%d oldRoadPartsRetired=%d badBankJoints=%d duplicateCollidableRoadSamples=%d dryBankSupports=%d sourceInventory=15226")
    :format(macdadeStatus,macdadePieces,maxMacdadeGrade,macdadeSteep,
        retiredPieces,jointFailures,duplicateLayers,pierCount))
if macdadeStatus=="built" and (macdadePieces~=14 or macdadeSteep>0
    or jointFailures>0 or duplicateLayers>0
    or pierCount~=(Workspace:GetAttribute("CW_MacdadeDryBankSupports") or -1)) then
    warn("[ChesterWorld MacdadeFinalDeckAudit] Bridge profile parts failed independent grade/part-count check")
end

table.sort(exactOpen,function(a,b) return a.impact>b.impact end)
for i=1,math.min(#exactOpen,30) do
    local d=exactOpen[i]
    local f=d.f
    print(("[ChesterWorld RoadFinalOpenGap] rank=%d road=%s kind=%s center=(%.1f,%.1f) length=%.1f width=%.1f GIS=%s gradePct=%s ownStations=%d/3 anyRoadStations=%d/3 from=(%.1f,%.1f) to=(%.1f,%.1f)")
        :format(i,tostring(f.road),f.kind,d.x,d.z,f.length,f.width,d.water,
            f.grade and string.format("%.1f",f.grade*100) or "unknown",
            d.ownStations,d.anyStations,f.ax,f.az,f.bx,f.bz))
end
for _,h in ipairs(badHighways) do
    warn(("[ChesterWorld RoadFinalHighwayGrade] road=%s center=(%.1f,%.1f) grade=%.1f%% threshold=%.1f%%")
        :format(h.name,h.x,h.z,h.grade*100,h.max*100))
end
print(("[ChesterWorld RoadFinalAudit] fragmentCandidates=%d coveredSameRoad=%d coveredOtherRoad=%d STILL_OPEN=%d fullyCoveredSameRoad3of3=%d partialSameRoad=%d otherRoadOnly=%d NOT_VERIFIED=%d unverifiedOnUnmappedGIS=%d unverifiedOnMappedWater=%d unverifiedOnApproxStream=%d checkedRoadParts=%d highwayParts=%d highwayAboveGradeLimit=%d nonHighwaySteep=%d bridgeFlagged=%d bridgeStillSteep=%d auditSeconds=%.1f repairStatus=%s repairParts=%d")
    :format(#fragments,sameRoadCovered,otherRoadCovered,openCount,
        fullOwnRoad,partialOwnRoad,otherRoadOnly,unverified,
        openLand,openMappedWater,openStream,#roadParts,
        highwayPieces,highwayGradeOverLimit,unsafeStreetPieces,
        gradeLimited,gradeLimitedSteep,os.clock()-auditStarted,repairStatus,
        Workspace:GetAttribute("CW_RoadGapRepairParts") or 0))
Workspace:SetAttribute("CW_RoadFinalUnverifiedFragments",unverified)
Workspace:SetAttribute("CW_RoadFinalOpenGaps",openCount)
Workspace:SetAttribute("CW_RoadFinalHighwaySteep",highwayGradeOverLimit)
end -- runAudit

local ok,err=xpcall(runAudit,function(message)
    return debug.traceback(tostring(message),2)
end)
if not ok then
    warn("[ChesterWorld RoadFinalAudit] FAILED: "..tostring(err))
    Workspace:SetAttribute("CW_RoadFinalAuditStatus","failed")
else
    Workspace:SetAttribute("CW_RoadFinalAuditStatus","complete")
end
-- A failed optional diagnostic must not block players for hours.
-- Never label it a successful audit: inspect Status, and the error above.
Workspace:SetAttribute("CW_RoadFinalAuditComplete",true)
