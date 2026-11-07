-- EXIT 6 home door prompts, made on this client for the rentable front doors
-- streamed in around the player (every house in the city is for rent; ~19k
-- doors would be too many server prompts). Actions go to Exit6Housing.server
-- through the HomeDoor remote, which checks the player is at that door.
--   E          Move in ($)              (nobody lives there, you have no home yet)
--   F / X      Look inside / Go inside / Go outside
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Exit6Catalog"))
local remotes = ReplicatedStorage:WaitForChild("Exit6Remotes")
local HomeDoor = remotes:WaitForChild("HomeDoor")

local function myHome()
	local raw = player:GetAttribute("Exit6Profile")
	local ok, p = pcall(function() return raw and HttpService:JSONDecode(raw) end)
	return ok and type(p) == "table" and p.home and p.home.id or nil
end

local function refresh(door)
	local move = door:FindFirstChild("Exit6MoveIn")
	local enter = door:FindFirstChild("Exit6Enter")
	if not move or not enter then return end
	local id = door:GetAttribute("Exit6HomeId")
	local mine = myHome() == id
	local occupant = door:GetAttribute("Exit6OccupantName")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local insideNow = root and door.CFrame:PointToObjectSpace(root.Position).Z > 0
	local price = Catalog.Housing[door:GetAttribute("Exit6HomeStyle") or ""] or Catalog.Housing.default
	move.Enabled = not occupant and not mine and not insideNow and myHome() == nil
	move.ActionText = "Move in ($" .. price .. ")"
	move.ObjectText = "For rent"
	if insideNow then
		enter.ActionText = "Go outside"
		enter.ObjectText = mine and "Home" or ""
		enter.Enabled = true
	elseif mine then
		enter.ActionText = "Go inside"
		enter.ObjectText = "Home"
		enter.Enabled = true
	elseif occupant then
		enter.ActionText = "Knock"
		enter.ObjectText = occupant .. "'s place"
		enter.Enabled = true
	else
		enter.ActionText = "Look inside"
		enter.ObjectText = "For rent"
		enter.Enabled = true
	end
end

local function setup(door)
	if not door:IsA("BasePart") or not door:GetAttribute("Exit6Rentable") or door:FindFirstChild("Exit6MoveIn") then return end
	local id = door:GetAttribute("Exit6HomeId")
	local move = Instance.new("ProximityPrompt")
	move.Name = "Exit6MoveIn"
	move.HoldDuration = 0.6
	move.MaxActivationDistance = 8
	move.RequiresLineOfSight = false
	move.Parent = door
	move.Triggered:Connect(function() HomeDoor:FireServer(id, "movein") end)
	local enter = Instance.new("ProximityPrompt")
	enter.Name = "Exit6Enter"
	enter.KeyboardKeyCode = Enum.KeyCode.F
	enter.GamepadKeyCode = Enum.KeyCode.ButtonX
	enter.MaxActivationDistance = 8
	enter.RequiresLineOfSight = false
	enter.UIOffset = Vector2.new(0, 70)
	enter.Parent = door
	enter.Triggered:Connect(function()
		if enter.ActionText == "Knock" then return end
		HomeDoor:FireServer(id, "enter")
	end)
	door:GetAttributeChangedSignal("Exit6OccupantName"):Connect(function() refresh(door) end)
	refresh(door)
end

for _, d in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do task.spawn(setup, d) end
CollectionService:GetInstanceAddedSignal("Exit6FrontDoor"):Connect(setup)
-- prompts show in / out and whether you've a home yet when they come up
ProximityPromptService.PromptShown:Connect(function(prompt)
	if prompt.Name == "Exit6Enter" or prompt.Name == "Exit6MoveIn" then refresh(prompt.Parent) end
end)
player:GetAttributeChangedSignal("Exit6Profile"):Connect(function()
	for _, d in ipairs(CollectionService:GetTagged("Exit6FrontDoor")) do
		if d:FindFirstChild("Exit6Enter") then refresh(d) end
	end
end)

-- keep the doors right by you current (in / out, someone moved in): PromptShown
-- is not reliable for the prompts on doors this client built itself
local near = OverlapParams.new()
near.MaxParts = 80
task.spawn(function()
	while true do
		task.wait(0.5)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			near.FilterType = Enum.RaycastFilterType.Exclude
			near.FilterDescendantsInstances = { player.Character }
			for _, p in ipairs(workspace:GetPartBoundsInRadius(root.Position, 15, near)) do
				if p:FindFirstChild("Exit6Enter") then refresh(p) end
			end
		end
	end
end)
