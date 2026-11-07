-- EXIT 6 performance overlay (diagnostics for console testing): server and
-- client memory, server frame time, streamed parts. Top-left, small. The last
-- numbers on screen before a disconnect say which side ran out. Remove for release.
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "Exit6PerfHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Position = UDim2.fromOffset(8, 8)
label.Size = UDim2.fromOffset(330, 40)
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.BackgroundTransparency = 0.35
label.TextColor3 = Color3.fromRGB(120, 255, 140)
label.Font = Enum.Font.Code
label.TextSize = 14
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Parent = gui

local parts = 0
task.spawn(function()
	while true do
		-- a streamed-part count, spread over frames
		local n, i = 0, 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("BasePart") then n += 1 end
			i += 1
			if i % 20000 == 0 then task.wait() end
		end
		parts = n
		task.wait(10)
	end
end)
while true do
	label.Text = string.format(" SRV %sMB lua %sMB hb %sms\n CLI %dMB parts %d",
		tostring(Workspace:GetAttribute("Exit6SrvMemMB") or "?"), tostring(Workspace:GetAttribute("Exit6SrvLuaMB") or "?"),
		tostring(Workspace:GetAttribute("Exit6SrvHeartbeat") or "?"), math.floor(Stats:GetTotalMemoryUsageMb()), parts)
	-- stays on top of the main menu (it hides other HUDs)
	gui.Enabled = true
	task.wait(1)
end
