-- EXIT 6: read-only surveyed-inventory MacDade bridge profile planning.
-- Never modifies paved parts or Terrain. Design locations are provisional:
-- county/bridge inventory provides existence and length, NOT Roblox deck Y.
-- In-game XY candidates come from the exact omitted-road GIS geometry.
local Workspace=game:GetService("Workspace")
local Terrain=Workspace.Terrain
local Builder=require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap=require(script.Parent:WaitForChild("WaterMap"))
Workspace:SetAttribute("CW_MacdadeSurveyComplete",false)

-- References are national bridge-inventory mirrors. Coordinates here are
-- local Roblox candidates derived from Nov 13 omitted Macdade fragments.
-- Do not treat the candidates as surveyed bridge abutments.
local crossings={
    {
        id="MACDADE_RIDLEY_CREEK",name="Ridley Creek",
        center=Vector3.new(7665.5,0,-7719.1),
        radius=245,inventoryFeet=100,structure="15224",
        source="https://usbridges.org/bridge/pa-county-045-bridge-000000000015224",
    },
    {
        id="MACDADE_CRUM_CREEK",name="Crum Creek",
        center=Vector3.new(9979.6,0,-9818.2),
        radius=150,inventoryFeet=95,structure="15226",
        source="https://usbridges.org/states/pennsylvania/delaware-county",
    },
}
local function horizontal(a,b)
    local dx,dz=a.X-b.X,a.Z-b.Z
    return math.sqrt(dx*dx+dz*dz)
end
local function propertyAt(part,x,z)
    local up=part.CFrame.UpVector
    if math.abs(up.Y)<0.85 then return nil end
    local top=part.Position+up*(part.Size.Y/2)
    local y=top.Y-(
        up.X*(x-top.X)+up.Z*(z-top.Z))/up.Y
    local q=part.CFrame:PointToObjectSpace(Vector3.new(x,y,z))
    if math.abs(q.X)>part.Size.X/2+0.6
        or math.abs(q.Z)>part.Size.Z/2+0.6 then
        return nil
    end
    return y
end

