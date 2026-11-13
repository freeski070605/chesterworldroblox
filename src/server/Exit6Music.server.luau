-- EXIT 6 recording studio + music progression (master plan Phase F).
-- "Exit 6 Sound" (fictional) is placed on a free lot near 9th & Kerlin
-- (Exit6Lots). Book a session ($), then:
--   write lyrics (pen) / make a beat (beats) at the desk, record (flow) in the booth
-- Each is a rhythm take on the client (Exit6Music.client); the server keeps the
-- skills (0-100, they grow with practice), the draft and the tracks.
-- Released tracks (phone > Music) earn streams while you're in town: fans,
-- and $1 per 100 streams. Everything is saved in the profile (Profile.music).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
Workspace:SetAttribute("CW_Exit6MusicReady", false)

local Profile = require(script.Parent:WaitForChild("Exit6Profile"))
local Lots = require(script.Parent:WaitForChild("Exit6Lots"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local function remote(class, name)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local MusicTake = remote("RemoteEvent", "MusicTake")          -- server -> client: start a take
local MusicResult = remote("RemoteEvent", "MusicTakeResult")  -- client -> server: accuracy
local MusicAction = remote("RemoteFunction", "MusicAction")   -- phone: release

local SESSION_PRICE, SESSION_SECONDS = 25, 600
local TAKE_MIN_SECONDS = 7
local NAMES = { "Kerlin Nights", "9th Street Dreams", "Exit 6", "Make It Out", "Concord Ave", "Riverfront", "Union Blue",
	"Front Porch", "Late Bus", "Block Party", "Crozer Hill", "Delaware Wind", "Corner Store", "Last Stop", "Barry Lights" }
local takes = {}     -- player -> { token, kind, at }
local drafts = {}    -- player -> { pen, beats }
local rng = Random.new()

local function notify(player, text)
	player:SetAttribute("Exit6Notice", text)
	player:SetAttribute("Exit6NoticeId", (player:GetAttribute("Exit6NoticeId") or 0) + 1)
end
local function inSession(player)
	return (player:GetAttribute("Exit6StudioUntil") or 0) > Workspace:GetServerTimeNow()
end
local function startTake(player, kind)
	local p = Profile.Get(player)
	if not p then return end
	if not inSession(player) then notify(player, "Book studio time at the front desk first ($" .. SESSION_PRICE .. ")") return end
	if takes[player] then return end
	if kind == "record" and not (drafts[player] and drafts[player].pen and drafts[player].beats) then
		notify(player, "Write lyrics and make a beat at the desk first")
		return
	end
	local token = HttpService:GenerateGUID(false)
	takes[player] = { token = token, kind = kind, at = os.clock() }
	local skill = kind == "write" and p.music.pen or kind == "beat" and p.music.beats or p.music.flow
	-- better skill = a slightly slower, easier take
	MusicTake:FireClient(player, token, kind, math.clamp(0.62 - skill * 0.0015, 0.47, 0.62))
end

MusicResult.OnServerEvent:Connect(function(player, token, accuracy)
	local t = takes[player]
	takes[player] = nil
	local p = Profile.Get(player)
	if not t or not p or t.token ~= token then return end
	if os.clock() - t.at < TAKE_MIN_SECONDS then return end   -- a real take lasts longer than that
	accuracy = math.clamp(tonumber(accuracy) or 0, 0, 1)
	local m = p.music
	local key = t.kind == "write" and "pen" or t.kind == "beat" and "beats" or "flow"
	local gain = 1 + accuracy * 3
	m[key] = math.min(100, m[key] + gain)
	local score = math.floor(accuracy * 60 + m[key] * 0.4 + 0.5)
	if t.kind ~= "record" then
		drafts[player] = drafts[player] or {}
		drafts[player][key] = score
		notify(player, string.format("%s: %d%% (%s +%.1f)", t.kind == "write" and "Lyrics done" or "Beat done",
			math.floor(accuracy * 100), key, gain))
	else
		local d = drafts[player]
		drafts[player] = nil
		local q = math.floor((d.pen + d.beats + score) / 3 + 0.5)
		if #m.tracks >= 20 then table.remove(m.tracks, 1) end
		local name = NAMES[rng:NextInteger(1, #NAMES)] .. (#m.tracks > 0 and (" " .. (#m.tracks + 1)) or "")
		table.insert(m.tracks, { name = name, q = q, streams = 0 })
		notify(player, string.format("Recorded \"%s\" - quality %d. Release it from your phone (Music)", name, q))
	end
	Profile.Publish(player)
end)

MusicAction.OnServerInvoke = function(player, action, index)
	local p = Profile.Get(player)
	if not p then return false end
	if action == "release" then
		local t = p.music.tracks[tonumber(index) or 0]
		if not t or t.rel then return false end
		t.rel = os.time()
		p.music.fans += math.floor(t.q / 5)
		Profile.Publish(player)
		notify(player, "\"" .. t.name .. "\" is out! Streams come in while you're in town")
		return true
	end
	return false
end

-- streams: every minute for every released track of everyone in town
task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			local p = Profile.Get(player)
			if p and #p.music.tracks > 0 then
				local m = p.music
				local gained = 0
				for _, t in ipairs(m.tracks) do
					if t.rel then
						local age = (os.time() - t.rel) / (3600 * 24 * 7)
						local decay = math.max(0.25, 1 - age)
						local s = math.floor((6 + m.fans * 0.03) * (t.q / 100) * decay + rng:NextNumber())
						t.streams += s
						gained += s
					end
				end
				if gained > 0 then
					m.fans += math.floor(gained / 50 + rng:NextNumber())
					m.payout = (m.payout or 0) + gained
					local dollars = math.floor(m.payout / 100)
					if dollars > 0 then
						m.payout -= dollars * 100
						local ls = player:FindFirstChild("leaderstats")
						local cash = ls and ls:FindFirstChild("Chester Cash")
						if cash then cash.Value += dollars end
					end
					Profile.Publish(player)
				end
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player) takes[player], drafts[player] = nil, nil end)

-- ------------------------------------------------------------------ the studio
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
local function prompt(parent, action, object, fn, key)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.MaxActivationDistance = 8
	pp.RequiresLineOfSight = false
	if key then pp.KeyboardKeyCode, pp.GamepadKeyCode = key[1], key[2] end
	pp.Parent = parent
	pp.Triggered:Connect(fn)
	return pp
end

task.spawn(function()
	while not Workspace:GetAttribute("CW_StreetFurnitureComplete") do task.wait(2) end
	task.wait(5)
	local dealer = Workspace:GetAttribute("Exit6DealershipAt")
	local W, D, H = 34, 26, 13
	local cf, street = Lots.Find({ near = Vector3.new(2700, 60, 1700), size = Vector3.new(W + 6, 0, D + 8),
		keepClear = dealer and { { dealer, 120 } } or nil })
	if not cf then
        warn("[EXIT6 Music] no lot for the studio")
        Workspace:SetAttribute("CW_Exit6MusicStatus", "lot-unavailable")
        Workspace:SetAttribute("CW_Exit6MusicReady", true)
        return
    end
	local m = Instance.new("Model")
	m.Name = "Exit 6 Sound"
	local base = cf * CFrame.new(0, 0, 2)
	local BRICK = Color3.fromRGB(70, 66, 72)
	local ACC = Color3.fromRGB(150, 40, 190)
	local INSIDE = Color3.fromRGB(40, 38, 46)
	block(m, "Floor", Vector3.new(W, 0.4, D), base * CFrame.new(0, 0.2, 0), Color3.fromRGB(56, 50, 48), Enum.Material.WoodPlanks)
	block(m, "Roof", Vector3.new(W + 1, 0.6, D + 1), base * CFrame.new(0, H + 0.3, 0), Color3.fromRGB(40, 40, 44))
	block(m, "BackWall", Vector3.new(W, H, 0.8), base * CFrame.new(0, H / 2, D / 2), BRICK, Enum.Material.Brick)
	for _, s in ipairs({ -1, 1 }) do
		block(m, "SideWall", Vector3.new(0.8, H, D), base * CFrame.new(s * W / 2, H / 2, 0), BRICK, Enum.Material.Brick)
		local g = block(m, "Window", Vector3.new(W / 2 - 3, H - 4.4, 0.3), base * CFrame.new(s * (W / 4 + 1.5), (H - 4.4) / 2 + 0.4, -D / 2),
			Color3.fromRGB(30, 26, 40), Enum.Material.Glass)
		g.Transparency = 0.35
	end
	block(m, "Header", Vector3.new(W, 4, 0.8), base * CFrame.new(0, H - 2, -D / 2), BRICK, Enum.Material.Brick)
	local sign = block(m, "Sign", Vector3.new(W - 6, 2.6, 0.3), base * CFrame.new(0, H - 2, -D / 2 - 0.5), Color3.fromRGB(20, 18, 24))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Parent = sign
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = "EXIT 6 SOUND  -  RECORDING STUDIO"
	tl.TextColor3 = Color3.fromRGB(220, 160, 255)
	tl.Font = Enum.Font.GothamBlack
	tl.TextScaled = true
	tl.Parent = sg
	local strip = block(m, "NeonStrip", Vector3.new(W - 6, 0.25, 0.25), base * CFrame.new(0, H - 3.5, -D / 2 - 0.55), ACC, Enum.Material.Neon)
	strip.CanCollide = false
	-- inside: the booth wall between the control room and the vocal booth -
	-- a window into the booth, a doorway to walk in
	local bz = D / 2 - 8
	local function wallSeg(x0, x1, y0, y1)
		if x1 - x0 > 0.05 and y1 - y0 > 0.05 then
			block(m, "BoothWall", Vector3.new(x1 - x0, y1 - y0, 0.6), base * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, bz), INSIDE)
		end
	end
	local x0, x1 = -W / 2 + 0.8, W / 2 - 0.8
	local gx0, gx1 = -W / 4 - 5, -W / 4 + 5      -- the booth window
	local dx0, dx1 = W / 4 - 2.5, W / 4 + 2.5    -- the doorway
	wallSeg(x0, gx0, 0.4, H)
	wallSeg(gx0, gx1, 0.4, 4)
	wallSeg(gx0, gx1, 9, H)
	wallSeg(gx1, dx0, 0.4, H)
	wallSeg(dx0, dx1, 8.6, H)
	wallSeg(dx1, x1, 0.4, H)
	local booth = block(m, "BoothGlass", Vector3.new(gx1 - gx0, 5, 0.3), base * CFrame.new(-W / 4, 6.5, bz), Color3.fromRGB(120, 140, 170),
		Enum.Material.Glass)
	booth.Transparency = 0.45
	-- front desk
	local desk = block(m, "FrontDesk", Vector3.new(8, 3.4, 2.4), base * CFrame.new(-W / 2 + 6, 1.9, -D / 2 + 5), Color3.fromRGB(30, 30, 34))
	-- control room: mixing desk, monitors, couch
	local mixer = block(m, "MixingDesk", Vector3.new(12, 3.2, 4), base * CFrame.new(-W / 4, 1.8, D / 2 - 12), Color3.fromRGB(26, 26, 30))
	block(m, "Faders", Vector3.new(11, 0.2, 3), base * CFrame.new(-W / 4, 3.5, D / 2 - 12) * CFrame.Angles(math.rad(-12), 0, 0),
		Color3.fromRGB(60, 60, 70), Enum.Material.Metal)
	for _, s in ipairs({ -1, 1 }) do
		block(m, "Monitor", Vector3.new(1.6, 2.4, 1.6), base * CFrame.new(-W / 4 + s * 5, 4.8, D / 2 - 11), Color3.fromRGB(16, 16, 18))
	end
	block(m, "Couch", Vector3.new(9, 2.4, 3), base * CFrame.new(W / 4, 1.6, -D / 2 + 4), Color3.fromRGB(110, 40, 140), Enum.Material.Fabric)
	-- the booth: mic on a stand
	block(m, "MicStand", Vector3.new(0.3, 5.5, 0.3), base * CFrame.new(-W / 4, 3.1, D / 2 - 4), Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	local mic = block(m, "Mic", Vector3.new(0.7, 1.2, 0.7), base * CFrame.new(-W / 4, 6.2, D / 2 - 4), Color3.fromRGB(180, 180, 190),
		Enum.Material.Metal)
	-- the walk-in: the front is glass with a door gap in the middle (windows
	-- stop 1.5 short of centre each side)
	m.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 140, 255)
	light.Range = 30
	light.Brightness = 1.5
	light.Parent = mixer

	prompt(desk, "Book studio time ($" .. SESSION_PRICE .. ")", "Exit 6 Sound", function(player)
		if inSession(player) then notify(player, "You're booked - get to work") return end
		local ls = player:FindFirstChild("leaderstats")
		local cash = ls and ls:FindFirstChild("Chester Cash")
		if not cash or cash.Value < SESSION_PRICE then notify(player, "A session is $" .. SESSION_PRICE) return end
		cash.Value -= SESSION_PRICE
		player:SetAttribute("Exit6StudioUntil", Workspace:GetServerTimeNow() + SESSION_SECONDS)
		notify(player, "Studio's yours for 10 minutes: write and make a beat at the desk, record in the booth")
	end)
	prompt(mixer, "Write lyrics", "Pen", function(player) startTake(player, "write") end)
	prompt(mixer, "Make a beat", "Beats", function(player) startTake(player, "beat") end,
		{ Enum.KeyCode.F, Enum.KeyCode.ButtonX }).UIOffset = Vector2.new(0, 70)
	prompt(mic, "Record a track", "Booth", function(player) startTake(player, "record") end)
	Workspace:SetAttribute("Exit6StudioAt", base.Position)
	Workspace:SetAttribute("Exit6StudioMic", mic.Position)
	print(string.format("[EXIT6 Music] Exit 6 Sound on %s at (%.0f, %.0f, %.0f)", tostring(street), base.X, base.Y, base.Z))
    Workspace:SetAttribute("CW_Exit6MusicStatus", "ready")
    Workspace:SetAttribute("CW_Exit6MusicReady", true)
end)
