-- EXIT 6 vehicles (master plan Phase D): garage, calling a car, fuel, gas
-- pumps and the dealership lot.
--   garage     Exit6Profile.vehicles (saved): every car the player owns + its fuel
--   call       phone Car tab -> the car pulls up kerbside on the nearest street
--   fuel       burned by distance while driven; empty = no power (Exit6CarPhysics)
--   pumps      every station dispenser: "Pump gas" at the station's sign price
--   dealership Exit 6 Motors lot near 9th & Kerlin; the salesman's counter sells
--              Catalog.Menus.dealer through the shop menu (Exit6Shop.server)
-- Physics: Exit6CarPhysics on the driver's client while driven; parked cars here.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local CarPhysics = require(Shared:WaitForChild("Exit6CarPhysics"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Builder = require(script.Parent:WaitForChild("Exit6CarBuilder"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local CallCar = remote("RemoteFunction", "CallCar")
local SendHome = remote("RemoteEvent", "SendCarHome")

local folder = Instance.new("Folder")
folder.Name = "Exit6Vehicles"
folder.Parent = Workspace

local CALL_COOLDOWN = 8
local PUMP_REACH = 32
local PAINT = {
	Color3.fromRGB(148, 18, 28), Color3.fromRGB(22, 36, 70), Color3.fromRGB(196, 198, 200), Color3.fromRGB(28, 28, 30),
	Color3.fromRGB(236, 236, 232), Color3.fromRGB(60, 74, 60), Color3.fromRGB(110, 112, 118), Color3.fromRGB(90, 40, 30),
}
local cars = {}        -- player -> model (one car out at a time)
local lastCall = {}
local lastPos = {}     -- model -> last horizontal position (fuel burn)

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
local function saveFuel(player, car)
	local p = Profile.Get(player)
	local id = car and car:GetAttribute("Exit6Model")
	if p and id and p.vehicles[id] then
		p.vehicles[id].fuel = math.floor((car:GetAttribute("Fuel") or 0) * 100 + 0.5) / 100
	end
end
local function despawn(player)
	local car = cars[player]
	cars[player] = nil
	if car then
		saveFuel(player, car)
		lastPos[car] = nil
		car:Destroy()
		Profile.Publish(player)
	end
end

local function call(player, modelId)
	local prof = Profile.Get(player)
	if player:GetAttribute("Exit6DataReady") ~= true or not prof then return false, "Not ready" end
	modelId = (type(modelId) == "string" and prof.vehicles[modelId]) and modelId or prof.active
	if not prof.vehicles[modelId] then return false, "You don't own that" end
	local now = os.clock()
	if lastCall[player] and now - lastCall[player] < CALL_COOLDOWN then return false, "Your car is on the way" end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not root or (hum and hum.SeatPart) then return false, "Get out first" end
	local spot = curbside(root.Position)
	if not spot then return false, "No street nearby - walk to a road" end
	lastCall[player] = now
	despawn(player)
	prof.active = modelId
	-- park in the lane on the side nearest the player, facing with traffic
	local right = Vector3.new(-spot.axis.Z, 0, spot.axis.X)
	local side = (root.Position - spot.pos):Dot(right) >= 0 and 1 or -1
	local facing = spot.axis * side
	local pos = spot.pos + right * side * math.max(0, spot.width / 2 - 5) + Vector3.new(0, 3.2, 0)
	local car = Builder.Build(modelId, CFrame.lookAt(pos, pos + facing),
		{ owner = player, paint = paintFor(player, modelId), fuel = prof.vehicles[modelId].fuel })
	car.Parent = folder
	pcall(function() car.PrimaryPart:SetNetworkOwner(nil) end)
	cars[player] = car
	Profile.Publish(player)
	notify(player, "Your " .. Catalog.Vehicles[modelId].name .. " is parked on " .. tostring(spot.street))
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
RunService.Heartbeat:Connect(function(dt)
	fuelSync += dt
	for player, car in pairs(cars) do
		local chassis = car.Parent and car.PrimaryPart
		if chassis then
			if not car:GetAttribute("Driver") then
				-- parked: hold it on its suspension
				CarPhysics.Step(car, dt, { throttle = 0, steer = 0, handbrake = true })
				lastPos[car] = nil
			else
				-- driven: burn fuel by distance (the server sees the replicated chassis)
				local p = chassis.Position
				local flat = Vector3.new(p.X, 0, p.Z)
				local prev = lastPos[car]
				lastPos[car] = flat
				if prev then
					local d = (flat - prev).Magnitude
					if d < 200 then
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
	if fuelSync > 10 then
		fuelSync = 0
		for player, car in pairs(cars) do saveFuel(player, car) end
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
				saveFuel(player, car)
				Profile.Publish(player)
				notify(player, string.format("Pumped %.1f gal at %s (-$%d)", gallons, brand, cost))
			end)
		end
	end
	print("[EXIT6 Vehicles] pumps=" .. n)
end
task.spawn(setupPumps)

-- ------------------------------------------------------------------ dealership
local DEALER_NAME = "Exit 6 Motors"
local LOT = Vector3.new(64, 0, 46)   -- along the road / depth
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { Workspace.Terrain }
local function groundAt(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -900, 0), terrainOnly)
	return hit and hit.Position.Y
end
local function lotFree(cf)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace.Terrain }
	params.MaxParts = 1
	return #Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 13, 0), Vector3.new(LOT.X + 6, 22, LOT.Z + 4), params) == 0
