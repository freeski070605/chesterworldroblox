-- ChesterWorld landmarks. Data: src/shared/WorldData/Landmarks.lua
-- (tools/build_landmarks.py: outline, oriented box {cx, cz, length, width, yaw}
-- and the county building ids under each landmark, all in studs). Generic
-- footprint buildings are restyled in place or replaced by bespoke geometry.
-- Shapes and placements were checked against the DVRPC 2025 orthophoto
-- (tools/harness/crossing_aerial.py sites lm_*).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Landmarks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldData"):WaitForChild("Landmarks"))

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end

local root = Instance.new("Folder")
root.Name = "ChesterLandmarks"
root.Parent = Workspace
local world = Workspace:WaitForChild("ChesterWorld")

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
local function groundY(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), terrainParams)
	return hit and hit.Position.Y or nil
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local WHITE = rgb(236, 234, 226)

local partCount = 0
local function part(parent, name, size, cframe, material, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color or WHITE
	if shape then p.Shape = shape end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	partCount += 1
	if partCount % 150 == 0 then task.wait() end
	return p
end

local function wedge(parent, name, size, cframe, material, color)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cframe
	w.Material = material or Enum.Material.SmoothPlastic
	w.Color = color or WHITE
	w.Parent = parent
	partCount += 1
	return w
end

-- a straight member between two points
local function beam(parent, name, a, b, thickness, material, color)
	return part(parent, name, Vector3.new(thickness, thickness, (b - a).Magnitude + thickness * 0.5),
		CFrame.lookAt((a + b) / 2, b), material, color)
end

local function sign(parent, text, cframe, width, height, background, textColor)
	local board = part(parent, "Sign", Vector3.new(width, height, 0.6), cframe, Enum.Material.SmoothPlastic, background)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0.2
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = textColor or WHITE
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Text = text
		label.Parent = gui
	end
	return board
end

-- county building models by id
local buildingsById = {}
for _, tile in ipairs(world:GetChildren()) do
	local folder = tile:FindFirstChild("Buildings")
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			local id = model:GetAttribute("ChesterBuildingId")
			if id then buildingsById[id] = model end
		end
	end
end
local function modelsOf(lm)
	local list = {}
	for _, id in ipairs(lm and lm.buildings or {}) do
		if buildingsById[id] then table.insert(list, buildingsById[id]) end
	end
	return list
end
local function wallParts(model)
	local list = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and (p.Name == "Walls" or p.Name == "GroundStorey") then table.insert(list, p) end
	end
	return list
end
local function largestWall(models)
	local best, area = nil, 0
	for _, m in ipairs(models) do
		for _, p in ipairs(wallParts(m)) do
			if p.Size.X * p.Size.Z > area then best, area = p, p.Size.X * p.Size.Z end
		end
	end
	return best
end
local function restyle(models, material, color, keepTextures)
	for _, m in ipairs(models) do
		for _, p in ipairs(wallParts(m)) do
			p.Material = material
			p.Color = color
			if not keepTextures then
				for _, t in ipairs(p:GetChildren()) do
					if t:IsA("Texture") then t:Destroy() end
				end
			end
		end
	end
end

-- road parts for "which side faces the street"
local roadFolders = {}
for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then table.insert(roadFolders, roads) end
end
local roadParams = OverlapParams.new()
roadParams.FilterType = Enum.RaycastFilterType.Include
roadParams.FilterDescendantsInstances = roadFolders

-- the face of a wall part closest to a road: returns CFrame on that face
-- (looking outward), and the face width
local function streetFace(wall)
	local best, bestDist, bestWidth
	for _, f in ipairs({
		{ Vector3.new(0, 0, -1), wall.Size.X }, { Vector3.new(0, 0, 1), wall.Size.X },
		{ Vector3.new(-1, 0, 0), wall.Size.Z }, { Vector3.new(1, 0, 0), wall.Size.Z },
	}) do
		local half = math.abs(f[1].X) > 0 and wall.Size.X / 2 or wall.Size.Z / 2
		local centre = wall.CFrame * (f[1] * half)
		local dist = math.huge
		for _, r in ipairs(Workspace:GetPartBoundsInRadius(centre, 160, roadParams)) do
			dist = math.min(dist, (Vector3.new(r.Position.X - centre.X, 0, r.Position.Z - centre.Z)).Magnitude)
		end
		if not bestDist or dist < bestDist then
			local outward = wall.CFrame:VectorToWorldSpace(f[1])
			best, bestDist, bestWidth = CFrame.lookAt(centre, centre + outward), dist, f[2]
		end
	end
	return best, bestWidth
end

local function wallTopY(wall)
	return wall.Position.Y + wall.Size.Y / 2
end
local function wallBottomY(wall)
	local g = wall:GetAttribute("GroundY")
	return g or (wall.Position.Y - wall.Size.Y / 2)
end

-- classical portico: columns + entablature + pediment on a street face
local function portico(parent, face, width, height, columns, color)
	local depth = 14
	local base = face * CFrame.new(0, 0, -depth / 2)
	local span = width * 0.6
	for i = 0, columns - 1 do
		local x = -span / 2 + span * i / math.max(columns - 1, 1)
		part(parent, "Column", Vector3.new(height, 2.6, 2.6),
			base * CFrame.new(x, height / 2, -depth / 2 + 3) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Marble, color, Enum.PartType.Cylinder)
	end
	part(parent, "Entablature", Vector3.new(span + 6, 3, depth), base * CFrame.new(0, height + 1.5, 0), Enum.Material.Marble, color)
	part(parent, "Steps", Vector3.new(span + 8, 1.6, depth + 6), base * CFrame.new(0, 0.8, -3), Enum.Material.Marble, color)
	local rise = math.min(span * 0.18, 14)
	for side = -1, 1, 2 do
		wedge(parent, "Pediment", Vector3.new(depth, rise, (span + 6) / 2),
			base * CFrame.new(side * (span + 6) / 4, height + 3 + rise / 2, 0) * CFrame.Angles(0, side == 1 and -math.pi / 2 or math.pi / 2, 0),
			Enum.Material.Marble, color)
	end
end

local built = {}

------------------------------------------------------------------------------
-- Chester City Hall: red brick, white trim, columned portico, cupola
do
	local lm = Landmarks.city_hall
	local models = modelsOf(lm)
	local wall = largestWall(models)
	if wall then
		local model = Instance.new("Model")
		model.Name = "Chester City Hall"
		restyle(models, Enum.Material.Brick, rgb(150, 64, 50), true)
		local top, bottom = wallTopY(wall), wallBottomY(wall)
		part(model, "Cornice", Vector3.new(wall.Size.X + 2, 2, wall.Size.Z + 2), wall.CFrame.Rotation + Vector3.new(wall.Position.X, top + 1, wall.Position.Z), Enum.Material.Concrete, WHITE)
		local face, width = streetFace(wall)
		face = face - Vector3.new(0, face.Position.Y - bottom, 0)
		portico(model, face, width, math.min(top - bottom - 4, 34), 6, WHITE)
		-- cupola
		local c = Vector3.new(wall.Position.X, top + 2, wall.Position.Z)
		part(model, "CupolaBase", Vector3.new(16, 10, 16), CFrame.new(c + Vector3.new(0, 5, 0)) * wall.CFrame.Rotation, Enum.Material.Concrete, WHITE)
		part(model, "CupolaDrum", Vector3.new(12, 11, 11), CFrame.new(c + Vector3.new(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Concrete, WHITE, Enum.PartType.Cylinder)
		part(model, "Dome", Vector3.new(12, 12, 12), CFrame.new(c + Vector3.new(0, 21, 0)), Enum.Material.Metal, rgb(92, 140, 118), Enum.PartType.Ball)
		part(model, "Flagpole", Vector3.new(0.4, 14, 0.4), CFrame.new(c + Vector3.new(0, 33, 0)), Enum.Material.Metal, rgb(200, 200, 200))
		part(model, "Flag", Vector3.new(0.1, 3, 5), CFrame.new(c + Vector3.new(0, 38, 2.5)), Enum.Material.Fabric, rgb(40, 60, 140))
		sign(model, "CITY OF CHESTER", face * CFrame.new(0, math.min(top - bottom - 4, 34) + 9, -0.4), math.min(width * 0.5, 60), 5, rgb(150, 64, 50), WHITE)
		model.Parent = root
		built.city_hall = true
	end
end

------------------------------------------------------------------------------
-- Widener Old Main: stone, mansard roof, central clock tower
do
	local models = modelsOf(Landmarks.old_main)
	local wall = largestWall(models)
	if wall then
		local model = Instance.new("Model")
		model.Name = "Old Main"
		restyle(models, Enum.Material.Slate, rgb(176, 164, 148), true)
		local top, bottom = wallTopY(wall), wallBottomY(wall)
		-- mansard: steep slate band all round + flat cap
		part(model, "Mansard", Vector3.new(wall.Size.X - 2, 14, wall.Size.Z - 2), wall.CFrame.Rotation + Vector3.new(wall.Position.X, top + 7, wall.Position.Z), Enum.Material.Slate, rgb(64, 66, 74))
		part(model, "MansardCap", Vector3.new(wall.Size.X - 10, 1, wall.Size.Z - 10), wall.CFrame.Rotation + Vector3.new(wall.Position.X, top + 14.5, wall.Position.Z), Enum.Material.Slate, rgb(54, 56, 62))
		local face, width = streetFace(wall)
		face = face - Vector3.new(0, face.Position.Y - bottom, 0)
		-- tower straddling the street face
		local towerH = (top - bottom) + 60
		local tower = face * CFrame.new(0, 0, 8)
		part(model, "Tower", Vector3.new(30, towerH, 30), tower * CFrame.new(0, towerH / 2, 0), Enum.Material.Slate, rgb(170, 158, 142))
		part(model, "TowerRoof", Vector3.new(26, 22, 26), tower * CFrame.new(0, towerH + 11, 0), Enum.Material.Slate, rgb(64, 66, 74))
		for i = 0, 3 do
			local dir = tower * CFrame.Angles(0, i * math.pi / 2, 0)
			-- cylinder axis (local X) turned to face outward (-Z): a disc on the wall
			part(model, "ClockFace", Vector3.new(0.6, 12, 12), dir * CFrame.new(0, towerH - 10, -15.4) * CFrame.Angles(0, math.pi / 2, 0),
				Enum.Material.SmoothPlastic, rgb(246, 242, 226), Enum.PartType.Cylinder)
		end
		part(model, "Flagpole", Vector3.new(0.4, 16, 0.4), tower * CFrame.new(0, towerH + 30, 0), Enum.Material.Metal, rgb(200, 200, 200))
		sign(model, "WIDENER UNIVERSITY", face * CFrame.new(width * 0.3, 7, -16), 34, 4, rgb(18, 40, 92), rgb(255, 210, 60))
		model.Parent = root
		built.old_main = true
	end
end

------------------------------------------------------------------------------
-- Deshong Museum: white marble Greek-revival temple front
do
	local models = modelsOf(Landmarks.deshong_museum)
	local wall = largestWall(models)
	if wall then
		local model = Instance.new("Model")
		model.Name = "Deshong Museum"
		restyle(models, Enum.Material.Marble, rgb(232, 228, 216), false)
		local top, bottom = wallTopY(wall), wallBottomY(wall)
		local face, width = streetFace(wall)
		face = face - Vector3.new(0, face.Position.Y - bottom, 0)
		portico(model, face, width / 0.6, top - bottom - 3, 6, rgb(236, 232, 222))
		model.Parent = root
		built.deshong_museum = true
	end
end

------------------------------------------------------------------------------
-- restyled civic / institutional buildings with signs
local function restyledWithSign(key, label, material, color, signColor, textColor)
	local models = modelsOf(Landmarks[key])
	local wall = largestWall(models)
	if not wall then return end
	local model = Instance.new("Model")
	model.Name = Landmarks[key].name
	restyle(models, material, color, true)
	local face, width = streetFace(wall)
	local bottom = wallBottomY(wall)
	face = face - Vector3.new(0, face.Position.Y - bottom, 0)
	sign(model, label, face * CFrame.new(0, math.min(wallTopY(wall) - bottom - 4, 24), -0.5), math.min(width * 0.6, 70), 6, signColor, textColor)
	model.Parent = root
	built[key] = true
end
restyledWithSign("chester_high", "CHESTER HIGH SCHOOL", Enum.Material.Brick, rgb(156, 86, 66), rgb(110, 20, 30), rgb(250, 214, 80))
restyledWithSign("crozer_north", "CROZER HEALTH", Enum.Material.Concrete, rgb(214, 206, 192), rgb(0, 84, 150), WHITE)
restyledWithSign("crozer_building", "CROZER BUILDING", Enum.Material.Sandstone, rgb(150, 104, 76), rgb(70, 46, 34), rgb(240, 226, 196))
restyledWithSign("wolfgram_library", "WOLFGRAM LIBRARY", Enum.Material.Brick, rgb(150, 82, 64), rgb(18, 40, 92), rgb(255, 210, 60))
restyledWithSign("wharf", "THE WHARF AT RIVERTOWN", Enum.Material.Brick, rgb(140, 70, 50), rgb(40, 40, 44), WHITE)

------------------------------------------------------------------------------
-- stadium helpers
local function standsAlong(parent, frame, length, tiers, tierDepth, tierRise, baseHeight, color, accent)
	-- tiers rise away from the field (local -Z is toward the field)
	for i = 0, tiers - 1 do
		local h = baseHeight + (i + 1) * tierRise
		part(parent, "Stand", Vector3.new(length, h, tierDepth),
			frame * CFrame.new(0, h / 2, (i + 0.5) * tierDepth), Enum.Material.Concrete, (i % 4 == 3) and accent or color)
	end
end

local function fieldLines(parent, frame, L, W, y)
	local t = 0.7
	local function line(x, z, lx, lz)
		part(parent, "Line", Vector3.new(lx, 0.08, lz), frame * CFrame.new(x, y, z), nil, WHITE)
	end
	line(0, W / 2, L, t)
	line(0, -W / 2, L, t)
	line(L / 2, 0, t, W)
	line(-L / 2, 0, t, W)
	line(0, 0, t, W)
	return line
end

------------------------------------------------------------------------------
-- Subaru Park (Philadelphia Union): bowl, pitch, canopies, outer wall
do
	local lm = Landmarks.subaru_park
	local models = modelsOf(lm)
	local main = largestWall(models)
	if lm and main then
		local model = Instance.new("Model")
		model.Name = "Subaru Park"
		local axis = main.CFrame.Rotation
		if main.Size.Z > main.Size.X then axis = axis * CFrame.Angles(0, math.pi / 2, 0) end
		local cx, cz = main.Position.X, main.Position.Z
		local y = groundY(cx, cz) or wallBottomY(main)
		for _, m in ipairs(models) do m:Destroy() end
		local frame = CFrame.new(cx, y, cz) * axis
		local L, W = 330, 210
		-- level the bowl: clear terrain above pitch level (cuts are allowed)
		Workspace.Terrain:FillBlock(frame * CFrame.new(0, 40, 0), Vector3.new(L + 250, 80, W + 230), Enum.Material.Air)
		part(model, "Plaza", Vector3.new(L + 260, 1, W + 240), frame * CFrame.new(0, -0.3, 0), Enum.Material.Concrete, rgb(196, 192, 184))
		part(model, "Pitch", Vector3.new(L + 30, 0.6, W + 30), frame * CFrame.new(0, 0.3, 0), Enum.Material.Grass, rgb(70, 128, 58))
		for i = -5, 5, 2 do
			part(model, "Stripe", Vector3.new(L / 11, 0.05, W), frame * CFrame.new(i * L / 11, 0.62, 0), Enum.Material.Grass, rgb(82, 142, 66))
		end
		fieldLines(model, frame, L, W, 0.65)
		for i = 0, 15 do
			local a = i / 16 * math.pi * 2
			part(model, "Line", Vector3.new(0.7, 0.08, 2 * math.pi * 30 / 16 + 0.3), frame * CFrame.new(math.cos(a) * 30, 0.65, math.sin(a) * 30) * CFrame.Angles(0, -a, 0), nil, WHITE)
		end
		for side = -1, 1, 2 do
			local gx = side * (L / 2 + 1)
			part(model, "GoalPost", Vector3.new(0.6, 8, 0.6), frame * CFrame.new(gx, 4, 12), nil, WHITE)
			part(model, "GoalPost", Vector3.new(0.6, 8, 0.6), frame * CFrame.new(gx, 4, -12), nil, WHITE)
			part(model, "Crossbar", Vector3.new(0.6, 0.6, 24.6), frame * CFrame.new(gx, 8, 0), nil, WHITE)
		end
		local navy, gold = rgb(26, 40, 72), rgb(200, 162, 60)
		local setback = 18
		-- long sides (toward +/-Z) and ends (+/-X)
		standsAlong(model, frame * CFrame.new(0, 0, W / 2 + setback), L + 40, 8, 9, 5, 2, navy, gold)
		standsAlong(model, frame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, W / 2 + setback), L + 40, 8, 9, 5, 2, navy, gold)
		standsAlong(model, frame * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, 0, L / 2 + setback), W + 40, 7, 9, 5, 2, navy, gold)
		standsAlong(model, frame * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, L / 2 + setback), W + 40, 7, 9, 5, 2, navy, gold)
		-- outer wall: ellipse of panels
		local ra, rb = L / 2 + setback + 8 * 9 + 6, W / 2 + setback + 8 * 9 + 6
		local n = 40
		for i = 0, n - 1 do
			local a0, a1 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
			local p0 = Vector3.new(math.cos(a0) * ra, 0, math.sin(a0) * rb)
			local p1 = Vector3.new(math.cos(a1) * ra, 0, math.sin(a1) * rb)
			local mid = (p0 + p1) / 2
			local panel = part(model, "OuterWall", Vector3.new((p1 - p0).Magnitude + 1, 46, 3),
				frame * CFrame.lookAt(mid + Vector3.new(0, 23, 0), mid + Vector3.new(0, 23, 0) + Vector3.new(-(p1 - p0).Z, 0, (p1 - p0).X)) ,
				Enum.Material.Concrete, (i % 2 == 0) and rgb(214, 214, 210) or rgb(196, 198, 200))
			if i == math.floor(n * 0.25) then
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Back
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 10
				gui.Parent = panel
				local label = Instance.new("TextLabel")
				label.Size = UDim2.fromScale(1, 0.4)
				label.Position = UDim2.fromScale(0, 0.3)
				label.BackgroundColor3 = navy
				label.TextColor3 = WHITE
				label.TextScaled = true
				label.Font = Enum.Font.GothamBlack
				label.Text = "SUBARU PARK"
				label.Parent = gui
			end
		end
		-- white canopies over both long stands, on columns at the back
		for side = -1, 1, 2 do
			local back = W / 2 + setback + 8 * 9
			local canopy = frame * CFrame.new(0, 66, side * (back - 30))
			part(model, "Canopy", Vector3.new(L + 20, 1.2, 70), canopy * CFrame.Angles(side * math.rad(-6), 0, 0), Enum.Material.Fabric, rgb(244, 244, 240))
			for i = -3, 3 do
				part(model, "CanopyColumn", Vector3.new(2, 66, 2), frame * CFrame.new(i * (L + 20) / 7, 33, side * back), Enum.Material.Metal, rgb(220, 220, 222))
			end
		end
		-- scoreboard behind one goal
		sign(model, "PHILADELPHIA UNION", frame * CFrame.new(-(L / 2 + setback + 7 * 9 + 4), 52, 0) * CFrame.Angles(0, math.pi / 2, 0), 70, 22, rgb(20, 20, 24), rgb(200, 162, 60))
		model.Parent = root
		built.subaru_park = true
	end
