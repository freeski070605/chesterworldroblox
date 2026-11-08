-- EXIT 6 events, client: a banner while an event is on (Exit6Events.server,
-- Workspace attribute Exit6Event) and a marker over where it is.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "Exit6EventBanner"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 278)
banner.Size = UDim2.fromOffset(420, 34)
banner.BackgroundColor3 = Color3.fromRGB(110, 40, 140)
banner.BackgroundTransparency = 0.1
banner.TextColor3 = Color3.new(1, 1, 1)
banner.Font = Enum.Font.GothamBlack
banner.TextSize = 16
banner.Visible = false
banner.Parent = gui
local c = Instance.new("UICorner")
c.CornerRadius = UDim.new(0, 10)
c.Parent = banner

local marker = nil
local markerKey = nil
local function setMarker(ev)
	local key = ev and (ev.name .. table.concat(ev.pos, ",")) or nil
	if key == markerKey then return end
	markerKey = key
	if marker then marker:Destroy() marker = nil end
	if not ev then return end
	local p = Instance.new("Part")
	p.Name = "Exit6EventMarker"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one
	p.CFrame = CFrame.new(ev.pos[1], ev.pos[2] + 14, ev.pos[3])
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 100000
	bb.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = Color3.fromRGB(110, 40, 140)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 16
	l.Text = "EVENT"
	l.Parent = bb
	p.Parent = Workspace
	marker = p
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.5 then return end
	acc = 0
	local raw = Workspace:GetAttribute("Exit6Event")
	local ok, ev = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	ev = ok and type(ev) == "table" and ev or nil
	setMarker(ev)
	banner.Visible = ev ~= nil
	if ev then
		local left = math.max(0, math.floor((ev.ends or 0) - Workspace:GetServerTimeNow()))
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local d = root and math.floor((Vector3.new(ev.pos[1], 0, ev.pos[3]) - root.Position * Vector3.new(1, 0, 1)).Magnitude) or 0
		banner.Text = string.format("%s  -  %d studs  -  %d:%02d left", ev.name, d, left // 60, left % 60)
	end
end)
