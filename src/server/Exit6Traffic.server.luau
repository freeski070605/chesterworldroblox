-- EXIT 6 traffic (master plan Phase D): everyday cars driving the streets of
-- the real-buildings region (9th & Kerlin). The road graph comes from the
-- built street parts (Roads folders, ChesterStreet): strip ends that meet are
-- one road, ends across an intersection connect. Cars keep right, slow at
-- junctions, stop for anything ahead (players, cars, pedestrians), and are
-- moved by AlignPosition / AlignOrientation (server-owned physics), so they
-- replicate smoothly. A car that stays blocked is quietly moved elsewhere.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Config = require(Shared:WaitForChild("Exit6Config"))
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local Builder = require(script.Parent:WaitForChild("Exit6CarBuilder"))
local TR = Config.Traffic or {}
local COUNT = TR.cars or 14
if COUNT <= 0 then return end
local REGION = TR.region or WorldConfig.REAL_BUILDINGS_REGION

local JOIN = 5
local ACROSS = 34          -- an intersection: road ends this close connect
local RIDE = 2.4           -- chassis centre above the road
local CRUISE = { 34, 46 }  -- studs/s (~ 20-27 mph)
local TURN_SPEED = 16
local LOOK_AHEAD = 26
local rng = Random.new()

local t0 = os.clock()
while not Workspace:GetAttribute("CW_StreetFurnitureComplete") and os.clock() - t0 < 400 do task.wait(2) end
local world = Workspace:FindFirstChild("ChesterWorld")
if not world then return end

-- ------------------------------------------------------------------ road graph
local nodes = {}
local index = {}
local function key(p) return math.floor(p.X / 2 + 0.5) .. ":" .. math.floor(p.Z / 2 + 0.5) end
local function node(p)
	local k = key(p)
	if not index[k] then
		table.insert(nodes, { pos = p, out = {} })
		index[k] = #nodes
	end
	return index[k]
end
-- out[id] = { width, street }
local function link(a, b, width, street)
	if a == b then return end
	nodes[a].out[b] = nodes[a].out[b] or { width = width, street = street }
	nodes[b].out[a] = nodes[b].out[a] or { width = width, street = street }
end
local function inRegion(p)
	return p.X >= REGION.minX and p.X <= REGION.maxX and p.Z >= REGION.minZ and p.Z <= REGION.maxZ
end
-- the tile folders' own <name> folders (never world:GetDescendants() - the
-- city is over a million instances: a memory spike and a long server freeze)
local function tileFolders(name)
	local out = {}
	for _, tile in ipairs(world:GetChildren()) do
		local f = tile:FindFirstChild(name)
		if f then table.insert(out, f) end
	end
	return out
end
local ends = {}
for _, f in ipairs(tileFolders("Roads")) do
	task.wait()
	do
		for _, p in ipairs(f:GetChildren()) do
			if p:IsA("BasePart") and p:GetAttribute("ChesterStreet") and not p:GetAttribute("CW_HighwayProfiled")
				and inRegion(p.Position) then
				local size = p.Size
				local axis, len, width = p.CFrame.RightVector, size.X, size.Z
				if size.Z > size.X then axis, len, width = p.CFrame.LookVector, size.Z, size.X end
				local flat = Vector3.new(axis.X, 0, axis.Z)
				if width >= 12 and len >= 4 and flat.Magnitude > 0.5 then
					local top = p.Position + Vector3.new(0, size.Y / 2, 0)
					local a = node(top - axis * len / 2)
					local b = node(top + axis * len / 2)
					local street = p:GetAttribute("ChesterStreet")
					link(a, b, width, street)
					table.insert(ends, { a, width, street })
					table.insert(ends, { b, width, street })
				end
			end
		end
	end
end
local grid = {}
local CELL = 40
local function cellKey(x, z) return math.floor(x / CELL) .. ":" .. math.floor(z / CELL) end
for id, n in ipairs(nodes) do
	local k = cellKey(n.pos.X, n.pos.Z)
	grid[k] = grid[k] or {}
	table.insert(grid[k], id)
