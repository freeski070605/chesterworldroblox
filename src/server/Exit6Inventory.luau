-- EXIT 6 player inventory (server-owned). Saved with cash and reputation by
-- Exit6Gameplay.server.luau (one save manager); replicated to the player's own
-- client as the JSON attribute Exit6Inventory (the phone's Bag).
local HttpService = game:GetService("HttpService")
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Exit6Catalog"))

local Inventory = {}
local bags = {}
local MAX_STACK = 99

local function publish(player)
	local bag = bags[player]
	if bag then player:SetAttribute("Exit6Inventory", HttpService:JSONEncode(bag)) end
end

-- saved table -> session (unknown item ids from older catalogs are dropped)
function Inventory.Import(player, saved)
	local bag = {}
	if type(saved) == "table" then
		for id, n in pairs(saved) do
			if Catalog.Items[id] and type(n) == "number" and n > 0 then
				bag[id] = math.min(math.floor(n), MAX_STACK)
			end
		end
	end
	bags[player] = bag
	publish(player)
end

function Inventory.Export(player)
	return bags[player] and table.clone(bags[player]) or nil
end

function Inventory.Count(player, id)
	return bags[player] and bags[player][id] or 0
end

function Inventory.Add(player, id, n)
	local bag = bags[player]
	if not bag or not Catalog.Items[id] then return false end
	local have = bag[id] or 0
	if have + n > MAX_STACK then return false end
	bag[id] = have + n
	publish(player)
	return true
end

function Inventory.Remove(player, id, n)
	local bag = bags[player]
	if not bag or (bag[id] or 0) < n then return false end
	bag[id] -= n
	if bag[id] <= 0 then bag[id] = nil end
	publish(player)
	return true
end

function Inventory.Forget(player)
	bags[player] = nil
end

return Inventory
