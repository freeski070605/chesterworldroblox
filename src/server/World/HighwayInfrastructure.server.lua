-- ChesterWorld I-95 bridge structure and underpass clearance audit.
-- Runs AFTER the grade-aware RoadTerrainConformer.
-- Adds physical decks/parapets/supports and clears terrain above highway
-- pavement that runs in a cut; never edits junctions.

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
    -- Source roads split AT crossings, so accept touching ends; reject
    -- shallow angles (continuations of the same road).
    local e=1e-4
    if t>=-e and t<=1+e and u>=-e and u<=1+e then
        local sine=math.abs(det)/math.max(math.sqrt(rx*rx+rz*rz)*math.sqrt(sx*sx+sz*sz),1e-6)
        if sine>0.26 then
            return math.clamp(t,0,1),math.clamp(u,0,1)
        end
    end
    return nil
end

local bridge, lower, ramps, unprofiledBridges, gradeLimited = {}, {}, {}, {}, {}
local profiled = {}
for _, tile in ipairs(world:GetChildren()) do
    local roads=tile:FindFirstChild("Roads")
    if roads then
        for _, part in ipairs(roads:GetDescendants()) do
            -- steel rail strips (TileBuilderV2 buildRailTrack) are decoration on
            -- the ballast bed, not roads: keep them out of the structure audit
            if part:IsA("BasePart") and not (part.Name=="Rail" and part:GetAttribute("CW_Rail")) then
                local level=tonumber(part:GetAttribute("CW_GradeLevel")) or 0
                if part:GetAttribute("CW_HighwayProfiled") == true then
                    -- Generator-owned highway pavement (HighwayProfile). It is
                    -- a lower road for local overpasses as well.
                    table.insert(profiled,part)
                    if part:GetAttribute("CW_HighwayStructure") ~= "span" then
                        table.insert(lower,part)
                    end
                elseif part:GetAttribute("CW_BridgeProfiled") == true then
                    table.insert(bridge,part)
                    if part:GetAttribute("CW_GradeLimited") == true then
                        table.insert(gradeLimited,part)
                    end
                elseif part:GetAttribute("CW_RampProfiled") == true then
                    table.insert(ramps,part)
                elseif (part:GetAttribute("CW_Bridge")==true or level>0)
                    and not part:GetAttribute("CW_LowerRoadUnderStructure") then
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
local lowerRoadOverlap=OverlapParams.new()
lowerRoadOverlap.FilterType=Enum.RaycastFilterType.Include
lowerRoadOverlap.FilterDescendantsInstances=lower
local blockedSupports=0
local function supportCrossesLowerRoad(frame,size,carrier)
    for _,road in ipairs(Workspace:GetPartBoundsInBox(frame,size,lowerRoadOverlap)) do
        if road~=carrier and road:IsA("BasePart") and road.CanCollide
            and road:GetAttribute("CW_Rail")~=true
            and road.Position.Y+road.Size.Y/2<carrier.Position.Y-carrier.Size.Y/2-0.5 then
            return true
        end
    end
    return false
end
local buildingFolders={}
for _,tile in ipairs(world:GetChildren()) do
    local buildings=tile:FindFirstChild("Buildings")
    if buildings then table.insert(buildingFolders,buildings) end
end
local buildingParams=OverlapParams.new()
buildingParams.FilterType=Enum.RaycastFilterType.Include
buildingParams.FilterDescendantsInstances=buildingFolders
buildingParams.MaxParts=1

-- Profiled rail beds (RailProfile; built by TileBuilderV2 before this runs):
-- no abutment wall, fill block or pier may stand on the tracks. The Barry
-- carriageways over the NEC put a 77-stud abutment across all four tracks.
local railBeds={}
for _,tile in ipairs(world:GetChildren()) do
    local roads=tile:FindFirstChild("Roads")
    if roads then
        for _,p in ipairs(roads:GetChildren()) do
            if p:IsA("BasePart") and p:GetAttribute("CW_Rail")==true and p.Name~="Rail" then
                table.insert(railBeds,p)
            end
        end
    end
end
local railParams=OverlapParams.new()
railParams.FilterType=Enum.RaycastFilterType.Include
railParams.FilterDescendantsInstances=railBeds
railParams.MaxParts=1
local function onRail(frame,size)
    if #railBeds==0 then return false end
    -- footprint extended down to reach a bed under a tall wall / fill
    return #Workspace:GetPartBoundsInBox(frame,size+Vector3.new(0,8,0),railParams)>0
end

local function canPier(point,height,carrier)
    if height<9 then return false end
    if onRail(CFrame.new(point.X,point.Y-height/2,point.Z),Vector3.new(4,height,4)) then return false end
    if carrier and supportCrossesLowerRoad(CFrame.new(point.X,point.Y-height/2,point.Z),
        Vector3.new(4,height,4),carrier) then
        blockedSupports+=1
        return false
    end
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
for _,part in ipairs(bridge) do
    -- Do not decorate a structurally unresolved grade with fake piers and
    -- parapets. It remains in the road audit and in-game road geometry.
    if part:GetAttribute("CW_GradeLimited") ~= true then
        table.insert(visuallyRaised,part)
    end
end
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
                    if height>9 and canPier(top,height,road) then
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

