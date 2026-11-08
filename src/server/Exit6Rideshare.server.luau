-- EXIT 6 rideshare job (master plan Phase E, additional jobs): drive your own
-- car for riders. A rider waits on a doorstep (a RealBuildings front door);
-- stop next to them and they get in; drop them at another door across town.
-- Pay by distance (Catalog.Rideshare). Started from phone > Job while driving.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local QuitJob = remotes:WaitForChild("QuitJob")
local StartRide = Instance.new("RemoteFunction")
StartRide.Name = "StartRideshare"
StartRide.Parent = remotes

local R = Catalog.Rideshare
local STOP_REACH = 36   -- homes sit back from the kerb
local jobs = {}
local lastRun = {}
local rng = Random.new()

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function myCar(player)
	local folder = Workspace:FindFirstChild("Exit6Vehicles")
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		if m:IsA("Model") and m.PrimaryPart and m:GetAttribute("Owner") == player.UserId and m:GetAttribute("Driver") == player.UserId then return m end
	end
	return nil
end
local function doorstep(door)
	return (door.CFrame * CFrame.new(0, -door.Size.Y / 2 + 0.5, -4)).Position
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
	return best or "the marked spot"
end

local function publish(player)
	local job = jobs[player]
	if not job then player:SetAttribute("Exit6Job", nil) return end
	local t = job.stage == "pickup" and job.pickup or job.dropoff
	player:SetAttribute("Exit6Job", HttpService:JSONEncode({
		type = "ride", stage = job.stage, store = "Rideshare", address = job.stage == "pickup" and job.pickupStreet or job.dropStreet,
		deadline = job.deadline, target = { t.X, t.Y, t.Z }, pay = job.pay,
	}))
end
local function finish(player, success, why)
	local job = jobs[player]
	if not job then return end
	jobs[player] = nil
	lastRun[player.UserId] = os.clock()
	if job.rider then job.rider:Destroy() end
	publish(player)
	if not success then notify(player, why or "The rider cancelled") return end
	local ls = player:FindFirstChild("leaderstats")
	local cash, rep = ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
	if cash then cash.Value += job.pay end
	if rep then rep.Value += R.reputation end
	notify(player, string.format("Ride complete: +$%d, +%d REP", job.pay, R.reputation))
end

