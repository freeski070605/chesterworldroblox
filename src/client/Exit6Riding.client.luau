-- EXIT 6 Bike Life riding (client). While the local player sits on one of
-- their Bike Life rides, this client owns its physics (Exit6BikeBuilder hands
-- the chassis over) and steps Exit6BikePhysics every frame. Cars stay with
-- Exit6Driving.client.
--   Xbox      RT throttle  LT brake / reverse  left stick steer
--             A wheelie (lean back)  B rear brake (slide)  X get off
--   Keyboard  W / Up throttle  S / Down brake  A / D steer
--             Space wheelie  Shift rear brake  F or X get off
--   Touch     on-screen GAS / BRAKE / WHEELIE / OFF; steer with the thumbstick
-- All bindings exist only while riding and are released on dismount, so the
-- phone (P / D-pad Up / Select, B to close at higher priority), the car
-- controls, the character's jump and the Hair Test menu are untouched.
-- Every client also animates every ride nearby: wheels roll, the fork / quad
-- bars steer, and riders sit in a riding pose instead of the chair-sit pose.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BikePhysics = require(Shared:WaitForChild("Exit6BikePhysics"))
local STUDS_PER_MPH = 3.92 * 0.44704 -- same speedo scale as the cars

local INK = Color3.fromRGB(18, 21, 27)
local ACCENT = Color3.fromRGB(229, 157, 53)
local TEXT = Color3.fromRGB(245, 245, 242)
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end

-- ------------------------------------------------------------------ HUD
local gui = new("ScreenGui", { Name = "Exit6BikeHUD", ResetOnSpawn = false, Enabled = false, DisplayOrder = 20 },
	player:WaitForChild("PlayerGui"))
local panel = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(210, 104),
	BackgroundColor3 = INK, BackgroundTransparency = 0.15 }, gui)
round(panel, 12)
local speedLabel = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 46),
	Font = Enum.Font.GothamBlack, TextSize = 40, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, Text = "0" }, panel)
local unit = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, 18),
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left, Text = "MPH" }, panel)
local gaugeBack = new("Frame", { Position = UDim2.fromOffset(14, 70), Size = UDim2.new(1, -28, 0, 10),
	BackgroundColor3 = Color3.fromRGB(50, 54, 62), BorderSizePixel = 0 }, panel)
local gauge = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = ACCENT, BorderSizePixel = 0 }, gaugeBack)
local hint = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 82), Size = UDim2.new(1, -28, 0, 18),
	Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = Color3.fromRGB(155, 164, 177), TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd }, panel)
local wheelieBanner = new("TextLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(300, 54),
	BackgroundColor3 = INK, BackgroundTransparency = 0.2, Font = Enum.Font.GothamBlack, TextSize = 30, TextColor3 = ACCENT,
	Visible = false, Text = "" }, gui)
round(wheelieBanner, 12)

-- touch controls (only drawn on touch devices)
local touch = { gas = false, brake = false, wheelie = false }
local touchFrame = new("Frame", { Name = "Touch", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false }, gui)
local function touchButton(name, text, pos, size, color)
	local b = new("TextButton", { Name = name, AnchorPoint = Vector2.new(1, 1), Position = pos, Size = size, Text = text,
		Font = Enum.Font.GothamBlack, TextSize = 18, TextColor3 = TEXT, BackgroundColor3 = color, BackgroundTransparency = 0.25,
		AutoButtonColor = false, Selectable = false }, touchFrame)
	round(b, 14)
	return b
end
local gasB = touchButton("Gas", "GAS", UDim2.new(1, -130, 1, -150), UDim2.fromOffset(96, 120), Color3.fromRGB(40, 130, 60))
local brakeB = touchButton("Brake", "BRAKE", UDim2.new(1, -236, 1, -150), UDim2.fromOffset(96, 84), Color3.fromRGB(150, 40, 40))
local wheelieB = touchButton("Wheelie", "WHEELIE", UDim2.new(1, -130, 1, -280), UDim2.fromOffset(96, 64), Color3.fromRGB(200, 110, 20))
local offB = touchButton("Off", "OFF", UDim2.new(1, -236, 1, -244), UDim2.fromOffset(96, 48), Color3.fromRGB(60, 64, 74))
local function hold(button, key)
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touch[key] = true
			button.BackgroundTransparency = 0.05
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touch[key] = false
			button.BackgroundTransparency = 0.25
		end
	end)