-- ===========================================================================
-- Generator-owned highway structures (HighwayProfile classification)
-- ===========================================================================
-- Every profiled pavement piece carries CW_HighwayStructure:
--   "span"  : open structure. Deck, fascia girders, parapets; abutments at
--             the structure ends; pier bents on long spans (never on a road).
--   "fill"  : pavement above the bare-earth DEM with nothing below it.
--             A collidable retaining fill closes the void; barriers if high.
--   "grade" : at-grade pavement; nothing added.
-- Basis/provenance of each span is copied to its parts (CW_StructureBasis).
local hwFolder=Instance.new("Folder")
hwFolder.Name="HighwayStructures"
hwFolder.Parent=folder
local STRUCT_COLOR=Config.HIGHWAY_STRUCTURE_COLOR or SUPPORT_COLOR
local BARRIER_COLOR=Config.HIGHWAY_BARRIER_COLOR or COLOR
local BARRIER_HEIGHT=Config.HIGHWAY_BARRIER_HEIGHT_STUDS or RAIL_HEIGHT
local BARRIER_MIN_FILL=Config.HIGHWAY_BARRIER_MIN_FILL_STUDS or 4
local PIER_SPACING=Config.HIGHWAY_PIER_MAX_SPACING_STUDS or 95
local OVERPASS_FENCE_HEIGHT=Config.HIGHWAY_OVERPASS_FENCE_HEIGHT_STUDS or 7
local RETAINING_WALL_BASES={["registry:KERLIN_I95"]=true}
local STEEL_GIRDER_BASES={["registry:I95_OVER_BULLENS"]=true,["registry:I95_OVER_COMM_BARRY_RAMP"]=true}
local LOCAL_OVERPASS_BASES={
    ["registry:BULLENS_OVER_I476"]=true, ["registry:EDGMONT_OVER_I95"]=true,
    ["registry:MADISON_OVER_I95"]=true, ["registry:UPLAND_OVER_I95"]=true,
    ["registry:POTTER_OVER_I95"]=true, ["registry:CHESTNUT_OVER_I95"]=true,
    ["registry:MELROSE_OVER_I95"]=true, ["registry:HIGHLAND_OVER_I95"]=true,
    ["registry:ENGLE_OVER_I95"]=true, ["registry:CROSBY_FOOTBRIDGE_OVER_I95"]=true,
}
local hw={decks=0,girders=0,barriers=0,abutments=0,piers=0,fills=0,fences=0,retainingWalls=0,
    spans=0,spanPieces=0,fillPieces=0,gradePieces=0}
local pavedOverlap=OverlapParams.new()
pavedOverlap.FilterType=Enum.RaycastFilterType.Include
local pavedRoads={}
for _,road in ipairs(profiled) do table.insert(pavedRoads,road) end
for _,road in ipairs(lower) do table.insert(pavedRoads,road) end
pavedOverlap.FilterDescendantsInstances=pavedRoads

local function minTerrainUnder(part,lateral)
    local a,b=endpoints(part)
    local right=part.CFrame.RightVector
    local low=math.huge
    for _,t in ipairs({0,0.5,1}) do
        local p=a:Lerp(b,t)
        for _,side in ipairs({-1,0,1}) do
            local q=p+right*side*lateral
            local y=terrainY(q.X,q.Z)
            if y and y<low then low=y end
        end
    end
    return low<math.huge and low or nil
end

local function barrierPair(road,parent,attrs)
    -- Jersey-profile concrete barrier: wide base + narrower upper wall.
    for _,side in ipairs({-1,1}) do
        local edge=side*(road.Size.X/2-0.7)
        local baseFrame=road.CFrame*CFrame.new(edge,road.Size.Y/2+0.55,0)
        local blockedByMerge=false
        for _,other in ipairs(Workspace:GetPartBoundsInBox(baseFrame,
            Vector3.new(1.6,1.5,road.Size.Z),pavedOverlap)) do
            if other~=road and other.CanCollide
                and other:GetAttribute("CW_StrokeId")~=road:GetAttribute("CW_StrokeId")
                and math.abs((other.Position.Y+other.Size.Y/2)-(road.Position.Y+road.Size.Y/2))<2.5 then
                -- Adjacent pavement segments on the same stroke overlap at
                -- their joints; that is not a ramp merge. Also ignore
                -- parallel neighboring carriageways: only a genuinely
                -- angled, different-stroke road can open this barrier edge.
                local alignment=math.abs(other.CFrame.LookVector:Dot(road.CFrame.LookVector))
                if alignment<0.97 then
                    blockedByMerge=true
                    break
                end
            end
        end
        if blockedByMerge then
            hw.barriersAtMergesSkipped=(hw.barriersAtMergesSkipped or 0)+1
            continue
        end
        local base=partAt(parent,"HighwayBarrier",
            Vector3.new(1.4,1.1,road.Size.Z),
            baseFrame,BARRIER_COLOR,true)
        local wall=partAt(parent,"HighwayBarrier",
            Vector3.new(0.75,BARRIER_HEIGHT-1.1,road.Size.Z),
            road.CFrame*CFrame.new(edge+side*0.15,road.Size.Y/2+1.1+(BARRIER_HEIGHT-1.1)/2,0),
            BARRIER_COLOR,true)
        for key,value in pairs(attrs) do
            base:SetAttribute(key,value)
            wall:SetAttribute(key,value)
        end
        hw.barriers+=1
    end
end

