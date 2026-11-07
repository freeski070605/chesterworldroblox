-- ChesterWorld street furniture: street-name blade signs at every named
-- intersection, stop signs / traffic signals by street hierarchy, and
-- cobra-head street lights along city streets. Built from the road tile data
-- after the world (and the highway finish) so everything stands on the final
-- pavement / sidewalk surface.
--
-- Efficiency: only plain parts are built here (pole, blades, sign plate,
-- signal head, light arm). Text and the stop-sign octagon are drawn by the
-- client (src/client/SignFaces.client.lua) for parts tagged CW_StreetBlade /
-- CW_StopSign as they stream in, so thousands of signs cost no SurfaceGuis
-- until a player is near them.
--
-- Placement rules (US / Pennsylvania practice):
--   * named intersection (2+ street names, 3+ arms): one blade-sign pole on a
--     corner between the two most perpendicular differently-named streets;
--   * main x main (tertiary or above on 2+ differently-named streets):
--     traffic signal on the right of every approach;
--   * otherwise the lower-class approaches get STOP; where all approaches are
--     the same class a T junction stops its stem, a 4-way is an all-way stop;
--   * lights: every ~150 studs along streets with sidewalks, alternating
--     sides, set back from intersections; none on freeways, bridges, rail,
--     alleys or service drives.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local Tiles = Shared:WaitForChild("WorldData"):WaitForChild("Tiles")

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end
-- stand on the final surfaces (RoadTerrainClear.server.lua), but never hang
local clearDeadline = os.clock() + 120
while Workspace:GetAttribute("CW_RoadTerrainCleared") ~= true and os.clock() < clearDeadline do task.wait(0.5) end
if Workspace:FindFirstChild("ChesterStreetFurniture") then return end
local root = Instance.new("Folder")
root.Name = "ChesterStreetFurniture"
root.Parent = Workspace
local world = Workspace:WaitForChild("ChesterWorld")

local S = WorldConfig.STUDS_PER_METER
local CX, CZ = WorldConfig.WORLD_CENTER_X_M, WorldConfig.WORLD_CENTER_Z_M
local SIDEWALK = (WorldConfig.SIDEWALK_WIDTH_STUDS or 5) + (WorldConfig.SIDEWALK_GAP_STUDS or 0.1)

local RANK = {
	primary = 4, secondary = 3, tertiary = 2,
	residential = 1, ["local"] = 1, unclassified = 1, living_street = 1,
}
local RAIL = {
	["Cr Chester Secondary"] = true, ["Amtrak Ne Corridor"] = true,
	["Linwood Industrial Track"] = true, ["Csx Phila Subdivision"] = true,
}

-- ---------------------------------------------------------------------------
-- surface height: the pavement / sidewalk near the ground, not a deck above
local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
terrainParams.IgnoreWater = true
local surfaceFolders = {}
for _, tile in ipairs(world:GetChildren()) do
	for _, name in ipairs({ "Roads", "Sidewalks", "Intersection", "Intersections" }) do
		local f = tile:FindFirstChild(name)
		if f then table.insert(surfaceFolders, f) end
	end
end
local surfaceParams = RaycastParams.new()
surfaceParams.FilterType = Enum.RaycastFilterType.Include
surfaceParams.FilterDescendantsInstances = surfaceFolders
-- rail beds: no pole on the tracks (a signal stood on the CSX at Edgmont)
local railBeds = {}
for _, f in ipairs(surfaceFolders) do
	for _, p in ipairs(f:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("CW_Rail") == true and p.Name ~= "Rail" then
			table.insert(railBeds, p)
		end
	end
end
local railParams = RaycastParams.new()
railParams.FilterType = Enum.RaycastFilterType.Include
railParams.FilterDescendantsInstances = railBeds
local function surfaceY(x, z)
	local t = Workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), terrainParams)
	if not t then return nil end
	local s = Workspace:Raycast(Vector3.new(x, t.Position.Y + 6, z), Vector3.new(0, -12, 0), surfaceParams)
	local y = math.max(t.Position.Y, s and s.Position.Y or -math.huge)
	if #railBeds > 0 then
		local r = Workspace:Raycast(Vector3.new(x, y + 6, z), Vector3.new(0, -12, 0), railParams)
		if r then return nil end
	end
	return y
end

