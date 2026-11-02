local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GeoOrientation = require(Shared:WaitForChild("GeoOrientation"))

local world = Workspace:WaitForChild("ChesterWorld")

local SEARCH_RADIUS = 95
local INTERSECTION_DISTANCE = 38
local UPDATE_INTERVAL = 0.18

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { world }
overlap.MaxParts = 180

local gui = Instance.new("ScreenGui")
gui.Name = "ChesterLocationHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "LocationPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 16)
panel.Size = UDim2.fromOffset(430, 92)
panel.BackgroundColor3 = Color3.fromRGB(10, 12, 15)
panel.BackgroundTransparency = 0.18
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 11)
corner.Parent = panel

local city = Instance.new("TextLabel")
city.BackgroundTransparency = 1
city.Position = UDim2.fromOffset(14, 8)
city.Size = UDim2.new(1, -28, 0, 20)
city.Font = Enum.Font.GothamBold
city.TextSize = 13
city.TextXAlignment = Enum.TextXAlignment.Center
city.TextColor3 = Color3.fromRGB(200, 205, 214)
city.Text = "CHESTER, PA"
city.Parent = panel

local location = Instance.new("TextLabel")
location.BackgroundTransparency = 1
location.Position = UDim2.fromOffset(14, 27)
location.Size = UDim2.new(1, -28, 0, 32)
location.Font = Enum.Font.GothamBlack
location.TextSize = 23
location.TextXAlignment = Enum.TextXAlignment.Center
location.TextColor3 = Color3.fromRGB(255, 255, 255)
location.Text = "LOCATING..."
location.Parent = panel

local detail = Instance.new("TextLabel")
detail.BackgroundTransparency = 1
detail.Position = UDim2.fromOffset(14, 61)
detail.Size = UDim2.new(1, -28, 0, 20)
detail.Font = Enum.Font.GothamMedium
detail.TextSize = 11
detail.TextXAlignment = Enum.TextXAlignment.Center
detail.TextColor3 = Color3.fromRGB(170, 177, 188)
detail.Text = "RUNTIME ROAD HUD • TRUE NORTH -Z"
detail.Parent = panel

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeStreet(raw)
	local s = trim(raw)
	if s == "" or s:lower() == "road" then
		return nil
	end

	local upper = string.upper(s)

	-- Collapse common suffix variants so "Barclay" and "Barclay St"
	-- are treated as the same rendered street.
	upper = upper:gsub("%s+STREET$", "")
	upper = upper:gsub("%s+ST$", "")
	upper = upper:gsub("%s+AVENUE$", "")
	upper = upper:gsub("%s+AVE$", "")
	upper = upper:gsub("%s+ROAD$", "")
	upper = upper:gsub("%s+RD$", "")
	upper = upper:gsub("%s+BOULEVARD$", "")
	upper = upper:gsub("%s+BLVD$", "")

	return trim(upper)
end

local function horizontalDistanceToPart(position, part)
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local hx = part.Size.X * 0.5
	local hz = part.Size.Z * 0.5

	local dx = math.max(math.abs(localPoint.X) - hx, 0)
	local dz = math.max(math.abs(localPoint.Z) - hz, 0)

	return math.sqrt(dx * dx + dz * dz)
end

local function numberedStreet(name)
	return name and name:match("^%d") ~= nil
end

local function pairLabel(a, b)
	if not b then
		return a
	end

	-- Chester locals naturally say "9TH & PARKER", so put numbered
	-- streets first when only one side is numbered.
	if numberedStreet(a) and not numberedStreet(b) then
		return a .. " & " .. b
	elseif numberedStreet(b) and not numberedStreet(a) then
		return b .. " & " .. a
	end

	return a .. " & " .. b
end

local function headingInfo()
	local camera = Workspace.CurrentCamera
	if not camera then
		return 0, "N"
	end

	local look = camera.CFrame.LookVector
	local heading = GeoOrientation.headingDegrees(look)
	return heading, GeoOrientation.headingName(heading)
end

local function resolveLocation(position)
	local nearby = Workspace:GetPartBoundsInRadius(
		position,
		SEARCH_RADIUS,
		overlap
	)

	local bestByStreet = {}

	for _, part in ipairs(nearby) do
		if part:IsA("BasePart") then
			local rawStreet = part:GetAttribute("ChesterStreet")

			if rawStreet == nil then
				-- Fallback for generated Road Parts whose Name is the street.
				local parent = part.Parent
				if parent and parent.Name == "Roads" then
					rawStreet = part.Name
				end
			end

			local street = normalizeStreet(rawStreet)
			if street then
				local d = horizontalDistanceToPart(position, part)
				local current = bestByStreet[street]

				if current == nil or d < current then
					bestByStreet[street] = d
				end
			end
		end
	end

	local ranked = {}
	for street, distance in pairs(bestByStreet) do
		table.insert(ranked, {
			street = street,
			distance = distance,
		})
	end

	table.sort(ranked, function(a, b)
		if math.abs(a.distance - b.distance) > 0.05 then
			return a.distance < b.distance
		end
		return a.street < b.street
	end)

	if #ranked == 0 then
		return "CHESTER", nil, nil
	end

	local first = ranked[1]
	local second = ranked[2]

	if second and second.distance <= INTERSECTION_DISTANCE then
		return pairLabel(first.street, second.street), first, second
	end

	return first.street, first, nil
end

local elapsed = 0

RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		location.Text = "LOCATING..."
		return
	end

	local label, first, second = resolveLocation(rootPart.Position)
	location.Text = label

	local heading, cardinal = headingInfo()

	if first then
		if second then
			detail.Text = string.format(
				"RUNTIME ROADS • %03d° %s • N -Z • %.0f/%.0f studs",
				math.floor(heading + 0.5),
				cardinal,
				first.distance,
				second.distance
			)
		else
			detail.Text = string.format(
				"RUNTIME ROAD • %03d° %s • TRUE N -Z • %.0f studs",
				math.floor(heading + 0.5),
				cardinal,
				first.distance
			)
		end
	else
		detail.Text = string.format(
			"RUNTIME ROAD HUD • %03d° %s • TRUE N -Z",
			math.floor(heading + 0.5),
			cardinal
		)
	end
end)

print("[ChesterWorld] Runtime road HUD loaded — north=-Z, rendered roads are source of truth.")
