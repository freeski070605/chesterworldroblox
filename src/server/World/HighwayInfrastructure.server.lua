-- ChesterWorld I-95 bridge structure and underpass clearance audit.
-- Runs AFTER the grade-aware RoadTerrainConformer.
-- Adds only physical decks/parapets/supports; never edits terrain or junctions.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldConfig"))

while Workspace:GetAttribute("CW_RoadConformComplete") ~= true do task.wait(0.2) end
local world = Workspace:WaitForChild("ChesterWorld")
local Terrain = Workspace.Terrain

local old = world:FindFirstChild("HighwayInfrastructure")
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "HighwayInfrastructure"
folder.Parent = world

local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = {Terrain}
terrainRay.IgnoreWater = false

local function terrainY(x, z)
    local hit = Workspace:Raycast(Vector3.new(x, 3000, z),
        Vector3.new(0, -6000, 0), terrainRay)
    return hit and hit.Position.Y or nil
end

local function endpoints(part)
    local shift = part.CFrame.LookVector * part.Size.Z / 2
    return part.Position - shift, part.Position + shift
end
local function distXZ(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Z - b.Z)^2)
end
local function roadSegmentDistanceXZ(point, part)
    local a, b = endpoints(part)
    local dx, dz = b.X-a.X, b.Z-a.Z
    local len2 = dx*dx + dz*dz
    if len2 < 0.001 then return distXZ(point,a) end
    local t = math.clamp(((point.X-a.X)*dx+(point.Z-a.Z)*dz)/len2,0,1)
    return distXZ(point, a:Lerp(b,t))
end
local function lineIntersection(a, b, c, d)
    local rx, rz = b.X-a.X,b.Z-a.Z
    local sx, sz = d.X-c.X,d.Z-c.Z
    local det = rx*sz-rz*sx
    if math.abs(det)<0.001 then return nil end
    local dx,dz=c.X-a.X,c.Z-a.Z
    local t=(dx*sz-dz*sx)/det
    local u=(dx*rz-dz*rx)/det
    if t>0.02 and t<0.98 and u>0.02 and u<0.98 then
        return t,u
    end
    return nil
end

local bridge, lower, ramps, unprofiledBridges = {}, {}, {}, {}
for _, tile in ipairs(world:GetChildren()) do
    local roads=tile:FindFirstChild("Roads")
    if roads then
        for _, part in ipairs(roads:GetDescendants()) do
            if part:IsA("BasePart") then
                local level=tonumber(part:GetAttribute("CW_GradeLevel")) or 0
                if part:GetAttribute("CW_BridgeProfiled") == true then
                    table.insert(bridge,part)
                elseif part:GetAttribute("CW_RampProfiled") == true then
                    table.insert(ramps,part)
                elseif part:GetAttribute("CW_Bridge")==true or level>0 then
                    -- This is a bridge missing terrain data, NOT a lower road.
                    table.insert(unprofiledBridges,part)
                else
                    table.insert(lower,part)
                end
            end
        end
    end
end

local CELL=110
local groundGrid={}
for _, part in ipairs(lower) do
    local a,b=endpoints(part)
    local pad=part.Size.X/2+5
    for ix=math.floor((math.min(a.X,b.X)-pad)/CELL),
        math.floor((math.max(a.X,b.X)+pad)/CELL) do
        for iz=math.floor((math.min(a.Z,b.Z)-pad)/CELL),
            math.floor((math.max(a.Z,b.Z)+pad)/CELL) do
            local key=ix..":"..iz
            groundGrid[key]=groundGrid[key] or {}
            table.insert(groundGrid[key],part)
        end
    end
end

