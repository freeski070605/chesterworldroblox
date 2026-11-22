-- EXIT 6 Bike Life (client): the Exit 6 Motors bike shop panel and the
-- rideout waypoint. Everything goes through Exit6Remotes.BikeLifeAction and is
-- decided by Exit6BikeLife.server; this only draws and forwards button presses.
--   Bike shop  opened by the kiosk / display-ride prompts (OpenBikeShop):
--              pick a ride, then buy / test ride, or upgrade engine and
--              suspension, paint, accent and race number for one you own.
--              Gamepad (A select, B back / close), mouse and touch.
--   Waypoint   the next rideout stop: a ring on the street, a beam from the
--              rider and the distance, whenever you're in a rideout.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local Action = remotes:WaitForChild("BikeLifeAction", 120)
local Changed = remotes:WaitForChild("BikeLifeChanged", 120)
local OpenShop = remotes:WaitForChild("OpenBikeShop", 120)
if not (Action and Changed and OpenShop) then return end

local INK = Color3.fromRGB(18, 21, 27)
local CARD = Color3.fromRGB(37, 44, 56)
local ACCENT = Color3.fromRGB(229, 157, 53)
local TEXT = Color3.fromRGB(245, 245, 242)
local DIM = Color3.fromRGB(155, 164, 177)
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end

local gui = new("ScreenGui", { Name = "Exit6BikeShop", ResetOnSpawn = false, DisplayOrder = 55 }, player:WaitForChild("PlayerGui"))
local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(470, 460),
	BackgroundColor3 = INK, BackgroundTransparency = 0.04, Visible = false }, gui)
round(panel, 14)
new("UISizeConstraint", { MaxSize = Vector2.new(470, 460) }, panel)
local title = new("TextLabel", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -80, 0, 30), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, Text = "EXIT 6 MOTORS" }, panel)
local sub = new("TextLabel", { Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 20), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local list = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -24, 1, -104), BackgroundTransparency = 1,
	BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false }, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
new("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -8), Size = UDim2.new(1, -36, 0, 22),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "A / CLICK  SELECT      B / BACKSPACE  BACK" }, panel)
local closeB = new("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = CARD, Text = "X", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = TEXT, Selectable = false }, panel)
round(closeB, 8)

local function row(order, left, right, onClick, color)
	local b = new("TextButton", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = color or CARD,
		AutoButtonColor = onClick ~= nil, Selectable = onClick ~= nil, Active = onClick ~= nil, Text = "" }, list)
	round(b, 8)
	new("TextLabel", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = TEXT, Text = left, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd }, b)
	new("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 130, 1, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = ACCENT, Text = right or "",
		TextXAlignment = Enum.TextXAlignment.Right }, b)
	if onClick then b.Activated:Connect(onClick) end
	return b
end

local info = nil       -- Action "shop" result
local focus = nil      -- model id being looked at, nil = the list
local busy = false
local draw

local function refresh()
	local ok, r = pcall(function() return Action:InvokeServer("shop") end)
	if ok and type(r) == "table" then info = r end
end
local function send(cmd, value)
	if busy then return end
	busy = true
	local ok, r = pcall(function() return Action:InvokeServer(cmd, value) end)
	if ok and type(r) == "table" and type(r.shop) == "table" then info = r.shop else refresh() end
	busy = false
	if cmd == "testride" and ok and type(r) == "table" and r.ok then
		panel.Visible = false
		GuiService.SelectedObject = nil
		return
	end
	draw()
end
local function close()
	panel.Visible = false
	focus = nil
	GuiService.SelectedObject = nil
end
closeB.Activated:Connect(close)

local function entryFor(id)
	for _, e in ipairs(info and info.rides or {}) do
		if e.model == id then return e end
	end
end

