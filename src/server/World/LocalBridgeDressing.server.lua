-- Structure under elevated local streets (city streets over I-95 / I-476,
-- county bridges over Chester Creek and the rail lines, short ramps).
--
-- HighwayInfrastructure dresses the freeway spans (deck, fascia, barriers,
-- abutments, piers) from HighwayProfile's classification. The road-tile
-- bridges lifted by RoadTerrainConformer (BridgeDeck / HighwayRamp /
-- RegistryOverpass) had almost nothing under them: audit 2026-11-06 found
-- 188 elevated local pieces floating with no deck, 118 with no barrier.
--
-- For every street piece standing more than LIFT_MIN studs above the ground
-- (or water) under it:
--   * a concrete deck slab under the pavement, and steel stringers when the
--     opening is tall enough to see them;
--   * concrete parapets on both edges where the piece has none (outside the
--     sidewalk when one runs on the bridge);
-- and along each continuous run of such pieces (same street, joined ends):
--   * an abutment wall where the run meets the ground,
--   * a twin-column pier bent every PIER_SPACING studs that is not standing on
--     another road or track (the opening stays clear).
-- Built after RoadTerrainClear so the ground under the bridge is final.
-- Sets CW_LocalBridgesDressed.
local Workspace = game:GetService("Workspace")

while Workspace:GetAttribute("CW_HighwayFinishComplete") ~= true do task.wait(0.5) end
local deadline = os.clock() + 150
while Workspace:GetAttribute("CW_RoadTerrainCleared") ~= true and os.clock() < deadline do task.wait(0.5) end
if Workspace:FindFirstChild("ChesterLocalBridges") then return end
local root = Instance.new("Folder")
root.Name = "ChesterLocalBridges"
root.Parent = Workspace
local world = Workspace:WaitForChild("ChesterWorld")

local LIFT_MIN = 3.5
local PIER_SPACING = 80
local CONCRETE = Color3.fromRGB(168, 166, 160)
local STEEL = Color3.fromRGB(96, 104, 110)

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Workspace.Terrain }
terrainParams.IgnoreWater = false
local bedParams = RaycastParams.new()
bedParams.FilterType = Enum.RaycastFilterType.Include
bedParams.FilterDescendantsInstances = { Workspace.Terrain }
bedParams.IgnoreWater = true

local roadFolders, walkFolders = {}, {}
for _, tile in ipairs(world:GetChildren()) do
	for _, name in ipairs({ "Roads", "Intersection", "Intersections" }) do
		local f = tile:FindFirstChild(name)
		if f then table.insert(roadFolders, f) end
	end
	local s = tile:FindFirstChild("Sidewalks")
	if s then table.insert(walkFolders, s) end
end
local roadParams = RaycastParams.new()
roadParams.FilterType = Enum.RaycastFilterType.Include
roadParams.FilterDescendantsInstances = roadFolders
local walkOverlap = OverlapParams.new()
walkOverlap.FilterType = Enum.RaycastFilterType.Include
walkOverlap.FilterDescendantsInstances = walkFolders

