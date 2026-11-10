-- Read-only ChesterWorld geometry probe. Run with the Rojo-synced Studio place.
local W=game:GetService("Workspace")
local targets={{"EDGMONT_I95",6223,-2232,850},{"BARRY_7TH_FLOWER",-1195,4865,900},{"BARRY_2ND",15,6815,800}}
local world=W:WaitForChild("ChesterWorld",180)
if not world then warn("[CWProbe] Missing ChesterWorld") return end
-- The previous probe ran before HighwayFinish, so supports and clearance
-- geometry were incomplete. Wait for the actual completion flag.
local deadline=os.clock()+240
while os.clock()<deadline and W:GetAttribute("CW_HighwayFinishComplete")~=true do task.wait(1) end
if W:GetAttribute("CW_HighwayFinishComplete")~=true then
 warn("[CWProbe] HighwayFinish did not complete within 240 seconds; results may be incomplete")
end
task.wait(2)
for _,t in ipairs(targets) do
    local found={}
    for _,p in ipairs(world:GetDescendants()) do
        if p:IsA("BasePart") then
            local dx,dz=p.Position.X-t[2],p.Position.Z-t[3]
            local d=math.sqrt(dx*dx+dz*dz)
            if d<t[4] then
                local isRoad=p:GetAttribute("CW_HighwayProfiled") or p:GetAttribute("CW_BridgeProfiled") or p:GetAttribute("CW_RampProfiled") or (p.Parent and p.Parent.Name=="Roads")
                local isSupport=p.CanCollide and (p.Name:find("Pier") or p.Name:find("Abutment") or p.Name:find("Barrier") or p.Name:find("Support"))
                if isRoad or isSupport then table.insert(found,{p=p,d=d,kind=isRoad and "ROAD" or "SUPPORT"}) end
            end
        end
    end
    table.sort(found,function(a,b)return a.d<b.d end)
    print(string.format("[CWProbe] AREA %s center=(%d,%d) candidates=%d",t[1],t[2],t[3],#found))
    for i=1,math.min(100,#found) do
        local f=found[i];local p=f.p
        print(string.format("[CWProbe] %s d=%.0f name=%s xyz=%.1f,%.1f,%.1f size=%.1f,%.1f,%.1f top=%.1f collide=%s stroke=%s structure=%s grade=%s",
            f.kind,f.d,p.Name,p.Position.X,p.Position.Y,p.Position.Z,p.Size.X,p.Size.Y,p.Size.Z,
            p.Position.Y+p.Size.Y/2,tostring(p.CanCollide),tostring(p:GetAttribute("CW_StrokeId")),
            tostring(p:GetAttribute("CW_HighwayStructure")),tostring(p:GetAttribute("CW_GradeLevel"))))
    end
end
print("[CWProbe] END")
