-- EXIT 6 housing (master plan Phase E): every house in the city is for rent.
-- The house kit (World/HouseKit.lua) tags each unit's front door
-- Exit6FrontDoor + Exit6Rentable. The door prompts are made on each client for
-- the doors streamed in near it (Exit6HomeDoors.client) - not ~19k prompts on
-- the server - and come here through the HomeDoor remote, checked against the
-- player's distance to that door.
--   look inside   anyone, while nobody in this server lives there
--   move in       a one-time payment (Catalog.Housing by style), saved
--   go inside     your own home (locked to everyone else)
-- The ground floor is built the first time someone goes in (HouseKit.Hollow):
-- living room, kitchen, a stash chest (phone > Home). You wake up at home.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Inventory = require(script.Parent:WaitForChild("Exit6Inventory"))
local HouseKit = require(Shared:WaitForChild("HouseKit"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local HomeAction = remote("RemoteFunction", "HomeAction")
local HomeDoor = remote("RemoteEvent", "HomeDoor")
local OpenPhone = remote("RemoteEvent", "OpenPhoneTab")

local DOOR_REACH = 14
local STASH_REACH = 14   -- beyond the home's depth
local doors = {}         -- homeId -> door part

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function doorstep(door)
	return door.CFrame * CFrame.new(0, -door.Size.Y / 2 + 3, -4) * CFrame.Angles(0, math.pi, 0)
end
-- just inside the front door, facing in (door local +Z is inward)
local function inside(door)
	return door.CFrame * CFrame.new(0, -door.Size.Y / 2 + 3, 4.5) * CFrame.Angles(0, math.pi, 0)
end
local function isInside(door, pos)
	return door.CFrame:PointToObjectSpace(pos).Z > 0
end
local function priceOf(door)
	return Catalog.Housing[door:GetAttribute("Exit6HomeStyle") or ""] or Catalog.Housing.default
end
local streetParams = OverlapParams.new()
streetParams.MaxParts = 250
local function streetNear(pos)
	local best, bd = nil, math.huge
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(pos, 70, streetParams)) do
		local name = p:GetAttribute("ChesterStreet")
		if type(name) == "string" and name ~= "" and p.Parent and p.Parent.Name == "Roads" then
			local d = (p.Position - pos).Magnitude
			if d < bd then best, bd = name, d end
		end
	end
	return best
end
local function occupant(homeId)
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = Profile.Get(pl)
		if p and p.home and p.home.id == homeId then return pl end
	end
	return nil
end
local function markDoor(door)
	local who = occupant(door:GetAttribute("Exit6HomeId"))
	door:SetAttribute("Exit6OccupantId", who and who.UserId or nil)
	door:SetAttribute("Exit6OccupantName", who and who.DisplayName or nil)
	local light = door:FindFirstChild("PorchLight")
	if who and not light then
		light = Instance.new("PointLight")
		light.Name = "PorchLight"
		light.Range = 14
		light.Brightness = 1.4
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Parent = door
	elseif not who and light then
		light:Destroy()
	end
end
local function markAll()
	-- only the doors of players in this server can be occupied
	for _, d in pairs(doors) do
		if d:GetAttribute("Exit6OccupantId") then markDoor(d) end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local p = Profile.Get(pl)
		local d = p and p.home and doors[p.home.id]
		if d then markDoor(d) end
	end
end

-- the first time anyone goes in: build the ground floor, wire the stash chest
local function openUp(door)
	local stash = HouseKit.Hollow(door)
	if stash and not stash:FindFirstChild("StashPrompt") then
		local id = door:GetAttribute("Exit6HomeId")
		local sp = Instance.new("ProximityPrompt")
		sp.Name = "StashPrompt"
		sp.ActionText = "Stash"
		sp.ObjectText = "Your stuff"
		sp.MaxActivationDistance = 8
		sp.RequiresLineOfSight = false
		sp.Parent = stash
		sp.Triggered:Connect(function(player)
			local p = Profile.Get(player)
			if p and p.home and p.home.id == id then OpenPhone:FireClient(player, "home") else notify(player, "Not your place") end
		end)
	end
	return stash
end

local function moveIn(player, door)
	local p = Profile.Get(player)
	if not p or player:GetAttribute("Exit6DataReady") ~= true then return end
	local id = door:GetAttribute("Exit6HomeId")
	if p.home and p.home.id == id then notify(player, "Welcome home") return end
	if occupant(id) then notify(player, "Someone lives here") return end
	if p.home then notify(player, "You already have a place on " .. p.home.street .. " - move out first (phone > Home)") return end
	local price = priceOf(door)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Chester Cash")
	if not cash or cash.Value < price then notify(player, "Move-in costs $" .. price) return end
	cash.Value -= price
	p.home = { id = id, street = streetNear(door.Position) or "your block" }
	Profile.Publish(player)
	openUp(door)
	markAll()
	notify(player, "You moved in on " .. p.home.street .. "! You'll wake up here (-$" .. price .. ")")
end

local function goThrough(player, door)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local who = occupant(door:GetAttribute("Exit6HomeId"))
	if who and who ~= player and not isInside(door, root.Position) then
		notify(player, "It's locked")
		return
	end
	if not isInside(door, root.Position) then openUp(door) end
	player.Character:PivotTo(isInside(door, root.Position) and doorstep(door) or inside(door))
end

-- ----------------------------------------------------------- client-decorated houses
-- Outside the core the house kit exists only on the clients near each house
-- (Exit6HouseDecor.client): the server has the plain block and the building's
-- Exit6Kit description. The first time a home there is used (look inside /
-- move in / wake up there), the server builds that one building for real -
-- same inputs, same door ids - and the clients stop decorating it (KitServer).
local OLD_HOME_PARTS = { Walls = true, GroundStorey = true, Foundation = true, Cornice = true, Roof = true }
local OLD_PORCH = { PorchFloor = true, PorchRoof = true, PorchPost = true }
local byBuilding = nil
local function buildingModel(id)
	if not byBuilding then
		byBuilding = {}
		local world = Workspace:FindFirstChild("ChesterWorld")
		for _, tile in ipairs(world and world:GetChildren() or {}) do
			local f = tile:FindFirstChild("Buildings")
			for _, m in ipairs(f and f:GetChildren() or {}) do
				if m:GetAttribute("Exit6Kit") then byBuilding[m:GetAttribute("ChesterBuildingId")] = m end
			end
			task.wait()
		end
	end
	return byBuilding[id]
end
local function insideRect(r, p)
	local l = r.frame:PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
	return math.abs(l.X) <= r.along / 2 + 0.5 and math.abs(l.Z) <= r.across / 2 + 0.5
end
local function materialise(buildingId)
	local m = buildingModel(buildingId)
	if not m or m:GetAttribute("KitServer") then return end
	local ctx, homes = HouseKit.Decode(m:GetAttribute("Exit6Kit"))
	-- the plain block of each home section, and the old porch
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") then
			if OLD_PORCH[c.Name] then
				c:Destroy()
			elseif OLD_HOME_PARTS[c.Name] then
				for _, r in ipairs(homes) do
					if insideRect(r, c.Position) then c:Destroy() break end
				end
			end
		end
	end
	ctx.lite = true
	ctx.buildingId = buildingId
	ctx.applyFacade = HouseKit.ApplyFacade
	ctx.stats = { frontDoors = 0, backDoors = 0, sideDoors = 0, rentals = 0 }
	for _, r in ipairs(homes) do HouseKit.Build(m, r, ctx, HouseKit.H) end
	-- register its doors now (not via the tag signal: no frame-ordering doubt)
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("BasePart") and c:GetAttribute("Exit6Rentable") and c:GetAttribute("Exit6HomeId") then
			doors[c:GetAttribute("Exit6HomeId")] = c
		end
	end
	m:SetAttribute("KitServer", true)
end
HouseKit.Materialise = materialise
-- index the described buildings in the background once the city is up, so
-- the first "look inside" out of the core doesn't wait for it
task.spawn(function()
	while not Workspace:GetAttribute("CW_StreetFurnitureComplete") do task.wait(2) end
	buildingModel("")
end)

local function track(door)
	local id = door:GetAttribute("Exit6HomeId")
	if id and door:GetAttribute("Exit6Rentable") then doors[id] = door end
end
for _, d in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do track(d) end
CollectionService:GetInstanceAddedSignal("Exit6FrontDoor"):Connect(track)

HomeDoor.OnServerEvent:Connect(function(player, homeId, action)
	if type(homeId) ~= "string" then return end
	if not doors[homeId] then
		-- a client-decorated house: build it for real (its doors get tracked)
		materialise(string.match(homeId, "^(.-):%d+$") or "")
		task.wait()
	end
	local door = doors[homeId]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not door or not root or (root.Position - door.Position).Magnitude > DOOR_REACH then return end
	if action == "movein" then
		moveIn(player, door)
	elseif action == "enter" then
		goThrough(player, door)
	end
end)

-- wake up at home
local function spawnAtHome(player, char)
	local p = Profile.Get(player)
	if p and p.home and not doors[p.home.id] then
		materialise(string.match(p.home.id, "^(.-):%d+$") or "")
		task.wait()
	end
	local door = p and p.home and doors[p.home.id]
	if not door then return end
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if root then
		openUp(door)
		task.wait(0.2)
		char:PivotTo(inside(door))
	end
end
local function hook(player)
	player.CharacterAdded:Connect(function(char) spawnAtHome(player, char) end)
end
Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do hook(pl) end
Profile.Loaded:Connect(function(player)
	markAll()
	-- the first character may already be standing at the city spawn
	if player.Character and player:GetAttribute("Exit6HomeSpawned") == nil then
		player:SetAttribute("Exit6HomeSpawned", true)
		task.spawn(spawnAtHome, player, player.Character)
	end
end)
Players.PlayerRemoving:Connect(function() task.defer(markAll) end)

-- phone > Home
HomeAction.OnServerInvoke = function(player, action, itemId)
	local p = Profile.Get(player)
	if not p or not p.home then return false end
	local door = doors[p.home.id]
	if action == "where" then
		return door and doorstep(door).Position or nil
	elseif action == "moveout" then
		local old = door
		p.home = nil
		Profile.Publish(player)
		if old then markDoor(old) end
		notify(player, "You moved out")
		return true
	end
	-- stash: only at home
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not door or not root or (root.Position - door.Position).Magnitude > (door:GetAttribute("Exit6HomeDepth") or 20) + STASH_REACH then
		notify(player, "You need to be at home")
		return false
	end
	if type(itemId) ~= "string" or not Catalog.Items[itemId] then return false end
	if action == "stash" then
		if not Inventory.Remove(player, itemId, 1) then return false end
		p.stash[itemId] = (p.stash[itemId] or 0) + 1
	elseif action == "take" then
		if (p.stash[itemId] or 0) < 1 then return false end
		if not Inventory.Add(player, itemId, 1) then notify(player, "Your bag is full") return false end
		p.stash[itemId] -= 1
		if p.stash[itemId] <= 0 then p.stash[itemId] = nil end
	else
		return false
	end
	Profile.Publish(player)
	return true
end