end
hold(gasB, "gas")
hold(brakeB, "brake")
hold(wheelieB, "wheelie")

-- ------------------------------------------------------------------ riding
local wheelie, rearBrake = false, false
local riding = nil      -- { model, seat, conn }
local lastStep = nil    -- the latest physics step result (for the visuals)
local lastPad = false

local function getOff()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and riding and hum.SeatPart == riding.seat then
		hum.Sit = false
		hum.Jump = true
	end
end
offB.Activated:Connect(getOff)

local function controlsHint()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		hint.Text = "Stick steer  GAS/BRAKE  WHEELIE  OFF"
	elseif lastPad then
		hint.Text = "RT gas  LT brake  A wheelie  B slide  X off"
	else
		hint.Text = "W/S gas-brake  A/D steer  Space wheelie  F off"
	end
end
UserInputService.LastInputTypeChanged:Connect(function(t)
	lastPad = t.Name:find("Gamepad") ~= nil
	if riding then controlsHint() end
end)

local function stop()
	if riding and riding.conn then riding.conn:Disconnect() end
	riding = nil
	lastStep = nil
	wheelie, rearBrake = false, false
	touch.gas, touch.brake, touch.wheelie = false, false, false
	gui.Enabled = false
	ContextActionService:UnbindAction("Exit6BikeWheelie")
	ContextActionService:UnbindAction("Exit6BikeRearBrake")
	ContextActionService:UnbindAction("Exit6BikeGetOff")
end

local function analog(state, code)
	for _, input in ipairs(state) do
		if input.KeyCode == code then return input end
	end
end

local function readInput(seat)
	local throttle, brake, steer = 0, 0, 0
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local menuOpen = GuiService.SelectedObject ~= nil  -- gamepad is driving a menu (phone / shop)
	if not typing then
		if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then throttle = 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then brake = 1 end
		local kbSteer = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then kbSteer += 1 end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then kbSteer -= 1 end
		steer = kbSteer
	end
	if not menuOpen and UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		local state = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
		local rt, lt, stick = analog(state, Enum.KeyCode.ButtonR2), analog(state, Enum.KeyCode.ButtonL2), analog(state, Enum.KeyCode.Thumbstick1)
		if rt then throttle = math.max(throttle, rt.Position.Z) end
		if lt then brake = math.max(brake, lt.Position.Z) end
		if stick and math.abs(stick.Position.X) > 0.12 then
			local x = (math.abs(stick.Position.X) - 0.12) / 0.88 * math.sign(stick.Position.X)
			steer = math.abs(x) > math.abs(steer) and x or steer
		end
	end
	-- touch buttons, and the seat's own input (mobile thumbstick / fallbacks)
	if touch.gas then throttle = 1 end
	if touch.brake then brake = 1 end
	local seatThrottle, seatSteer = seat.ThrottleFloat, seat.SteerFloat
	if not menuOpen then
		if seatThrottle > 0 then throttle = math.max(throttle, seatThrottle) end
		if seatThrottle < 0 then brake = math.max(brake, -seatThrottle) end
		if steer == 0 then steer = seatSteer end
	end
	return {
		throttle = throttle, brake = brake, steer = steer,
		wheelie = wheelie or touch.wheelie, rearBrake = rearBrake,
	}
end

