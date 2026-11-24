-- EXIT 6 Premium boutique (client): browse the Robux collection, try it on
-- with an orbiting camera, buy through the Roblox purchase prompt.
-- Everything is decided by the server (Exit6PremiumStore.server): this script
-- only shows the catalog it returns and asks for try-on / buy / wear.
--
-- Open: phone Closet > "EXIT 6 Premium", or a premium row at a clothing
-- store, barbershop or jeweller (they fire PlayerGui.Exit6Boutique.Open).
-- Gamepad: D-pad / left stick browse (each item is tried on), A buy / wear,
-- right stick rotate, LT / RT zoom, B close. Keyboard: arrows, Enter,
-- Q / E rotate, mouse wheel zoom, right-drag rotate, Backspace close.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Premium = require(Shared:WaitForChild("Exit6Premium"))
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
if not Premium.Enabled then return end
local Action = ReplicatedStorage:WaitForChild("Exit6PremiumAction")

local INK = Color3.fromRGB(12, 12, 15)
local CARD = Color3.fromRGB(30, 30, 36)
local SEL = Color3.fromRGB(58, 58, 68)
local SILVER = Color3.fromRGB(214, 218, 226)
local TEXT = Color3.fromRGB(245, 245, 242)
local DIM = Color3.fromRGB(150, 152, 160)
local RED = Color3.fromRGB(200, 30, 38)

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Boutique"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local OpenEvent = Instance.new("BindableEvent")
OpenEvent.Name = "Open"
OpenEvent.Parent = gui

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end

-- left: the collection list
local side = new("Frame", { Position = UDim2.new(0, 24, 0, 24), Size = UDim2.new(0, 380, 1, -48), BackgroundColor3 = INK,
	BackgroundTransparency = 0.08 }, gui)
round(side, 14)
new("TextLabel", { Position = UDim2.fromOffset(20, 14), Size = UDim2.new(1, -40, 0, 40), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 34, TextColor3 = TEXT, Text = "EXIT 6", TextXAlignment = Enum.TextXAlignment.Left }, side)
new("Frame", { Position = UDim2.fromOffset(22, 54), Size = UDim2.fromOffset(110, 4), BackgroundColor3 = RED, BorderSizePixel = 0 }, side)
new("TextLabel", { Position = UDim2.fromOffset(20, 62), Size = UDim2.new(1, -40, 0, 22), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = SILVER, Text = "PREMIUM COLLECTION  ·  ROBUX",
	TextXAlignment = Enum.TextXAlignment.Left }, side)
local list = new("ScrollingFrame", { Position = UDim2.fromOffset(12, 96), Size = UDim2.new(1, -24, 1, -152),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y, Selectable = false, ScrollingDirection = Enum.ScrollingDirection.Y }, side)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
local hint = new("TextLabel", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 20, 1, -12), Size = UDim2.new(1, -40, 0, 32),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = DIM, TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left }, side)

-- right: details for the selected product
local card = new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -24, 1, -24), Size = UDim2.fromOffset(380, 250),
	BackgroundColor3 = INK, BackgroundTransparency = 0.08 }, gui)
round(card, 14)
local cTitle = new("TextLabel", { Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 30), BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd }, card)
local cBlurb = new("TextLabel", { Position = UDim2.fromOffset(18, 46), Size = UDim2.new(1, -36, 0, 40), BackgroundTransparency = 1,
	Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = DIM, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top }, card)
local cItems = new("TextLabel", { Position = UDim2.fromOffset(18, 90), Size = UDim2.new(1, -36, 0, 80), BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = SILVER, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top }, card)
local cButton = new("TextButton", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -16), Size = UDim2.new(1, -36, 0, 46),
	BackgroundColor3 = SILVER, Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = INK, Text = "", Selectable = false }, card)
round(cButton, 10)

-- ---------------------------------------------------------------- state
local open = false
local catalog = nil      -- server catalog
local current = nil      -- selected sku
local rows = {}          -- sku -> button
local busy = false
local tryTicket = 0
local focus = "body"

local function info(sku)
	return catalog and catalog.products and catalog.products[sku]
end

local function priceText(sku)
	local c = info(sku)
	if not c then return "..." end
	if c.owned then return "OWNED" end
	if not c.ready then return "SOON" end
	if not c.buyable then return "SOON" end
	return "R$ " .. tostring(c.price) .. (c.test and "*" or "")
end

local function drawCard()
	local p = current and Premium.Products[current]
	if not p then
		card.Visible = false
		return
	end
	card.Visible = true
	cTitle.Text = string.upper(p.name)
	cBlurb.Text = p.blurb or ""
	local names = {}
	for _, id in ipairs(p.grants) do
		local it = Catalog.Items[id]
		if it then table.insert(names, "· " .. it.name) end
	end
	cItems.Text = table.concat(names, "\n")
	local c = info(current)
	if c and c.owned then
		cButton.Text = "WEAR IT"
		cButton.BackgroundColor3 = SILVER
	elseif c and c.buyable then
		cButton.Text = "BUY  R$ " .. tostring(c.price) .. (c.test and "  (STUDIO TEST)" or "")
		cButton.BackgroundColor3 = SILVER
	else
		cButton.Text = (c and not c.ready) and "NOT INSTALLED YET" or "COMING SOON"
		cButton.BackgroundColor3 = DIM
	end
	local st = catalog and catalog.status
	if st and st ~= "ready" then
		cButton.Text = st == "failed" and "PURCHASES UNAVAILABLE - RETRYING" or "LOADING YOUR PURCHASES..."
		cButton.BackgroundColor3 = DIM
	end