end

------------------------------------------------------------------------------
-- Leslie C. Quick Jr. Stadium (Widener): football field, track, stands
do
	local lm = Landmarks.quick_stadium
	if lm then
		local model = Instance.new("Model")
		model.Name = "Leslie C. Quick Jr. Stadium"
		local b = lm.box
		local y = groundY(b[1], b[2])
		if y then
			for _, m in ipairs(modelsOf(lm)) do m:Destroy() end
			local frame = CFrame.new(b[1], y, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0)
			local L, W = 330, 160
			Workspace.Terrain:FillBlock(frame * CFrame.new(0, 40, 0), Vector3.new(L + 110, 80, W + 90), Enum.Material.Air)
			part(model, "Track", Vector3.new(L + 120, 0.6, W + 100), frame * CFrame.new(0, 0.3, 0), Enum.Material.SmoothPlastic, rgb(172, 70, 52))
			part(model, "Field", Vector3.new(L + 40, 0.7, W + 20), frame * CFrame.new(0, 0.35, 0), Enum.Material.Grass, rgb(64, 130, 60))
			local line = fieldLines(model, frame, L, W, 0.75)
			for i = -5, 5 do
				line(i * L / 12, 0, 0.5, W)
			end
			for side = -1, 1, 2 do
				local x = side * (L / 2 + 15)
				part(model, "Upright", Vector3.new(0.5, 20, 0.5), frame * CFrame.new(x, 14, 9), Enum.Material.Metal, rgb(250, 210, 40))
				part(model, "Upright", Vector3.new(0.5, 20, 0.5), frame * CFrame.new(x, 14, -9), Enum.Material.Metal, rgb(250, 210, 40))
				part(model, "Crossbar", Vector3.new(0.5, 0.5, 18.5), frame * CFrame.new(x, 10, 0), Enum.Material.Metal, rgb(250, 210, 40))
				part(model, "Post", Vector3.new(0.6, 10, 0.6), frame * CFrame.new(x, 5, 0), Enum.Material.Metal, rgb(250, 210, 40))
			end
			standsAlong(model, frame * CFrame.new(0, 0, W / 2 + 54), L, 6, 8, 4, 2, rgb(150, 150, 154), rgb(18, 40, 92))
			standsAlong(model, frame * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, 0, W / 2 + 54), L * 0.7, 4, 8, 4, 2, rgb(150, 150, 154), rgb(18, 40, 92))
			sign(model, "WIDENER PRIDE", frame * CFrame.new(0, 40, W / 2 + 54 + 6 * 8 + 2), 60, 10, rgb(18, 40, 92), rgb(255, 210, 60))
			model.Parent = root
			built.quick_stadium = true
		end
	end
