-- EXIT 6: conservative repair of SHORT, DRY, physically anchored road gaps.
-- This does not extrapolate over mapped/visible water or invent steep ramps.
-- Constructed only AFTER all terrain, highways and local bridges finish.
local Workspace=game:GetService("Workspace")
local Terrain=Workspace.Terrain
local Builder=require(script.Parent:WaitForChild("TileBuilderV2"))
local WaterMap=require(script.Parent:WaitForChild("WaterMap"))

Workspace:SetAttribute("CW_RoadGapRepairComplete",false)
Workspace:SetAttribute("CW_RoadGapRepairStatus","waiting")

local function awaitStages()
    for _,stage in ipairs({
        "CW_BootstrapComplete","CW_RoadConformComplete",
        "CW_HighwayFinishComplete","CW_RoadTerrainCleared",
        "CW_LocalBridgesDressed","CW_LandmarksComplete","CW_WaterComplete",
    }) do
        while Workspace:GetAttribute(stage)~=true do task.wait(0.5) end
    end
end

local terrainDry=RaycastParams.new()
terrainDry.FilterType=Enum.RaycastFilterType.Include
terrainDry.FilterDescendantsInstances={Terrain}
terrainDry.IgnoreWater=true
local terrainWet=RaycastParams.new()
terrainWet.FilterType=Enum.RaycastFilterType.Include
terrainWet.FilterDescendantsInstances={Terrain}
terrainWet.IgnoreWater=false

local function terrainHeight(x,z)
    local hit=Workspace:Raycast(Vector3.new(x,5000,z),
        Vector3.new(0,-10000,0),terrainDry)
    return hit and hit.Position.Y
end
local function confirmedDry(x,z)
    if WaterMap.Classify(x,z)~="notMapped" then return false end
    local hit=Workspace:Raycast(Vector3.new(x,5000,z),
        Vector3.new(0,-10000,0),terrainWet)
    return hit~=nil and hit.Material~=Enum.Material.Water
end
local function pt(x,z) return Vector3.new(x,0,z) end
local function key(x,z)
    return tostring(math.floor(x*10+0.5))..":"..tostring(math.floor(z*10+0.5))
end
local function len(a,b)
    local dx,dz=a.X-b.X,a.Z-b.Z
    return math.sqrt(dx*dx+dz*dz)
end