end

local function refreshRows()
	for sku, b in pairs(rows) do
		b.Price.Text = priceText(sku)
		b.BackgroundColor3 = sku == current and SEL or CARD
		b.Price.TextColor3 = (info(sku) and info(sku).owned) and DIM or SILVER
	end
	drawCard()
end

local function fetch()
	local ok, good, data = pcall(function() return Action:InvokeServer("catalog") end)
	if ok and good and type(data) == "table" then catalog = data end
	refreshRows()
end

-- try the product on (debounced so fast browsing doesn't spam the server)
local function select(sku)
	if current == sku then return end
	current = sku
	focus = Premium.Products[sku].focus or "body"
	refreshRows()
	tryTicket += 1
	local mine = tryTicket
	task.delay(0.3, function()
		if mine ~= tryTicket or not open then return end
		pcall(function() Action:InvokeServer("tryon", sku) end)
	end)
end

local function act()
	if busy or not current then return end
	local c = info(current)
	if not c then return end
	busy = true
	if c.owned then
		pcall(function() Action:InvokeServer("wear", current) end)
	elseif c.buyable then
		local ok, good, why = pcall(function() return Action:InvokeServer("buy", current) end)
		if ok and good and why == "granted" then task.wait(0.3) end
	end
	busy = false
	fetch()
end
cButton.Activated:Connect(act)

local function build()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	table.clear(rows)
	local order = 0
	local seq = {}
	local function heading(text)
		order += 1
		new("TextLabel", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = RED, Text = text, TextXAlignment = Enum.TextXAlignment.Left }, list)
	end
	local function row(sku)
		local p = Premium.Products[sku]
		order += 1
		local b = new("TextButton", { Name = sku, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 48), BackgroundColor3 = CARD,
			AutoButtonColor = true, Text = "", Selectable = true }, list)
		round(b, 8)
		new("TextLabel", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -120, 1, 0), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = TEXT, Text = p.name, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd }, b)
		new("TextLabel", { Name = "Price", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0, 100, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 16,
			TextColor3 = SILVER, Text = "...", TextXAlignment = Enum.TextXAlignment.Right }, b)
		b.Activated:Connect(function()
			if current == sku then act() else select(sku) end
		end)
		b.SelectionGained:Connect(function() select(sku) end)
		rows[sku] = b
		table.insert(seq, b)
	end
	heading("FLAGSHIP")
	for _, sku in ipairs(Premium.Order) do
		if Premium.Products[sku].flagship then row(sku) end
	end
	for _, cat in ipairs(Premium.Categories) do
		local any = false
		for _, sku in ipairs(Premium.Order) do
			local p = Premium.Products[sku]
			if p.category == cat and not p.flagship then
				if not any then heading(string.upper(Premium.CategoryNames[cat])) any = true end
				row(sku)
			end
		end
	end
	for i, b in ipairs(seq) do
		b.NextSelectionUp = seq[i - 1] or b
		b.NextSelectionDown = seq[i + 1] or b
		b.NextSelectionLeft, b.NextSelectionRight = b, b
	end
	return seq
end

-- ---------------------------------------------------------------- orbit camera
local yaw, pitch, zoom = 0, 0.12, 1
local stick, trig = Vector2.zero, 0
local idle = 0
local saved = nil
local renderConn = nil

local FOCUS = {
	head = { parts = { "Head" }, dist = 4.6, up = 0.1 },
	chest = { parts = { "UpperTorso" }, dist = 4.4, up = 0.35 },
	wrist = { parts = { "LeftHand", "LeftLowerArm" }, dist = 3.4, up = 0.0, yaw = math.rad(70) },
	feet = { parts = { "LeftFoot", "RightFoot" }, dist = 4.6, up = 0.3 },
	body = { parts = { "HumanoidRootPart" }, dist = 10, up = 0.6 },
}

local function focusPoint(char)
	local f = FOCUS[focus] or FOCUS.body
	local sum, n = Vector3.zero, 0
	for _, name in ipairs(f.parts) do
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then sum += p.Position n += 1 end
	end
	if n == 0 then return nil, f end
	return sum / n, f
end

