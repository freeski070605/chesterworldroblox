-- EXIT 6 vehicles (master plan Phase D, first step: one complete everyday car).
-- Every player has a car they can call from the phone (Car tab): it pulls up
-- on the nearest street. Physics: Exit6CarPhysics (raycast suspension) runs on
-- the driver's client while driven; parked cars are stepped here.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CarPhysics = require(Shared:WaitForChild("Exit6CarPhysics"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local CallCar = Instance.new("RemoteFunction")
CallCar.Name = "CallCar"
CallCar.Parent = remotes
local ParkCar = Instance.new("RemoteEvent")
ParkCar.Name = "SendCarHome"
ParkCar.Parent = remotes

local folder = Instance.new("Folder")
folder.Name = "Exit6Vehicles"
folder.Parent = Workspace

local CALL_COOLDOWN = 8
local PAINT = {
	Color3.fromRGB(148, 18, 28), Color3.fromRGB(22, 36, 70), Color3.fromRGB(196, 198, 200), Color3.fromRGB(28, 28, 30),
	Color3.fromRGB(236, 236, 232), Color3.fromRGB(60, 74, 60), Color3.fromRGB(110, 112, 118), Color3.fromRGB(90, 40, 30),
}
local cars = {}        -- player -> model
local lastCall = {}

