-- ChesterWorld unified, per-player HUD visibility toggle.
-- H toggles both top road name and bottom flight inspector.
-- A small always-visible button works on touch and mouse.
-- Flight/teleport key controls keep working with the HUD hidden.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local guiParent = player:WaitForChild("PlayerGui")

if player:GetAttribute("CW_HUDVisible") == nil then
    player:SetAttribute("CW_HUDVisible", true)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ChesterHUDToggle"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100
gui.Parent = guiParent

local button = Instance.new("TextButton")
button.Name = "ToggleHUD"
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -14, 0, 16)
button.Size = UDim2.fromOffset(104, 36)
button.BackgroundColor3 = Color3.fromRGB(17, 21, 26)
button.BackgroundTransparency = 0.13
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 12
button.TextColor3 = Color3.fromRGB(250, 250, 250)
button.AutoButtonColor = true
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 9)
corner.Parent = button

local function refresh()
    local visible = player:GetAttribute("CW_HUDVisible") ~= false
    button.Text = visible and "H  Hide HUD" or "H  Show HUD"
    button:SetAttribute("CW_HUDVisible", visible)
end

local function toggle()
    player:SetAttribute("CW_HUDVisible",
        not (player:GetAttribute("CW_HUDVisible") ~= false))
end

button.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or input.KeyCode ~= Enum.KeyCode.H then return end
    if UserInputService:GetFocusedTextBox() then return end
    toggle()
end)

player:GetAttributeChangedSignal("CW_HUDVisible"):Connect(refresh)
refresh()
print("[ChesterWorld HUD] Press H or tap the top-right button to hide/show HUDs.")
