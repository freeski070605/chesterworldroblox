-- EXIT 6 activities, client (Exit6Activities.server decides):
--   time trial        timer + the next checkpoint as a ring on the road
--   penalty shootout  aim with A / D or the D-pad, hold Click / R2 / Space and
--                     release for power (green = good, past it = over the bar)
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local Activity = remotes:WaitForChild("Activity")
local INK = Color3.fromRGB(18, 21, 27)
local ACCENT = Color3.fromRGB(229, 157, 53)

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Activities"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function decode(name)
	local raw = player:GetAttribute(name)
	local ok, t = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(t) == "table" and t or nil
end

-- ------------------------------------------------------------------ time trial
local trialLabel = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 230), Size = UDim2.fromOffset(340, 40),
	BackgroundColor3 = INK, BackgroundTransparency = 0.15, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 18,
	Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, trialLabel)
local ring = nil
local ringKey = nil
local function setRing(t)
	local key = t and table.concat(t.cp, ",") or nil
	if key == ringKey then return end
	ringKey = key
	if ring then ring:Destroy() ring = nil end
	if not t then return end
	ring = new("Part", { Name = "Exit6TrialRing", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
		Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ACCENT, Transparency = 0.35, Size = Vector3.new(0.6, 30, 30),
		CFrame = CFrame.new(t.cp[1], t.cp[2] + 8, t.cp[3]) * CFrame.Angles(0, 0, math.rad(90)) }, Workspace)
	local bb = new("BillboardGui", { Size = UDim2.fromOffset(120, 34), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000,
		StudsOffset = Vector3.new(0, 18, 0) }, ring)
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.2, TextColor3 = ACCENT,
		Font = Enum.Font.GothamBlack, TextSize = 15, Text = "CHECKPOINT " .. t.n .. "/" .. t.total }, bb)
end

-- ------------------------------------------------------------------ penalties
local pen = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -230), Size = UDim2.fromOffset(320, 86),
	BackgroundColor3 = INK, BackgroundTransparency = 0.12, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, pen)
local penTitle = new("TextLabel", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1,
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 16 }, pen)
local aimRow = new("Frame", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 22), BackgroundTransparency = 1 }, pen)
local aimBoxes = {}
for i, name in ipairs({ "LEFT", "MIDDLE", "RIGHT" }) do
	local b = new("TextLabel", { Position = UDim2.new((i - 1) / 3, 2, 0, 0), Size = UDim2.new(1 / 3, -4, 1, 0), BackgroundColor3 = Color3.fromRGB(37, 44, 56),
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 13, Text = name }, aimRow)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	aimBoxes[i] = b
end
local powerBack = new("Frame", { Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = Color3.fromRGB(37, 44, 56),
	BorderSizePixel = 0 }, pen)
new("Frame", { Position = UDim2.fromScale(0.86, 0), Size = UDim2.fromScale(0.14, 1), BackgroundColor3 = Color3.fromRGB(60, 170, 80),
	BackgroundTransparency = 0.4, BorderSizePixel = 0 }, powerBack)
local power = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, powerBack)

local aim, charging, t0, bound = 0, false, 0, false
local CHARGE = 1.1
local function powerNow() return math.clamp((os.clock() - t0) / CHARGE, 0, 1.25) end
local function bindPens(on)
	if on == bound then return end
	bound = on
	if on then
		aim = 0
		ContextActionService:BindActionAtPriority("Exit6PenAim", function(_, state, input)
			if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
			local k = input.KeyCode
			if k == Enum.KeyCode.A or k == Enum.KeyCode.DPadLeft or k == Enum.KeyCode.Left then aim = math.max(-1, aim - 1)
			elseif k == Enum.KeyCode.D or k == Enum.KeyCode.DPadRight or k == Enum.KeyCode.Right then aim = math.min(1, aim + 1) end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.A, Enum.KeyCode.D, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
		ContextActionService:BindActionAtPriority("Exit6PenKick", function(_, state)
			if state == Enum.UserInputState.Begin then
				charging, t0 = true, os.clock()
			elseif (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) and charging then
				charging = false
				Activity:FireServer("kick", aim, powerNow())
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction("Exit6PenAim")
		ContextActionService:UnbindAction("Exit6PenKick")
		charging = false
	end
end

RunService.RenderStepped:Connect(function()
	local t = decode("Exit6Trial")
	setRing(t)
	trialLabel.Visible = t ~= nil
	if t then
		local e = math.max(0, Workspace:GetServerTimeNow() - (t.start or 0))
		trialLabel.Text = string.format("%s   %.1fs  (par %d)   %d/%d", t.name, e, t.par or 0, (t.n or 1) - 1, t.total or 0)
		trialLabel.TextColor3 = e > (t.par or 0) and Color3.fromRGB(240, 120, 100) or Color3.new(1, 1, 1)
	end
	local p = decode("Exit6Pens")
	bindPens(p ~= nil)
	pen.Visible = p ~= nil
	if p then
		penTitle.Text = string.format("PENALTY %d / %d   -   GOALS %d", p.kick, p.of, p.goals)
		for i, b in ipairs(aimBoxes) do b.BackgroundColor3 = (i - 2 == aim) and ACCENT or Color3.fromRGB(37, 44, 56) end
		local v = charging and powerNow() or 0
		power.Size = UDim2.fromScale(math.min(v, 1), 1)
		power.BackgroundColor3 = v > 1.0 and Color3.fromRGB(220, 60, 60) or ACCENT
	end
end)
