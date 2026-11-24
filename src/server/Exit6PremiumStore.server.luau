-- EXIT 6 Premium store (server): Robux purchases, permanent entitlements,
-- receipts, boutique try-on.
--
-- Entitlements live in their own DataStore (not the player profile), keyed
-- "u_<userId>":
--   { v = 1, skus = { [sku] = true }, items = { [itemId] = true },
--     receipts = { [PurchaseId] = { sku, p = productId, r = robux, t = os.time() } },
--     log = { PurchaseId, ... } }   (newest RECEIPT_KEEP receipts kept)
-- A purchase is written with UpdateAsync (idempotent on PurchaseId) BEFORE
-- the receipt is acknowledged, so a crash or failed profile save never loses
-- a paid item, and a re-delivered receipt never double-grants.
-- On join (after Exit6Profile loads) the entitlements are granted into the
-- session's style.owned; Exit6Profile strips premium ownership from the
-- profile itself, so ownership can only come from here.
--
-- Studio: products without a developer product id (productId = 0) can be
-- test-bought through the same grant path; Studio writes to a separate
-- "_studio" store so test grants never reach live data.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Premium = require(Shared:WaitForChild("Exit6Premium"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Style = require(script.Parent:WaitForChild("Exit6Style"))
local Receipts = require(script.Parent:WaitForChild("Exit6Receipts"))

if not Premium.Enabled then return end

local STUDIO = RunService:IsStudio()
local STORE_NAME = "Exit6Entitlements_v1" .. (STUDIO and "_studio" or "")
local RECEIPT_KEEP = 300
local store = DataStoreService:GetDataStore(STORE_NAME)

-- ---------------------------------------------------------------- catalog checks
-- a grant may only hold premium cosmetics: no cash, reputation, vehicles or
-- reputation-gated items can ever be bought with Robux here
local GRANTS = {}
for sku, p in pairs(Premium.Products) do
	local list = {}
	for _, id in ipairs(p.grants) do
		local it = Catalog.Items[id]
		if it and it.kind == "wear" and it.premium and not it.repRequired then
			table.insert(list, id)
		else
			warn("[Exit6Premium] " .. sku .. ": dropped non-cosmetic grant " .. tostring(id))
		end
	end
	GRANTS[sku] = list
end

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end

-- ---------------------------------------------------------------- session state
local ent = {}       -- player -> { skus = {}, items = {} } (copy of the saved record)
local status = {}    -- player -> "loading" | "ready" | "failed"

local function blank()
	return { v = 1, skus = {}, items = {}, receipts = {}, log = {} }
end

local function ownsAll(player, sku)
	local e = ent[player]
	if not e then return false end
	for _, id in ipairs(GRANTS[sku] or {}) do
		if not e.items[id] then return false end
	end
	return true
end

local function available(sku)
	for _, id in ipairs(GRANTS[sku] or {}) do
		if not Style.ItemReady(id) then return false, id end
	end
	return #(GRANTS[sku] or {}) > 0
end

local function publish(player)
	local e = ent[player]
	local owned = {}
	if e then
		for sku in pairs(Premium.Products) do
			if ownsAll(player, sku) then owned[sku] = true end
		end
	end
	player:SetAttribute("Exit6Premium", HttpService:JSONEncode({ status = status[player], owned = owned }))
end

-- entitlements -> the session's wardrobe ownership
local function applyOwnership(player)
	local e = ent[player]
	if not e or not Profile.Get(player) then return end
	for id in pairs(e.items) do
		local it = Catalog.Items[id]
		if it and it.premium then Style.Grant(player, id) end
	end
	Profile.Publish(player)
	Style.Apply(player)
	publish(player)
end

local function load(player)
	if status[player] == "loading" then return end
	if ent[player] then
		-- profile re-imported this session: re-grant from the cached record
		applyOwnership(player)
		return
	end
	status[player] = "loading"
	publish(player)
	local data, ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function() data = store:GetAsync("u_" .. player.UserId) end)
		if ok then break end
		task.wait(attempt * 2)
	end
	if not player.Parent then return end
	if not ok then
		if STUDIO then
			warn("[Exit6Premium] entitlements DataStore unavailable in Studio; unsaved test session: " .. tostring(err))
			data = nil
		else
			warn("[Exit6Premium] entitlement load failed for " .. player.UserId .. ": " .. tostring(err))
			status[player] = "failed"
			publish(player)
			-- retry later; purchases stay blocked until ownership is known
			task.delay(30, function()
				if player.Parent and status[player] == "failed" then
					status[player] = nil
					load(player)
				end
			end)
			return
		end
	end
	local rec = type(data) == "table" and data or blank()
	ent[player] = { skus = type(rec.skus) == "table" and rec.skus or {}, items = type(rec.items) == "table" and rec.items or {} }
	status[player] = "ready"
	applyOwnership(player)
end

Profile.Loaded:Connect(function(player) task.spawn(load, player) end)
for _, pl in ipairs(Players:GetPlayers()) do
	if Profile.Get(pl) then task.spawn(load, pl) end
end
Players.PlayerRemoving:Connect(function(player)
	ent[player] = nil
	status[player] = nil
end)

-- ---------------------------------------------------------------- receipts
-- record one purchase; returns true once it is safely stored (new or a repeat)
local function record(userId, sku, purchaseId, productId, robux)
	local stored = false
	local ok, err = pcall(function()
		store:UpdateAsync("u_" .. userId, function(old)
			local rec = type(old) == "table" and old or blank()
			rec.skus = type(rec.skus) == "table" and rec.skus or {}
			rec.items = type(rec.items) == "table" and rec.items or {}
			rec.receipts = type(rec.receipts) == "table" and rec.receipts or {}
			rec.log = type(rec.log) == "table" and rec.log or {}
			if rec.receipts[purchaseId] then
				stored = true
				return nil  -- already granted: no write
			end
			rec.receipts[purchaseId] = { sku = sku, p = productId, r = robux, t = os.time() }
			table.insert(rec.log, purchaseId)
			while #rec.log > RECEIPT_KEEP do
				rec.receipts[table.remove(rec.log, 1)] = nil
			end
			rec.skus[sku] = true
			for _, id in ipairs(GRANTS[sku]) do rec.items[id] = true end
			rec.v = 1
			stored = true
			return rec
		end)
	end)
	if not ok then
		warn("[Exit6Premium] receipt write failed (" .. tostring(purchaseId) .. "): " .. tostring(err))
		if STUDIO then return "studio" end  -- Studio without API access: grant for this session only
		return false
	end
	return stored
end

local function grantPurchase(info, sku)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local stored = record(info.PlayerId, sku, info.PurchaseId, info.ProductId, info.CurrencySpent or 0)
	if not stored then return false end
	if player and status[player] ~= "ready" then
		-- ownership was never loaded this session: load the whole record
		-- (which now includes this purchase) rather than a partial one
		ent[player] = nil
		status[player] = nil
		task.spawn(load, player)
	elseif player then
		ent[player].skus[sku] = true
		for _, id in ipairs(GRANTS[sku]) do ent[player].items[id] = true end
		applyOwnership(player)
		Style.EquipMany(player, GRANTS[sku])
		notify(player, "EXIT 6 Premium: " .. Premium.Products[sku].name .. " is yours" ..
			(stored == "studio" and " (Studio test, not saved)" or ""))
	end
	print(("[Exit6Premium] granted %s to %d (purchase %s, R$%d)"):format(sku, info.PlayerId, tostring(info.PurchaseId),
		info.CurrencySpent or 0))
	return true
end

for sku, p in pairs(Premium.Products) do
	if p.productId ~= 0 then
		Receipts.Register(p.productId, function(info) return grantPurchase(info, sku) end)
	end
end

-- live prices (from the configured developer products)
local prices = {}
local function priceOf(sku)
	local p = Premium.Products[sku]
	if p.productId == 0 then return p.robux, false end
	if prices[sku] == nil then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(p.productId, Enum.InfoType.Product)
		end)
		prices[sku] = (ok and info and info.PriceInRobux) or false
	end
	return prices[sku] or p.robux, prices[sku] ~= false
