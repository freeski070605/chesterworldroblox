-- ChesterWorld | Kerlin / I-95 | OPT-IN, STUDIO-ONLY DRIVE TEST.
-- Uses the two measured I-95 tie-ins from the successful grade-profile preview.
-- This is an EXPERIMENTAL PHYSICAL ROAD PROFILE, NOT AN ENGINEERING DESIGN.
-- Run ONLY after Bootstrap + RoadConform + HighwayFinish in a Studio Play server.
--
-- Run({isolateLegacy=false}) creates collidable elevated test pavement without
-- changing any existing Instances. Run({isolateLegacy=true}) additionally hides
-- existing I-95 strips ONLY when their full lengths fit within the test corridor.
-- Both modes are reversible with Clear(). No Terrain, GIS, spawn or place edits.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Test = {}

local NAME = "KerlinDrivableTest_TEMP"
local OWNER_ATTR = "CW_KerlinDrivableTestOwned"
local TIE = 120                -- measured locations, not surveyed ramp limits
local DECK_START = -35        -- aerial-estimate bridge ends, NOT verified abutments
local DECK_END = 35
local STEP = 6
local ROAD_DEPTH = 0.45       -- temporary pavement thickness in studs
local DECK_DEPTH = 1.6        -- TEMPORARY structural what-if, NOT surveyed depth
local EXTRA_LENGTH = 0.3     -- small seams overlap
local REFERENCE_OPENING = 12.878  -- provisional inventory figure, NOT a code limit
local INNER_MUTE_LIMIT = 114  -- protect existing roadway outside the test tie-ins

local ROUTES = {
    {
        name = "county:424/425",
        ids = {[424]=true,[425]=true},
        origin = Vector2.new(2015.268,25.443),
        direction = Vector2.new(7120.060-7019.645,-(7244.322-7193.492)).Unit,
        width = 75,
        tint = Color3.fromRGB(68,86,93),
    },
    {
        name = "county:423/426",
        ids = {[423]=true,[426]=true},
        origin = Vector2.new(1990.695,-20.670),
        direction = Vector2.new(7270.559-7011.454,-(7343.750-7208.863)).Unit,
        width = 36,
        tint = Color3.fromRGB(89,83,70),
    },
}
local KERLIN_IDS = {[2758]=true,[27163]=true,[20771]=true,[20770]=true}
local JOINTS = {
    {name="north",x=2015.268,z=25.443},
    {name="south",x=1990.695,z=-20.670},
}

-- Original properties are held in-memory during one Play session only.
local muted = {}
local currentFolder = nil

local function log(stage,status,msg)
    print(("KERLIN_DRIVE | %s | %s | %s"):format(stage,status,msg))
end
local function fmt(value)
    return value and string.format("%.3f",value) or "UNKNOWN"
end
local function ready()
    if not RunService:IsStudio() or not RunService:IsServer() then
        log("READY","FAIL","Run in Roblox Studio Play, SERVER Command Bar")
        return nil
    end
    if Workspace:GetAttribute("CW_QuickStreetPreview") == true then
        log("READY","FAIL","Quick preview is not sufficient")
        return nil
    end
    for _,flag in ipairs({"CW_BootstrapComplete","CW_RoadConformComplete","CW_HighwayFinishComplete"}) do
        if Workspace:GetAttribute(flag) ~= true then
            log("READY","FAIL",flag.." is not true yet")
            return nil
        end
    end
    local world = Workspace:FindFirstChild("ChesterWorld")
    if not world or not world:FindFirstChild("tile_r07_c07") then
        log("READY","FAIL","Expected Kerlin tile is not loaded")
        return nil
    end
    return world
end
local function groupId(part)
    return tonumber(tostring(part:GetAttribute("CW_GradeGroup") or ""):match("^county:(%d+):"))
end
local function collect(world, ids, folderName)
    local found = {}
    for _,tile in ipairs(world:GetChildren()) do
        if tile.Name:match("^tile_") then
            local roadFolder = tile:FindFirstChild(folderName)
            if roadFolder then
                for _,part in ipairs(roadFolder:GetDescendants()) do
                    if part:IsA("BasePart") and ids[groupId(part)] then
                        table.insert(found,part)
                    end
                end
            end
        end
    end
    return found
