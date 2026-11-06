-- EXIT 6 Xbox/keyboard-compatible sprint and basic gameplay HUD.
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Exit6Config"))
local gui = Instance.new("ScreenGui")
gui.Name = "Exit6HUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local panel = Instance.new("TextLabel")
panel.Name = "Status"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 16)
panel.Size = UDim2.fromOffset(300, 56)
panel.BackgroundColor3 = Color3.fromRGB(18, 21, 27)
panel.BackgroundTransparency = 0.18
panel.TextColor3 = Color3.new(1, 1, 1)
panel.Font = Enum.Font.GothamBold
panel.TextSize = 17
panel.Text = "EXIT 6 | Loading..."
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel
local function refresh()
 local stats = player:FindFirstChild("leaderstats")
 local cash = stats and stats:FindFirstChild("Chester Cash")
 local rep = stats and stats:FindFirstChild("Reputation")
 if not cash or not rep then
  panel.Text = "EXIT 6 | Progress unavailable"
 else
  panel.Text = string.format("EXIT 6  |  $%d  |  REP %d", cash.Value, rep.Value)
 end
end
task.spawn(function()
 local stats = player:WaitForChild("leaderstats", 20)
 if not stats then refresh() return end
 for _, name in ipairs({"Chester Cash", "Reputation"}) do
  local value = stats:WaitForChild(name, 10)
  if value then value:GetPropertyChangedSignal("Value"):Connect(refresh) end
 end
 refresh()
end)
local sprinting = false
local function applySpeed()
 local character = player.Character
 local humanoid = character and character:FindFirstChildOfClass("Humanoid")
 if humanoid then humanoid.WalkSpeed = sprinting and Config.SprintSpeed or Config.WalkSpeed end
end
local function sprintAction(_, state)
 if state == Enum.UserInputState.Begin then sprinting = true
 elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then sprinting = false
 else return Enum.ContextActionResult.Pass end
 applySpeed()
 return Enum.ContextActionResult.Sink
end
ContextActionService:BindAction("Exit6Sprint", sprintAction, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("Exit6Sprint", "Sprint")
player.CharacterAdded:Connect(function(character)
 sprinting = false
 local humanoid = character:WaitForChild("Humanoid", 10)
 if humanoid then humanoid.WalkSpeed = Config.WalkSpeed end
end)