local structures={}
for index,road in ipairs(profiled) do
    local kind=road:GetAttribute("CW_HighwayStructure")
    local attrs={
        CW_StructureId=tostring(road:GetAttribute("CW_StructureId") or ""),
        CW_StructureBasis=tostring(road:GetAttribute("CW_StructureBasis") or ""),
        CW_StrokeId=tostring(road:GetAttribute("CW_StrokeId") or ""),
        CW_SourceRoad=road.Name,
    }
    if kind=="span" then
        hw.spanPieces+=1
        local id=attrs.CW_StructureId
        local entry=structures[id]
        if not entry then
            entry={pieces={},basis=attrs.CW_StructureBasis}
            structures[id]=entry
            hw.spans+=1
        end
        table.insert(entry.pieces,road)
        local length,width=road.Size.Z,road.Size.X
        local deck=partAt(hwFolder,"HighwayDeck",
            Vector3.new(width+1.2,DECK_THICKNESS,length),
            road.CFrame*CFrame.new(0,-(road.Size.Y+DECK_THICKNESS)/2-0.02,0),
            STRUCT_COLOR,true)
        hw.decks+=1
        for _,side in ipairs({-1,1}) do
            local girder=partAt(hwFolder,"HighwayFascia",
                Vector3.new(0.9,2.6,length),
                road.CFrame*CFrame.new(side*(width/2+0.15),
                    -road.Size.Y/2-DECK_THICKNESS-1.3+0.6,0),
                STRUCT_COLOR,false)
            girder:SetAttribute("CW_StructureId",id)
            if STEEL_GIRDER_BASES[attrs.CW_StructureBasis] then
                -- weathered steel plate girders in the Street View captures
                girder.Material=Enum.Material.CorrodedMetal
                girder.Color=Color3.fromRGB(122,78,56)
                girder.Size=Vector3.new(0.9,3.4,length)
            end
            hw.girders+=1
        end
        for key,value in pairs(attrs) do deck:SetAttribute(key,value) end
        barrierPair(road,hwFolder,attrs)
        -- Local streets over I-95 / I-476 carry tall protective fencing on the
        -- parapet (KartaView 2017-2022 + Google Street View 2024-2026 at every
        -- *_OVER_I95 / BULLENS_OVER_I476 entry: Data\HighwayReference\imagery).
        local basis=attrs.CW_StructureBasis
        -- Only local streets: highway flyovers (N476_FLYOVER_OVER_I95 ...) carry
        -- Jersey barriers, not fencing (audit 2026-11-06). The city-street
        -- overpasses over I-95 are road-tile bridges, fenced in the finish pass.
        if OVERPASS_FENCE_HEIGHT>0 and LOCAL_OVERPASS_BASES[basis] then
            for _,side in ipairs({-1,1}) do
                local fence=partAt(hwFolder,"HighwayOverpassFence",
                    Vector3.new(0.2,OVERPASS_FENCE_HEIGHT,road.Size.Z),
                    road.CFrame*CFrame.new(side*(road.Size.X/2-0.55),
                        road.Size.Y/2+BARRIER_HEIGHT+OVERPASS_FENCE_HEIGHT/2,0),
                    Color3.fromRGB(122,128,126),true)
                fence.Material=Enum.Material.DiamondPlate
                fence.Transparency=0.6
                for key,value in pairs(attrs) do fence:SetAttribute(key,value) end
                fence:SetAttribute("CW_Evidence","KartaView street frames (HighwayReference/imagery)")
                hw.fences+=1
            end
        end
    elseif kind=="fill" then
        hw.fillPieces+=1
        local bottom=minTerrainUnder(road,road.Size.X/2)
        if bottom then
            local roadBottom=road.Position.Y-road.Size.Y/2
            local height=roadBottom-bottom+1.0
            if height>0.6 then
                local slopeDrop=math.abs(road.CFrame.LookVector.Y)*road.Size.Z/2
                height+=slopeDrop
                local fillSize=Vector3.new(road.Size.X+1.0,height,road.Size.Z)
                local fillFrame=road.CFrame*CFrame.new(0,-road.Size.Y/2-height/2-0.01,0)
                local railBelow=onRail(fillFrame,fillSize)
                local streetBelow=supportCrossesLowerRoad(fillFrame,fillSize,road)
                if railBelow or streetBelow then
                    -- A track or lower street runs under here: leave an open deck.
                    local deck=partAt(hwFolder,"HighwayDeck",
                        Vector3.new(road.Size.X+1.0,DECK_THICKNESS,road.Size.Z),
                        road.CFrame*CFrame.new(0,-road.Size.Y/2-DECK_THICKNESS/2-0.01,0),
                        STRUCT_COLOR,true)
                    for key,value in pairs(attrs) do deck:SetAttribute(key,value) end
                    if railBelow then hw.fillsOverRail=(hw.fillsOverRail or 0)+1 end
                    if streetBelow then hw.fillsOverRoad=(hw.fillsOverRoad or 0)+1 end
                    barrierPair(road,hwFolder,attrs)
                else
                    local block=partAt(hwFolder,"HighwayFill",fillSize,fillFrame,STRUCT_COLOR,true)
                    block.Material=height>6 and Enum.Material.Concrete or Enum.Material.Ground
                    if height<=6 then block.Color=Color3.fromRGB(96,104,74) end
                    for key,value in pairs(attrs) do block:SetAttribute(key,value) end
                    block:SetAttribute("CW_FillHeightStuds",height)
                    hw.fills+=1
                    if height>BARRIER_MIN_FILL then
                        barrierPair(road,hwFolder,attrs)
                    end
                end
            end
        end
    else
        hw.gradePieces+=1
    end
    if index%40==0 then task.wait() end
