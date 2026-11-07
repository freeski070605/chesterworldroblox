-- EXIT 6 player profile (server-owned): the parts of a player's life that are
-- not cash / reputation / bag. Saved by Exit6Gameplay.server.luau with the
-- rest of the player's data (one save manager). The owning client sees a copy
-- as the JSON attribute Exit6Profile (phone apps).
--
--   vehicles = { [modelId] = { fuel = gallons } }   active = modelId
--   style    = { hair, top, bottom, hat }            (catalog item ids)
--   home     = { id = "building:door", street = "..." }
--   stash    = { [itemId] = count }                 (kept at home)
--   business = { [storeKey] = { name, kind, bank } }
local HttpService = game:GetService("HttpService")
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Exit6Catalog"))

local Profile = {}
local data = {}
local loaded = Instance.new("BindableEvent")
Profile.Loaded = loaded.Event   -- (player, profile)

local function fresh()
	local starter = Catalog.StarterVehicle
	return {
		vehicles = { [starter] = { fuel = Catalog.Vehicles[starter].tank } },
		active = starter,
		style = {},
		home = nil,
		stash = {},
		business = {},
	}
end

function Profile.Publish(player)
	local p = data[player]
	if p then player:SetAttribute("Exit6Profile", HttpService:JSONEncode(p)) end
end

-- saved table -> session; unknown vehicles / items from older catalogs are dropped
function Profile.Import(player, saved)
	local p = fresh()
	if type(saved) == "table" then
		if type(saved.vehicles) == "table" then
			for id, v in pairs(saved.vehicles) do
				local spec = Catalog.Vehicles[id]
				if spec and type(v) == "table" then
					p.vehicles[id] = { fuel = math.clamp(tonumber(v.fuel) or spec.tank, 0, spec.tank) }
				end
			end
		end
		if type(saved.active) == "string" and p.vehicles[saved.active] then p.active = saved.active end
		if type(saved.style) == "table" then
			for _, slot in ipairs({ "hair", "top", "bottom", "hat" }) do
				local id = saved.style[slot]
				if type(id) == "string" and Catalog.Items[id] then p.style[slot] = id end
			end
		end
		if type(saved.home) == "table" and type(saved.home.id) == "string" then
			p.home = { id = saved.home.id, street = tostring(saved.home.street or "") }
		end
		if type(saved.stash) == "table" then
			for id, n in pairs(saved.stash) do
				if Catalog.Items[id] and type(n) == "number" and n > 0 then p.stash[id] = math.min(math.floor(n), 999) end
			end
		end
		if type(saved.business) == "table" then
			for key, b in pairs(saved.business) do
				if type(key) == "string" and type(b) == "table" then
					p.business[key] = { name = tostring(b.name or key), kind = tostring(b.kind or "market"),
						bank = math.max(0, math.floor(tonumber(b.bank) or 0)) }
				end
			end
		end
	end
	data[player] = p
	Profile.Publish(player)
	loaded:Fire(player, p)
end

function Profile.Get(player)
	return data[player]
end

function Profile.Export(player)
	local p = data[player]
	return p and HttpService:JSONDecode(HttpService:JSONEncode(p)) or nil
end

function Profile.Forget(player)
	data[player] = nil
end

return Profile
