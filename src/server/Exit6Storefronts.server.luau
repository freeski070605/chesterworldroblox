-- EXIT 6: convert explicitly tagged gas station models into playable storefronts.
-- Tag an existing gas-station Model "Exit6GasStation" in Studio.
-- This ADDS a compact store beside its pivot; it never deletes or modifies city geometry.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local stations = {}
local function part(parent,name,size,cf,color,material)
 local p=Instance.new("Part")
 p.Name=name;p.Size=size;p.CFrame=cf;p.Anchored=true;p.Color=color
 p.Material=material or Enum.Material.SmoothPlastic;p.Parent=parent
 return p
end
local function prompt(target,action,object,callback)
 local p=Instance.new("ProximityPrompt")
 p.ActionText=action;p.ObjectText=object;p.MaxActivationDistance=10
 p.HoldDuration=0.25;p.RequiresLineOfSight=false;p.Parent=target
 p.Triggered:Connect(function(player)
  local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  if not root or (root.Position-target.Position).Magnitude>13 then return end
  callback(player)
 end)
end
local function build(model)
 if not model:IsA("Model") or stations[model] then return end
 stations[model]=true
 -- The store is a separate open-front kiosk for safe placement during initial integration.
 -- Move/rotate the tagged gas station's Exit6StoreAnchor attachment/part to position it precisely.
 local anchor=model:FindFirstChild("Exit6StoreAnchor",true)
 if not (anchor and anchor:IsA("BasePart")) then
  warn("[EXIT6] Gas station requires Exit6StoreAnchor part:",model:GetFullName())
  stations[model]=nil;return
 end
 local folder=Instance.new("Model");folder.Name="Exit6Storefront";folder.Parent=model
 local base=anchor.CFrame
 local function make(name,size,x,y,z,color,mat)
  return part(folder,name,size,base*CFrame.new(x,y,z),color,mat)
 end
 make("Floor",Vector3.new(26,0.5,22),0,0,0,Color3.fromRGB(110,110,110),Enum.Material.Concrete)
 make("BackWall",Vector3.new(26,12,0.7),0,6,11,Color3.fromRGB(198,190,175))
 for _,x in ipairs({-13,13}) do make("SideWall",Vector3.new(0.7,12,22),x,6,0,Color3.fromRGB(198,190,175)) end
 make("Roof",Vector3.new(26,0.7,22),0,12,0,Color3.fromRGB(50,54,60))
 make("Counter",Vector3.new(10,3.2,3),-5,1.8,5,Color3.fromRGB(76,55,40),Enum.Material.Wood)
 for _,x in ipairs({2,8}) do
  make("MerchandiseShelf",Vector3.new(3,5,9),x,2.75,-1,Color3.fromRGB(55,62,70),Enum.Material.Metal)
  for _,z in ipairs({-4,-1,2}) do
   make("Stock",Vector3.new(2.5,1.1,1.6),x,3.1,z,Color3.fromRGB(195,88,42))
  end
 end
 local cooler=make("DrinkCooler",Vector3.new(6,7,2),-8,3.5,-9,Color3.fromRGB(43,76,92),Enum.Material.Glass)
 local register=make("CashRegister",Vector3.new(2,1,1.5),-5,4,5,Color3.fromRGB(35,35,40))
 local lastJob={}
 prompt(register,"Work shift (+$35)","Gas Station",function(player)
  local stats=player:FindFirstChild("leaderstats")
  local cash=stats and stats:FindFirstChild("Chester Cash")
  local rep=stats and stats:FindFirstChild("Reputation")
  if not (cash and rep) or player:GetAttribute("Exit6DataReady")~=true then return end
  local now=os.clock()
  if lastJob[player.UserId] and now-lastJob[player.UserId]<120 then
   player:SetAttribute("Exit6Notice","Next shift available in "..math.ceil(120-(now-lastJob[player.UserId])).."s")
   return
  end
  lastJob[player.UserId]=now
  cash.Value+=35;rep.Value+=1
  player:SetAttribute("Exit6Notice","Shift complete! +$35, +1 REP")
 end)
 prompt(cooler,"Buy drink ($5)","Corner Store",function(player)
  local stats=player:FindFirstChild("leaderstats")
  local cash=stats and stats:FindFirstChild("Chester Cash")
  if not cash or player:GetAttribute("Exit6DataReady")~=true then return end
  if cash.Value<5 then player:SetAttribute("Exit6Notice","Not enough Chester Cash");return end
  cash.Value-=5
  player:SetAttribute("Exit6Notice","Purchased a drink (-$5)")
 end)
 model.Destroying:Connect(function() stations[model]=nil end)
 print("[EXIT6] Storefront installed at",model:GetFullName())
end
for _,m in ipairs(CollectionService:GetTagged("Exit6GasStation")) do build(m) end
CollectionService:GetInstanceAddedSignal("Exit6GasStation"):Connect(build)
Players.PlayerRemoving:Connect(function(p) end)
