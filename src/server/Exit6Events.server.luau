-- EXIT 6 social events (master plan Phase F). Every few minutes the server
-- runs an event, in rotation:
--   block party      a park court near town: speakers, DJ table, lights, dancers
--   open mic         Exit 6 Sound: perform your best released track (cash + fans)
--   pickup tournament a court: buckets there count (Exit6HoopMade), top scorer wins
-- Announced to everyone (Workspace attribute Exit6Event -> Exit6Events.client
-- banner + marker). Spending a minute at the event pays an attendance reward.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local HoopMade = ServerStorage:FindFirstChild("Exit6HoopMade") or Instance.new("BindableEvent")
HoopMade.Name = "Exit6HoopMade"
HoopMade.Parent = ServerStorage

local FIRST_AFTER, EVERY, LASTS = 120, 9 * 60, 5 * 60
local RADIUS, ATTEND_SECONDS = 55, 60
local ATTEND_CASH, ATTEND_REP = 20, 2
local TOURNEY_CASH, TOURNEY_REP = 60, 4
local TOWN = Vector3.new(2810, 0, 1518)
local DANCE = "rbxassetid://507771019"
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
local function block(parent, name, size, cf, color, material)
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

-- a court near town (block parties and tournaments)
local function nearCourt()
	local list = {}
	for _, m in ipairs(CollectionService:GetTagged("Exit6Court")) do
		local d = (m:GetPivot().Position * Vector3.new(1, 0, 1) - TOWN).Magnitude
		if d < 2600 and m:GetAttribute("Exit6CourtId") then table.insert(list, { m = m, d = d }) end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a.d < b.d end)
	return list[rng:NextInteger(1, math.min(4, #list))].m
end

-- block party set: speakers, DJ table, light posts with strings, dancers
local function partySet(cf)
	local m = Instance.new("Model")
	m.Name = "Exit6BlockParty"
	local LIGHTS = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 200, 255), Color3.fromRGB(255, 210, 80), Color3.fromRGB(150, 255, 120) }
	block(m, "DJTable", Vector3.new(8, 3.4, 3), cf * CFrame.new(0, 1.7, 0), Color3.fromRGB(26, 26, 30))
	block(m, "Decks", Vector3.new(6, 0.4, 2.2), cf * CFrame.new(0, 3.6, 0), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		block(m, "Speaker", Vector3.new(3, 6, 3), cf * CFrame.new(s * 7, 3, 0.5), Color3.fromRGB(20, 20, 22))
		block(m, "Cone", Vector3.new(2, 2, 0.2), cf * CFrame.new(s * 7, 4.2, -1.1), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
		local post = block(m, "LightPost", Vector3.new(0.5, 12, 0.5), cf * CFrame.new(s * 14, 6, 10), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
		post.CanCollide = false
	end
	for i = 0, 9 do
		local x = -13 + i * 2.9
		local bulb = block(m, "Bulb", Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(x, 11.3 - math.sin(i / 9 * math.pi) * 1.2, 10), LIGHTS[i % #LIGHTS + 1],
			Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 140, 220)
	glow.Range = 40
	glow.Brightness = 2
	glow.Parent = m:FindFirstChild("Decks")
	m.Parent = Workspace
	-- a few dancers
	for i = 1, 5 do
		local desc = Instance.new("HumanoidDescription")
		local skins = { Color3.fromRGB(86, 58, 44), Color3.fromRGB(156, 112, 84), Color3.fromRGB(226, 186, 150), Color3.fromRGB(120, 84, 62) }
		local skin = skins[rng:NextInteger(1, #skins)]
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
		desc.TorsoColor = LIGHTS[rng:NextInteger(1, #LIGHTS)]
		local ok, npc = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
		if ok and npc then
			npc.Name = "Dancer"
			npc:PivotTo(cf * CFrame.new(-8 + i * 3.2, 3, 7) * CFrame.Angles(0, math.pi, 0))
			for _, p in ipairs(npc:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end
			npc:FindFirstChildOfClass("Humanoid").DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			npc.Parent = m
			local animator = npc.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", npc.Humanoid)
			local a = Instance.new("Animation")
			a.AnimationId = DANCE
			local okT, track = pcall(function() return animator:LoadAnimation(a) end)
			if okT then track.Looped = true track:Play() end
		end
	end
	return m
end

-- ------------------------------------------------------------------ running an event
local current = nil
local KINDS = { "party", "openmic", "tourney" }
local kindIndex = 0

local function announce(ev)
	Workspace:SetAttribute("Exit6Event", ev and HttpService:JSONEncode({ name = ev.name, kind = ev.kind,
		pos = { ev.pos.X, ev.pos.Y, ev.pos.Z }, ends = ev.ends }) or nil)
end

local function finish(ev)
	if current ~= ev then return end
	current = nil
	announce(nil)
	if ev.set then ev.set:Destroy() end
	if ev.micPrompt then ev.micPrompt:Destroy() end
	if ev.hoopConn then ev.hoopConn:Disconnect() end
	if ev.kind == "tourney" then
		local best, bp = nil, 0
		for pl, pts in pairs(ev.points) do if pts > bp and pl.Parent == Players then best, bp = pl, pts end end
		if best then
			pay(best, TOURNEY_CASH, TOURNEY_REP)
			for _, pl in ipairs(Players:GetPlayers()) do
				notify(pl, string.format("%s won the tournament with %d points!", best.DisplayName, bp))
			end
			notify(best, string.format("Tournament champ! +$%d, +%d REP", TOURNEY_CASH, TOURNEY_REP))
		end
	end
end

local function start(kind)
	local ev = { kind = kind, ends = Workspace:GetServerTimeNow() + LASTS, attend = {}, paid = {}, points = {}, performed = {} }
	if kind == "party" or kind == "tourney" then
		local court = nearCourt()
		if not court then return nil end
		local cf = court:GetPivot()
		local W = court:GetAttribute("CourtWidth") or 40
		ev.pos = cf.Position
		ev.courtId = court:GetAttribute("Exit6CourtId")
		if kind == "party" then
			ev.name = "BLOCK PARTY"
			ev.set = partySet(cf * CFrame.new(0, 0, -(W / 2 + 10)) * CFrame.Angles(0, math.pi, 0))
		else
			ev.name = "PICKUP TOURNAMENT"
			ev.hoopConn = HoopMade.Event:Connect(function(player, courtId, pts)
				if courtId == ev.courtId then
					ev.points[player] = (ev.points[player] or 0) + pts
					notify(player, "Tournament: " .. ev.points[player] .. " pts")
				end
			end)
		end
	else
		local at, mic = Workspace:GetAttribute("Exit6StudioAt"), Workspace:GetAttribute("Exit6StudioMic")
		if typeof(at) ~= "Vector3" or typeof(mic) ~= "Vector3" then return nil end
		ev.name = "OPEN MIC at Exit 6 Sound"
		ev.pos = at
		local stage = block(Workspace, "OpenMicSpot", Vector3.new(1, 1, 1), CFrame.new(mic), Color3.new(1, 1, 1))
		stage.Transparency, stage.CanCollide = 1, false
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = "Perform your best track"
		pp.ObjectText = "Open mic"
		pp.HoldDuration = 0.8
		pp.MaxActivationDistance = 9
		pp.RequiresLineOfSight = false
		pp.UIOffset = Vector2.new(0, -70)
		pp.Parent = stage
		ev.micPrompt = stage
		pp.Triggered:Connect(function(player)
			if ev.performed[player] then notify(player, "You already went up tonight") return end
			local p = Profile.Get(player)
			local best
			for _, t in ipairs(p and p.music.tracks or {}) do
				if t.rel and (not best or t.q > best.q) then best = t end
			end
			if not best then notify(player, "Release a track first (record at Exit 6 Sound)") return end
			ev.performed[player] = true
			local cash = 10 + math.floor(best.q / 5)
			local fans = math.floor(best.q / 2)
			pay(player, cash, 2)
			p.music.fans += fans
			Profile.Publish(player)
			for _, pl in ipairs(Players:GetPlayers()) do
				local r = root(pl)
				if r and (r.Position - mic).Magnitude < 120 then
					notify(pl, string.format("%s performed \"%s\" - the room goes up!", player.DisplayName, best.name))
				end
			end
			notify(player, string.format("You performed \"%s\": +$%d, +%d fans, +2 REP", best.name, cash, fans))
		end)
	end
	current = ev
	announce(ev)
	for _, pl in ipairs(Players:GetPlayers()) do notify(pl, ev.name .. " is on now - check your map marker") end
	task.delay(LASTS, function() finish(ev) end)
	return ev
end

-- attendance: a minute at the event pays once
task.spawn(function()
	while true do
		task.wait(2)
		local ev = current
		if ev then
			for _, pl in ipairs(Players:GetPlayers()) do
				local r = root(pl)
				if r and not ev.paid[pl] and (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(ev.pos.X, 0, ev.pos.Z)).Magnitude < RADIUS then
					ev.attend[pl] = (ev.attend[pl] or 0) + 2
					if ev.attend[pl] >= ATTEND_SECONDS then
						ev.paid[pl] = true
						pay(pl, ATTEND_CASH, ATTEND_REP)
						notify(pl, string.format("Thanks for coming out: +$%d, +%d REP", ATTEND_CASH, ATTEND_REP))
					end
				end
			end
		end
	end
end)

-- the schedule
task.spawn(function()
	while not Workspace:GetAttribute("CW_StreetFurnitureComplete") do task.wait(2) end
	task.wait(FIRST_AFTER)
	while true do
		for _ = 1, #KINDS do
			kindIndex = kindIndex % #KINDS + 1
			if start(KINDS[kindIndex]) then break end
		end
		task.wait(EVERY)
	end
end)
