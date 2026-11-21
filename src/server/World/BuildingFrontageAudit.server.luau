-- EXIT 6 read-only storefront orientation audit.
-- Opt in with Workspace attribute CW_FrontageAudit=true before Play.
-- This finds probable incorrectly facing storefronts across built city tiles.
-- It NEVER moves buildings or changes gameplay IDs.
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
if Workspace:GetAttribute("CW_FrontageAudit") ~= true then return end

local started = os.clock()
while Workspace:GetAttribute("CW_BootstrapComplete") ~= true and os.clock()-started < 360 do
 task.wait(2)
end
-- Give auxiliary shop/station generators time to load before this one-shot audit.
local t = os.clock()
while Workspace:GetAttribute("CW_GasStationsComplete") ~= true and os.clock()-t < 120 do
 task.wait(2)
end
local stats = {checked=0, suspected=0, skipped=0, noStreet=0}
local suspects = {}
local checked = {}
local roadParams = OverlapParams.new()
roadParams.MaxParts = 500
local function flat(p) return Vector3.new(p.X,0,p.Z) end
local function nearestStreet(anchor)
 local best, dist, name = nil, math.huge, nil
 -- The search uses physics spatial indexing, not a full 102-tile parts scan.
 local nearby = Workspace:GetPartBoundsInRadius(anchor.Position,120,roadParams)
 for _,road in ipairs(nearby) do
  if road:IsA("BasePart") and road.Parent and road.Parent.Name=="Roads"
   and not road:GetAttribute("CW_HighwayProfiled") then
   local street = road:GetAttribute("ChesterStreet")
   if type(street)=="string" and street~="" then
    local p = road:GetClosestPointOnSurface(anchor.Position)
    local delta = flat(p-anchor.Position)
    local d = delta.Magnitude
    if d>0.5 and d<dist then best,dist,name=p,d,street end
   end
  end
 end
 return best,dist,name
end
for _,tag in ipairs({"Exit6Store","Exit6GasStation"}) do
 for _,store in ipairs(CollectionService:GetTagged(tag)) do
  if store:IsA("Model") and not checked[store] then
   checked[store]=true
   local anchor = store:FindFirstChild("Exit6StoreAnchor",true)
   if not (anchor and anchor:IsA("BasePart")) then
    stats.skipped+=1
   else
    stats.checked+=1
    local p,dist,street = nearestStreet(anchor)
    if not p then
     stats.noStreet+=1
    else
     local direction=flat(p-anchor.Position)
     local forward=flat(anchor.CFrame.LookVector)
     if direction.Magnitude>0.5 and forward.Magnitude>0.5 then
      local alignment=forward.Unit:Dot(direction.Unit)
      -- Dot<0: the named storefront looks away from nearest road. It may
      -- face its addressed road instead, especially at a corner, so REVIEW.
      if alignment < -0.2 then
       stats.suspected+=1
       table.insert(suspects,{
        shop=tostring(store:GetAttribute("ShopName") or store.Name),
        id=tostring(store:GetAttribute("ChesterBuildingId") or store:GetAttribute("StationId") or "unlinked"),
        street=street, alignment=alignment, distance=dist, pos=anchor.Position,
       })
      end
     end
    end
   end
  end
 end
end
table.sort(suspects,function(a,b) return a.alignment < b.alignment end)
print(string.format("[CW FrontageAudit] checked=%d suspected=%d noStreet=%d noAnchor=%d",
 stats.checked,stats.suspected,stats.noStreet,stats.skipped))
for i=1,math.min(#suspects,80) do
 local s=suspects[i]
 warn(string.format("[CW FrontageAudit] REVIEW #%d shop=%s id=%s nearestStreet=%s dot=%.2f distance=%.1f X=%.1f Z=%.1f",
 i,s.shop,s.id,s.street,s.alignment,s.distance,s.pos.X,s.pos.Z))
end
Workspace:SetAttribute("CW_FrontageAuditComplete",true)
