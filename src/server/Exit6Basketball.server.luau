-- EXIT 6 street basketball (master plan Phase F) on Chester's park courts
-- (ParkBuilder tags each court model Exit6Court). One ball per court.
--   rack (centre court)  "Get the ball" (respawns a lost one), "Start pickup game"
--   holding the ball     shoot = hold + release the meter (Exit6Basketball.client)
--   near the ball holder steal (same button)
-- Every shot is decided here: distance + meter timing (+ a little practice).
-- Solo shootaround: a streak of 5 makes pays. Pickup game: everyone on the
-- court at the start, two teams, 1s inside the arc / 2s outside, first to 11.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local BallAction = Instance.new("RemoteEvent")
BallAction.Name = "BallAction"
BallAction.Parent = remotes

local ARC = 26                  -- studs from the rim: inside = 1, outside = 2
local GAME_TO = 11
local GAME_SECONDS = 8 * 60
local STREAK = 5
local STEAL_RANGE, STEAL_CHANCE, STEAL_COOLDOWN = 6, 0.35, 1.5
local WIN_CASH, WIN_REP = 40, 3
local rng = Random.new()

local courts = {}       -- id -> court
local holding = {}      -- player -> court
local lastSteal, streak, streakPaid = {}, {}, {}

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function root(player)
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function stats(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Chester Cash"), ls and ls:FindFirstChild("Reputation")
end

local function newBall(court)
	if court.ball then court.ball:Destroy() end
	local b = Instance.new("Part")
	b.Name = "Basketball"
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(1.5, 1.5, 1.5)
	b.Color = Color3.fromRGB(214, 96, 32)
	b.Material = Enum.Material.SmoothPlastic
	b.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.4, 0.75, 1, 1)
	b.CFrame = court.rack.CFrame + Vector3.new(0, 2, 0)
	b.Parent = court.model
	local p = Instance.new("ProximityPrompt")
	p.Name = "PickUp"
	p.ActionText = "Pick up"
	p.ObjectText = "Basketball"
	p.MaxActivationDistance = 7
	p.RequiresLineOfSight = false
	p.Parent = b
	p.Triggered:Connect(function(player) court.give(player) end)
	pcall(function() b:SetNetworkOwner(nil) end)
	court.ball = b
	return b
end

local function publishGame(court)
	local g = court.game
	for _, pl in ipairs(Players:GetPlayers()) do
		if g and (g.team[pl] ~= nil) then
			pl:SetAttribute("Exit6Game", HttpService:JSONEncode({ a = g.score.A, b = g.score.B, mine = g.team[pl], to = GAME_TO,
				ends = g.ends }))
		elseif pl:GetAttribute("Exit6GameCourt") == court.id then
			pl:SetAttribute("Exit6Game", nil)
		end
		if g and g.team[pl] then pl:SetAttribute("Exit6GameCourt", court.id) end
	end
end

local function endGame(court, winner)
	local g = court.game
	if not g then return end
	court.game = nil
	for pl, team in pairs(g.team) do
		if pl.Parent == Players then
			pl:SetAttribute("Exit6Game", nil)
			pl:SetAttribute("Exit6GameCourt", nil)
			if winner and team == winner then
				local cash, rep = stats(pl)
				if cash then cash.Value += WIN_CASH end
				if rep then rep.Value += WIN_REP end
				local p = Profile.Get(pl)
				if p then p.hoops.wins += 1 Profile.Publish(pl) end
				notify(pl, string.format("You won %d-%d! +$%d, +%d REP", g.score[team], g.score[team == "A" and "B" or "A"], WIN_CASH, WIN_REP))
			elseif winner then
				notify(pl, string.format("Game over: %d-%d. Run it back?", g.score[team], g.score[team == "A" and "B" or "A"]))
			else
				notify(pl, "Game over")
			end
		end
	end
end

