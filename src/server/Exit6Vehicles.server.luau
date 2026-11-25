-- EXIT 6 vehicles (master plan Phase D): garage, calling a car, fuel, gas
-- pumps and the dealership lot.
--   garage     Exit6Profile.vehicles (saved): every car / bike / quad the player
--              owns + its fuel (Bike Life rides also their looks and upgrades)
--   call       phone Car tab -> the ride pulls up kerbside on the nearest street
--   fuel       burned by distance while driven; empty = no power
--   pumps      every station dispenser: "Pump gas" at the station's sign price
--   dealership Exit 6 Motors at the front of the J&S lot on W 9th (building
--              93584); the salesman's counter sells Catalog.Menus.dealer through
--              the shop menu (Exit6Shop.server), the Bike Life kiosk is wired by
--              Exit6BikeLife.server
-- Physics: cars run Exit6CarPhysics, Bike Life rides Exit6BikePhysics, on the
-- driver's client while driven (network owner) and here while parked. The
-- server bounds what a client-owned ride may do (speed, climb).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
Workspace:SetAttribute("CW_Exit6DealershipReady", false)

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local CarPhysics = require(Shared:WaitForChild("Exit6CarPhysics"))
local BikePhysics = require(Shared:WaitForChild("Exit6BikePhysics"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Builder = require(script.Parent:WaitForChild("Exit6CarBuilder"))
local BikeBuilder = require(script.Parent:WaitForChild("Exit6BikeBuilder"))
local Garage = require(script.Parent:WaitForChild("Exit6Garage"))
local Fleet = require(script.Parent:WaitForChild("Exit6Fleet"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local CallCar = remote("RemoteFunction", "CallCar")
local SendHome = remote("RemoteEvent", "SendCarHome")

local folder = Fleet.folder
local cars = Fleet.cars   -- player -> model (one ride out at a time)

local CALL_COOLDOWN = 8
local PUMP_REACH = 32
local PAINT = {
	Color3.fromRGB(148, 18, 28), Color3.fromRGB(22, 36, 70), Color3.fromRGB(196, 198, 200), Color3.fromRGB(28, 28, 30),
	Color3.fromRGB(236, 236, 232), Color3.fromRGB(60, 74, 60), Color3.fromRGB(110, 112, 118), Color3.fromRGB(90, 40, 30),
}
local lastCall = {}
local overSince = {}   -- model -> os.clock() a client-owned ride first broke the limits
local lastPos = {}     -- model -> { position, sample time } (fuel burn)

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function paintFor(player, modelId)
	local h = player.UserId
	for i = 1, #modelId do h += string.byte(modelId, i) * i end
	return PAINT[(h % #PAINT) + 1]
end

-- ------------------------------------------------------------------ streets
local world = Workspace:WaitForChild("ChesterWorld", 300)
local overlap = OverlapParams.new()
overlap.MaxParts = 400
if world then
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = { world }
end
-- the nearest point on a city street (not a freeway) and the street's direction
local function curbside(pos, radius, minWidth)
	local best, bd = nil, math.huge
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(pos, radius or 160, overlap)) do
		if p.Parent and p.Parent.Name == "Roads" and p:GetAttribute("ChesterStreet") and not p:GetAttribute("CW_HighwayProfiled") then
			local cf, size = p.CFrame, p.Size
			local axis, len, width = cf.RightVector, size.X, size.Z
			if size.Z > size.X then axis, len, width = cf.LookVector, size.Z, size.X end
			axis = Vector3.new(axis.X, 0, axis.Z)
			if width >= (minWidth or 14) and len >= 20 and axis.Magnitude > 0.5 then
				axis = axis.Unit
				local t = math.clamp((pos - p.Position):Dot(axis), -len / 2 + 9, len / 2 - 9)
				local at = p.Position + axis * t
				local d = (Vector3.new(at.X, pos.Y, at.Z) - pos).Magnitude
				if d < bd then
					best, bd = { pos = at + Vector3.new(0, size.Y / 2, 0), axis = axis, width = width,
						street = p:GetAttribute("ChesterStreet"), part = p }, d
				end
			end
		end
	end
	return best
end

-- ------------------------------------------------------------------ garage
local function despawn(player)
	local car = cars[player]
	if car then lastPos[car] = nil end
	Fleet.Despawn(player)
end

local spotClear = Fleet.SpotClear

-- build a garage ride for its owner (looks, upgrades and fuel from the save)
local function buildOwned(player, modelId, cf)
	local prof = Profile.Get(player)
	local rec = prof.vehicles[modelId]
	local spec = Catalog.Vehicles[modelId]
	if spec.rideType then
		return BikeBuilder.Build(modelId, cf, { owner = player, fuel = rec.fuel, look = rec,
			stats = Garage.Effective(modelId, rec) })
	end
	return Builder.Build(modelId, cf, { owner = player, paint = paintFor(player, modelId), fuel = rec.fuel })
end

local function call(player, modelId)
	local prof = Profile.Get(player)
	if player:GetAttribute("Exit6DataReady") ~= true or not prof then return false, "Not ready" end
	modelId = (type(modelId) == "string" and prof.vehicles[modelId]) and modelId or prof.active
	if not prof.vehicles[modelId] or not Catalog.Vehicles[modelId] then return false, "You don't own that" end
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < CALL_COOLDOWN then return false, "Your ride is on the way" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or (hum and hum.SeatPart) then return false, "Get off first" end
	local spot = curbside(root.Position)
	if not spot then return false, "No street nearby - walk to a road" end
	local spec = Catalog.Vehicles[modelId]
	-- park in the lane on the side nearest the player, facing with traffic
	local right = Vector3.new(-spot.axis.Z, 0, spot.axis.X)
	local side = (root.Position - spot.pos):Dot(right) >= 0 and 1 or -1
	local facing = spot.axis * side
	local lift = spec.rideType and (BikeBuilder.RideHeight(modelId) + 0.25) or 3.2
	local inset = spec.rideType and 3.5 or 5
	local base = spot.pos + right * side * math.max(0, spot.width / 2 - inset)
	local ignore = { Workspace.Terrain, player.Character, folder }
	local size = Vector3.new(spec.wid + 1, 5, spec.len + 1)
	local pos
	-- slide along the kerb to a spot with nothing standing in the ride's way
	for _, t in ipairs({ 0, 12, -12, 24, -24, 36, -36, 48, -48 }) do
		local at = base + spot.axis * t
		if spotClear(CFrame.lookAt(at + Vector3.new(0, 2.6, 0), at + Vector3.new(0, 2.6, 0) + facing), size, spot.pos.Y, ignore) then
			pos = at + Vector3.new(0, lift, 0)
			break
		end
	end
	if not pos then return false, "The kerb here is blocked - try another spot" end
	lastCall[player] = now
	despawn(player)
	prof.active = modelId
	local car = buildOwned(player, modelId, CFrame.lookAt(pos, pos + facing))
	Fleet.Put(player, car)
	Profile.Publish(player)
	notify(player, "Your " .. spec.name .. " is parked on " .. tostring(spot.street))
	return true
end
CallCar.OnServerInvoke = function(player, modelId)
	local ok, why = call(player, modelId)
	if not ok and why then notify(player, why) end
	return ok, why
end
SendHome.OnServerEvent:Connect(function(player)
	local car = cars[player]
	if car and not car:GetAttribute("Driver") then despawn(player) end
end)
Players.PlayerRemoving:Connect(function(player)
	despawn(player)
	lastCall[player] = nil
end)

-- ------------------------------------------------------------------ simulation + fuel
local fuelSync = 0
local PARKED = { parked = true }
local PARKED_CAR = { throttle = 0, steer = 0, handbrake = true }
RunService.Heartbeat:Connect(function(dt)
	fuelSync += dt
	for player, car in pairs(cars) do
		local chassis = car.Parent and car.PrimaryPart
		if chassis then
			local bike = car:GetAttribute("Exit6BikeLife") ~= nil
			if bike and car:GetAttribute("Driver") then
				-- the rider's client simulates the ride (network owner); a client
				-- that reports impossible speed or climb for more than a moment
				-- loses the ride: off the seat, physics back to the server, clamped
				local v = chassis.AssemblyLinearVelocity
				local limit = (car:GetAttribute("TopSpeed") or 80) * 1.25 + 8
				local flat = Vector3.new(v.X, 0, v.Z)
				if flat.Magnitude > limit or v.Y > 80 then
					local now = os.clock()
					overSince[car] = overSince[car] or now
					if now - overSince[car] > 0.75 then
						overSince[car] = nil
						local seat = car:FindFirstChild("DriverSeat")
						if seat and seat.Occupant then seat.Occupant.Sit = false end
						pcall(function() chassis:SetNetworkOwner(nil) end)
						local f = flat.Magnitude > limit and flat.Unit * limit * 0.5 or flat
						chassis.AssemblyLinearVelocity = Vector3.new(f.X, math.min(v.Y, 0), f.Z)
						notify(player, "Ride reset - it was moving faster than it can")
						warn(string.format("[EXIT6 Vehicles] %s's %s exceeded limits (%.0f studs/s, climb %.0f)",
							player.Name, tostring(car:GetAttribute("Exit6Model")), flat.Magnitude, v.Y))
					end
				else
					overSince[car] = nil
				end
			end
			if not car:GetAttribute("Driver") then
				-- parked: hold it on its suspension (a bike on its stand)
				if bike then BikePhysics.Step(car, dt, PARKED) else CarPhysics.Step(car, dt, PARKED_CAR) end
				lastPos[car] = nil
			else
				-- driven: burn fuel by distance (the server sees the replicated chassis)
				local p = chassis.Position
				local flat = Vector3.new(p.X, 0, p.Z)
				local now = os.clock()
				local prev = lastPos[car]
				if not prev then
					lastPos[car] = { position = flat, time = now }
				else
					local d = (flat - prev.position).Magnitude
					-- Keep the old sample through sub-stud suspension/network noise.
					-- A large jump is a teleport or physics correction, not mileage.
					if d >= 0.75 then
						local elapsed = math.clamp(now - prev.time, 0, 0.5)
						local topSpeed = car:GetAttribute("TopSpeed") or 80
						local plausible = d <= topSpeed * 1.6 * elapsed + 2
						lastPos[car] = { position = flat, time = now }
						if plausible and not overSince[car] then
							local spec = Catalog.Vehicles[car:GetAttribute("Exit6Model")] or Catalog.Vehicles.sedan
							local fuel = math.max(0, (car:GetAttribute("FuelExact") or car:GetAttribute("Fuel") or 0) - d / spec.perGallon)
							car:SetAttribute("FuelExact", fuel)
							-- the replicated gauge moves in 0.05 gal steps
							if math.abs((car:GetAttribute("Fuel") or 0) - fuel) >= 0.05 or (fuel == 0 and car:GetAttribute("Fuel") ~= 0) then
								car:SetAttribute("Fuel", math.floor(fuel * 100 + 0.5) / 100)
								if fuel == 0 then notify(player, "Out of gas! Push it to a station or call it home") end
							end
						end
					end
				end
			end
		end
	end
	if fuelSync > 10 then
		fuelSync = 0
		for player, car in pairs(cars) do Fleet.SaveFuel(player, car) end
	end
end)

-- ------------------------------------------------------------------ gas pumps
local function setupPumps()
	local stations = Workspace:WaitForChild("ChesterGasStations", 300)
	if not stations then return end
	local t0 = os.clock()
	while not Workspace:GetAttribute("CW_GasStationsComplete") and os.clock() - t0 < 300 do task.wait(2) end
	local n = 0
	for _, d in ipairs(stations:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Kind") == "FuelDispenser" then
			local station = d:FindFirstAncestorWhichIsA("Model")
			while station and station:GetAttribute("FuelPrice") == nil and station.Parent ~= stations do
				station = station.Parent:FindFirstAncestorWhichIsA("Model")
			end
			local price = (station and station:GetAttribute("FuelPrice")) or Catalog.FuelPrice
			local brand = station and (station:GetAttribute("BrandName") or station.Name) or "Gas"
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "PumpPrompt"
			prompt.ActionText = string.format("Pump gas ($%.2f/gal)", price)
			prompt.ObjectText = brand
			prompt.HoldDuration = 1
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = d
			n += 1
			prompt.Triggered:Connect(function(player)
				local car = cars[player]
				if not car or not car.PrimaryPart then notify(player, "Call your car first (phone > Car)") return end
				if (car.PrimaryPart.Position - d.Position).Magnitude > PUMP_REACH then notify(player, "Pull your car up to the pump") return end
				if car.PrimaryPart.AssemblyLinearVelocity.Magnitude > 3 then notify(player, "Stop the car first") return end
				if car:GetAttribute("TestRide") then notify(player, "Test rides come fuelled by the dealer") return end
				local ls = player:FindFirstChild("leaderstats")
				local cash = ls and ls:FindFirstChild("Chester Cash")
				local tank = car:GetAttribute("Tank") or 12
				local fuel = car:GetAttribute("FuelExact") or car:GetAttribute("Fuel") or 0
				local want = tank - fuel
				if want < 0.05 then notify(player, "Tank's already full") return end
				if not cash or cash.Value < 1 then notify(player, "Not enough Chester Cash") return end
				local gallons = math.min(want, cash.Value / price)
				local cost = math.max(1, math.ceil(gallons * price))
				cash.Value -= cost
				fuel += gallons
				car:SetAttribute("FuelExact", fuel)
				car:SetAttribute("Fuel", math.floor(fuel * 100 + 0.5) / 100)
				Fleet.SaveFuel(player, car)
				Profile.Publish(player)
				notify(player, string.format("Pumped %.1f gal at %s (-$%d)", gallons, brand, cost))
			end)
		end
	end
	print("[EXIT6 Vehicles] pumps=" .. n)
end
task.spawn(setupPumps)

-- ------------------------------------------------------------------ dealership
-- Exit 6 Motors stands at the FRONT of the J&S / Boost Mobile / 5 Points
-- Market parking lot (county building 93584, tile r06_c07), facing the
-- W 9th St / Kerlin St / Concord Ave five-point node - NOT Concord Avenue.
-- Verified 2026-11-22 against
--   * DVRPC 2025 orthophoto + county footprints (tools/harness/intersection_aerial.py,
--     build/aerial/js_lot_93584.png): a triangular paved lot in front of the
--     strip's NW face, apex at the 9th / Kerlin crossing;
--   * OpenStreetMap names: West 9th Street runs through that node, Concord
--     Avenue leaves it ESE along the lot's NE edge, Kerlin St on the west;
--   * the rendered Studio geometry (tools/harness/probes/js_lot_fit.py): lot =
--     terrain pavement (Y 51.0) between the Kerlin east sidewalk (yaw 24.4),
--     the Concord south sidewalk (yaw 65.7) and the 9th / Kerlin pad; the
--     strip's lot-facing doors (Boost Mobile, J & S) look along bearing 335.
-- Frame: origin = Boost Mobile's ShopDoor at ground level, local -Z = that
-- door's LookVector (out across the lot toward W 9th), +X = ENE along the
-- storefronts. Layout (studs): display pad for the five Bike Life rides at the
-- 9th Street end, the car row behind it, the sales office behind the cars at
-- the Kerlin end (clear of every door), and a 30-stud aisle kept open in front
-- of all three storefronts. Every piece is box-checked against the real
-- sidewalks, roads, buildings and furniture before it is built; a blocked
-- piece is left out and reported - the dealership is never moved elsewhere.
local DEALER_NAME = "Exit 6 Motors"
local STRIP_ID = "93584"
local STRIP_TILE = "tile_r06_c07"
local VERIFIED_DOOR = Vector3.new(2927.469, 0, 1636.098)     -- Boost Mobile ShopDoor, studs
local VERIFIED_OUT = Vector3.new(-0.4223842, 0, -0.9064169)  -- its LookVector (bearing 335)
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Workspace.Terrain }
local function groundAt(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -900, 0), terrainOnly)
	return hit and hit.Position.Y
end

-- the strip by its stable county id, and its lot-facing storefront doors
local function stripFrame()
	local tile = world and world:WaitForChild(STRIP_TILE, 300)
	local buildings = tile and tile:WaitForChild("Buildings", 120)
	local strip
	for _, b in ipairs(buildings and buildings:GetChildren() or {}) do
		if tostring(b:GetAttribute("ChesterBuildingId")) == STRIP_ID then strip = b break end
	end
	local origin, out, source = VERIFIED_DOOR, VERIFIED_OUT, "verified-constants"
	if strip then
		local along = Vector3.new(-VERIFIED_OUT.Z, 0, VERIFIED_OUT.X)
		local west
		for _, d in ipairs(strip:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "ShopDoor" and d.CFrame.LookVector:Dot(VERIFIED_OUT) > 0.97 then
				if not west or d.Position:Dot(along) < west.Position:Dot(along) then west = d end
			end
		end
		if west then
			local look = west.CFrame.LookVector
			origin, out, source = west.Position, Vector3.new(look.X, 0, look.Z).Unit, "building-93584-doors"
			local drift = (Vector3.new(origin.X, 0, origin.Z) - VERIFIED_DOOR).Magnitude
			if drift > 6 then
				warn(string.format("[EXIT6 Vehicles] strip 93584 door moved %.1f studs from the verified survey", drift))
			end
		else
			warn("[EXIT6 Vehicles] strip 93584 found but no lot-facing ShopDoor; using verified survey")
		end
	else
		warn("[EXIT6 Vehicles] strip 93584 not found in " .. STRIP_TILE .. "; using verified survey")
	end
	local probe = origin + out * 60
	local y = groundAt(probe.X, probe.Z)
	if not y then return nil, "no ground in the J&S lot" end
	local right = Vector3.new(-out.Z, 0, out.X)
	return CFrame.fromMatrix(Vector3.new(origin.X, y, origin.Z), right, Vector3.yAxis, -out), source
end

-- everything standing inside a footprint (terrain, this dealership, parked /
-- driven vehicles and people excluded): real sidewalks, kerbs, roads, walls,
-- poles and trees all count
local function blockers(frame, lx, lz, w, h, d, ignore)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.MaxParts = 40
	local cf = frame * CFrame.new(lx, 0.12 + h / 2, lz)
	local found = {}
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, Vector3.new(w, h, d), params)) do
		local m = p:FindFirstAncestorOfClass("Model")
		if not (m and m:FindFirstChildOfClass("Humanoid")) then
			table.insert(found, p:GetFullName())
			if #found >= 3 then break end
		end
	end
	-- the ground under every corner must be the lot's own level
	for _, c in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
		local wp = frame * Vector3.new(lx + c[1] * w / 2, 0, lz + c[2] * d / 2)
		local gy = groundAt(wp.X, wp.Z)
		if not gy or math.abs(gy - frame.Y) > 1.5 then
			table.insert(found, string.format("ground %.1f at (%.0f, %.0f)", gy or -1, wp.X, wp.Z))
			break
		end
	end
	return found
end

-- the lot's terrain is uneven by a stud or two: each piece stands on the
-- highest ground under its footprint (nothing sinks into the paving) and
-- slabs get a footing down to the lowest point (nothing floats)
local function groundSpan(frame, lx, lz, w, d)
	local lo, hi = math.huge, -math.huge
	for _, u in ipairs({ -0.5, 0, 0.5 }) do
		for _, v in ipairs({ -0.5, 0, 0.5 }) do
			local wp = frame * Vector3.new(lx + u * w, 0, lz + v * d)
			local y = groundAt(wp.X, wp.Z)
			if y then lo, hi = math.min(lo, y), math.max(hi, y) end
		end
	end
	if lo == math.huge then return frame.Y, frame.Y end
	return lo, hi
end
local function onGround(frame, lx, lz, w, d)
	local lo, hi = groundSpan(frame, lx, lz, w, d)
	return frame + Vector3.new(0, hi - frame.Y, 0), hi - lo
end

local function block(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end
local function label(part, face, text, ppm)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.PixelsPerStud = ppm or 40
	g.LightInfluence = 0
	g.Parent = part
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextScaled = true
	l.Parent = g
	return l
end
local function priceBoard(parent, text, height)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150, 46)
	bb.StudsOffset = Vector3.new(0, height, 0)
	bb.MaxDistance = 60
	bb.Parent = parent
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
	l.BackgroundTransparency = 0.15
	l.TextColor3 = Color3.fromRGB(245, 245, 242)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.Text = text
	l.Parent = bb
end

-- layout, in the dealership frame (studs; -Z toward W 9th)
local PAD = { x = -9, z = -97, w = 46, d = 18 }        -- Bike Life showroom pad
local CARS = { x = 4, z = -70, w = 72, d = 20 }        -- used-car row
local OFFICE = { x = -17, z = -43, w = 22, d = 14, h = 11 }
local PYLON = { x = -30, z = -103 }
local KIOSK = { x = 19, z = -94 }
local TEST_SPAWN = { x = 30, z = -46 }                 -- test rides leave toward Concord's kerb cut
local BIKE_DISPLAY = { "bike_110", "bike_250", "bike_450", "quad_450", "quad_700" }
local CAR_DISPLAY = { "car_hatch", "car_suv", "car_coupe" }

local function buildDealership()
	local t0 = os.clock()
	while not Workspace:GetAttribute("CW_StreetFurnitureComplete") and os.clock() - t0 < 400 do task.wait(2) end
	local frame, source = stripFrame()
	if not frame then
		warn("[EXIT6 Vehicles] J&S lot unavailable (" .. tostring(source) .. "); Exit 6 Motors not built")
		Workspace:SetAttribute("CW_Exit6DealershipStatus", "lot-unavailable")
		Workspace:SetAttribute("CW_Exit6DealershipReady", true)
		return
	end
	local m = Instance.new("Model")
	m.Name = DEALER_NAME
	local ignore = { Workspace.Terrain, m, folder }
	local problems = {}
	local function place(name, lx, lz, w, h, d)
		local hit = blockers(frame, lx, lz, w, h, d, ignore)
		if #hit > 0 then
			table.insert(problems, name .. " <- " .. table.concat(hit, "; "))
			warn("[EXIT6 Vehicles] " .. DEALER_NAME .. " " .. name .. " blocked by " .. table.concat(hit, "; "))
			return false
		end
		return true
	end
	local WHITE = Color3.fromRGB(236, 236, 230)
	local BLUE = Color3.fromRGB(22, 70, 150)
	local ORANGE = Color3.fromRGB(229, 120, 30)

	-- Bike Life showroom pad at the 9th Street end
	if place("showroom pad", PAD.x, PAD.z, PAD.w, 7, PAD.d) then
		local padFrame, drop = onGround(frame, PAD.x, PAD.z, PAD.w, PAD.d)
		local thick = 0.3 + drop
		block(m, "ShowroomPad", Vector3.new(PAD.w, thick, PAD.d), padFrame * CFrame.new(PAD.x, 0.3 - thick / 2, PAD.z),
			Color3.fromRGB(170, 170, 166), Enum.Material.Concrete)
		block(m, "PadEdge", Vector3.new(PAD.w, thick + 0.02, 0.6), padFrame * CFrame.new(PAD.x, 0.31 - thick / 2, PAD.z - PAD.d / 2 + 0.3), ORANGE)
		for i, itemId in ipairs(BIKE_DISPLAY) do
			local item = Catalog.Items[itemId]
			local x = PAD.x - PAD.w / 2 + 5 + (i - 1) * 9
			local yaw = math.rad((i % 2 == 0) and 14 or -14)
			local base = padFrame * CFrame.new(x, 0.3, PAD.z + 1) * CFrame.Angles(0, yaw, 0)
			local ride = BikeBuilder.Build(item.model, base * CFrame.new(0, BikeBuilder.RideHeight(item.model), 0),
				{ display = true })
			ride.Name = "Display_" .. itemId
			ride:SetAttribute("Exit6ShopItem", itemId)
			ride.Parent = m
			priceBoard(ride.PrimaryPart, item.name .. "\n$" .. item.price .. (item.repRequired and ("  REP " .. item.repRequired) or "")
				.. "\nFREE TEST RIDE", 4.2 + (i % 2) * 1.4)
		end
	end

	-- used cars behind the bikes
	if place("car row", CARS.x, CARS.z, CARS.w, 7, CARS.d) then
		for i, itemId in ipairs(CAR_DISPLAY) do
			local item = Catalog.Items[itemId]
			local x = CARS.x - CARS.w / 2 + 12 + (i - 1) * 24
			local bay = onGround(frame, x, CARS.z, 13, 16)
			for _, s in ipairs({ -1, 1 }) do
				local lineFrame = onGround(frame, x + s * 6.5, CARS.z, 0.4, 16)
				block(m, "BayLine", Vector3.new(0.4, 0.05, 16), lineFrame * CFrame.new(x + s * 6.5, 0.03, CARS.z), WHITE)
			end
			local car = Builder.Build(item.model, bay * CFrame.new(x, 3.0, CARS.z), { display = true, paint = PAINT[(i * 3) % #PAINT + 1] })
			car.Name = "Display_" .. itemId
			car:SetAttribute("Exit6ShopItem", itemId)
			car.Parent = m
			priceBoard(car.PrimaryPart, item.name .. "\n$" .. item.price, 6.5)
		end
	end

	-- sales office behind the display rows, at the Kerlin end of the lot
	local officeOk = place("sales office", OFFICE.x, OFFICE.z, OFFICE.w + 1, OFFICE.h, OFFICE.d + 1)
	if officeOk then
		local ow, od, oh = OFFICE.w, OFFICE.d, OFFICE.h
		local officeFrame, drop = onGround(frame, OFFICE.x, OFFICE.z, ow, od)
		local officeCf = officeFrame * CFrame.new(OFFICE.x, 0, OFFICE.z)
		local WALL = Color3.fromRGB(226, 222, 214)
		block(m, "Floor", Vector3.new(ow, 0.4 + drop, od), officeCf * CFrame.new(0, 0.4 - (0.4 + drop) / 2, 0), Color3.fromRGB(214, 210, 200))
		block(m, "BackWall", Vector3.new(ow, oh, 0.8), officeCf * CFrame.new(0, oh / 2, od / 2), WALL, Enum.Material.Brick)
		for _, s in ipairs({ -1, 1 }) do
			block(m, "SideWall", Vector3.new(0.8, oh, od), officeCf * CFrame.new(s * ow / 2, oh / 2, 0), WALL, Enum.Material.Brick)
			local g = block(m, "Window", Vector3.new(ow / 2 - 3, oh - 3.4, 0.3), officeCf * CFrame.new(s * (ow / 4 + 1.5), (oh - 3.4) / 2 + 0.4, -od / 2),
				Color3.fromRGB(150, 190, 210), Enum.Material.Glass)
			g.Transparency = 0.4
		end
		block(m, "Header", Vector3.new(ow, 3.0, 0.8), officeCf * CFrame.new(0, oh - 1.5, -od / 2), BLUE)
		block(m, "Roof", Vector3.new(ow + 1, 0.6, od + 1), officeCf * CFrame.new(0, oh + 0.3, 0), Color3.fromRGB(70, 72, 76))
		local signPart = block(m, "SignBoard", Vector3.new(ow - 2, 2.4, 0.2), officeCf * CFrame.new(0, oh - 1.5, -od / 2 - 0.5), BLUE)
		label(signPart, Enum.NormalId.Front, string.upper(DEALER_NAME))
		-- the salesman's office is a shop (Exit6Storefronts fits it, Exit6Shop staffs it)
		local anchor = block(m, "Exit6StoreAnchor", Vector3.new(1, 1, 1), officeCf * CFrame.new(0, 0.4, 0), Color3.new(1, 1, 1))
		anchor.Transparency = 1
		anchor.CanCollide = false
		m:SetAttribute("ShopName", DEALER_NAME)
		m:SetAttribute("BrandName", DEALER_NAME)
		m:SetAttribute("Exit6StoreShell", "building")
		m:SetAttribute("Exit6StoreWidth", ow - 1.6)
		m:SetAttribute("Exit6StoreDepth", od - 1.6)
		m:SetAttribute("Exit6StoreHeight", oh)
		m:SetAttribute("BrandFascia", BLUE)
	end

	-- pylon on the corner nearest W 9th & Kerlin, readable from both directions
	if place("pylon", PYLON.x, PYLON.z, 3, 17, 3) then
		local pylonCf = onGround(frame, PYLON.x, PYLON.z, 2, 2) * CFrame.new(PYLON.x, 0, PYLON.z)
		block(m, "PylonPost", Vector3.new(1.2, 14, 1.2), pylonCf * CFrame.new(0, 7, 0), Color3.fromRGB(180, 182, 186), Enum.Material.Metal)
		local board = block(m, "PylonSign", Vector3.new(11, 4.4, 0.8), pylonCf * CFrame.new(0, 15.6, 0), BLUE)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(board, face, "EXIT 6 MOTORS\nDIRT BIKES  QUADS  CARS", 30)
		end
	end

	-- Bike Life kiosk: buy, upgrade, paint, test ride (Exit6BikeLife.server wires it)
	if place("bike life kiosk", KIOSK.x, KIOSK.z, 7, 9, 5) then
		local kCf = onGround(frame, KIOSK.x, KIOSK.z, 6, 2.2) * CFrame.new(KIOSK.x, 0, KIOSK.z)
		local counter = block(m, "BikeShopKiosk", Vector3.new(6, 3.6, 2.2), kCf * CFrame.new(0, 1.8, 0), Color3.fromRGB(28, 30, 34))
		block(m, "KioskTop", Vector3.new(6.4, 0.3, 2.6), kCf * CFrame.new(0, 3.75, 0), ORANGE)
		for _, s in ipairs({ -1, 1 }) do
			block(m, "KioskPost", Vector3.new(0.4, 5, 0.4), kCf * CFrame.new(s * 2.9, 6.4, 0.9), Color3.fromRGB(180, 182, 186), Enum.Material.Metal)
		end
		local sign = block(m, "KioskSign", Vector3.new(6.6, 1.8, 0.3), kCf * CFrame.new(0, 8.6, 0.9), ORANGE)
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			label(sign, face, "BIKE LIFE - BUY / UPGRADE / TEST RIDE", 30)
		end
		counter:SetAttribute("Exit6BikeShop", true)
	end

	-- where test rides are handed over: open lot between the cars and the stores
	if place("test-ride bay", TEST_SPAWN.x, TEST_SPAWN.z, 8, 6, 12) then
		local spawnPart = block(m, "TestRideSpawn", Vector3.new(3, 0.2, 9),
			onGround(frame, TEST_SPAWN.x, TEST_SPAWN.z, 9, 3) * CFrame.new(TEST_SPAWN.x, 0.1, TEST_SPAWN.z) * CFrame.Angles(0, math.rad(-90), 0), ORANGE, Enum.Material.Neon)
		spawnPart.Transparency = 0.6
		spawnPart.CanCollide = false
		spawnPart.CanQuery = false
	end

	if officeOk then CollectionService:AddTag(m, "Exit6Store") end
	m.Parent = Workspace
	local facing = frame.LookVector   -- local -Z: out of the doors toward W 9th
	local bearing = (math.deg(math.atan2(facing.X, -facing.Z)) + 360) % 360
	Workspace:SetAttribute("Exit6DealershipAt", frame.Position)
	Workspace:SetAttribute("CW_Exit6DealershipPlacement", "J&S-front-lot:" .. STRIP_ID .. ":" .. tostring(source))
	Workspace:SetAttribute("CW_Exit6DealershipFacing", bearing)
	Workspace:SetAttribute("CW_Exit6DealershipClearance", #problems == 0 and "clear" or table.concat(problems, " | "))
	print(string.format("[EXIT6 Vehicles] %s: J&S lot (building %s, %s) origin (%.1f, %.1f, %.1f) facing bearing %.0f toward W 9th; clearance %s",
		DEALER_NAME, STRIP_ID, tostring(source), frame.X, frame.Y, frame.Z, bearing, #problems == 0 and "clear" or (#problems .. " piece(s) skipped")))
	Workspace:SetAttribute("CW_Exit6DealershipStatus", "ready")
	Workspace:SetAttribute("CW_Exit6DealershipReady", true)
end
task.spawn(buildDealership)
