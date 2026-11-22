-- EXIT 6 Bike Life (server): the Exit 6 Motors bike shop, test rides,
-- server-observed wheelie scoring and multiplayer rideouts.
-- Nothing the client sends is trusted beyond "which button": prices, reach,
-- ownership, positions, wheelie timing and rideout progress are all decided
-- here from the server's own view of the world.
--
-- Remotes (ReplicatedStorage.Exit6Remotes)
--   BikeLifeAction  RemoteFunction (command, value) -> status table
--     status | shop
--     buy itemId | upgrade {model, kind} | custom {model, field, value} | testride modelId   (at the shop)
--     create routeIndex | invite userId | join leaderId | leave | start | finish
--   BikeLifeChanged RemoteEvent -> status table (pushed when something changes)
--   OpenBikeShop    RemoteEvent -> modelId to focus (the kiosk / a display ride was used)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local BikePhysics = require(Shared:WaitForChild("Exit6BikePhysics"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Garage = require(script.Parent:WaitForChild("Exit6Garage"))
local Fleet = require(script.Parent:WaitForChild("Exit6Fleet"))
local BikeBuilder = require(script.Parent:WaitForChild("Exit6BikeBuilder"))
local BL = Catalog.BikeLife

local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local Action = remote("RemoteFunction", "BikeLifeAction")
local Changed = remote("RemoteEvent", "BikeLifeChanged")
local OpenShop = remote("RemoteEvent", "OpenBikeShop")

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function cashRep(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
end
local function rootOf(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- model id -> shop item id
local ITEM_FOR = {}
for itemId, item in pairs(Catalog.Items) do
	if item.kind == "vehicle" and Catalog.Vehicles[item.model] and Catalog.Vehicles[item.model].rideType then
		ITEM_FOR[item.model] = itemId
	end
end
local RIDES = { "bike110", "bike250", "bike450", "quad450", "quad700" }

-- the Bike Life ride a player is sitting on (their own or a test ride), or nil
local function ridingOn(player)
	local car = Fleet.Get(player)
	if not car or not car:GetAttribute("Exit6BikeLife") or car:GetAttribute("Driver") ~= player.UserId then return nil end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = car:FindFirstChild("DriverSeat")
	if not hum or not seat or hum.SeatPart ~= seat then return nil end
	return car
end

-- ================================================================== the shop
local shopPoints = {}     -- BaseParts a customer must stand near (kiosk + display rides)
local dealer, testBay = nil, nil
local function atShop(player)
	local r = rootOf(player)
	if not r then return false end
	for _, p in ipairs(shopPoints) do
		if p.Parent and (p.Position - r.Position).Magnitude <= BL.shopReach then return true end
	end
	return false
end

local function shopInfo(player)
	local prof = Profile.Get(player)
	local cash, rep = cashRep(player)
	local list = {}
	for _, id in ipairs(RIDES) do
		local spec = Catalog.Vehicles[id]
		local item = Catalog.Items[ITEM_FOR[id]]
		local rec = prof and prof.vehicles[id]
		local entry = { model = id, item = ITEM_FOR[id], name = item.name, price = item.price, rep = item.repRequired or 0,
			rideType = spec.rideType, owned = rec ~= nil }
		local eff = Garage.Effective(id, rec)
		entry.stats = { topSpeed = math.floor(eff.topSpeed / 1.7525 + 0.5), accel = math.floor(eff.accel + 0.5),
			grip = math.floor(eff.grip * 100 + 0.5) / 100 }
		if rec then
			entry.paint, entry.accent, entry.number = rec.paint, rec.accent, rec.number
			entry.upgrades = {}
			for kind, U in pairs(BL.upgrades) do
				local level = rec[kind] or 0
				local price, repNeed = Garage.UpgradePrice(id, kind, level + 1)
				entry.upgrades[kind] = { level = level, max = U.maxLevel, name = U.name, price = price, rep = repNeed }
			end
		end
		table.insert(list, entry)
	end
	return { rides = list, cash = cash and cash.Value or 0, rep = rep and rep.Value or 0, atShop = atShop(player),
		paints = BL.paints, accents = BL.accents, paintPrice = BL.paintPrice, accentPrice = BL.accentPrice,
		numberPrice = BL.numberPrice }
end

-- a parked garage ride the player just changed is rebuilt in place to show it
local function refreshParked(player, modelId)
	local car = Fleet.Get(player)
	if not car or car:GetAttribute("TestRide") or car:GetAttribute("Exit6Model") ~= modelId or car:GetAttribute("Driver") then return end
	local prof = Profile.Get(player)
	local rec = prof and prof.vehicles[modelId]
	if not rec or not car.PrimaryPart then return end
	Fleet.SaveFuel(player, car)
	local cf = car.PrimaryPart.CFrame
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
	local fresh = BikeBuilder.Build(modelId, CFrame.lookAt(cf.Position + Vector3.new(0, 0.3, 0), cf.Position + Vector3.new(0, 0.3, 0) + look.Unit),
		{ owner = player, fuel = rec.fuel, look = rec, stats = Garage.Effective(modelId, rec) })
	Fleet.Put(player, fresh)
end

-- ------------------------------------------------------------------ test rides
local testRides = {}   -- player -> { model, ends }
local lastTest = {}    -- player -> os.clock()
local function endTest(player, why)
	local t = testRides[player]
	testRides[player] = nil
	if t and Fleet.Get(player) == t.model then Fleet.Despawn(player) end
	if t and why then notify(player, why) end
end
local function startTest(player, modelId)
	local spec = Catalog.Vehicles[modelId]
	if not spec or not spec.rideType then return false, "Pick a ride" end
	if not testBay or not testBay.Parent then return false, "The test-ride bay is closed" end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.SeatPart then return false, "Get off first" end
	local now = os.clock()
	if lastTest[player] and now - lastTest[player] < 15 then return false, "One test ride at a time - try again in a moment" end
	if Fleet.Get(player) and Fleet.Get(player):GetAttribute("Driver") then return false, "Park your ride first" end
	-- the bay, or a clear spot beside it
	local bay = testBay.CFrame
	local look = Vector3.new(bay.LookVector.X, 0, bay.LookVector.Z).Unit
	local side = Vector3.new(-look.Z, 0, look.X)
	local size = Vector3.new(spec.wid + 1, 5, spec.len + 1)
	local ignore = { Workspace.Terrain, player.Character, Fleet.folder, testBay }
	local at
	for _, o in ipairs({ 0, 6, -6, 12, -12 }) do
		local p = bay.Position + side * o
		if Fleet.SpotClear(CFrame.lookAt(p + Vector3.new(0, 2.6, 0), p + Vector3.new(0, 2.6, 0) + look), size, bay.Position.Y, ignore) then
			at = p
			break
		end
	end
	if not at then return false, "The test-ride bay is blocked - try again" end
	lastTest[player] = now
	local pos = at + Vector3.new(0, BikeBuilder.RideHeight(modelId) + 0.25, 0)
	local model = BikeBuilder.Build(modelId, CFrame.lookAt(pos, pos + look),
		{ owner = player, testRide = true, fuel = spec.tank, look = { paint = 0, accent = 1, number = 6 } })
	Fleet.Put(player, model)
	testRides[player] = { model = model, ends = now + BL.testRideSeconds }
	task.delay(0.2, function()
		local seat = model:FindFirstChild("DriverSeat")
		if seat and model.Parent and hum.Parent and not hum.SeatPart then seat:Sit(hum) end
	end)
	return true, string.format("Test ride: %s for %d seconds - stay near Exit 6 Motors", spec.name, BL.testRideSeconds)
end

-- ------------------------------------------------------------------ shop wiring
local function wireShop()
	local t0 = os.clock()
	while not Workspace:GetAttribute("CW_Exit6DealershipReady") and os.clock() - t0 < 900 do task.wait(2) end
	dealer = Workspace:FindFirstChild("Exit 6 Motors")
	if not dealer then
		warn("[Exit6 Bike Life] Exit 6 Motors is not built; the bike shop is closed")
		return
	end
	testBay = dealer:FindFirstChild("TestRideSpawn")
	local function shopPrompt(part, text, focus)
		local p = Instance.new("ProximityPrompt")
		p.Name = "BikeShopPrompt"
		p.ActionText = text
		p.ObjectText = "Exit 6 Motors"
		p.KeyboardKeyCode = Enum.KeyCode.E
		p.GamepadKeyCode = Enum.KeyCode.ButtonX
		p.MaxActivationDistance = 11
		p.RequiresLineOfSight = false
		p.Parent = part
		p.Triggered:Connect(function(player)
			if atShop(player) then OpenShop:FireClient(player, focus) end
		end)
		table.insert(shopPoints, part)
	end
	local kiosk = dealer:FindFirstChild("BikeShopKiosk")
	if kiosk then shopPrompt(kiosk, "Bike shop: buy / upgrade / test ride", nil) end
	for _, m in ipairs(dealer:GetChildren()) do
		local itemId = m:GetAttribute("Exit6ShopItem")
		local item = itemId and Catalog.Items[itemId]
		if m:IsA("Model") and m.PrimaryPart and item and Catalog.Vehicles[item.model] and Catalog.Vehicles[item.model].rideType then
			shopPrompt(m.PrimaryPart, "Test ride / buy", item.model)
		end
	end
	print(string.format("[Exit6 Bike Life] bike shop open: %d counters, test bay %s", #shopPoints, testBay and "ready" or "missing"))
end
task.spawn(wireShop)

-- ================================================================== rideouts
local rides = {}     -- leaderUserId -> ride
local current = {}   -- userId -> leaderUserId
local resolved = {}  -- route index -> { { name, pos } }
local intersections = OverlapParams.new()
intersections.MaxParts = 60
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Workspace.Terrain }

-- a route's stops on the rendered streets: each named junction (county road
-- centreline endpoint) snapped to the nearest rendered intersection pad
local function routeStops(index)
	if resolved[index] then return resolved[index] end
	local route = BL.routes[index]
	local world = Workspace:FindFirstChild("ChesterWorld")
	if not route or not world then return nil end
	intersections.FilterType = Enum.RaycastFilterType.Include
	intersections.FilterDescendantsInstances = { world }
	local streetOnly = RaycastParams.new()
	streetOnly.FilterType = Enum.RaycastFilterType.Include
	streetOnly.FilterDescendantsInstances = { world, Workspace.Terrain }
	local stops = {}
	for _, s in ipairs(route.stops) do
		local x, z = (s[2] - 6347.889) * 3, (7201.973 - s[3]) * 3
		local best, bd = nil, 95
		for _, p in ipairs(Workspace:GetPartBoundsInRadius(Vector3.new(x, 60, z), 95, intersections)) do
			-- pads are WedgeParts inside an "Intersection" model in each tile's Intersections folder
			if p:FindFirstAncestor("Intersections") then
				local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(x, 0, z)).Magnitude
				if d < bd then best, bd = p, d end
			end
		end
		local px, pz = x, z
		if best then
			-- the middle of that junction's pad (all its wedges)
			local model = best.Parent
			local sum, n = Vector3.zero, 0
			for _, w in ipairs(model:IsA("Model") and model:GetChildren() or { best }) do
				if w:IsA("BasePart") then sum += w.Position n += 1 end
			end
			local c = n > 0 and sum / n or best.Position
			px, pz = c.X, c.Z
		end
		local down = Workspace:Raycast(Vector3.new(px, 600, pz), Vector3.new(0, -900, 0), streetOnly)
		local y = down and down.Position.Y or 55
		table.insert(stops, { name = s[1], pos = Vector3.new(px, y, pz), snapped = best ~= nil })
	end
	resolved[index] = stops
	return stops
end

local function count(ride)
	local n = 0
	for _ in pairs(ride.members) do n += 1 end
	return n
end
local function rideKind(player)
	local car = Fleet.Get(player)
	local id = car and car:GetAttribute("Exit6BikeLife") and car:GetAttribute("Exit6Model")
	return id and Catalog.Vehicles[id] and Catalog.Vehicles[id].name or nil
end

-- this server's wheelie leaderboard
local sessionBest = {}  -- userId -> best wheelie seconds this server

local function statusFor(player)
	local prof = Profile.Get(player)
	local mine = current[player.UserId] and rides[current[player.UserId]]
	local out = { stats = prof and prof.bikeLife or {}, open = {}, board = {} }
	for leaderId, ride in pairs(rides) do
		if not ride.started and ride ~= mine then
			table.insert(out.open, { leaderId = leaderId, leaderName = ride.leader.DisplayName, riders = count(ride),
				route = BL.routes[ride.route].name, invited = ride.invites[player.UserId] == true })
		end
	end
	table.sort(out.open, function(a, b)
		if a.invited ~= b.invited then return a.invited end
		return a.leaderId < b.leaderId
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		local pr = Profile.Get(p)
		table.insert(out.board, { name = p.DisplayName, session = math.floor((sessionBest[p.UserId] or 0) * 10) / 10,
			best = pr and pr.bikeLife and pr.bikeLife.bestWheelie or 0, me = p == player })
	end
	table.sort(out.board, function(a, b) return a.session > b.session or (a.session == b.session and a.best > b.best) end)
	if mine then
		local me = mine.members[player.UserId]
		local members = {}
		for uid, m in pairs(mine.members) do
			local p = Players:GetPlayerByUserId(uid)
			table.insert(members, { userId = uid, name = p and p.DisplayName or tostring(uid), cp = m.cp, score = math.floor(m.score),
				place = m.place, ride = p and rideKind(p) or nil, leader = uid == mine.leader.UserId })
		end
		table.sort(members, function(a, b)
			if (a.place ~= nil) ~= (b.place ~= nil) then return a.place ~= nil end
			if a.place and b.place then return a.place < b.place end
			if a.cp ~= b.cp then return a.cp > b.cp end
			return a.score > b.score
		end)
		local stops = mine.stops
		local nextStop = (not mine.started) and stops[1] or (me.place == nil and stops[me.cp + 1]) or nil
		out.mine = {
			leaderId = mine.leader.UserId, leaderName = mine.leader.DisplayName, isLeader = mine.leader == player,
			route = BL.routes[mine.route].name, started = mine.started, done = mine.done, stops = #stops,
			cp = me.cp, place = me.place, score = math.floor(me.score), best = math.floor(me.best * 10) / 10,
			members = members, max = BL.maxRiders,
			next = nextStop and { name = nextStop.name, pos = nextStop.pos, index = mine.started and (me.cp + 1) or 1 } or nil,
		}
	end
	out.routes = {}
	for i, r in ipairs(BL.routes) do out.routes[i] = { name = r.name, from = r.stops[1][1], stops = #r.stops } end
	return out
end
local function push(player)
	if player.Parent then Changed:FireClient(player, statusFor(player)) end
end
local function pushRide(ride)
	for uid in pairs(ride.members) do
		local p = Players:GetPlayerByUserId(uid)
		if p then push(p) end
	end
end
local function pushAll()
	for _, p in ipairs(Players:GetPlayers()) do push(p) end
end

local function disband(ride)
	for uid in pairs(ride.members) do
		if current[uid] == ride.leader.UserId then current[uid] = nil end
	end
	rides[ride.leader.UserId] = nil
	pushAll()
end
local function leave(player)
	local key = current[player.UserId]
	local ride = key and rides[key]
	current[player.UserId] = nil
	if not ride then return end
	ride.members[player.UserId] = nil
	if count(ride) == 0 then
		rides[key] = nil
		pushAll()
		return
	end
	if ride.leader == player then
		-- the longest-standing rider leads on
		local nextUid, joined = nil, math.huge
		for uid, m in pairs(ride.members) do
			if m.joined < joined then nextUid, joined = uid, m.joined end
		end
		local p = Players:GetPlayerByUserId(nextUid)
		rides[key] = nil
		ride.leader = p
		rides[nextUid] = ride
		for uid in pairs(ride.members) do current[uid] = nextUid end
		if p then notify(p, "You're leading the rideout now") end
	end
	pushAll()
end

local function finishRider(ride, uid)
	local m = ride.members[uid]
	if not m or m.place then return end
	ride.places += 1
	m.place = ride.places
	local p = Players:GetPlayerByUserId(uid)
	if not p then return end
	local reward = BL.finishCash[m.place] or BL.finishCash[#BL.finishCash]
	local bonus = math.max(0, 120 - (m.place - 1) * 30)
	m.score += bonus
	local cash, rep = cashRep(p)
	if cash then cash.Value += reward end
	if rep then rep.Value += BL.finishRep end
	local prof = Profile.Get(p)
	if prof then
		prof.bikeLife.finished += 1
		prof.bikeLife.bestRide = math.max(prof.bikeLife.bestRide, math.floor(m.score))
		Profile.Publish(p)
	end
	notify(p, string.format("Rideout finished - #%d! +$%d, +%d rep, %d pts", m.place, reward, BL.finishRep, math.floor(m.score)))
end

local function command(player, cmd, value)
	local uid = player.UserId
	local mine = current[uid] and rides[current[uid]]
	if cmd == "buy" then
		if not atShop(player) then return false, "Visit the Bike Life kiosk at Exit 6 Motors" end
		local item = Catalog.Items[value]
		if not item or not Catalog.Vehicles[item.model] or not Catalog.Vehicles[item.model].rideType then return false, "Pick a ride" end
		return Garage.Buy(player, value)
	elseif cmd == "upgrade" then
		if not atShop(player) then return false, "Visit the Bike Life kiosk at Exit 6 Motors" end
		if type(value) ~= "table" or type(value.model) ~= "string" or type(value.kind) ~= "string" then return false end
		local ok, msg = Garage.Upgrade(player, value.model, value.kind)
		if ok then refreshParked(player, value.model) end
		return ok, msg
	elseif cmd == "custom" then
		if not atShop(player) then return false, "Visit the Bike Life kiosk at Exit 6 Motors" end
		if type(value) ~= "table" or type(value.model) ~= "string" or type(value.field) ~= "string" then return false end
		local ok, msg = Garage.Customize(player, value.model, value.field, tonumber(value.value))
		if ok then refreshParked(player, value.model) end
		return ok, msg
	elseif cmd == "testride" then
		if not atShop(player) then return false, "Visit the Bike Life kiosk at Exit 6 Motors" end
		if type(value) ~= "string" then return false end
		return startTest(player, value)
	elseif cmd == "create" then
		if mine then return false, "You're already in a rideout" end
		local index = tonumber(value)
		if not index or index % 1 ~= 0 or not BL.routes[index] then return false, "Pick a route" end
		local stops = routeStops(index)
		if not stops then return false, "The streets are still loading" end
		rides[uid] = { leader = player, route = index, stops = stops, started = false, places = 0, invites = {},
			members = { [uid] = { joined = os.clock(), cp = 0, score = 0, best = 0 } } }
		current[uid] = uid
		pushAll()
		return true, "Rideout created - meet at " .. stops[1].name .. ". Invite riders from the Ride tab."
	elseif cmd == "invite" then
		local target = Players:GetPlayerByUserId(tonumber(value) or 0)
		if not mine or mine.leader ~= player then return false, "Only the leader can invite" end
		if mine.started then return false, "The rideout already left" end
		if not target or target == player then return false, "Pick a player" end
		if current[target.UserId] then return false, target.DisplayName .. " is already in a rideout" end
		mine.invites[target.UserId] = true
		notify(target, player.DisplayName .. " invited you to a rideout - Phone > Ride to join")
		push(target)
		return true, "Invited " .. target.DisplayName
	elseif cmd == "join" then
		if mine then return false, "You're already in a rideout" end
		local ride = rides[tonumber(value) or 0]
		if not ride or ride.started then return false, "That rideout already left" end
		if count(ride) >= BL.maxRiders then return false, "That rideout is full" end
		ride.members[uid] = { joined = os.clock(), cp = 0, score = 0, best = 0 }
		ride.invites[uid] = nil
		current[uid] = ride.leader.UserId
		notify(ride.leader, player.DisplayName .. " joined your rideout")
		pushAll()
		return true, "Joined - meet at " .. ride.stops[1].name
	elseif cmd == "leave" then
		if not mine then return false end
		leave(player)
		return true, "Left the rideout"
	elseif cmd == "start" then
		if not mine or mine.leader ~= player then return false, "Only the leader can start it" end
		if mine.started then return false end
		local car = ridingOn(player)
		if not car then return false, "Get on your bike or quad first" end
		local meet = mine.stops[1].pos
		if (car.PrimaryPart.Position - meet).Magnitude > BL.meetRadius then
			return false, "Ride to the meetup at " .. mine.stops[1].name .. " first"
		end
		mine.started, mine.startedAt = true, os.clock()
		for muid, m in pairs(mine.members) do
			m.cp = 1
			local p = Players:GetPlayerByUserId(muid)
			local prof = p and Profile.Get(p)
			if prof then
				prof.bikeLife.rideouts += 1
				Profile.Publish(p)
			end
			if p and p ~= player then notify(p, "Rideout started! Next: " .. (mine.stops[2] and mine.stops[2].name or "finish")) end
		end
		pushAll()
		return true, "Rideout started! Next: " .. (mine.stops[2] and mine.stops[2].name or "finish")
	elseif cmd == "finish" then
		if not mine or mine.leader ~= player then return false end
		for muid in pairs(mine.members) do
			local p = Players:GetPlayerByUserId(muid)
			if p and p ~= player then notify(p, "The leader ended the rideout") end
		end
		disband(mine)
		return true, "Rideout ended"
	end
	return false
end

local cooldown = {}
Action.OnServerInvoke = function(player, cmd, value)
	if type(cmd) ~= "string" then return statusFor(player) end
	if cmd == "status" then return statusFor(player) end
	if cmd == "shop" then return shopInfo(player) end
	local now = os.clock()
	if cooldown[player] and now - cooldown[player] < 0.35 then return { ok = false, status = statusFor(player) } end
	cooldown[player] = now
	local ok, msg = command(player, cmd, value)
	if msg then notify(player, msg) end
	return { ok = ok == true, msg = msg, status = statusFor(player), shop = (cmd == "buy" or cmd == "upgrade" or cmd == "custom") and shopInfo(player) or nil }
end

-- ================================================================== wheelies + rideout progress
-- Server-observed: the rear wheel on the ground, the front wheel well clear of
-- it, nose up past the minimum pitch, moving, on a Bike Life ride the player
-- is actually sitting on. A short grace (0.25 s) bridges bumps.
local streaks = {}   -- player -> { t = seconds, grace = seconds }
local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Exclude
local function wheelieNow(car)
	local chassis = car.PrimaryPart
	local cf = chassis.CFrame
	local look = cf.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	local flat = Vector3.new(chassis.AssemblyLinearVelocity.X, 0, chassis.AssemblyLinearVelocity.Z).Magnitude
	if pitch < BL.wheelieMinPitch or pitch > 70 or flat < BL.wheelieMinSpeed then return false end
	if flat > (car:GetAttribute("TopSpeed") or 80) * 1.3 then return false end
	local wb = car:GetAttribute("WheelBase") or 5
	local radius = car:GetAttribute("Radius") or 1.2
	local hubDrop = (car:GetAttribute("Rest") or 1) - BikePhysics.Tuning.sag
	local list = { car }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(list, p.Character) end end
	probe.FilterDescendantsInstances = list
	local function hubHeight(z)
		local hub = cf:PointToWorldSpace(Vector3.new(0, -hubDrop, z))
		local hit = Workspace:Raycast(hub, Vector3.new(0, -12, 0), probe)
		return hit and hit.Distance or 12
	end
	return hubHeight(wb / 2) < radius + 0.8 and hubHeight(-wb / 2) > radius + 0.5
end

local function endStreak(player, s)
	if s.t >= BL.wheelieMinSeconds then
		local secs = math.floor(s.t * 10) / 10
		local points = math.floor(secs * BL.wheeliePointsPerSecond * (1 + secs / 10))
		local prof = Profile.Get(player)
		local pb = false
		if prof then
			if secs > prof.bikeLife.bestWheelie then prof.bikeLife.bestWheelie = secs pb = true end
			prof.bikeLife.totalWheelie += math.floor(secs)
			Profile.Publish(player)
		end
		sessionBest[player.UserId] = math.max(sessionBest[player.UserId] or 0, secs)
		local ride = current[player.UserId] and rides[current[player.UserId]]
		local m = ride and ride.started and ride.members[player.UserId]
		if m and not m.place then
			m.score += points
			m.best = math.max(m.best, secs)
			pushRide(ride)
		end
		notify(player, string.format("Wheelie %.1fs  +%d pts%s", secs, points, pb and "  NEW PERSONAL BEST" or ""))
	end
	player:SetAttribute("BikeLifeWheelie", nil)
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then return end
	local step = math.min(acc, 0.3)
	acc = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local car = ridingOn(player)
		local s = streaks[player]
		if car and car.PrimaryPart and wheelieNow(car) then
			s = s or { t = 0, grace = 0 }
			streaks[player] = s
			s.t += step
			s.grace = 0
			local shown = math.floor(s.t * 10) / 10
			if player:GetAttribute("BikeLifeWheelie") ~= shown then player:SetAttribute("BikeLifeWheelie", shown) end
		elseif s then
			s.grace += step
			if s.grace > 0.25 or not car then
				streaks[player] = nil
				endStreak(player, s)
			end
		end
	end
	-- test rides: time and distance limits
	local home = Workspace:GetAttribute("Exit6DealershipAt")
	local now = os.clock()
	for player, t in pairs(testRides) do
		local chassis = t.model.Parent and t.model.PrimaryPart
		if not chassis then
			testRides[player] = nil
		elseif now > t.ends then
			endTest(player, "Test ride over - buy it at the Bike Life kiosk")
		elseif typeof(home) == "Vector3" and (chassis.Position - home).Magnitude > BL.testRideRadius then
			endTest(player, "Test rides stay near Exit 6 Motors - ride returned to the dealer")
		end
	end
	-- rideout checkpoints
	for _, ride in pairs(rides) do
		if ride.started and not ride.done then
			local moved = false
			for uid, m in pairs(ride.members) do
				local p = Players:GetPlayerByUserId(uid)
				local car = p and ridingOn(p)
				local target = ride.stops[m.cp + 1]
				if car and target and not m.place and (car.PrimaryPart.Position - target.pos).Magnitude <= BL.checkpointRadius then
					m.cp += 1
					moved = true
					if m.cp >= #ride.stops then
						finishRider(ride, uid)
					else
						notify(p, string.format("Checkpoint %d/%d - next: %s", m.cp, #ride.stops - 1, ride.stops[m.cp + 1].name))
					end
				end
			end
			local allDone = true
			for _, m in pairs(ride.members) do
				if not m.place then allDone = false break end
			end
			if allDone or now - ride.startedAt > 900 then
				ride.done = true
				moved = true
				task.delay(30, function()
					if rides[ride.leader.UserId] == ride then disband(ride) end
				end)
			end
			if moved then pushRide(ride) end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local s = streaks[player]
	streaks[player] = nil
	if s then endStreak(player, s) end
	leave(player)
	endTest(player, nil)
	lastTest[player] = nil
	cooldown[player] = nil
	for _, ride in pairs(rides) do ride.invites[player.UserId] = nil end
end)
Fleet.Changed:Connect(function(player, model)
	-- the test ride was replaced or sent home
	local t = testRides[player]
	if t and model ~= t.model then testRides[player] = nil end
end)

print("[Exit6 Bike Life] server ready: shop, test rides, wheelies, rideouts")
