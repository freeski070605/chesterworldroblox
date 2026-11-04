local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

if not RunService:IsStudio() then
	return
end

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeoOrientation = require(Shared:WaitForChild("GeoOrientation"))

local BASE_SPEED = 140
local BOOST_SPEED = 520
local VERTICAL_SPEED = 110
local BOOST_VERTICAL_SPEED = 260

local flying = false
local rootPart = nil
local humanoid = nil

local pressed = {
	W = false,
	A = false,
	S = false,
	D = false,
	Space = false,
	Control = false,
	Shift = false,
}

local gui = Instance.new("ScreenGui")
gui.Name = "ChesterInspectorHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

-- Shared HUD visibility. H button is owned by HUDToggle.client.lua.
local function updateHUDVisibility()
    gui.Enabled = player:GetAttribute("CW_HUDVisible") ~= false
end
player:GetAttributeChangedSignal("CW_HUDVisible"):Connect(updateHUDVisibility)
updateHUDVisibility()

local panel = Instance.new("Frame")
panel.Name = "Inspector"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -18, 1, -18)
panel.Size = UDim2.fromOffset(370, 132)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
panel.BackgroundTransparency = 0.16
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 9)
title.Size = UDim2.new(1, -28, 0, 20)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "CHESTER WORLD INSPECTOR"
title.Parent = panel

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.fromOffset(14, 31)
status.Size = UDim2.new(1, -28, 0, 20)
status.Font = Enum.Font.GothamMedium
status.TextSize = 13
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(205, 210, 220)
status.Text = "F: Fly  •  X: 9th & Kerlin"
status.Parent = panel

local coords = Instance.new("TextLabel")
coords.BackgroundTransparency = 1
coords.Position = UDim2.fromOffset(14, 54)
coords.Size = UDim2.new(1, -28, 0, 20)
coords.Font = Enum.Font.Code
coords.TextSize = 13
coords.TextXAlignment = Enum.TextXAlignment.Left
coords.TextColor3 = Color3.fromRGB(230, 230, 230)
coords.Text = "X 0   Y 0   Z 0"
coords.Parent = panel

local compass = Instance.new("TextLabel")
compass.BackgroundTransparency = 1
compass.Position = UDim2.fromOffset(14, 76)
compass.Size = UDim2.new(1, -28, 0, 20)
compass.Font = Enum.Font.GothamBold
compass.TextSize = 13
compass.TextXAlignment = Enum.TextXAlignment.Left
compass.TextColor3 = Color3.fromRGB(255, 255, 255)
compass.Text = "TRUE HEADING 000° N"
compass.Parent = panel

local axes = Instance.new("TextLabel")
axes.BackgroundTransparency = 1
axes.Position = UDim2.fromOffset(14, 98)
axes.Size = UDim2.new(1, -28, 0, 24)
axes.Font = Enum.Font.Gotham
axes.TextSize = 11
axes.TextWrapped = true
axes.TextXAlignment = Enum.TextXAlignment.Left
axes.TextColor3 = Color3.fromRGB(180, 185, 195)
axes.Text = "TRUE N -Z  •  S +Z  •  E +X  •  W -X"
axes.Parent = panel

local function currentCharacter()
	local character = player.Character
	if not character then
		return nil
	end

	rootPart = character:FindFirstChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")
	return character
end

local function stopFlight()
	flying = false

	if rootPart and rootPart.Parent then
		rootPart.Anchored = false
	end

	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
	end
end

local function startFlight()
	if not currentCharacter() or not rootPart or not humanoid then
		return
	end

	flying = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	rootPart.Anchored = true
end

local function toggleFlight()
	if flying then
		stopFlight()
	else
		startFlight()
	end
end

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
terrainParams.IgnoreWater = false

local function terrainY(x, z)
	local result = Workspace:Raycast(
		Vector3.new(x, 5000, z),
		Vector3.new(0, -10000, 0),
		terrainParams
	)

	return result and result.Position.Y or 50
end