end
local function raycastY(parts,x,z,fromBelow)
    if #parts == 0 then return nil end
    local params=RaycastParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances=parts
    params.IgnoreWater=false
    local origin=Vector3.new(x,fromBelow and -2000 or 2000,z)
    local dir=Vector3.new(0,fromBelow and 4000 or -4000,0)
    local hit=Workspace:Raycast(origin,dir,params)
    return hit and hit.Position.Y or nil
end
local terrainParams=RaycastParams.new()
terrainParams.FilterType=Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances={Workspace.Terrain}
terrainParams.IgnoreWater=false
local function terrainY(x,z)
    local hit=Workspace:Raycast(Vector3.new(x,2000,z),Vector3.new(0,-4000,0),terrainParams)
    return hit and hit.Position.Y or nil
end
local function station(route,t)
    return route.origin+route.direction*t
end
local function smoothstep(v)
    v=math.clamp(v,0,1)
    return v*v*(3-2*v)
end
local function profile(t,low,mid,high)
    if t<DECK_START then
        return low+(mid-low)*smoothstep((t+TIE)/(TIE+DECK_START))
    elseif t>DECK_END then
        return mid+(high-mid)*smoothstep((t-DECK_END)/(TIE-DECK_END))
    end
    return mid
end
local function stations()
    local values={-TIE,DECK_START,0,DECK_END,TIE}
    for t=-TIE,TIE,STEP do table.insert(values,t) end
    table.sort(values)
    local dedup={}
    for _,value in ipairs(values) do
        if #dedup==0 or value-dedup[#dedup]>0.001 then
            table.insert(dedup,value)
        end
    end
    return dedup
end
local function pieceEnds(part)
    local half=part.CFrame.LookVector*(part.Size.Z/2)
    return part.Position-half,part.Position+half
end
local function along(route,point)
    return (Vector2.new(point.X,point.Z)-route.origin):Dot(route.direction)
end
local function ownedFolder(world)
    local obj=world:FindFirstChild(NAME)
    if obj and obj:GetAttribute(OWNER_ATTR) ~= true then
        error("Refusing to overwrite unowned "..obj:GetFullName())
    end
    return obj
end
local function restore()
    for part,old in pairs(muted) do
        if part.Parent then
            part.Transparency=old.transparency
            part.CanCollide=old.collide
            part.CanQuery=old.query
            part.CanTouch=old.touch
            part.CastShadow=old.shadow
        end
    end
    muted={}
    if currentFolder and currentFolder.Parent and currentFolder:GetAttribute(OWNER_ATTR)==true then
        currentFolder:Destroy()
    end
    currentFolder=nil
end
function Test.Clear()
    if not RunService:IsStudio() or not RunService:IsServer() then
        log("CLEAR","FAIL","Studio Play SERVER required")
        return false
    end
    restore()
    local world=Workspace:FindFirstChild("ChesterWorld")
    if world then
        local old=ownedFolder(world)
        if old then old:Destroy() end
    end
    log("CLEAR","PASS","Test road deleted; all original Part properties restored")
    return true
end
local function mute(part)
    if muted[part] then return end
    muted[part]={
        transparency=part.Transparency,
        collide=part.CanCollide,
        query=part.CanQuery,
        touch=part.CanTouch,
        shadow=part.CastShadow,
    }
    part.Transparency=1
    part.CanCollide=false
    part.CanQuery=false
    part.CanTouch=false
    part.CastShadow=false
end
local function makePart(folder,name,a,b,width,depth,color,deck)
    local length=(b-a).Magnitude
    if length<0.05 then return nil end
    local part=Instance.new("Part")
    part.Name=name
    part.Anchored=true
    part.Size=Vector3.new(width,depth,length+EXTRA_LENGTH)
    local frame=CFrame.lookAt((a+b)/2,b,Vector3.yAxis)
    part.CFrame=frame*CFrame.new(0,-depth/2,0)
    part.Material=deck and Enum.Material.Concrete or Enum.Material.Asphalt
    part.Color=color
    part.TopSurface=Enum.SurfaceType.Smooth
    part.BottomSurface=Enum.SurfaceType.Smooth
    part.CanCollide=true
    part.CanQuery=true
    part.CanTouch=true
    part.CastShadow=true
    part:SetAttribute(OWNER_ATTR,true)
    part:SetAttribute("CW_ExperimentOnly",true)
    part:SetAttribute("CW_AssumedThicknessStuds",depth)
    part:SetAttribute("CW_SurveyedAbutment",false)
    part.Parent=folder
    return part