local function run()
    awaitStages()
    Workspace:SetAttribute("CW_RoadGapRepairStatus","checking")
    local world=Workspace:FindFirstChild("ChesterWorld")
    if not world then error("ChesterWorld missing after bootstrap") end
    local omissions=Builder.Stats()
    local all=omissions and omissions.missingFragments or {}
    local groups={}
    for _,f in ipairs(all) do
        -- Footways, pedestrian routes, and motorway profiles require their
        -- own materials and separate engineering rules; never turn them
        -- into generic street asphalt during this repair pass.
        local cls=string.lower(tostring(f.class or ""))
        local roadName=string.lower(tostring(f.road or ""))
        local isVehicleStreet=cls~="footway" and cls~="path"
            and cls~="pedestrian" and cls~="cycleway"
            and cls~="motorway" and cls~="motorway_link"
            and cls~="trunk" and cls~="trunk_link"
            and not roadName:find("pedestrian",1,true)
        if f.kind=="steep" and f.length>=0.3 and isVehicleStreet then
            -- Avoid joining roads with different width or source class.
            local gkey=tostring(f.road).."|"..tostring(f.class).."|"
                ..tostring(math.floor(f.width+0.5))
            local list=groups[gkey]
            if not list then list={} groups[gkey]=list end
            table.insert(list,f)
        end
    end
    local overlap=OverlapParams.new()
    overlap.FilterType=Enum.RaycastFilterType.Include
    overlap.MaxParts=0
    local roadFolders={}
    for _,tile in ipairs(world:GetChildren()) do
        local folder=tile:FindFirstChild("Roads")
        if folder then table.insert(roadFolders,folder) end
    end
    overlap.FilterDescendantsInstances=roadFolders

    local function anchorFor(x,z,outward,road,width)
        local candidates=Workspace:GetPartBoundsInBox(
            CFrame.new(x,200,z),Vector3.new(12,1200,12),overlap)
        local best,bestScore=nil,math.huge
        for _,part in ipairs(candidates) do
            if part:IsA("BasePart") and part.Name==road
                and part:GetAttribute("CW_HighwayProfiled")~=true
                and part:GetAttribute("CW_GradeLimited")~=true
                and part:GetAttribute("CW_Rail")~=true
                and part:GetAttribute("CW_Tunnel")~=true
                and part:GetAttribute("CW_Bridge")~=true
                and math.abs(part.Size.X-width)<=3 then
                local a=part.CFrame*Vector3.new(0,0,part.Size.Z/2)
                local b=part.CFrame*Vector3.new(0,0,-part.Size.Z/2)
                for _,pair in ipairs({{a,b},{b,a}}) do
                    local near,far=pair[1],pair[2]
                    local dist=len(near,pt(x,z))
                    local continuation=pt(far.X-near.X,far.Z-near.Z)
                    local run=continuation.Magnitude
                    if dist<=2.2 and run>2 then
                        local dot=continuation.Unit:Dot(outward)
                        if dot>0.78 then
                            local score=dist+math.abs(part.Size.X-width)*0.08
                            if score<bestScore then
                                best={part=part,y=near.Y,point=near}
                                bestScore=score
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local reasonCounts={}
    local function rejected(why)
        reasonCounts[why]=(reasonCounts[why] or 0)+1
    end
    local totalGroups,repairedGroups,repairedFragments=0,0,0
    local insertedParts=0

    local function tryGroup(fragments)
        totalGroups+=1
        local adj,ends={},{}
        for index,f in ipairs(fragments) do
            local ka,kb=key(f.ax,f.az),key(f.bx,f.bz)
            ends[index]={ka,kb}
            adj[ka]=adj[ka] or {}
            adj[kb]=adj[kb] or {}
            table.insert(adj[ka],index)
            table.insert(adj[kb],index)
        end
        local terminals={}
        for k,items in pairs(adj) do
            if #items>2 then rejected("junction-ambiguous") return end
            if #items==1 then table.insert(terminals,k) end
        end
        if #terminals~=2 then rejected("not-a-simple-open-chain") return end
        table.sort(terminals)
        local current=terminals[1]
        local used,ordered={},{}
        for _=1,#fragments do
            local nextIndex
            for _,id in ipairs(adj[current] or {}) do
                if not used[id] then nextIndex=id break end
            end
            if not nextIndex then break end
            used[nextIndex]=true
            local f=fragments[nextIndex]
            local ka,kb=ends[nextIndex][1],ends[nextIndex][2]
            local reversed=current==kb
            local from=reversed and pt(f.bx,f.bz) or pt(f.ax,f.az)
            local to=reversed and pt(f.ax,f.az) or pt(f.bx,f.bz)
            table.insert(ordered,{f=f,a=from,b=to,length=len(from,to)})
            current=reversed and ka or kb
        end
        if current~=terminals[2] or #ordered~=#fragments then
            rejected("chain-not-contiguous") return
        end
        local total=0
        for _,seg in ipairs(ordered) do total+=seg.length end
        if total<1 or total>48 then rejected("too-long-for-local-repair") return end
        local first,last=ordered[1],ordered[#ordered]
        local dxA=(first.b-first.a).Unit
        local dxB=(last.b-last.a).Unit
        local start=anchorFor(first.a.X,first.a.Z,-dxA,first.f.road,first.f.width)
        local finish=anchorFor(last.b.X,last.b.Z,dxB,last.f.road,last.f.width)
        if not start or not finish then rejected("missing-two-road-anchors") return end
        if start.part==finish.part then rejected("same-anchor-road") return end
        local grade=math.abs(finish.y-start.y)/total
        if grade>0.11 then rejected("unsafe-anchor-grade") return end
        local sourceStartY=first.a.X==first.f.ax and first.a.Z==first.f.az
            and first.f.ay or first.f.by
        local sourceEndY=last.b.X==last.f.bx and last.b.Z==last.f.bz
            and last.f.by or last.f.ay
        if math.abs(start.y-sourceStartY)>18 or math.abs(finish.y-sourceEndY)>18 then
            -- Guard against a road at an entirely different elevation.
            rejected("layer-mismatch") return
        end

        -- Validate the actual road corridor BEFORE changing terrain. Reject
        -- any water or missing ground at center and both pavement shoulders.
        local walked=0
        for _,seg in ipairs(ordered) do
            local dir=(seg.b-seg.a).Unit
            local right=Vector3.new(-dir.Z,0,dir.X)
            for _,t in ipairs({0,0.5,1}) do
                local p=seg.a:Lerp(seg.b,t)
                local roadY=start.y+(finish.y-start.y)*(walked+seg.length*t)/total
                local roadTop=roadY+0.23
                -- Do not insert an at-grade patch across an elevated
                -- overpass, motorway, tunnel or rail crossing.
                if t==0.5 then
                    local nearby=Workspace:GetPartBoundsInBox(
                        CFrame.new(p.X,roadY,p.Z),
                        Vector3.new(math.max(3,seg.f.width),18,3),overlap)
                    for _,other in ipairs(nearby) do
                        if other:GetAttribute("CW_HighwayProfiled")==true
                            or other:GetAttribute("CW_Bridge")==true
                            or other:GetAttribute("CW_Tunnel")==true
                            or other:GetAttribute("CW_Rail")==true then
                            rejected("grade-separated-crossing") return
                        end
                    end
                end
                for _,side in ipairs({-0.55,-0.35,0,0.35,0.55}) do
                    local x,z=p.X+right.X*seg.f.width*side,
                        p.Z+right.Z*seg.f.width*side
                    if not confirmedDry(x,z) then
                        rejected("water-or-missing-land") return
                    end
                    local gy=terrainHeight(x,z)
                    if not gy then rejected("no-ground-elevation") return end
                    if gy-roadTop>2.5 then
                        rejected("requires-deep-excavation") return
                    end
                    if roadTop-gy>3 then
                        rejected("floating-above-terrain") return
                    end
                end
            end
            walked+=seg.length
        end

        -- Whole chain passed. Install all pieces on a known real-road parent.
        -- Preserve the same 0.45-stud asphalt and CFrame orientation.
        walked=0
        for _,seg in ipairs(ordered) do
            local y0=start.y+(finish.y-start.y)*walked/total
            walked+=seg.length
            local y1=start.y+(finish.y-start.y)*walked/total
            local a=Vector3.new(seg.a.X,y0,seg.a.Z)
            local b=Vector3.new(seg.b.X,y1,seg.b.Z)
            local newPart=Instance.new("Part")
            newPart.Name=tostring(seg.f.road)
            newPart.Size=Vector3.new(seg.f.width,0.45,(b-a).Magnitude+0.16)
            newPart.CFrame=CFrame.lookAt((a+b)/2,b,Vector3.yAxis)
            newPart.Anchored=true
            newPart.Material=Enum.Material.Asphalt
            newPart.Color=Color3.fromRGB(53,53,56)
            newPart.TopSurface=Enum.SurfaceType.Smooth
            newPart.BottomSurface=Enum.SurfaceType.Smooth
            newPart:SetAttribute("ChesterStreet",tostring(seg.f.road))
            newPart:SetAttribute("CW_RoadClass",tostring(seg.f.class or ""))
            newPart:SetAttribute("RoadWidthStuds",seg.f.width)
            newPart:SetAttribute("CW_RoadGapRepair",true)
            newPart:SetAttribute("CW_RepairAnchorGrade",grade)
            newPart.Parent=start.part.Parent
            -- Small <2.5-stud local terrain bumps only; no new water fill.
            Terrain:FillBlock(newPart.CFrame*CFrame.new(0,2.1,0),
                Vector3.new(seg.f.width+0.5,4.0,newPart.Size.Z+0.2),
                Enum.Material.Air)
            insertedParts+=1
        end
        repairedGroups+=1
        repairedFragments+=#fragments
        print(("[ChesterWorld RoadGapRepaired] road=%s fragments=%d length=%.1f grade=%.1f%% from=(%.1f,%.1f) to=(%.1f,%.1f)")
            :format(tostring(first.f.road),#fragments,total,grade*100,
                first.a.X,first.a.Z,last.b.X,last.b.Z))
    end

    for _,list in pairs(groups) do
        local vertices={}
        for index,f in ipairs(list) do
            for _,k in ipairs({key(f.ax,f.az),key(f.bx,f.bz)}) do
                vertices[k]=vertices[k] or {}
                table.insert(vertices[k],index)
            end
        end
        local seen={}
        for index=1,#list do
            if not seen[index] then
                seen[index]=true
                local queue={index}
                local component={}
                local q=1
                while q<=#queue do
                    local i=queue[q]
                    q+=1
                    local f=list[i]
                    table.insert(component,f)
                    for _,k in ipairs({key(f.ax,f.az),key(f.bx,f.bz)}) do
                        for _,other in ipairs(vertices[k] or {}) do
                            if not seen[other] then
                                seen[other]=true
                                table.insert(queue,other)
                            end
                        end
                    end
                end
                tryGroup(component)
                if totalGroups%10==0 then task.wait() end
            end
        end
    end
    local reasonList={}
    for k,count in pairs(reasonCounts) do
        table.insert(reasonList,k.."="..count)
    end
    table.sort(reasonList)
    Workspace:SetAttribute("CW_RoadGapRepairGroups",repairedGroups)
    Workspace:SetAttribute("CW_RoadGapRepairFragments",repairedFragments)
    Workspace:SetAttribute("CW_RoadGapRepairParts",insertedParts)
    Workspace:SetAttribute("CW_RoadGapRepairStatus","complete")
    print(("[ChesterWorld RoadGapRepair] evaluatedChains=%d fixedChains=%d fixedFragments=%d newAsphaltParts=%d rejected={%s}")
        :format(totalGroups,repairedGroups,repairedFragments,
            insertedParts,table.concat(reasonList,",")))
end

local ok,err=pcall(run)
if not ok then
    warn("[ChesterWorld RoadGapRepair] FAILED "..tostring(err))
    Workspace:SetAttribute("CW_RoadGapRepairStatus","failed")
end
Workspace:SetAttribute("CW_RoadGapRepairComplete",true)
