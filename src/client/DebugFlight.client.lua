-- ChesterWorld tester flight / fast travel, keyboard + gamepad (console).
-- Always on in Studio; in a live server for players the server marks CW_Tester
-- (src/server/TesterAccess.server.lua, WorldConfig.TESTER_FLIGHT_ALL).
--
-- Keyboard: F fly  •  WASD move  •  Space/E up  •  Ctrl/Q down  •  Shift boost
--           [ / ] speed level  •  X back to 9th & Kerlin  (H: HUD, HUDToggle)
-- Gamepad:  Y fly  •  left stick move  •  RT up  •  LT down  •  RB boost
--           LB precise  •  D-pad up/down speed level  •  D-pad left spawn
--           D-pad right HUD.  On the ground RB / Shift sprints.
--
-- Flight drives the character with a LinearVelocity + AlignOrientation (no
-- anchoring) so the movement replicates and the world streams in around the
-- tester in live servers too.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

if not RunService:IsStudio() then
	local deadline = os.clock() + 20
	while player:GetAttribute("CW_Tester") == nil and os.clock() < deadline do
		task.wait(0.25)
	end
	if player:GetAttribute("CW_Tester") ~= true then
		return
	end
end

local camera = Workspace.CurrentCamera
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeoOrientation = require(Shared:WaitForChild("GeoOrientation"))

local BASE_SPEED = 140
local VERTICAL_SPEED = 110
local BOOST = 3.5
local PRECISE = 0.25
local TIERS = { 0.5, 1, 2, 4 }
local tier = 2
local WALK_SPEED = 16
local SPRINT_SPEED = 64
local testerSprinting = false
local DEADZONE = 0.15

local flying = false
local rootPart, humanoid
local mover, aligner, attachment

local keys = { W = false, A = false, S = false, D = false, Up = false, Down = false, Boost = false }
local pad = { stick = Vector2.zero, rt = 0, lt = 0, rb = false, lb = false }
local usingGamepad = UserInputService.GamepadEnabled

-- HUD -----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ChesterInspectorHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local function updateHUDVisibility()
	gui.Enabled = player:GetAttribute("CW_HUDVisible") ~= false
end
player:GetAttributeChangedSignal("CW_HUDVisible"):Connect(updateHUDVisibility)
updateHUDVisibility()

local panel = Instance.new("Frame")
panel.Name = "Inspector"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -18, 1, -18)
panel.Size = UDim2.fromOffset(400, 152)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
panel.BackgroundTransparency = 0.16
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local function label(y, h, font, size, color, text)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(14, y)
	t.Size = UDim2.new(1, -28, 0, h)
	t.Font = font
	t.TextSize = size
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	t.Text = text
	t.Parent = panel
	return t
end
label(9, 20, Enum.Font.GothamBold, 14, Color3.fromRGB(255, 255, 255), "CHESTER WORLD INSPECTOR")
local status = label(31, 20, Enum.Font.GothamMedium, 13, Color3.fromRGB(205, 210, 220), "")
local coords = label(54, 20, Enum.Font.Code, 13, Color3.fromRGB(230, 230, 230), "X 0   Y 0   Z 0")
local compass = label(76, 20, Enum.Font.GothamBold, 13, Color3.fromRGB(255, 255, 255), "TRUE HEADING 000° N")
local help = label(98, 46, Enum.Font.Gotham, 11, Color3.fromRGB(180, 185, 195), "")

local function refreshHelp()
	if usingGamepad then
		help.Text = "Y fly • L-stick move • RT up • LT down • RB boost • LB precise\n"
			.. "D-pad ▲▼ speed • ◀ 9th & Kerlin • ▶ HUD   (ground: hold RB to sprint)"
	else
		help.Text = "F fly • WASD move • Space/E up • Ctrl/Q down • Shift boost\n"
			.. "[ ] speed • X 9th & Kerlin • H HUD   (ground: hold Shift to sprint)"
	end
end
refreshHelp()

-- Character / flight -----------------------------------------------------------
local function currentCharacter()
	local character = player.Character
	if not character then return nil end
	rootPart = character:FindFirstChild("HumanoidRootPart")
	humanoid = character:FindFirstChildOfClass("Humanoid")
	return character
end

local function stopFlight()
	flying = false
	player:SetAttribute("CW_Flying", nil)
	for _, inst in ipairs({ mover, aligner, attachment }) do
		if inst then inst:Destroy() end
	end
	mover, aligner, attachment = nil, nil, nil
	if rootPart and rootPart.Parent then
		rootPart.Anchored = false
	end
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = true
		humanoid.PlatformStand = false
	end
end

