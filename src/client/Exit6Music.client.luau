-- EXIT 6 studio takes: a rhythm lane for writing, beat-making and recording
-- (Exit6Music.server starts a take and keeps the score). Notes slide to the
-- line; tap Space / A / Click on each: perfect, good or miss.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local MusicTake = remotes:WaitForChild("MusicTake")
local MusicResult = remotes:WaitForChild("MusicTakeResult")

local NOTES = 16
local TRAVEL = 1.6          -- seconds a note takes to cross the lane
local PERFECT, GOOD, LATE = 0.08, 0.16, 0.22
local INK = Color3.fromRGB(18, 21, 27)
local ACCENT = Color3.fromRGB(190, 110, 255)
local TITLES = { write = "WRITING LYRICS", beat = "MAKING A BEAT", record = "RECORDING" }

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Studio"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local panel = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(560, 150),
	BackgroundColor3 = INK, BackgroundTransparency = 0.08 }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, panel)
local title = new("TextLabel", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 26), BackgroundTransparency = 1,
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left }, panel)
local status = new("TextLabel", { Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 26), BackgroundTransparency = 1,
	TextColor3 = ACCENT, Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right }, panel)
local lane = new("Frame", { Position = UDim2.fromOffset(18, 52), Size = UDim2.new(1, -36, 0, 54), BackgroundColor3 = Color3.fromRGB(34, 30, 44),
	ClipsDescendants = true }, panel)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, lane)
local HIT_X = 0.14
new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(HIT_X, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = ACCENT,
	BorderSizePixel = 0 }, lane)
new("TextLabel", { Position = UDim2.new(0, 18, 1, -36), Size = UDim2.new(1, -36, 0, 24), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(155, 164, 177), Font = Enum.Font.Gotham, TextSize = 14, Text = "Tap SPACE / A / CLICK as each note hits the line" }, panel)

local running = false
local notes = {}
local t0 = 0
local score, judged = 0, 0

local function judge(n, value, text)
	n.done = true
	score += value
	judged += 1
	status.Text = text
	n.ui.BackgroundColor3 = value >= 1 and Color3.fromRGB(80, 220, 120) or value > 0 and Color3.fromRGB(240, 200, 80) or Color3.fromRGB(200, 60, 60)
end

local function tap()
	local now = os.clock() - t0
	local best, bd = nil, LATE
	for _, n in ipairs(notes) do
		if not n.done then
			local d = math.abs(now - n.at)
			if d < bd then best, bd = n, d end
		end
	end
	if not best then return end
	if bd <= PERFECT then judge(best, 1, "PERFECT")
	elseif bd <= GOOD then judge(best, 0.6, "GOOD")
	else judge(best, 0, "MISS") end
end

MusicTake.OnClientEvent:Connect(function(token, kind, spacing)
	if running then return end
	running = true
	gui.Enabled = true
	title.Text = TITLES[kind] or "IN THE STUDIO"
	status.Text = ""
	score, judged = 0, 0
	for _, n in ipairs(notes) do n.ui:Destroy() end
	table.clear(notes)
	local rng = Random.new()
	local at = 1.4
	for _ = 1, NOTES do
		local ui = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), Position = UDim2.fromScale(1.2, 0.5),
			BackgroundColor3 = Color3.fromRGB(240, 240, 240) }, lane)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ui)
		table.insert(notes, { at = at, ui = ui })
		at += spacing * (rng:NextNumber() < 0.25 and 0.5 or 1)
	end
	local last = at
	t0 = os.clock()
	ContextActionService:BindActionAtPriority("Exit6StudioTap", function(_, state)
		if state == Enum.UserInputState.Begin then tap() end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock() - t0
		for _, n in ipairs(notes) do
			local x = HIT_X + (n.at - now) / TRAVEL * (1 - HIT_X)
			n.ui.Position = UDim2.fromScale(x, 0.5)
			if not n.done and now - n.at > LATE then judge(n, 0, "MISS") end
		end
		if now > last + 0.6 then
			conn:Disconnect()
			ContextActionService:UnbindAction("Exit6StudioTap")
			local accuracy = score / NOTES
			status.Text = string.format("%d%%", math.floor(accuracy * 100))
			MusicResult:FireServer(token, accuracy)
			task.delay(1.2, function()
				gui.Enabled = false
				running = false
			end)
		end
	end)
end)
