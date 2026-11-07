-- EXIT 6 pedestrians and street activity around 9th & Kerlin (master plan
-- Phase C: basic pedestrians, nearby street activity). Walkers follow the
-- built sidewalks (TileBuilderV2 "Sidewalk" strips, attribute ChesterStreet)
-- as a graph: along a strip, on to the next strip, and across the street only
-- where a sidewalk run ends (a corner), never mid-block. Hangers-out stand by
-- store fronts. Anyone can be talked to (prompt, a speech bubble).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Config = require(Shared:WaitForChild("Exit6Config"))
local P = Config.Pedestrians or {}
local WALKERS = P.walkers or 22
local HANGERS = P.hangers or 8
if WALKERS + HANGERS <= 0 then return end
local REGION = P.region or WorldConfig.REAL_BUILDINGS_REGION

local JOIN = 4           -- strip ends this close are one walkway
local CROSS = 46         -- a corner can be crossed to a walkway end this close
local QUANT = 2
local ANIM = {
	walk = "rbxassetid://507777826",
	idle = "rbxassetid://507766388",
}
local LINES = {
	"What's good?", "Chester stand up.", "You see the Union game?", "Watch the bus on 9th.",
	"Grab a platter from J & S, trust me.", "Make it out, for real.", "Long day, man.",
	"Kerlin been busy today.", "Stay safe out here.", "You from around here?",
	"They got the good wings over there.", "I'm just headed to the store.",
}
local rng = Random.new()

-- wait for the city: sidewalks exist once the street dressing finished
local t0 = os.clock()
while not Workspace:GetAttribute("CW_StreetFurnitureComplete") and os.clock() - t0 < 400 do task.wait(2) end
local world = Workspace:FindFirstChild("ChesterWorld")
if not world then return end

-- ------------------------------------------------------------- sidewalk graph
local nodes = {}      -- id -> { pos, links = {id = kind} }
local index = {}
local function key(p) return math.floor(p.X / QUANT + 0.5) .. ":" .. math.floor(p.Z / QUANT + 0.5) end
local function node(p)
	local k = key(p)
	local id = index[k]
	if not id then
		table.insert(nodes, { pos = p, links = {}, street = nil })
		id = #nodes
		index[k] = id
	end
	return id
end
local function inRegion(p)
	return p.X >= REGION.minX and p.X <= REGION.maxX and p.Z >= REGION.minZ and p.Z <= REGION.maxZ
end
local function link(a, b, kind)
	if a == b then return end
	nodes[a].links[b] = kind
	nodes[b].links[a] = kind
end
local strips = 0
for _, folder in ipairs(world:GetDescendants()) do
	if folder.Name == "Sidewalks" and folder:IsA("Folder") then
		for _, s in ipairs(folder:GetChildren()) do
			if s:IsA("BasePart") and inRegion(s.Position) then
				local cf, size = s.CFrame, s.Size
				local axis, len = cf.RightVector, size.X
				if size.Z > size.X then axis, len = cf.LookVector, size.Z end
				axis = Vector3.new(axis.X, 0, axis.Z)
				if axis.Magnitude > 0.1 and len >= 2 then
					axis = axis.Unit
					local top = s.Position + Vector3.new(0, size.Y / 2, 0)
					local a = node(top - axis * (len / 2 - 0.5))
					local b = node(top + axis * (len / 2 - 0.5))
					link(a, b, "walk")
					nodes[a].street = s:GetAttribute("ChesterStreet")
					nodes[b].street = nodes[a].street
					strips += 1
				end
			end
		end
	end
end
-- spatial hash for joining / crossings
local grid = {}
local CELL = 50
local function cellOf(p) return math.floor(p.X / CELL) .. ":" .. math.floor(p.Z / CELL) end
for id, n in ipairs(nodes) do
	local c = cellOf(n.pos)
	grid[c] = grid[c] or {}
	table.insert(grid[c], id)
end
local function around(p, r)
	local out = {}
	local cx, cz = math.floor(p.X / CELL), math.floor(p.Z / CELL)
	local reach = math.ceil(r / CELL)
	for dx = -reach, reach do
		for dz = -reach, reach do
			for _, id in ipairs(grid[(cx + dx) .. ":" .. (cz + dz)] or {}) do
				if (nodes[id].pos - p).Magnitude <= r then table.insert(out, id) end
			end
		end
	end
	return out
end
-- 1) strip ends that touch are one walkway
for id, n in ipairs(nodes) do
	for _, o in ipairs(around(n.pos, JOIN)) do
		if o ~= id and math.abs(nodes[o].pos.Y - n.pos.Y) < 3 then link(id, o, "walk") end
	end