local function teleportToSpawn()
	if not currentCharacter() or not rootPart then
		return
	end

	-- Use the actual reflected runtime spawn instead of the old StreetData index.
	local spawn = Workspace:FindFirstChild("ChesterCitySpawn")
	if not spawn then
		return
	end

	local destination = CFrame.new(
		spawn.Position.X,
		spawn.Position.Y + 18,
		spawn.Position.Z
	)

	if flying then
		rootPart.CFrame = destination
	else
		player.Character:PivotTo(destination)
	end
end

local function setKey(input, value)
	local code = input.KeyCode

	if code == Enum.KeyCode.W then
		pressed.W = value
	elseif code == Enum.KeyCode.A then
		pressed.A = value
	elseif code == Enum.KeyCode.S then
		pressed.S = value
	elseif code == Enum.KeyCode.D then
		pressed.D = value
	elseif code == Enum.KeyCode.Space then
		pressed.Space = value
	elseif code == Enum.KeyCode.LeftControl or code == Enum.KeyCode.RightControl then
		pressed.Control = value
	elseif code == Enum.KeyCode.LeftShift or code == Enum.KeyCode.RightShift then
		pressed.Shift = value
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		toggleFlight()
		return
	end

	if input.KeyCode == Enum.KeyCode.X then
		teleportToSpawn()
		return
	end

	setKey(input, true)
end)

UserInputService.InputEnded:Connect(function(input)
	setKey(input, false)
end)

player.CharacterAdded:Connect(function()
	stopFlight()
	rootPart = nil
	humanoid = nil
	task.wait(0.5)
	currentCharacter()
end)

local function flatDirection(vector)
	local v = Vector3.new(vector.X, 0, vector.Z)

	if v.Magnitude < 0.001 then
		return GeoOrientation.NORTH
	end

	return v.Unit
end

RunService.RenderStepped:Connect(function(dt)
	camera = Workspace.CurrentCamera or camera

	if not rootPart or not rootPart.Parent then
		currentCharacter()
	end

	if rootPart then
		local p = rootPart.Position
		coords.Text = string.format(
			"X %7.0f   Y %5.0f   Z %7.0f",
			p.X,
			p.Y,
			p.Z
		)
	end

	if camera then
		local h =
			GeoOrientation.headingDegrees(
				flatDirection(camera.CFrame.LookVector)
			)

		compass.Text = string.format(
			"TRUE HEADING %03d° %s",
			math.floor(h + 0.5),
			GeoOrientation.headingName(h)
		)
	end

	if flying and rootPart and camera then
		local forward =
			flatDirection(camera.CFrame.LookVector)

		local right =
			flatDirection(camera.CFrame.RightVector)

		local move = Vector3.zero

		if pressed.W then move += forward end
		if pressed.S then move -= forward end
		if pressed.D then move += right end
		if pressed.A then move -= right end

		if move.Magnitude > 1 then
			move = move.Unit
		end

		local horizontalSpeed =
			pressed.Shift and BOOST_SPEED or BASE_SPEED

		local verticalSpeed =
			pressed.Shift and BOOST_VERTICAL_SPEED or VERTICAL_SPEED

		local vertical = 0
		if pressed.Space then vertical += 1 end
		if pressed.Control then vertical -= 1 end

		local displacement =
			move * horizontalSpeed * dt
			+ Vector3.new(
				0,
				vertical * verticalSpeed * dt,
				0
			)

		rootPart.CFrame =
			rootPart.CFrame + displacement

		rootPart.AssemblyLinearVelocity =
			Vector3.zero

		rootPart.AssemblyAngularVelocity =
			Vector3.zero

		status.Text =
			pressed.Shift
			and "FLYING — BOOST  •  F: Land  •  X: 9th & Kerlin"
			or "FLYING  •  Shift: Boost  •  F: Land  •  X: 9th & Kerlin"
	else
		status.Text =
			"F: Fly  •  X: 9th & Kerlin"
	end
end)

print("[ChesterWorld] True-geographic Studio inspector loaded.")
