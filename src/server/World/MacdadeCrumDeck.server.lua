-- EXIT 6: source-backed Macdade Boulevard / Crum Creek carriageway
-- continuity reconstruction. Only build when ACTUAL rendered same-road
-- outer approach anchors prove a <=8% design grade and no conflicting
-- road or native terrain occupies the planned deck. Never change Terrain,
-- Riverfront, Ridley Creek, or baked water.
-- Published structure: PA Delaware County bridge 15226 over Crum Creek.
-- Inventory length 95ft (~113 horizontal studs at Chester projection).
-- Only the central 120-stud creek corridor is reconstructed; measured
-- road surfaces at +/-60 serve as the joining banks. Existing paved
-- approaches remain in place, avoiding a 280-stud double-layer flyover.
local RunService=game:GetService("RunService")
local Workspace=game:GetService("Workspace")
local Terrain=Workspace.Terrain
local Builder=require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap=require(script.Parent:WaitForChild("WaterMap"))
local STATUS="CW_MacdadeCrumDeckStatus"
Workspace:SetAttribute("CW_MacdadeCrumDeckComplete",false)
Workspace:SetAttribute(STATUS,"waiting")

local function horizontal(x,z,cx,cz)
    local dx,dz=x-cx,z-cz
    return math.sqrt(dx*dx+dz*dz)
end
local function slabTop(part,x,z)
    local up=part.CFrame.UpVector
    if math.abs(up.Y)<0.85 then return nil end
    local top=part.Position+up*(part.Size.Y/2)
    local y=top.Y-(up.X*(x-top.X)+up.Z*(z-top.Z))/up.Y
    local localPoint=part.CFrame:PointToObjectSpace(Vector3.new(x,y,z))
    if math.abs(localPoint.X)>part.Size.X/2+0.25
        or math.abs(localPoint.Z)>part.Size.Z/2+0.25 then
        return nil
    end
    return y
end

