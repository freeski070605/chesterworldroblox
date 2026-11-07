-- EXIT 6 car bodies: one recipe, six everyday bodies (Catalog.Vehicles).
-- The chassis is the only physical part; the body is welded, massless trim.
-- Physics attributes for Exit6CarPhysics are written on the model.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local CarPhysics = require(Shared:WaitForChild("Exit6CarPhysics"))

local Builder = {}

-- cabin length / height / centre z, body height, and extras per body
local BODIES = {
	sedan = { cabLen = 7.4, cabH = 2.4, cabZ = 0.6, bodyH = 2.0, hood = true, trunk = true },
	hatch = { cabLen = 7.2, cabH = 2.5, cabZ = 1.6, bodyH = 2.0, hood = true },
	van = { cabLen = 13.2, cabH = 3.4, cabZ = 1.4, bodyH = 2.4, hood = true, rearRow = true },
	pickup = { cabLen = 5.8, cabH = 2.6, cabZ = -2.2, bodyH = 2.4, hood = true, bed = true },
	suv = { cabLen = 10.2, cabH = 2.9, cabZ = 1.6, bodyH = 2.4, hood = true, rearRow = true },
	coupe = { cabLen = 5.8, cabH = 1.9, cabZ = 1.0, bodyH = 1.7, hood = true, trunk = true, twoSeat = true },
}

local TRIM = Color3.fromRGB(26, 26, 28)
local CHROME = Color3.fromRGB(190, 192, 196)
local GLASS = Color3.fromRGB(40, 54, 66)

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

local function seatAt(model, chassis, class, name, offset)
	local s = Instance.new(class)
	s.Name = name
	s.Size = Vector3.new(2.2, 0.6, 2.2)
	s.CFrame = chassis.CFrame * offset
	s.Transparency = 1
	s.CanCollide = false
	s.Massless = true
	if class == "VehicleSeat" then
		s.MaxSpeed, s.Torque, s.HeadsUpDisplay = 0, 0, false
	end
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = chassis, s
	w.Parent = s
	s.Parent = model
	return s
end

-- mesh bodies (Studio mesh generation, kept in the place file - not in Rojo):
-- ServerStorage.Exit6CarMeshes.<body> is a Model normalised by
-- tools/harness/car_mesh_templates.luau - pivot on the ground under the
-- centre, front toward -Z - with parts Body, FrontLeftWheel, FrontRightWheel,
-- RearLeftWheel, RearRightWheel and attributes Len, Wid, WheelBase,
-- TrackHalf, Radius, SeatY. A body with a template uses it; otherwise the
-- part-built body below.
local function template(body)
	local folder = ServerStorage:FindFirstChild("Exit6CarMeshes")
	return folder and folder:FindFirstChild(body)
end