end

------------------------------------------------------------------------------
-- Harrah's Philadelphia: dark casino with neon band and sign; harness track
do
	local lm = Landmarks.harrahs
	local models = modelsOf(lm)
	local wall = largestWall(models)
	if wall then
		local model = Instance.new("Model")
		model.Name = "Harrah's Philadelphia"
		-- keep the window textures: a plain dark slab reads as a void, not a casino
		restyle(models, Enum.Material.SmoothPlastic, rgb(58, 60, 70), true)
		local top = wallTopY(wall)
		for _, m in ipairs(models) do
			for _, p in ipairs(wallParts(m)) do
				local t = p.Position.Y + p.Size.Y / 2
				part(model, "NeonBand", Vector3.new(p.Size.X + 0.6, 2, p.Size.Z + 0.6), p.CFrame.Rotation + Vector3.new(p.Position.X, t - 4, p.Position.Z), Enum.Material.Neon, rgb(255, 170, 40))
			end
		end
		local face, width = streetFace(wall)
		sign(model, "HARRAH'S", face * CFrame.new(0, (top - face.Position.Y) + 14, -1) - Vector3.new(0, 0, 0), math.min(width * 0.45, 140), 28, rgb(160, 14, 26), rgb(255, 230, 160))
		model.Parent = root
		built.harrahs = true
	end
	-- half-mile harness track, measured off the orthophoto (lm_harrahs): end
	-- centres (10514, 870) and (10982, 376), turn radius ~247, width ~60
	local track = Instance.new("Model")
	track.Name = "Harrah's Racetrack"
	local c1, c2 = Vector3.new(10514, 0, 870), Vector3.new(10982, 0, 376)
	local centre = (c1 + c2) / 2
	local axis = (c2 - c1).Unit
	local normal = Vector3.new(-axis.Z, 0, axis.X)
	local half = (c2 - c1).Magnitude / 2
	local radius, width = 247, 60
	local function trackPoint(t)
		-- t in [0, 1): straight, turn, straight, turn
		local straight = 2 * half
		local turn = math.pi * radius
		local total = 2 * straight + 2 * turn
		local s = t * total
		if s < straight then
			return centre - axis * half + axis * s + normal * radius
		end
		s -= straight
		if s < turn then
			local a = s / radius
			return centre + axis * half + (normal * math.cos(a) + axis * math.sin(a)) * radius
		end
		s -= turn
		if s < straight then
			return centre + axis * half - axis * s - normal * radius
		end
		s -= straight
		local a = s / radius
		return centre - axis * half + (-normal * math.cos(a) - axis * math.sin(a)) * radius
	end
	local n = 90
	for i = 0, n - 1 do
		local p0, p1 = trackPoint(i / n), trackPoint((i + 1) / n)
		local g0, g1 = groundY(p0.X, p0.Z), groundY(p1.X, p1.Z)
		if g0 and g1 then
			local a, b = Vector3.new(p0.X, g0 + 0.4, p0.Z), Vector3.new(p1.X, g1 + 0.4, p1.Z)
			part(track, "Track", Vector3.new(width, 0.8, (b - a).Magnitude + 2), CFrame.lookAt((a + b) / 2, b), Enum.Material.Ground, rgb(150, 116, 84))
			local inward = (centre - (a + b) / 2)
			inward = Vector3.new(inward.X, 0, inward.Z).Unit
			part(track, "Rail", Vector3.new(0.6, 3, (b - a).Magnitude + 0.5), CFrame.lookAt((a + b) / 2 + Vector3.new(0, 1.5, 0), b + Vector3.new(0, 1.5, 0)) + inward * (width / 2 - 1), Enum.Material.SmoothPlastic, WHITE)
		end
	end
	-- grandstand on the casino side straight (toward the casino at -normal)
	local gy = groundY(centre.X - normal.X * (radius + 70), centre.Z - normal.Z * (radius + 70))
	if gy then
		local frame = CFrame.lookAt(Vector3.new(centre.X, gy, centre.Z) - normal * (radius + width / 2 + 8), Vector3.new(centre.X, gy, centre.Z))
		-- frame looks at the track (local -Z), so tiers rise away from it (+Z)
		standsAlong(track, frame, 2 * half * 0.9, 6, 8, 4, 1, rgb(200, 196, 188), rgb(160, 14, 26))
		part(track, "GrandstandRoof", Vector3.new(2 * half * 0.9, 1, 56), frame * CFrame.new(0, 34, 26), Enum.Material.Metal, rgb(160, 14, 26))
	end
	track.Parent = root
	built.racetrack = true