end
-- 2) corners: a walkway end (one walking link) crosses to the nearest other
-- walkway end within CROSS, if the ground between is not a wall
local function degree(id)
	local d = 0
	for _ in pairs(nodes[id].links) do d += 1 end
	return d
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local crossings = 0
for id, n in ipairs(nodes) do
	if degree(id) == 1 then
		local best, bd = nil, CROSS
		for _, o in ipairs(around(n.pos, CROSS)) do
			if o ~= id and not n.links[o] and degree(o) <= 2 then
				local d = (nodes[o].pos - n.pos).Magnitude
				if d > JOIN and d < bd and math.abs(nodes[o].pos.Y - n.pos.Y) < 4 then
					-- nothing tall in the way (a building, a wall) at knee height
					local from = n.pos + Vector3.new(0, 2.5, 0)
					local hit = Workspace:Raycast(from, (nodes[o].pos + Vector3.new(0, 2.5, 0)) - from, rayParams)
					if not hit or hit.Instance:IsDescendantOf(world) and hit.Instance.Parent and hit.Instance.Parent.Name == "Sidewalks" then
						best, bd = o, d
					end
				end
			end
		end
		if best then
			link(id, best, "cross")
			crossings += 1
		end
	end
end
-- keep the biggest connected walkway network (stray strips strand walkers)
local comp, sizes = {}, {}
for id in ipairs(nodes) do
	if not comp[id] then
		local c = #sizes + 1
		sizes[c] = 0
		local stack = { id }
		comp[id] = c
		while #stack > 0 do
			local cur = table.remove(stack)
			sizes[c] += 1
			for o in pairs(nodes[cur].links) do
				if not comp[o] then comp[o] = c table.insert(stack, o) end
			end
		end
	end