local function startFlight()
	if not currentCharacter() or not rootPart or not humanoid then return end
	flying = true
	player:SetAttribute("CW_Flying", true)
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	attachment = Instance.new("Attachment")
	attachment.Name = "CW_FlightAttachment"
	attachment.Parent = rootPart
	mover = Instance.new("LinearVelocity")
	mover.Name = "CW_FlightVelocity"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.MaxForce = math.huge
	mover.VectorVelocity = Vector3.zero
	mover.Parent = rootPart
	aligner = Instance.new("AlignOrientation")
	aligner.Name = "CW_FlightAlign"
	aligner.Mode = Enum.OrientationAlignmentMode.OneAttachment
	aligner.Attachment0 = attachment
	aligner.MaxTorque = math.huge
	aligner.Responsiveness = 40
	aligner.CFrame = rootPart.CFrame.Rotation
	aligner.Parent = rootPart
end

local function toggleFlight()
	if flying then stopFlight() else startFlight() end
end

local function teleportToSpawn()
	if not currentCharacter() or not rootPart then return end
	local spawn = Workspace:FindFirstChild("ChesterCitySpawn")
	if not spawn then return end
	player.Character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, 18, 0)))
	rootPart.AssemblyLinearVelocity = Vector3.zero
end

local function setTier(delta)
	tier = math.clamp(tier + delta, 1, #TIERS)
end

local function toggleHUD()
	player:SetAttribute("CW_HUDVisible", not (player:GetAttribute("CW_HUDVisible") ~= false))
end

-- Input ------------------------------------------------------------------------
local KEYMAP = {
	[Enum.KeyCode.W] = "W", [Enum.KeyCode.A] = "A", [Enum.KeyCode.S] = "S", [Enum.KeyCode.D] = "D",
	[Enum.KeyCode.Space] = "Up", [Enum.KeyCode.E] = "Up",
	[Enum.KeyCode.LeftControl] = "Down", [Enum.KeyCode.RightControl] = "Down", [Enum.KeyCode.Q] = "Down",
	[Enum.KeyCode.LeftShift] = "Boost", [Enum.KeyCode.RightShift] = "Boost",
}

local function isGamepad(input)
	return input.UserInputType.Name:sub(1, 7) == "Gamepad"
end

-- EXIT 6 gameplay owns some of the same buttons (F / X at a counter prompt,
-- ButtonY / D-pad / X near another player or in a rumble): flight yields
-- while a ProximityPrompt is showing or Exit6Rumble marks Exit6Context
local promptsShown = {}
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptShown:Connect(function(prompt) promptsShown[prompt] = true end)
ProximityPromptService.PromptHidden:Connect(function(prompt) promptsShown[prompt] = nil end)
local function anyPrompt()
	for prompt in pairs(promptsShown) do
		if prompt.Parent and prompt.Enabled then return true end
		promptsShown[prompt] = nil
	end
	return false
end
local YIELD_KEYS = {
	[Enum.KeyCode.F] = true, [Enum.KeyCode.X] = true, [Enum.KeyCode.ButtonY] = true,
	[Enum.KeyCode.DPadUp] = true, [Enum.KeyCode.DPadDown] = true, [Enum.KeyCode.DPadLeft] = true,
	[Enum.KeyCode.DPadRight] = true, [Enum.KeyCode.ButtonR1] = true,
}
-- a prompt in reach right now (PromptShown is not reliable for prompts the
-- client builds itself, e.g. the house decorator's front doors)
local promptParams = OverlapParams.new()
promptParams.MaxParts = 60
local function promptInReach()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	promptParams.FilterType = Enum.RaycastFilterType.Exclude
	promptParams.FilterDescendantsInstances = { char }
	for _, p in ipairs(Workspace:GetPartBoundsInRadius(root.Position, 10, promptParams)) do
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("ProximityPrompt") and c.Enabled then return true end
		end
	end
	return false
end

local function gameplayOwns(code)
	if (code == Enum.KeyCode.F or code == Enum.KeyCode.X or code == Enum.KeyCode.ButtonY) and promptInReach() then return true end
	-- on foot, D-pad Up opens the EXIT 6 phone (Exit6Phone.client); in flight it is the speed tier
	if code == Enum.KeyCode.DPadUp and not flying then return true end
	return YIELD_KEYS[code] and (anyPrompt() or player:GetAttribute("Exit6Context") ~= nil)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if UserInputService:GetFocusedTextBox() then return end
	if gameplayOwns(input.KeyCode) then return end
	-- the EXIT 6 main menu owns the controller / keyboard until Play
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui and playerGui:FindFirstChild("Exit6MainMenu") then return end
	local code = input.KeyCode
	if isGamepad(input) then
		if not usingGamepad then usingGamepad = true refreshHelp() end
		if code == Enum.KeyCode.ButtonY then toggleFlight()
		elseif code == Enum.KeyCode.DPadUp then setTier(1)
		elseif code == Enum.KeyCode.DPadDown then setTier(-1)
		elseif code == Enum.KeyCode.DPadLeft then teleportToSpawn()
		elseif code == Enum.KeyCode.DPadRight then toggleHUD()
		elseif code == Enum.KeyCode.ButtonR1 then pad.rb = true
		elseif code == Enum.KeyCode.ButtonL1 then pad.lb = true
		end
		return
	end
	if processed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard and usingGamepad then
		usingGamepad = false
		refreshHelp()
	end
	if code == Enum.KeyCode.F then toggleFlight() return end
	if code == Enum.KeyCode.X then teleportToSpawn() return end
	if code == Enum.KeyCode.RightBracket then setTier(1) return end
	if code == Enum.KeyCode.LeftBracket then setTier(-1) return end
	local key = KEYMAP[code]
	if key then keys[key] = true end
end)

UserInputService.InputEnded:Connect(function(input)
	local code = input.KeyCode
	if code == Enum.KeyCode.ButtonR1 then pad.rb = false
	elseif code == Enum.KeyCode.ButtonL1 then pad.lb = false
	elseif code == Enum.KeyCode.ButtonR2 then pad.rt = 0
	elseif code == Enum.KeyCode.ButtonL2 then pad.lt = 0
	elseif code == Enum.KeyCode.Thumbstick1 then pad.stick = Vector2.zero
	end
	local key = KEYMAP[code]
	if key then keys[key] = false end
end)

UserInputService.InputChanged:Connect(function(input)
	local code = input.KeyCode
	if code == Enum.KeyCode.Thumbstick1 then
		local v = Vector2.new(input.Position.X, input.Position.Y)
		pad.stick = v.Magnitude > DEADZONE and v or Vector2.zero
	elseif code == Enum.KeyCode.ButtonR2 then
		pad.rt = input.Position.Z
	elseif code == Enum.KeyCode.ButtonL2 then
		pad.lt = input.Position.Z
	end
end)

UserInputService.GamepadConnected:Connect(function() usingGamepad = true refreshHelp() end)

player.CharacterAdded:Connect(function()
	stopFlight()
	rootPart, humanoid = nil, nil
	task.wait(0.5)
	currentCharacter()
end)

local function flatDirection(vector)
	local v = Vector3.new(vector.X, 0, vector.Z)
	if v.Magnitude < 0.001 then return GeoOrientation.NORTH end
	return v.Unit
end

-- Frame ------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	camera = Workspace.CurrentCamera or camera
	if not rootPart or not rootPart.Parent then currentCharacter() end

	if rootPart then
		local p = rootPart.Position
		coords.Text = string.format("X %7.0f   Y %5.0f   Z %7.0f", p.X, p.Y, p.Z)
	end
	if camera then
		local h = GeoOrientation.headingDegrees(flatDirection(camera.CFrame.LookVector))
		compass.Text = string.format("TRUE HEADING %03d° %s", math.floor(h + 0.5), GeoOrientation.headingName(h))
	end

	local boost = keys.Boost or pad.rb
	local precise = pad.lb
	local scale = TIERS[tier] * (boost and BOOST or 1) * (precise and PRECISE or 1)

	if flying and rootPart and camera and mover then
		local forward = flatDirection(camera.CFrame.LookVector)
		local right = flatDirection(camera.CFrame.RightVector)
		local move = Vector3.zero
		if keys.W then move += forward end
		if keys.S then move -= forward end
		if keys.D then move += right end
		if keys.A then move -= right end
		-- analog stick: Y up = forward
		move += forward * pad.stick.Y + right * pad.stick.X
		if move.Magnitude > 1 then move = move.Unit end
		local vertical = (keys.Up and 1 or 0) - (keys.Down and 1 or 0) + pad.rt - pad.lt
		vertical = math.clamp(vertical, -1, 1)
		mover.VectorVelocity = move * BASE_SPEED * scale + Vector3.new(0, vertical * VERTICAL_SPEED * scale, 0)
		aligner.CFrame = CFrame.lookAt(Vector3.zero, forward)
		status.Text = string.format("FLYING  •  speed %gx%s", TIERS[tier],
			boost and "  •  BOOST" or (precise and "  •  PRECISE" or ""))
	else
		-- only own the walk speed while the tester sprint is held; otherwise the
		-- game's own movement (EXIT 6 sprint, Exit6Gameplay.client) sets it
		if humanoid and humanoid.Parent and not flying then
			if boost then
				humanoid.WalkSpeed = SPRINT_SPEED * TIERS[tier]
				testerSprinting = true
			elseif testerSprinting then
				humanoid.WalkSpeed = WALK_SPEED
				testerSprinting = false
			end
		end
		status.Text = string.format("WALKING  •  speed level %gx%s", TIERS[tier], boost and "  •  SPRINT" or "")
	end
end)

print("[ChesterWorld] Tester flight loaded (keyboard + gamepad).")
