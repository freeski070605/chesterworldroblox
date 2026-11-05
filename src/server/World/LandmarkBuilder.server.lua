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
-- Commodore Barry Bridge: deck across the Delaware with the cantilever
-- through-truss over the main span; deck truss + piers elsewhere.
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
		local length = (endP - startP).Magnitude
		-- deck starts at the existing approach road's height
		local startY = 40
		local nearest
		for _, r in ipairs(Workspace:GetPartBoundsInRadius(Vector3.new(startP.X, 60, startP.Z), 260, roadParams)) do
			local name = tostring(r:GetAttribute("ChesterStreet"))
			if string.find(name, "Barry", 1, true) then
				local d = (Vector3.new(r.Position.X - startP.X, 0, r.Position.Z - startP.Z)).Magnitude
				if not nearest or d < nearest then nearest, startY = d, r.Position.Y + r.Size.Y / 2 end
			end
		end
		local TOP, GRADE = 180, 0.045
		local function deckY(s)
			return math.min(startY + GRADE * s, TOP, startY + GRADE * (length - s))
		end
		local mid = length / 2
		local trussFrom, trussTo = mid - 1500, mid + 1500
		local function trussHeight(s)
			-- tall over the two main piers (mid -/+ 750), lower at mid span and ends
			local d = math.abs(math.abs(s - mid) - 750)
			return math.max(40, 110 - d * 0.075)
		end
		local deckWidth = math.min(b[4], 90)
		local panel = 50
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local steel = rgb(104, 114, 122)
		local prevTop = {}
		local s = 0
		while s < length do
			local s1 = math.min(s + panel, length)
			local a = startP + dir * s + Vector3.new(0, deckY(s), 0)
			local c = startP + dir * s1 + Vector3.new(0, deckY(s1), 0)
			part(model, "Deck", Vector3.new(deckWidth, 3, (c - a).Magnitude + 0.5), CFrame.lookAt((a + c) / 2, c), Enum.Material.Concrete, rgb(150, 150, 146))
			part(model, "Roadway", Vector3.new(deckWidth - 6, 0.3, (c - a).Magnitude + 0.5), CFrame.lookAt((a + c) / 2 + Vector3.new(0, 1.6, 0), c + Vector3.new(0, 1.6, 0)), Enum.Material.Asphalt, rgb(62, 62, 64))
			part(model, "CentreLine", Vector3.new(1, 0.1, (c - a).Magnitude), CFrame.lookAt((a + c) / 2 + Vector3.new(0, 1.8, 0), c + Vector3.new(0, 1.8, 0)), nil, rgb(240, 200, 40))
			local inTruss = s >= trussFrom and s1 <= trussTo
			for side = -1, 1, 2 do
				local off = right * side * (deckWidth / 2)
				if inTruss then
					local h0, h1 = trussHeight(s), trussHeight(s1)
					local bottom0, bottom1 = a + off, c + off
					local top0, top1 = bottom0 + Vector3.new(0, h0, 0), bottom1 + Vector3.new(0, h1, 0)
					beam(model, "Vertical", bottom0, top0, 2.2, Enum.Material.Metal, steel)
					beam(model, "TopChord", top0, top1, 2.6, Enum.Material.Metal, steel)
					beam(model, "BottomChord", bottom0, bottom1, 2.6, Enum.Material.Metal, steel)
					beam(model, "Diagonal", (math.floor(s / panel) % 2 == 0) and bottom0 or top0, (math.floor(s / panel) % 2 == 0) and top1 or bottom1, 1.8, Enum.Material.Metal, steel)
					prevTop[side] = top0
				else
					part(model, "Parapet", Vector3.new(1.2, 3.5, (c - a).Magnitude + 0.5), CFrame.lookAt((a + c) / 2 + off + Vector3.new(0, 3, 0), c + off + Vector3.new(0, 3, 0)), Enum.Material.Concrete, rgb(170, 170, 166))
					part(model, "Girder", Vector3.new(2, 10, (c - a).Magnitude + 0.5), CFrame.lookAt((a + c) / 2 + off - Vector3.new(0, 6, 0), c + off - Vector3.new(0, 6, 0)), Enum.Material.Metal, steel)
				end
			end
			if inTruss and math.floor(s / panel) % 2 == 0 then
				local h = trussHeight(s)
				beam(model, "TopBracing", a - right * deckWidth / 2 + Vector3.new(0, h, 0), a + right * deckWidth / 2 + Vector3.new(0, h, 0), 1.6, Enum.Material.Metal, steel)
			end
			-- piers: every 300 studs outside the main span, two big main piers
			local isMain = math.abs(s - (mid - 750)) < panel / 2 or math.abs(s - (mid + 750)) < panel / 2
			if isMain or (not inTruss and math.floor(s / panel) % 6 == 0) then
				local ground = groundY(a.X, a.Z) or -40
				local pierTop = a.Y - 3
				local pierBottom = math.min(ground, -40)
				local w = isMain and 34 or 14
				part(model, "Pier", Vector3.new(deckWidth + 8, pierTop - pierBottom, w), CFrame.lookAt(Vector3.new(a.X, (pierTop + pierBottom) / 2, a.Z), Vector3.new(c.X, (pierTop + pierBottom) / 2, c.Z)),
					Enum.Material.Concrete, rgb(160, 158, 150))
			end
			s = s1
		end
		-- the far end leaves the world: close it off
		local last = startP + dir * length + Vector3.new(0, deckY(length), 0)
		part(model, "EndBarrier", Vector3.new(deckWidth, 4, 2), CFrame.lookAt(last + Vector3.new(0, 3.5, 0), last + Vector3.new(0, 3.5, 0) + dir), Enum.Material.Concrete, rgb(220, 200, 60))
		model.Parent = root
		built.barry_bridge = true
		model:SetAttribute("StartDeckY", startY)
	end
end

local keys = {}
for k in pairs(built) do table.insert(keys, k) end
table.sort(keys)
print(("[ChesterWorld Landmarks] built %d: %s parts=%d"):format(#keys, table.concat(keys, " "), partCount))
Workspace:SetAttribute("CW_LandmarksComplete", true)
