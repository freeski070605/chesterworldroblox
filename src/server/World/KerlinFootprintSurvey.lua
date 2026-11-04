-- ChesterWorld | Kerlin/I-95 footprint survey, 2026-11-04
-- RESEARCH VISUALIZATION ONLY. No roadway, terrain, collision or place edits.
-- Full Play -> Server Command Bar:
-- require(game.ServerScriptService.Server.World.KerlinFootprintSurvey).Run()
-- require(game.ServerScriptService.Server.World.KerlinFootprintSurvey).Run({mode="ghost"})
-- require(game.ServerScriptService.Server.World.KerlinFootprintSurvey).Clear()

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Survey = {}

local TILE = "tile_r07_c07"
local FOLDER_NAME = "KerlinFootprintSurvey_TEMP"
local OWNER_ATTRIBUTE = "CW_KerlinFootprintSurveyOwned"
local CLEARANCE_REFERENCE = 12.878 -- 14 ft 1 in, converted at nominal 3 studs/m; PROVISIONAL
local ILLUSTRATIVE_DEPTH = 1.6 -- NOT measured. Only controls translucent ghost preview.
local BRIDGE_SOURCE = "DVRPC 2025 aerial, visual picks; NOT surveyed abutment faces"
local UPPER_IDS = { [423]=true, [424]=true, [425]=true, [426]=true }
local LOWER_IDS = { [2758]=true, [27163]=true, [20771]=true, [20770]=true }

-- Four user-picked corners, corrected order: A-left, A-right, B-right, B-left.
-- Coordinates derive from assumed NBI bridge pin -> Roblox anchor registration.
-- Verify alignment in Studio before using for any permanent mesh.
local P = {
    Vector2.new(1939.4802780665, -37.8303143063),
    Vector2.new(2005.5860456761, 61.3283371164),
    Vector2.new(2061.1749866262, 33.5338666414),
    Vector2.new(2007.8396513920, -70.8831981110),
}
local JOINTS = {
    {name="South source joint", x=1990.695, z=-20.670},
    {name="North source joint", x=2015.268, z=25.443},
}
local BRIDGE_MAP_PIN = Vector2.new(2029.925, 19.862)

local function log(label, status, message)
    print(("KERLIN_SURVEY | %s | %s | %s"):format(label, status, message))
end

local function ready()
    if not RunService:IsStudio() or not RunService:IsServer() then
        log("READY", "FAIL", "Run ONLY in Roblox Studio full Play / Server Command Bar")
        return nil
    end
    if Workspace:GetAttribute("CW_QuickStreetPreview") == true then
        log("READY", "FAIL", "QuickStreetPreview is not a full city load")
        return nil
    end
    for _, name in ipairs({"CW_BootstrapComplete", "CW_RoadConformComplete", "CW_HighwayFinishComplete"}) do
        if Workspace:GetAttribute(name) ~= true then
            log("READY", "FAIL", name .. " is not true; wait for finish")
            return nil
        end
    end
    local world = Workspace:FindFirstChild("ChesterWorld")
    if not world or not world:FindFirstChild(TILE) then
        log("READY", "FAIL", "ChesterWorld." .. TILE .. " not loaded")
        return nil
    end
    return world
end

local function idFor(part)
    return tonumber((tostring(part:GetAttribute("CW_GradeGroup") or "")):match("^county:(%d+):"))
end