end

-- Highway cuts. Where profiled pavement runs below the terrain (a depressed
-- section under local overpasses; the bare-earth DEM often has no notch for
-- the real cut) the terrain above the roadway is cleared and deep cuts are
-- lined with concrete retaining walls. Never under spans. A wall is skipped
-- where other profiled pavement (a ramp at a gore) occupies its line.
local CUT_SHOULDER=Config.HIGHWAY_CUT_SHOULDER_STUDS or 4
local CUT_MAX_DEPTH=Config.HIGHWAY_CUT_MAX_DEPTH_STUDS or 32
local CUT_WALL_MIN=Config.HIGHWAY_CUT_WALL_MIN_STUDS or 3
local cut={pieces=0,walls=0,deepest=0,capped=0,deepX=0,deepZ=0}
local paveGrid={}
for _,road in ipairs(profiled) do
    local key=math.floor(road.Position.X/CELL)..":"..math.floor(road.Position.Z/CELL)
    paveGrid[key]=paveGrid[key] or {}
    table.insert(paveGrid[key],road)
end
local function otherPavementAt(point,self)
    local gx,gz=math.floor(point.X/CELL),math.floor(point.Z/CELL)
    for ix=gx-1,gx+1 do
        for iz=gz-1,gz+1 do
            for _,other in ipairs(paveGrid[ix..":"..iz] or {}) do
                if other~=self and math.abs(other.Position.Y-point.Y)<6
                    and roadSegmentDistanceXZ(point,other)<other.Size.X/2+0.5 then
                    return true
                end
            end
        end
    end
    return false
end
for index,road in ipairs(profiled) do
    if road:GetAttribute("CW_HighwayStructure")~="span" then
        local a,b=endpoints(road)
        local right=road.CFrame.RightVector
        local half=road.Size.X/2+CUT_SHOULDER
        local over=0
        for _,t in ipairs({0,0.5,1}) do
            local p=a:Lerp(b,t)
            for _,side in ipairs({-1,-0.5,0,0.5,1}) do
                local q=p+right*side*half
                local y=terrainY(q.X,q.Z)
                if y and y-(p.Y+road.Size.Y/2)>over then
                    over=y-(p.Y+road.Size.Y/2)
                end
            end
        end
        if over>0.3 then
            local depth=math.min(over,CUT_MAX_DEPTH)
            if over>CUT_MAX_DEPTH then cut.capped+=1 end
            local height=depth+6
            -- from just below the pavement top to above the terrain
            local base=road.Size.Y/2-0.4
            Terrain:FillBlock(road.CFrame*CFrame.new(0,base+height/2,0),
                Vector3.new(half*2,height,road.Size.Z+2),Enum.Material.Air)
            road:SetAttribute("CW_HighwayCutDepth",over)
            cut.pieces+=1
            if over>cut.deepest then
                cut.deepest,cut.deepX,cut.deepZ=over,road.Position.X,road.Position.Z
            end
            if depth>CUT_WALL_MIN then
                for _,side in ipairs({-1,1}) do
                    local offset=side*(half+0.6)
                    local probe=road.Position+right*offset+Vector3.new(0,road.Size.Y/2,0)
                    if not otherPavementAt(probe,road) then
                        local wall=partAt(hwFolder,"HighwayCutWall",
                            Vector3.new(1.2,depth+1,road.Size.Z+0.4),
                            road.CFrame*CFrame.new(offset,road.Size.Y/2+(depth+1)/2-0.5,0),
                            STRUCT_COLOR,true)
                        wall.Material=Enum.Material.Concrete
                        wall:SetAttribute("CW_StrokeId",tostring(road:GetAttribute("CW_StrokeId") or ""))
                        cut.walls+=1
                    end
                end
            end
        end
    end
    if index%40==0 then task.wait() end
end
print(("[ChesterWorld HighwayCuts] pieces=%d walls=%d deepest=%.1f at (%.1f, %.1f) cappedAt%d=%d")
    :format(cut.pieces,cut.walls,cut.deepest,cut.deepX,cut.deepZ,CUT_MAX_DEPTH,cut.capped))

