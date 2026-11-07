-- EXIT 6 business ownership (master plan Phase E). Buy a Chester store
-- (phone > Biz while standing in it): its till fills while you're in town
-- (Catalog.Business), plus a cut of what other players spend there
-- (Exit6Shop.server fires Exit6Sale). Collect the till at the store.
-- Ownership is saved in the profile, keyed by the store's stable key.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local BusinessAction = Instance.new("RemoteFunction")
BusinessAction.Name = "BusinessAction"
BusinessAction.Parent = remotes
local Sale = ServerStorage:FindFirstChild("Exit6Sale") or Instance.new("BindableEvent")
Sale.Name = "Exit6Sale"
Sale.Parent = ServerStorage

local B = Catalog.Business
local REACH = 30
local SALE_CUT = 0.2
local stores = {}   -- key -> model

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function keyOf(model)
	local id = model:GetAttribute("StationId") or model:GetAttribute("ChesterBuildingId") or ""
	return tostring(id) .. ":" .. tostring(model:GetAttribute("ShopName") or model.Name)
end
local function priceOf(model)
	local kind = model:GetAttribute("Exit6StoreKind") or "market"
	return B.priceByKind[kind]
end
local function ownerOf(key)
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = Profile.Get(pl)
		if p and p.business[key] then return pl end
	end
	return nil
end
local function markOwners()
	for key, model in pairs(stores) do
		local who = ownerOf(key)
		model:SetAttribute("Exit6OwnerId", who and who.UserId or nil)
		model:SetAttribute("Exit6OwnerName", who and who.DisplayName or nil)
	end
end

local function setup(model)
	local t0 = os.clock()
	while model.Parent and not model:GetAttribute("Exit6StoreKind") and os.clock() - t0 < 200 do task.wait(1) end
	if not model:GetAttribute("Exit6StoreKind") or not priceOf(model) then return end
	local key = keyOf(model)
	model:SetAttribute("Exit6StoreKey", key)
	model:SetAttribute("Exit6StorePrice", priceOf(model))
	stores[key] = model
	markOwners()
end
for _, tag in ipairs({ "Exit6Store", "Exit6GasStation" }) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do task.spawn(setup, m) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m) task.spawn(setup, m) end)
end
Profile.Loaded:Connect(markOwners)
Players.PlayerRemoving:Connect(function() task.defer(markOwners) end)

-- the till fills while the owner is in town
task.spawn(function()
	while true do
		task.wait(60)
		for _, pl in ipairs(Players:GetPlayers()) do
			local p = Profile.Get(pl)
			if p then
				local changed = false
				for key, b in pairs(p.business) do
					local price = B.priceByKind[b.kind] or 5000
					local cap = math.floor(price * B.maxBank)
					local nb = math.min(cap, b.bank + math.max(1, math.floor(price * B.incomePerMinute)))
					if nb ~= b.bank then b.bank = nb changed = true end
				end
				if changed then Profile.Publish(pl) end
			end
		end
	end
end)
-- other players' purchases: the owner's cut goes in the till
Sale.Event:Connect(function(model, buyer, amount)
	local key = model and model:GetAttribute("Exit6StoreKey")
	local owner = key and ownerOf(key)
	if not owner or owner == buyer then return end
	local b = Profile.Get(owner).business[key]
	local cap = math.floor((B.priceByKind[b.kind] or 5000) * B.maxBank)
	b.bank = math.min(cap, b.bank + math.max(1, math.floor(amount * SALE_CUT)))
	Profile.Publish(owner)
end)

local function nearestStore(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local best, bd = nil, REACH
	for key, model in pairs(stores) do
		local a = model:FindFirstChild("Exit6StoreAnchor", true)
		if a then
			local d = (a.Position - root.Position).Magnitude
			if d < bd then best, bd = key, d end
		end
	end
	return best
end

BusinessAction.OnServerInvoke = function(player, action)
	local p = Profile.Get(player)
	if not p or player:GetAttribute("Exit6DataReady") ~= true then return false end
	local key = nearestStore(player)
	local model = key and stores[key]
	if not model then notify(player, "Stand inside a store first") return false end
	if action == "buy" then
		if p.business[key] then notify(player, "You already own it") return false end
		if ownerOf(key) then notify(player, "Someone here already owns it") return false end
		local price = priceOf(model)
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Chester Cash")
		if not cash or cash.Value < price then notify(player, "It costs $" .. price) return false end
		cash.Value -= price
		p.business[key] = { name = model:GetAttribute("ShopName") or model.Name, kind = model:GetAttribute("Exit6StoreKind"), bank = 0 }
		local rep = ls:FindFirstChild("Reputation")
		if rep then rep.Value += 5 end
		Profile.Publish(player)
		markOwners()
		notify(player, "You own " .. p.business[key].name .. " now (+5 REP)")
		return true
	elseif action == "collect" then
		local b = p.business[key]
		if not b then notify(player, "This isn't your store") return false end
		if b.bank <= 0 then notify(player, "The till is empty") return false end
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Chester Cash")
		if cash then cash.Value += b.bank end
		notify(player, "Collected $" .. b.bank .. " from " .. b.name)
		b.bank = 0
		Profile.Publish(player)
		return true
	end
	return false
end
