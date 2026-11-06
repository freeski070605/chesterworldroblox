-- Draws the faces of street furniture built by StreetFurniture.server.lua, on
-- the client and only for parts that are streamed in: street-name blades
-- (CW_StreetBlade, text in the "Text" attribute) and stop signs (CW_StopSign:
-- white-bordered red octagon with STOP). Streamed-out parts take their
-- SurfaceGuis with them, so the GUI count follows what the player can see.
local CollectionService = game:GetService("CollectionService")

local SQRT2 = math.sqrt(2)

local function frame(parent, x, y, w, h, color, rotation, z)
	local f = Instance.new("Frame")
	f.ZIndex = z or 1
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.Rotation = rotation or 0
	f.Parent = parent
	return f
end

-- regular octagon filling a square of side `scale` centred in the gui:
-- two crossing rectangles + four 45-degree diamonds on the diagonal edges
local function octagon(parent, scale, color, z)
	local s = scale / (1 + SQRT2)          -- side length
	local c = (scale - s) / 2               -- corner cut
	local o = (1 - scale) / 2               -- offset to centre
	frame(parent, 0.5, 0.5, scale, s, color, 0, z)
	frame(parent, 0.5, 0.5, s, scale, color, 0, z)
	for _, p in ipairs({ { c, c }, { scale - c, c }, { c, scale - c }, { scale - c, scale - c } }) do
		-- diamond side s: half-diagonal = corner cut, so it fills exactly the cut corner
		frame(parent, o + p[1], o + p[2], s, s, color, 45, z)
	end
end

local function surfaceGui(part, face, ppStud)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppStud
	gui.LightInfluence = 0.6
	gui.MaxDistance = 260
	gui.Parent = part
	return gui
end

local function decorateBlade(part)
	if part:FindFirstChild("BladeFace") then return end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = surfaceGui(part, face, 40)
		gui.Name = "BladeFace"
		local border = Instance.new("UIStroke")
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = part.Color
		bg.BorderSizePixel = 0
		bg.Parent = gui
		border.Color = Color3.fromRGB(240, 240, 236)
		border.Thickness = 2
		border.Parent = bg
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.04, 0.1)
		t.Size = UDim2.fromScale(0.92, 0.8)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(250, 250, 248)
		t.Text = part:GetAttribute("Text") or ""
		t.Parent = bg
	end
end

local function decorateStop(part)
	if part:FindFirstChild("StopFace") then return end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = surfaceGui(part, face, 50)
		gui.Name = "StopFace"
		if face == Enum.NormalId.Back then
			-- back of the plate: plain grey octagon
			octagon(gui, 1, Color3.fromRGB(150, 152, 150))
		else
			octagon(gui, 1, Color3.fromRGB(245, 245, 245), 1)
			octagon(gui, 0.9, Color3.fromRGB(190, 20, 30), 2)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.fromScale(0.5, 0.5)
			t.Size = UDim2.fromScale(0.78, 0.36)
			t.Font = Enum.Font.GothamBold
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.Text = "STOP"
			t.ZIndex = 5
			t.Parent = gui
		end
	end
end

local function watch(tag, fn)
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		task.defer(fn, part)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
		task.defer(fn, part)
	end)
end
watch("CW_StreetBlade", decorateBlade)
watch("CW_StopSign", decorateStop)
