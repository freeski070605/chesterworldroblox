-- EXIT 6 player profile (server-owned): the parts of a player's life that are
-- not cash / reputation / bag. Saved by Exit6Gameplay.server.luau with the
-- rest of the player's data (one save manager). The owning client sees a copy
-- as the JSON attribute Exit6Profile (phone apps).
--
--   vehicles = { [modelId] = { fuel = gallons } }   active = modelId
--              Bike Life rides also: paint (0 = factory), accent, number,
--              engine / handling (upgrade stages)
--   bikeLife = { bestWheelie (s), totalWheelie (s), rideouts, finished, bestRide (points) }
--   style    = { v, owned = { [itemId] = true }, hair, hat, top, bottom, shoes,
--                chain, neck, watch, bracelet, ears, eyes }   (Exit6Wardrobe ids)
--   home     = { id = "building:door", street = "..." }
--   stash    = { [itemId] = count }                 (kept at home)
--   business = { [storeKey] = { name, kind, bank } }
--   music    = { pen, flow, beats (skills 0-100), fans, tracks = { { name, q, rel, streams } } }
--   hoops    = { makes, wins }    trials = { [routeId] = best seconds }    pens = { best }
local HttpService = game:GetService("HttpService")
local Catalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Exit6Catalog"))

local Wardrobe = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Exit6Wardrobe"))

local Profile = {}
local data = {}
local STYLE_VERSION = 2
local MAX_OWNED = 400

-- saved style -> session: slot ids must be wearables for that slot (old
-- part-built / Hair Test ids map through Wardrobe.Legacy and count as owned)
local function importStyle(dst, src)
	local owned = type(src.owned) == "table" and src.owned or {}
	local n = 0
	for id, v in pairs(owned) do
		local it = type(id) == "string" and Catalog.Items[id]
		if v == true and it and it.kind == "wear" and n < MAX_OWNED then
			dst.owned[id] = true
			n += 1
		end
	end
	for _, slot in ipairs(Wardrobe.Slots) do
		local id = src[slot]
		if type(id) == "string" then
			id = Wardrobe.Legacy[id] or id
			local it = Catalog.Items[id]
			if it and it.kind == "wear" and it.slot == slot then
				dst[slot] = id
				dst.owned[id] = true
			end
		end
	end
	if src.v == STYLE_VERSION then dst.v = STYLE_VERSION end
end
local loaded = Instance.new("BindableEvent")
Profile.Loaded = loaded.Event   -- (player, profile)

local function fresh()
	local starter = Catalog.StarterVehicle
	return {
		vehicles = { [starter] = { fuel = Catalog.Vehicles[starter].tank } },
		active = starter,
		style = { owned = {} },
		home = nil,
		stash = {},
		business = {},
		music = { pen = 0, flow = 0, beats = 0, fans = 0, tracks = {} },
		hoops = { makes = 0, wins = 0 },
		bikeLife = { bestWheelie = 0, totalWheelie = 0, rideouts = 0, finished = 0, bestRide = 0 },
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
					if spec.rideType then
						local BL = Catalog.BikeLife
						local function int(x, lo, hi, d) return math.clamp(math.floor(tonumber(x) or d), lo, hi) end
						local rec = p.vehicles[id]
						rec.paint = int(v.paint, 0, #BL.paints, 0)
						rec.accent = int(v.accent, 1, #BL.accents, 1)
						rec.number = int(v.number, 0, 99, (player.UserId % 99) + 1)
						rec.engine = int(v.engine, 0, BL.upgrades.engine.maxLevel, 0)
						rec.handling = int(v.handling, 0, BL.upgrades.handling.maxLevel, 0)
					end
				end
			end
		end
		if type(saved.active) == "string" and p.vehicles[saved.active] then p.active = saved.active end
		if type(saved.style) == "table" then importStyle(p.style, saved.style) end
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
		if type(saved.bikeLife) == "table" then
			local b = saved.bikeLife
			p.bikeLife.bestWheelie = math.floor(num(b.bestWheelie, 0, 3600) * 10 + 0.5) / 10
			p.bikeLife.totalWheelie = math.floor(num(b.totalWheelie, 0, 1e7))
			p.bikeLife.rideouts = math.floor(num(b.rideouts, 0, 100000))
			p.bikeLife.finished = math.floor(num(b.finished, 0, 100000))
			p.bikeLife.bestRide = math.floor(num(b.bestRide, 0, 1e7))
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
	if p.style.v ~= STYLE_VERSION then
		-- first load on the mesh wardrobe: everyone owns the starter fit, and
		-- whoever never picked a look wears it
		for slot, id in pairs(Wardrobe.Starter) do
			p.style.owned[id] = true
			if p.style[slot] == nil then p.style[slot] = id end
		end
		p.style.v = STYLE_VERSION
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