local function stepCamera(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	if not root or not cam then return end
	local target, f = focusPoint(char)
	if not target then return end
	local turning = math.abs(stick.X) > 0.15 or UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.E)
	if turning then idle = 0 else idle += dt end
	local spin = stick.X * 2.4
	if UserInputService:IsKeyDown(Enum.KeyCode.Q) then spin -= 1.8 end
	if UserInputService:IsKeyDown(Enum.KeyCode.E) then spin += 1.8 end
	if idle > 2.5 then spin += 0.35 end
	yaw += spin * dt
	pitch = math.clamp(pitch + (math.abs(stick.Y) > 0.15 and -stick.Y * 1.2 * dt or 0), -0.35, 0.7)
	zoom = math.clamp(zoom + trig * dt * 1.4, 0.55, 1.7)
	local look = root.CFrame.LookVector
	local right = root.CFrame.RightVector
	local a = yaw + (f.yaw or 0)
	local dir = (look * math.cos(a) - right * math.sin(a)) * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
	local eye = target + dir * f.dist * zoom
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(eye, target + Vector3.new(0, f.up * 0.3, 0)), math.min(1, dt * 8))
end

UserInputService.InputChanged:Connect(function(input)
	if not open then return end
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then
		stick = Vector2.new(input.Position.X, input.Position.Y)
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
		local r = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		local lt, rt = 0, 0
		for _, s in ipairs(r) do
			if s.KeyCode == Enum.KeyCode.ButtonL2 then lt = s.Position.Z end
			if s.KeyCode == Enum.KeyCode.ButtonR2 then rt = s.Position.Z end
		end
		trig = lt - rt   -- RT zooms in, LT out
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		zoom = math.clamp(zoom - input.Position.Z * 0.08, 0.55, 1.7)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement
		and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		yaw -= input.Delta.X * 0.01
		idle = 0
	end
end)

-- movement is frozen while the boutique is open (the camera orbits instead).
-- PlayerModule is not guaranteed in this game (see Exit6MainMenu), so the
-- fallback zeroes the local humanoid's walk / jump and restores them after.
local frozen = nil
local function controls(enable)
	local ps = player:FindFirstChild("PlayerScripts")
	local module = ps and ps:FindFirstChild("PlayerModule")
	if module then
		local ok = pcall(function()
			local c = require(module):GetControls()
			if enable then c:Enable() else c:Disable() end
		end)
		if ok then return end
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not enable and hum then
		frozen = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, height = hum.JumpHeight }
		hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0
	elseif enable and frozen then
		if frozen.hum.Parent then
			frozen.hum.WalkSpeed, frozen.hum.JumpPower, frozen.hum.JumpHeight = frozen.walk, frozen.jump, frozen.height
		end
		frozen = nil
	end
end

local close
local function sink(_, state)
	if state == Enum.UserInputState.Begin then close() end
	return Enum.ContextActionResult.Sink
end

local function openBoutique(sku)
	if open then
		if sku and rows[sku] then GuiService.SelectedObject = rows[sku] end
		return
	end
	-- never behind the main menu (it keeps every other ScreenGui hidden)
	local menu = player.PlayerGui:FindFirstChild("Exit6MainMenu")
	if menu and menu:IsA("ScreenGui") and menu.Enabled then return end
	open = true
	gui.Enabled = true
	hint.Text = UserInputService.GamepadEnabled
		and "D-PAD BROWSE + TRY ON   A BUY / WEAR   R-STICK ROTATE   LT/RT ZOOM   B CLOSE"
		or "CLICK TO TRY ON, AGAIN TO BUY   Q / E OR RIGHT-DRAG ROTATE   WHEEL ZOOM   BACKSPACE CLOSE"
	local cam = Workspace.CurrentCamera
	saved = { type = cam.CameraType, cf = cam.CFrame, subject = cam.CameraSubject }
	yaw, pitch, zoom, idle, stick, trig = 0, 0.12, 1, 0, Vector2.zero, 0
	controls(false)
	local seq = build()
	current = nil
	fetch()
	local first = (sku and rows[sku]) or seq[1]
	if first then
		select(first.Name)
		GuiService.SelectedObject = first
	end
	ContextActionService:BindActionAtPriority("Exit6BoutiqueClose", sink, false, 3000,
		Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	RunService:BindToRenderStep("Exit6BoutiqueCam", Enum.RenderPriority.Camera.Value + 1, stepCamera)
end

close = function()
	if not open then return end
	open = false
	tryTicket += 1
	gui.Enabled = false
	ContextActionService:UnbindAction("Exit6BoutiqueClose")
	pcall(function() RunService:UnbindFromRenderStep("Exit6BoutiqueCam") end)
	local cam = Workspace.CurrentCamera
	if saved then
		cam.CameraType = saved.type == Enum.CameraType.Scriptable and Enum.CameraType.Custom or saved.type
		cam.CameraSubject = saved.subject or (player.Character and player.Character:FindFirstChildOfClass("Humanoid"))
	end
	controls(true)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then GuiService.SelectedObject = nil end
	task.spawn(function() pcall(function() Action:InvokeServer("cancel") end) end)
end

OpenEvent.Event:Connect(function(sku)
	openBoutique(type(sku) == "string" and Premium.Products[sku] and sku or nil)
end)

-- ownership / status changes -> redraw
player:GetAttributeChangedSignal("Exit6Premium"):Connect(function()
	if open then fetch() end
end)
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId)
	if userId == player.UserId and open then
		task.wait(1)
		fetch()
	end
end)
player.CharacterAdded:Connect(function()
	if open then close() end
end)