end
local mainComp, mainSize = nil, 0
for c, s in ipairs(sizes) do if s > mainSize then mainComp, mainSize = c, s end end
local usable = {}
for id in ipairs(nodes) do if comp[id] == mainComp then table.insert(usable, id) end end
print(string.format("[EXIT6 Pedestrians] strips=%d nodes=%d crossings=%d network=%d", strips, #nodes, crossings, #usable))
if #usable < 20 then return end

-- ------------------------------------------------------------- people
local folder = Instance.new("Folder")
folder.Name = "Exit6Pedestrians"
folder.Parent = Workspace
local SKIN = { Color3.fromRGB(86, 58, 44), Color3.fromRGB(120, 84, 62), Color3.fromRGB(156, 112, 84),
	Color3.fromRGB(196, 150, 116), Color3.fromRGB(66, 44, 34), Color3.fromRGB(226, 186, 150) }
local TOPS = { Color3.fromRGB(30, 30, 34), Color3.fromRGB(230, 230, 226), Color3.fromRGB(150, 30, 40),
	Color3.fromRGB(30, 70, 150), Color3.fromRGB(60, 110, 70), Color3.fromRGB(120, 120, 128), Color3.fromRGB(214, 160, 40),
	Color3.fromRGB(110, 60, 140) }
local BOTTOMS = { Color3.fromRGB(40, 44, 60), Color3.fromRGB(30, 30, 34), Color3.fromRGB(90, 80, 70),
	Color3.fromRGB(70, 90, 130), Color3.fromRGB(120, 120, 128) }
local function pick(t) return t[rng:NextInteger(1, #t)] end

local function bubble(head, text)
	local old = head:FindFirstChild("Exit6Bubble")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "Exit6Bubble"
	bb.Size = UDim2.fromOffset(220, 46)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 60
	bb.Parent = head
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(250, 250, 248)
	l.TextColor3 = Color3.fromRGB(20, 20, 24)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 15
	l.TextWrapped = true
	l.Text = text
	l.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = l
	task.delay(4, function() if bb.Parent then bb:Destroy() end end)
end

local function person(cf)
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(SKIN)
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
	desc.TorsoColor = pick(TOPS)
	local legs = pick(BOTTOMS)
	desc.LeftLegColor, desc.RightLegColor = legs, legs
	desc.HeightScale = rng:NextNumber(0.92, 1.06)
	desc.WidthScale = rng:NextNumber(0.9, 1.1)
	local ok, npc = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not npc then return nil end
	npc.Name = "Pedestrian"
	local hum = npc:FindFirstChildOfClass("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.WalkSpeed = rng:NextNumber(6.5, 9.5)
	hum.BreakJointsOnDeath = false
	-- the player-side Animate script does not run on a server NPC
	local animate = npc:FindFirstChild("Animate")
	if animate then animate:Destroy() end
	npc:PivotTo(cf)
	npc:SetAttribute("Exit6NPC", "pedestrian")
	npc.Parent = folder
	local root = npc:FindFirstChild("HumanoidRootPart")
	if root then pcall(function() root:SetNetworkOwner(nil) end) end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local tracks = {}
	for name, id in pairs(ANIM) do
		local a = Instance.new("Animation")
		a.AnimationId = id
		local ok2, track = pcall(function() return animator:LoadAnimation(a) end)
		if ok2 then
			track.Looped = true
			tracks[name] = track
		end
	end
	local function play(name)
		for n, t in pairs(tracks) do
			if n == name then
				if not t.IsPlaying then t:Play(0.2) end
			elseif t.IsPlaying then
				t:Stop(0.2)
			end
		end
	end
	-- talk to anyone
	local head = npc:FindFirstChild("Head")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Local"
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	local talking = 0
	prompt.Triggered:Connect(function(player)
		local pr = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not pr or not root then return end
		talking = os.clock() + 3
		hum:MoveTo(root.Position)
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(pr.Position.X, root.Position.Y, pr.Position.Z))
		if head then bubble(head, pick(LINES)) end
	end)
	return npc, hum, root, play, function() return os.clock() < talking end
end

-- a walker: random walk on the graph, preferring straight on, pausing now and then
local function walker()
	local at = usable[rng:NextInteger(1, #usable)]
	local npc, hum, root, play, busy = person(CFrame.new(nodes[at].pos + Vector3.new(0, 3, 0)))
	if not npc then return end
	local prev = nil
	while npc.Parent do
		if busy() then
			play("idle")
			task.wait(0.5)
			continue
		end
		-- next node: not straight back unless it's a dead end
		local options = {}
		for o, kind in pairs(nodes[at].links) do
			if o ~= prev then
				-- crossings are taken less often than walking on
				local w = (kind == "cross") and 1 or 3
				for _ = 1, w do table.insert(options, o) end
			end
		end
		local nxt = #options > 0 and options[rng:NextInteger(1, #options)] or prev
		if not nxt then break end
		local target = nodes[nxt].pos
		play("walk")
		hum:MoveTo(target)
		local started, last, lastPos = os.clock(), os.clock(), root.Position
		local reached = false
		local conn = hum.MoveToFinished:Connect(function(ok) reached = ok or true end)
		while not reached and npc.Parent do
			task.wait(0.4)
			if busy() then break end
			if (root.Position - lastPos).Magnitude > 1 then last, lastPos = os.clock(), root.Position end
			if os.clock() - last > 4 or os.clock() - started > 30 then
				-- stuck: back on the walkway
				npc:PivotTo(CFrame.new(nodes[nxt].pos + Vector3.new(0, 3, 0)))
				break
			end
		end
		conn:Disconnect()
		if not busy() then
			prev, at = at, nxt
			if rng:NextNumber() < 0.04 then
				play("idle")
				task.wait(rng:NextNumber(2, 6))
			end
		end
	end
end

-- a hanger-out: stands by a store front, now and then says something
local function hanger(spot, look)
	local npc, hum, root, play, busy = person(CFrame.lookAt(spot + Vector3.new(0, 3, 0), look + Vector3.new(0, 3, 0)))
	if not npc then return end
	play("idle")
	while npc.Parent do
		task.wait(rng:NextNumber(10, 25))
		if not busy() and npc:FindFirstChild("Head") and rng:NextNumber() < 0.35 then
			-- only chatter when a player is around to hear it
			for _, p in ipairs(Players:GetPlayers()) do
				local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if pr and root and (pr.Position - root.Position).Magnitude < 40 then
					bubble(npc.Head, pick(LINES))
					break
				end
			end
		end
	end
end

for _ = 1, WALKERS do
	task.spawn(walker)
	task.wait(0.15)
end
-- spots outside the store doors in the region (store anchor -Z = out the door)
local spots = {}
for _, tag in ipairs({ "Exit6Store", "Exit6GasStation" }) do
	for _, m in ipairs(CollectionService:GetTagged(tag)) do
		local a = m:FindFirstChild("Exit6StoreAnchor", true)
		if a and inRegion(a.Position) then table.insert(spots, a) end
	end
end
for i = 1, math.min(HANGERS, #spots) do
	local a = table.remove(spots, rng:NextInteger(1, #spots))
	local side = (i % 2 == 0) and 1 or -1
	local w = a.Parent and (a.Parent:GetAttribute("Exit6StoreWidth") or 20) or 20
	local d = a.Parent and (a.Parent:GetAttribute("Exit6StoreDepth") or 20) or 20
	-- just outside the front wall, off to one side of the door
	local spot = (a.CFrame * CFrame.new(side * math.min(w / 2 - 2, 7), 0, -(d / 2 + 4))).Position
	local look = (a.CFrame * CFrame.new(side * 3, 0, -(d / 2 + 12))).Position
	task.spawn(hanger, spot, look)
	task.wait(0.15)
end