draw = function()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if not info then
		row(1, "Loading...", "")
		return
	end
	local first
	local function pick(b) if b and b.Selectable and not first then first = b end return b end
	sub.Text = string.format("BIKE LIFE  |  $%d  |  REP %d%s", info.cash, info.rep, info.atShop and "" or "  |  walk up to the kiosk")
	local e = focus and entryFor(focus)
	if not e then
		title.Text = "EXIT 6 MOTORS"
		for i, r in ipairs(info.rides) do
			local right
			if r.owned then right = "OWNED"
			elseif r.rep > info.rep then right = "REP " .. r.rep
			else right = "$" .. r.price end
			pick(row(i, r.name, right, function() focus = r.model draw() end))
		end
		row(20, "Dirt bikes balance and lean; quads stay flat.", "")
		row(21, "Test rides are free - 2 minutes near the lot.", "")
	else
		title.Text = string.upper(e.name)
		local n = 0
		local function line(l, r, f, c) n += 1 return pick(row(n, l, r, f, c)) end
		row(0, string.format("Top %d mph   Accel %d   Grip %.2f", e.stats.topSpeed, e.stats.accel, e.stats.grip), "")
		if not e.owned then
			local locked = e.rep > info.rep
			line(locked and ("Needs " .. e.rep .. " reputation") or ("Buy for $" .. e.price), locked and "LOCKED" or "BUY",
				(not locked) and function() send("buy", e.item) end or nil, Color3.fromRGB(40, 110, 60))
			line("Free test ride (2 min)", "RIDE", function() send("testride", e.model) end)
		else
			for _, kind in ipairs({ "engine", "handling" }) do
				local u = e.upgrades[kind]
				if u.level >= u.max then
					line(u.name .. "  stage " .. u.level .. "/" .. u.max, "MAX")
				else
					local need = (u.rep or 0) > info.rep
					line(string.format("%s  stage %d -> %d", u.name, u.level, u.level + 1), need and ("REP " .. u.rep) or ("$" .. u.price),
						function() send("upgrade", { model = e.model, kind = kind }) end)
				end
			end
			local paints = info.paints
			local paintName = e.paint == 0 and "Factory graphics" or (paints[e.paint] and paints[e.paint].name or "?")
			line("Plastics: " .. paintName, "$" .. info.paintPrice .. " next",
				function() send("custom", { model = e.model, field = "paint", value = (e.paint + 1) % (#paints + 1) }) end)
			local accents = info.accents
			line("Plate / trim: " .. (accents[e.accent] and accents[e.accent].name or "?"), "$" .. info.accentPrice .. " next",
				function() send("custom", { model = e.model, field = "accent", value = e.accent % #accents + 1 }) end)
			line("Race number: " .. tostring(e.number), "$" .. info.numberPrice .. " +1",
				function() send("custom", { model = e.model, field = "number", value = (e.number + 1) % 100 }) end)
			line("Free test ride (2 min)", "RIDE", function() send("testride", e.model) end)
			row(30, "Call it any time: Phone > Car or Ride", "")
		end
		line("Back to all rides", "", function() focus = nil draw() end, Color3.fromRGB(28, 32, 40))
	end
	if panel.Visible and (GuiService.SelectedObject == nil or not GuiService.SelectedObject:IsDescendantOf(panel)) then
		GuiService.SelectedObject = first
	end
end

OpenShop.OnClientEvent:Connect(function(model)
	focus = type(model) == "string" and model or nil
	panel.Visible = true
	info = nil
	draw()
	refresh()
	draw()
end)
-- B / Backspace: back to the list, then close (above the phone's own close)
ContextActionService:BindActionAtPriority("Exit6BikeShopBack", function(_, state)
	if state ~= Enum.UserInputState.Begin or not panel.Visible then return Enum.ContextActionResult.Pass end
	if focus then focus = nil draw() else close() end
	return Enum.ContextActionResult.Sink
end, false, 4100, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
-- money / reputation moved: redraw prices
task.spawn(function()
	local ls = player:WaitForChild("leaderstats", 60)
	for _, name in ipairs({ "Chester Cash", "Reputation" }) do
		local v = ls and ls:WaitForChild(name, 10)
		if v then v:GetPropertyChangedSignal("Value"):Connect(function()
			if panel.Visible and info then info[name == "Chester Cash" and "cash" or "rep"] = v.Value draw() end
		end) end
	end
end)
-- walking away closes the shop
RunService.Heartbeat:Connect(function()
	if not panel.Visible then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local home = Workspace:GetAttribute("Exit6DealershipAt")
	if not root or (typeof(home) == "Vector3" and (root.Position - home).Magnitude > 220) then close() end
end)

-- ------------------------------------------------------------------ rideout waypoint
local marker, beam, label, target = nil, nil, nil, nil
local function clear()
	if marker then marker:Destroy() end
	marker, beam, label, target = nil, nil, nil, nil
end
local function show(next)
	if not next or typeof(next.pos) ~= "Vector3" then clear() return end
	if target and (target - next.pos).Magnitude < 1 and marker then
		label.Text = string.upper(next.name)
		return
	end
	clear()
	target = next.pos
	marker = new("Part", { Name = "Exit6RideoutStop", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(next.pos + Vector3.new(0, 1.5, 0)) }, Workspace)
	new("Part", { Name = "Ring", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon, Color = ACCENT, Transparency = 0.45, Size = Vector3.new(0.3, 60, 60),
		CFrame = CFrame.new(next.pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, marker)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(220, 52), StudsOffset = Vector3.new(0, 10, 0), AlwaysOnTop = true,
		LightInfluence = 0, MaxDistance = 100000 }, marker)
	label = new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.2, TextColor3 = ACCENT,
		Font = Enum.Font.GothamBlack, TextSize = 17, Text = string.upper(next.name) }, bb)
	round(label, 8)
	local a1 = new("Attachment", {}, marker)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local a0 = root:FindFirstChild("Exit6RideoutAttach") or new("Attachment", { Name = "Exit6RideoutAttach" }, root)
		beam = new("Beam", { Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(ACCENT), Width0 = 0.5, Width1 = 0.5,
			FaceCamera = true, LightEmission = 0.6, Transparency = NumberSequence.new(0.35), Segments = 1 }, marker)
	end
end
local lastNext = nil
Changed.OnClientEvent:Connect(function(state)
	lastNext = type(state) == "table" and state.mine and state.mine.next or nil
	show(lastNext)
end)
player.CharacterAdded:Connect(function()
	task.wait(1)
	clear()
	show(lastNext)
end)
-- distance on the label, twice a second
local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	if t < 0.5 or not marker or not label or not lastNext then return end
	t = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		label.Text = string.format("%s  %d studs", string.upper(lastNext.name), math.floor((root.Position - lastNext.pos).Magnitude))
	end
end)
task.spawn(function()
	local ok, r = pcall(function() return Action:InvokeServer("status") end)
	if ok and type(r) == "table" and r.mine then lastNext = r.mine.next show(lastNext) end
end)
