-- EXIT 6 food delivery job. A takeout counter (J & S, Happy House, the
-- chicken and pizza spots: Catalog.DeliveryKinds) hands the player an order
-- for a real front door in the city (RealBuildings tags Exit6FrontDoor). The
-- client draws the waypoint and a local "Deliver" prompt at that door; the
-- server checks the player is actually standing there before paying.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Config = require(Shared:WaitForChild("Exit6Config"))
if not Config.ShopSystem then return end
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local QuitJob = remotes:WaitForChild("QuitJob")
local Deliver = Instance.new("RemoteEvent")
Deliver.Name = "Deliver"
Deliver.Parent = remotes

local D = Catalog.Delivery
local DROP_REACH = 12
local jobs = {}
local lastRun = {}
local rng = Random.new()

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function root(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

-- street a door faces: the nearest road part carrying ChesterStreet
local streetParams = OverlapParams.new()
streetParams.MaxParts = 250
local function streetNear(pos)
	local best, bd = nil, math.huge
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(pos, 70, streetParams)) do
		local name = p:GetAttribute("ChesterStreet")
		if type(name) == "string" and name ~= "" then
			local d = (p.Position - pos).Magnitude
			if d < bd then best, bd = name, d end
		end
	end
	return best
end

-- where the courier stands: just outside the door (door -Z faces the street)
local function dropPoint(door)
	return (door.CFrame * CFrame.new(0, -door.Size.Y / 2 + 0.5, -3)).Position
end

local function publish(player)
	local job = jobs[player]
	if not job then
		player:SetAttribute("Exit6Job", nil)
		return
	end
	player:SetAttribute("Exit6Job", HttpService:JSONEncode({
		type = "delivery", store = job.store, address = job.address, deadline = job.deadline,
		target = { job.target.X, job.target.Y, job.target.Z }, pay = job.pay,
	}))
end

local function finish(player, success, why)
	local job = jobs[player]
	if not job then return end
	jobs[player] = nil
	lastRun[player.UserId] = os.clock()
	if job.bag then job.bag:Destroy() end
	publish(player)
	if not success then
		notify(player, why or "Delivery failed - the food went cold")
		return
	end
	local ls = player:FindFirstChild("leaderstats")
	local cash, rep = ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
	local used = Workspace:GetServerTimeNow() - job.started
	local tip = (used <= job.limit * D.tipSeconds) and D.tip or 0
	if cash then cash.Value += job.pay + tip end
	if rep then rep.Value += D.reputation end
	notify(player, string.format("Delivered for %s: +$%d%s, +%d REP", job.store, job.pay + tip,
		tip > 0 and (" (incl. $" .. tip .. " tip)") or "", D.reputation))
end

local function carryBag(player)
	local r = root(player)
	if not r then return nil end
	local bag = Instance.new("Part")
	bag.Name = "TakeoutBag"
	bag.Size = Vector3.new(1.4, 1.2, 0.9)
	bag.Color = Color3.fromRGB(214, 190, 150)
	bag.Material = Enum.Material.Fabric
	bag.CanCollide = false
	bag.Massless = true
	bag.CFrame = r.CFrame * CFrame.new(1.3, -0.9, -0.6)
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = r, bag
	weld.Parent = bag
	bag.Parent = player.Character
	return bag
end

local function start(player, model, counter)
	local r = root(player)
	if not r or not counter.Parent or (r.Position-counter.Position).Magnitude>12 then return end
	if player:GetAttribute("Exit6DataReady") ~= true then return end
	if jobs[player] or player:GetAttribute("Exit6Job") then notify(player, "Finish your current job first") return end
	local since = lastRun[player.UserId] and os.clock() - lastRun[player.UserId]
	if since and since < D.cooldown then
		notify(player, "No orders right now - check back in " .. math.ceil(D.cooldown - since) .. "s")
		return
	end
	-- a random front door at a fair walk from the counter
	local from = counter.Position
	local picks = {}
	for _, door in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do
		if door:IsA("BasePart") and door.Parent then
			local d = (door.Position - from).Magnitude
			if d >= D.minStuds and d <= D.maxStuds then table.insert(picks, door) end
		end
	end
	if #picks == 0 then notify(player, "No orders right now") return end
	local door = picks[rng:NextInteger(1, #picks)]
	if not door.Parent then notify(player, "That address is unavailable - try again") return end
	local target = dropPoint(door)
	local dist = (target - from).Magnitude
	local street = streetNear(target)
	local limit = math.max(D.minSeconds, math.floor(dist * D.secondsPerStud * 1.4 + 0.5))
	local now = Workspace:GetServerTimeNow()
	local store = model:GetAttribute("ShopName") or model.Name
	local job = {
		store = store, target = target, started = now, limit = limit, deadline = now + limit,
		pay = math.floor(D.basePay + dist * D.payPerStud + 0.5),
		address = street and ("a home on " .. street) or "the marked house",
	}
	jobs[player] = job
	job.bag = carryBag(player)
	publish(player)
	notify(player, string.format("Order up at %s: take it to %s", store, job.address))
	task.delay(limit, function()
		if jobs[player] == job then finish(player, false) end
	end)
end

Deliver.OnServerEvent:Connect(function(player)
	local job = jobs[player]
	local r = root(player)
	if not job or not r then return end
	if (r.Position - job.target).Magnitude > DROP_REACH then
		notify(player, "Get to the front door first")
		return
	end
	finish(player, true)
end)
QuitJob.OnServerEvent:Connect(function(player)
	if jobs[player] then finish(player, false, "You dropped the order") end
end)
Players.PlayerRemoving:Connect(function(player)
	jobs[player] = nil
	lastRun[player.UserId] = nil
end)
-- dying (or resetting) drops the order
local function watch(player)
	player.CharacterRemoving:Connect(function()
		if jobs[player] then finish(player, false, "You dropped the order") end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end

-- counters: a "Take delivery" prompt at every takeout store
local function setup(model)
	if not model.Parent then return end
	local t0 = os.clock()
	while model.Parent and not model:GetAttribute("Exit6StoreKind") and os.clock() - t0 < 150 do task.wait(1) end
	if not Catalog.DeliveryKinds[model:GetAttribute("Exit6StoreKind")] then return end
	local interior = model:FindFirstChild("Exit6Storefront")
	local counter = interior and interior:FindFirstChild("Counter")
	if not counter and CollectionService:HasTag(model,"Exit6SimpleStore") then
		local ref = model:FindFirstChild("Exit6ShopDoor")
		counter = ref and ref.Value
	end
	if not counter or not counter.Parent or counter:FindFirstChild("DeliveryPrompt") then return end
	local p = Instance.new("ProximityPrompt")
	p.Name = "DeliveryPrompt"
	p.ActionText = "Take delivery order"
	p.ObjectText = model:GetAttribute("ShopName") or model.Name
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p.HoldDuration = 0.5
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = counter
	p.Triggered:Connect(function(player)
		if model.Parent and player:GetAttribute("Exit6DataReady") == true then start(player, model, counter) end
	end)
end
for _, tag in ipairs({"Exit6Store","Exit6SimpleStore"}) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do task.spawn(setup, m) end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(m) task.spawn(setup, m) end)
end