local function lowerNearby(a,b)
    local found,seen={},{}
    for ix=math.floor(math.min(a.X,b.X)/CELL)-1,
        math.floor(math.max(a.X,b.X)/CELL)+1 do
        for iz=math.floor(math.min(a.Z,b.Z)/CELL)-1,
            math.floor(math.max(a.Z,b.Z)/CELL)+1 do
            for _,part in ipairs(groundGrid[ix..":"..iz] or {}) do
                if not seen[part] then
                    seen[part]=true
                    table.insert(found,part)
                end
            end
        end
    end
    return found
end

local DECK_THICKNESS=Config.HIGHWAY_DECK_THICKNESS_STUDS or 1.6
local RAIL_HEIGHT=Config.HIGHWAY_GUARDRAIL_HEIGHT_STUDS or 3.2
local COLOR=Color3.fromRGB(125,126,126)
local SUPPORT_COLOR=Color3.fromRGB(139,141,142)
local deckCount,railCount,pierCount=0,0,0

local function partAt(parent,name,size,frame,color,collide)
    local part=Instance.new("Part")
    part.Name=name
    part.Anchored=true
    part.CanCollide=collide
    part.CanTouch=false
    part.CanQuery=collide
    part.CastShadow=true
    part.Material=Enum.Material.Concrete
    part.Color=color
    part.TopSurface=Enum.SurfaceType.Smooth
    part.BottomSurface=Enum.SurfaceType.Smooth
    part.Size=size
    part.CFrame=frame
    part.Parent=parent
    return part
end

local supportLocations={}
local SUPPORT_SPACING=130
local buildingFolders={}
for _,tile in ipairs(world:GetChildren()) do
    local buildings=tile:FindFirstChild("Buildings")
    if buildings then table.insert(buildingFolders,buildings) end
end
local buildingParams=OverlapParams.new()
buildingParams.FilterType=Enum.RaycastFilterType.Include
buildingParams.FilterDescendantsInstances=buildingFolders
buildingParams.MaxParts=1

local function canPier(point,height)
    if height<9 then return false end
    local x,z=point.X,point.Z
    local key=math.floor(x/SUPPORT_SPACING)..":"..math.floor(z/SUPPORT_SPACING)
    if supportLocations[key] then return false end
    for _,road in ipairs(lowerNearby(point,point)) do
        if roadSegmentDistanceXZ(point,road)<road.Size.X/2+5 then
            return false
        end
    end
    -- Query ONLY existing building masses; road Parts would otherwise
    -- consume the overlap-result cap and hide a real building collision.
    if #buildingFolders>0 then
        local hits=Workspace:GetPartBoundsInBox(
            CFrame.new(point.X,point.Y-height/2,point.Z),
            Vector3.new(4,height,4),buildingParams)
        if #hits>0 then return false end
    end
    supportLocations[key]=true
    return true
end

local visuallyRaised={}
for _,part in ipairs(bridge) do table.insert(visuallyRaised,part) end
for _,part in ipairs(ramps) do
    if (part:GetAttribute("CW_RampLiftCenter") or 0)>5 then
        table.insert(visuallyRaised,part)
    end
end