-- ------------------------------------------------------------------ builder
local function weldPart(model, chassis, name, size, offset, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = chassis.CFrame * offset
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	for k, v in pairs(props or {}) do p[k] = v end
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = chassis, p
	w.Parent = p
	p.Parent = model
	return p
end

-- an everyday 4-door sedan, ~17 studs long (front = chassis -Z)
local function buildSedan(cf, paint, owner)
	local model = Instance.new("Model")
	model.Name = owner and (owner.Name .. "'s car") or "Car"
	model:SetAttribute("Exit6Car", true)
	model:SetAttribute("WheelBase", 10.4)
	model:SetAttribute("TrackHalf", 3.0)
	model:SetAttribute("WheelMountY", -0.2)
	model:SetAttribute("Rest", 1.4)
	model:SetAttribute("Radius", 1.5)
	if owner then model:SetAttribute("Owner", owner.UserId) end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(7, 1.4, 15)
	chassis.CFrame = cf
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.05, 0, 1, 1)
	chassis.TopSurface, chassis.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	chassis.Parent = model
	model.PrimaryPart = chassis

	local trim = Color3.fromRGB(26, 26, 28)
	local chrome = Color3.fromRGB(190, 192, 196)
	local glass = Color3.fromRGB(40, 54, 66)
	-- body: lower shell, hood / trunk decks, cabin, roof
	weldPart(model, chassis, "Body", Vector3.new(7.2, 2.0, 16.4), CFrame.new(0, 0.5, 0), paint, Enum.Material.SmoothPlastic,
		{ CanCollide = true })
	weldPart(model, chassis, "Hood", Vector3.new(6.9, 0.5, 4.6), CFrame.new(0, 1.7, -5.6) * CFrame.Angles(math.rad(-4), 0, 0), paint)
	weldPart(model, chassis, "Trunk", Vector3.new(6.9, 0.5, 3.0), CFrame.new(0, 1.75, 6.5), paint)
	weldPart(model, chassis, "Cabin", Vector3.new(6.6, 2.4, 7.4), CFrame.new(0, 2.85, 0.6), glass, Enum.Material.Glass,
		{ Transparency = 0.45, CanCollide = true })
	weldPart(model, chassis, "Roof", Vector3.new(6.4, 0.3, 6.0), CFrame.new(0, 4.15, 0.8), paint)
	for _, s in ipairs({ -1, 1 }) do
		weldPart(model, chassis, "Pillar", Vector3.new(0.3, 2.4, 0.4), CFrame.new(s * 3.2, 2.85, -2.9) * CFrame.Angles(math.rad(-25), 0, 0), paint)
		weldPart(model, chassis, "Pillar", Vector3.new(0.3, 2.4, 0.5), CFrame.new(s * 3.2, 2.85, 4.1) * CFrame.Angles(math.rad(25), 0, 0), paint)
		weldPart(model, chassis, "Mirror", Vector3.new(0.7, 0.45, 0.3), CFrame.new(s * 3.75, 2.1, -2.5), paint)
		weldPart(model, chassis, "DoorLine", Vector3.new(0.05, 1.6, 0.08), CFrame.new(s * 3.61, 0.9, 0.6), trim)
		weldPart(model, chassis, "Handle", Vector3.new(0.1, 0.18, 0.7), CFrame.new(s * 3.63, 1.25, -1.0), chrome, Enum.Material.Metal)
		weldPart(model, chassis, "Handle", Vector3.new(0.1, 0.18, 0.7), CFrame.new(s * 3.63, 1.25, 2.4), chrome, Enum.Material.Metal)
		-- lights
		weldPart(model, chassis, "Headlight", Vector3.new(1.6, 0.6, 0.2), CFrame.new(s * 2.5, 1.0, -8.25), Color3.fromRGB(240, 240, 228),
			Enum.Material.Neon)
		weldPart(model, chassis, "Taillight", Vector3.new(1.6, 0.6, 0.2), CFrame.new(s * 2.5, 1.1, 8.25), Color3.fromRGB(170, 20, 24),
			Enum.Material.Neon)
	end
	weldPart(model, chassis, "Grille", Vector3.new(3.0, 0.7, 0.15), CFrame.new(0, 0.95, -8.25), trim)
	weldPart(model, chassis, "FrontBumper", Vector3.new(7.3, 0.7, 0.6), CFrame.new(0, 0.1, -8.4), trim, nil, { CanCollide = true })
	weldPart(model, chassis, "RearBumper", Vector3.new(7.3, 0.7, 0.6), CFrame.new(0, 0.1, 8.4), trim, nil, { CanCollide = true })
	weldPart(model, chassis, "Plate", Vector3.new(1.6, 0.6, 0.1), CFrame.new(0, 0.6, 8.48), Color3.fromRGB(236, 230, 200))
	-- wheels (visual; the suspension is raycast). Centre at ride height.
	local sag = CarPhysics.Tuning.staticSag
	for _, w in ipairs(CarPhysics.Wheels(model)) do
		local o = w[1]
		local y = o.Y - (1.4 - sag)   -- mount - (rest - sag)
		local tyre = weldPart(model, chassis, w[2] and "FrontWheel" or "RearWheel", Vector3.new(1.2, 3.0, 3.0),
			CFrame.new(o.X + math.sign(o.X) * 0.35, y, o.Z) * CFrame.Angles(0, 0, 0), trim, Enum.Material.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder })
		weldPart(model, chassis, "Rim", Vector3.new(1.25, 1.7, 1.7), CFrame.new(o.X + math.sign(o.X) * 0.37, y, o.Z), chrome,
			Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
		tyre:SetAttribute("Exit6Wheel", true)
	end
	-- seats: driver front-left, passenger front-right, two in the back
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2.2, 0.6, 2.2)
	seat.CFrame = chassis.CFrame * CFrame.new(-1.5, 1.6, -0.4)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.HeadsUpDisplay = false
	local sw = Instance.new("WeldConstraint")
	sw.Part0, sw.Part1 = chassis, seat
	sw.Parent = seat
	seat.Parent = model
	for i, off in ipairs({ CFrame.new(1.5, 1.6, -0.4), CFrame.new(-1.5, 1.6, 2.6), CFrame.new(1.5, 1.6, 2.6) }) do
		local s = Instance.new("Seat")
		s.Name = "PassengerSeat" .. i
		s.Size = Vector3.new(2.2, 0.6, 2.2)
		s.CFrame = chassis.CFrame * off
		s.Transparency = 1
		s.CanCollide = false
		s.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = chassis, s
		w.Parent = s
		s.Parent = model
	end
	-- get in with a prompt (driver if free, else a passenger seat)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Get in"
	prompt.ObjectText = model.Name
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = chassis
	prompt.Triggered:Connect(function(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart then return end
		local owner = model:GetAttribute("Owner")
		-- only the owner drives; anyone can ride
		if not seat.Occupant and (not owner or owner == player.UserId) then
			seat:Sit(hum)
			return
		end
		for _, s in ipairs(model:GetChildren()) do
			if s:IsA("Seat") and not s.Occupant then s:Sit(hum) return end
		end
	end)
	-- the driver's client simulates the car while driven
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local player = occ and Players:GetPlayerFromCharacter(occ.Parent)
		local owner = model:GetAttribute("Owner")
		if player and owner and owner ~= player.UserId then
			-- someone else touched the driver seat: move them to a passenger seat
			occ.Sit = false
			task.defer(function()
				for _, s in ipairs(model:GetChildren()) do
					if s:IsA("Seat") and not s.Occupant then s:Sit(occ) return end
				end
			end)
			return
		end
		pcall(function() chassis:SetNetworkOwner(player) end)
		model:SetAttribute("Driver", player and player.UserId or nil)
	end)
	model.Parent = folder
	pcall(function() chassis:SetNetworkOwner(nil) end)
	return model
