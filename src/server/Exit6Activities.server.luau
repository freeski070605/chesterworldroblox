-- EXIT 6 activities (master plan Phase F, more sports and activities):
--   time trials      three routes through the city's real streets, generated
--                    from the road network near 9th & Kerlin; start from your
--                    car at the start marker, drive the checkpoints. Beat par
--                    for cash; best times are saved (Profile.trials).
--   penalty shootout Subaru Park: five kicks against the keeper (aim left /
--                    middle / right + power, Exit6Activities.client). 4+ pays.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local Activity = Instance.new("RemoteEvent")
Activity.Name = "Activity"
Activity.Parent = remotes

local rng = Random.new()
local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function root(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function pay(player, cash, rep)
	local ls = player:FindFirstChild("leaderstats")
	local c, r = ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
	if c then c.Value += cash end
	if r then r.Value += rep end
end
local function myCar(player)
	local folder = Workspace:FindFirstChild("Exit6Vehicles")
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		if m:GetAttribute("Owner") == player.UserId and m:GetAttribute("Driver") == player.UserId then return m end
	end
	return nil
end
local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

while not Workspace:GetAttribute("CW_StreetFurnitureComplete") do task.wait(2) end
local world = Workspace:FindFirstChild("ChesterWorld")

-- ================================================================== time trials
local CP_EVERY, CP_REACH = 220, 30
local ROUTE_LEN = 1800
local PAR_SPEED = 70           -- studs/s
local WIN_CASH, WIN_REP, FIRST_CASH = 30, 2, 15
local ROUTES = { { id = "kerlin", name = "Kerlin Sprint", near = Vector3.new(2810, 0, 1518) },
	{ id = "ninth", name = "Ninth Street Loop", near = Vector3.new(2300, 0, 1150) },
	{ id = "concord", name = "Concord Run", near = Vector3.new(3100, 0, 2000) } }

-- road graph of the region (the tiles' Roads folders; never GetDescendants)
local REGION = WorldConfig.REAL_BUILDINGS_REGION
local nodes, index = {}, {}
local function key(p) return math.floor(p.X / 3 + 0.5) .. ":" .. math.floor(p.Z / 3 + 0.5) end
local function node(p)
	local k = key(p)
	if not index[k] then table.insert(nodes, { pos = p, out = {} }) index[k] = #nodes end
	return index[k]
end
local function link(a, b) if a ~= b then nodes[a].out[b] = true nodes[b].out[a] = true end end
for _, tile in ipairs(world and world:GetChildren() or {}) do
	local f = tile:FindFirstChild("Roads")
	if f then
		task.wait()
		for _, p in ipairs(f:GetChildren()) do
			local pos = p:IsA("BasePart") and p.Position
			if pos and p:GetAttribute("ChesterStreet") and not p:GetAttribute("CW_HighwayProfiled") and pos.X > REGION.minX - 400 and pos.X < REGION.maxX + 400
				and pos.Z > REGION.minZ - 400 and pos.Z < REGION.maxZ + 400 then
				local size = p.Size
				local axis, len, width = p.CFrame.RightVector, size.X, size.Z
				if size.Z > size.X then axis, len, width = p.CFrame.LookVector, size.Z, size.X end
				if width >= 14 and len >= 4 then
					local top = pos + Vector3.new(0, size.Y / 2, 0)
					link(node(top - axis * len / 2), node(top + axis * len / 2))
				end
			end
		end
	end
end
local grid = {}
for id, n in ipairs(nodes) do
	local k = math.floor(n.pos.X / 40) .. ":" .. math.floor(n.pos.Z / 40)
	grid[k] = grid[k] or {}
	table.insert(grid[k], id)
end
for id, n in ipairs(nodes) do
	local cx, cz = math.floor(n.pos.X / 40), math.floor(n.pos.Z / 40)
	for dx = -1, 1 do
		for dz = -1, 1 do
			for _, o in ipairs(grid[(cx + dx) .. ":" .. (cz + dz)] or {}) do
				if o ~= id and (nodes[o].pos - n.pos).Magnitude < 34 then link(id, o) end
			end
		end
	end
end

local function buildRoute(spec, seed)
	local r = Random.new(seed)
	local start, bd
	for id, n in ipairs(nodes) do
		local d = (n.pos * Vector3.new(1, 0, 1) - spec.near).Magnitude
		if next(n.out) and (not bd or d < bd) then start, bd = id, d end
	end
	if not start then return nil end
	local path, seen = { start }, { [start] = true }
	local length, prevDir = 0, nil
	local cur = start
	while length < ROUTE_LEN do
		local best, bestScore
		for o in pairs(nodes[cur].out) do
			if not seen[o] then
				local d = nodes[o].pos - nodes[cur].pos
				local dir = Vector3.new(d.X, 0, d.Z)
				if dir.Magnitude > 0.5 then
					dir = dir.Unit
					local score = (prevDir and dir:Dot(prevDir) or 0) + r:NextNumber() * 0.9
					if not bestScore or score > bestScore then best, bestScore = o, score end
				end
			end
		end
		if not best then break end
		local step = nodes[best].pos - nodes[cur].pos
		length += Vector3.new(step.X, 0, step.Z).Magnitude
		prevDir = Vector3.new(step.X, 0, step.Z).Unit
		seen[best] = true
		table.insert(path, best)
		cur = best
	end
	if length < 600 then return nil end
	-- checkpoints along the path
	local cps, acc = {}, 0
	for i = 2, #path do
		local a, b = nodes[path[i - 1]].pos, nodes[path[i]].pos
		acc += (Vector3.new(b.X - a.X, 0, b.Z - a.Z)).Magnitude
		if acc >= CP_EVERY or i == #path then
			table.insert(cps, b)
			acc = 0
		end
	end
	return { id = spec.id, name = spec.name, start = nodes[start].pos, cps = cps, length = length, par = math.floor(length / PAR_SPEED) }
end

local trials = {}      -- player -> run
local routes = {}
local function publishTrial(player)
	local run = trials[player]
	if not run then player:SetAttribute("Exit6Trial", nil) return end
	local cp = run.route.cps[run.next]
	player:SetAttribute("Exit6Trial", HttpService:JSONEncode({ name = run.route.name, cp = { cp.X, cp.Y, cp.Z }, n = run.next,
		total = #run.route.cps, start = run.started, par = run.route.par }))
end
for i, spec in ipairs(ROUTES) do
	local route = buildRoute(spec, 1000 + i)
	if route then
		table.insert(routes, route)
		-- start marker: a lit post by the road, prompt to start from the car
		local post = part(Workspace, "TrialStart_" .. route.id, Vector3.new(1.2, 10, 1.2), CFrame.new(route.start + Vector3.new(0, 5, 0)),
			Color3.fromRGB(229, 157, 53), Enum.Material.Neon)
		post.CanCollide = false
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(200, 44)
		bb.StudsOffset = Vector3.new(0, 7, 0)
		bb.MaxDistance = 400
		bb.Parent = post
		local l = Instance.new("TextLabel")
		l.Size = UDim2.fromScale(1, 1)
		l.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
		l.BackgroundTransparency = 0.15
		l.TextColor3 = Color3.fromRGB(229, 157, 53)
		l.Font = Enum.Font.GothamBlack
		l.TextSize = 14
		l.Text = "TIME TRIAL\n" .. route.name .. "  (par " .. route.par .. "s)"
		l.Parent = bb
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Start time trial"
		pp.ObjectText = route.name
		pp.KeyboardKeyCode = Enum.KeyCode.Z
		pp.GamepadKeyCode = Enum.KeyCode.ButtonY
		pp.MaxActivationDistance = 30
		pp.RequiresLineOfSight = false
		pp.Parent = post
		pp.Triggered:Connect(function(player)
			if trials[player] then notify(player, "Already on a run") return end
			if not myCar(player) then notify(player, "Pull up here in your car to start") return end
			trials[player] = { route = route, next = 1, started = Workspace:GetServerTimeNow() }
			publishTrial(player)
			notify(player, route.name .. ": GO! " .. #route.cps .. " checkpoints, par " .. route.par .. "s")
		end)
	end
end
print(string.format("[EXIT6 Activities] roadNodes=%d trialRoutes=%d", #nodes, #routes))

task.spawn(function()
	while true do
		task.wait(0.2)
		for player, run in pairs(trials) do
			local car = myCar(player)
			local elapsed = Workspace:GetServerTimeNow() - run.started
			if player.Parent ~= Players or not car or elapsed > run.route.par * 3 then
				trials[player] = nil
				if player.Parent == Players then
					publishTrial(player)
					notify(player, not car and "Time trial over - you left your car" or "Time trial over - out of time")
				end
			else
				local cp = run.route.cps[run.next]
				local p = car.PrimaryPart.Position
				if (Vector3.new(p.X - cp.X, 0, p.Z - cp.Z)).Magnitude < CP_REACH then
					run.next += 1
					if run.next > #run.route.cps then
						trials[player] = nil
						publishTrial(player)
						local t = math.floor(elapsed * 10) / 10
						local prof = Profile.Get(player)
						local best = prof and prof.trials[run.route.id]
						local first = prof and best == nil
						if prof and (not best or t < best) then prof.trials[run.route.id] = t Profile.Publish(player) end
						local cash, rep = 0, 0
						if first then cash += FIRST_CASH end
						if t <= run.route.par then cash += WIN_CASH rep += WIN_REP end
						if cash > 0 or rep > 0 then pay(player, cash, rep) end
						notify(player, string.format("%s: %.1fs (par %ds)%s%s", run.route.name, t, run.route.par,
							(best and t < best) and " - NEW BEST" or "", cash > 0 and (" +$" .. cash) or ""))
					else
						publishTrial(player)
					end
				end
			end
		end
	end
end)

-- ================================================================== penalty shootout
local KICKS = 5
local PEN_CASH, PEN_REP, PEN_COOLDOWN = 25, 2, 40
local GOAL_W, GOAL_H, SPOT = 28, 9.5, 43
local pens = {}
local lastPens = {}

local function setupPens()
	local t0 = os.clock()
	while not Workspace:GetAttribute("Exit6SubaruPitch") and os.clock() - t0 < 120 do task.wait(2) end
	local frame = Workspace:GetAttribute("Exit6SubaruPitch")
	if typeof(frame) ~= "CFrame" then return end
	local L = Workspace:GetAttribute("Exit6SubaruPitchL") or 330
	-- the goal at one end of the pitch, facing down the field (-X)
	local goalCf = frame * CFrame.new(L / 2 - 6, 0.7, 0) * CFrame.Angles(0, math.rad(90), 0)
	local m = Instance.new("Model")
	m.Name = "Exit6PenaltyGoal"
	local WHITE = Color3.fromRGB(240, 240, 240)
	for _, s in ipairs({ -1, 1 }) do
		part(m, "Post", Vector3.new(0.6, GOAL_H, 0.6), goalCf * CFrame.new(s * GOAL_W / 2, GOAL_H / 2, 0), WHITE)
	end
	part(m, "Crossbar", Vector3.new(GOAL_W + 0.6, 0.6, 0.6), goalCf * CFrame.new(0, GOAL_H, 0), WHITE)
	local net = part(m, "Net", Vector3.new(GOAL_W, GOAL_H, 0.2), goalCf * CFrame.new(0, GOAL_H / 2, 6), Color3.fromRGB(220, 220, 220), Enum.Material.Fabric)
	net.Transparency = 0.6
	-- goalCf -Z faces the field; the spot is SPOT studs out
	local spotCf = goalCf * CFrame.new(0, 0, -SPOT)
	local spot = part(m, "PenaltySpot", Vector3.new(1.4, 0.1, 1.4), spotCf * CFrame.new(0, 0.05, 0), WHITE)
	spot.CanCollide = false
	m.Parent = Workspace
	-- the keeper
	local desc = Instance.new("HumanoidDescription")
	desc.TorsoColor = Color3.fromRGB(240, 200, 30)
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = Color3.fromRGB(120, 84, 62), Color3.fromRGB(120, 84, 62), Color3.fromRGB(120, 84, 62)
	local ok, keeper = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	local keeperHome = goalCf * CFrame.new(0, 2.9, -1) * CFrame.Angles(0, math.pi, 0)
	if ok and keeper then
		keeper.Name = "Keeper"
		for _, p in ipairs(keeper:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
		keeper:PivotTo(keeperHome)
		keeper.Parent = m
	end
	local ball = part(m, "PenaltyBall", Vector3.new(1.6, 1.6, 1.6), spotCf * CFrame.new(0, 0.8, 0), Color3.fromRGB(245, 245, 245))
	ball.Shape = Enum.PartType.Ball
	ball.CanCollide = false
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Penalty shootout"
	pp.ObjectText = "Subaru Park"
	pp.HoldDuration = 0.5
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = spot
	pp.Triggered:Connect(function(player)
		if next(pens) then notify(player, "Someone's on the spot - wait your turn") return end
		local since = lastPens[player.UserId] and os.clock() - lastPens[player.UserId]
		if since and since < PEN_COOLDOWN then notify(player, "Catch your breath - " .. math.ceil(PEN_COOLDOWN - since) .. "s") return end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		pens[player] = { kick = 1, goals = 0, walk = hum.WalkSpeed, busy = false }
		hum.WalkSpeed = 0
		player.Character:PivotTo(spotCf * CFrame.new(0, 3, 4))
		player:SetAttribute("Exit6Pens", HttpService:JSONEncode({ kick = 1, goals = 0, of = KICKS }))
		notify(player, "Penalty shootout: aim with A / D (D-pad), hold and release to shoot")
	end)

	local function finishPens(player)
		local run = pens[player]
		pens[player] = nil
		lastPens[player.UserId] = os.clock()
		player:SetAttribute("Exit6Pens", nil)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = run.walk end
		local prof = Profile.Get(player)
		if prof and run.goals > (prof.pens.best or 0) then prof.pens.best = run.goals Profile.Publish(player) end
		if run.goals >= 4 then
			pay(player, PEN_CASH, PEN_REP)
			notify(player, string.format("%d of %d! +$%d, +%d REP", run.goals, KICKS, PEN_CASH, PEN_REP))
		else
			notify(player, string.format("%d of %d. The keeper had your number", run.goals, KICKS))
		end
	end

	Activity.OnServerEvent:Connect(function(player, action, aim, power)
		local run = pens[player]
		if action ~= "kick" or not run or run.busy then return end
		run.busy = true
		aim = math.clamp(math.floor(tonumber(aim) or 0), -1, 1)
		power = math.clamp(tonumber(power) or 0, 0, 1.3)
		local roll = rng:NextNumber()
		local dive = roll < 0.38 and -1 or roll < 0.62 and 0 or 1
		local over = power > 1.05
		local weak = power < 0.45
		local saved = not over and dive == aim and (power < 0.9 or rng:NextNumber() < 0.65)
		saved = saved or (weak and rng:NextNumber() < 0.6)
		local goal = not over and not saved
		-- animate: ball to its spot in the goal, keeper dives
		local target = goalCf * CFrame.new(aim * (GOAL_W / 2 - 3), over and GOAL_H + 3 or (power > 0.8 and 6 or 2), 1.5)
		if saved then target = goalCf * CFrame.new(dive * (GOAL_W / 2 - 4), 2.5, -1.5) end
		local from = ball.CFrame
		local k = m:FindFirstChild("Keeper")
		local t0 = os.clock()
		local dur = 0.55
		while os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			ball.CFrame = from:Lerp(target, a) + Vector3.new(0, math.sin(a * math.pi) * 2, 0)
			if k then k:PivotTo(keeperHome * CFrame.new(-dive * (GOAL_W / 2 - 4) * math.min(1, a * 1.4), 0, 0) * CFrame.Angles(0, 0, math.rad(-dive * 70 * math.min(1, a * 1.4)))) end
			task.wait()
		end
		if goal then run.goals += 1 end
		notify(player, goal and "GOAL!" or (over and "Over the bar" or "Saved!"))
		task.wait(1.2)
		ball.CFrame = spotCf * CFrame.new(0, 0.8, 0)
		if k then k:PivotTo(keeperHome) end
		run.kick += 1
		run.busy = false
		if run.kick > KICKS then
			finishPens(player)
		else
			player:SetAttribute("Exit6Pens", HttpService:JSONEncode({ kick = run.kick, goals = run.goals, of = KICKS }))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		if pens[player] then pens[player] = nil end
		lastPens[player.UserId] = nil
	end)
	print("[EXIT6 Activities] penalty shootout at Subaru Park")
end
task.spawn(setupPens)
Players.PlayerRemoving:Connect(function(player) trials[player] = nil end)
