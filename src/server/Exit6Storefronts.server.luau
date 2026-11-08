-- EXIT 6: convert explicitly tagged gas station models into playable storefronts.
-- Tag an existing gas-station Model "Exit6GasStation" in Studio.
-- This ADDS a compact store beside its pivot; it never deletes or modifies city geometry.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local stations = {}
-- the id bump makes the same message twice still show the client toast
local function notify(player, text)
 player:SetAttribute("Exit6Notice", text)
 player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
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
 -- brand colours from the station (GasStationBuilder: BrandFascia / BrandAccent);
 -- the lit brand board over the front is the station's own Exit6StoreFascia
 local brandName=model:GetAttribute("BrandName") or model.Name
 local fascia=model:GetAttribute("BrandFascia") or Color3.fromRGB(50,54,60)
 local accent=model:GetAttribute("BrandAccent") or Color3.fromRGB(200,60,40)
 local WALL=Color3.fromRGB(232,228,220)
 -- a ChesterWorld station shop (GasStationBuilder: Exit6StoreShell = "building")
 -- already has walls, glass front and fascia: only fit the interior, scaled
 -- to the shop's floor
 local inBuilding=model:GetAttribute("Exit6StoreShell")=="building"
 if inBuilding then
  brandName=model:GetAttribute("ShopName") or brandName
  local w=model:GetAttribute("Exit6StoreWidth") or 26
  local d=model:GetAttribute("Exit6StoreDepth") or 22
  local fx,fz=math.min(1,(w-4)/26),math.min(1,(d-4)/22)
  make=function(name,size,x,y,z,color,mat)
   return part(folder,name,Vector3.new(size.X*math.max(fx,0.6),size.Y,size.Z*math.max(fz,0.6)),base*CFrame.new(x*fx,y,z*fz),color,mat)
  end
 end
 if not inBuilding then
 make("Floor",Vector3.new(26,0.5,22),0,0,0,Color3.fromRGB(196,198,200),Enum.Material.Marble)
 make("BackWall",Vector3.new(26,12,0.7),0,6,11,WALL,Enum.Material.Brick)
 for _,x in ipairs({-13,13}) do make("SideWall",Vector3.new(0.7,12,22),x,6,0,WALL,Enum.Material.Brick) end
 -- brand stripe along the base of the walls and a coloured roof edge
 make("BaseStripe",Vector3.new(26.4,1.2,0.3),0,1.1,11.4,accent)
 for _,x in ipairs({-13.4,13.4}) do make("BaseStripe",Vector3.new(0.3,1.2,22.4),x,1.1,0,accent) end
 make("Roof",Vector3.new(26.6,0.7,22.6),0,12,0,Color3.fromRGB(60,62,66))
 make("RoofEdge",Vector3.new(26.8,1.2,0.4),0,12,11.3,fascia)
 for _,x in ipairs({-13.4,13.4}) do make("RoofEdge",Vector3.new(0.4,1.2,22.8),x,12,0,fascia) end
 -- glass shopfront with a door opening in the middle
 for _,x in ipairs({-8,8}) do
  local g=make("Shopfront",Vector3.new(10,8.6,0.3),x,4.6,-11,Color3.fromRGB(150,190,210),Enum.Material.Glass)
  g.Transparency=0.35
  g.Reflectance=0.15
  make("Mullion",Vector3.new(0.4,8.6,0.5),x+(x<0 and 5 or -5),4.6,-11,fascia,Enum.Material.Metal)
 end
 make("Header",Vector3.new(26,1.4,0.6),0,11.1,-11,fascia)
 make("AccentStripe",Vector3.new(26,0.6,0.7),0,10.1,-11,accent)
 make("Transom",Vector3.new(26,0.9,0.5),0,9.35,-11,WALL,Enum.Material.Brick)
 local mat=make("DoorMat",Vector3.new(5,0.1,3),0,0.3,-12.5,Color3.fromRGB(40,40,44),Enum.Material.Fabric)
 mat.CanCollide=false
 end
 make("Counter",Vector3.new(10,3.2,3),-5,1.8,5,Color3.fromRGB(76,55,40),Enum.Material.Wood)
 -- Narrow city shops need an open aisle from the front door to the register.
 -- Fitting two shelving runs in a small footprint blocks that route; one
 -- shorter run also reduces parts in the busiest downtown tiles.
 local storeWidth=model:GetAttribute("Exit6StoreWidth") or 26
 local storeDepth=model:GetAttribute("Exit6StoreDepth") or 22
 local shelfXs=(inBuilding and storeWidth<21) and {6.5} or {2,8}
 local shelfLength=(inBuilding and storeDepth<19) and 5.5 or 9
 for _,x in ipairs(shelfXs) do
  make("MerchandiseShelf",Vector3.new(3,5,shelfLength),x,2.75,-1,Color3.fromRGB(55,62,70),Enum.Material.Metal)
  local stockZs=shelfLength<9 and {-2,1} or {-4,-1,2}
  for _,z in ipairs(stockZs) do
   local stock=make("Stock",Vector3.new(2.5,1.1,1.6),x,3.1,z,Color3.fromRGB(195,88,42))
   stock.CanCollide=false
  end
 end
 local cooler=make("DrinkCooler",Vector3.new(6,7,2),-8,3.5,-9,Color3.fromRGB(43,76,92),Enum.Material.Glass)
 local register=make("CashRegister",Vector3.new(2,1,1.5),-5,4,5,Color3.fromRGB(35,35,40))
 local lastJob={}
 -- the shift job is the gas stations' (tag Exit6GasStation); every other
 -- ChesterWorld store (tag Exit6Store, RealBuildings.lua) gets the interior
 -- and the drink cooler
 local isStation=CollectionService:HasTag(model,"Exit6GasStation")
 local Config=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Exit6Config"))
 if Config.ShopSystem then
  -- Exit6Shop.server runs the counter (cashier, menu, stock shift)
  model:SetAttribute("Exit6InteriorReady",true)
  if isStation then print("[EXIT6] Storefront installed at",model:GetFullName()) end
  return
 end
 if isStation then prompt(register,"Work shift (+$35)",brandName,function(player)
  local stats=player:FindFirstChild("leaderstats")
  local cash=stats and stats:FindFirstChild("Chester Cash")
  local rep=stats and stats:FindFirstChild("Reputation")
  if not (cash and rep) or player:GetAttribute("Exit6DataReady")~=true then return end
  local now=os.clock()
  if lastJob[player.UserId] and now-lastJob[player.UserId]<120 then
   notify(player,"Next shift available in "..math.ceil(120-(now-lastJob[player.UserId])).."s")
   return
  end
  lastJob[player.UserId]=now
  cash.Value+=35;rep.Value+=1
  notify(player,"Shift complete! +$35, +1 REP")
 end) end
 prompt(cooler,"Buy drink ($5)",brandName.." Market",function(player)
  local stats=player:FindFirstChild("leaderstats")
  local cash=stats and stats:FindFirstChild("Chester Cash")
  if not cash or player:GetAttribute("Exit6DataReady")~=true then return end
  if cash.Value<5 then notify(player,"Not enough Chester Cash");return end
  cash.Value-=5
  notify(player,"Purchased a drink (-$5)")
 end)
 model.Destroying:Connect(function() stations[model]=nil end)
 if isStation then print("[EXIT6] Storefront installed at",model:GetFullName()) end
end
for _,m in ipairs(CollectionService:GetTagged("Exit6GasStation")) do build(m) end
CollectionService:GetInstanceAddedSignal("Exit6GasStation"):Connect(build)
for _,m in ipairs(CollectionService:GetTagged("Exit6Store")) do task.spawn(build,m) end
CollectionService:GetInstanceAddedSignal("Exit6Store"):Connect(build)
