-- ChesterWorld gas stations. Data: src/shared/WorldData/GasStations.lua
-- (tools/storefronts/build_gas_stations.py, from the street-imagery-verified
-- storefront inventory). The county footprints that are really fuel canopies
-- (checked on the DVRPC 2025 aerial) were being extruded into solid boxes; this
-- removes those models and builds an open canopy on columns, pump islands with
-- dispensers, a forecourt slab and a brand sign at the street.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local WorldData = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WorldData")
local module = WorldData:FindFirstChild("GasStations")
if not module then return end
local Stations = require(module)

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end
-- one build per server even if a duplicate copy of this script exists (no yield between check and claim)
if Workspace:FindFirstChild("ChesterGasStations") then return end

local V = 3 -- vertical studs per metre (BuildingTiles heights)
local H = 3.906 -- horizontal studs per metre at Chester's latitude (Web-Mercator x3)
local CLEARANCE = 4.6 * V
local FASCIA = 1.1 * V

local root = Instance.new("Folder")
root.Name = "ChesterGasStations"
root.Parent = Workspace
local world = Workspace:WaitForChild("ChesterWorld")

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
local function groundY(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), terrainParams)
	return hit and hit.Position.Y or nil
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end
local WHITE = Color3.fromRGB(238, 238, 234)
local CONCRETE = Color3.fromRGB(176, 174, 168)

local count = 0
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
	count += 1
	if count % 200 == 0 then task.wait() end
	return p
end

local function label(p, text, faces, color)
	for _, face in ipairs(faces) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0.3
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = string.upper(text)
		t.TextColor3 = color
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Parent = gui
	end
end

-- Brand artwork (from the Street View captures, tools/storefronts) drawn on
-- a SurfaceGui: canopy fascias and the pylon's brand panel.
local function text(parent, value, pos, size, color, font, align)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = value
	t.TextColor3 = color
	t.Font = font or Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Center
	t.Parent = parent
	return t
end
local function box(parent, pos, size, color, rotation)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.Rotation = rotation or 0
	f.Parent = parent
	return f
end
local function brandArt(gui, st, fascia, accent, textColor, logoAspect)
	local full = box(gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), fascia)
	local bg = full
	if logoAspect then
		-- long canopy fascia: the logo sits in a centred panel, the rest of the
		-- band keeps the brand colour
		bg = box(full, UDim2.fromScale(0.5, 0), UDim2.fromScale(1, 1), fascia)
		bg.AnchorPoint = Vector2.new(0.5, 0)
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = logoAspect
		ratio.Parent = bg
	end
	local b = st.brand
	if b == "Sunoco" then
		text(bg, "SUNOCO", UDim2.fromScale(0.06, 0.18), UDim2.fromScale(0.62, 0.64), textColor, Enum.Font.GothamBlack)
		-- the yellow chevron
		box(bg, UDim2.fromScale(0.74, 0.27), UDim2.fromScale(0.16, 0.14), accent, 35)
		box(bg, UDim2.fromScale(0.74, 0.59), UDim2.fromScale(0.16, 0.14), accent, -35)
	elseif b == "Chester Gas" then
		text(bg, "Chester", UDim2.fromScale(0.05, 0.12), UDim2.fromScale(0.42, 0.5), accent, Enum.Font.Fondamento)
		text(bg, "GAS", UDim2.fromScale(0.45, 0.1), UDim2.fromScale(0.5, 0.8), textColor, Enum.Font.GothamBlack)
	elseif b == "US Gas" then
		box(bg, UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), accent == Color3.fromRGB(240, 240, 240) and fascia or accent)
		bg.BackgroundColor3 = Color3.fromRGB(242, 242, 240)
		full.BackgroundColor3 = bg.BackgroundColor3
		local oval = box(bg, UDim2.fromScale(0.25, 0.1), UDim2.fromScale(0.5, 0.62), fascia)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = oval
		text(oval, "US GAS", UDim2.fromScale(0.08, 0.12), UDim2.fromScale(0.84, 0.76), Color3.fromRGB(255, 255, 255))
	elseif b == "Lukoil" then
		bg.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
		full.BackgroundColor3 = bg.BackgroundColor3
		box(bg, UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.18), fascia)
		text(bg, "LUKOIL", UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.66), fascia)
	elseif b == "Eagle Fuel" then
		box(bg, UDim2.fromScale(0.7, 0), UDim2.fromScale(0.3, 1), accent)
		text(bg, "EAGLE FUEL", UDim2.fromScale(0.04, 0.18), UDim2.fromScale(0.62, 0.64), textColor, Enum.Font.GothamBlack)
		text(bg, "▲", UDim2.fromScale(0.72, 0.1), UDim2.fromScale(0.26, 0.8), Color3.fromRGB(255, 255, 255))
	else
		box(bg, UDim2.fromScale(0, 0.8), UDim2.fromScale(1, 0.2), accent)
		text(bg, string.upper(b), UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.65), textColor)
	end