local spanParams=OverlapParams.new()
spanParams.FilterType=Enum.RaycastFilterType.Include
spanParams.FilterDescendantsInstances=profiled
-- Abutments at the two ends of every span structure, and pier bents inside
-- long spans. Ends are the pieces with the lowest / highest stroke station.
for id,entry in pairs(structures) do
    table.sort(entry.pieces,function(p,q)
        return (p:GetAttribute("CW_Station0") or 0)<(q:GetAttribute("CW_Station0") or 0)
    end)
    local first,last=entry.pieces[1],entry.pieces[#entry.pieces]
    local s0=first:GetAttribute("CW_Station0") or 0
    local s1=last:GetAttribute("CW_Station1") or 0
    -- Abutment wall across the deck at a structure end point `p`.
    local function abutment(piece,p,other)
        local a,b=endpoints(piece)
        local flat=Vector3.new(b.X-a.X,0,b.Z-a.Z)
        if flat.Magnitude<0.01 then return end
        flat=flat.Unit
        local ground=terrainY(p.X,p.Z)
        if not ground then return end
        local top=p.Y-piece.Size.Y/2-DECK_THICKNESS-0.02
        local height=top-ground+1.5
        if height<1.5 then return end
        -- push the wall 1.5 studs OUTSIDE the span so it never sits in the opening
        local outward=Vector3.new(p.X-other.X,0,p.Z-other.Z)
        outward=outward.Magnitude>0.01 and outward.Unit or flat
        local c=Vector3.new(p.X,top-height/2,p.Z)+outward*1.5
        -- the deck carries on as ANOTHER structure here (a ramp's span ending
        -- where it merges into the I-95 / I-476 bridge): no wall in mid-span
        for _,q in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(p.X,p.Y,p.Z)+outward*4,
            Vector3.new(6,piece.Size.Y+4,6),spanParams)) do
            if q~=piece and q:GetAttribute("CW_HighwayStructure")=="span"
                and tostring(q:GetAttribute("CW_StructureId") or "")~=id then
                hw.abutmentsMidSpan=(hw.abutmentsMidSpan or 0)+1
                return
            end
        end
        local wallFrame=CFrame.lookAt(c,c+flat)
        local wallSize=Vector3.new(piece.Size.X+2.0,height,3.0)
        if onRail(wallFrame,wallSize) then
            hw.abutmentsOnRail=(hw.abutmentsOnRail or 0)+1
            return
        end
        if supportCrossesLowerRoad(wallFrame,wallSize,piece) then
            hw.abutmentsOnRoad=(hw.abutmentsOnRoad or 0)+1
            blockedSupports+=1
            return
        end
        local wall=partAt(hwFolder,"HighwayAbutment",
            wallSize,wallFrame,STRUCT_COLOR,true)
        wall:SetAttribute("CW_StructureId",id)
        wall:SetAttribute("CW_StructureBasis",entry.basis)
        hw.abutments+=1
        if RETAINING_WALL_BASES[entry.basis] then
            -- long concrete retaining walls continue along the street below
            -- (Kerlin St approaches, Street View 2025): stepped wing walls
            local along=CFrame.lookAt(c,c+flat).RightVector
            for _,side in ipairs({-1,1}) do
                for k,frac in ipairs({1.0,0.75,0.5}) do
                    local seg=24
                    local centre=c+along*side*((piece.Size.X+2.0)/2+seg*(k-0.5))
                    local g=terrainY(centre.X,centre.Z)
                    if g then
                        local wTop=ground+(top-ground)*frac
                        local h=wTop-(g-1.5)
                        if h>2 then
                            local wing=partAt(hwFolder,"HighwayRetainingWall",Vector3.new(seg,h,2.4),
                                CFrame.lookAt(Vector3.new(centre.X,wTop-h/2,centre.Z),
                                    Vector3.new(centre.X,wTop-h/2,centre.Z)+flat),STRUCT_COLOR,true)
                            wing:SetAttribute("CW_StructureBasis",entry.basis)
                            hw.retainingWalls+=1
                        end
                    end
                end
            end
        end
    end
    local function farEnd(piece,fromPiece)
        local a,b=endpoints(piece)
        local ref=fromPiece.Position
        return (distXZ(a,ref)>distXZ(b,ref)) and a or b
    end
    if first==last then
        local a,b=endpoints(first)
        abutment(first,a,b)
        abutment(first,b,a)
    else
        local startPoint=farEnd(first,last)
        local endPoint=farEnd(last,first)
        abutment(first,startPoint,endPoint)
        abutment(last,endPoint,startPoint)
    end
    local total=s1-s0
    if total>PIER_SPACING*1.15 then
        local bents=math.floor(total/PIER_SPACING)
        for k=1,bents do
            local target=s0+total*k/(bents+1)
            for _,piece in ipairs(entry.pieces) do
                local p0=piece:GetAttribute("CW_Station0") or 0
                local p1=piece:GetAttribute("CW_Station1") or 0
                if target>=p0 and target<=p1 then
                    local center=piece.Position
                    local right=piece.CFrame.RightVector
                    local columns=piece.Size.X>40 and 3 or 2
                    for c=1,columns do
                        local offset=(c-(columns+1)/2)*(piece.Size.X*0.7/math.max(columns-1,1))
                        local top=center+right*offset-Vector3.new(0,piece.Size.Y/2+DECK_THICKNESS,0)
                        local below=terrainY(top.X,top.Z)
                        if below then
                            local height=top.Y-below
                            if canPier(top,height,piece) then
                                local col=partAt(hwFolder,"HighwayPier",
                                    Vector3.new(3.2,height,3.2),
                                    CFrame.new(top.X,below+height/2,top.Z),
                                    STRUCT_COLOR,true)
                                col:SetAttribute("CW_StructureId",id)
                                hw.piers+=1
                            end
                        end
                    end
                    break
                end
            end
        end
    end
end

-- Continuity audit: every stroke must be covered by pavement from station 0
-- to its end, except where an intersection pad legitimately covers a gap.
local byStroke={}
for _,road in ipairs(profiled) do
    local id=road:GetAttribute("CW_StrokeId")
    if id then
        byStroke[id]=byStroke[id] or {}
        table.insert(byStroke[id],road)
    end
end
local padParams=RaycastParams.new()
padParams.FilterType=Enum.RaycastFilterType.Include
local surfaceFolders={}
for _,tile in ipairs(world:GetChildren()) do
    for _,name in ipairs({"Roads","Intersections"}) do
        local f=tile:FindFirstChild(name)
        if f then table.insert(surfaceFolders,f) end
    end
