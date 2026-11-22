-- EXIT 6 Bike Life rides: real dirt bikes and sport quads.
-- Looks: the Studio-generated meshes in ServerStorage.Exit6BikeMeshes.<modelId>
-- (normalised by tools/harness/bike_mesh_templates.luau - pivot on the ground
-- midway between the axles, front toward -Z), with wheels that spin and a fork
-- / handlebars that steer (Motor6Ds animated by Exit6Riding.client). A ride
-- without a template falls back to a part-built frame so the game still works.
-- Physics: Exit6BikePhysics (two raycast wheels on a bike, four on a quad,
-- plus the "Balance" AlignOrientation). The chassis is the collision hull and
-- sits high enough for the hull to clear kerbs; the wheels do the rest.
--
-- Build(modelId, chassisCFrame, opts)
--   opts.owner     Player who may ride it (nil = display / nobody)
--   opts.display   anchored showroom piece, no seat
--   opts.fuel      gallons
--   opts.look      { paint = 0..#paints (0 = factory), accent = 1..#accents, number = 0..99 }
--   opts.stats     { topSpeed, accel, brake, grip, steerLock, wheelie } (Exit6Garage.Effective)
--   opts.testRide  true for a dealership test ride (not saved, not owned)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local BikePhysics = require(Shared:WaitForChild("Exit6BikePhysics"))
local BikeBuilder = {}

local T = BikePhysics.Tuning
local DARK = Color3.fromRGB(25, 27, 31)
local METAL = Color3.fromRGB(156, 162, 166)

local function template(id)
	local folder = ServerStorage:FindFirstChild("Exit6BikeMeshes")
	return folder and folder:FindFirstChild(id)
end

-- ride geometry: from the mesh template when present, else from the catalog
function BikeBuilder.Geometry(id)
	local spec = Catalog.Vehicles[id]
	assert(spec and spec.rideType, "Not a Bike Life vehicle: " .. tostring(id))
	local quad = spec.rideType == "quad"
	local t = template(id)
	if t then
		return {
			wheelBase = t:GetAttribute("WheelBase"), trackHalf = t:GetAttribute("TrackHalf"),
			radius = t:GetAttribute("Radius"), seatY = t:GetAttribute("SeatY"), seatZ = t:GetAttribute("SeatZ"),
			len = t:GetAttribute("Len"), wid = t:GetAttribute("Wid"), height = t:GetAttribute("Height"),
			quad = quad, mesh = t,
		}
	end
	local wb = spec.len * 0.66
	return {
		wheelBase = wb, trackHalf = quad and (spec.wid / 2 - 0.45) or 0, radius = quad and 1.15 or 1.25,
		seatY = quad and 3.3 or 3.6, seatZ = wb * 0.14, len = spec.len, wid = spec.wid, height = 4.4, quad = quad,
	}
end

-- chassis centre height above the ground when the ride sits on its suspension
function BikeBuilder.RideHeight(id)
	return BikePhysics.ChassisHeight(BikeBuilder.Geometry(id).radius)
end

local function colour(list, i)
	local e = list[i]
	return e and Color3.fromRGB(e.rgb[1], e.rgb[2], e.rgb[3]) or nil
end

local function weldTo(base, p)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, p
	w.Parent = p
end
-- a Motor6D whose joint frame sits at `pivot` (world), axes from `axes`
local function motor(name, part0, part1, pivot)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0, m.Part1 = part0, part1
	m.C0 = part0.CFrame:ToObjectSpace(pivot)
	m.C1 = part1.CFrame:ToObjectSpace(pivot)
	m.Parent = part1
	return m
end
local function looks(p)
	p.Anchored = false
	p.Massless = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
end
local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	looks(p)
	p.Parent = model
	return p
end

-- the race-number plate (front of a bike's fork, front rack of a quad)
local function numberPlate(model, mount, cf, look)
	local acc = colour(Catalog.BikeLife.accents, look.accent or 1) or Color3.new(1, 1, 1)
	local plate = part(model, "NumberPlate", Vector3.new(1.1, 0.9, 0.08), cf, acc)
	weldTo(mount, plate)
	local g = Instance.new("SurfaceGui")
	g.Name = "Number"
	g.Face = Enum.NormalId.Front
	g.PixelsPerStud = 60
	g.Parent = plate
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Text = tostring(look.number or 0)
	local bright = acc.R * 0.3 + acc.G * 0.59 + acc.B * 0.11
	l.TextColor3 = bright > 0.55 and Color3.fromRGB(15, 15, 18) or Color3.new(1, 1, 1)
	l.Parent = g
	return plate
end

-- mesh body on the chassis; returns the steering mount for the number plate
local function meshBody(model, chassis, geo, rideH, look)
	local copy = geo.mesh:Clone()
	copy:PivotTo(chassis.CFrame * CFrame.new(0, -rideH, 0))
	local rot = chassis.CFrame.Rotation
	local parts = {}
	for _, p in ipairs(copy:GetChildren()) do
		if p:IsA("BasePart") then
			looks(p)
			parts[p.Name] = p
			p.Parent = model
		end
	end
	copy:Destroy()
	-- paint the plastics (0 = keep the factory graphics)
	local paint = colour(Catalog.BikeLife.paints, look.paint or 0)
	if paint and parts.Plastics then
		parts.Plastics.TextureID = ""
		parts.Plastics.Color = paint
		parts.Plastics.Material = Enum.Material.SmoothPlastic
	end
	if parts.Plastics then weldTo(chassis, parts.Plastics) end
	if parts.Frame then weldTo(chassis, parts.Frame) end
	if geo.quad then
		for _, n in ipairs({ "FrontLeftWheel", "FrontRightWheel", "RearLeftWheel", "RearRightWheel" }) do
			local w = parts[n]
			if w then motor(n .. "Motor", chassis, w, CFrame.new(w.Position) * rot) end
		end
		if parts.Bars then motor("BarsMotor", chassis, parts.Bars, CFrame.new(parts.Bars.Position) * rot) end
		return chassis, chassis.CFrame * CFrame.new(0, (geo.seatY or 3.3) - rideH - 0.6, -geo.wheelBase / 2 - 0.9)
	end
	local fork, fw, rw = parts.Fork, parts.FrontWheel, parts.RearWheel
	if rw then motor("RearWheelMotor", chassis, rw, CFrame.new(rw.Position) * rot) end
	if fork and fw then
		-- steering axis through the front hub, raked back like a real fork
		local axis = CFrame.new(fw.Position) * rot * CFrame.Angles(T.rake, 0, 0)
		motor("ForkMotor", chassis, fork, axis)
		motor("FrontWheelMotor", fork, fw, CFrame.new(fw.Position) * rot)
		-- plate on the front of the fork, above the fender
		local plateCf = CFrame.new(fw.Position) * rot * CFrame.Angles(T.rake, 0, 0)
			* CFrame.new(0, geo.radius + 0.9, -0.55) * CFrame.Angles(0, math.pi, 0)
		return fork, plateCf
	end
	return chassis, nil
end

-- part-built fallback (only if the mesh templates are missing from the place)
local function partBody(model, chassis, geo, rideH, look)
	local paint = colour(Catalog.BikeLife.paints, look.paint or 0) or Color3.fromRGB(208, 48, 34)
	local base = chassis.CFrame * CFrame.new(0, -rideH, 0)
	local r, wb = geo.radius, geo.wheelBase
	local rot = chassis.CFrame.Rotation
	local function wheelAt(name, x, z, parent0)
		local w = part(model, name, Vector3.new(geo.quad and 1.0 or 0.6, r * 2, r * 2),
			base * CFrame.new(x, r, z) * CFrame.Angles(0, 0, math.rad(90)), DARK, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		motor(name .. "Motor", parent0 or chassis, w, CFrame.new(w.Position) * rot)
		return w
	end
	local frame = part(model, "Frame", Vector3.new(geo.quad and geo.wid - 1 or 0.9, 1.4, wb * 0.7),
		base * CFrame.new(0, r + 0.9, 0.2), DARK, Enum.Material.Metal)
	weldTo(chassis, frame)
	local plastics = part(model, "Plastics", Vector3.new(geo.quad and geo.wid - 0.4 or 1.3, 0.5, wb * 1.2),
		base * CFrame.new(0, r + 1.9, 0), paint)
	weldTo(chassis, plastics)
	if geo.quad then
		for _, n in ipairs({ { "FrontLeftWheel", -1, -1 }, { "FrontRightWheel", 1, -1 }, { "RearLeftWheel", -1, 1 }, { "RearRightWheel", 1, 1 } }) do
			wheelAt(n[1], n[2] * geo.trackHalf, n[3] * wb / 2)
		end
		local bars = part(model, "Bars", Vector3.new(3.2, 0.25, 0.25), base * CFrame.new(0, (geo.seatY or 3.3) + 0.7, -wb * 0.25), METAL, Enum.Material.Metal)
		motor("BarsMotor", chassis, bars, CFrame.new(bars.Position) * rot)
		return chassis, nil
	end
	wheelAt("RearWheel", 0, wb / 2)
	local fork = part(model, "Fork", Vector3.new(0.5, 2.6, 0.5), base * CFrame.new(0, r + 1.3, -wb / 2) * CFrame.Angles(T.rake, 0, 0), METAL, Enum.Material.Metal)
	local axis = base * CFrame.new(0, r, -wb / 2) * CFrame.Angles(T.rake, 0, 0)
	motor("ForkMotor", chassis, fork, axis)
	wheelAt("FrontWheel", 0, -wb / 2, fork)
	return fork, nil
end

function BikeBuilder.Build(id, cf, opts)
	opts = opts or {}
	local spec = Catalog.Vehicles[id]
	assert(spec and spec.rideType, "Not a Bike Life vehicle: " .. tostring(id))
	local geo = BikeBuilder.Geometry(id)
	local stats = opts.stats or {}
	local look = opts.look or {}
	local quad = geo.quad
	local rideH = BikePhysics.ChassisHeight(geo.radius)

	local m = Instance.new("Model")
	m.Name = opts.owner and (opts.owner.Name .. "'s " .. spec.name) or spec.name
	m:SetAttribute("Exit6Car", true)       -- garage, fuel, pumps and the phone's Car tab
	m:SetAttribute("Exit6BikeLife", spec.rideType)
	m:SetAttribute("Exit6Model", id)
	m:SetAttribute("WheelBase", geo.wheelBase)
	m:SetAttribute("TrackHalf", geo.trackHalf)
	m:SetAttribute("Radius", geo.radius)
	m:SetAttribute("Rest", T.rest)
	m:SetAttribute("TopSpeed", stats.topSpeed or spec.topSpeed)
	m:SetAttribute("EngineAccel", stats.accel or spec.accel)
	m:SetAttribute("Brake", stats.brake or spec.brake)
	m:SetAttribute("Grip", stats.grip or spec.grip)
	m:SetAttribute("SteerLock", stats.steerLock or spec.steerLock)
	m:SetAttribute("WheelieMax", stats.wheelie or spec.wheelie)
	m:SetAttribute("Tank", spec.tank)
	m:SetAttribute("Fuel", opts.fuel or spec.tank)
	if opts.owner then m:SetAttribute("Owner", opts.owner.UserId) end
	if opts.testRide then m:SetAttribute("TestRide", true) end

	-- chassis = collision hull: bottom 0.9 above the road (kerbs pass under),
	-- top near the tank; mass set from the catalog (a 250 is ~1.4x its rider)
	local bottom = 0.9
	local hullH = math.max(1.0, 2 * (rideH - bottom))
	local hullW = quad and (geo.trackHalf * 2 - 0.3) or 1.5
	local hullL = geo.wheelBase + (quad and 0.6 or 0.4)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(hullW, hullH, hullL)
	chassis.CFrame = cf
	chassis.Transparency = 1
	chassis.CanCollide = true
	chassis.CanTouch = false
	chassis.Anchored = opts.display == true
	local volume = hullW * hullH * hullL
	chassis.CustomPhysicalProperties = PhysicalProperties.new(math.clamp((spec.mass or 26) / volume, 0.1, 100), 0.25, 0, 1, 1)
	chassis.TopSurface, chassis.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	chassis.Parent = m
	m.PrimaryPart = chassis

	local plateMount, plateCf
	if geo.mesh then
		plateMount, plateCf = meshBody(m, chassis, geo, rideH, look)
	else
		plateMount, plateCf = partBody(m, chassis, geo, rideH, look)
	end
	if plateMount and plateCf then numberPlate(m, plateMount, plateCf, look) end
	local lamp = part(m, "Headlight", Vector3.new(quad and 1.6 or 0.7, 0.4, 0.15),
		chassis.CFrame * CFrame.new(0, (geo.seatY or 3.4) - rideH - (quad and 0.9 or 0.2), -(geo.len or 7) / 2 + 0.25),
		Color3.fromRGB(248, 240, 208), Enum.Material.Neon)
	lamp.Transparency = 0.2
	weldTo(plateMount or chassis, lamp)
	if opts.display then
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true end
		end
		return m
	end

	-- the rider: the Balance controller (Exit6BikePhysics drives it)
	local att = Instance.new("Attachment")
	att.Name = "BalanceAttachment"
	att.CFrame = CFrame.fromMatrix(Vector3.zero, Vector3.yAxis, Vector3.xAxis)
	att.Parent = chassis
	local align = Instance.new("AlignOrientation")
	align.Name = "Balance"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.AlignType = Enum.AlignType.PrimaryAxisParallel
	align.Attachment0 = att
	align.PrimaryAxis = Vector3.yAxis
	align.RigidityEnabled = false
	align.Responsiveness = T.balanceResponse[spec.rideType]
	align.MaxTorque = (spec.mass or 26) * T.balanceTorque[spec.rideType]
	align.Parent = chassis

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(1.4, 0.4, 1.8)
	-- slightly into the seat foam, behind the middle
	seat.CFrame = chassis.CFrame * CFrame.new(0, (geo.seatY or 3.5) - rideH - 0.45, geo.seatZ or 0.6)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false   -- nobody sits by walking into it: only the prompt seats the rider
	seat.Massless = true
	seat.Torque, seat.MaxSpeed, seat.HeadsUpDisplay = 0, 0, false
	seat.Parent = m
	weldTo(chassis, seat)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = quad and "Ride quad" or "Ride dirt bike"
	prompt.ObjectText = opts.testRide and (spec.name .. " (test ride)") or m.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = chassis
	local function mayRide(player)
		local owner = m:GetAttribute("Owner")
		return owner ~= nil and owner == player.UserId
	end
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not hum or not root or hum.Health <= 0 or hum.SeatPart or seat.Occupant then return end
		if (root.Position - chassis.Position).Magnitude > 14 then return end
		if not mayRide(player) then
			player:SetAttribute("Exit6Notice", "That's not your ride")
			player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
			return
		end
		seat:Sit(hum)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occ = seat.Occupant
		local player = occ and Players:GetPlayerFromCharacter(occ.Parent)
		if occ and (not player or not mayRide(player)) then
			occ.Sit = false
			return
		end
		prompt.Enabled = occ == nil
		if not chassis.Parent then return end
		pcall(function() chassis:SetNetworkOwner(player) end)
		local last = m:GetAttribute("Driver")
		m:SetAttribute("Driver", player and player.UserId or nil)
		if not player and last then
			-- step off to the left of the ride instead of popping up through it
			local leaver = Players:GetPlayerByUserId(last)
			local root = leaver and leaver.Character and leaver.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - chassis.Position).Magnitude < 10 then
				task.defer(function()
					if root.Parent and chassis.Parent then
						local side = chassis.CFrame * CFrame.new(-(geo.wid or 3) / 2 - 2.2, 1.5, 0)
						root.Parent:PivotTo(CFrame.lookAt(side.Position, side.Position + chassis.CFrame.LookVector))
					end
				end)
			end
		end
	end)
	return m
end

return BikeBuilder
