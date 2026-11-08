-- EXIT 6 street basketball, client: the shot meter and the game score.
--   holding the ball   hold Click / R2, release in the green (Exit6Basketball.server decides)
--   near the holder    tap Click / R2 to steal
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local BallAction = remotes:WaitForChild("BallAction")

local INK = Color3.fromRGB(18, 21, 27)
local ACCENT = Color3.fromRGB(229, 157, 53)
local FILL_SECONDS = 1.0

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Hoops"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
-- meter: a bar with the release window marked
local meter = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -250), Size = UDim2.fromOffset(260, 22),
	BackgroundColor3 = INK, BackgroundTransparency = 0.2, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, meter)
new("Frame", { Position = UDim2.fromScale(0.82, 0), Size = UDim2.fromScale(0.13, 1), BackgroundColor3 = Color3.fromRGB(60, 170, 80),
	BackgroundTransparency = 0.3, BorderSizePixel = 0 }, meter)
local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, meter)
local hint = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -276), Size = UDim2.fromOffset(360, 22),
	BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 15, TextStrokeTransparency = 0.5,
	Text = "", Visible = false }, gui)
-- scoreboard
local board = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 230), Size = UDim2.fromOffset(300, 40),
	BackgroundColor3 = INK, BackgroundTransparency = 0.15, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 20,
	Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, board)

local charging, t0 = false, 0
local function meterValue() return math.clamp((os.clock() - t0) / FILL_SECONDS, 0, 1.2) end

local function holdingBall() return player:GetAttribute("Exit6HasBall") ~= nil end
local function nearHolder()
	local me = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not me then return false end
	for _, p in ipairs(Players:GetPlayers()) do
		local r = p ~= player and p:GetAttribute("Exit6HasBall") and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r and (r.Position - me.Position).Magnitude < 7 then return true end
	end
	return false
end

local bound = false
local function bind(on)
	if on == bound then return end
	bound = on
	if on then
		ContextActionService:BindAction("Exit6Shoot", function(_, state)
			if player.Character and player.Character:FindFirstChildOfClass("Humanoid") and player.Character:FindFirstChildOfClass("Humanoid").SeatPart then
				return Enum.ContextActionResult.Pass
			end
			if holdingBall() then
				if state == Enum.UserInputState.Begin then
					charging, t0 = true, os.clock()
				elseif (state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel) and charging then
					charging = false
					BallAction:FireServer("shoot", meterValue())
				end
				return Enum.ContextActionResult.Sink
			elseif state == Enum.UserInputState.Begin and nearHolder() then
				BallAction:FireServer("steal")
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	else
		ContextActionService:UnbindAction("Exit6Shoot")
		charging = false
	end
end

RunService.RenderStepped:Connect(function()
	local has, near = holdingBall(), nearHolder()
	bind(has or near)
	meter.Visible = has
	if has then
		local v = charging and meterValue() or 0
		fill.Size = UDim2.fromScale(math.min(v, 1), 1)
		fill.BackgroundColor3 = (v > 0.82 and v < 0.95) and Color3.fromRGB(80, 210, 100) or ACCENT
	end
	hint.Visible = has or near
	hint.Text = has and "Hold Click / R2 - release in the green" or (near and "Click / R2 to steal" or "")
	local raw = player:GetAttribute("Exit6Game")
	local ok, g = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	board.Visible = ok and type(g) == "table"
	if board.Visible then
		local left = math.max(0, math.floor((g.ends or 0) - Workspace:GetServerTimeNow()))
		board.Text = string.format("%s %d  -  %d %s    %d:%02d", g.mine == "A" and "YOU" or "A", g.a, g.b, g.mine == "B" and "YOU" or "B",
			left // 60, left % 60)
	end
end)