end
padParams.FilterDescendantsInstances=surfaceFolders
local holes,coveredGaps,steps,worstStep=0,0,0,0
local holeList={}
for id,list in pairs(byStroke) do
    table.sort(list,function(p,q)
        return (p:GetAttribute("CW_Station0") or 0)<(q:GetAttribute("CW_Station0") or 0)
    end)
    for i=2,#list do
        local prev,cur=list[i-1],list[i]
        local gap=(cur:GetAttribute("CW_Station0") or 0)-(prev:GetAttribute("CW_Station1") or 0)
        local pa,pb=endpoints(prev)
        local ca,cb=endpoints(cur)
        -- nearest pair of ends between the two pieces
        local best,bp,bc=math.huge,nil,nil
        for _,x in ipairs({pa,pb}) do
            for _,y in ipairs({ca,cb}) do
                local d=distXZ(x,y)
                if d<best then best,bp,bc=d,x,y end
            end
        end
        if gap>1.0 and bp then
            local mid=(bp+bc)/2
            local hit=Workspace:Raycast(Vector3.new(mid.X,mid.Y+40,mid.Z),
                Vector3.new(0,-80,0),padParams)
            if hit then
                coveredGaps+=1
            else
                holes+=1
                if #holeList<20 then
                    table.insert(holeList,string.format("%s %s gap=%.1f at (%.1f, %.1f)",
                        id,prev.Name,gap,mid.X,mid.Z))
                end
            end
        elseif bp and best<2.0 then
            local step=math.abs(bp.Y-bc.Y)
            if step>0.35 then
                steps+=1
                worstStep=math.max(worstStep,step)
            end
        end
    end
end
Workspace:SetAttribute("CW_HighwayHoles",holes)
Workspace:SetAttribute("CW_HighwaySpans",hw.spans)
print(("[ChesterWorld HighwayStructures] profiledParts=%d spans=%d spanPieces=%d fillPieces=%d gradePieces=%d decks=%d fascia=%d barriers=%d abutments=%d piers=%d fills=%d overpassFences=%d holes=%d padCoveredGaps=%d steps=%d worstStep=%.2f")
    :format(#profiled,hw.spans,hw.spanPieces,hw.fillPieces,hw.gradePieces,hw.decks,
    hw.girders,hw.barriers,hw.abutments,hw.piers,hw.fills,hw.fences,holes,coveredGaps,steps,worstStep))
print(("[ChesterWorld HighwayStructures] railBeds=%d abutmentsOnRailSkipped=%d abutmentsOnRoadSkipped=%d supportsOnRoadSkipped=%d fillsOverRailAsDeck=%d fillsOverRoadAsDeck=%d barriersAtMergesSkipped=%d abutmentsMidSpanSkipped=%d")
    :format(#railBeds,hw.abutmentsOnRail or 0,hw.abutmentsOnRoad or 0,blockedSupports,
        hw.fillsOverRail or 0,hw.fillsOverRoad or 0,hw.barriersAtMergesSkipped or 0,
        hw.abutmentsMidSpan or 0))
for _,line in ipairs(holeList) do
    warn("[ChesterWorld HighwayHole] "..line)
end

-- Report the ACTUAL vertical clearance between every road pair with crossing
-- centerlines on different levels. Do not infer safety from bridge count.
local crossings,tooLow,minClearance=0,0,math.huge
local minRequired=Config.HIGHWAY_MIN_CLEARANCE_STUDS or 18
local clearancePairs={}
local clearanceSeen={}

local uppers=table.clone(bridge)
for _,part in ipairs(profiled) do
    if part:GetAttribute("CW_HighwayStructure")=="span" then
        table.insert(uppers,part)
    end
end
local clearanceList={}
for i,upper in ipairs(uppers) do
    local a,b=endpoints(upper)
    for _,groundRoad in ipairs(lowerNearby(a,b)) do
        local c,d=endpoints(groundRoad)
        local t,u=lineIntersection(a,b,c,d)
        if t then
            crossings+=1
            local upperBottom=a.Y+(b.Y-a.Y)*t-upper.Size.Y/2-DECK_THICKNESS
            local lowerTop=c.Y+(d.Y-c.Y)*u+groundRoad.Size.Y/2
            local clearance=upperBottom-lowerTop
            if clearance < -1.5 then
                -- the "lower" road is actually above this piece (e.g. the
                -- profiled highway passing under a local overpass that is
                -- itself in `bridge`); it is audited from the other side.
                crossings-=1
                continue
            end
            minClearance=math.min(minClearance,clearance)
            if #clearanceList<40 then
                table.insert(clearanceList,string.format("%s over %s=%.1f",
                    tostring(upper.Name),tostring(groundRoad.Name),clearance))
            end
            local required=minRequired
            if upper:GetAttribute("CW_HighwayProfiled")==true
                or upper:GetAttribute("CW_RegistryOverpassDeck")==true then
                -- generator-owned span: underpass rule (registry inventory
                -- clearances are enforced by HighwayProfile itself)
                required=Config.HIGHWAY_UNDERPASS_MIN_CLEARANCE_STUDS or 14
            end
            if clearance+0.25<required then
                tooLow+=1
                upper:SetAttribute("CW_LowClearance",true)
                local at=a:Lerp(b,t)
                local pairKey=tostring(upper.Name).."|"..tostring(groundRoad.Name).."|"
                    ..math.floor(at.X/60)..":"..math.floor(at.Z/60)
                if not clearanceSeen[pairKey] and #clearancePairs<40 then
                    clearanceSeen[pairKey]=true
                    table.insert(clearancePairs,string.format("%s over %s at (%.0f, %.0f)=%.1f need=%.0f",
                        tostring(upper.Name),tostring(groundRoad.Name),at.X,at.Z,clearance,required))
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
local embankmentApproaches=0
for _,road in ipairs(bridge) do
    if road:GetAttribute("CW_OnEmbankment")==true then
        -- a county-tagged approach resting on its fill (RoadTerrainConformer)
        embankmentApproaches+=1
        continue
    end
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