for index,road in ipairs(visuallyRaised) do
    local ground=terrainY(road.Position.X,road.Position.Z)
    local gap=ground and road.Position.Y-ground or 0
    if gap>2.5 then
        local length,width=road.Size.Z,road.Size.X
        local slab=partAt(folder,"BridgeDeck",
            Vector3.new(width+0.6,DECK_THICKNESS,length),
            road.CFrame*CFrame.new(0,-(road.Size.Y+DECK_THICKNESS)/2-0.05,0),
            SUPPORT_COLOR,false)
        slab:SetAttribute("CW_SourceRoad",road.Name)
        deckCount+=1
        -- Place parapets ONLY on actual bridge sections. Adding a pair
        -- to every approach ramp creates walls through entrance/exit merges.
        -- These are cosmetic until abutments and end connections are verified.
        if road:GetAttribute("CW_BridgeProfiled") == true then
            for _,side in ipairs({-1,1}) do
                local beam=partAt(folder,"BridgeParapet",
                    Vector3.new(0.65,RAIL_HEIGHT,length),
                    road.CFrame*CFrame.new(side*(width/2+0.25),
                        road.Size.Y/2+RAIL_HEIGHT/2,0),
                    COLOR,false)
                beam:SetAttribute("CW_GradeGroup",
                    tostring(road:GetAttribute("CW_GradeGroup") or ""))
                railCount+=1
            end
        end
        if index%5==0 then task.wait() end

        -- Side columns are attached only at substantial elevated spans.
        -- Check lower road centerlines before placing each column.
        if gap>18 and length>22 then
            for _,side in ipairs({-1,1}) do
                local sideAxis=road.CFrame.RightVector
                local lateral=sideAxis*side*(width/2+2.4)
                local top=road.Position+lateral-
                    Vector3.new(0,road.Size.Y/2+DECK_THICKNESS,0)
                local below=terrainY(top.X,top.Z)
                if below then
                    local height=top.Y-below
                    if height>9 and canPier(top,height) then
                        partAt(folder,"BridgeSupport",
                            Vector3.new(3.0,height,3.0),
                            CFrame.new(top.X,below+height/2,top.Z),
                            SUPPORT_COLOR,true)
                        pierCount+=1
                    end
                end
            end
        end
    end
    if index%30==0 then task.wait() end
end

-- Report the ACTUAL vertical clearance between every road pair with crossing
-- centerlines on different levels. Do not infer safety from bridge count.
local crossings,tooLow,minClearance=0,0,math.huge
local minRequired=Config.HIGHWAY_MIN_CLEARANCE_STUDS or 18
local clearancePairs={}

for i,upper in ipairs(bridge) do
    local a,b=endpoints(upper)
    for _,groundRoad in ipairs(lowerNearby(a,b)) do
        local c,d=endpoints(groundRoad)
        local t,u=lineIntersection(a,b,c,d)
        if t then
            crossings+=1
            local upperBottom=a.Y+(b.Y-a.Y)*t-upper.Size.Y/2-DECK_THICKNESS
            local lowerTop=c.Y+(d.Y-c.Y)*u+groundRoad.Size.Y/2
            local clearance=upperBottom-lowerTop
            minClearance=math.min(minClearance,clearance)
            if clearance+0.25<minRequired then
                tooLow+=1
                upper:SetAttribute("CW_LowClearance",true)
                local msg=tostring(upper.Name).." over "..tostring(groundRoad.Name)
                if #clearancePairs<12 then
                    table.insert(clearancePairs,string.format("%s=%.1f",msg,clearance))
                end
            end
        end
    end
    if i%30==0 then task.wait() end
end

-- Inspect the actual bridge MIDSPAN and report its X/Z instead of
-- treating embankment contact at every piece's terminal as an overpass failure.
-- This is a non-destructive audit: no terrain edits, no artificial grade fixes.
local bridgeTerrainIntrusions=0
local bridgeTerminalContacts=0
local intrusionDetails={}
for _,road in ipairs(bridge) do
    local a,b=endpoints(road)
    local terminalHit=false
    local midspanHit=false
    local worstGap=math.huge
    for _,t in ipairs({0,0.2,0.4,0.5,0.6,0.8,1}) do
        local p=a:Lerp(b,t)
        local ground=terrainY(p.X,p.Z)
        local underside=p.Y-road.Size.Y/2-DECK_THICKNESS
        if ground and underside<ground+0.25 then
            local deficit=(ground+0.25)-underside
            if t==0 or t==1 then
                terminalHit=true
            else
                midspanHit=true
                worstGap=math.min(worstGap, -deficit)
            end
        end
    end
    if midspanHit then
        road:SetAttribute("CW_BridgeTerrainIntrusion",true)
        bridgeTerrainIntrusions+=1
        table.insert(intrusionDetails,{
            road=road, gap=worstGap, x=road.Position.X, z=road.Position.Z,
        })
    elseif terminalHit then
        road:SetAttribute("CW_BridgeTerminalEmbankmentContact",true)
        bridgeTerminalContacts+=1
    end
