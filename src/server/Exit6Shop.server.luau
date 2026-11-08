-- EXIT 6 stores: cashier NPCs, the counter menu, purchases, and the stock-clerk
-- shift. Runs on every store the world exposes (CollectionService tags
-- Exit6GasStation - GasStationBuilder - and Exit6Store - RealBuildings), once
-- Exit6Storefronts has fitted the interior (attribute Exit6InteriorReady).
-- Everything that moves money or reputation is decided here, on the server.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Config = require(Shared:WaitForChild("Exit6Config"))
local Inventory = require(script.Parent:WaitForChild("Exit6Inventory"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Style = require(script.Parent:WaitForChild("Exit6Style"))
if not Config.ShopSystem then return end

-- remotes
local remotes = Instance.new("Folder")
remotes.Name = "Exit6Remotes"
remotes.Parent = ReplicatedStorage
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local ShopOpen = remote("RemoteEvent", "ShopOpen")
local Purchase = remote("RemoteFunction", "Purchase")
local UseItem = remote("RemoteFunction", "UseItem")

local stores = {}        -- storeId -> { model, kind, title, counter (BasePart), menu }
local nextId = 0
local REACH = 18          -- studs from the counter to buy

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function stats(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
end
local function root(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function ready(player)
	return player:GetAttribute("Exit6DataReady") == true
end
local function prompt(parent, action, object, hold)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.MaxActivationDistance = 10
	p.HoldDuration = hold or 0
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- cashier NPC: an R15 figure behind the counter, facing the door
local SKIN = { Color3.fromRGB(86, 58, 44), Color3.fromRGB(120, 84, 62), Color3.fromRGB(156, 112, 84),
	Color3.fromRGB(196, 150, 116), Color3.fromRGB(66, 44, 34) }
local SHIRT = { Color3.fromRGB(180, 30, 40), Color3.fromRGB(30, 60, 140), Color3.fromRGB(40, 110, 60),
	Color3.fromRGB(40, 40, 44), Color3.fromRGB(230, 230, 226) }
local function cashier(store, cf, seed)
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN[seed % #SKIN + 1]
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.LeftLegColor, desc.RightLegColor = Color3.fromRGB(40, 40, 50), Color3.fromRGB(40, 40, 50)
	desc.TorsoColor = SHIRT[(seed * 3) % #SHIRT + 1]
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then return nil end
	npc.Name = "Cashier"
	local hum = npc:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = "Cashier"
	hum.NameDisplayDistance = 30
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	npc:PivotTo(cf + Vector3.new(0, 2.9, 0))
	for _, p in ipairs(npc:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end
	npc:SetAttribute("Exit6NPC", "cashier")
	npc.Parent = store.model
	return npc
end

-- ---------------------------------------------------------------- purchases
local function menuFor(store)
	local list = {}
	for _, id in ipairs(Catalog.Menus[store.kind] or Catalog.Menus.market) do
		local item = Catalog.Items[id]
		table.insert(list, { id = id, name = item.name, price = item.price })
	end
	return list
end

local function purchase(player, storeId, itemId)
	local store = stores[storeId]
	local item = Catalog.Items[itemId]
	if not store or not item or not ready(player) then return false, "Can't buy that here" end
	local onMenu = false
	for _, id in ipairs(Catalog.Menus[store.kind] or {}) do
		if id == itemId then onMenu = true break end
	end
	if not onMenu then return false, "Not sold here" end
	local r = root(player)
	if not r or (r.Position - store.counter.Position).Magnitude > REACH then return false, "Walk up to the counter" end
	local cash = stats(player)
	if not cash or cash.Value < item.price then return false, "Not enough Chester Cash" end
	if item.kind == "vehicle" then
		-- dealership: into the garage (Exit6Vehicles calls it from the phone)
		local prof = Profile.Get(player)
		local spec = Catalog.Vehicles[item.model]
		if not prof or not spec then return false, "Can't buy that here" end
		if prof.vehicles[item.model] then return false, "You already own a " .. spec.name end
		prof.vehicles[item.model] = { fuel = spec.tank }
		prof.active = item.model
		Profile.Publish(player)
		cash.Value -= item.price
		notify(player, "Bought the " .. item.name .. "! Call it from your phone (Car)")
		return true
	elseif item.kind == "haircut" or item.kind == "clothing" then
		if not Style.Wear(player, itemId) then return false, "Can't do that right now" end
		cash.Value -= item.price
		notify(player, (item.kind == "haircut" and "Fresh cut: " or "Wearing: ") .. item.name ..
			(item.price > 0 and (" (-$" .. item.price .. ")") or ""))
		return true
	end
	if item.kind ~= "service" and not Inventory.Add(player, itemId, 1) then return false, "Your bag is full" end
	cash.Value -= item.price
	if item.kind == "service" then
		notify(player, item.name .. " done (-$" .. item.price .. ")")
	else
		notify(player, "Bought " .. item.name .. " (-$" .. item.price .. ")")
	end
	return true
end
Purchase.OnServerInvoke = function(player, storeId, itemId)
	local ok, why = purchase(player, storeId, itemId)
	if not ok and why then notify(player, why) end
	if ok and stores[storeId] and Catalog.Items[itemId] and Catalog.Items[itemId].price > 0 then
		-- the owner's cut (Exit6Business.server owns this event)
		local Sale = game:GetService("ServerStorage"):FindFirstChild("Exit6Sale")
		if Sale then Sale:Fire(stores[storeId].model, player, Catalog.Items[itemId].price) end
	end
	return ok, why
end

UseItem.OnServerInvoke = function(player, itemId)
	local item = Catalog.Items[itemId]
	if not item or not Inventory.Remove(player, itemId, 1) then return false end
	local verb = (item.kind == "drink") and "Drank" or ((item.kind == "food" or item.kind == "snack") and "Ate" or "Used")
	notify(player, verb .. " " .. item.name)
	return true
end

-- ---------------------------------------------------------------- stock shift
local jobs = {}           -- player -> job
local lastShift = {}      -- userId -> os.clock of the last finished / failed shift
local S = Catalog.StockShift

local function publishJob(player)
	local job = jobs[player]
	if not job then
		player:SetAttribute("Exit6Job", nil)
		return
	end
	player:SetAttribute("Exit6Job", HttpService:JSONEncode({
		type = "stock", store = job.store.title, done = job.done, total = S.crates, carrying = job.carrying,
		deadline = job.deadline,
	}))
end

local function endJob(player, success, why)
	local job = jobs[player]
	if not job then return end
	jobs[player] = nil
	lastShift[player.UserId] = os.clock()
	if job.crate then job.crate:Destroy() end
	if job.carry then job.carry:Destroy() end
	for _, p in ipairs(job.shelfPrompts) do p:Destroy() end
	publishJob(player)
	if success then
		local cash, rep = stats(player)
		local left = math.max(0, job.deadline - Workspace:GetServerTimeNow())
		local bonus = math.floor(S.speedBonus * math.clamp(left / (S.timeLimit / 2), 0, 1) + 0.5)
		if cash then cash.Value += S.basePay + bonus end
		if rep then rep.Value += S.reputation end
		notify(player, string.format("Shift done at %s: +$%d%s, +%d REP", job.store.title, S.basePay + bonus,
			bonus > 0 and (" (incl. $" .. bonus .. " speed bonus)") or "", S.reputation))
	else
		notify(player, why or "Shift failed - the shelves weren't stocked in time")
	end
end

local function spawnCrate(player)
	local job = jobs[player]
	local store = job.store
	local crate = Instance.new("Part")
	crate.Name = "StockCrate"
	crate.Size = Vector3.new(2.6, 2, 2)
	crate.Color = Color3.fromRGB(160, 120, 74)
	crate.Material = Enum.Material.Wood
	crate.Anchored = true
	crate.CFrame = store.backRoom
	crate.Parent = store.model
	local p = prompt(crate, "Pick up crate", "Stock room", 0.4)
	p.Triggered:Connect(function(who)
		if who ~= player or jobs[player] ~= job or job.carrying then return end
		job.carrying = true
		crate:Destroy()
		job.crate = nil
		-- carry it in front of the player
		local r = root(player)
		if r then
			local box = Instance.new("Part")
			box.Name = "CarriedCrate"
			box.Size = Vector3.new(2.2, 1.6, 1.6)
			box.Color = crate.Color
			box.Material = Enum.Material.Wood
			box.CanCollide = false
			box.Massless = true
			box.CFrame = r.CFrame * CFrame.new(0, 0, -1.8)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = r, box
			weld.Parent = box
			box.Parent = player.Character
			job.carry = box
		end
		publishJob(player)
	end)
	job.crate = crate
end

local function startJob(player, store)
	-- one job at a time across the job scripts (Exit6Delivery publishes Exit6Job too)
	if jobs[player] or player:GetAttribute("Exit6Job") then notify(player, "Finish your current job first") return end
	local since = lastShift[player.UserId] and os.clock() - lastShift[player.UserId]
	if since and since < S.cooldown then
		notify(player, "Next shift available in " .. math.ceil(S.cooldown - since) .. "s")
		return
	end
	local job = { store = store, done = 0, carrying = false, shelfPrompts = {},
		deadline = Workspace:GetServerTimeNow() + S.timeLimit }
	jobs[player] = job
	for _, shelf in ipairs(store.shelves) do
		local p = prompt(shelf, "Stock shelf", "Shelf", 0.6)
		p.Triggered:Connect(function(who)
			if who ~= player or jobs[player] ~= job or not job.carrying then return end
			job.carrying = false
			if job.carry then job.carry:Destroy() job.carry = nil end
			job.done += 1
			if job.done >= S.crates then
				endJob(player, true)
			else
				spawnCrate(player)
				publishJob(player)
			end
		end)
		table.insert(job.shelfPrompts, p)
	end
	spawnCrate(player)
	publishJob(player)
	notify(player, "Stock shift started: carry " .. S.crates .. " crates from the back room to the shelves")
	task.delay(S.timeLimit, function()
		if jobs[player] == job then endJob(player, false) end
	end)
end

-- phone: Job > Quit
local QuitJob = remote("RemoteEvent", "QuitJob")
QuitJob.OnServerEvent:Connect(function(player)
	if jobs[player] then endJob(player, false, "You quit the shift") end
end)

Players.PlayerRemoving:Connect(function(player)
	if jobs[player] then
		local job = jobs[player]
		jobs[player] = nil
		if job.crate then job.crate:Destroy() end
		for _, p in ipairs(job.shelfPrompts) do p:Destroy() end
	end
end)

-- ---------------------------------------------------------------- stores
local function setup(model)
	if model:GetAttribute("Exit6StoreId") then return end
	local t0 = os.clock()
	while model.Parent and model:GetAttribute("Exit6InteriorReady") ~= true and os.clock() - t0 < 120 do
		task.wait(0.5)
	end
	local interior = model:FindFirstChild("Exit6Storefront")
	local anchor = model:FindFirstChild("Exit6StoreAnchor", true)
	if not interior or not anchor then return end
	local counter = interior:FindFirstChild("Counter")
	local register = interior:FindFirstChild("CashRegister")
	if not counter or not register then return end
	nextId += 1
	local id = "store" .. nextId
	model:SetAttribute("Exit6StoreId", id)
	local isGas = CollectionService:HasTag(model, "Exit6GasStation")
	local title = model:GetAttribute("ShopName") or model:GetAttribute("BrandName") or model.Name
	local w = model:GetAttribute("Exit6StoreWidth") or 26
	local d = model:GetAttribute("Exit6StoreDepth") or 22
	local shelves = {}
	for _, p in ipairs(interior:GetChildren()) do
		if p.Name == "MerchandiseShelf" then table.insert(shelves, p) end
	end
	local store = {
		model = model, title = title, kind = Catalog.KindFor(title, isGas), counter = counter, shelves = shelves,
		-- back room: the far corner from the door
		backRoom = anchor.CFrame * CFrame.new(math.clamp(w / 2 - 3, 2, 12), 1.1, math.clamp(d / 2 - 3, 2, 14)),
	}
	stores[id] = store
	model:SetAttribute("Exit6StoreKind", store.kind)
	-- the cashier stands behind the counter, facing the door (anchor -Z)
	local behind = counter.CFrame * CFrame.new(0, -counter.Size.Y / 2, counter.Size.Z / 2 + 2)
	local face = CFrame.lookAt(behind.Position, behind.Position + anchor.CFrame.LookVector)
	-- the cashier is spawned while a player is nearby (see the loop below):
	-- ~360 stores city-wide, so not 360 Humanoids at once
	store.cashierCf, store.seed = face, nextId
	local buy = prompt(register, "Buy", title, 0)
	buy.Triggered:Connect(function(player)
		if not ready(player) then return end
		ShopOpen:FireClient(player, { storeId = id, title = title, kind = store.kind, items = menuFor(store),
			pos = counter.Position })
	end)
	if Catalog.JobKinds[store.kind] and #shelves > 0 then
		local job = prompt(counter, "Start stock shift", title, 0.5)
		job.KeyboardKeyCode = Enum.KeyCode.F
		job.GamepadKeyCode = Enum.KeyCode.ButtonX
		job.Triggered:Connect(function(player)
			if ready(player) then startJob(player, store) end
		end)
	end
end

-- Generic city shops get a compact walk-in fit-out only while players are nearby.
-- The existing storefront shell, glass entrance and shop menu remain untouched.
-- No NPCs or permanent citywide interior geometry.
local function simpleInterior(store)
 local door=store.counter
 if not door or not door.Parent then return end
 local model=Instance.new("Model")
 model.Name="Exit6LocalMarketInterior"
 model.Parent=store.model
 local function fixture(name,size,x,y,z,color,material)
  local p=Instance.new("Part")
  p.Name=name;p.Size=size;p.Anchored=true
  p.CanCollide=false;p.CanTouch=false
  p.Material=material or Enum.Material.SmoothPlastic
  p.Color=color
  -- Door CFrame's positive Z points into the shop, negative Z to street.
  p.CFrame=door.CFrame*CFrame.new(x,y,z)
  p.Parent=model
  return p
 end
 -- Place compact displays against the sides; keep the entrance and centre aisle clear.
 local ground=-door.Size.Y/2+0.8
 fixture("CheckoutCounter",Vector3.new(3.2,2.7,1.6),-3.8,ground+1.35,4.8,Color3.fromRGB(90,67,48),Enum.Material.Wood)
 fixture("CashRegister",Vector3.new(1.1,0.65,0.8),-3.8,ground+3.0,4.8,Color3.fromRGB(42,44,48))
 fixture("DisplayShelf",Vector3.new(1.6,4.5,4),4.2,ground+2.25,6.5,Color3.fromRGB(65,70,76),Enum.Material.Metal)
 fixture("StockDisplay",Vector3.new(1.3,1,2.6),4.2,ground+3.0,6.5,Color3.fromRGB(178,92,48))
 store.interior=model
end

-- Unnamed city storefronts use their existing glass door as a shop counter.
-- No new physical parts, interiors, or cashier NPCs are spawned.
local function setupSimple(model)
 if not model.Parent or model:GetAttribute("Exit6StoreId") then return end
 local ref = model:FindFirstChild("Exit6ShopDoor")
 local door = ref and ref.Value
 if not door or not door.Parent then return end
 nextId += 1
 local id = "store" .. nextId
 local title = model:GetAttribute("ShopName") or "Neighborhood Market"
 local store = { model = model, title = title, kind = "market", counter = door, shelves = {}, simple = true }
 stores[id] = store
 model:SetAttribute("Exit6StoreId", id)
 model:SetAttribute("Exit6StoreKind", "market")
 local buy = prompt(door, "Shop", title, 0)
 buy.Triggered:Connect(function(player)
  if not ready(player) then return end
  local r = root(player)
  if not r or (r.Position - door.Position).Magnitude > REACH then return end
  ShopOpen:FireClient(player, { storeId = id, title = title, kind = "market",
   items = menuFor(store), pos = door.Position })
 end)
 model.Destroying:Connect(function() stores[id] = nil end)
end
for _, m in ipairs(CollectionService:GetTagged("Exit6SimpleStore")) do setupSimple(m) end
CollectionService:GetInstanceAddedSignal("Exit6SimpleStore"):Connect(setupSimple)

for _, tag in ipairs({ "Exit6GasStation", "Exit6Store" }) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do task.spawn(setup, m) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m) task.spawn(setup, m) end)
end

-- cashiers come and go with the players: a store within CASHIER_NEAR of anyone
-- gets its cashier, one nobody has been near for a while loses it
local CASHIER_NEAR, CASHIER_FAR = 220, 320
task.spawn(function()
	while true do
		task.wait(2)
		local roots = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local r = root(pl)
			if r then table.insert(roots, r.Position) end
		end
		local n = 0
		for _, store in pairs(stores) do
			if store.simple and store.model.Parent and store.counter.Parent then
				local nearest = math.huge
				for _, rp in ipairs(roots) do
					nearest = math.min(nearest, (rp - store.counter.Position).Magnitude)
				end
				if nearest < 85 and not (store.interior and store.interior.Parent) then
					simpleInterior(store)
				elseif nearest > 120 and store.interior then
					store.interior:Destroy()
					store.interior = nil
				end
			end
			if store.cashierCf and store.model.Parent then
				local p = store.counter.Position
				local nearest = math.huge
				for _, rp in ipairs(roots) do nearest = math.min(nearest, (rp - p).Magnitude) end
				if nearest < CASHIER_NEAR and not (store.npc and store.npc.Parent) then
					store.npc = cashier(store, store.cashierCf, store.seed)
					n += 1
					if n % 4 == 0 then task.wait() end
				elseif nearest > CASHIER_FAR and store.npc then
					store.npc:Destroy()
					store.npc = nil
				end
			end
		end
	end
end)
