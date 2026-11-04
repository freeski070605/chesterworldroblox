-- DEVELOPMENT TOOL - superseded for production by HighwayProfile.lua.
-- ChesterWorld | I-95 over Kerlin | Studio-only, reversible GRADE PROFILE VISUALIZATION.
-- This script does NOT change existing roadway, terrain, collisions, markings or Studio saves.
-- It displays NON-COLLIDING translucent pavement strips at a candidate profile inferred
-- solely from the live road surfaces ~120 studs either side of both crossing vertices.
-- The visual bridge footprint (±35 studs) is an AERIAL ESTIMATE, not a structural survey.
-- The physical underside, structure thickness and real clearance are UNKNOWN.
--
-- Run in a full Studio Play session, using SERVER Command Bar, after HighwayFinish:
-- require(game.ServerScriptService.Server.World.KerlinGradeProfilePreview).Run()
-- require(game.ServerScriptService.Server.World.KerlinGradeProfilePreview).Clear()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Preview = {}

local FOLDER_NAME = "KerlinGradeProfilePreview_TEMP"
local OWNED = "CW_KerlinGradeProfilePreviewOwned"
local CENTER_LEFT = -35  -- approximate visual deck face, in studs along I-95
local CENTER_RIGHT = 35
local TIE = 120            -- illustrative profile tie-ins, NOT approved ramp limits
local STEP = 6
local THICKNESS_VISUAL = 0.18
local ILLUSTRATIVE_DEPTH = 1.6 -- used ONLY for a what-if printout, never actual geometry
local PROVISIONAL_CLEARANCE = 12.878 -- 14ft 1in * nominal 3studs/m, NOT measured at these x/z

local ROUTES = {
    {
        label = "county:424/425", ids = {[424]=true,[425]=true},
        origin = Vector2.new(2015.268,25.443),
        direction = Vector2.new(7120.060-7019.645,-(7244.322-7193.492)).Unit,
        width = 75,
        color = Color3.fromRGB(53, 230, 220),
    },
    {
        label = "county:423/426", ids = {[423]=true,[426]=true},
        origin = Vector2.new(1990.695,-20.670),
        direction = Vector2.new(7270.559-7011.454,-(7343.750-7208.863)).Unit,
        width = 36,
        color = Color3.fromRGB(255, 185, 65),
    },
}
local LOWER_IDS = {[2758]=true,[27163]=true,[20771]=true,[20770]=true}

local function log(kind, status, msg)
    print(("KERLIN_PROFILE | %s | %s | %s"):format(kind,status,msg))
end
local function fmt(v)
    if v == nil then return "UNKNOWN" end
    return string.format("%.3f",v)
end
local function ready()
    if not RunService:IsStudio() or not RunService:IsServer() then
        log("READY","FAIL","Full Play, SERVER Command Bar required")
        return nil
    end
    if Workspace:GetAttribute("CW_QuickStreetPreview") == true then
        log("READY","FAIL","Full city Play required; quick preview is not sufficient")
        return nil
    end
    for _, name in ipairs({"CW_BootstrapComplete","CW_RoadConformComplete","CW_HighwayFinishComplete"}) do
        if Workspace:GetAttribute(name) ~= true then
            log("READY","FAIL",name.." must be true before Run()")
            return nil
        end
    end
    local world = Workspace:FindFirstChild("ChesterWorld")
    if not world or not world:FindFirstChild("tile_r07_c07") then
        log("READY","FAIL","Kerlin city tile not loaded")
        return nil
    end
    return world
end
local function ownedFolder(world)
    local folder = world:FindFirstChild(FOLDER_NAME)
    if folder and folder:GetAttribute(OWNED) ~= true then
        error("Refusing to touch unowned object "..folder:GetFullName())
    end
    return folder
end
local function groupId(part)
    return tonumber(tostring(part:GetAttribute("CW_GradeGroup") or ""):match("^county:(%d+):"))