-- A tagged tunnel / underpass whose terrain rises through its roadway gets
-- the same terrain cut as the highway (cuts are allowed; see the cut pass).
local tunnelObstructions=0
local tunnelCuts=0
for _,road in ipairs(lower) do
    if road:GetAttribute("CW_Tunnel")==true
        or (tonumber(road:GetAttribute("CW_GradeLevel")) or 0)<0 then
        local a,b=endpoints(road)
        local mid=road.Position
        local worst=0
        for _,p in ipairs({a,mid,b}) do
            local gy=terrainY(p.X,p.Z)
            if gy and gy>p.Y+road.Size.Y/2+1 then
                worst=math.max(worst,gy-(p.Y+road.Size.Y/2))
            end
        end
        if worst>0 then
            -- terrain cuts are allowed: open the underpass the way the
            -- highway cut pass does (no retaining walls on rail/local cuts)
            local height=math.min(worst,CUT_MAX_DEPTH)+6
            Terrain:FillBlock(road.CFrame*CFrame.new(0,road.Size.Y/2+height/2,0),
                Vector3.new(road.Size.X+CUT_SHOULDER*2,height,road.Size.Z+2),Enum.Material.Air)
            road:SetAttribute("CW_TunnelCutDepth",worst)
            tunnelCuts+=1
        end
    end
end

-- Buildings under elevated freeway spans (Commodore Barry approach viaduct
-- etc.) may not poke through the deck (audit 2026-11-06: 33 buildings). A
-- block with headroom under the deck is cut down to just below it; one
-- without headroom (the deck runs through its lower storeys) is removed.
local underDeckTrimmed,underDeckRemoved,laneBuildingsRemoved=0,0,0
do
    local MIN_HEADROOM=9
    local params=OverlapParams.new()
    params.FilterType=Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances=buildingFolders
    local probe=Instance.new("Part")
    probe.Anchored=true
    probe.CanCollide=false
    probe.CanQuery=false
    probe.CanTouch=false
    probe.Transparency=1
    probe.Parent=Workspace
    for i,span in ipairs(profiled) do
        if span:GetAttribute("CW_HighwayStructure")=="span" and span.Parent then
            local underside=span.Position.Y-span.Size.Y/2-DECK_THICKNESS-0.5
            probe.Size=Vector3.new(span.Size.X+1,60,span.Size.Z)
            probe.CFrame=CFrame.new(span.Position.X,underside+30,span.Position.Z)*span.CFrame.Rotation
            for _,p in ipairs(Workspace:GetPartsInPart(probe,params)) do
                if p.Parent and p:IsA("BasePart") then
                    local bottom=p.Position.Y-p.Size.Y/2
                    local top=p.Position.Y+p.Size.Y/2
                    if top>underside then
                        local isWall=p.Name=="Walls" or p.Name=="GroundStorey" or p.Name=="Foundation"
                        if isWall and underside-bottom>=MIN_HEADROOM then
                            local newTop=underside-1
                            p.Size=Vector3.new(p.Size.X,newTop-bottom,p.Size.Z)
                            p.CFrame=p.CFrame+Vector3.new(0,(newTop+bottom)/2-p.Position.Y,0)
                            underDeckTrimmed+=1
                        else
                            p:Destroy()
                            underDeckRemoved+=1
                        end
                    end
                end
            end
        end
        if i%60==0 then task.wait() end
    end
    -- Grade / fill freeway pavement: a county footprint standing in the
    -- travel lanes (I-95 by Widener, the Barry approach by Engle / Central;
    -- audit 2026-11-06: 17 buildings) yields to the highway - the whole
    -- building model goes, not just the part that touches.
    for i,road in ipairs(profiled) do
        if road:GetAttribute("CW_HighwayStructure")~="span" and road.Parent then
            local top=road.Position.Y+road.Size.Y/2
            probe.Size=Vector3.new(road.Size.X*0.85,18,road.Size.Z)
            probe.CFrame=road.CFrame*CFrame.new(0,road.Size.Y/2+9.5,0)
            for _,p in ipairs(Workspace:GetPartsInPart(probe,params)) do
                if p.Parent and (p.Position.Y+p.Size.Y/2)>top+1 then
                    local model=p
                    for _,folder in ipairs(buildingFolders) do
                        if p:IsDescendantOf(folder) then
                            while model.Parent and model.Parent~=folder do model=model.Parent end
                            break
                        end
                    end
                    if model.Parent then
                        model:Destroy()
                        laneBuildingsRemoved+=1
                    end
                end
            end
            if i%80==0 then task.wait() end
        end
    end
    probe:Destroy()
end
print(("[ChesterWorld UnderDeckBuildings] trimmed=%d removed=%d laneBuildingsRemoved=%d"):format(underDeckTrimmed,underDeckRemoved,laneBuildingsRemoved))