end
table.sort(intrusionDetails,function(a,b) return a.gap<b.gap end)

-- A tagged tunnel whose terrain rises through its roadway needs an engineered
-- cut/portal. We DO NOT destroy imported regional terrain automatically.
local tunnelObstructions=0
for _,road in ipairs(lower) do
    if road:GetAttribute("CW_Tunnel")==true
        or (tonumber(road:GetAttribute("CW_GradeLevel")) or 0)<0 then
        local a,b=endpoints(road)
        local mid=road.Position
        for _,p in ipairs({a,mid,b}) do
            local gy=terrainY(p.X,p.Z)
            if gy and gy>p.Y+road.Size.Y/2+1 then
                road:SetAttribute("CW_TunnelTerrainObstruction",true)
                tunnelObstructions+=1
                break
            end
        end
    end
end

Workspace:SetAttribute("CW_HighwayFinishComplete",true)
Workspace:SetAttribute("CW_HighwayClearanceFailures",tooLow)
Workspace:SetAttribute("CW_HighwayTunnelObstructions",tunnelObstructions)
Workspace:SetAttribute("CW_HighwayBridgeTerrainIntrusions",bridgeTerrainIntrusions)
Workspace:SetAttribute("CW_HighwayBridgeEmbankmentContacts",bridgeTerminalContacts)
Workspace:SetAttribute("CW_HighwayCrossingsVerified",crossings>0)

print(("[ChesterWorld HighwayFinish] bridgeRoadParts=%d rampRoadParts=%d deckSlabs=%d guardrails=%d supports=%d crossings=%d minClearance=%.1f lowClearance=%d tunnelObstructions=%d bridgeTerrainIntrusions=%d terminalEmbankmentContacts=%d unprofiledBridgeParts=%d crossingsVerified=%s")
    :format(#bridge,#ramps,deckCount,railCount,pierCount,crossings,
    minClearance==math.huge and -1 or minClearance,tooLow,tunnelObstructions,bridgeTerrainIntrusions,bridgeTerminalContacts,#unprofiledBridges,tostring(crossings>0)))

if tooLow>0 then
    warn("[ChesterWorld HighwayFinish] LOW CLEARANCE: "..
        table.concat(clearancePairs,"; "))
end
if #unprofiledBridges>0 then
    warn(("[ChesterWorld HighwayFinish] %d bridge road parts could not be height-profiled (missing Terrain samples)."):format(#unprofiledBridges))
end
if bridgeTerrainIntrusions>0 then
    warn(("[ChesterWorld HighwayFinish] %d elevated bridge segments still intersect terrain in their interior. Worst locations:"):format(bridgeTerrainIntrusions))
    for index=1,math.min(15,#intrusionDetails) do
        local item=intrusionDetails[index]
        warn(("[ChesterWorld HighwayIssue] road=%s x=%.1f z=%.1f intrusion=%.1f studs group=%s")
            :format(item.road.Name,item.x,item.z,-item.gap,
                tostring(item.road:GetAttribute("CW_GradeGroup") or "")))
    end
end
if crossings==0 then
    warn("[ChesterWorld HighwayFinish] NO GROUND-ROAD CROSSINGS DETECTED: underpass clearances have NOT been verified. Rail/stream crossings are not represented in Road tiles.")
end
if bridgeTerminalContacts>0 then
    print(("[ChesterWorld HighwayFinish] %d additional bridge parts contact embankments at their ends only."):format(bridgeTerminalContacts))
end
if tunnelObstructions>0 then
    warn(("[ChesterWorld HighwayFinish] %d tunnel segments have terrain intrusions. No destructive terrain edits were made."):format(tunnelObstructions))
end