-- ---------------------------------------------------------------------------
local count = 0
local function part(parent, name, size, cframe, material, color, tag)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Material = material or Enum.Material.Metal
	p.Color = color or Color3.fromRGB(120, 124, 128)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if tag then CollectionService:AddTag(p, tag) end
	p.Parent = parent
	count += 1
	if count % 400 == 0 then task.wait() end
	return p
end
local POLE = Color3.fromRGB(110, 114, 116)
local GREEN = WorldConfig.SIGN_BACKGROUND_COLOR or Color3.fromRGB(24, 94, 55)

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-6 and f.Unit or Vector3.new(0, 0, -1)
end
local function rightOf(travel) -- driver's right for a horizontal travel direction
	return Vector3.new(-travel.Z, 0, travel.X)
end

-- ---------------------------------------------------------------------------
-- 1. city street graph from the tile data
local nodes = {}
local segments = {}
local function key(x, z)
	return math.floor(x * 2 + 0.5) .. ":" .. math.floor(z * 2 + 0.5)
end
for _, module in ipairs(Tiles:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, tile = pcall(require, module)
		if ok and type(tile) == "table" then
			for _, road in ipairs(tile.roads or {}) do
				local cls = string.lower(tostring(road.road_class or ""))
				local rank = RANK[cls]
				local name = tostring(road.name or "")
				if rank and not RAIL[name] and road.bridge ~= true and road.tunnel ~= true
					and (tonumber(road.layer) or 0) == 0 then
					local ax, az = (road.x1 - CX) * S, -(road.z1 - CZ) * S
					local bx, bz = (road.x2 - CX) * S, -(road.z2 - CZ) * S
					local a, b = Vector3.new(ax, 0, az), Vector3.new(bx, 0, bz)
					if (b - a).Magnitude > 0.5 then
						local seg = {
							a = a, b = b, name = name, rank = rank,
							half = math.max((tonumber(road.width_m) or 7) * S, 3) / 2,
							sidewalk = road.sidewalk ~= false,
						}
						table.insert(segments, seg)
						for e, p in ipairs({ a, b }) do
							local k = key(p.X, p.Z)
							local n = nodes[k]
							if not n then
								n = { p = p, arms = {} }
								nodes[k] = n
							end
							local other = e == 1 and b or a
							table.insert(n.arms, { dir = flat(other - p), seg = seg })
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- 2. intersections: blades, stop signs, signals
local junctionPoints = {}
local blades, stops, signals = 0, 0, 0

local function bladeSign(n, armA, armB)
	local corner = flat(armA.dir + armB.dir)
	local reach = math.max(armA.seg.half, armB.seg.half) + 3.5
	local p = n.p + corner * (reach * 1.414)
	local y = surfaceY(p.X, p.Z)
	if not y then return end
	local H = 11
	part(root, "StreetSignPole", Vector3.new(0.4, H, 0.4), CFrame.new(p.X, y + H / 2, p.Z), Enum.Material.Metal, POLE)
	for i, arm in ipairs({ armA, armB }) do
		-- a blade lies along its street, readable from both sides
		local look = CFrame.lookAt(Vector3.zero, rightOf(arm.dir))
		local blade = part(root, "StreetBlade", Vector3.new(5.6, 1.1, 0.12),
			CFrame.new(p.X, y + H - 0.6 - (i - 1) * 1.25, p.Z) * look.Rotation
				* CFrame.new(0, 0, 0), Enum.Material.SmoothPlastic, GREEN, "CW_StreetBlade")
		blade:SetAttribute("Text", string.upper(arm.seg.name))
	end
	blades += 1
end

-- carriageway / junction paving only (not sidewalks): no pole stands in the road
local carriageFolders = {}
for _, f in ipairs(surfaceFolders) do
	if f.Name ~= "Sidewalks" then table.insert(carriageFolders, f) end
end
local carriageParams = RaycastParams.new()
carriageParams.FilterType = Enum.RaycastFilterType.Include
carriageParams.FilterDescendantsInstances = carriageFolders
local function inCarriageway(p, y)
	local hit = Workspace:Raycast(Vector3.new(p.X, y + 3, p.Z), Vector3.new(0, -6, 0), carriageParams)
	return hit ~= nil and hit.Instance:GetAttribute("CW_Rail") ~= true
end
-- step a pole spot out from the kerb (along `out`) until it is off the road;
-- nil when no spot within reach is clear
local function kerbSpot(p, out)
	for _, extra in ipairs({ 0, 2.5, 5.5, 8.5 }) do
		local q = p + out * extra
		local y = surfaceY(q.X, q.Z)
		if y and not inCarriageway(q, y) then return q, y end
	end
	return nil
end

local function stopSign(n, arm)
	-- approaching traffic travels toward the node, against arm.dir
	local travel = -arm.dir
	local others = 0
	for _, o in ipairs(n.arms) do
		if o ~= arm then others = math.max(others, o.seg.half) end
	end
	local p, y = kerbSpot(n.p + arm.dir * (others + 5) + rightOf(travel) * (arm.seg.half + 2.2), rightOf(travel))
	if not p then return end
	local H = 7.4
	part(root, "StopSignPole", Vector3.new(0.3, H, 0.3), CFrame.new(p.X, y + H / 2, p.Z), Enum.Material.Metal, POLE)
	local face = CFrame.lookAt(Vector3.new(p.X, y + H + 0.9, p.Z), Vector3.new(p.X, y + H + 0.9, p.Z) + arm.dir)
	part(root, "StopSign", Vector3.new(2.4, 2.4, 0.1), face, Enum.Material.SmoothPlastic,
		Color3.fromRGB(190, 20, 30), "CW_StopSign").Transparency = 1
	stops += 1
end

local SIGNAL_BODY = Color3.fromRGB(38, 40, 36)
local function signal(n, arm, go)
	local travel = -arm.dir
	local others = 0
	for _, o in ipairs(n.arms) do
		if o ~= arm then others = math.max(others, o.seg.half) end
	end
	-- (a signal is kept at its kerb spot even on wide junction paving)
	local base0 = n.p + arm.dir * (others + 4) + rightOf(travel) * (arm.seg.half + 2.5)
	local base, y = kerbSpot(base0, rightOf(travel))
	if not base then
		base, y = base0, surfaceY(base0.X, base0.Z)
		if not y then return end
	end
	local H = 15
	part(root, "SignalPole", Vector3.new(0.6, H, 0.6), CFrame.new(base.X, y + H / 2, base.Z), Enum.Material.Metal, POLE)
	-- mast arm out over the approach lanes, head facing the traffic
	local reach = math.min(arm.seg.half + 1, 18)
	local tip = base - rightOf(travel) * reach + Vector3.new(0, y + H - 0.6, 0)
	local from = Vector3.new(base.X, y + H - 0.6, base.Z)
	part(root, "SignalArm", Vector3.new(0.4, 0.4, (tip - from).Magnitude), CFrame.lookAt((from + tip) / 2, tip),
		Enum.Material.Metal, POLE)
	local headCf = CFrame.lookAt(tip - Vector3.new(0, 2.4, 0), tip - Vector3.new(0, 2.4, 0) + arm.dir)
	part(root, "SignalHead", Vector3.new(1.3, 3.8, 1.0), headCf, Enum.Material.SmoothPlastic, SIGNAL_BODY)
	for i, c in ipairs({ Color3.fromRGB(255, 40, 30), Color3.fromRGB(255, 190, 30), Color3.fromRGB(40, 230, 90) }) do
		-- static phase: one street green, the cross street red (no cycling)
		local lit = (go and i == 3) or (not go and i == 1)
		part(root, "SignalLamp", Vector3.new(0.85, 0.85, 0.2), headCf * CFrame.new(0, 1.2 - (i - 1) * 1.2, -0.55),
			lit and Enum.Material.Neon or Enum.Material.SmoothPlastic, lit and c or c:Lerp(Color3.new(0, 0, 0), 0.7))
	end
	signals += 1
end

-- one real intersection is often several county vertices (dual carriageways,
-- offset centrelines): decide signals first, then keep stop signs and
-- duplicate name signs away from them
local function controlOf(n)
	local mainNames, distinct, seen = 0, 0, {}
	for _, arm in ipairs(n.arms) do
		if not seen[arm.seg.name] then
			seen[arm.seg.name] = true
			distinct += 1
			if arm.seg.rank >= 2 then mainNames += 1 end
		end
	end
	return #n.arms >= 3 and distinct >= 2 and mainNames >= 2
end
local signalGrid = {}
for _, n in pairs(nodes) do
	if controlOf(n) then
		local k = math.floor(n.p.X / 100) .. ":" .. math.floor(n.p.Z / 100)
		signalGrid[k] = signalGrid[k] or {}
		local names = {}
		for _, arm in ipairs(n.arms) do names[arm.seg.name] = true end
		table.insert(signalGrid[k], { p = n.p, names = names })
	end
end
-- within d of a signalled node, or within `shared` of one that has one of
-- `names` among its arms (the 9th / Kerlin / Concord junction is several nodes)
local function nearSignal(p, d, names, shared)
	local gx, gz = math.floor(p.X / 100), math.floor(p.Z / 100)
	for ix = gx - 2, gx + 2 do
		for iz = gz - 2, gz + 2 do
			for _, q in ipairs(signalGrid[ix .. ":" .. iz] or {}) do
				if q.p ~= p then
					local dist = (q.p - p).Magnitude
					if dist < d then return true end
					if names and shared and dist < shared then
						for name in pairs(names) do
							if q.names[name] then return true end
						end
					end
				end
			end
		end
	end
	return false
end
local bladeSeen = {}
local function bladeDuplicate(p, a, b)
	local pair = a < b and (a .. "|" .. b) or (b .. "|" .. a)
	for _, q in ipairs(bladeSeen[pair] or {}) do
		if (q - p).Magnitude < 90 then return true end
	end
	bladeSeen[pair] = bladeSeen[pair] or {}
	table.insert(bladeSeen[pair], p)
	return false
end

local done = 0
for _, n in pairs(nodes) do
	local names, distinct = {}, 0
	for _, arm in ipairs(n.arms) do
		if not names[arm.seg.name] then
			names[arm.seg.name] = true
			distinct += 1
		end
	end
	if #n.arms >= 3 or (#n.arms == 2 and distinct == 2 and math.abs(n.arms[1].dir:Dot(n.arms[2].dir)) < 0.7) then
		table.insert(junctionPoints, n.p)
	end
	if #n.arms >= 3 and distinct >= 2 then
		-- street-name blades: most perpendicular pair of differently-named arms
		local bestA, bestB, bestScore
		for i = 1, #n.arms do
			for j = i + 1, #n.arms do
				local a, b = n.arms[i], n.arms[j]
				if a.seg.name ~= b.seg.name then
					local score = math.abs(a.dir:Dot(b.dir))
					if not bestScore or score < bestScore then bestA, bestB, bestScore = a, b, score end
				end
			end
		end
		if bestA and bestScore < 0.8 and not bladeDuplicate(n.p, bestA.seg.name, bestB.seg.name) then
			bladeSign(n, bestA, bestB)
		end

		-- control: signal / two-way stop / all-way stop
		local mainNames, maxRank, minRank = {}, 0, math.huge
		for _, arm in ipairs(n.arms) do
			maxRank = math.max(maxRank, arm.seg.rank)
			minRank = math.min(minRank, arm.seg.rank)
			if arm.seg.rank >= 2 then mainNames[arm.seg.name] = true end
		end
		local mains = 0
		for _ in pairs(mainNames) do mains += 1 end
		-- a big signalled junction is several county nodes (9th / Kerlin /
		-- Concord): a node with a main-road arm near a signal belongs to it
		local armNames = {}
		for _, arm in ipairs(n.arms) do armNames[arm.seg.name] = true end
		if mains < 2 and nearSignal(n.p, 70, armNames, 160) then
			-- part of a signalled intersection: no stop signs
		elseif mains >= 2 then
			local axis = n.arms[1].dir
			for _, arm in ipairs(n.arms) do signal(n, arm, math.abs(arm.dir:Dot(axis)) > 0.7) end
		elseif maxRank > minRank then
			for _, arm in ipairs(n.arms) do
				if arm.seg.rank < maxRank then stopSign(n, arm) end
			end
		elseif #n.arms == 3 then
			-- T junction: the stem is the arm least aligned with the other two
			local stem, worst
			for _, arm in ipairs(n.arms) do
				local best = 1
				for _, o in ipairs(n.arms) do
					if o ~= arm then best = math.min(best, arm.dir:Dot(o.dir)) end
				end
				-- through arms have a near-opposite partner (dot ~ -1)
				if not worst or best > worst then stem, worst = arm, best end
			end
			if stem then stopSign(n, stem) end
		else
			for _, arm in ipairs(n.arms) do stopSign(n, arm) end
		end
	end
	done += 1
	if done % 300 == 0 then task.wait() end
end

-- ---------------------------------------------------------------------------
-- 3. street lights: cobra heads at the curb
local GRID = 120
local grid = {}
local function gridKey(x, z) return math.floor(x / GRID) .. ":" .. math.floor(z / GRID) end
local function nearLight(p, minDist)
	local gx, gz = math.floor(p.X / GRID), math.floor(p.Z / GRID)
	for ix = gx - 1, gx + 1 do
		for iz = gz - 1, gz + 1 do
			for _, q in ipairs(grid[ix .. ":" .. iz] or {}) do
				if (q - p).Magnitude < minDist then return true end
			end
		end
	end
	return false
end
local junctionGrid = {}
for _, p in ipairs(junctionPoints) do
	local k = gridKey(p.X, p.Z)
	junctionGrid[k] = junctionGrid[k] or {}
	table.insert(junctionGrid[k], p)
end
local function nearJunction(p, d)
	local gx, gz = math.floor(p.X / GRID), math.floor(p.Z / GRID)
	for ix = gx - 1, gx + 1 do
		for iz = gz - 1, gz + 1 do
			for _, q in ipairs(junctionGrid[ix .. ":" .. iz] or {}) do
				if (q - p).Magnitude < d then return true end
			end
		end
	end
	return false
end

table.sort(segments, function(a, b) return (a.b - a.a).Magnitude > (b.b - b.a).Magnitude end)
local SPACING = 150
local lights = 0
local LAMP = Color3.fromRGB(255, 214, 150)
for i, seg in ipairs(segments) do
	if seg.sidewalk then
		local d = seg.b - seg.a
		local len = d.Magnitude
		local dir = d / len
		local side = (math.floor((seg.a.X + seg.a.Z) / 97) % 2 == 0) and 1 or -1
		local s = 30
		while s < len - 20 do
			local c = seg.a + dir * s
			local outward = rightOf(dir) * side
			local p = c + outward * (seg.half + 1.2)
			if not nearJunction(c, seg.half + 22) and not nearLight(p, SPACING * 0.8) then
				local y = surfaceY(p.X, p.Z)
				-- not under a rail bridge (the pole would stand up through the deck)
				if y and #railBeds > 0
					and Workspace:Raycast(Vector3.new(p.X, y + 1, p.Z), Vector3.new(0, 26, 0), railParams) then
					y = nil
				end
				if y then
					local H = 22
					part(root, "LightPole", Vector3.new(0.55, H, 0.55), CFrame.new(p.X, y + H / 2, p.Z), Enum.Material.Metal, POLE)
					local top = Vector3.new(p.X, y + H - 0.4, p.Z)
					local tip = top - outward * 6 + Vector3.new(0, 0.8, 0)
					part(root, "LightArm", Vector3.new(0.35, 0.35, (tip - top).Magnitude), CFrame.lookAt((top + tip) / 2, tip),
						Enum.Material.Metal, POLE)
					local head = part(root, "LightHead", Vector3.new(1.4, 0.5, 2.6),
						CFrame.lookAt(tip, tip - outward) * CFrame.new(0, -0.2, -0.8), Enum.Material.SmoothPlastic,
						Color3.fromRGB(150, 152, 150))
					local lens = part(root, "LightLens", Vector3.new(1.0, 0.12, 1.8), head.CFrame * CFrame.new(0, -0.3, 0),
						Enum.Material.Neon, LAMP)
					local light = Instance.new("SpotLight")
					light.Face = Enum.NormalId.Bottom
					light.Angle = 120
					light.Range = 40
					light.Brightness = 1.6
					light.Color = LAMP
					light.Parent = lens
					local k = gridKey(p.X, p.Z)
					grid[k] = grid[k] or {}
					table.insert(grid[k], p)
					lights += 1
				end
			end
			s += SPACING
		end
	end
	if i % 500 == 0 then task.wait() end
end

print(("[ChesterWorld StreetFurniture] nameSigns=%d stopSigns=%d signals=%d lights=%d parts=%d")
	:format(blades, stops, signals, lights, count))
Workspace:SetAttribute("CW_StreetFurnitureComplete", true)