-- modelId: Catalog.Vehicles key. opts: { owner = Player, paint = Color3, fuel = gallons, display = bool }
function Builder.Build(modelId, cf, opts)
	opts = opts or {}
	local spec = Catalog.Vehicles[modelId] or Catalog.Vehicles.sedan
	local b = BODIES[spec.body] or BODIES.sedan
	local len, wid = spec.len, spec.wid
	local mesh = template(spec.body)
	if mesh then
		len, wid = mesh:GetAttribute("Len") or len, mesh:GetAttribute("Wid") or wid
	end
	local paint = opts.paint or Color3.fromRGB(148, 18, 28)
	local model = Instance.new("Model")
	model.Name = opts.owner and (opts.owner.Name .. "'s " .. spec.name) or spec.name
	model:SetAttribute("Exit6Car", true)
	model:SetAttribute("Exit6Model", modelId)
	model:SetAttribute("WheelBase", math.floor(len * 0.63 * 10) / 10)
	model:SetAttribute("TrackHalf", wid / 2 - 0.6)
	model:SetAttribute("WheelMountY", -0.2)
	model:SetAttribute("Rest", 1.4)
	model:SetAttribute("Radius", 1.5)
	if mesh then
		-- the physics wheels sit where the mesh's wheels are
		model:SetAttribute("WheelBase", mesh:GetAttribute("WheelBase"))
		model:SetAttribute("TrackHalf", mesh:GetAttribute("TrackHalf"))
		model:SetAttribute("Radius", mesh:GetAttribute("Radius"))
	end
	model:SetAttribute("TopSpeed", spec.topSpeed)
	model:SetAttribute("EngineAccel", spec.accel)
	model:SetAttribute("Tank", spec.tank)
	model:SetAttribute("Fuel", opts.fuel or spec.tank)
	if opts.owner then model:SetAttribute("Owner", opts.owner.UserId) end

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(wid - 0.2, 1.4, len - 1.4)
	chassis.CFrame = cf
	chassis.Transparency = 1
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.6, 0.05, 0, 1, 1)
	chassis.TopSurface, chassis.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	chassis.Anchored = opts.display == true
	chassis.Parent = model
	model.PrimaryPart = chassis

	local half = len / 2
	local bodyTop = -0.5 + b.bodyH
	local cabFront = b.cabZ - b.cabLen / 2
	if mesh then
		-- the mesh body and wheels, welded to the chassis; the mesh pivot is on
		-- the ground under the car's centre
		local rest, radius = model:GetAttribute("Rest"), model:GetAttribute("Radius")
		local ground = chassis.CFrame * CFrame.new(0, -(rest + radius - CarPhysics.Tuning.staticSag + 0.2), 0)
		local copy = mesh:Clone()
		copy:PivotTo(ground)
		for _, p in ipairs(copy:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.Massless = true
				p.CanTouch = false
				p.CanCollide = p.Name == "Body"
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = chassis, p
				w.Parent = p
				p.Parent = model
			end
		end
		copy:Destroy()
		bodyTop = mesh:GetAttribute("SeatY") or 1.5
		cabFront = -len * 0.2
	else
	weldPart(model, chassis, "Body", Vector3.new(wid, b.bodyH, len), CFrame.new(0, -0.5 + b.bodyH / 2, 0), paint, nil,
		{ CanCollide = true })
	local cabBack = b.cabZ + b.cabLen / 2
	if b.hood then
		local hl = cabFront + half - 0.3
		weldPart(model, chassis, "Hood", Vector3.new(wid - 0.3, 0.4, hl), CFrame.new(0, bodyTop + 0.15, -half + hl / 2 + 0.1)
			* CFrame.Angles(math.rad(-3), 0, 0), paint)
	end
	if b.trunk then
		local tl = half - cabBack - 0.3
		if tl > 1 then weldPart(model, chassis, "Trunk", Vector3.new(wid - 0.3, 0.4, tl), CFrame.new(0, bodyTop + 0.2, cabBack + tl / 2), paint) end
	end
	weldPart(model, chassis, "Cabin", Vector3.new(wid - 0.6, b.cabH, b.cabLen), CFrame.new(0, bodyTop + b.cabH / 2, b.cabZ), GLASS,
		Enum.Material.Glass, { Transparency = 0.45, CanCollide = true })
	weldPart(model, chassis, "Roof", Vector3.new(wid - 0.8, 0.3, b.cabLen - 1.2), CFrame.new(0, bodyTop + b.cabH + 0.1, b.cabZ), paint)
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (wid / 2 - 0.4)
		weldPart(model, chassis, "Pillar", Vector3.new(0.3, b.cabH, 0.45), CFrame.new(x, bodyTop + b.cabH / 2, cabFront + 0.4)
			* CFrame.Angles(math.rad(-22), 0, 0), paint)
		weldPart(model, chassis, "Pillar", Vector3.new(0.3, b.cabH, 0.5), CFrame.new(x, bodyTop + b.cabH / 2, cabBack - 0.3), paint)
		weldPart(model, chassis, "Mirror", Vector3.new(0.7, 0.45, 0.3), CFrame.new(s * (wid / 2 + 0.15), bodyTop + 0.4, cabFront + 0.6), paint)
		weldPart(model, chassis, "Handle", Vector3.new(0.1, 0.18, 0.7), CFrame.new(s * (wid / 2 + 0.03), bodyTop - 0.6, cabFront + 2.2),
			CHROME, Enum.Material.Metal)
		weldPart(model, chassis, "Headlight", Vector3.new(1.5, 0.55, 0.2), CFrame.new(s * (wid / 2 - 1.1), bodyTop - 0.6, -half - 0.05),
			Color3.fromRGB(240, 240, 228), Enum.Material.Neon)
		weldPart(model, chassis, "Taillight", Vector3.new(1.4, 0.6, 0.2), CFrame.new(s * (wid / 2 - 1.0), bodyTop - 0.5, half + 0.05),
			Color3.fromRGB(170, 20, 24), Enum.Material.Neon)
	end
	if b.bed then
		-- pickup bed: open box behind the cab
		local bedLen = half - cabBack - 0.2
		for _, s in ipairs({ -1, 1 }) do
			weldPart(model, chassis, "BedWall", Vector3.new(0.35, 1.3, bedLen), CFrame.new(s * (wid / 2 - 0.18), bodyTop + 0.65, cabBack + bedLen / 2 + 0.1), paint)
		end
		weldPart(model, chassis, "Tailgate", Vector3.new(wid, 1.3, 0.35), CFrame.new(0, bodyTop + 0.65, half - 0.18), paint)
	end
	weldPart(model, chassis, "Grille", Vector3.new(wid * 0.42, 0.7, 0.15), CFrame.new(0, bodyTop - 0.55, -half - 0.05), TRIM)
	weldPart(model, chassis, "FrontBumper", Vector3.new(wid + 0.1, 0.7, 0.6), CFrame.new(0, -0.4, -half - 0.2), TRIM, nil, { CanCollide = true })
	weldPart(model, chassis, "RearBumper", Vector3.new(wid + 0.1, 0.7, 0.6), CFrame.new(0, -0.4, half + 0.2), TRIM, nil, { CanCollide = true })
	weldPart(model, chassis, "Plate", Vector3.new(1.6, 0.6, 0.1), CFrame.new(0, 0.1, half + 0.52), Color3.fromRGB(236, 230, 200))
	-- wheels (visual; suspension is raycast), centred at ride height
	local sag = CarPhysics.Tuning.staticSag
	for _, w in ipairs(CarPhysics.Wheels(model)) do
		local o = w[1]
		local y = o.Y - (1.4 - sag)
		weldPart(model, chassis, w[2] and "FrontWheel" or "RearWheel", Vector3.new(1.2, 3.0, 3.0),
			CFrame.new(o.X + math.sign(o.X) * 0.35, y, o.Z), TRIM, nil, { Shape = Enum.PartType.Cylinder })
		weldPart(model, chassis, "Rim", Vector3.new(1.25, 1.7, 1.7), CFrame.new(o.X + math.sign(o.X) * 0.37, y, o.Z), CHROME,
			Enum.Material.Metal, { Shape = Enum.PartType.Cylinder })
	end
	end
	if opts.display then return model end
	-- seats: driver front-left, then passengers
	local seatY = mesh and bodyTop or (bodyTop - 0.1)
	local frontZ = cabFront + 2.6
	local seat = seatAt(model, chassis, "VehicleSeat", "DriverSeat", CFrame.new(-(wid / 2 - 2.0), seatY, frontZ))
	seatAt(model, chassis, "Seat", "PassengerSeat1", CFrame.new(wid / 2 - 2.0, seatY, frontZ))
	if not b.twoSeat and b.cabLen >= 7 then
		seatAt(model, chassis, "Seat", "PassengerSeat2", CFrame.new(-(wid / 2 - 2.0), seatY, frontZ + 3.0))
		seatAt(model, chassis, "Seat", "PassengerSeat3", CFrame.new(wid / 2 - 2.0, seatY, frontZ + 3.0))
	end
	if b.rearRow then
		seatAt(model, chassis, "Seat", "PassengerSeat4", CFrame.new(0, seatY, frontZ + 6.0))
	end
	-- get in: the owner drives, anyone can ride
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Get in"
	prompt.ObjectText = model.Name
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = chassis
	prompt.Triggered:Connect(function(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart then return end
		local owner = model:GetAttribute("Owner")
		if not seat.Occupant and (not owner or owner == player.UserId) then
			seat:Sit(hum)
			return
		end
		for _, s in ipairs(model:GetChildren()) do
			if s:IsA("Seat") and not s.Occupant then s:Sit(hum) return end
		end
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local player = occ and Players:GetPlayerFromCharacter(occ.Parent)
		local owner = model:GetAttribute("Owner")
		if player and owner and owner ~= player.UserId then
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
	return model
end

return Builder