end

-- ---------------------------------------------------------------- boutique remote
local Action = Instance.new("RemoteFunction")
Action.Name = "Exit6PremiumAction"
Action.Parent = ReplicatedStorage
local last = {}

Action.OnServerInvoke = function(player, verb, sku)
	if type(verb) ~= "string" then return false, "Bad request" end
	local now = os.clock()
	if verb ~= "catalog" then
		if last[player] and now - last[player] < 0.25 then return false, "Wait a moment" end
		last[player] = now
	end
	if verb == "catalog" then
		local list = {}
		for _, id in ipairs(Premium.Order) do
			local p = Premium.Products[id]
			local price, live = priceOf(id)
			local ready = available(id)
			list[id] = {
				price = price, live = live, ready = ready, owned = ownsAll(player, id),
				buyable = ready and (p.productId ~= 0 or (STUDIO and Premium.StudioTestPurchases)),
				test = p.productId == 0 and STUDIO and Premium.StudioTestPurchases,
			}
		end
		return true, { status = status[player], products = list }
	end
	if verb == "cancel" then
		Style.CancelPreview(player)
		return true
	end
	local p = type(sku) == "string" and Premium.Products[sku]
	if not p then return false, "Unknown item" end
	if verb == "tryon" then
		if not available(sku) then return false, "Not available yet" end
		local look = {}
		for _, id in ipairs(GRANTS[sku]) do
			local it = Catalog.Items[id]
			if look[it.slot] == nil then look[it.slot] = id end
		end
		return Style.PreviewLook(player, look)
	elseif verb == "wear" then
		local e = ent[player]
		local mine = {}
		for _, id in ipairs(GRANTS[sku]) do
			if e and e.items[id] then table.insert(mine, id) end
		end
		if #mine == 0 then return false, "You don't own that yet" end
		return Style.EquipMany(player, mine)
	elseif verb == "buy" then
		if status[player] ~= "ready" then return false, "Still loading your purchases" end
		if not available(sku) then return false, "Not available yet" end
		if ownsAll(player, sku) then return false, "You already own this" end
		if p.productId ~= 0 then
			MarketplaceService:PromptProductPurchase(player, p.productId)
			return true, "prompted"
		elseif STUDIO and Premium.StudioTestPurchases then
			-- same path as a real receipt, with a test purchase id
			local ok = grantPurchase({ PlayerId = player.UserId, ProductId = 0, CurrencySpent = p.robux,
				PurchaseId = "studio-" .. HttpService:GenerateGUID(false) }, sku)
			return ok, ok and "granted" or "Purchase failed"
		end
		return false, "Coming soon"
	end
	return false, "Unknown action"
end
Players.PlayerRemoving:Connect(function(player) last[player] = nil end)

task.defer(function()
	local missing = {}
	for _, sku in ipairs(Premium.Order) do
		local ok, mesh = available(sku)
		if not ok then table.insert(missing, sku .. " (" .. tostring(mesh) .. ")") end
	end
	if #missing > 0 then
		warn("[Exit6Premium] not on sale until installed (tools/studio/install_exit6_premium.luau): "
			.. table.concat(missing, ", "))
	end
	local configured = 0
	for _, p in pairs(Premium.Products) do
		if p.productId ~= 0 then configured += 1 end
	end
	print(("[Exit6Premium] %d products, %d with developer product ids, store %s"):format(#Premium.Order, configured, STORE_NAME))
end)