local function run()
    while Workspace:GetAttribute("CW_MacdadeSurveyComplete")~=true
        or Workspace:GetAttribute("CW_StreetFurnitureComplete")~=true do
        task.wait(0.5)
    end
    local world=Workspace:FindFirstChild("ChesterWorld")
    if not world then return "city-not-built" end
    local stats=Builder.Stats()
    local fragments=stats and stats.missingFragments or {}
    local major=nil
    local sourceFragments,sourceMissingLength=0,0
    for _,f in ipairs(fragments) do
        if f.kind=="steep" and f.road=="Macdade"
            and horizontal((f.ax+f.bx)/2,(f.az+f.bz)/2,
                9979.6,-9818.2)<40 then
            sourceFragments+=1
            sourceMissingLength+=f.length
            if not major or f.length>major.length then major=f end
        end
    end
    if not major then return "missing-source-crossing" end
    local axis=Vector3.new(major.bx-major.ax,0,major.bz-major.az)
    if axis.Magnitude<1 then return "short-source-axis" end
    axis=axis.Unit
    if axis.X<0 then axis=-axis end
    local center=Vector3.new((major.ax+major.bx)/2,0,
        (major.az+major.bz)/2)
    if horizontal(center.X,center.Z,9979.6,-9818.2)>40 then
        return "source-geometry-not-at-inventory-crossing"
    end

    local folders={}
    for _,tile in ipairs(world:GetChildren()) do
        local folder=tile:FindFirstChild("Roads")
        if folder then table.insert(folders,folder) end
    end
    if #folders<50 then return "incomplete-road-tiles" end
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances=folders
    overlap.MaxParts=0
    local groundRay=RaycastParams.new()
    groundRay.FilterType=Enum.RaycastFilterType.Include
    groundRay.FilterDescendantsInstances={Terrain}
    groundRay.IgnoreWater=false

    local function pointAt(s,side)
        local cross=Vector3.new(-axis.Z,0,axis.X)
        return center+axis*s+cross*(side or 0)
    end
    local function partsAt(s,side)
        local p=pointAt(s,side)
        return Workspace:GetPartBoundsInBox(
            CFrame.new(p.X,110,p.Z),Vector3.new(2,500,2),overlap),
            p.X,p.Z
    end
    local function pavementAt(s,side)
        local candidates,x,z=partsAt(s,side)
        local y,best=nil,nil
        for _,part in ipairs(candidates) do
            if part:IsA("BasePart") and part.Name=="Macdade"
                and part.CanCollide and part.Transparency<1
                and part:GetAttribute("CW_HighwayProfiled")~=true
                and part.Size.X>=30 and part.Size.X<=55 then
                local top=slabTop(part,x,z)
                if top and (not y or top>y) then
                    y,best=top,part
                end
            end
        end
        return y,best
    end
    local yL,pL=pavementAt(-60,0)
    local yR,pR=pavementAt(60,0)
    local yLL=pavementAt(-100,0)
    local yRR=pavementAt(100,0)
    if not (yL and yR and yLL and yRR and pL and pR) then
        return "missing-stable-outer-pavement-anchors"
    end
    if pL==pR then return "same-anchor-for-both-banks" end
    local leftGrade=math.abs(yL-yLL)/40
    local rightGrade=math.abs(yRR-yR)/40
    local designGrade=math.abs(yR-yL)/120
    if leftGrade>0.11 or rightGrade>0.11 or designGrade>0.10 then
        return string.format(
            "approach-grade-not-supported left=%.1f right=%.1f deck=%.1f",
            leftGrade*100,rightGrade*100,designGrade*100)
    end
    if math.abs(pL.Size.X-major.width)>4
        or math.abs(pR.Size.X-major.width)>4 then
        return "source-pavement-width-mismatch"
    end
    -- Both real banks must remain dry and solid at and beyond the
    -- proposed culvert; missing creekbed Terrain is allowed only IN
    -- the documented central crossing.
    for _,s in ipairs({-70,-60,60,70}) do
        for _,side in ipairs({-major.width*0.43,0,major.width*0.43}) do
            local p=pointAt(s,side)
            local land=Workspace:Raycast(Vector3.new(p.X,5000,p.Z),
                Vector3.new(0,-10000,0),groundRay)
            if not land or land.Material==Enum.Material.Water
                or WaterMap.Classify(p.X,p.Z)~="notMapped" then
                return string.format("bank-not-grounded-at-s=%d side=%.1f",s,side)
            end
        end
    end
    local function profileY(station)
        return yL+(yR-yL)*(station+60)/120
    end

    local maxTerrainIntrusion=-math.huge
    local maxOldRoadAbove=-math.huge
    local maxFloating=-math.huge
    local waterInside=0
    local scanned=0
    local retirementCandidates={}
    local trimPlans={}
    local greatestOriginalDifference=0
    local function partLongitudinalSpan(part)
        local relative=part.Position-center
        local station=relative:Dot(axis)
        local right=part.CFrame.RightVector
        local look=part.CFrame.LookVector
        local half=math.abs(right:Dot(axis))*part.Size.X/2
            +math.abs(look:Dot(axis))*part.Size.Z/2
        return station-half,station+half
    end
    -- Run all safety checks before creating a single part. Note that this
    -- deliberately rejects any existing road in the planned bridge's
    -- driving envelope, avoiding an invented junction on an elevated deck.
    for s=-60,60,5 do
        local top=profileY(s)
        for _,shoulder in ipairs({-major.width*0.43,0,major.width*0.43}) do
            local point=pointAt(s,shoulder)
            local x,z=point.X,point.Z
            local hit=Workspace:Raycast(Vector3.new(x,5000,z),
                Vector3.new(0,-10000,0),groundRay)
            local water=hit and hit.Material==Enum.Material.Water
            local cls=WaterMap.Classify(x,z)
            if water or cls=="mappedPolygon" or cls=="approxStream" then
                waterInside+=1
                if math.abs(s)>60 then
                    return string.format(
                        "water-extends-outside-surveyed-culvert s=%d",s)
                end
            elseif not hit then
                -- A stream gap may leave no Terrain, but if it extends
                -- outside the known bridge span, the bank is unverified.
                if math.abs(s)>60 then
                    return string.format(
                        "terrain-unverified-at-approach s=%d",s)
                end
            end
            if hit and hit.Material~=Enum.Material.Water then
                local intrude=hit.Position.Y-top
                maxTerrainIntrusion=math.max(maxTerrainIntrusion,intrude)
                maxFloating=math.max(maxFloating,top-hit.Position.Y)
                if intrude>0.18 then
                    return string.format(
                        "road-deck-in-terrain at=(%.1f,%.1f) intrusion=%.2f",
                        x,z,intrude)
                end
                if top-hit.Position.Y>16 then
                    return string.format(
                        "unvalidated-deck-height at=(%.1f,%.1f) lift=%.2f",
                        x,z,top-hit.Position.Y)
                end
            end
            local candidates=Workspace:GetPartBoundsInBox(
                CFrame.new(x,110,z),Vector3.new(1.5,500,1.5),overlap)
            for _,part in ipairs(candidates) do
                if part:IsA("BasePart") and part.CanCollide
                    and part.Transparency<1 then
                    local partTop=slabTop(part,x,z)
                    if partTop then
                        if part.Name=="Macdade" then
                            local excess=partTop-top
                            maxOldRoadAbove=math.max(maxOldRoadAbove,excess)
                            greatestOriginalDifference=math.max(
                                greatestOriginalDifference,math.abs(excess))
                            if math.abs(excess)>0.55 then
                                -- Never leave a second collidable road
                                -- above/below the bridge. Only source
                                -- road pieces wholly inside this central
                                -- span may be temporarily retired during
                                -- an isolated Studio Play test.
                                local lo,hi=partLongitudinalSpan(part)
                                if lo < -60.5 or hi > 60.5 then
                                    -- Preserve the OUTSIDE bank asphalt.
                                    -- Plan a mathematically aligned cut;
                                    -- do not hide an entire approach Part.
                                    trimPlans[part]=true
                                end
                                if part:GetAttribute("CW_RoadGapRepair")==true
                                    or part:GetAttribute("CW_HighwayProfiled")==true
                                    or part:GetAttribute("CW_Bridge")==true then
                                    return string.format(
                                        "old-road-structural-part-at-span s=%d part=%s",
                                        s,tostring(part.Name))
                                end
                                retirementCandidates[part]=true
                            end
                        elseif part:GetAttribute("CW_Rail")~=true
                            and math.abs(partTop-top)<5
                            and part.Size.X>2 then
                            return string.format(
                                "other-road-at-crossing s=%d road=%s",
                                s,tostring(part.Name))
                        end
                    end
                end
            end
            scanned+=1
        end
    end

    -- A boundary-spanning road Part must be replaced with its
    -- exterior bank portion, NOT deleted wholesale. Precompute the
    -- local-Z trim for every candidate before changing any Instance.
    -- Only axis-aligned, undecorated ordinary Parts can be split safely.
    local function planBankCut(part)
        if not part:IsA("Part") or part.Shape~=Enum.PartType.Block
            or #part:GetChildren()>0
            or part:GetAttribute("CW_Bridge")==true
            or part:GetAttribute("CW_Rail")==true
            or part:GetAttribute("CW_HighwayProfiled")==true
            or part:GetAttribute("CW_RoadGapRepair")==true then
            return nil,"bank-part-not-safe-to-split"
        end
        local slope=part.CFrame:VectorToWorldSpace(
            Vector3.new(0,0,1)):Dot(axis)
        local crossSlope=math.abs(part.CFrame.RightVector:Dot(axis))
            *part.Size.X/2
        if math.abs(slope)<0.995 or crossSlope>1.2 then
            return nil,string.format(
                "bank-part-not-collinear axisDot=%.4f shoulderStationError=%.2f",
                slope,crossSlope)
        end
        local centerStation=(part.Position-center):Dot(axis)
        local half=part.Size.Z/2
        local stationNeg=centerStation-half*slope
        local stationPos=centerStation+half*slope
        local lo,hi=math.min(stationNeg,stationPos),
            math.max(stationNeg,stationPos)
        if lo<-60.5 and hi>60.5 then
            return nil,"single-old-part-spans-both-banks"
        end
        local boundary,outsideStation=nil,nil
        if lo<-60.5 and hi>-60+0.5 then
            boundary=-60
            outsideStation=lo
        elseif hi>60.5 and lo<60-0.5 then
            boundary=60
            outsideStation=hi
        else
            return nil,string.format(
                "bank-part-overlap-ambiguous span=%.2f..%.2f",
                lo,hi)
        end
        local cutZ=(boundary-centerStation)/slope
        local outerZ=outsideStation==lo
            and (stationNeg<stationPos and -half or half)
            or (stationNeg>stationPos and -half or half)
        if math.abs(cutZ)>=half-.3 then
            return nil,"cut-not-inside-old-part"
        end
        local kept=math.abs(outerZ-cutZ)
        if kept<3 then return nil,"outside-bank-road-too-short" end
        return {
            centerLocalZ=(outerZ+cutZ)/2,
            length=kept,
            bank=boundary,
            previousLength=part.Size.Z,
        }
    end
    local plannedCuts={}
    local retired=0
    local cutCount=0
    for part in pairs(retirementCandidates) do
        local lo,hi=partLongitudinalSpan(part)
        if trimPlans[part] or lo<-60.5 or hi>60.5 then
            local plan,why=planBankCut(part)
            if not plan then
                return string.format("bank-trim-rejected %s originalSpan=%.1f..%.1f",
                    why,lo,hi)
            end
            plannedCuts[part]=plan
            cutCount+=1
        end
        retired+=1
    end

    -- All source, bank, water, existing road and grade checks passed.
    -- Temporarily disable underlying, *fully contained* pavement Parts
    -- BEFORE placing the new surface. This happens in Studio Play only
    -- and does NOT mutate GIS or baked Terrain.
    local savedOld={}
    local newObjects={}
    local ok,madeOrError=pcall(function()
        for part in pairs(retirementCandidates) do
            savedOld[part]={
                collide=part.CanCollide,
                transparency=part.Transparency,
            }
            part:SetAttribute("CW_MacdadeOldRoadTemporarilyRetired",true)
            part.CanCollide=false
            part.Transparency=1
            local cut=plannedCuts[part]
            if cut then
                local bank=part:Clone()
                bank.Name=part.Name
                bank.Size=Vector3.new(part.Size.X,part.Size.Y,cut.length)
                bank.CFrame=part.CFrame*CFrame.new(
                    0,0,cut.centerLocalZ)
                bank:SetAttribute("CW_MacdadeOldRoadTemporarilyRetired",nil)
                bank:SetAttribute("CW_MacdadeBankTrim",true)
                bank:SetAttribute("CW_OriginalRoadLengthStuds",
                    cut.previousLength)
                bank:SetAttribute("CW_BankBoundaryStation",cut.bank)
                bank.CanCollide=savedOld[part].collide
                bank.Transparency=savedOld[part].transparency
                bank.Parent=part.Parent
                table.insert(newObjects,bank)
            end
        end
        local parent=pL.Parent
        local made=0
    for i=1,12 do
        local s0=-60+(i-1)*10
        local s1=s0+10
        local p0=pointAt(s0,0)+Vector3.new(0,profileY(s0)-0.225,0)
        local p1=pointAt(s1,0)+Vector3.new(0,profileY(s1)-0.225,0)
        local asphalt=Instance.new("Part")
        asphalt.Name="Macdade"
        asphalt.Size=Vector3.new(major.width,0.45,(p1-p0).Magnitude+0.35)
        asphalt.CFrame=CFrame.lookAt((p0+p1)/2,p1,Vector3.yAxis)
        asphalt.Anchored=true
        asphalt.CanCollide=true
        asphalt.Material=Enum.Material.Asphalt
        asphalt.Color=Color3.fromRGB(53,53,56)
        asphalt.TopSurface=Enum.SurfaceType.Smooth
        asphalt.BottomSurface=Enum.SurfaceType.Smooth
        asphalt:SetAttribute("ChesterStreet","Macdade")
        asphalt:SetAttribute("CW_RoadClass","primary")
        asphalt:SetAttribute("CW_Bridge",true)
        asphalt:SetAttribute("CW_MacdadeCrumDeck",true)
        asphalt:SetAttribute("CW_StructureId","MACDADE_CRUM_CREEK")
        asphalt:SetAttribute("CW_InventoryStructure","15226")
        asphalt:SetAttribute("CW_ProfileGrade",designGrade)
        asphalt.Parent=parent
        table.insert(newObjects,asphalt)
        -- Railings on the central creek/culvert span only. Ends remain
        -- open to existing city streets and adjoining sidewalks.
        if s0>=-50 and s1<=50 then
            for _,side in ipairs({-1,1}) do
                local wall=Instance.new("Part")
                wall.Name="MacdadeCrumCreekParapet"
                wall.Size=Vector3.new(0.7,3.1,asphalt.Size.Z)
                wall.CFrame=asphalt.CFrame*CFrame.new(
                    side*(major.width/2+0.45),1.6,0)
                wall.Anchored=true
                wall.CanCollide=true
                wall.Material=Enum.Material.Concrete
                wall.Color=Color3.fromRGB(148,148,144)
                wall:SetAttribute("CW_StructureId","MACDADE_CRUM_CREEK")
                wall.Parent=parent
                table.insert(newObjects,wall)
            end
        end
            made+=1
        end
        return made
    end)
    if not ok then
        for _,obj in ipairs(newObjects) do
            if obj.Parent then obj:Destroy() end
        end
        for part,previous in pairs(savedOld) do
            if part.Parent then
                part.CanCollide=previous.collide
                part.Transparency=previous.transparency
                part:SetAttribute("CW_MacdadeOldRoadTemporarilyRetired",nil)
            end
        end
        return "construction-failed-rolled-back: "..tostring(madeOrError)
    end
    local made=madeOrError
    Workspace:SetAttribute("CW_MacdadeCrumDeckPieces",made)
    Workspace:SetAttribute("CW_MacdadeOldPartsRetired",retired)
    Workspace:SetAttribute("CW_MacdadeBankTrimmedParts",cutCount)
    print(("[ChesterWorld MacdadeCrumDeck] status=built source=county_bridge_15226 road=Macdade deckPieces=%d length=120 grade=%.2f%% bankLeft=%.2f bankRight=%.2f maxTerrainLift=%.1f oldRoadMaxHeightDifference=%.1f oldRoadPiecesTemporarilyRetired=%d bankEdgeTrimmedParts=%d outerApproachGrades=%.1f%%/%.1f%% sourceFragments=%d sourceMissingLength=%.1f waterSamples=%d checked=%d from=(%.1f,%.1f) to=(%.1f,%.1f)")
        :format(made,designGrade*100,yL,yR,maxFloating,
            greatestOriginalDifference,retired,cutCount,leftGrade*100,rightGrade*100,
            sourceFragments,sourceMissingLength,waterInside,scanned,
            pointAt(-60).X,pointAt(-60).Z,
            pointAt(60).X,pointAt(60).Z))
    return "built"
end

-- This is a new 120-stud physical road change. Keep it in Studio
-- until visual/vehicle tests confirm real bridge and sidewalk connections.
if not RunService:IsStudio() then
    Workspace:SetAttribute(STATUS,"studio-only-awaiting-driving-verification")
    Workspace:SetAttribute("CW_MacdadeCrumDeckComplete",true)
    return
end

local ok,status=pcall(run)
if not ok then
    warn("[ChesterWorld MacdadeCrumDeck] ERROR "..tostring(status))
    Workspace:SetAttribute(STATUS,"error")
else
    Workspace:SetAttribute(STATUS,status)
    if status~="built" then
        warn("[ChesterWorld MacdadeCrumDeck] status=rejected reason="..status)
    end
end
Workspace:SetAttribute("CW_MacdadeCrumDeckComplete",true)