-- City streets over I-95 / I-476 (Edgmont, Madison, Upland, Potter, Chestnut,
-- Melrose, Highland, Engle ...) are road-tile bridges, not highway spans. Every
-- one carries a concrete parapet topped by tall chain-link fencing in the
-- 2024-2026 Street View captures (Data\HighwayReference\imagery\google,
-- STRUCTURE_REVIEW_2026-11-05.md). Fence each street piece that crosses over
-- profiled freeway pavement.
local overFreewayFences,overFreewayPieces=0,0
do
    local candidates={}
    for _,part in ipairs(bridge) do table.insert(candidates,part) end
    for _,part in ipairs(lower) do
        if part:GetAttribute("CW_RegistryOverpassDeck")==true then table.insert(candidates,part) end
    end
    local fenceFolder=Instance.new("Folder")
    fenceFolder.Name="OverpassFencing"
    fenceFolder.Parent=folder
    local fenced={}
    for i,upper in ipairs(candidates) do
        if not fenced[upper] and upper:GetAttribute("CW_HighwayProfiled")~=true
            and upper:GetAttribute("CW_Rail")~=true then
            local a,b=endpoints(upper)
            for _,groundRoad in ipairs(lowerNearby(a,b)) do
                if groundRoad~=upper and groundRoad:GetAttribute("CW_HighwayProfiled")==true then
                    local c,d=endpoints(groundRoad)
                    local t,u=lineIntersection(a,b,c,d)
                    if t then
                        local clearance=(a.Y+(b.Y-a.Y)*t)-(c.Y+(d.Y-c.Y)*u)
                        if clearance>10 then
                            fenced[upper]=true
                            break
                        end
                    end
                end
            end
            if fenced[upper] then
                overFreewayPieces+=1
                local length,width=upper.Size.Z,upper.Size.X
                local hasParapet=upper:GetAttribute("CW_BridgeProfiled")==true
                    and upper:GetAttribute("CW_GradeLimited")~=true
                for _,side in ipairs({-1,1}) do
                    if not hasParapet then
                        partAt(fenceFolder,"OverpassParapet",Vector3.new(0.8,RAIL_HEIGHT,length),
                            upper.CFrame*CFrame.new(side*(width/2+0.3),upper.Size.Y/2+RAIL_HEIGHT/2,0),
                            COLOR,true)
                    end
                    local fence=partAt(fenceFolder,"HighwayOverpassFence",
                        Vector3.new(0.2,OVERPASS_FENCE_HEIGHT,length),
                        upper.CFrame*CFrame.new(side*(width/2+0.3),
                            upper.Size.Y/2+RAIL_HEIGHT+OVERPASS_FENCE_HEIGHT/2,0),
                        Color3.fromRGB(122,128,126),true)
                    fence.Material=Enum.Material.DiamondPlate
                    fence.Transparency=0.6
                    fence:SetAttribute("CW_SourceRoad",upper.Name)
                    fence:SetAttribute("CW_Evidence","Google Street View 2024-2026 (HighwayReference/imagery/google)")
                    overFreewayFences+=1
                end
            end
        end
        if i%40==0 then task.wait() end
    end
end
print(("[ChesterWorld OverpassFencing] streetPiecesOverFreeway=%d fences=%d"):format(overFreewayPieces,overFreewayFences))

Workspace:SetAttribute("CW_HighwayFinishComplete",true)
Workspace:SetAttribute("CW_HighwayClearanceFailures",tooLow)
Workspace:SetAttribute("CW_HighwayTunnelObstructions",tunnelObstructions)
Workspace:SetAttribute("CW_HighwayBridgeTerrainIntrusions",bridgeTerrainIntrusions)
Workspace:SetAttribute("CW_HighwayBridgeEmbankmentContacts",bridgeTerminalContacts)
Workspace:SetAttribute("CW_HighwayCrossingsVerified",crossings>0)

print(("[ChesterWorld HighwayFinish] embankmentApproachParts=%d (county bridge tags resting on their fill)"):format(embankmentApproaches))
print(("[ChesterWorld HighwayFinish] bridgeRoadParts=%d rampRoadParts=%d deckSlabs=%d guardrails=%d supports=%d crossings=%d minClearance=%.1f lowClearance=%d tunnelObstructions=%d bridgeTerrainIntrusions=%d terminalEmbankmentContacts=%d unprofiledBridgeParts=%d gradeLimitedBridgeParts=%d crossingsVerified=%s")
    :format(#bridge,#ramps,deckCount,railCount,pierCount,crossings,
    minClearance==math.huge and -1 or minClearance,tooLow,tunnelObstructions,bridgeTerrainIntrusions,bridgeTerminalContacts,#unprofiledBridges,#gradeLimited,tostring(crossings>0)))

if tooLow>0 then
    warn("[ChesterWorld HighwayFinish] LOW CLEARANCE: "..
        table.concat(clearancePairs,"; "))
end
if #gradeLimited>0 then
    warn(("[ChesterWorld HighwayFinish] %d short bridge parts lack enough aligned ramp distance for the requested clearance; fake deck supports are suppressed."):format(#gradeLimited))
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
if tunnelCuts>0 then
    print(("[ChesterWorld HighwayFinish] %d tunnel/underpass segments had terrain over them; cut open."):format(tunnelCuts))
end