local function start(seat)
	stop()
	local model = seat.Parent
	riding = { model = model, seat = seat }
	gui.Enabled = true
	touchFrame.Visible = UserInputService.TouchEnabled
	lastPad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	controlsHint()
	-- A / Space: lean back for a wheelie (also stops Space / A from jumping off)
	ContextActionService:BindActionAtPriority("Exit6BikeWheelie", function(_, state)
		if GuiService.SelectedObject ~= nil then return Enum.ContextActionResult.Pass end
		wheelie = state == Enum.UserInputState.Begin or (state == Enum.UserInputState.Change and wheelie)
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then wheelie = false end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	-- B / Shift: rear brake (lock the back wheel and slide it round)
	ContextActionService:BindActionAtPriority("Exit6BikeRearBrake", function(_, state)
		if GuiService.SelectedObject ~= nil then return Enum.ContextActionResult.Pass end
		rearBrake = state == Enum.UserInputState.Begin
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then rearBrake = false end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB)
	-- X / F: get off
	ContextActionService:BindActionAtPriority("Exit6BikeGetOff", function(_, state)
		if GuiService.SelectedObject ~= nil then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then getOff() end
		return Enum.ContextActionResult.Sink
	end, false, 2500, Enum.KeyCode.F, Enum.KeyCode.X, Enum.KeyCode.ButtonX)

	riding.conn = RunService.PreSimulation:Connect(function(dt)
		if not model.Parent or seat.Occupant == nil or not riding then stop() return end
		local input = readInput(seat)
		local r = BikePhysics.Step(model, dt, input)
		if not r then return end
		r.input = input
		lastStep = r
		speedLabel.Text = tostring(math.floor(math.abs(r.speed) / STUDS_PER_MPH + 0.5))
		local fuel, tank = model:GetAttribute("Fuel") or 0, model:GetAttribute("Tank") or 1
		local f = math.clamp(fuel / tank, 0, 1)
		gauge.Size = UDim2.fromScale(f, 1)
		gauge.BackgroundColor3 = f < 0.15 and Color3.fromRGB(200, 50, 40) or ACCENT
		local test = model:GetAttribute("TestRide") and "  TEST RIDE" or ""
		unit.Text = string.format("MPH    FUEL %d%%%s%s", math.floor(f * 100 + 0.5), fuel <= 0 and "  EMPTY" or (f < 0.15 and "  LOW" or ""), test)
		-- the server times the wheelie (Exit6BikeLife.server); show its count
		local streak = player:GetAttribute("BikeLifeWheelie") or 0
		wheelieBanner.Visible = streak >= 0.5
		if streak >= 0.5 then
			wheelieBanner.Text = string.format("WHEELIE  %.1fs", streak)
		end
	end)
end

local function watch(character)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum.Seated:Connect(function(active, seat)
		if active and seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent:GetAttribute("Exit6BikeLife") then
			start(seat)
		else
			stop()
		end
	end)
end
if player.Character then task.spawn(watch, player.Character) end
player.CharacterAdded:Connect(watch)
player.CharacterRemoving:Connect(stop)

-- ------------------------------------------------------------------ visuals
-- every client animates every ride near the camera: wheel spin, steering, and
-- the rider's pose (Motor6D.Transform is local to each client)
local rides = setmetatable({}, { __mode = "k" })  -- model -> { motors, spin }
local function rideParts(model)
	local r = rides[model]
	if r then return r end
	r = { spin = 0, motors = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then r.motors[d.Name] = d end
	end
	rides[model] = r
	return r
end

local JOINTS = { "Waist", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow" }
local poses = setmetatable({}, { __mode = "k" })  -- character -> { jointName = Motor6D }
local function jointsOf(character)
	local j = poses[character]
	if j then return j end
	j = {}
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("Motor6D") and table.find(JOINTS, d.Name) then j[d.Name] = d end
	end
	poses[character] = j
	return j
end
-- riding stance: bum on the seat, feet on the pegs, hands on the bars
local POSE = {
	bike = { waist = -0.35, hip = 1.05, hipOut = 0.12, knee = -1.35, arm = 1.2, armOut = 0.15, elbow = 0.35 },
	quad = { waist = -0.25, hip = 1.15, hipOut = 0.32, knee = -1.3, arm = 1.15, armOut = 0.28, elbow = 0.3 },
}
local function pose(character, kind, back)
	local j = jointsOf(character)
	local p = POSE[kind]
	local w = p.waist + back * 0.45
	if j.Waist then j.Waist.Transform = CFrame.Angles(w, 0, 0) end
	if j.LeftHip then j.LeftHip.Transform = CFrame.Angles(p.hip, 0, -p.hipOut) end
	if j.RightHip then j.RightHip.Transform = CFrame.Angles(p.hip, 0, p.hipOut) end
	if j.LeftKnee then j.LeftKnee.Transform = CFrame.Angles(p.knee, 0, 0) end
	if j.RightKnee then j.RightKnee.Transform = CFrame.Angles(p.knee, 0, 0) end
	local arm = p.arm - back * 0.25
	if j.LeftShoulder then j.LeftShoulder.Transform = CFrame.Angles(arm, 0, -p.armOut) end
	if j.RightShoulder then j.RightShoulder.Transform = CFrame.Angles(arm, 0, p.armOut) end
	if j.LeftElbow then j.LeftElbow.Transform = CFrame.Angles(p.elbow, 0, 0) end
	if j.RightElbow then j.RightElbow.Transform = CFrame.Angles(p.elbow, 0, 0) end
end

local folder = Workspace:WaitForChild("Exit6Vehicles", 120)
RunService.PreSimulation:Connect(function(dt)
	if not folder then return end
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, model in ipairs(folder:GetChildren()) do
		local kind = model:GetAttribute("Exit6BikeLife")
		local chassis = model.PrimaryPart
		if kind and chassis and (chassis.Position - camPos).Magnitude < 350 then
			local r = rideParts(model)
			local cf = chassis.CFrame
			local vel = chassis.AssemblyLinearVelocity
			local speed = vel:Dot(cf.LookVector)
			local radius = model:GetAttribute("Radius") or 1.2
			r.spin = (r.spin - speed / radius * dt) % (math.pi * 2)
			-- steering: ours from the input, everyone else's from their turn rate
			local steerAngle
			if riding and riding.model == model and lastStep then
				steerAngle = lastStep.steerAngle
			else
				local wb = model:GetAttribute("WheelBase") or 5
				local yawRate = chassis.AssemblyAngularVelocity:Dot(cf.UpVector)
				steerAngle = math.abs(speed) > 1 and math.atan(yawRate * wb / speed) or 0
				steerAngle = math.clamp(steerAngle, -0.6, 0.6)
			end
			local m = r.motors
			local spinCf = CFrame.Angles(r.spin, 0, 0)
			if m.RearWheelMotor then m.RearWheelMotor.Transform = spinCf end
			if m.FrontWheelMotor then m.FrontWheelMotor.Transform = spinCf end
			if m.ForkMotor then m.ForkMotor.Transform = CFrame.Angles(0, steerAngle, 0) end
			local steerCf = CFrame.Angles(0, steerAngle, 0)
			if m.FrontLeftWheelMotor then m.FrontLeftWheelMotor.Transform = steerCf * spinCf end
			if m.FrontRightWheelMotor then m.FrontRightWheelMotor.Transform = steerCf * spinCf end
			if m.RearLeftWheelMotor then m.RearLeftWheelMotor.Transform = spinCf end
			if m.RearRightWheelMotor then m.RearRightWheelMotor.Transform = spinCf end
			if m.BarsMotor then m.BarsMotor.Transform = CFrame.Angles(0, steerAngle * 0.8, 0) end
			-- the rider
			local driver = model:GetAttribute("Driver")
			local rider = driver and Players:GetPlayerByUserId(driver)
			local character = rider and rider.Character
			if character then
				local back = math.clamp(cf.LookVector.Y * 2.5, 0, 1)  -- leans back as the front comes up
				pose(character, kind, back)
			end
		end
	end
end)
