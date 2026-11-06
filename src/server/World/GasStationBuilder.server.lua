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

local built, removed = 0, 0
for _, st in ipairs(Stations) do
	local fascia, accent, textColor = rgb(st.colors[1]), rgb(st.colors[2]), rgb(st.colors[3])
	local model = Instance.new("Model")
	model.Name = st.name
	model:SetAttribute("StationId", st.id)
	model:SetAttribute("Address", st.address)
	model:SetAttribute("Source", "street-imagery verified storefront inventory 2026-11-05")
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
				label(long, st.brand, { side == 1 and Enum.NormalId.Back or Enum.NormalId.Front }, textColor)
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
	-- brand sign at the street
	if st.sign then
		local x, z, bearing = st.sign[1], st.sign[2], st.sign[3]
		local y = groundY(x, z)
		if y then
			local rad = math.rad(bearing)
			local facing = Vector3.new(math.sin(rad), 0, -math.cos(rad))
			local base = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x, y, z) + facing)
			part(model, "SignPole", Vector3.new(0.6 * H, 6 * V, 0.6 * H), base * CFrame.new(0, 3 * V, 0), Enum.Material.Metal,
				Color3.fromRGB(120, 122, 126))
			local board = part(model, "SignBoard", Vector3.new(3 * H, 2.2 * V, 0.6), base * CFrame.new(0, 6 * V + 1.1 * V, 0),
				Enum.Material.SmoothPlastic, fascia)
			part(model, "SignStripe", Vector3.new(3 * H + 0.1, 0.35 * V, 0.7), base * CFrame.new(0, 6 * V + 0.2 * V, 0),
				Enum.Material.SmoothPlastic, accent)
			label(board, st.brand, { Enum.NormalId.Front, Enum.NormalId.Back }, textColor)
		end
	end
	if #model:GetChildren() > 0 then
		model.Parent = root
		built += 1
	end
end
print(("[ChesterWorld GasStations] built=%d canopyBoxesReplaced=%d parts=%d"):format(built, removed, count))