end

------------------------------------------------------------------------------
-- Commodore Barry Bridge. Modelled on the Google Street View captures from the
-- deck (tools/storefronts/google_barry.py, 2026-04/08) and the DVRPC 2025
-- aerial (crossing_aerial.py barry_7): a pale silver-grey cantilever through
-- truss - two ~251 m anchor spans and the 501 m main span on two river piers,
-- the top chord peaking over the main piers and dropping to a shallow
-- suspended span mid-channel - every panel point with a transverse strut,
-- a lower sway strut and X bracing over the roadway; concrete deck with
-- rust-red edge barriers under a railing, a movable median barrier and light
-- poles; steel girder approach spans on twin-column concrete bents.
-- Horizontal studs are Mercator (3.906 per real metre), vertical 3 per metre.
do
	local lm = Landmarks.barry_bridge
	if lm then
		local model = Instance.new("Model")
		model.Name = "Commodore Barry Bridge"
		local b = lm.box
		local yawAxis = CFrame.Angles(0, math.rad(b[5]), 0).RightVector
		local centre = Vector3.new(b[1], 0, b[2])
		local e1, e2 = centre - yawAxis * b[3] / 2, centre + yawAxis * b[3] / 2
		-- Chester end = the end nearer the city (smaller z here)
		local startP, endP = e1, e2
		if e2.Z < e1.Z then startP, endP = e2, e1 end
		local dir = (endP - startP).Unit
		-- The deck continues the approach viaduct (HighwayProfile design line
		-- BARRY_PA_APPROACH): start at the far ends of the approach's two
		-- carriageways, at their height, so the roadway runs straight on.
		local startY = 40
		do
			local tips = {}
			for _, r in ipairs(Workspace:GetPartBoundsInRadius(Vector3.new(startP.X, 60, startP.Z), 320, roadParams)) do
				if r:GetAttribute("ChesterStreet") == "Commodore John Barry" then
					local half = r.CFrame.LookVector * r.Size.Z / 2
					for _, p in ipairs({ r.Position - half, r.Position + half }) do
						table.insert(tips, { p = p, along = (p - startP):Dot(dir), top = p.Y + r.Size.Y / 2 })
					end
				end
			end
			table.sort(tips, function(a, c) return a.along > c.along end)
			if #tips > 0 then
				local first = tips[1]
				local second
				for _, t in ipairs(tips) do
					if (Vector3.new(t.p.X - first.p.X, 0, t.p.Z - first.p.Z)).Magnitude > 15 then
						second = t
						break
					end
				end
				local a = second and (first.p + second.p) / 2 or first.p
				startP = Vector3.new(a.X, 0, a.Z)
				startY = second and math.max(first.top, second.top) or first.top
				dir = (endP - startP).Unit
			end
		end
		local length = (endP - startP).Magnitude
		local right = Vector3.new(-dir.Z, 0, dir.X)

		-- layout along the deck (studs from the end of the Chester approach)
		local M = 3.906                       -- horizontal studs per metre
		local TRUSS0 = 470                    -- PA end of the truss (Street View: portal ~450-500)
		local PIER1 = TRUSS0 + 251 * M        -- PA main pier (rock-armoured pier mid-river on the aerial)
		local PIER2 = PIER1 + 501 * M         -- NJ main pier
		local TRUSS1 = PIER2 + 251 * M        -- NJ end of the truss
		local MID = (PIER1 + PIER2) / 2
		local SUSP = 90 * M                   -- half the suspended span
		-- deck: 4.5 % real grade (0.0346 stud/stud) both ways, 900-stud vertical
		-- curve over the channel (~55 m above the water at mid-span)
		local GRADE, CURVE = 0.0346, 900
		local PEAK = startY + GRADE * MID
		local function deckY(s)
			local d = math.abs(s - MID)
			if d < CURVE then
				return PEAK - GRADE * (CURVE * CURVE + d * d) / (2 * CURVE)
			end
			return PEAK - GRADE * d
		end
		-- truss height above the bottom chord
		local KNOTS = {
			{ TRUSS0, 48 }, { PIER1, 128 }, { MID - SUSP, 52 }, { MID, 62 },
			{ MID + SUSP, 52 }, { PIER2, 128 }, { TRUSS1, 48 },
		}
		local function trussH(s)
			for k = 1, #KNOTS - 1 do
				local a, c = KNOTS[k], KNOTS[k + 1]
				if s <= c[1] then
					return a[2] + (c[2] - a[2]) * math.clamp((s - a[1]) / (c[1] - a[1]), 0, 1)
				end
			end
			return KNOTS[#KNOTS][2]
		end

		local deckWidth = math.clamp(b[4], 70, 84)
		local hw = deckWidth / 2 + 2.5         -- truss planes just outside the deck
		local STEEL = rgb(196, 202, 204)
		local CONC = rgb(168, 166, 160)
		local BARRIER = rgb(146, 82, 62)       -- rust-red edge barriers
		local MEDIAN = rgb(212, 196, 150)
		local function at(s, off, y)
			return startP + dir * s + right * off + Vector3.new(0, y, 0)
		end
		local function slab(name, s0, s1, off, y0, y1, w, h, material, color)
			local a, c = at(s0, off, y0), at(s1, off, y1)
			return part(model, name, Vector3.new(w, h, (c - a).Magnitude + 0.4),
				CFrame.lookAt((a + c) / 2, c), material, color)
		end

		-- deck, barriers, railing, median, lane lines, lights
		local DECK_STEP = 40
		local s = 0
		local seg = 0
		while s < length do
			local s1 = math.min(s + DECK_STEP, length)
			local y0, y1 = deckY(s), deckY(s1)
			slab("Deck", s, s1, 0, y0 - 1.8, y1 - 1.8, deckWidth + 6, 3, Enum.Material.Concrete, CONC)
			local road = slab("Roadway", s, s1, 0, y0 - 0.15, y1 - 0.15, deckWidth - 4, 0.3, Enum.Material.Concrete,
				rgb(150, 148, 142))
			road:SetAttribute("ChesterStreet", "Commodore Barry Bridge")
			for side = -1, 1, 2 do
				slab("EdgeBarrier", s, s1, side * (deckWidth / 2 - 1), y0 + 1.6, y1 + 1.6, 2, 3.4,
					Enum.Material.Concrete, BARRIER)
				slab("Railing", s, s1, side * (deckWidth / 2 - 1), y0 + 4.2, y1 + 4.2, 0.4, 0.4, Enum.Material.Metal, STEEL)
			end
			slab("MedianBarrier", s, s1, deckWidth / 10, y0 + 1.2, y1 + 1.2, 1.4, 2.6, Enum.Material.Concrete, MEDIAN)
			-- dashed lane lines (5 lanes)
			for lane = 1, 4 do
				local off = -deckWidth / 2 + 2 + lane * (deckWidth - 4) / 5
				if lane ~= 3 then
					slab("LaneDash", s, s + math.min(14, s1 - s), off, y0 + 0.02, y0 + 0.02, 0.6, 0.06,
						Enum.Material.SmoothPlastic, WHITE)
				end
			end
			if seg % 3 == 0 then
				for side = -1, 1, 2 do
					local base = at(s, side * (deckWidth / 2 - 1), y0 + 3.2)
					local top = base + Vector3.new(0, 16, 0)
					part(model, "LightPole", Vector3.new(0.6, 16, 0.6), CFrame.new((base + top) / 2), Enum.Material.Metal, STEEL)
					local arm = top - right * side * 5
					beam(model, "LightArm", top, arm, 0.5, Enum.Material.Metal, STEEL)
					local lamp = part(model, "Lamp", Vector3.new(2.4, 0.6, 1.2), CFrame.new(arm - Vector3.new(0, 0.3, 0)),
						Enum.Material.Neon, rgb(255, 236, 196))
					local light = Instance.new("PointLight")
					light.Range = 36
					light.Brightness = 1.2
					light.Color = rgb(255, 230, 190)
					light.Parent = lamp
				end
			end
			seg += 1
			s = s1
		end

		-- through truss
		local panels = math.max(1, math.floor((TRUSS1 - TRUSS0) / 60 + 0.5))
		local panel = (TRUSS1 - TRUSS0) / panels
		local function node(i, side, top)
			local sAt = TRUSS0 + i * panel
			local y = deckY(sAt) - 2.5
			if top then y += trussH(sAt) end
			return at(sAt, side * hw, y)
		end
		for i = 0, panels do
			for side = -1, 1, 2 do
				local b0, t0 = node(i, side, false), node(i, side, true)
				if i < panels then
					local b1, t1 = node(i + 1, side, false), node(i + 1, side, true)
					beam(model, "BottomChord", b0, b1, 3.4, Enum.Material.Metal, STEEL)
					if i == 0 then
						beam(model, "EndPost", b0, t1, 3.6, Enum.Material.Metal, STEEL)
					elseif i == panels - 1 then
						beam(model, "EndPost", t0, b1, 3.6, Enum.Material.Metal, STEEL)
					else
						beam(model, "TopChord", t0, t1, 3.4, Enum.Material.Metal, STEEL)
						-- Warren diagonals alternating, with a K sub-strut to the panel's mid bottom
						local fromTop = i % 2 == 0
						local d0, d1 = fromTop and t0 or b0, fromTop and b1 or t1
						beam(model, "Diagonal", d0, d1, 2.4, Enum.Material.Metal, STEEL)
						beam(model, "SubStrut", (d0 + d1) / 2, (b0 + b1) / 2, 1.4, Enum.Material.Metal, STEEL)
					end
				end
				if i > 0 and i < panels then
					beam(model, "Vertical", b0, t0, 2.2, Enum.Material.Metal, STEEL)
				end
			end
			-- bracing over the roadway: top strut, lower sway strut, X between them,
			-- top lateral X to the next panel point
			if i > 0 and i < panels then
				local tl, tr = node(i, -1, true), node(i, 1, true)
				local drop = Vector3.new(0, -trussH(TRUSS0 + i * panel) * 0.22, 0)
				local ll, lr = tl + drop, tr + drop
				beam(model, "TopStrut", tl, tr, 2.0, Enum.Material.Metal, STEEL)
				beam(model, "SwayStrut", ll, lr, 1.6, Enum.Material.Metal, STEEL)
				beam(model, "SwayBrace", tl, lr, 1.2, Enum.Material.Metal, STEEL)
				beam(model, "SwayBrace", tr, ll, 1.2, Enum.Material.Metal, STEEL)
				if i < panels - 1 then
					local nl, nr = node(i + 1, -1, true), node(i + 1, 1, true)
					beam(model, "TopLateral", tl, nr, 1.0, Enum.Material.Metal, STEEL)
					beam(model, "TopLateral", tr, nl, 1.0, Enum.Material.Metal, STEEL)
				end
			end
		end

		-- piers: main river piers, anchor piers, twin-column bents under the
		-- girder approach spans
		local function riverBed(p)
			return math.min(groundY(p.X, p.Z) or -40, -40)
		end
		local function pierAt(sAt, big)
			local c = at(sAt, 0, 0)
			local top = deckY(sAt) - (big and 4 or 6)
			local bed = riverBed(c)
			local look = CFrame.lookAt(c, c + dir).Rotation
			local colW = big and 18 or 9
			local footTop = math.min(big and 12 or 4, top - 10)
			if big then
				part(model, "PierFooting", Vector3.new(deckWidth + 34, footTop - bed, 46),
					CFrame.new(c.X, (footTop + bed) / 2, c.Z) * look, Enum.Material.Concrete, CONC)
			end
			for side = -1, 1, 2 do
				local x = at(sAt, side * (big and hw or deckWidth / 2 - 6), 0)
				local bottom = big and footTop or bed
				part(model, "PierColumn", Vector3.new(colW, top - bottom, colW),
					CFrame.new(x.X, (top + bottom) / 2, x.Z) * look, Enum.Material.Concrete, CONC)
			end
			part(model, "PierCap", Vector3.new(deckWidth + (big and 22 or 10), big and 8 or 5, colW + 2),
				CFrame.new(c.X, top - (big and 4 or 2.5), c.Z) * look, Enum.Material.Concrete, CONC)
			if big then
				part(model, "PierStrut", Vector3.new(deckWidth, 6, colW - 2),
					CFrame.new(c.X, (top + footTop) / 2, c.Z) * look, Enum.Material.Concrete, CONC)
			end
		end
		pierAt(PIER1, true)
		pierAt(PIER2, true)
		pierAt(TRUSS0, false)
		pierAt(TRUSS1, false)
		local BENT = 160
		for sAt = BENT, length, BENT do
			if sAt < TRUSS0 - 40 or sAt > TRUSS1 + 40 then
				pierAt(sAt, false)
			end
		end
		-- steel plate girders under the approach spans
		for _, range in ipairs({ { 0, TRUSS0 }, { TRUSS1, length } }) do
			local g = range[1]
			while g < range[2] do
				local g1 = math.min(g + 80, range[2])
				for _, off in ipairs({ -deckWidth / 2 + 6, 0, deckWidth / 2 - 6 }) do
					slab("Girder", g, g1, off, deckY(g) - 7, deckY(g1) - 7, 1.6, 8, Enum.Material.Metal, STEEL)
				end
				g = g1
			end
		end

		-- County footprints traced from the bridge itself (the landmark's ids,
		-- and building 41244: a 48 m "warehouse" at the deck height straddling
		-- the Riverfront abutment) and anything else poking up through the
		-- deck: cleared. Buildings below the deck stay.
		do
			local listed = {}
			for _, id in ipairs(lm.buildings or {}) do listed[id] = true end
			local cleared = 0
			for id, bm in pairs(buildingsById) do
				if bm.Parent then
					local cf, size
					if bm:IsA("Model") then
						cf, size = bm:GetBoundingBox()
					else
						cf, size = bm.CFrame, bm.Size
					end
					local rel = Vector3.new(cf.X - startP.X, 0, cf.Z - startP.Z)
					local along = rel:Dot(dir)
					local across = math.abs(rel:Dot(right))
					local reach = math.max(size.X, size.Z) / 2
					local topY = cf.Y + size.Y / 2
					if listed[id] or (along > -reach and along < length + reach
						and across < deckWidth / 2 + reach and topY > deckY(math.clamp(along, 0, length)) - 6) then
						bm:Destroy()
						cleared += 1
					end
				end
			end
			model:SetAttribute("ClearedBuildings", cleared)
		end
		-- the far end leaves the world: close it off
		local last = at(length, 0, deckY(length))
		part(model, "EndBarrier", Vector3.new(deckWidth, 4, 2), CFrame.lookAt(last + Vector3.new(0, 2, 0), last + Vector3.new(0, 2, 0) + dir),
			Enum.Material.Concrete, rgb(220, 200, 60))
		model.Parent = root
		built.barry_bridge = true
		model:SetAttribute("StartDeckY", startY)
		model:SetAttribute("PeakDeckY", deckY(MID))
	end
end

local keys = {}
for k in pairs(built) do table.insert(keys, k) end
table.sort(keys)
print(("[ChesterWorld Landmarks] built %d: %s parts=%d"):format(#keys, table.concat(keys, " "), partCount))
Workspace:SetAttribute("CW_LandmarksComplete", true)