end
local function near(p, r)
	local out = {}
	local cx, cz = math.floor(p.X / CELL), math.floor(p.Z / CELL)
	local reach = math.ceil(r / CELL)
	for dx = -reach, reach do
		for dz = -reach, reach do
			for _, id in ipairs(grid[(cx + dx) .. ":" .. (cz + dz)] or {}) do
				local q = nodes[id].pos
				if (Vector3.new(q.X, 0, q.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude <= r and math.abs(q.Y - p.Y) < 6 then
					table.insert(out, id)
				end
			end
		end
	end
	return out
end
local function degree(id)
	local d = 0
	for _ in pairs(nodes[id].out) do d += 1 end
	return d
end
-- touching strip ends are one road
for id, n in ipairs(nodes) do
	for _, o in ipairs(near(n.pos, JOIN)) do
		if o ~= id then
			local e = next(n.out) and n.out[next(n.out)]
			link(id, o, e and e.width or 16, e and e.street)
		end
	end
end
-- across intersections: a road end connects to the nearby ends of other roads
for _, e in ipairs(ends) do
	local id = e[1]
	if degree(id) == 1 then
		for _, o in ipairs(near(nodes[id].pos, ACROSS)) do
			if o ~= id and not nodes[id].out[o] and degree(o) <= 2 then
				link(id, o, math.min(e[2], 18), "junction")
			end
		end
	end
end
-- biggest connected network
local comp, best, bestSize = {}, nil, 0
for id in ipairs(nodes) do
	if not comp[id] then
		local stack, size = { id }, 0
		comp[id] = id
		while #stack > 0 do
			local cur = table.remove(stack)
			size += 1
			for o in pairs(nodes[cur].out) do
				if not comp[o] then comp[o] = id table.insert(stack, o) end
			end
		end
		if size > bestSize then best, bestSize = id, size end
	end
end
local usable = {}
for id in ipairs(nodes) do
	if comp[id] == best and degree(id) >= 2 then table.insert(usable, id) end
end
print(string.format("[EXIT6 Traffic] roadNodes=%d network=%d", #nodes, #usable))
if #usable < 20 then return end

-- ------------------------------------------------------------------ cars
local folder = Instance.new("Folder")
folder.Name = "Exit6Traffic"
folder.Parent = Workspace
local MODELS = { "sedan", "sedan", "hatch", "van", "pickup", "suv", "sedan", "hatch" }
local PAINT = {
	Color3.fromRGB(196, 198, 200), Color3.fromRGB(28, 28, 30), Color3.fromRGB(236, 236, 232), Color3.fromRGB(110, 112, 118),
	Color3.fromRGB(148, 18, 28), Color3.fromRGB(22, 36, 70), Color3.fromRGB(60, 74, 60), Color3.fromRGB(150, 120, 80),
}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { world, Workspace.Terrain }

local function farFromPlayers(p, r)
	for _, pl in ipairs(Players:GetPlayers()) do
		local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - p).Magnitude < r then return false end
	end
	return true
end

local traffic = {}
local function laneTarget(a, b)
	-- point along a->b in the right-hand lane
	local pa, pb = nodes[a].pos, nodes[b].pos
	local dir = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
	if dir.Magnitude < 1e-3 then return pa, pb, Vector3.zAxis end
	dir = dir.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local w = nodes[a].out[b] and nodes[a].out[b].width or 16
	local off = right * math.clamp(w / 4, 3.5, 7)
	return pa + off, pb + off, dir
end

local function pickNext(car)
	local options = {}
	local from = car.from
	local here = car.to
	local inDir = Vector3.new(nodes[here].pos.X - nodes[from].pos.X, 0, nodes[here].pos.Z - nodes[from].pos.Z)
	inDir = inDir.Magnitude > 0 and inDir.Unit or Vector3.zAxis
	for o in pairs(nodes[here].out) do
		if o ~= from then
			local d = Vector3.new(nodes[o].pos.X - nodes[here].pos.X, 0, nodes[o].pos.Z - nodes[here].pos.Z)
			if d.Magnitude > 0.5 then
				-- no hairpins; prefer straight on
				local dot = d.Unit:Dot(inDir)
				if dot > -0.3 then
					local w = dot > 0.8 and 4 or 1
					for _ = 1, w do table.insert(options, o) end
				end
			end
		end
	end
	if #options == 0 then return nil end
	return options[rng:NextInteger(1, #options)]
end

local function place(car)
	for _ = 1, 30 do
		local a = usable[rng:NextInteger(1, #usable)]
		local b = next(nodes[a].out)
		local opts = {}
		for o in pairs(nodes[a].out) do table.insert(opts, o) end
		b = opts[rng:NextInteger(1, #opts)]
		local pa = laneTarget(a, b)
		local clear = farFromPlayers(pa, 120)
		for _, other in ipairs(traffic) do
			if other ~= car and other.model.PrimaryPart and (other.model.PrimaryPart.Position - pa).Magnitude < 40 then clear = false end
		end
		if clear then
			car.from, car.to = a, b
			local p0, p1, dir = laneTarget(a, b)
			local cf = CFrame.lookAt(p0 + Vector3.new(0, RIDE, 0), p0 + Vector3.new(0, RIDE, 0) + dir)
			car.model:PivotTo(cf)
			car.pos = p0 + Vector3.new(0, RIDE, 0)
			car.blocked = 0
			car.speed = 0
			return true
		end
	end
	return false
end

local function spawnCar(i)
	local modelId = MODELS[(i - 1) % #MODELS + 1]
	local model = Builder.Build(modelId, CFrame.new(0, -500, 0), { display = true, paint = PAINT[rng:NextInteger(1, #PAINT)] })
	model.Name = "Traffic_" .. modelId
	local chassis = model.PrimaryPart
	chassis.Anchored = false
	local att = Instance.new("Attachment")
	att.Parent = chassis
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = 1e7
	ap.MaxVelocity = 200
	ap.Responsiveness = 45
	ap.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e8
	ao.MaxAngularVelocity = 8
	ao.Responsiveness = 30
	ao.Parent = chassis
	model.Parent = folder
	pcall(function() chassis:SetNetworkOwner(nil) end)
	local car = { model = model, ap = ap, ao = ao, cruise = rng:NextNumber(CRUISE[1], CRUISE[2]), speed = 0, blocked = 0 }
	table.insert(traffic, car)
	if not place(car) then car.model:PivotTo(CFrame.new(0, -500, 0)) car.parked = true end
end

for i = 1, COUNT do
	spawnCar(i)
	task.wait(0.1)
end

-- obstacles ahead: player characters, every vehicle, pedestrians
local function obstacleAhead(car, pos, dir)
	local closest = math.huge
	local function check(p)
		local d = p - pos
		local along = d:Dot(dir)
		if along > 0 and along < LOOK_AHEAD then
			local side = (d - dir * along)
			if Vector3.new(side.X, 0, side.Z).Magnitude < 5 and math.abs(d.Y) < 10 then
				closest = math.min(closest, along)
			end
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if r then check(r.Position) end
	end
	for _, other in ipairs(traffic) do
		if other ~= car and other.model.PrimaryPart then check(other.model.PrimaryPart.Position) end
	end
	local veh = Workspace:FindFirstChild("Exit6Vehicles")
	for _, m in ipairs(veh and veh:GetChildren() or {}) do
		if m.PrimaryPart then check(m.PrimaryPart.Position) end
	end
	local peds = Workspace:FindFirstChild("Exit6Pedestrians")
	for _, m in ipairs(peds and peds:GetChildren() or {}) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r then check(r.Position) end
	end
	return closest
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	for _, car in ipairs(traffic) do
		if car.parked then
			-- waiting for a free spot
			if acc > 3 and place(car) then car.parked = false end
			continue
		end
		if not car.model.Parent or not car.model.PrimaryPart then continue end
		local p0, p1, dir = laneTarget(car.from, car.to)
		local target = p1 + Vector3.new(0, RIDE, 0)
		local flat = Vector3.new(target.X - car.pos.X, 0, target.Z - car.pos.Z)
		-- next corner: slow down if the road turns there
		local nextDeg = degree(car.to)
		local remaining = flat.Magnitude
		local want = car.cruise
		if nextDeg > 2 and remaining < 30 then want = math.min(want, TURN_SPEED + remaining * 0.8) end
		local gap = obstacleAhead(car, car.pos, dir)
		if gap < LOOK_AHEAD then want = math.min(want, math.max(0, (gap - 9) * 2)) end
		-- accelerate / brake smoothly
		local rate = want > car.speed and 14 or 40
		car.speed += math.clamp(want - car.speed, -rate * dt, rate * dt)
		local step = car.speed * dt
		if step >= remaining then
			-- reached the node: on to the next road
			local nxt = pickNext(car)
			if not nxt then
				if not place(car) then car.parked = true end
				continue
			end
			car.from, car.to = car.to, nxt
			car.pos = Vector3.new(target.X, car.pos.Y, target.Z)
		elseif remaining > 0.01 then
			car.pos += flat.Unit * step
		end
		-- ride the road surface
		local hit = Workspace:Raycast(car.pos + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), rayParams)
		local y = hit and (hit.Position.Y + RIDE) or car.pos.Y
		car.pos = Vector3.new(car.pos.X, y, car.pos.Z)
		local heading = flat.Magnitude > 0.1 and flat.Unit or dir
		car.ap.Position = car.pos
		car.ao.CFrame = CFrame.lookAt(Vector3.zero, heading)
		-- blocked for a long time (a parked car in the lane, a player standing there)
		if car.speed < 0.5 then car.blocked += dt else car.blocked = 0 end
		if car.blocked > 15 and farFromPlayers(car.pos, 90) then
			if not place(car) then car.parked = true end
		end
	end
	if acc > 3 then acc = 0 end
end)
