-- EXIT 6 housing (master plan Phase E): rent a real home in the city.
-- Every RealBuildings front door (tag Exit6FrontDoor, attribute Exit6HomeId)
-- can be moved into with a one-time payment (Catalog.Housing by style). Your
-- home is saved in the profile; you respawn on its doorstep, and items can be
-- stashed there (phone > Home). One player per home in a server.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Inventory = require(script.Parent:WaitForChild("Exit6Inventory"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local HomeAction = Instance.new("RemoteFunction")
HomeAction.Name = "HomeAction"
HomeAction.Parent = remotes

local STASH_REACH = 18
local doors = {}      -- homeId -> door part

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function doorstep(door)
	return door.CFrame * CFrame.new(0, -door.Size.Y / 2 + 3, -4) * CFrame.Angles(0, math.pi, 0)
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
local function refreshDoor(door)
	local prompt = door:FindFirstChild("HomePrompt")
	if not prompt then return end
	local who = occupant(door:GetAttribute("Exit6HomeId"))
	if who then
		prompt.ActionText = "Home"
		prompt.ObjectText = who.DisplayName .. "'s place"
	else
		prompt.ActionText = "Move in ($" .. priceOf(door) .. ")"
		prompt.ObjectText = "For rent"
	end
end
local function refreshAll()
	for _, door in pairs(doors) do refreshDoor(door) end
end

local function moveIn(player, door)
	local p = Profile.Get(player)
	if not p or player:GetAttribute("Exit6DataReady") ~= true then return end
	local id = door:GetAttribute("Exit6HomeId")
	if p.home and p.home.id == id then
		notify(player, "Welcome home")
		return
	end
	if occupant(id) then notify(player, "Someone lives here") return end
	if p.home then notify(player, "You already have a place on " .. p.home.street .. " - move out first (phone > Home)") return end
	local price = priceOf(door)
	local ls = player:FindFirstChild("leaderstats")
	local cash = ls and ls:FindFirstChild("Chester Cash")
	if not cash or cash.Value < price then notify(player, "Move-in costs $" .. price) return end
	cash.Value -= price
	p.home = { id = id, street = streetNear(door.Position) or "your block" }
	Profile.Publish(player)
	refreshAll()
	notify(player, "You moved in on " .. p.home.street .. "! You'll wake up here (-$" .. price .. ")")
end

local function setup(door)
	local id = door:GetAttribute("Exit6HomeId")
	if not id or doors[id] then return end
	doors[id] = door
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HomePrompt"
	prompt.MaxActivationDistance = 7
	prompt.HoldDuration = 0.6
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player) moveIn(player, door) end)
	refreshDoor(door)
end
for _, d in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do setup(d) end
CollectionService:GetInstanceAddedSignal("Exit6FrontDoor"):Connect(setup)

-- wake up at home
local function spawnAtHome(player, char)
	local p = Profile.Get(player)
	local door = p and p.home and doors[p.home.id]
	if not door then return end
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if root then
		task.wait(0.2)
		char:PivotTo(doorstep(door))
	end
end
local function hook(player)
	player.CharacterAdded:Connect(function(char) spawnAtHome(player, char) end)
end
Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do hook(pl) end
Profile.Loaded:Connect(function(player)
	refreshAll()
	-- the first character may already be standing at the city spawn
	if player.Character and player:GetAttribute("Exit6HomeSpawned") == nil then
		player:SetAttribute("Exit6HomeSpawned", true)
		task.spawn(spawnAtHome, player, player.Character)
	end
end)
Players.PlayerRemoving:Connect(function() task.defer(refreshAll) end)

-- phone > Home
HomeAction.OnServerInvoke = function(player, action, itemId)
	local p = Profile.Get(player)
	if not p or not p.home then return false end
	local door = doors[p.home.id]
	if action == "where" then
		return door and doorstep(door).Position or nil
	elseif action == "moveout" then
		p.home = nil
		Profile.Publish(player)
		refreshAll()
		notify(player, "You moved out")
		return true
	end
	-- stash: only at home
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not door or not root or (root.Position - door.Position).Magnitude > STASH_REACH then
		notify(player, "You need to be at your front door")
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