local function collectRoads(world)
    local upper, lower = {}, {}
    for _, tile in ipairs(world:GetChildren()) do
        if tile.Name:match("^tile_") then
            local folder = tile:FindFirstChild("Roads")
            if folder then
                for _, part in ipairs(folder:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanQuery then
                        local id = idFor(part)
                        if UPPER_IDS[id] then table.insert(upper, part) end
                        if LOWER_IDS[id] then table.insert(lower, part) end
                    end
                end
            end
        end
    end
    return upper, lower
end

local function verticalY(parts, x, z)
    if #parts == 0 then return nil, nil end
    local prm = RaycastParams.new()
    prm.FilterType = Enum.RaycastFilterType.Include
    prm.FilterDescendantsInstances = parts
    prm.IgnoreWater = false
    local hit = Workspace:Raycast(Vector3.new(x, 5000, z), Vector3.new(0, -10000, 0), prm)
    return hit and hit.Position.Y or nil, hit and hit.Instance or nil
end

local terrainPrm = RaycastParams.new()
terrainPrm.FilterType = Enum.RaycastFilterType.Include
terrainPrm.FilterDescendantsInstances = { Workspace.Terrain }
terrainPrm.IgnoreWater = false
local function terrainY(x, z)
    local hit = Workspace:Raycast(Vector3.new(x, 5000, z), Vector3.new(0, -10000, 0), terrainPrm)
    return hit and hit.Position.Y or nil
end
local function fmt(x)
    return x and string.format("%.3f", x) or "UNKNOWN"
end
local function inXZ(a,b)
    return (a-b).Magnitude
end
local function mid(a,b)
    return (a+b)*0.5
end
local function length(a,b)
    return inXZ(a,b)
end

local function ownedFolder(world)
    local f = world:FindFirstChild(FOLDER_NAME)
    if not f then return nil end
    if f:GetAttribute(OWNER_ATTRIBUTE) ~= true then
        error("Refusing to touch unowned folder " .. f:GetFullName())
    end
    return f
end

function Survey.Clear()
    local world = ready()
    if not world then return false end
    local f = ownedFolder(world)
    if f then f:Destroy() end
    log("CLEAR", "PASS", "Removed only temporary survey-owned Instances; road geometry never changed")
    return true
end

local function createPart(folder, name, size, cf, color, transparency)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cf
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Neon
    part.Color = color
    part.Transparency = transparency or 0
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Parent = folder
    return part
end

local function guide(folder, name, a, b, radius, color, opacity)
    local diff = b - a
    if diff.Magnitude < 0.01 then return nil end
    return createPart(folder, name, Vector3.new(radius, radius, diff.Magnitude),
        CFrame.lookAt((a+b)*0.5, b), color, opacity)
end

local function marker(folder, label, x, y, z, color)
    local part = createPart(folder, label, Vector3.new(2.4, 2.4, 2.4),
        CFrame.new(x, y, z), color, 0.05)
    part.Shape = Enum.PartType.Ball
    local bb = Instance.new("BillboardGui")
    bb.Name = "SurveyLabel"
    bb.Adornee = part
    bb.AlwaysOnTop = true
    bb.Size = UDim2.fromOffset(235, 36)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
    bb.Parent = part
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0.1
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Text = label
    textLabel.Parent = bb
end

local function polyArea(corners)
    local sum = 0
    for i=1,#corners do
        local a, b = corners[i], corners[i % #corners + 1]
        sum += a.X*b.Y - b.X*a.Y
    end
    return math.abs(sum)*0.5
end

local function spanPointAcross(t, face)
    if face == "A" then return P[1]:Lerp(P[2], t) end
    return P[4]:Lerp(P[3], t)
end

local function sourceProfile(upper, tag, joint, direction)
    local values = {}
    for _, offset in ipairs({-240,-180,-120,-60,0,60,120,180,240}) do
        local pos = Vector2.new(joint.x, joint.z) + direction * offset
        local upperY = verticalY(upper, pos.X, pos.Y)
        table.insert(values, string.format("%+d:%s", offset, fmt(upperY)))
    end
    log("I95_PROFILE", "MEASURED_OR_UNKNOWN", tag .. " samples [offset studs:surfaceY] " .. table.concat(values," "))
end

function Survey.Run(options)
    options = options or {}
    local mode = options.mode or "outline"
    if mode ~= "outline" and mode ~= "ghost" then
        log("MODE", "FAIL", 'mode must be "outline" or "ghost"')
        return false
    end
    local world = ready()
    if not world then return false end
    local upper, lower = collectRoads(world)
    if #upper == 0 or #lower == 0 then
        log("SOURCE", "FAIL", ("Missing runtime parts upper=%d lower=%d; full tile load required"):format(#upper,#lower))
        return false
    end
    local old = ownedFolder(world)
    if old then old:Destroy() end
    local folder = Instance.new("Folder")
    folder.Name = FOLDER_NAME
    folder:SetAttribute(OWNER_ATTRIBUTE,true)
    folder:SetAttribute("CW_PreviewCollision",false)
    folder:SetAttribute("CW_FootprintSource",BRIDGE_SOURCE)
    folder.Parent = world

    local center = (P[1]+P[2]+P[3]+P[4])/4
    local aMid, bMid = mid(P[1],P[2]), mid(P[4],P[3])
    local along = bMid-aMid
    local alongUnit = along.Unit
    local width = (length(P[1],P[2])+length(P[4],P[3]))/2
    local span = (length(P[1],P[4])+length(P[2],P[3]))/2
    local upperCenter = verticalY(upper,center.X,center.Y)
    local lowerCenter = verticalY(lower,center.X,center.Y)
    local groundCenter = terrainY(center.X,center.Y)
    log("BEGIN","PASS","Runtime-only, reversible aerial footprint; NO terrain/road/collision edits")
    log("REFERENCE","UNVERIFIED",BRIDGE_SOURCE)
    log("FOOTPRINT","VISUAL_ESTIMATE",string.format("center X=%.3f Z=%.3f deckWidth=%.2f studs spanAlongI95=%.2f studs area=%.2f stud^2",center.X,center.Y,width,span,polyArea(P)))
    log("PARTS","MEASURED",string.format("I95=%d Kerlin=%d CanQuery road parts",#upper,#lower))
    log("CENTER","MEASURED_OR_UNKNOWN", "terrainY="..fmt(groundCenter).." I95surfaceY="..fmt(upperCenter).." KerlinSurfaceY="..fmt(lowerCenter))

    local lowerHighest = lowerCenter
    local maxUpper = upperCenter
    for _, j in ipairs(JOINTS) do
        local top, lowerPart = verticalY(lower,j.x,j.z)
        local road = verticalY(upper,j.x,j.z)
        local ground = terrainY(j.x,j.z)
        if top and (not lowerHighest or top > lowerHighest) then lowerHighest = top end
        if road and (not maxUpper or road > maxUpper) then maxUpper = road end
        log("JOINT","MEASURED_OR_UNKNOWN",string.format("%s X=%.3f Z=%.3f I95Y=%s KerlinY=%s terrainY=%s lowerPart=%s",j.name,j.x,j.z,fmt(road),fmt(top),fmt(ground),lowerPart and lowerPart:GetFullName() or "UNKNOWN"))
    end
    local centerToJoint = (Vector2.new((JOINTS[1].x+JOINTS[2].x)/2,(JOINTS[1].z+JOINTS[2].z)/2)-center).Magnitude
    log("REGISTRATION","CHECK",string.format("Aerial centroid vs midpoint of source vertices=%.3f studs; NOT independent georeferencing verification",centerToJoint))
    log("REFERENCE_PIN","UNVERIFIED",string.format("X=%.3f Z=%.3f; source pin registration assumed",BRIDGE_MAP_PIN.X,BRIDGE_MAP_PIN.Y))

    -- Neither the inventory clearance nor a notional depth is a measured deck height.
    local candidateUnderside = lowerHighest and lowerHighest + CLEARANCE_REFERENCE or nil
    local illustrativeDeckY = candidateUnderside and candidateUnderside + ILLUSTRATIVE_DEPTH or nil
    log("HEIGHT","UNKNOWN", "No surveyed underside or deck thickness. Provisional lowerHighest="..fmt(lowerHighest).." + 12.878 reference => underside>="..fmt(candidateUnderside))
    log("HEIGHT","UNVERIFIED", "Illustrative-only, not physical deck top = "..fmt(illustrativeDeckY).." (assumes arbitrary 1.6-stud depth)")

    local highestCornerTerrain = nil
    for i, corner in ipairs(P) do
        local ty = terrainY(corner.X, corner.Y)
        if ty and (not highestCornerTerrain or ty > highestCornerTerrain) then
            highestCornerTerrain = ty
        end
        log("CORNER_TERRAIN", "MEASURED_OR_UNKNOWN", ("corner=%d X=%.3f Z=%.3f terrainY=%s")
            :format(i, corner.X, corner.Y, fmt(ty)))
    end
    -- A survey outline should be visible even when existing terrain is higher
    -- than the as-yet-unbuilt freeway. Ghost mode keeps its theoretical Y,
    -- and explicitly warns when that puts the candidate inside terrain.
    local visualizationY = math.max(maxUpper or -1000, lowerHighest or -1000,
        groundCenter or -1000, highestCornerTerrain or -1000, 40) + 6
    if mode == "ghost" and illustrativeDeckY then
        visualizationY=illustrativeDeckY
        if highestCornerTerrain and illustrativeDeckY < highestCornerTerrain then
            log("GHOST_TERRAIN", "WARN", ("illustrativeY=%.3f below highest surveyed corner terrainY=%.3f; geometry cannot yet be approved")
                :format(illustrativeDeckY,highestCornerTerrain))
        end
    end
    local cyan=Color3.fromRGB(65,231,231)
    local yellow=Color3.fromRGB(255,211,72)
    local orange=Color3.fromRGB(255,129,72)
    for i=1,4 do
        local a,b=P[i],P[i%4+1]
        guide(folder,"VISUAL_FOOTPRINT_EDGE_"..i,
            Vector3.new(a.X,visualizationY,a.Y),Vector3.new(b.X,visualizationY,b.Y),0.8,cyan,0.05)
        marker(folder,"AERIAL_ESTIMATE_CORNER_"..i,a.X,visualizationY,a.Y,cyan)
    end
    guide(folder,"I95_SPAN_AXIS",Vector3.new(aMid.X,visualizationY,aMid.Y),
        Vector3.new(bMid.X,visualizationY,bMid.Y),1.0,orange,0.05)
    for _, j in ipairs(JOINTS) do
        local y=verticalY(lower,j.x,j.z) or visualizationY
        marker(folder,"SOURCE_"..j.name,j.x,y+3,j.z,yellow)
    end
    marker(folder,"INVENTORY_PIN_APPROX",BRIDGE_MAP_PIN.X,visualizationY,BRIDGE_MAP_PIN.Y,orange)

    -- Translucent, fully noncolliding suggestion of a deck. NOT a bridge.
    -- Each strip spans the user's visually estimated A and B faces.
    if mode == "ghost" and illustrativeDeckY then
        local count=12
        for i=1,count do
            local t=(i-0.5)/count
            local a=spanPointAcross(t,"A")
            local b=spanPointAcross(t,"B")
            local widthHere=width/count+0.12
            local delta=b-a
            createPart(folder,"NONCOLLIDING_GHOST_STRIP_"..i,
                Vector3.new(widthHere,0.20,delta.Magnitude),
                CFrame.lookAt(Vector3.new((a.X+b.X)/2,visualizationY,(a.Y+b.Y)/2),
                    Vector3.new(b.X,visualizationY,b.Y)),cyan,0.78)
        end
        log("GHOST","PASS","Only 12 translucent CanCollide=false, CanQuery=false strips created at ILLUSTRATIVE Y; not drivable")
    elseif mode == "ghost" then
        log("GHOST","UNKNOWN","No measured Kerlin road surface; skipping illustrative deck")
    end

    -- Two source carriageways, directions measured from the tile's existing road records.
    -- Never use shared crossing vertices as assumed abutments.
    local dirA=Vector2.new(7120.060-7019.645,-(7244.322-7193.492)).Unit
    local dirB=Vector2.new(7270.559-7011.454,-(7343.750-7208.863)).Unit
    sourceProfile(upper,"county:424/425",JOINTS[2],dirA)
    sourceProfile(upper,"county:423/426",JOINTS[1],dirB)
    log("END","PASS","Survey visual ONLY. Clear with require(...KerlinFootprintSurvey).Clear(). All existing road geometry unchanged.")
    return true
end

return Survey
