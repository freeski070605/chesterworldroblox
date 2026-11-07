-- EXIT 6 house decorator: outside the 9th & Kerlin core the server keeps each
-- home as its plain block plus a description (model attribute Exit6Kit) -
-- the full house kit city-wide was too much for an Xbox server / client. This
-- client builds the house kit (HouseKit, lite) locally for the homes near the
-- camera, hides the plain block under it, and clears it again further away.
-- Doors it builds are tagged Exit6FrontDoor locally, so Exit6HomeDoors.client
-- gives them the rent / look-inside prompts; the server builds a house for
-- real the first time it is used (Exit6Housing, KitServer) and this stops
-- decorating it.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HouseKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HouseKit"))
local world = Workspace:WaitForChild("ChesterWorld", 600)
if not world then return end

local NEAR, FAR = 300, 380
local PER_STEP = 3
local OLD_HOME_PARTS = { Walls = true, GroundStorey = true, Foundation = true, Cornice = true, Roof = true }
local OLD_PORCH = { PorchFloor = true, PorchRoof = true, PorchPost = true }

local decorFolder = Instance.new("Folder")
decorFolder.Name = "Exit6HouseDecor"
decorFolder.Parent = Workspace

local known = {}   -- model -> { pos, decor, ctx, homes, conn }

local function hide(part, on)
	part.LocalTransparencyModifier = on and 1 or 0
	for _, t in ipairs(part:GetChildren()) do
		if t:IsA("Decal") then t.LocalTransparencyModifier = on and 1 or 0 end
	end
end
local function insideRect(r, p)
	local l = r.frame:PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
	return math.abs(l.X) <= r.along / 2 + 0.5 and math.abs(l.Z) <= r.across / 2 + 0.5
end
local function covers(entry, part)
	if not part:IsA("BasePart") then return false end
	if OLD_PORCH[part.Name] then return true end
	if OLD_HOME_PARTS[part.Name] then
		for _, r in ipairs(entry.homes) do
			if insideRect(r, part.Position) then return true end
		end
	end
	return false
end

local function decorate(model, entry)
	local ctx, homes = HouseKit.Decode(model:GetAttribute("Exit6Kit"))
	entry.homes = homes
	ctx.lite = true
	ctx.buildingId = model:GetAttribute("ChesterBuildingId")
	ctx.applyFacade = HouseKit.ApplyFacade
	ctx.stats = { frontDoors = 0, backDoors = 0, sideDoors = 0, rentals = 0 }
	local m = Instance.new("Model")
	m.Name = tostring(ctx.buildingId)
	for _, r in ipairs(homes) do
		local ok, err = pcall(HouseKit.Build, m, r, ctx, HouseKit.H)
		if not ok then warn("[EXIT6 HouseDecor]", ctx.buildingId, err) end
	end
	-- decoration only: the server's block does the colliding
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = p.Name == "Door"
		end
	end
	m.Parent = decorFolder
	entry.decor = m
	for _, c in ipairs(model:GetChildren()) do
		if covers(entry, c) then hide(c, true) end
	end
	-- parts of the block that stream in later
	entry.conn = model.ChildAdded:Connect(function(c)
		if entry.decor and covers(entry, c) then hide(c, true) end
	end)
end

local function undecorate(model, entry)
	if entry.conn then entry.conn:Disconnect() entry.conn = nil end
	if entry.decor then entry.decor:Destroy() entry.decor = nil end
	if model.Parent and entry.homes then
		for _, c in ipairs(model:GetChildren()) do
			if c:IsA("BasePart") and covers(entry, c) then hide(c, false) end
		end
	end
end

local function track(model)
	if known[model] or not model:IsA("Model") then return end
	local kit = model:GetAttribute("Exit6Kit")
	if not kit then return end
	-- position: the first rect of the description
	local first = string.split(string.split(kit, ";")[2] or "", ",")
	local x, z = tonumber(first[1]), tonumber(first[2])
	if not x or not z then return end
	known[model] = { pos = Vector3.new(x, 0, z) }
end
local function untrack(model)
	local entry = known[model]
	if entry then
		undecorate(model, entry)
		known[model] = nil
	end
end

local function watchTile(tile)
	local f = tile:WaitForChild("Buildings", 30)
	if not f then return end
	for _, m in ipairs(f:GetChildren()) do track(m) end
	f.ChildAdded:Connect(track)
	f.ChildRemoved:Connect(untrack)
end
for _, tile in ipairs(world:GetChildren()) do task.spawn(watchTile, tile) end
world.ChildAdded:Connect(function(tile) task.spawn(watchTile, tile) end)

-- near the camera: decorate a few a step; far away / built for real: clear
while true do
	task.wait(0.15)
	-- around the player (what the server streams in), else the camera
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = Workspace.CurrentCamera
	local at = (root and root.Position) or (cam and cam.CFrame.Position)
	if at then
		local here = at * Vector3.new(1, 0, 1)
		local budget = PER_STEP
		for model, entry in pairs(known) do
			local d = (entry.pos - here).Magnitude
			local real = model:GetAttribute("KitServer")
			if entry.decor and (d > FAR or real) then
				undecorate(model, entry)
			elseif not entry.decor and not real and d < NEAR and budget > 0 then
				budget -= 1
				decorate(model, entry)
			end
		end
	end
end
