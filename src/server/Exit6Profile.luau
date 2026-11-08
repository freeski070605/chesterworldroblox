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
--   music    = { pen, flow, beats (skills 0-100), fans, tracks = { { name, q, rel, streams } } }
--   hoops    = { makes, wins }    trials = { [routeId] = best seconds }    pens = { best }
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
		music = { pen = 0, flow = 0, beats = 0, fans = 0, tracks = {} },
		hoops = { makes = 0, wins = 0 },
		trials = {},
		pens = { best = 0 },
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
		local function num(v, lo, hi) return math.clamp(tonumber(v) or 0, lo, hi) end
		if type(saved.music) == "table" then
			local m = saved.music
			p.music.pen, p.music.flow, p.music.beats = num(m.pen, 0, 100), num(m.flow, 0, 100), num(m.beats, 0, 100)
			p.music.fans = math.floor(num(m.fans, 0, 1e9))
			if type(m.tracks) == "table" then
				for i, t in ipairs(m.tracks) do
					if i > 20 then break end
					if type(t) == "table" then
						table.insert(p.music.tracks, { name = tostring(t.name or ("Track " .. i)):sub(1, 40), q = num(t.q, 0, 100),
							rel = t.rel and math.floor(num(t.rel, 0, 1e10)) or nil, streams = math.floor(num(t.streams, 0, 1e12)) })
					end
				end
			end
		end
		if type(saved.hoops) == "table" then
			p.hoops.makes, p.hoops.wins = math.floor(num(saved.hoops.makes, 0, 1e9)), math.floor(num(saved.hoops.wins, 0, 1e9))
		end
		if type(saved.trials) == "table" then
			for k, v in pairs(saved.trials) do
				if type(k) == "string" and tonumber(v) then p.trials[k] = num(v, 1, 36000) end
			end
		end
		if type(saved.pens) == "table" then p.pens.best = math.floor(num(saved.pens.best, 0, 5)) end
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