local function run()
    while Workspace:GetAttribute("CW_RoadGapRepairComplete")~=true do task.wait(.5) end
    local world=Workspace:FindFirstChild("ChesterWorld")
    if not world then error("World missing after road gap repair") end
    local omissions=Builder.Stats()
    local missing=omissions and omissions.missingFragments or {}
    local roadFolders={}
    for _,tile in ipairs(world:GetChildren()) do
        local roads=tile:FindFirstChild("Roads")
        if roads then table.insert(roadFolders,roads) end
    end
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.FilterDescendantsInstances=roadFolders
    overlap.MaxParts=0
    local ray=RaycastParams.new()
    ray.FilterType=Enum.RaycastFilterType.Include
    ray.FilterDescendantsInstances={Terrain}
    ray.IgnoreWater=false
    local rayLand=RaycastParams.new()
    rayLand.FilterType=Enum.RaycastFilterType.Include
    rayLand.FilterDescendantsInstances={Terrain}
    rayLand.IgnoreWater=true

    local function roadSurface(x,z)
        local parts=Workspace:GetPartBoundsInBox(CFrame.new(x,150,z),
            Vector3.new(3,500,3),overlap)
        local best,bestY=nil,-math.huge
        for _,part in ipairs(parts) do
            if part:IsA("BasePart") and part.Name=="Macdade"
                and part.CanCollide and part.Transparency<1
                and part:GetAttribute("CW_HighwayProfiled")~=true then
                local y=propertyAt(part,x,z)
                if y and y>bestY then
                    bestY=y
                    best=part
                end
            end
        end
        return best and bestY or nil
    end
    local function groundAt(x,z)
        local start=Vector3.new(x,5000,z)
        local dir=Vector3.new(0,-10000,0)
        local wet=Workspace:Raycast(start,dir,ray)
        local land=Workspace:Raycast(start,dir,rayLand)
        return land and land.Position.Y or nil,
            wet and wet.Material==Enum.Material.Water
    end
    local samples={-320,-240,-180,-140,-100,-60,-30,0,30,60,100,140,180,240,320}
    for _,site in ipairs(crossings) do
        local fragments,major={},nil
        local count,length=0,0
        for _,f in ipairs(missing) do
            if f.kind=="steep" and tostring(f.road)=="Macdade" then
                local mx,mz=(f.ax+f.bx)/2,(f.az+f.bz)/2
                if horizontal(Vector3.new(mx,0,mz),site.center)<=site.radius then
                    count+=1
                    length+=f.length
                    table.insert(fragments,f)
                    if not major or f.length>major.length then major=f end
                end
            end
        end
        if major then
            local d=Vector3.new(major.bx-major.ax,0,major.bz-major.az).Unit
            if d.X<0 then d=-d end
            -- Use the midpoint of the largest SOURCE omission as a station
            -- anchor; it is not the structural inventory's surveyed center.
            local origin=Vector3.new((major.ax+major.bx)/2,0,
                (major.az+major.bz)/2)
            local logSamples={}
            local valid={}
            local missingSamples,waterHits=0,0
            local stationFacts={}
            for _,station in ipairs(samples) do
                local pt=origin+d*station
                local y=roadSurface(pt.X,pt.Z)
                local gy,wet=groundAt(pt.X,pt.Z)
                local classification=WaterMap.Classify(pt.X,pt.Z)
                if not y then missingSamples+=1
                else table.insert(valid,{s=station,y=y}) end
                if wet or classification=="mappedPolygon" or
                    classification=="approxStream" then
                    waterHits+=1
                end
                table.insert(logSamples,string.format(
                    "%s:%s/%s/%s",
                    station,
                    y and string.format("%.1f",y) or "_",
                    gy and string.format("%.1f",gy) or "_",
                    wet and "wet" or classification))
                table.insert(stationFacts,{s=station,y=y,ground=gy,wet=wet,
                    class=classification})
            end
            local left,right=nil,nil
            for _,data in ipairs(valid) do
                if data.s<=-140 and (not left or data.s>left.s) then left=data end
                if data.s>=140 and (not right or data.s<right.s) then right=data end
            end
            local grade=left and right and
                math.abs(right.y-left.y)/(right.s-left.s) or nil
            local estStuds=site.inventoryFeet*0.3048*3.906
            local gtext=grade and string.format("%.1f",grade*100) or "unknown"
            local needs=grade and grade<=.11 and "candidate-profile-not-validated"
                or "requires-banks-and-longitudinal-profile"
            print(("[ChesterWorld MacdadeBridgeSurvey] id=%s waterway=%s inventory=%sft (~%.0f horizontal studs at Chester projection) countyBridge=%s sourceFragments=%d sourceMissingLength=%.1f sampleOrigin=(%.1f,%.1f) axis=(%.3f,%.3f) roadPavementSamplesMissing=%d waterSampleHits=%d farBankGradePct=%s status=%s")
                :format(site.id,site.name,site.inventoryFeet,estStuds,
                    site.structure,count,length,origin.X,origin.Z,d.X,d.Z,
                    missingSamples,waterHits,gtext,needs))
            print("[ChesterWorld MacdadeBridgeStations] id="..site.id..
                " station:renderedRoadY/terrainLandY/waterGIS="..
                table.concat(logSamples," "))
            -- These arrays are diagnostic source traces only. Under no
            -- circumstances should an estimated bank height be used as
            -- a bridge deck or a new terrain import without inspection.
        else
            warn("[ChesterWorld MacdadeBridgeSurvey] no omitted Macdade road fragments inside approximate bounds for "..site.id)
        end
    end
end

local ok,err=pcall(run)
if not ok then warn("[ChesterWorld MacdadeBridgeSurvey] FAILED "..tostring(err)) end
Workspace:SetAttribute("CW_MacdadeSurveyComplete",true)
