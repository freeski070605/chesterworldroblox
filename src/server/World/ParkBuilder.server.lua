-- ChesterWorld parks: name signs, walking loops, benches and lamps for each park,
-- and the mapped sports/leisure features (courts, fields, tracks, playgrounds,
-- pools, cemeteries). Data: src/shared/WorldData/Parks.lua (tools/build_parks.py),
-- already in studs. Runs once the tiles are built.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Parks = require(Shared:WaitForChild("WorldData"):WaitForChild("Parks"))

while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do task.wait(0.5) end

local root = Instance.new("Folder")
root.Name = "ChesterParks"
root.Parent = Workspace

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
local WHITE, POST, WOOD, CONCRETE = rgb(236, 236, 230), rgb(70, 72, 74), rgb(110, 78, 52), rgb(170, 166, 156)

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
	return p
end

local parts = 0
local function counted(p)
	parts += 1
	if parts % 200 == 0 then task.wait() end
	return p
end

-- Feature frame: origin at the rectangle centre, +X along its length, at the
-- highest ground under the rectangle so nothing is buried on a slope.
local function frameOf(box)
	local rotation = CFrame.Angles(0, math.rad(box[5]), 0)
	local top
	for _, c in ipairs({ { 0, 0 }, { 0.5, 0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { -0.5, -0.5 } }) do
		local p = CFrame.new(box[1], 0, box[2]) * rotation * Vector3.new(c[1] * box[3], 0, c[2] * box[4])
		local y = groundY(p.X, p.Z)
		if y and (not top or y > top) then top = y end
	end
	if not top then return nil end
	return CFrame.new(box[1], top, box[2]) * rotation
end

-- surfaces carry a skirt down to the ground on sloping sites
local SKIRT = 6
local function slab(parent, name, frame, lx, lz, length, width, thick, material, color, lift)
	local skirt = (lift or 0) == 0 and SKIRT or 0
	return counted(part(parent, name, Vector3.new(length, thick + skirt, width),
		frame * CFrame.new(lx, (lift or 0) + (thick - skirt) / 2, lz), material, color))
end

-- painted lines: rectangle border plus extra cross lines (local x positions)
local function lines(parent, frame, length, width, lift, crossXs)
	local t = 0.6
	slab(parent, "Line", frame, 0, width / 2 - t / 2, length, t, 0.05, nil, WHITE, lift)
	slab(parent, "Line", frame, 0, -width / 2 + t / 2, length, t, 0.05, nil, WHITE, lift)
	slab(parent, "Line", frame, length / 2 - t / 2, 0, t, width, 0.05, nil, WHITE, lift)
	slab(parent, "Line", frame, -length / 2 + t / 2, 0, t, width, 0.05, nil, WHITE, lift)
	for _, x in ipairs(crossXs or {}) do
		slab(parent, "Line", frame, x, 0, t, width, 0.05, nil, WHITE, lift)
	end
end

local function circleLine(parent, frame, radius, lift)
	local n = 16
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local seg = 2 * math.pi * radius / n + 0.2
		counted(part(parent, "Line", Vector3.new(seg, 0.05, 0.6),
			frame * CFrame.new(math.cos(a) * radius, lift + 0.025, math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0),
			nil, WHITE))
	end
end

local function hoop(parent, frame, x, facing)
	counted(part(parent, "HoopPole", Vector3.new(0.6, 12, 0.6), frame * CFrame.new(x, 6, 0), Enum.Material.Metal, POST))
	counted(part(parent, "Backboard", Vector3.new(0.3, 3.6, 6), frame * CFrame.new(x - facing * 1.2, 11.5, 0), nil, WHITE))
	counted(part(parent, "Rim", Vector3.new(1.6, 0.2, 1.6), frame * CFrame.new(x - facing * 2.4, 10.2, 0), Enum.Material.Metal, rgb(214, 96, 32)))
end

local function net(parent, frame, width, height, lift)
	counted(part(parent, "NetPost", Vector3.new(0.4, height, 0.4), frame * CFrame.new(0, lift + height / 2, width / 2), Enum.Material.Metal, POST))
	counted(part(parent, "NetPost", Vector3.new(0.4, height, 0.4), frame * CFrame.new(0, lift + height / 2, -width / 2), Enum.Material.Metal, POST))
	local n = counted(part(parent, "Net", Vector3.new(0.15, height * 0.45, width), frame * CFrame.new(0, lift + height * 0.75, 0), Enum.Material.Fabric, rgb(30, 30, 32)))
	n.Transparency = 0.35
end

local function goal(parent, frame, x, width)
	local h = 8
	counted(part(parent, "GoalPost", Vector3.new(0.5, h, 0.5), frame * CFrame.new(x, h / 2, width / 2), nil, WHITE))
	counted(part(parent, "GoalPost", Vector3.new(0.5, h, 0.5), frame * CFrame.new(x, h / 2, -width / 2), nil, WHITE))
	counted(part(parent, "Crossbar", Vector3.new(0.5, 0.5, width), frame * CFrame.new(x, h, 0), nil, WHITE))
end

local BUILDERS = {}

BUILDERS.basketball = function(model, frame, L, W)
	slab(model, "Court", frame, 0, 0, L, W, 0.3, Enum.Material.Asphalt, rgb(58, 60, 62))
	lines(model, frame, L - 2, W - 2, 0.3, { 0 })
	circleLine(model, frame, math.min(W * 0.12, 6), 0.3)
	hoop(model, frame, L / 2 - 1, 1)
	hoop(model, frame, -L / 2 + 1, -1)
end

BUILDERS.tennis = function(model, frame, L, W)
	slab(model, "Court", frame, 0, 0, L, W, 0.3, Enum.Material.SmoothPlastic, rgb(64, 112, 86))
	slab(model, "Court", frame, 0, 0, L - 12, W - 10, 0.05, Enum.Material.SmoothPlastic, rgb(54, 92, 140), 0.3)
	lines(model, frame, L - 12, W - 10, 0.35, { (L - 12) * 0.27, -(L - 12) * 0.27 })
	net(model, frame, W - 8, 3.5, 0.35)
end

BUILDERS.volleyball = function(model, frame, L, W)
	slab(model, "Court", frame, 0, 0, L, W, 0.3, Enum.Material.Sand, rgb(214, 196, 150))
	lines(model, frame, L - 4, W - 4, 0.3)
	net(model, frame, W - 2, 8, 0.3)
end
BUILDERS.beachvolleyball = BUILDERS.volleyball

local PITCH = rgb(86, 124, 58)

BUILDERS.baseball = function(model, frame, L, W)
	-- levelled outfield with the infield diamond toward one end
	slab(model, "Outfield", frame, 0, 0, L, W, 0.3, Enum.Material.Grass, PITCH)
	local side = math.clamp(math.min(L, W) * 0.38, 24, 82)
	local home = -L / 2 + side * 0.35
	local centre = home + side / math.sqrt(2)
	counted(part(model, "Infield", Vector3.new(side, 0.1, side),
		frame * CFrame.new(centre, 0.35, 0) * CFrame.Angles(0, math.rad(45), 0), Enum.Material.Ground, rgb(150, 108, 72)))
	local d = side / math.sqrt(2)
	for _, base in ipairs({ { home, 0 }, { home + d, d }, { home + 2 * d, 0 }, { home + d, -d } }) do
		counted(part(model, "Base", Vector3.new(2, 0.2, 2), frame * CFrame.new(base[1], 0.5, base[2]) * CFrame.Angles(0, math.rad(45), 0), nil, WHITE))
	end
	counted(part(model, "Mound", Vector3.new(0.5, 6, 6), frame * CFrame.new(home + d, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.Material.Ground, rgb(150, 108, 72), Enum.PartType.Cylinder))
	-- backstop behind home plate
	for i = -2, 2 do
		counted(part(model, "BackstopPost", Vector3.new(0.4, 14, 0.4), frame * CFrame.new(home - 10, 7, i * 6), Enum.Material.Metal, POST))
	end
	local fence = counted(part(model, "Backstop", Vector3.new(0.2, 13, 24), frame * CFrame.new(home - 10, 7, 0), Enum.Material.DiamondPlate, rgb(150, 150, 150)))
	fence.Transparency = 0.55
end

local function field(model, frame, L, W)
	-- a levelled grass pitch carries the lines
	slab(model, "Pitch", frame, 0, 0, L, W, 0.3, Enum.Material.Grass, PITCH)
	lines(model, frame, L - 4, W - 4, 0.32, { 0 })
	circleLine(model, frame, math.min(W * 0.14, 27), 0.32)
	local goalWidth = math.clamp(W * 0.12, 8, 22)
	goal(model, frame, L / 2 - 2, goalWidth)
	goal(model, frame, -L / 2 + 2, goalWidth)
end
BUILDERS.soccer = field
BUILDERS.american_football = field
BUILDERS.pitch = field

BUILDERS.athletics = function(model, frame, L, W)
	local lane = math.clamp(W * 0.1, 12, 30)
	local red = rgb(170, 72, 52)
	slab(model, "Track", frame, 0, W / 2 - lane / 2, L, lane, 0.3, Enum.Material.SmoothPlastic, red)
	slab(model, "Track", frame, 0, -W / 2 + lane / 2, L, lane, 0.3, Enum.Material.SmoothPlastic, red)
	slab(model, "Track", frame, L / 2 - lane / 2, 0, lane, W - 2 * lane, 0.3, Enum.Material.SmoothPlastic, red)
	slab(model, "Track", frame, -L / 2 + lane / 2, 0, lane, W - 2 * lane, 0.3, Enum.Material.SmoothPlastic, red)
	field(model, frame, L - 2 * lane - 8, W - 2 * lane - 8)
end

BUILDERS.playground = function(model, frame, L, W)
	slab(model, "Surface", frame, 0, 0, L, W, 0.3, Enum.Material.Fabric, rgb(150, 82, 52))
	local s = math.min(L, W)
	-- slide tower
	local tx = -L / 4
	for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
		counted(part(model, "Post", Vector3.new(0.5, 8, 0.5), frame * CFrame.new(tx + c[1], 4, c[2]), Enum.Material.Metal, rgb(40, 90, 160)))
	end
	counted(part(model, "Deck", Vector3.new(5, 0.4, 5), frame * CFrame.new(tx, 5, 0), nil, rgb(220, 180, 40)))
	counted(part(model, "Roof", Vector3.new(5.5, 0.4, 5.5), frame * CFrame.new(tx, 8.2, 0), nil, rgb(200, 50, 40)))
	local slide = Instance.new("WedgePart")
	slide.Name = "Slide"
	slide.Anchored = true
	slide.Size = Vector3.new(3, 5, 7)
	slide.Color = rgb(220, 70, 50)
	slide.CFrame = frame * CFrame.new(tx, 2.8, 6) * CFrame.Angles(0, math.pi, 0)
	slide.Parent = model
	counted(slide)
	-- swing set
	if s > 18 then
		local sx = L / 4
		for _, z in ipairs({ -6, 6 }) do
			counted(part(model, "SwingPost", Vector3.new(0.5, 10, 0.5), frame * CFrame.new(sx, 5, z), Enum.Material.Metal, rgb(40, 90, 160)))
		end
		counted(part(model, "SwingBar", Vector3.new(0.5, 0.5, 12.5), frame * CFrame.new(sx, 10, 0), Enum.Material.Metal, rgb(40, 90, 160)))
		for _, z in ipairs({ -2.5, 2.5 }) do
			counted(part(model, "Chain", Vector3.new(0.1, 7, 0.1), frame * CFrame.new(sx, 6.5, z), Enum.Material.Metal, POST))
			counted(part(model, "Seat", Vector3.new(1.2, 0.2, 2), frame * CFrame.new(sx, 3, z), nil, rgb(30, 30, 30)))
		end
	end
end

BUILDERS.swimming_pool = function(model, frame, L, W)
	slab(model, "Deck", frame, 0, 0, L + 6, W + 6, 0.4, Enum.Material.Concrete, rgb(200, 196, 186))
	local water = slab(model, "Water", frame, 0, 0, math.max(L - 2, 2), math.max(W - 2, 2), 0.2, Enum.Material.Glass, rgb(70, 160, 210), 0.42)
	water.Transparency = 0.15
	water.CanCollide = false
end

local function insidePolygon(points, x, z)
	local inside, n = false, #points / 2
	local j = n
	for i = 1, n do
		local xi, zi, xj, zj = points[2 * i - 1], points[2 * i], points[2 * j - 1], points[2 * j]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

BUILDERS.cemetery = function(model, frame, L, W, item)
	local placed = 0
	for gx = -L / 2 + 4, L / 2 - 4, 6 do
		for gz = -W / 2 + 4, W / 2 - 4, 9 do
			local p = frame * Vector3.new(gx, 0, gz)
			if placed < 600 and insidePolygon(item.outline, p.X, p.Z) then
				local y = groundY(p.X, p.Z)
				if y then
					local shade = 150 + (placed * 37) % 40
					counted(part(model, "Headstone", Vector3.new(0.6, 2.6 + (placed % 3) * 0.4, 2),
						CFrame.new(p.X, y + 1.2, p.Z) * frame.Rotation, Enum.Material.Granite, rgb(shade, shade, shade - 6)))
					placed += 1
				end
			end
		end
	end
end

-- 1. features
local featureFolder = Instance.new("Folder")
featureFolder.Name = "Features"
featureFolder.Parent = root
local built, skipped = {}, 0
for _, item in ipairs(Parks.features) do
	local key = item.kind == "pitch" and (item.sport or "pitch") or item.kind
	local builder = BUILDERS[key] or BUILDERS[item.sport or ""] or (item.kind == "pitch" and BUILDERS.pitch)
	local frame = frameOf(item.box)
	if builder and frame then
		local model = Instance.new("Model")
		model.Name = key
		builder(model, frame, item.box[3], item.box[4], item)
		model.Parent = featureFolder
		built[key] = (built[key] or 0) + 1
	else
		skipped += 1
	end
end

-- 2. parks: sign, walking loop, benches, lamps
local roadFolders = {}
local world = Workspace:FindFirstChild("ChesterWorld")
for _, tile in ipairs(world and world:GetChildren() or {}) do
	local roads = tile:FindFirstChild("Roads")
	if roads then table.insert(roadFolders, roads) end
end
local roadParams = OverlapParams.new()
roadParams.FilterType = Enum.RaycastFilterType.Include
roadParams.FilterDescendantsInstances = roadFolders
roadParams.MaxParts = 1

local function sign(parent, x, z, text)
	local y = groundY(x, z)
	if not y then return end
	local base = CFrame.new(x, y, z)
	counted(part(parent, "SignPost", Vector3.new(0.5, 6, 0.5), base * CFrame.new(-4, 3, 0), Enum.Material.Wood, WOOD))
	counted(part(parent, "SignPost", Vector3.new(0.5, 6, 0.5), base * CFrame.new(4, 3, 0), Enum.Material.Wood, WOOD))
	local board = counted(part(parent, "Sign", Vector3.new(10, 3, 0.4), base * CFrame.new(0, 5, 0), Enum.Material.Wood, rgb(40, 84, 52)))
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = rgb(240, 236, 220)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.Parent = gui
	end
end

local function bench(parent, cframe)
	counted(part(parent, "BenchSeat", Vector3.new(5, 0.3, 1.5), cframe * CFrame.new(0, 1.6, 0), Enum.Material.Wood, WOOD))
	counted(part(parent, "BenchBack", Vector3.new(5, 1.4, 0.3), cframe * CFrame.new(0, 2.6, 0.7), Enum.Material.Wood, WOOD))
	counted(part(parent, "BenchLeg", Vector3.new(0.3, 1.6, 1.5), cframe * CFrame.new(-2.2, 0.8, 0), Enum.Material.Metal, POST))
	counted(part(parent, "BenchLeg", Vector3.new(0.3, 1.6, 1.5), cframe * CFrame.new(2.2, 0.8, 0), Enum.Material.Metal, POST))
end

local function lamp(parent, x, y, z)
	counted(part(parent, "LampPost", Vector3.new(0.5, 12, 0.5), CFrame.new(x, y + 6, z), Enum.Material.Metal, rgb(36, 40, 38)))
	local head = counted(part(parent, "LampHead", Vector3.new(1.4, 1, 1.4), CFrame.new(x, y + 12.3, z), Enum.Material.Neon, rgb(255, 236, 190)))
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 0.8
	light.Shadows = false
	light.Color = rgb(255, 226, 170)
	light.Parent = head
end

local parkFolder = Instance.new("Folder")
parkFolder.Name = "Parks"
parkFolder.Parent = root
local signs, benches, lamps, pathParts = 0, 0, 0, 0
for _, park in ipairs(Parks.parks) do
	local model = Instance.new("Model")
	model.Name = park.name or "Park"
	local pts = park.outline
	local cx, cz, n = 0, 0, #pts / 2
	for i = 1, n do cx += pts[2 * i - 1]; cz += pts[2 * i] end
	cx, cz = cx / n, cz / n
	-- sign at the first outline vertex with a road beside it
	if park.name then
		for i = 1, n do
			local x, z = pts[2 * i - 1], pts[2 * i]
			local y = groundY(x, z)
			if y and #Workspace:GetPartBoundsInRadius(Vector3.new(x, y, z), 30, roadParams) > 0 then
				local inward = Vector3.new(cx - x, 0, cz - z)
				inward = inward.Magnitude > 0 and inward.Unit or Vector3.zero
				local sx, sz = x + inward.X * 8, z + inward.Z * 8
				local sy = groundY(sx, sz)
				if sy then
					sign(model, sx, sz, park.name)
					signs += 1
				end
				break
			end
		end
	end
	-- walking loop with benches and lamps
	local loop = park.loop
	if loop then
		local m = #loop / 2
		local travelled, nextBench, nextLamp, budget = 0, 40, 70, 400
		for i = 1, m do
			local ax, az = loop[2 * i - 1], loop[2 * i]
			local j = i % m + 1
			local bx, bz = loop[2 * j - 1], loop[2 * j]
			local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
			local steps = math.max(1, math.ceil(length / 20))
			for s = 0, steps - 1 do
				if budget <= 0 then break end
				local t0, t1 = s / steps, (s + 1) / steps
				local x0, z0 = ax + (bx - ax) * t0, az + (bz - az) * t0
				local x1, z1 = ax + (bx - ax) * t1, az + (bz - az) * t1
				local y0, y1 = groundY(x0, z0), groundY(x1, z1)
				if y0 and y1 then
					local a, b = Vector3.new(x0, y0 + 0.15, z0), Vector3.new(x1, y1 + 0.15, z1)
					counted(part(model, "Path", Vector3.new(6, 0.3, (b - a).Magnitude + 0.6),
						CFrame.lookAt((a + b) / 2, b), Enum.Material.Concrete, CONCRETE))
					pathParts += 1
					budget -= 1
				end
				travelled += length / steps
				if travelled >= nextBench and benches < 2000 then
					local dir = Vector3.new(x1 - x0, 0, z1 - z0)
					if dir.Magnitude > 0 and y1 then
						local side = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X) * 5
						local p = Vector3.new(x1, y1, z1) + side
						local by = groundY(p.X, p.Z)
						if by then
							bench(model, CFrame.lookAt(Vector3.new(p.X, by, p.Z), Vector3.new(x1, by, z1)) * CFrame.Angles(0, math.pi, 0))
							benches += 1
						end
					end
					nextBench += 70
				end
				if travelled >= nextLamp and y1 then
					local dir = Vector3.new(x1 - x0, 0, z1 - z0)
					if dir.Magnitude > 0 then
						local side = Vector3.new(dir.Unit.Z, 0, -dir.Unit.X) * 5
						local p = Vector3.new(x1, 0, z1) + side
						local ly = groundY(p.X, p.Z)
						if ly then
							lamp(model, p.X, ly, p.Z)
							lamps += 1
						end
					end
					nextLamp += 90
				end
			end
		end
	end
	model.Parent = parkFolder
end

local summary = {}
for k, v in pairs(built) do table.insert(summary, k .. "=" .. v) end
table.sort(summary)
print(("[ChesterWorld Parks] parks=%d signs=%d pathParts=%d benches=%d lamps=%d features: %s skipped=%d parts=%d")
	:format(#Parks.parks, signs, pathParts, benches, lamps, table.concat(summary, " "), skipped, parts))
Workspace:SetAttribute("CW_ParksComplete", true)
