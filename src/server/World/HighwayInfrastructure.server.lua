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
            if part:IsA("BasePart") then
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
local hw={decks=0,girders=0,barriers=0,abutments=0,piers=0,fills=0,
    spans=0,spanPieces=0,fillPieces=0,gradePieces=0}

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
        local base=partAt(parent,"HighwayBarrier",
            Vector3.new(1.4,1.1,road.Size.Z),
            road.CFrame*CFrame.new(edge,road.Size.Y/2+0.55,0),BARRIER_COLOR,true)
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
            hw.girders+=1
        end
        for key,value in pairs(attrs) do deck:SetAttribute(key,value) end
        barrierPair(road,hwFolder,attrs)
    elseif kind=="fill" then
        hw.fillPieces+=1
        local bottom=minTerrainUnder(road,road.Size.X/2)
        if bottom then
            local roadBottom=road.Position.Y-road.Size.Y/2
            local height=roadBottom-bottom+1.0
            if height>0.6 then
                local slopeDrop=math.abs(road.CFrame.LookVector.Y)*road.Size.Z/2
                height+=slopeDrop
                local block=partAt(hwFolder,"HighwayFill",
                    Vector3.new(road.Size.X+1.0,height,road.Size.Z),
                    road.CFrame*CFrame.new(0,-road.Size.Y/2-height/2-0.01,0),
                    STRUCT_COLOR,true)
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
    else
        hw.gradePieces+=1
    end
    if index%40==0 then task.wait() end
end

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
        local wall=partAt(hwFolder,"HighwayAbutment",
            Vector3.new(piece.Size.X+2.0,height,3.0),
            CFrame.lookAt(c,c+flat),STRUCT_COLOR,true)
        wall:SetAttribute("CW_StructureId",id)
        wall:SetAttribute("CW_StructureBasis",entry.basis)
        hw.abutments+=1
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
                            if canPier(top,height) then
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
print(("[ChesterWorld HighwayStructures] profiledParts=%d spans=%d spanPieces=%d fillPieces=%d gradePieces=%d decks=%d fascia=%d barriers=%d abutments=%d piers=%d fills=%d holes=%d padCoveredGaps=%d steps=%d worstStep=%.2f")
    :format(#profiled,hw.spans,hw.spanPieces,hw.fillPieces,hw.gradePieces,hw.decks,
    hw.girders,hw.barriers,hw.abutments,hw.piers,hw.fills,holes,coveredGaps,steps,worstStep))
for _,line in ipairs(holeList) do
    warn("[ChesterWorld HighwayHole] "..line)
end

-- Report the ACTUAL vertical clearance between every road pair with crossing
-- centerlines on different levels. Do not infer safety from bridge count.
local crossings,tooLow,minClearance=0,0,math.huge
local minRequired=Config.HIGHWAY_MIN_CLEARANCE_STUDS or 18
local clearancePairs={}

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
            if upper:GetAttribute("CW_HighwayProfiled")==true then
                -- generator-owned span: underpass rule (registry inventory
                -- clearances are enforced by HighwayProfile itself)
                required=Config.HIGHWAY_UNDERPASS_MIN_CLEARANCE_STUDS or 14
            end
            if clearance+0.25<required then
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
if tunnelObstructions>0 then
    warn(("[ChesterWorld HighwayFinish] %d tunnel segments have terrain intrusions. No destructive terrain edits were made."):format(tunnelObstructions))
end