end
local function collect(world, idTable)
    local matches = {}
    for _, tile in ipairs(world:GetChildren()) do
        if tile.Name:match("^tile_") then
            local roads = tile:FindFirstChild("Roads")
            if roads then
                for _, part in ipairs(roads:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanQuery and idTable[groupId(part)] then
                        table.insert(matches,part)
                    end
                end
            end
        end
    end
    return matches
end
local function roadY(parts,x,z)
    if #parts == 0 then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = parts
    params.IgnoreWater = false
    local hit = Workspace:Raycast(Vector3.new(x,3000,z), Vector3.new(0,-6000,0),params)
    return hit and hit.Position.Y or nil
end
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = {Workspace.Terrain}
terrainParams.IgnoreWater = false
local function terrainY(x,z)
    local hit = Workspace:Raycast(Vector3.new(x,3000,z),Vector3.new(0,-6000,0),terrainParams)
    return hit and hit.Position.Y or nil
end
local function position(route,t)
    return route.origin+route.direction*t
end
local function smooth(t)
    t = math.clamp(t,0,1)
    return t*t*(3-2*t)
end
local function candidate(t,startY,plateau,endY)
    if t < CENTER_LEFT then
        return startY+(plateau-startY)*smooth((t+TIE)/(TIE+CENTER_LEFT))
    end
    if t > CENTER_RIGHT then
        return plateau+(endY-plateau)*smooth((t-CENTER_RIGHT)/(TIE-CENTER_RIGHT))
    end
    return plateau
end
local function ghostPart(folder,name,a,b,width,color)
    local vector = b-a
    if vector.Magnitude <= 0.01 then return end
    local part=Instance.new("Part")
    part.Name=name
    part.Size=Vector3.new(width,THICKNESS_VISUAL,vector.Magnitude)
    part.CFrame=CFrame.lookAt((a+b)/2,b,Vector3.yAxis)
    part.Anchored=true
    part.CanCollide=false
    part.CanTouch=false
    part.CanQuery=false
    part.CastShadow=false
    part.Material=Enum.Material.Neon
    part.Color=color
    part.Transparency=0.62
    part.TopSurface=Enum.SurfaceType.Smooth
    part.BottomSurface=Enum.SurfaceType.Smooth
    part:SetAttribute("CW_VisualizationOnly",true)
    part.Parent=folder
end
local function marker(folder,name,point,y,color)
    local part=Instance.new("Part")
    part.Name=name
    part.Size=Vector3.new(2.5,2.5,2.5)
    part.Shape=Enum.PartType.Ball
    part.CFrame=CFrame.new(point.X,y,point.Y)
    part.Anchored=true
    part.CanCollide=false
    part.CanTouch=false
    part.CanQuery=false
    part.CastShadow=false
    part.Material=Enum.Material.Neon
    part.Color=color
    part.Parent=folder
end

function Preview.Clear()
    local world=ready()
    if not world then return false end
    local old=ownedFolder(world)
    if old then old:Destroy() end
    log("CLEAR","PASS","Removed only preview-owned visual parts. World geometry unchanged")
    return true
end

function Preview.Run(options)
    -- Production ownership: since 2026-11-04 HighwayProfile (TileBuilderV2)
    -- builds the I-95 / Kerlin crossing on every world build. Stacking this
    -- temporary geometry on top of it would create duplicate collision.
    if workspace:GetAttribute("CW_HighwayProfiledPieces") and workspace:GetAttribute("CW_HighwayProfiledPieces") > 0
        and not (type(options) == "table" and options.force == true) then
        warn("[Kerlin dev tool] HighwayProfile already owns this crossing; pass {force=true} to run anyway.")
        return nil
    end

    local world=ready()
    if not world then return false end
    local tracks={}
    local lowerParts=collect(world,LOWER_IDS)
    if #lowerParts == 0 then
        log("SOURCE","FAIL","Kerlin underpass road Parts missing")
        return false
    end
    for index,route in ipairs(ROUTES) do
        local parts=collect(world,route.ids)
        if #parts == 0 then
            log("SOURCE","FAIL",route.label.." missing")
            return false
        end
        local startPt=position(route,-TIE)
        local endPt=position(route,TIE)
        local startY=roadY(parts,startPt.X,startPt.Y)
        local endY=roadY(parts,endPt.X,endPt.Y)
        if not startY or not endY then
            log("TIE_IN","FAIL",route.label.." missing -120 or +120 road surface; no assumptions made")
            return false
        end
        local plateau=(startY+endY)/2
        tracks[index]={route=route,parts=parts,startY=startY,endY=endY,plateau=plateau}
    end

    local old=ownedFolder(world)
    if old then old:Destroy() end
    local folder=Instance.new("Folder")
    folder.Name=FOLDER_NAME
    folder:SetAttribute(OWNED,true)
    folder:SetAttribute("CW_VisualizationOnly",true)
    folder:SetAttribute("CW_PreviewCollision",false)
    folder.Parent=world
    log("BEGIN","PASS","Noncolliding, opt-in 2-carriageway profile. NO road, terrain, collision, or marking changes")
    log("MODEL","UNVERIFIED","Footprint ±35 studs and tie-ins ±120 studs are visual/illustrative; NO surveyed abutment, deck thickness or underside")
    log("REFERENCE","UNVERIFIED","14ft 1in => nominal 12.878 studs; coordinate registration and horizontal scale not independently verified")
    local plateauMin=math.huge
    for index,track in ipairs(tracks) do
        local route=track.route
        local prev=nil
        local minLift,maxLift=math.huge,-math.huge
        local holes=0
        local terrainConflicts=0
        local maxGroundConflict=-math.huge
        local candidateLowerHighest=nil
        for t=-TIE,TIE,STEP do
            local pt=position(route,t)
            local y=candidate(t,track.startY,track.plateau,track.endY)
            local current=roadY(track.parts,pt.X,pt.Y)
            local ground=terrainY(pt.X,pt.Y)
            local lower=roadY(lowerParts,pt.X,pt.Y)
            if not current then holes+=1 end
            if current then
                local lift=y-current
                minLift=math.min(minLift,lift)
                maxLift=math.max(maxLift,lift)
            end
            if ground and ground>y then
                terrainConflicts+=1
                maxGroundConflict=math.max(maxGroundConflict,ground-y)
            end
            if math.abs(t)<=CENTER_RIGHT and lower then
                candidateLowerHighest=math.max(candidateLowerHighest or -math.huge,lower)
            end
            local here=Vector3.new(pt.X,y,pt.Y)
            if prev then ghostPart(folder,("Carriageway%d_t%+d"):format(index,t),prev,here,route.width,route.color) end
            prev=here
        end
        for _,t in ipairs({-TIE,CENTER_LEFT,0,CENTER_RIGHT,TIE}) do
            local point=position(route,t)
            local y=candidate(t,track.startY,track.plateau,track.endY)
            marker(folder,("Track%d_t%+d"):format(index,t),point,y+1.4,route.color)
        end
        plateauMin=math.min(plateauMin,track.plateau)
        log("TRACK","ILLUSTRATIVE",string.format("%s partCount=%d width=%.1f startY=%s plateauY=%s endY=%s",
            route.label,#track.parts,route.width,fmt(track.startY),fmt(track.plateau),fmt(track.endY)))
        log("DELTA","MEASURED_VS_ILLUSTRATIVE",string.format("%s sampled current road misses=%d minimumLift=%s maximumLift=%s terrainAboveGhost=%d worstTerrainExcess=%s",
            route.label,holes,fmt(minLift==math.huge and nil or minLift),fmt(maxLift==-math.huge and nil or maxLift),terrainConflicts,
            fmt(maxGroundConflict==-math.huge and nil or maxGroundConflict)))
        if candidateLowerHighest then
            local whatIf=track.plateau-ILLUSTRATIVE_DEPTH-candidateLowerHighest
            log("OPENING","WHAT_IF_ONLY",string.format("%s lowerTopMax=%s proposedTop=%s assumedDepth=%.2f => modeledOpening=%s provisionalReference=%.3f; NOT measured clearance",
                route.label,fmt(candidateLowerHighest),fmt(track.plateau),ILLUSTRATIVE_DEPTH,fmt(whatIf),PROVISIONAL_CLEARANCE))
        else
            log("OPENING","UNKNOWN",route.label.." no lower road hit at sampled candidate centerline")
        end
    end
    log("END","PASS","Translucent ghost above existing road is NOT drivable; collisions disabled. Run Clear() to remove it")
    return true
end

return Preview
