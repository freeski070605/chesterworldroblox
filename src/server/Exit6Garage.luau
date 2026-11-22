-- EXIT 6 garage rules (server only): buying vehicles, Bike Life upgrades and
-- customisation, and the effective stats a ride is built with. One place for
-- the money / reputation / ownership checks, used by the dealership counter
-- (Exit6Shop.server) and the Bike Life kiosk (Exit6BikeLife.server). Every
-- function checks, then debits and grants without yielding in between, so two
-- requests can never both pass the same check.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Catalog"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))

local Garage = {}
local BL = Catalog.BikeLife

local function stats(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
end
local function ready(player)
	return player:GetAttribute("Exit6DataReady") == true and Profile.Get(player) ~= nil
end

-- a fresh garage record; Bike Life rides also carry looks and upgrades
function Garage.NewRecord(player, modelId)
	local spec = Catalog.Vehicles[modelId]
	local rec = { fuel = spec.tank }
	if spec.rideType then
		rec.paint, rec.accent, rec.number = 0, 1, (player.UserId % 99) + 1
		rec.engine, rec.handling = 0, 0
	end
	return rec
end

-- the ride's numbers with its upgrades applied
function Garage.Effective(modelId, rec)
	local spec = Catalog.Vehicles[modelId]
	if not spec or not spec.rideType then return nil end
	local e = math.clamp((rec and rec.engine) or 0, 0, BL.upgrades.engine.maxLevel)
	local h = math.clamp((rec and rec.handling) or 0, 0, BL.upgrades.handling.maxLevel)
	local U = BL.upgrades
	return {
		topSpeed = spec.topSpeed * (1 + U.engine.topSpeed * e),
		accel = spec.accel * (1 + U.engine.accel * e),
		brake = spec.brake,
		grip = spec.grip * (1 + U.handling.grip * h),
		steerLock = spec.steerLock * (1 + U.handling.steer * h),
		wheelie = spec.wheelie * (1 + U.handling.wheelie * h),
	}
end

function Garage.Owns(player, modelId)
	local p = Profile.Get(player)
	return p ~= nil and p.vehicles[modelId] ~= nil
end

-- buy a vehicle item (Catalog.Items[itemId].kind == "vehicle")
function Garage.Buy(player, itemId)
	local item = Catalog.Items[itemId]
	local spec = item and item.kind == "vehicle" and Catalog.Vehicles[item.model]
	if not spec then return false, "Can't buy that here" end
	if not ready(player) then return false, "Still loading your save" end
	local prof = Profile.Get(player)
	local cash, rep = stats(player)
	if not cash or not rep then return false, "Still loading your save" end
	if prof.vehicles[item.model] then return false, "You already own the " .. spec.name end
	if item.repRequired and rep.Value < item.repRequired then
		return false, "Requires " .. item.repRequired .. " reputation (you have " .. rep.Value .. ")"
	end
	if cash.Value < item.price then return false, "Not enough Chester Cash ($" .. item.price .. ")" end
	cash.Value -= item.price
	prof.vehicles[item.model] = Garage.NewRecord(player, item.model)
	prof.active = item.model
	Profile.Publish(player)
	return true, "Bought the " .. item.name .. "! Call it from your phone (Car)"
end

function Garage.UpgradePrice(modelId, kind, level)
	local item
	for _, it in pairs(Catalog.Items) do
		if it.kind == "vehicle" and it.model == modelId then item = it break end
	end
	local U = BL.upgrades[kind]
	if not item or not U or level < 1 or level > U.maxLevel then return nil end
	return math.floor(item.price * U.priceFactor[level] / 10 + 0.5) * 10, U.rep[level]
end

function Garage.Upgrade(player, modelId, kind)
	local spec = Catalog.Vehicles[modelId]
	local U = BL.upgrades[kind]
	if not spec or not spec.rideType or not U then return false, "Can't upgrade that" end
	if not ready(player) then return false, "Still loading your save" end
	local prof = Profile.Get(player)
	local rec = prof.vehicles[modelId]
	if not rec then return false, "You don't own the " .. spec.name end
	local level = (rec[kind] or 0) + 1
	if level > U.maxLevel then return false, U.name .. " is maxed out" end
	local price, repNeed = Garage.UpgradePrice(modelId, kind, level)
	local cash, rep = stats(player)
	if not price or not cash or not rep then return false, "Can't upgrade that" end
	if rep.Value < repNeed then return false, "Stage " .. level .. " needs " .. repNeed .. " reputation" end
	if cash.Value < price then return false, "Not enough Chester Cash ($" .. price .. ")" end
	cash.Value -= price
	rec[kind] = level
	Profile.Publish(player)
	return true, string.format("%s %s stage %d installed (-$%d). Re-call it to ride the upgrade.", spec.name, U.name, level, price)
end

-- field: "paint" (0..#paints), "accent" (1..#accents), "number" (0..99)
function Garage.Customize(player, modelId, field, value)
	local spec = Catalog.Vehicles[modelId]
	if not spec or not spec.rideType then return false, "Can't customise that" end
	if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then return false, "Can't customise that" end
	if not ready(player) then return false, "Still loading your save" end
	local rec = Profile.Get(player).vehicles[modelId]
	if not rec then return false, "You don't own the " .. spec.name end
	local price, ok
	if field == "paint" then
		ok, price = value >= 0 and value <= #BL.paints, BL.paintPrice
	elseif field == "accent" then
		ok, price = value >= 1 and value <= #BL.accents, BL.accentPrice
	elseif field == "number" then
		ok, price = value >= 0 and value <= 99, BL.numberPrice
	end
	if not ok then return false, "Can't customise that" end
	if rec[field] == value then return false, "Already set" end
	local cash = stats(player)
	if not cash or cash.Value < price then return false, "Not enough Chester Cash ($" .. price .. ")" end
	cash.Value -= price
	rec[field] = value
	Profile.Publish(player)
	return true, string.format("%s updated (-$%d). Re-call it to see the new look.", spec.name, price)
end

return Garage