end

-- ------------------------------------------------------------------ calling the car
local world = Workspace:WaitForChild("ChesterWorld", 300)
local overlap = OverlapParams.new()
overlap.MaxParts = 400
if world then
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { world }
end
-- the nearest point on a city street (not a freeway) and the street's direction
local function curbside(pos)
	local best, bd = nil, math.huge
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(pos, 160, overlap)) do
		local folderName = p.Parent and p.Parent.Name
		if folderName == "Roads" and p:GetAttribute("ChesterStreet") and not p:GetAttribute("CW_HighwayProfiled") then
			local cf, size = p.CFrame, p.Size
			local axis, len, width = cf.RightVector, size.X, size.Z
			if size.Z > size.X then axis, len, width = cf.LookVector, size.Z, size.X end
			axis = Vector3.new(axis.X, 0, axis.Z)
			if width >= 14 and len >= 20 and axis.Magnitude > 0.5 then
				axis = axis.Unit
				local t = math.clamp((pos - p.Position):Dot(axis), -len / 2 + 9, len / 2 - 9)
				local at = p.Position + axis * t
				local d = (Vector3.new(at.X, pos.Y, at.Z) - pos).Magnitude
				if d < bd then
					best, bd = { pos = at + Vector3.new(0, size.Y / 2, 0), axis = axis, width = width, street = p:GetAttribute("ChesterStreet") }, d
				end
			end
		end
	end
	return best
end

local function despawn(player)
	local car = cars[player]
	cars[player] = nil
	if car then car:Destroy() end
end

local function call(player)
	if player:GetAttribute("Exit6DataReady") ~= true then return false, "Not ready" end
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < CALL_COOLDOWN then return false, "Your car is on the way" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or (hum and hum.SeatPart) then return false, "Get out first" end
	local spot = curbside(root.Position)
	if not spot then return false, "No street nearby - walk to a road" end
	lastCall[player] = now
	despawn(player)
	-- park in the lane on the side nearest the player, facing with traffic
	local right = Vector3.new(-spot.axis.Z, 0, spot.axis.X)
	local side = (root.Position - spot.pos):Dot(right) >= 0 and 1 or -1
	local facing = spot.axis * side      -- right-hand traffic: kerb on the car's right
	local pos = spot.pos + right * side * math.max(0, spot.width / 2 - 5) + Vector3.new(0, 3.2, 0)
	local paint = PAINT[(player.UserId % #PAINT) + 1]
	local car = buildSedan(CFrame.lookAt(pos, pos + facing), paint, player)
	cars[player] = car
	player:SetAttribute("Exit6Notice", "Your car is parked on " .. tostring(spot.street))
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
	return true
end
CallCar.OnServerInvoke = function(player)
	local ok, why = call(player)
	if not ok and why then
		player:SetAttribute("Exit6Notice", why)
		player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
	end
	return ok, why
end
ParkCar.OnServerEvent:Connect(function(player)
	local car = cars[player]
	if car and not car:GetAttribute("Driver") then despawn(player) end
end)
Players.PlayerRemoving:Connect(function(player)
	despawn(player)
	lastCall[player] = nil
end)

-- parked cars: the server keeps them on their suspension (the driver's
-- client steps a driven car)
RunService.Heartbeat:Connect(function(dt)
	for _, car in pairs(cars) do
		if car.Parent and not car:GetAttribute("Driver") and car.PrimaryPart then
			CarPhysics.Step(car, dt, { throttle = 0, steer = 0, handbrake = true })
		end
	end
end)