end
local function preflightLegacy(parts,route)
    local candidates={}
    local unsafe={}
    for _,part in ipairs(parts) do
        local a,b=pieceEnds(part)
        local ta,tb=along(route,a),along(route,b)
        local left,right=math.min(ta,tb),math.max(ta,tb)
        if right>=-DECK_END and left<=DECK_END then
            if left<-INNER_MUTE_LIMIT or right>INNER_MUTE_LIMIT then
                table.insert(unsafe,part)
            end
        end
        if left>=-INNER_MUTE_LIMIT and right<=INNER_MUTE_LIMIT then
            table.insert(candidates,part)
        end
    end
    return candidates,unsafe
end

function Test.Run(options)
    options=options or {}
    local world=ready()
    if not world then return false end
    local isolate=options.isolateLegacy==true
    local tracks={}
    local lower=collect(world,KERLIN_IDS,"Roads")
    if #lower==0 then
        log("SOURCE","FAIL","Kerlin road Parts unavailable")
        return false
    end
    local existing=ownedFolder(world)
    if existing and existing~=currentFolder then
        log("OWNER","FAIL","Found an existing test folder from another module instance; remove in a fresh Play session")
        return false
    end
    local stationsList=stations()
    local toMute={}
    local toMuteSet={}
    local oldMarkings=0
    for _,route in ipairs(ROUTES) do
        local parts=collect(world,route.ids,"Roads")
        if #parts==0 then
            log("SOURCE","FAIL",route.name.." road Parts unavailable")
            return false
        end
        local a=station(route,-TIE)
        local b=station(route,TIE)
        local ya=raycastY(parts,a.X,a.Y,false)
        local yb=raycastY(parts,b.X,b.Y,false)
        if not ya or not yb then
            log("TIE_IN","FAIL",route.name.." is missing a measured road surface at +/-120 studs")
            return false
        end
        local mid=(ya+yb)/2
        tracks[#tracks+1]={route=route,parts=parts,first=ya,last=yb,mid=mid}
        if isolate then
            local candidates,unsafe=preflightLegacy(parts,route)
            if #unsafe>0 then
                log("ISOLATE","FAIL",string.format("%s has %d road parts intersecting bridge core but extending outside safe edit corridor; left untouched",route.name,#unsafe))
                return false
            end
            for _,part in ipairs(candidates) do
                if not toMuteSet[part] then
                    toMuteSet[part]=true
                    table.insert(toMute,part)
                end
            end
            local markings=collect(world,route.ids,"RoadMarkings")
            for _,mark in ipairs(markings) do
                local ma,mb=pieceEnds(mark)
                local ta,tb=along(route,ma),along(route,mb)
                if math.min(ta,tb)>=-INNER_MUTE_LIMIT and math.max(ta,tb)<=INNER_MUTE_LIMIT then
                    if not toMuteSet[mark] then
                        toMuteSet[mark]=true
                        table.insert(toMute,mark)
                        oldMarkings+=1
                    end
                end
            end
        end
    end

    -- All checks above run before any existing part is changed.
    Test.Clear()
    local folder=Instance.new("Folder")
    folder.Name=NAME
    folder:SetAttribute(OWNER_ATTR,true)
    folder:SetAttribute("CW_KerlinTestIsolated",isolate)
    folder:SetAttribute("CW_ExperimentalRoadProfile",true)
    folder.Parent=world
    currentFolder=folder
    local generated={}
    local terrainAbove=0
    local worstTerrain=0
    local ok,err=pcall(function()
        for idx,track in ipairs(tracks) do
            local route=track.route
            local roadFolder=Instance.new("Folder")
            roadFolder.Name=("Route%d_%s"):format(idx,route.name:gsub("[^%w]","_"))
            roadFolder.Parent=folder
            local edge=Vector2.new(-route.direction.Y,route.direction.X)
            local prevPt=nil
            local prevT=nil
            local maxSlope=0
            local count=0
            for _,t in ipairs(stationsList) do
                local p=station(route,t)
                local y=profile(t,track.first,track.mid,track.last)
                local node=Vector3.new(p.X,y,p.Y)
                if prevPt then
                    local deck=(t>DECK_START and prevT<DECK_END)
                    local depth=deck and DECK_DEPTH or ROAD_DEPTH
                    local part=makePart(roadFolder,("Road_%+04d_%+04d"):format(prevT,t),prevPt,node,route.width,depth,route.tint,deck)
                    if part then
                        generated[#generated+1]=part
                        count+=1
                    end
                    local dxz=(Vector2.new(node.X,node.Z)-Vector2.new(prevPt.X,prevPt.Z)).Magnitude
                    if dxz>0.01 then
                        maxSlope=math.max(maxSlope,math.abs(node.Y-prevPt.Y)/dxz)
                    end
                end
                if math.abs(t)<=DECK_END then
                    for _,offset in ipairs({-route.width*0.45,0,route.width*0.45}) do
                        local q=p+edge*offset
                        local ground=terrainY(q.X,q.Y)
                        if ground and ground>y-DECK_DEPTH+0.25 then
                            terrainAbove+=1
                            worstTerrain=math.max(worstTerrain,ground-(y-DECK_DEPTH))
                        end
                    end
                end
                prevPt=node
                prevT=t
            end
            log("PROFILE","EXPERIMENTAL",string.format("%s tieStartY=%s proposedDeckTop=%s tieEndY=%s generated=%d maxSlopePct=%.2f assumedDepth=%.2f",route.name,fmt(track.first),fmt(track.mid),fmt(track.last),count,maxSlope*100,DECK_DEPTH))
        end
        if isolate then
            for _,part in ipairs(toMute) do mute(part) end
        end
    end)
    if not ok then
        restore()
        log("ROLLBACK","FAIL",tostring(err))
        return false
    end

    if world:FindFirstChild("KerlinGradeProfilePreview_TEMP") then
        log("VISUAL", "WARN", "Old noncolliding grade ghost is still present; clear it to avoid misleading overlap")
    end
    if isolate then
        for _,joint in ipairs(JOINTS) do
            local maxOld = nil
            for _,track in ipairs(tracks) do
                local oldY = raycastY(track.parts,joint.x,joint.z,false)
                if oldY then maxOld=math.max(maxOld or -math.huge,oldY) end
            end
            log("RESIDUAL_I95",maxOld and "WARN" or "PASS",
                joint.name.." original I-95 road raycast top="..fmt(maxOld).." (hidden test strips do not raycast)")
        end
    end
    log("BEGIN","PASS","Studio-only test pavement; collidable=true; altered Terrain/GIS/place=false")
    log("MODE",isolate and "LEGACY_ISOLATED" or "NONDESTRUCTIVE_OVERLAY",
        isolate and string.format("%d old I-95 road/marking Parts temporarily disabled (markings=%d); Clear restores them",#toMute,oldMarkings)
            or "Old I-95 ground-level pavement remains; underpass-driving validation not valid in this mode")
    log("SURVEY","UNVERIFIED","Deck ends +/-35 studs, physical depth 1.6 studs and projected registration are visual/design assumptions")
    log("TERRAIN",terrainAbove==0 and "PASS_SAMPLED" or "WARN",string.format("inside provisional deck: %d sampled footprint intrusions, max=%s studs; wheel-track sweep still required",terrainAbove,fmt(worstTerrain)))
    for _,joint in ipairs(JOINTS) do
        local underside=raycastY(generated,joint.x,joint.z,true)
        local kerlinTop=raycastY(lower,joint.x,joint.z,false)
        if underside and kerlinTop then
            local clearance=underside-kerlinTop
            log("OPENING",clearance>=REFERENCE_OPENING and "PROVISIONAL_PASS" or "WARN",
                string.format("%s new collidable undersideY=%s KerlinTopY=%s opening=%s studs provisionalTarget=%s; EXPERIMENTAL, not real bridge clearance",joint.name,fmt(underside),fmt(kerlinTop),fmt(clearance),fmt(REFERENCE_OPENING)))
        else
            log("OPENING","UNKNOWN",joint.name.." underside or Kerlin road raycast missing")
        end
    end
    log("END","PASS",string.format("Created %d collidable road sections; run Clear() to restore. TEST in Play only; do not save a permanent bridge from this result",#generated))
    return true
end

return Test