end
local function findLot(near)
	local region = require(Shared:WaitForChild("WorldConfig")).REAL_BUILDINGS_REGION
	local cands = {}
	for _, p in ipairs(world and world:GetDescendants() or {}) do
		if p:IsA("BasePart") and p.Parent and p.Parent.Name == "Roads" and p:GetAttribute("ChesterStreet")
			and not p:GetAttribute("CW_HighwayProfiled") then
			local pos = p.Position
			if pos.X > region.minX and pos.X < region.maxX and pos.Z > region.minZ and pos.Z < region.maxZ then
				local size = p.Size
				local width = math.min(size.X, size.Z)
				local len = math.max(size.X, size.Z)
				if width >= 18 and len >= 40 then table.insert(cands, { p = p, d = (pos - near).Magnitude }) end
			end
		end
	end
	table.sort(cands, function(a, b) return a.d < b.d end)
	for i, c in ipairs(cands) do
		if i > 400 then break end
		local p = c.p
		local axis = (p.Size.Z > p.Size.X) and p.CFrame.LookVector or p.CFrame.RightVector
		axis = Vector3.new(axis.X, 0, axis.Z).Unit
		local width = math.min(p.Size.X, p.Size.Z)
		local right = Vector3.new(-axis.Z, 0, axis.X)
		for _, side in ipairs({ 1, -1 }) do
			local center = p.Position + right * side * (width / 2 + 10 + LOT.Z / 2)
			local gy = groundAt(center.X, center.Z)
			if gy then
				local flat = true
				for _, o in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
					local cp = center + axis * o[1] * LOT.X / 2 + right * o[2] * LOT.Z / 2
					local y = groundAt(cp.X, cp.Z)
					if not y or math.abs(y - gy) > 2.5 then flat = false break end
				end
				-- front (-Z) faces the road
				local cf = CFrame.lookAt(Vector3.new(center.X, gy, center.Z), Vector3.new(center.X, gy, center.Z) - right * side)
				if flat and lotFree(cf) then return cf, p:GetAttribute("ChesterStreet") end
			end
		end
	end
	return nil
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

local function buildDealership()
	local t0 = os.clock()
	while not Workspace:GetAttribute("CW_StreetFurnitureComplete") and os.clock() - t0 < 400 do task.wait(2) end
	local lotCf, street = findLot(Vector3.new(2810, 60, 1518))
	if not lotCf then warn("[EXIT6 Vehicles] no free lot for the dealership") return end
	local m = Instance.new("Model")
	m.Name = DEALER_NAME
	-- lot: asphalt, painted bays, kerb lights
	block(m, "Lot", Vector3.new(LOT.X, 0.6, LOT.Z), lotCf * CFrame.new(0, 0.3, 0), Color3.fromRGB(58, 58, 62), Enum.Material.Asphalt)
	for i = -3, 3 do
		block(m, "BayLine", Vector3.new(0.4, 0.05, 14), lotCf * CFrame.new(i * 9, 0.62, -LOT.Z / 2 + 10), Color3.fromRGB(230, 230, 226))
	end
	-- sales office at the back of the lot
	local ow, od, oh = 26, 16, 12
	local officeCf = lotCf * CFrame.new(LOT.X / 2 - ow / 2 - 3, 0.6, LOT.Z / 2 - od / 2 - 2)
	local WALL = Color3.fromRGB(226, 222, 214)
	local BLUE = Color3.fromRGB(22, 70, 150)
	block(m, "Floor", Vector3.new(ow, 0.4, od), officeCf * CFrame.new(0, 0.2, 0), Color3.fromRGB(214, 210, 200))
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
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 40
	sg.Parent = signPart
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = string.upper(DEALER_NAME)
	tl.TextColor3 = Color3.new(1, 1, 1)
	tl.Font = Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.Parent = sg
	-- pylon by the road
	local pylonCf = lotCf * CFrame.new(-LOT.X / 2 + 4, 0, -LOT.Z / 2 + 2)
	block(m, "PylonPost", Vector3.new(1.2, 14, 1.2), pylonCf * CFrame.new(0, 7, 0), Color3.fromRGB(180, 182, 186), Enum.Material.Metal)
	local board = block(m, "PylonSign", Vector3.new(10, 4, 0.8), pylonCf * CFrame.new(0, 15.5, 0) * CFrame.Angles(0, math.rad(90), 0), BLUE)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.PixelsPerStud = 30
		g.Parent = board
		local l = tl:Clone()
		l.Text = "EXIT 6 MOTORS\nUSED CARS"
		l.Parent = g
	end
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
	m.Parent = Workspace
	-- display cars along the front bays, a price board on each
	local shown = { "car_hatch", "car_pickup", "car_suv", "car_coupe", "car_van" }
	for i, itemId in ipairs(shown) do
		local item = Catalog.Items[itemId]
		local x = -22.5 + (i - 1) * 9   -- between the painted bay lines
		-- nose to the street (lot -Z)
		local cf = lotCf * CFrame.new(x, 3.0, -LOT.Z / 2 + 10)
		local car = Builder.Build(item.model, cf, { display = true, paint = PAINT[(i * 3) % #PAINT + 1] })
		car.Name = "Display_" .. itemId
		car.Parent = m
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 46)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.MaxDistance = 90
		bb.Parent = car.PrimaryPart
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
		l.BackgroundTransparency = 0.15
		l.TextColor3 = Color3.fromRGB(245, 245, 242)
		l.Font = Enum.Font.GothamBold
		l.TextSize = 15
		l.Text = item.name .. "\n$" .. item.price
		l.Parent = bb
	end
	CollectionService:AddTag(m, "Exit6Store")
	Workspace:SetAttribute("Exit6DealershipAt", lotCf.Position)
	print(string.format("[EXIT6 Vehicles] %s on %s at (%.0f, %.0f, %.0f)", DEALER_NAME, tostring(street), lotCf.X, lotCf.Y, lotCf.Z))
end
task.spawn(buildDealership)