end
local function artPanel(p, st, faces, fascia, accent, textColor, ppStud)
	for _, face in ipairs(faces) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = ppStud or 24
		gui.LightInfluence = 0.25
		gui.Parent = p
		local long = math.max(p.Size.X, p.Size.Z) / p.Size.Y > 6
		brandArt(gui, st, fascia, accent, textColor, long and 4.5 or nil)
	end
end
-- LED price panel: one row per grade, label left, digits right
local function pricePanel(p, st, faces)
	local panelColor = st.panel and rgb(st.panel) or Color3.fromRGB(20, 20, 24)
	local led = st.led and rgb(st.led) or Color3.fromRGB(255, 52, 40)
	local labelColor = (panelColor.R + panelColor.G + panelColor.B) > 2.2 and Color3.fromRGB(30, 30, 30)
		or Color3.fromRGB(245, 245, 240)
	for _, face in ipairs(faces) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.Brightness = 1.4
		gui.Parent = p
		local bg = box(gui, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), panelColor)
		local grades = st.grades or { "REGULAR", "PLUS", "DIESEL" }
		local prices = st.prices or { 3.29, 3.89, 4.19 }
		local rows = #grades
		for i, g in ipairs(grades) do
			local y = (i - 1) / rows
			text(bg, g, UDim2.fromScale(0.05, y + 0.08 / rows), UDim2.fromScale(0.4, 0.62 / rows), labelColor,
				Enum.Font.GothamBold, Enum.TextXAlignment.Left)
			local cell = box(bg, UDim2.fromScale(0.47, y + 0.1 / rows), UDim2.fromScale(0.5, 0.8 / rows),
				Color3.fromRGB(10, 10, 10))
			local whole = string.format("%.2f", prices[i] or 0)
			text(cell, whole, UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.78, 0.9), led, Enum.Font.Arcade,
				Enum.TextXAlignment.Right)
			text(cell, "9", UDim2.fromScale(0.82, 0.05), UDim2.fromScale(0.14, 0.5), led, Enum.Font.Arcade)
		end
	end
end

-- county building models by id
local buildingsById = {}
for _, tile in ipairs(world:GetChildren()) do
	local folder = tile:FindFirstChild("Buildings")
	if folder then
		for _, model in ipairs(folder:GetChildren()) do
			local id = model:GetAttribute("ChesterBuildingId")
			if id then buildingsById[tostring(id)] = model end
		end
	end
end

-- The station's own shop (GasStations.lua `store`, picked from the DVRPC 2025
-- aerial and Street View by tools/storefronts/build_gas_stations.py): the
-- county building standing there (or the kiosk the footprints miss) is
-- rebuilt in place as an enterable shop - its own walls and roof colours,
-- a glass shopfront with a door facing the pumps, the shop's fascia (its own
-- name, e.g. A-PLUS / MINI-MART, or the fuel brand artwork) - and EXIT 6
-- (Exit6Storefronts.server.luau) fits the counter, shelves, cooler and
-- register inside it (Exit6StoreShell = "building").
local CollectionService = game:GetService("CollectionService")
local stores = 0
local function hex(v)
	return v and Color3.fromRGB(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256) or nil
end
local function storeFrame(st)
	local s = st.store
	if not s then return nil end
	local b = s.box
	local y = groundY(b[1], b[2])
	if not y then return nil end
	return CFrame.new(b[1], y, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0), b[3], b[4]
end
-- is world point p inside the shop footprint (plus margin)?
local function insideStore(frame, width, depth, p, margin)
	if not frame then return false end
	local l = frame:PointToObjectSpace(Vector3.new(p.X, frame.Position.Y, p.Z))
	return math.abs(l.X) < width / 2 + margin and math.abs(l.Z) < depth / 2 + margin