local function rider(at, facing)
	local desc = Instance.new("HumanoidDescription")
	local skins = { Color3.fromRGB(86, 58, 44), Color3.fromRGB(156, 112, 84), Color3.fromRGB(226, 186, 150), Color3.fromRGB(120, 84, 62) }
	local skin = skins[rng:NextInteger(1, #skins)]
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor = Color3.fromRGB(rng:NextInteger(20, 220), rng:NextInteger(20, 220), rng:NextInteger(20, 220))
	local ok, npc = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not npc then return nil end
	npc.Name = "Rider"
	for _, p in ipairs(npc:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
	npc:PivotTo(CFrame.lookAt(at + Vector3.new(0, 2.9, 0), facing + Vector3.new(0, 2.9, 0)))
	local hum = npc:FindFirstChildOfClass("Humanoid")
	if not hum then npc:Destroy() return nil end
	hum.DisplayName = "Your rider"
	npc:SetAttribute("Exit6NPC", "rider")
	npc.Parent = Workspace
	return npc
end

StartRide.OnServerInvoke = function(player)
	if player:GetAttribute("Exit6DataReady") ~= true then return false end
	if jobs[player] or player:GetAttribute("Exit6Job") then notify(player, "Finish your current job first") return false end
	local car = myCar(player)
	if not car then notify(player, "Get in your car first (phone > Car)") return false end
	local since = lastRun[player.UserId] and os.clock() - lastRun[player.UserId]
	if since and since < R.cooldown then notify(player, "No riders nearby - try again in " .. math.ceil(R.cooldown - since) .. "s") return false end
	local from = car.PrimaryPart.Position
	local doors = CollectionService:GetTagged("Exit6FrontDoor")
	if #doors < 2 then notify(player, "No riders around here") return false end
	-- A single bounded scan is cheaper and more reliable than 1,200 random
	-- retries, especially when only a few streamed-in doors are usable.
	local pickups = {}
	for _, d in ipairs(doors) do
		if d:IsA("BasePart") and d.Parent then
			local dist = (d.Position - from).Magnitude
			if dist > 80 and dist < 700 then table.insert(pickups, d) end
		end
	end
	if #pickups == 0 then notify(player, "No riders around here") return false end
	local pickupDoor, dropDoor
	local attempts = math.min(#pickups, 12)
	local first = rng:NextInteger(1, #pickups)
	for i = 0, attempts - 1 do
		local candidate = pickups[(first + i - 1) % #pickups + 1]
		local options = {}
		for _, d in ipairs(doors) do
			if d:IsA("BasePart") and d.Parent and d ~= candidate then
				local dist = (d.Position - candidate.Position).Magnitude
				if dist >= R.minStuds and dist <= R.maxStuds then table.insert(options, d) end
			end
		end
		if #options > 0 then
			pickupDoor = candidate
			dropDoor = options[rng:NextInteger(1, #options)]
			break
		end
	end
	if not pickupDoor or not dropDoor then notify(player, "No suitable rides nearby") return false end
	local pickup, dropoff = doorstep(pickupDoor), doorstep(dropDoor)
	local dist = (dropoff - pickup).Magnitude
	local limit = math.max(R.minSeconds, math.floor(((pickup - from).Magnitude + dist) * R.secondsPerStud * 1.6))
	local now = Workspace:GetServerTimeNow()
	local job = {
		stage = "pickup", car = car, pickup = pickup, dropoff = dropoff, deadline = now + limit,
		pay = math.floor(R.basePay + dist * R.payPerStud + 0.5),
		pickupStreet = streetNear(pickup), dropStreet = streetNear(dropoff),
	}
	-- One nearby visual rider per job; the ride can still function if avatar
	-- creation is throttled by Roblox.
	job.rider = rider(pickup, pickupDoor.Position)
	jobs[player] = job
	publish(player)
	notify(player, "Rider waiting on " .. job.pickupStreet .. " - $" .. job.pay .. " fare")
	task.delay(limit, function() if jobs[player] == job then finish(player, false, "Too slow - the rider cancelled") end end)
	return true
end

-- pickup / drop-off: the car stopped close enough
task.spawn(function()
	while true do
		task.wait(0.5)
		for player, job in pairs(jobs) do
			local car = myCar(player)
			local chassis = car and car.PrimaryPart
			-- Jobs are bound to the car used at dispatch. Switching vehicles
			-- cannot teleport the passenger or complete a fare.
			if chassis and chassis.Parent and car == job.car and chassis.AssemblyLinearVelocity.Magnitude < 6 then
				local target = job.stage == "pickup" and job.pickup or job.dropoff
				local flat = (chassis.Position - target) * Vector3.new(1, 0, 1)
				if flat.Magnitude < STOP_REACH then
					if job.stage == "pickup" then
						job.stage = "dropoff"
						if job.rider then job.rider:Destroy() job.rider = nil end
						publish(player)
						notify(player, "Rider's in - take them to " .. job.dropStreet)
					else
						finish(player, true)
					end
				end
			end
		end
	end
end)
QuitJob.OnServerEvent:Connect(function(player)
	if jobs[player] then finish(player, false, "You cancelled the ride") end
end)
local function watch(player)
	player.CharacterRemoving:Connect(function()
		if jobs[player] then finish(player, false, "Ride cancelled when you left the vehicle") end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerRemoving:Connect(function(player)
	local job = jobs[player]
	if job and job.rider then job.rider:Destroy() end
	jobs[player] = nil
	lastRun[player.UserId] = nil
end)