local count = 0
local function part(name, size, cframe, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = root
	count += 1
	if count % 300 == 0 then task.wait() end
	return p
end

local function groundUnder(point)
	local hit = Workspace:Raycast(point, Vector3.new(0, -600, 0), terrainParams)
	return hit and hit.Position.Y or nil
end

-- existing barriers / parapets / fences near a piece (HighwayInfrastructure,
-- OverpassFencing, RegistryOverpass): do not double them
local BARRIER_WORDS = { "Parapet", "Barrier", "Fence", "Guardrail", "BridgeRail" }
local function hasBarrier(road)
	for _, q in ipairs(Workspace:GetPartBoundsInRadius(road.Position, road.Size.X / 2 + 7)) do
		for _, w in ipairs(BARRIER_WORDS) do
			if string.find(q.Name, w, 1, true) and math.abs(q.Position.Y - road.Position.Y) < 8 then
				return true
			end
		end
	end
	return false
end

-- 1. elevated street pieces
local pieces = {}
local scanned = 0
for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, road in ipairs(roads:GetChildren()) do
			scanned += 1
			if scanned % 500 == 0 then task.wait() end
			if road:IsA("BasePart") and road.Name ~= "Rail" and road.Transparency < 1
				and road:GetAttribute("CW_ElevationOwner") ~= "HighwayProfile"
				and road:GetAttribute("CW_Tunnel") ~= true then
				local g = groundUnder(road.Position)
				local bottom = road.Position.Y - road.Size.Y / 2
				if g and bottom - g > LIFT_MIN then
					table.insert(pieces, { road = road, height = bottom - g })
				end
			end
		end
	end
end

-- 2. deck, stringers, parapets per piece
local decks, stringers, parapets = 0, 0, 0
for _, rec in ipairs(pieces) do
	local road = rec.road
	local cf, size = road.CFrame, road.Size
	local w, len = size.X, size.Z
	-- sidewalks carried on the bridge (RegistryOverpass lifts them with the street)
	local walk = {}
	for side = -1, 1, 2 do
		local probe = cf * Vector3.new(side * (w / 2 + 2.6), 0, 0)
		walk[side] = #Workspace:GetPartBoundsInBox(CFrame.new(probe), Vector3.new(2, 3, 2), walkOverlap) > 0
	end
	local extraL, extraR = walk[-1] and 5.1 or 0, walk[1] and 5.1 or 0
	part("LocalBridgeDeck", Vector3.new(w + 1.6 + extraL + extraR, 1.6, len + 0.3),
		cf * CFrame.new((extraR - extraL) / 2, -size.Y / 2 - 0.8, 0), CONCRETE)
	decks += 1
	if rec.height > 6 then
		for _, f in ipairs({ -0.38, 0, 0.38 }) do
			part("LocalBridgeStringer", Vector3.new(0.9, 3.2, len + 0.3), cf * CFrame.new(w * f, -size.Y / 2 - 1.6 - 1.6, 0),
				STEEL, Enum.Material.Metal)
			stringers += 1
		end
	end
	if not hasBarrier(road) then
		for side = -1, 1, 2 do
			-- a sidewalk on the bridge puts the parapet outside it
			local off = w / 2 + (walk[side] and 5.6 or 0.5)
			part("LocalBridgeParapet", Vector3.new(1.0, 2.8, len + 0.2), cf * CFrame.new(side * off, size.Y / 2 + 1.2, 0), CONCRETE)
			parapets += 1
		end
	end
end

-- 3. runs of joined pieces of one street: abutments at the ends, piers inside
local function ends(road)
	local half = road.CFrame.LookVector * road.Size.Z / 2
	return road.Position - half, road.Position + half
end
local byKey = {}
local function key(p) return math.floor(p.X / 3 + 0.5) .. ":" .. math.floor(p.Z / 3 + 0.5) end
for _, rec in ipairs(pieces) do
	rec.a, rec.b = ends(rec.road)
	for _, p in ipairs({ rec.a, rec.b }) do
		local k = key(p)
		byKey[k] = byKey[k] or {}
		table.insert(byKey[k], rec)
	end
end
local function neighbours(rec, p)
	local out = {}
	for _, o in ipairs(byKey[key(p)] or {}) do
		if o ~= rec and o.road:GetAttribute("ChesterStreet") == rec.road:GetAttribute("ChesterStreet") then
			table.insert(out, o)
		end
	end
	return out
end

local abutments, piers = 0, 0
local function bent(point, dir, road, topY, wide)
	-- not on another road / track: the opening below must stay clear
	local below = Workspace:Raycast(Vector3.new(point.X, topY - 2, point.Z), Vector3.new(0, -400, 0), roadParams)
	local bed = Workspace:Raycast(Vector3.new(point.X, topY - 2, point.Z), Vector3.new(0, -400, 0), bedParams)
	if not bed then return false end
	if below and below.Position.Y > bed.Position.Y - 1 and below.Instance ~= road then return false end
	local bottom = bed.Position.Y - 2
	local h = topY - bottom
	if h < 3 then return false end
	local look = CFrame.lookAt(Vector3.zero, Vector3.new(dir.X, 0, dir.Z)).Rotation
	local right = Vector3.new(-dir.Z, 0, dir.X)
	if wide then
		part("LocalBridgeAbutment", Vector3.new(road.Size.X + 3, h, 3.5),
			CFrame.new(point.X, (topY + bottom) / 2, point.Z) * look, CONCRETE)
	else
		for side = -1, 1, 2 do
			local c = point + right * side * math.max(road.Size.X / 2 - 2.5, 1.5)
			part("LocalBridgePier", Vector3.new(2.6, h, 2.6), CFrame.new(c.X, (topY + bottom) / 2, c.Z) * look, CONCRETE)
		end
		part("LocalBridgePierCap", Vector3.new(road.Size.X + 1, 2.2, 3.2),
			CFrame.new(point.X, topY - 1.1, point.Z) * look, CONCRETE)
	end
	return true
end

local visited = {}
for _, start in ipairs(pieces) do
	if not visited[start] then
		-- walk to one end of the run, then collect it in order
		local cur, from, guard = start, nil, 0
		repeat
			local nexts = {}
			for _, p in ipairs({ cur.a, cur.b }) do
				for _, o in ipairs(neighbours(cur, p)) do
					if o ~= from then table.insert(nexts, o) end
				end
			end
			if #nexts == 0 then break end
			from, cur = cur, nexts[1]
			guard += 1
		until guard > 200 or cur == start
		local run, prev = {}, nil
		local node = cur
		guard = 0
		while node and not visited[node] and guard < 400 do
			visited[node] = true
			table.insert(run, node)
			local nxt
			for _, p in ipairs({ node.a, node.b }) do
				for _, o in ipairs(neighbours(node, p)) do
					if not visited[o] then nxt = o end
				end
			end
			prev, node = node, nxt
			guard += 1
		end
		-- abutments at the two free ends of the run
		local first, last = run[1], run[#run]
		for _, rec in ipairs({ first, last }) do
			for _, p in ipairs({ rec.a, rec.b }) do
				if #neighbours(rec, p) == 0 then
					local inward = (rec.road.Position - p)
					inward = Vector3.new(inward.X, 0, inward.Z).Unit
					local at = p + inward * 1.6
					local topY = rec.road.Position.Y - rec.road.Size.Y / 2 - 1.6
					if bent(at, inward, rec.road, topY, true) then abutments += 1 end
				end
			end
			if first == last then break end
		end
		-- piers along the run
		local travelled, nextPier = 0, PIER_SPACING
		for _, rec in ipairs(run) do
			local len = rec.road.Size.Z
			while travelled + len >= nextPier do
				local f = (nextPier - travelled) / len
				local p = rec.road.CFrame * Vector3.new(0, 0, len / 2 - f * len)
				local topY = p.Y - rec.road.Size.Y / 2 - 1.6
				if rec.height > 6 and bent(p, rec.road.CFrame.LookVector, rec.road, topY, false) then
					piers += 1
				end
				nextPier += PIER_SPACING
			end
			travelled += len
		end
	end
end

print(("[ChesterWorld LocalBridges] elevatedPieces=%d decks=%d stringers=%d parapets=%d abutments=%d piers=%d parts=%d")
	:format(#pieces, decks, stringers, parapets, abutments, piers, count))
Workspace:SetAttribute("CW_LocalBridgesDressed", true)
