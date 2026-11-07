-- EXIT 6 driving: while the local player sits in an EXIT 6 car's DriverSeat
-- this client owns the car's physics (Exit6Vehicles.server hands it over) and
-- steps Exit6CarPhysics every frame from the VehicleSeat input:
--   W / S or Up / Down, R2 / L2 (gamepad)   gas / brake-reverse
--   A / D or Left / Right, left stick       steer
--   Shift / ButtonX                         handbrake
--   Space / ButtonA                         get out
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local CarPhysics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6CarPhysics"))
local STUDS_PER_MPH = 3.92 * 0.44704 -- ChesterWorld ~3.92 studs per real metre

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6Speedo"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 16, 1, -16)
panel.Size = UDim2.fromOffset(190, 92)
panel.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
panel.BackgroundTransparency = 0.15
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel
local speedLabel = Instance.new("TextLabel")
speedLabel.BackgroundTransparency = 1
speedLabel.Position = UDim2.fromOffset(14, 4)
speedLabel.Size = UDim2.new(1, -28, 0, 46)
speedLabel.Font = Enum.Font.GothamBlack
speedLabel.TextSize = 40
speedLabel.TextColor3 = Color3.fromRGB(245, 245, 242)
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Parent = panel
local unit = Instance.new("TextLabel")
unit.BackgroundTransparency = 1
unit.Position = UDim2.fromOffset(14, 48)
unit.Size = UDim2.new(1, -28, 0, 18)
unit.Font = Enum.Font.GothamBold
unit.TextSize = 13
unit.TextColor3 = Color3.fromRGB(229, 157, 53)
unit.TextXAlignment = Enum.TextXAlignment.Left
unit.Text = "MPH"
unit.Parent = panel
-- fuel gauge
local gaugeBack = Instance.new("Frame")
gaugeBack.Position = UDim2.fromOffset(14, 70)
gaugeBack.Size = UDim2.new(1, -28, 0, 10)
gaugeBack.BackgroundColor3 = Color3.fromRGB(50, 54, 62)
gaugeBack.BorderSizePixel = 0
gaugeBack.Parent = panel
local gauge = Instance.new("Frame")
gauge.Size = UDim2.fromScale(1, 1)
gauge.BackgroundColor3 = Color3.fromRGB(229, 157, 53)
gauge.BorderSizePixel = 0
gauge.Parent = gaugeBack

local handbrake = false
local conn = nil

local function stop()
	if conn then conn:Disconnect() conn = nil end
	gui.Enabled = false
	handbrake = false
	ContextActionService:UnbindAction("Exit6Handbrake")
end

local function start(seat)
	stop()
	local car = seat.Parent
	gui.Enabled = true
	ContextActionService:BindAction("Exit6Handbrake", function(_, state)
		if state == Enum.UserInputState.Begin then handbrake = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then handbrake = false end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonX)
	conn = RunService.PreSimulation:Connect(function(dt)
		if not car.Parent or seat.Occupant == nil then stop() return end
		local speed = CarPhysics.Step(car, dt, {
			throttle = seat.ThrottleFloat, steer = seat.SteerFloat, handbrake = handbrake,
		})
		speedLabel.Text = tostring(math.floor(math.abs(speed) / STUDS_PER_MPH + 0.5))
		local fuel, tank = car:GetAttribute("Fuel") or 0, car:GetAttribute("Tank") or 1
		local f = math.clamp(fuel / tank, 0, 1)
		gauge.Size = UDim2.fromScale(f, 1)
		gauge.BackgroundColor3 = f < 0.15 and Color3.fromRGB(200, 50, 40) or Color3.fromRGB(229, 157, 53)
		unit.Text = string.format("MPH    FUEL %d%%%s", math.floor(f * 100 + 0.5), fuel <= 0 and "  EMPTY" or (f < 0.15 and "  LOW" or ""))
	end)
end

local function watch(character)
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum.Seated:Connect(function(active, seat)
		if active and seat and seat:IsA("VehicleSeat") and seat.Parent and seat.Parent:GetAttribute("Exit6Car") then
			start(seat)
		else
			stop()
		end
	end)
end
if player.Character then task.spawn(watch, player.Character) end
player.CharacterAdded:Connect(watch)
player.CharacterRemoving:Connect(stop)