end
local function buildStore(model, st, fascia, accent, textColor, frame, width, depth)
	local s = st.store
	-- the county building in the footprint goes (only its parts inside the shop:
	-- a strip of shops keeps its other units)
	local county = s.model and buildingsById[s.model]
	if county and county.Parent then
		for _, p in ipairs(county:GetDescendants()) do
			if p:IsA("BasePart") and insideStore(frame, width, depth, p.Position, 1) then p:Destroy() end
		end
		local left = false
		for _, p in ipairs(county:GetDescendants()) do
			if p:IsA("BasePart") then left = true break end
		end
		if not left then county:Destroy() end
	end
	-- under a canopy the shop stops below the deck
	local h = s.h
	for _, c in ipairs(st.canopies) do
		local b = c.box
		local cf = CFrame.new(b[1], frame.Position.Y, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0)
		if insideStore(cf, b[3], b[4], frame.Position, 0) then h = math.min(h, CLEARANCE - 0.6) end
	end
	local wall = hex(s.wc) or Color3.fromRGB(232, 228, 220)
	local roof = hex(s.rc) or Color3.fromRGB(70, 72, 76)
	local shop = Instance.new("Model")
	shop.Name = "Shop"
	shop.Parent = model
	local function make(name, size, x, y, z, color, material)
		return part(shop, name, size, frame * CFrame.new(x, y, z), material or Enum.Material.SmoothPlastic, color)
	end
	local W2, D2 = width / 2, depth / 2
	make("Floor", Vector3.new(width, 0.6, depth), 0, 0.3, 0, Color3.fromRGB(196, 198, 200), Enum.Material.Marble)
	make("Foundation", Vector3.new(width + 0.4, 3, depth + 0.4), 0, -1.2, 0, Color3.fromRGB(150, 146, 140),
		Enum.Material.Concrete)
	if s.roof == "gable" then
		-- ridge along the shopfront, shingles down to the front and back walls
		local rise = math.clamp(depth * 0.28, 4, 12)
		for _, side in ipairs({ -1, 1 }) do
			local w = Instance.new("WedgePart")
			w.Name = "RoofSlope"
			w.Anchored = true
			w.Size = Vector3.new(width + 1.2, rise, D2 + 0.8)
			-- a wedge's tall face is its +Z side: point it at the ridge
			w.CFrame = frame * CFrame.new(0, h + rise / 2, side * (D2 + 0.8) / 2)
				* CFrame.Angles(0, side == -1 and 0 or math.pi, 0)
			w.Material = Enum.Material.Slate
			w.Color = roof
			w.TopSurface = Enum.SurfaceType.Smooth
			w.BottomSurface = Enum.SurfaceType.Smooth
			w.Parent = shop
		end
		make("Ceiling", Vector3.new(width, 0.4, depth), 0, h + 0.2, 0, wall)
	else
		make("Roof", Vector3.new(width + 0.6, 0.8, depth + 0.6), 0, h + 0.4, 0, roof, Enum.Material.Slate)
	end
	-- each face of the shop is a plain wall or a shopfront (front = toward the
	-- pumps; extra shopfronts from GasStations.lua, e.g. US Gas's check cashing
	-- office on its 9th St side). Face frames: local -Z = outward.
	local FACES = {
		front = { 0, -D2, 0, width }, back = { 0, D2, math.pi, width },
		left = { -W2, 0, math.pi / 2, depth }, right = { W2, 0, -math.pi / 2, depth },
	}
	local shopfronts = { front = { sign = s.sign, signColors = s.signColors, main = true } }
	for _, e in ipairs(s.extra or {}) do
		shopfronts[e.face] = { sign = e.sign, signColors = e.signColors }
	end
	local function signBoard(board, spec, signBg, signAccent, signText)
		if spec.sign then
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 16
			gui.LightInfluence = 0.25
			gui.Parent = board
			if spec.sign == "A-PLUS" then
				-- Sunoco's A-Plus badge centred on the blue band (Street View)
				local badge = box(gui, UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.26, 0.76), Color3.fromRGB(250, 250, 248))
				badge.AnchorPoint = Vector2.new(0.5, 0)
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.2, 0)
				corner.Parent = badge
				text(badge, "A", UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.3, 0.9), Color3.fromRGB(226, 32, 40), Enum.Font.GothamBlack)
				text(badge, "Plus", UDim2.fromScale(0.34, 0.15), UDim2.fromScale(0.62, 0.7), Color3.fromRGB(236, 120, 30), Enum.Font.GothamBold)
				box(gui, UDim2.fromScale(0, 0.9), UDim2.fromScale(1, 0.1), signAccent)
			else
				box(gui, UDim2.fromScale(0, 0.82), UDim2.fromScale(1, 0.18), signAccent)
				text(gui, spec.sign, UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.68), signText, Enum.Font.GothamBlack)
			end
		else
			artPanel(board, st, { Enum.NormalId.Front }, fascia, accent, textColor, 16)
		end
	end
	local fasciaH = math.clamp(h * 0.22, 2.4, 4.5)
	local glassTop = math.min(h - fasciaH, 12)
	for faceName, f in pairs(FACES) do
		local fx, fz, rot, len = f[1], f[2], f[3], f[4]
		local fcf = frame * CFrame.new(fx, 0, fz) * CFrame.Angles(0, rot, 0)
		local function mk(name, size, x, y, z, color, material)
			return part(shop, name, size, fcf * CFrame.new(x, y, z), material or Enum.Material.SmoothPlastic, color)
		end
		local spec = shopfronts[faceName]
		if not spec then
			mk("Wall", Vector3.new(len, h, 0.8), 0, h / 2, 0.4, wall, Enum.Material.Brick)
		else
			-- glass either side of a centred door, piers, the shop's fascia above
			local half = len / 2
			local door = math.min(7, len * 0.3)
			local pane = math.max((len - door) / 2 - 1.2, 1)
			for _, side in ipairs({ -1, 1 }) do
				local g = mk("Shopfront", Vector3.new(pane, glassTop - 1.2, 0.3), side * (door / 2 + pane / 2),
					0.6 + (glassTop - 1.2) / 2, 0.4, Color3.fromRGB(150, 190, 210), Enum.Material.Glass)
				g.Transparency = 0.35
				g.Reflectance = 0.15
				mk("Pier", Vector3.new(1.2, glassTop, 0.9), side * (half - 0.6), glassTop / 2, 0.4, wall, Enum.Material.Brick)
				mk("DoorFrame", Vector3.new(0.4, glassTop - 0.6, 0.6), side * door / 2, (glassTop - 0.6) / 2 + 0.6, 0.4,
					fascia, Enum.Material.Metal)
			end
			mk("Sill", Vector3.new(len, 0.6, 0.9), 0, 0.6, 0.4, wall, Enum.Material.Brick)
			-- wall above the fascia up to the roof on a tall building
			local signTop = glassTop + fasciaH
			if h - signTop > 0.5 then
				mk("Wall", Vector3.new(len, h - signTop, 0.8), 0, signTop + (h - signTop) / 2, 0.4, wall, Enum.Material.Brick)
			end
			local signBg, signAccent, signText = fascia, accent, textColor
			if spec.signColors then
				signBg, signAccent, signText = rgb(spec.signColors[1]), rgb(spec.signColors[2]), rgb(spec.signColors[3])
			end
			local board = mk(spec.main and "ShopFascia" or "ShopFasciaExtra", Vector3.new(len, fasciaH, 0.9), 0,
				glassTop + fasciaH / 2, 0.3, signBg)
			signBoard(board, spec, signBg, signAccent, signText)
			mk("AccentStripe", Vector3.new(len, 0.5, 1.0), 0, glassTop - 0.1, 0.3, signAccent)
			local mat = mk("DoorMat", Vector3.new(door - 1, 0.1, 3), 0, 0.65, -1.2, Color3.fromRGB(40, 40, 44),
				Enum.Material.Fabric)
			mat.CanCollide = false
		end
	end
	-- EXIT 6 fits the interior at the shop floor, facing the door (-Z)
	local anchor = part(model, "Exit6StoreAnchor", Vector3.new(2, 0.2, 2), frame * CFrame.new(0, 0.7, 0),
		Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	model:SetAttribute("BrandName", st.brand)
	model:SetAttribute("ShopName", s.sign or st.brand)
	model:SetAttribute("BrandFascia", fascia)
	model:SetAttribute("BrandAccent", accent)
	model:SetAttribute("BrandText", textColor)
	model:SetAttribute("Exit6StoreShell", "building")
	model:SetAttribute("Exit6StoreWidth", width)
	model:SetAttribute("Exit6StoreDepth", depth)
	model:SetAttribute("Exit6StoreHeight", h)
	CollectionService:AddTag(model, "Exit6GasStation")
	stores += 1
end

local built, removed = 0, 0
for _, st in ipairs(Stations) do
	local fascia, accent, textColor = rgb(st.colors[1]), rgb(st.colors[2]), rgb(st.colors[3])
	local model = Instance.new("Model")
	model.Name = st.name
	model:SetAttribute("StationId", st.id)
	model:SetAttribute("Address", st.address)
	model:SetAttribute("Source", "street-imagery verified storefront inventory 2026-11-05")
	local shopFrame, shopWidth, shopDepth = storeFrame(st)
	for _, c in ipairs(st.canopies) do
		local b = c.box
		local y = groundY(b[1], b[2])
		if y then
			if c.replaces and buildingsById[c.replaces] then
				buildingsById[c.replaces]:Destroy()
				removed += 1
			end
			local L, W = math.max(b[3], 12 * H), math.max(b[4], 7 * H)
			local frame = CFrame.new(b[1], y, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0)
			-- forecourt slab
			part(model, "Forecourt", Vector3.new(L + 6 * H, 0.6, W + 8 * H), frame * CFrame.new(0, 0.2, 0),
				Enum.Material.Concrete, CONCRETE)
			-- canopy deck + fascia band with brand accent stripe
			local top = CLEARANCE + FASCIA
			local deck = part(model, "CanopyDeck", Vector3.new(L, 0.8, W), frame * CFrame.new(0, CLEARANCE + 0.4, 0),
				Enum.Material.SmoothPlastic, WHITE)
			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Brightness = 1.5
			light.Range = 16
			light.Color = Color3.fromRGB(255, 250, 235)
			light.Parent = deck
			for _, side in ipairs({ -1, 1 }) do
				local long = part(model, "Fascia", Vector3.new(L + 0.6, FASCIA, 0.6),
					frame * CFrame.new(0, CLEARANCE + FASCIA / 2, side * (W / 2 + 0.3)), Enum.Material.SmoothPlastic, fascia)
				part(model, "FasciaStripe", Vector3.new(L + 0.7, FASCIA * 0.22, 0.7),
					frame * CFrame.new(0, CLEARANCE + FASCIA * 0.2, side * (W / 2 + 0.3)), Enum.Material.SmoothPlastic, accent)
				artPanel(long, st, { side == 1 and Enum.NormalId.Back or Enum.NormalId.Front }, fascia, accent, textColor, 12)
				part(model, "Fascia", Vector3.new(0.6, FASCIA, W + 0.6),
					frame * CFrame.new(side * (L / 2 + 0.3), CLEARANCE + FASCIA / 2, 0), Enum.Material.SmoothPlastic, fascia)
			end
			part(model, "CanopyRoof", Vector3.new(L, 0.3, W), frame * CFrame.new(0, top - 0.15, 0), Enum.Material.Metal,
				Color3.fromRGB(205, 205, 200))
			-- pump islands along the canopy, one or two rows
			local rows = W > 12 * H and { -W / 4, W / 4 } or { 0 }
			local islandLen = 5 * H
			local n = math.max(1, math.floor(L / (9 * H) + 0.5))
			for _, rz in ipairs(rows) do
				for i = 1, n do
					local x = -L / 2 + (i - 0.5) * L / n
					if insideStore(shopFrame, shopWidth, shopDepth, frame * Vector3.new(x, 0, rz), 3) then
						continue
					end
					part(model, "PumpIsland", Vector3.new(islandLen, 0.9, 1.4 * H), frame * CFrame.new(x, 0.95, rz),
						Enum.Material.Concrete, Color3.fromRGB(200, 196, 186))
					local disp = part(model, "Dispenser", Vector3.new(1.1 * H, 1.8 * V, 0.7 * H),
						frame * CFrame.new(x, 1.4 + 0.9 * V, rz), Enum.Material.SmoothPlastic, WHITE)
					part(model, "DispenserBand", Vector3.new(1.12 * H, 0.5 * V, 0.72 * H),
						frame * CFrame.new(x, 1.4 + 1.55 * V, rz), Enum.Material.SmoothPlastic, fascia)
					disp:SetAttribute("Kind", "FuelDispenser")
					for _, e in ipairs({ -1, 1 }) do
						part(model, "Column", Vector3.new(0.5 * H, CLEARANCE, 0.5 * H),
							frame * CFrame.new(x + e * (islandLen / 2 - 0.4 * H), 1.4 + CLEARANCE / 2 - 0.7, rz),
							Enum.Material.SmoothPlastic, WHITE)
					end
				end
			end
		end
	end
	-- Pylon price sign at the lot corner behind the sidewalk (placed by
	-- tools/storefronts/build_gas_stations.py; board faces along the street so
	-- both sides read to traffic): concrete-clad post, LED price panel, brand
	-- panel on top - as on the Street View captures.
	if st.sign then
		local x, z, bearing = st.sign[1], st.sign[2], st.sign[3]
		local y = groundY(x, z)
		if y then
			local rad = math.rad(bearing)
			local facing = Vector3.new(math.sin(rad), 0, -math.cos(rad))
			local base = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + facing)
			local W = 2.7 * H                         -- ~2.7 m wide boards
			local postH, priceH, brandH = 3.2 * V, 2.4 * V, 1.9 * V
			part(model, "SignBase", Vector3.new(W * 0.7, 1.2, 2.4 * H * 0.7), base * CFrame.new(0, 0.6, 0),
				Enum.Material.Concrete, CONCRETE)
			-- post / frame in the pylon's own colour where it differs (Eagle Fuel: red)
			local postColor = st.post and rgb(st.post) or fascia
			part(model, "SignPost", Vector3.new(0.9 * H, postH, 0.9 * H), base * CFrame.new(0, postH / 2, 0),
				Enum.Material.SmoothPlastic, postColor)
			local priceBoard = part(model, "PriceBoard", Vector3.new(W, priceH, 1.2), base * CFrame.new(0, postH + priceH / 2, 0),
				Enum.Material.SmoothPlastic, st.panel and rgb(st.panel) or fascia)
			pricePanel(priceBoard, st, { Enum.NormalId.Front, Enum.NormalId.Back })
			local brandBoard = part(model, "BrandBoard", Vector3.new(W, brandH, 1.4),
				base * CFrame.new(0, postH + priceH + brandH / 2 + 0.2, 0), Enum.Material.SmoothPlastic, fascia)
			artPanel(brandBoard, st, { Enum.NormalId.Front, Enum.NormalId.Back }, fascia, accent, textColor, 24)
			part(model, "SignCap", Vector3.new(W + 0.4, 0.5, 1.6), base * CFrame.new(0, postH + priceH + brandH + 0.45, 0),
				Enum.Material.Metal, Color3.fromRGB(150, 152, 156))
			model:SetAttribute("PriceRegular", st.prices and st.prices[1])
		end
	end
	if #model:GetChildren() > 0 then
		model.Parent = root
		built += 1
		if shopFrame then buildStore(model, st, fascia, accent, textColor, shopFrame, shopWidth, shopDepth) end
		-- county footprints in the lot that are really low sheds / booths
		for _, shed in ipairs(st.sheds or {}) do
			local county = buildingsById[shed.model]
			if county and county.Parent then county:Destroy() end
			local b = shed.box
			local gy = groundY(b[1], b[2])
			if gy then
				local L, W, hS = math.max(b[3], 9), math.max(b[4], 7), 9
				local cf = CFrame.new(b[1], gy, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0)
				part(model, "Shed", Vector3.new(L, hS, W), cf * CFrame.new(0, hS / 2, 0), Enum.Material.SmoothPlastic,
					Color3.fromRGB(236, 236, 232))
				part(model, "ShedRoof", Vector3.new(L + 0.6, 0.5, W + 0.6), cf * CFrame.new(0, hS + 0.25, 0),
					Enum.Material.Metal, Color3.fromRGB(150, 152, 156))
				part(model, "ShedDoor", Vector3.new(3, 7, 0.2), cf * CFrame.new(0, 3.5, -W / 2 - 0.1),
					Enum.Material.Metal, Color3.fromRGB(120, 124, 128))
			end
		end
	end
end
print(("[ChesterWorld GasStations] built=%d canopyBoxesReplaced=%d exit6Stores=%d parts=%d"):format(built, removed, stores, count))
Workspace:SetAttribute("CW_GasStationsComplete", true)