-- release the ball from a player's hand
local function drop(player)
	local court = holding[player]
	holding[player] = nil
	player:SetAttribute("Exit6HasBall", nil)
	if court and court.ball then
		local w = court.ball:FindFirstChild("HoldWeld")
		if w then w:Destroy() end
		court.ball.CanCollide = true
		court.ball.Massless = false
		court.holder = nil
		court.ball.PickUp.Enabled = true
		pcall(function() court.ball:SetNetworkOwner(nil) end)
	end
end

local function setup(model)
	if model:GetAttribute("Exit6CourtId") then return end
	local rims = {}
	for _, c in ipairs(model:GetChildren()) do
		if c.Name == "Rim" and c:IsA("BasePart") then table.insert(rims, c) end
	end
	if #rims < 2 then return end
	local id = "court" .. (#courts + 1)
	model:SetAttribute("Exit6CourtId", id)
	local pivot = model:GetPivot()
	local L, W = model:GetAttribute("CourtLength") or 60, model:GetAttribute("CourtWidth") or 40
	local rack = Instance.new("Part")
	rack.Name = "BallRack"
	rack.Size = Vector3.new(2, 0.4, 2)
	rack.Anchored = true
	rack.CanCollide = false
	rack.Transparency = 1
	rack.CFrame = pivot * CFrame.new(0, 1, W / 2 + 2)
	rack.Parent = model
	local court = { id = id, model = model, rims = rims, pivot = pivot, L = L, W = W, rack = rack }
	courts[id] = court
	table.insert(courts, court)

	local function onCourt(pos)
		local l = pivot:PointToObjectSpace(pos)
		return math.abs(l.X) <= L / 2 + 6 and math.abs(l.Z) <= W / 2 + 8
	end
	court.onCourt = onCourt

	function court.give(player)
		local r = root(player)
		local hand = player.Character and (player.Character:FindFirstChild("RightHand") or player.Character:FindFirstChild("Right Arm"))
		if not r or not hand or holding[player] then return end
		if court.holder and court.holder ~= player then return end
		local b = court.ball or newBall(court)
		if (b.Position - r.Position).Magnitude > 12 and (rack.Position - r.Position).Magnitude > 12 then return end
		if b.Anchored then return end   -- in the air
		b.CanCollide = false
		b.Massless = true
		b.CFrame = hand.CFrame * CFrame.new(0, -1.1, -0.4)
		local w = Instance.new("WeldConstraint")
		w.Name = "HoldWeld"
		w.Part0, w.Part1 = hand, b
		w.Parent = b
		b.PickUp.Enabled = false
		court.holder = player
		holding[player] = court
		player:SetAttribute("Exit6HasBall", id)
	end

	local get = Instance.new("ProximityPrompt")
	get.ActionText = "Get the ball"
	get.ObjectText = "Court"
	get.MaxActivationDistance = 9
	get.RequiresLineOfSight = false
	get.Parent = rack
	get.Triggered:Connect(function(player)
		if court.holder then notify(player, "Someone has the ball - steal it!") return end
		if court.ball and not court.ball.Anchored and onCourt(court.ball.Position) and (court.ball.Position - rack.Position).Magnitude > 14 then
			notify(player, "The ball's loose on the court")
			return
		end
		newBall(court)
		court.give(player)
	end)
	local start = Instance.new("ProximityPrompt")
	start.ActionText = "Start pickup game (to " .. GAME_TO .. ")"
	start.ObjectText = "Court"
	start.HoldDuration = 1
	start.KeyboardKeyCode = Enum.KeyCode.F
	start.GamepadKeyCode = Enum.KeyCode.ButtonX
	start.MaxActivationDistance = 9
	start.RequiresLineOfSight = false
	start.UIOffset = Vector2.new(0, 70)
	start.Parent = rack
	start.Triggered:Connect(function(player)
		if court.game then notify(player, "A game's already on") return end
		local on = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local r = root(pl)
			if r and onCourt(r.Position) then table.insert(on, pl) end
		end
		if #on < 2 then notify(player, "Need at least 2 players on the court") return end
		-- teams: split by which end of the court each player stands at
		table.sort(on, function(a, b)
			return pivot:PointToObjectSpace(root(a).Position).X < pivot:PointToObjectSpace(root(b).Position).X
		end)
		local team = {}
		for i, pl in ipairs(on) do team[pl] = (i <= #on / 2) and "A" or "B" end
		-- team A attacks the rim at +X, team B the one at -X
		table.sort(rims, function(a, b) return pivot:PointToObjectSpace(a.Position).X > pivot:PointToObjectSpace(b.Position).X end)
		court.game = { team = team, score = { A = 0, B = 0 }, target = { A = rims[1], B = rims[#rims] },
			ends = Workspace:GetServerTimeNow() + GAME_SECONDS }
		local g = court.game
		for pl in pairs(team) do notify(pl, "Pickup game! First to " .. GAME_TO .. " - 1s inside the arc, 2s outside") end
		publishGame(court)
		task.delay(GAME_SECONDS, function() if court.game == g then endGame(court, nil) end end)
	end)
	newBall(court)
end

-- the shot: decided here, then the ball flies for everyone to see
local function shoot(player, meter)
	local court = holding[player]
	local r = root(player)
	if not court or not r or court.ball.Anchored then return end
	meter = math.clamp(tonumber(meter) or 0, 0, 1.2)
	local g = court.game
	local team = g and g.team[player]
	local rim = team and g.target[team]
	if not rim then
		rim = court.rims[1]
		for _, rr in ipairs(court.rims) do
			if (flat(rr.Position - r.Position)).Magnitude < (flat(rim.Position - r.Position)).Magnitude then rim = rr end
		end
	end
	local d = flat(rim.Position - r.Position).Magnitude
	local base = d < 8 and 0.75 or d < 18 and 0.56 or d < ARC and 0.44 or d < 40 and 0.3 or 0.07
	local q = 1 - math.min(1, math.abs(meter - 0.9) / 0.35)
	local prof = Profile.Get(player)
	local practice = prof and math.min(0.05, (prof.hoops.makes or 0) * 0.0002) or 0
	local chance = math.clamp(base * (0.35 + 0.75 * q) + practice, 0.02, 0.95)
	local made = rng:NextNumber() < chance
	-- release
	local b = court.ball
	drop(player)
	b.Anchored = true
	b.CanCollide = false
	b.PickUp.Enabled = false
	local from = b.Position
	local to = rim.Position + Vector3.new(0, 0.6, 0)
	if not made then
		local off = flat(to - from).Unit:Cross(Vector3.yAxis) * (rng:NextNumber() < 0.5 and 1 or -1)
		to += off * rng:NextNumber(0.9, 1.4) + flat(to - from).Unit * rng:NextNumber(-0.6, 0.9)
	end
	local apex = math.max(from.Y, to.Y) + 4 + d * 0.18
	local dur = 0.55 + d * 0.014
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < dur do
			local a = (os.clock() - t0) / dur
			local p = from:Lerp(to, a)
			local h = (1 - (2 * a - 1) ^ 2) * (apex - math.max(from.Y, to.Y)) + from.Y + (to.Y - from.Y) * a
			b.CFrame = CFrame.new(p.X, h, p.Z)
			task.wait()
		end
		b.CFrame = CFrame.new(made and rim.Position - Vector3.new(0, 1.2, 0) or to)
		b.Anchored = false
		b.CanCollide = true
		b.PickUp.Enabled = true
		pcall(function() b:SetNetworkOwner(nil) end)
		if not made then
			b.AssemblyLinearVelocity = (flat(to - rim.Position).Unit * 14) + Vector3.new(0, 10, 0)
		end
		-- scoring
		local pts = d < ARC and 1 or 2
		if made then
			if prof then prof.hoops.makes += 1 end
			-- events (tournament scoring) listen for buckets
			local ev = game:GetService("ServerStorage"):FindFirstChild("Exit6HoopMade")
			if ev then ev:Fire(player, court.id, pts) end
			if g and court.game == g and team then
				g.score[team] += pts
				publishGame(court)
				for pl in pairs(g.team) do
					if pl.Parent == Players then notify(pl, string.format("%s scores %d!  %d - %d", player.DisplayName, pts, g.score.A, g.score.B)) end
				end
				if g.score[team] >= GAME_TO then endGame(court, team) end
			else
				streak[player] = (streak[player] or 0) + 1
				if streak[player] % STREAK == 0 then
					local now = os.clock()
					streakPaid[player] = streakPaid[player] or {}
					local recent = 0
					for _, t in ipairs(streakPaid[player]) do if now - t < 600 then recent += 1 end end
					if recent < 6 then
						table.insert(streakPaid[player], now)
						local cash, rep = stats(player)
						if cash then cash.Value += 5 end
						if rep then rep.Value += 1 end
						notify(player, streak[player] .. " in a row! +$5, +1 REP")
					else
						notify(player, streak[player] .. " in a row!")
					end
				else
					notify(player, (pts == 2 and "Bucket from deep" or "Bucket") .. " - " .. streak[player] .. " straight")
				end
			end
		else
			if not g then streak[player] = 0 end
			notify(player, d > 40 and "Airball" or "Off the rim")
		end
	end)
end

local function steal(player)
	local r = root(player)
	if not r then return end
	local now = os.clock()
	if lastSteal[player] and now - lastSteal[player] < STEAL_COOLDOWN then return end
	for holder, court in pairs(holding) do
		local hr = root(holder)
		if holder ~= player and hr and (hr.Position - r.Position).Magnitude <= STEAL_RANGE then
			local g = court.game
			if g and g.team[player] and g.team[player] == g.team[holder] then return end
			lastSteal[player] = now
			if rng:NextNumber() < STEAL_CHANCE then
				drop(holder)
				court.give(player)
				notify(player, "Stolen! Your ball")
				notify(holder, player.DisplayName .. " stole the ball")
			else
				notify(player, "Missed the steal")
			end
			return
		end
	end
end

BallAction.OnServerEvent:Connect(function(player, action, value)
	if action == "shoot" then shoot(player, value)
	elseif action == "steal" then steal(player) end
end)

-- a ball carried off the court, or a player gone: back to the rack
task.spawn(function()
	while true do
		task.wait(1)
		for player, court in pairs(holding) do
			local r = root(player)
			if player.Parent ~= Players or not r or not court.onCourt(r.Position) and (r.Position - court.rack.Position).Magnitude > 90 then
				drop(player)
				newBall(court)
			end
		end
		for _, court in ipairs(courts) do
			local b = court.ball
			if b and not court.holder and not b.Anchored and ((b.Position - court.rack.Position).Magnitude > 120 or b.Position.Y < court.pivot.Y - 30) then
				newBall(court)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player)
	if holding[player] then drop(player) end
	for _, court in ipairs(courts) do
		local g = court.game
		if g and g.team[player] then
			g.team[player] = nil
			local left = 0
			for _ in pairs(g.team) do left += 1 end
			if left < 2 then endGame(court, nil) end
		end
	end
	lastSteal[player], streak[player], streakPaid[player] = nil, nil, nil
end)
local function onDied(player)
	player.CharacterRemoving:Connect(function() if holding[player] then drop(player) end end)
end
Players.PlayerAdded:Connect(onDied)
for _, pl in ipairs(Players:GetPlayers()) do onDied(pl) end

for _, m in ipairs(CollectionService:GetTagged("Exit6Court")) do task.spawn(setup, m) end
CollectionService:GetInstanceAddedSignal("Exit6Court"):Connect(function(m) task.spawn(setup, m) end)
