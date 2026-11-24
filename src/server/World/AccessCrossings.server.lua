-- Vehicle access crossings: road -> curb cut -> sidewalk crossing -> lot.
--
-- Sidewalk Parts sit 0.3 studs above the finished road, but the ground behind
-- them is often 0.6 - 2.5 studs lower (road and walk tops are placed above
-- the centre-line terrain; RoadTerrainClear lowers partial voxels beside
-- them). A car leaving a lot meets the back edge of the walk as a wall.
--
-- At VERIFIED access locations only - mapped OSM surface-parking polygons
-- (ParkingSurfaceData) directly behind a street sidewalk and without a mapped
-- access way, plus WorldData/VerifiedAccessCrossings - this pass:
--   * replaces the original sidewalk collision under the crossing with one
--     curb-cut apron from the finished road edge up to the walk's own height
--     (the original walk Parts are split around it, never covered);
--   * joins the walk's back edge to the lot ground with two eased strips at
--     no more than LOT_GRADE, clearing any Terrain above them.
-- Elsewhere the normal raised curb is untouched. Gas station entrances are
-- owned by GasStationBuilder and skipped. Measured wheel-path steps across
-- every crossing are reported before and after. Sets CW_AccessCrossingsComplete.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("WorldConfig"))
local WorldData = Shared:WaitForChild("WorldData")
local verified = require(WorldData:WaitForChild("VerifiedAccessCrossings"))
local gasStations = require(WorldData:WaitForChild("GasStations"))
local lots = require(script.Parent:WaitForChild("ParkingSurfaceData"))
local Terrain = Workspace.Terrain

local deadline = os.clock() + 600
-- After the final terrain, gas entrances, furniture, trees and the dealership
-- lot exist, so every crossing is checked against what really stands there.
for _, flag in ipairs({ "CW_RoadConformComplete", "CW_RoadTerrainCleared",
	"CW_GasStationsComplete", "CW_ParkingSurfaceComplete", "CW_StreetFurnitureComplete",
	"CW_TreesComplete", "CW_Exit6DealershipReady" }) do
	while Workspace:GetAttribute(flag) ~= true and os.clock() < deadline do task.wait(0.5) end
end
if Workspace:GetAttribute("CW_AccessCrossingsComplete") then return end
local world = Workspace:WaitForChild("ChesterWorld")

local LOT_GRADE = 0.12        -- lot-side transition grade limit
local MAX_LOT_RUN = 24        -- longest lot-side transition, studs
local MAX_DROP = 3.0          -- deeper lots need a retaining wall, not a ramp
local THICK = 0.4
local GAS_CLEAR = 80

local roadFolders, walkFolders = {}, {}
for _, tile in ipairs(world:GetChildren()) do
	for _, name in ipairs({ "Roads", "Intersection", "Intersections" }) do
		local f = tile:FindFirstChild(name)
		if f then table.insert(roadFolders, f) end
	end
	local s = tile:FindFirstChild("Sidewalks")
	if s then table.insert(walkFolders, s) end
end
local roadRay = RaycastParams.new()
roadRay.FilterType = Enum.RaycastFilterType.Include
roadRay.FilterDescendantsInstances = roadFolders
local terrainRay = RaycastParams.new()
terrainRay.FilterType = Enum.RaycastFilterType.Include
terrainRay.FilterDescendantsInstances = { Terrain }
terrainRay.IgnoreWater = false
local walkBox = OverlapParams.new()
walkBox.FilterType = Enum.RaycastFilterType.Include
walkBox.FilterDescendantsInstances = walkFolders
local roadBox = OverlapParams.new()
roadBox.FilterType = Enum.RaycastFilterType.Include
roadBox.FilterDescendantsInstances = roadFolders
local foreignBox = OverlapParams.new()
foreignBox.FilterType = Enum.RaycastFilterType.Exclude
foreignBox.FilterDescendantsInstances = { Terrain, table.unpack(roadFolders) }

local function terrainY(p)
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y + 60, p.Z), Vector3.new(0, -160, 0), terrainRay)
	if hit and hit.Material == Enum.Material.Water then return nil end
	return hit and hit.Position.Y or nil
end
local function roadTop(p, maxBelow)
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y + 3, p.Z), Vector3.new(0, -(3 + maxBelow), 0), roadRay)
	return hit and hit.Position.Y or nil, hit and hit.Instance
end
local function flat(v)
	local h = Vector3.new(v.X, 0, v.Z)
	return h.Magnitude > 1e-3 and h.Unit or nil
end
local function name(p)
	local value = string.lower(tostring(p:GetAttribute("ChesterStreet") or "")):gsub("[^%w%s]", " ")
	value = value:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	for _, suffix in ipairs({ "%s+street$", "%s+st$", "%s+avenue$", "%s+ave$", "%s+road$", "%s+rd$" }) do
		value = value:gsub(suffix, "")
	end
	return value
end
local function isWalk(p)
	return p:IsA("BasePart") and p.CanCollide and p:GetAttribute("CW_TileBuilderSidewalk") == true
end
local ACCESS = { service = true, parking_aisle = true, driveway = true, alley = true }

-- Wheel-sized (r = 0.75) collision profile along a path: largest rise
-- between 0.5-stud samples, the obstacle a car meets.
local wheelParams = RaycastParams.new()
wheelParams.FilterType = Enum.RaycastFilterType.Exclude
local function wheelProfileStep(a, b)
	local ignore = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	wheelParams.FilterDescendantsInstances = ignore
	local run = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	local n = math.max(2, math.ceil(run / 0.5))
	local prev, worstUp, worstDown = nil, 0, 0
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		local hit
		for _ = 1, 6 do
			hit = Workspace:Spherecast(Vector3.new(p.X, p.Y + 10, p.Z), 0.75, Vector3.new(0, -30, 0), wheelParams)
			if hit and not hit.Instance.CanCollide then
				table.insert(ignore, hit.Instance)
				wheelParams.FilterDescendantsInstances = ignore
			else
				break
			end
		end
		local y = hit and hit.Position.Y
		if y and prev then
			worstUp = math.max(worstUp, y - prev)
			worstDown = math.max(worstDown, prev - y)
		end
		prev = y or prev
	end
	return math.max(worstUp, worstDown)
end

local stats = { candidates = 0, built = 0, apronOnly = 0, blocked = 0, noRoad = 0, curbOdd = 0,
	lotTooLow = 0, lotGrade = 0, mappedAccess = 0, gas = 0, noFrontage = 0, walksSplit = 0,
	added = 0, removed = 0, beforeMax = 0, afterMax = 0, beforeSum = 0, afterSum = 0 }
local samples = {}

local function nearGas(p)
	for _, st in ipairs(gasStations) do
		local box = st.box
		if box and (p.X - box[1]) ^ 2 + (p.Z - box[2]) ^ 2 < GAS_CLEAR * GAS_CLEAR then return true end
	end
	return false
end

-- Which side of a walk Part is the road (+1 = RightVector side, -1 = left).
local function roadSide(walk)
	local cf, w = walk.CFrame, walk.Size.X
	local top = (cf * CFrame.new(0, walk.Size.Y / 2, 0)).Position.Y
	local found = {}
	for _, side in ipairs({ -1, 1 }) do
		local probe = cf * Vector3.new(side * (w / 2 + 1.2), 0, 0)
		local y, part = roadTop(Vector3.new(probe.X, top, probe.Z), 1.2)
		if y and part and part.Parent and part.Parent.Name == "Roads" then found[side] = true end
	end
	if found[1] and not found[-1] then return 1 end
	if found[-1] and not found[1] then return -1 end
	return nil
end

local function apronFrame(a, b, along)
	-- Part whose TOP face contains the line a -> b and the walk's own
	-- along-street direction, so its side edges meet the split walk ends.
	local d = b - a
	local look = d - along * d:Dot(along)
	local length = look.Magnitude
	look = look.Unit
	local right = along
	local up = right:Cross(look)
	if up.Y < 0 then right, up = -right, -up end
	local frame = CFrame.fromMatrix((a + b) / 2, right, up)
	return frame * CFrame.new(0, -THICK / 2, 0), length
end

local function makePart(parent, partName, width, a, b, along, id)
	local frame, length = apronFrame(a, b, along)
	local p = Instance.new("Part")
	p.Name = partName
	p.Anchored = true
	p.Size = Vector3.new(width, THICK, length)
	p.CFrame = frame
	p.Material = Config.SIDEWALK_MATERIAL
	p.Color = Config.SIDEWALK_COLOR
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("CW_AccessCrossing", id)
	p:SetAttribute("CW_ElevationOwner", "AccessCrossings")
	p.Parent = parent
	stats.added += 1
	return p
end

-- Split every original sidewalk Part under the apron footprint around it.
local function cutWalks(apron, streetKey)
	for _, walk in ipairs(Workspace:GetPartBoundsInBox(apron.CFrame, apron.Size + Vector3.new(0, 3, 0), walkBox)) do
		if isWalk(walk) and walk.Parent and name(walk) == streetKey then
			local zMin, zMax, xMin, xMax = math.huge, -math.huge, math.huge, -math.huge
			for _, x in ipairs({ -0.5, 0.5 }) do
				for _, z in ipairs({ -0.5, 0.5 }) do
					local p = walk.CFrame:PointToObjectSpace(apron.CFrame * Vector3.new(x * apron.Size.X, 0, z * apron.Size.Z))
					xMin, xMax = math.min(xMin, p.X), math.max(xMax, p.X)
					zMin, zMax = math.min(zMin, p.Z), math.max(zMax, p.Z)
				end
			end
			if xMin < walk.Size.X / 2 and xMax > -walk.Size.X / 2 then
				local half = walk.Size.Z / 2
				local from, to = math.max(-half, zMin), math.min(half, zMax)
				if to - from > 0.05 then
					for _, interval in ipairs({ { -half, from }, { to, half } }) do
						local length = interval[2] - interval[1]
						if length >= 0.5 then
							local rest = walk:Clone()
							rest.Size = Vector3.new(walk.Size.X, walk.Size.Y, length)
							rest.CFrame = walk.CFrame * CFrame.new(0, 0, (interval[1] + interval[2]) / 2)
							rest.Parent = walk.Parent
							stats.added += 1
						end
					end
					walk:Destroy()
					stats.removed += 1
					stats.walksSplit += 1
				end
			end
		end
	end
end

-- Build one crossing at local station zc of a walk Part.
local function buildCrossing(walk, zc, width, id)
	stats.candidates += 1
	local cf = walk.CFrame
	local center = cf * Vector3.new(0, 0, zc)
	if nearGas(center) then stats.gas += 1 return false, "gas" end
	local side = roadSide(walk)
	if not side then stats.noRoad += 1 return false, "noRoad" end
	local tangent = flat(cf.LookVector)
	local out = flat(cf.RightVector * -side) -- toward the lot
	local w = walk.Size.X
	local walkTop = (cf * CFrame.new(0, walk.Size.Y / 2, zc)).Position.Y
	local streetKey = name(walk)
	local gap = Config.SIDEWALK_GAP_STUDS or 0.1
	local frontXZ = Vector3.new(center.X, 0, center.Z) - out * (w / 2 + gap)
	local rTop = roadTop(Vector3.new(frontXZ.X - out.X * 0.6, walkTop + 1, frontXZ.Z - out.Z * 0.6), 3)
	if not rTop then stats.noRoad += 1 return false, "noRoadTop" end
	local curb = walkTop - rTop
	if curb < 0.05 or curb > 0.9 then stats.curbOdd += 1 return false, ("curb=%.2f"):format(curb) end
	local backXZ = Vector3.new(center.X, 0, center.Z) + out * (w / 2)

	-- A mapped access way already serves this frontage.
	for _, road in ipairs(Workspace:GetPartBoundsInBox(CFrame.lookAt(
		Vector3.new(backXZ.X, walkTop, backXZ.Z) + out * 8, Vector3.new(backXZ.X, walkTop, backXZ.Z) + out * 9),
		Vector3.new(width + 20, 8, 18), roadBox)) do
		if ACCESS[string.lower(tostring(road:GetAttribute("CW_RoadClass") or ""))] then
			stats.mappedAccess += 1
			return false, "mappedAccess"
		end
	end

	-- Lot side: smallest run whose grade, crossfall and ground agree.
	local function lotY(d, lateral)
		return terrainY(Vector3.new(backXZ.X, walkTop, backXZ.Z) + out * d + tangent * lateral)
	end
	local near = lotY(1.0, 0)
	if not near then stats.lotTooLow += 1 return false, "noLotGround" end
	local chosen
	if math.abs(near - walkTop) > 0.3 then
		for d = 3, MAX_LOT_RUN do
			local mid, l, r = lotY(d, 0), lotY(d, -width * 0.4), lotY(d, width * 0.4)
			if mid and l and r then
				local delta = mid - walkTop
				if -delta > MAX_DROP then break end
				if math.abs(delta) / d <= LOT_GRADE and math.max(mid, l, r) - math.min(mid, l, r) <= 0.6 then
					local ok = true
					for _, f in ipairs({ 0.25, 0.5, 0.75 }) do
						local e = f * f * (3 - 2 * f)
						local g = lotY(d * f, 0)
						if not g or g < walkTop + delta * e - 3.5 then ok = false break end
					end
					if ok then chosen = { d = d, delta = delta } break end
				end
			end
		end
		if not chosen then
			if near < walkTop - MAX_DROP then stats.lotTooLow += 1 else stats.lotGrade += 1 end
			return false, ("lot near=%.2f walk=%.2f"):format(near, walkTop)
		end
	end

	-- Nothing standing in the crossing (poles, trees, hydrants, buildings).
	local depth = w + gap + (chosen and chosen.d or 0)
	local mid = Vector3.new(center.X, walkTop + 3.6, center.Z) + out * (depth / 2 - w / 2 - gap)
	for _, other in ipairs(Workspace:GetPartBoundsInBox(CFrame.lookAt(mid, mid + out), Vector3.new(width, 6.4, depth), foreignBox)) do
		if other.CanCollide and other.Transparency < 1 and not isWalk(other)
			and other.Parent and other.Parent.Name ~= "Sidewalks" then
			stats.blocked += 1
			return false, "blocked:" .. other:GetFullName():sub(-40)
		end
	end

	local beforeA = Vector3.new(frontXZ.X, rTop, frontXZ.Z) - out * 3
	local beforeB = Vector3.new(backXZ.X, walkTop, backXZ.Z) + out * ((chosen and chosen.d or 0) + 3)
	local before = 0
	for _, lateral in ipairs({ -width * 0.3, 0, width * 0.3 }) do
		before = math.max(before, wheelProfileStep(beforeA + tangent * lateral, beforeB + tangent * lateral))
	end

	local parent = walk.Parent
	local A = Vector3.new(frontXZ.X, rTop, frontXZ.Z)
	local B = Vector3.new(backXZ.X, walkTop, backXZ.Z)
	local along = cf.LookVector
	local apron = makePart(parent, "CurbCut", width, A, B, along, id)
	cutWalks(apron, streetKey)
	if chosen then
		local prev = B
		for i = 1, 2 do
			local t = i / 2
			local e = t * t * (3 - 2 * t)
			local y = walkTop + chosen.delta * e - (i == 2 and 0.05 or 0)
			local point = Vector3.new(backXZ.X, y, backXZ.Z) + out * (chosen.d * t)
			local strip = makePart(parent, "DrivewayApron", width, prev, point, along, id)
			-- Terrain above the transition is ground the strip replaces.
			Terrain:FillBlock(strip.CFrame * CFrame.new(0, THICK / 2 + 4, 0),
				Vector3.new(width, 8, strip.Size.Z), Enum.Material.Air)
			prev = point
		end
	else
		stats.apronOnly += 1
	end

	local after = 0
	for _, lateral in ipairs({ -width * 0.3, 0, width * 0.3 }) do
		after = math.max(after, wheelProfileStep(beforeA + tangent * lateral, beforeB + tangent * lateral))
	end
	stats.built += 1
	stats.beforeMax = math.max(stats.beforeMax, before)
	stats.afterMax = math.max(stats.afterMax, after)
	stats.beforeSum += before
	stats.afterSum += after
	if #samples < 40 then
		table.insert(samples, ("%s (%.0f,%.0f) %s curb=%.2f lotRun=%s lotDelta=%s stepBefore=%.2f stepAfter=%.2f")
			:format(id, center.X, center.Z, streetKey, curb, chosen and tostring(chosen.d) or "0",
				chosen and ("%.2f"):format(chosen.delta) or "0", before, after))
	end
	return true
end

-- Slide along the frontage (within the walk Part) when street furniture or a
-- tree stands in the first position; other rejections are final.
local function tryCrossing(walk, zc, width, id, zMin, zMax)
	local half = walk.Size.Z / 2
	zMin, zMax = math.max(zMin or -half, -half), math.min(zMax or half, half)
	local reason
	for _, offset in ipairs({ 0, 6, -6, 12, -12, 18, -18, 24, -24 }) do
		local z = zc + offset
		if z >= zMin and z <= zMax then
			local ok
			ok, reason = buildCrossing(walk, z, width, id)
			if ok then return true end
			if not string.find(tostring(reason), "^blocked") then return false, reason end
		end
	end
	return false, reason
end

local function inside(x, z, ring)
	local hit, j = false, #ring - 1
	for i = 1, #ring - 1, 2 do
		local xi, zi, xj, zj = ring[i], ring[i + 1], ring[j], ring[j + 1]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then hit = not hit end
		j = i
	end
	return hit
end

local started = os.clock()
local rejections = {}
local function note(id, reason)
	if reason and #rejections < 24 then table.insert(rejections, id .. ":" .. reason) end
end

-- 1. Explicit verified access points.
for _, entry in ipairs(verified) do
	local p = Vector3.new(entry.point[1], 0, entry.point[2])
	local key = string.lower(entry.street)
	local best, bestD, bestZ
	for _, walk in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(p.X, 100, p.Z), Vector3.new(24, 600, 24), walkBox)) do
		if isWalk(walk) and name(walk) == key then
			local lp = walk.CFrame:PointToObjectSpace(Vector3.new(p.X, walk.Position.Y, p.Z))
			local z = math.clamp(lp.Z, -walk.Size.Z / 2, walk.Size.Z / 2)
			local d = (walk.CFrame * Vector3.new(0, 0, z) - Vector3.new(p.X, walk.Position.Y, p.Z)).Magnitude
			if not bestD or d < bestD then best, bestD, bestZ = walk, d, z end
		end
	end
	if best and bestD < 12 then
		local ok, reason = tryCrossing(best, bestZ, entry.width or 16, entry.id)
		if not ok then note(entry.id, reason) end
	else
		stats.noFrontage += 1
		note(entry.id, "noSidewalk")
	end
end

-- 2. Mapped surface-parking polygons directly behind a street sidewalk.
for lotIndex, lot in ipairs(lots) do
	local ring = lot.outline
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, #ring, 2 do
		minX, maxX = math.min(minX, ring[i]), math.max(maxX, ring[i])
		minZ, maxZ = math.min(minZ, ring[i + 1]), math.max(maxZ, ring[i + 1])
	end
	local best -- longest frontage run: {walk, z0, z1}
	local box = CFrame.new((minX + maxX) / 2, 100, (minZ + maxZ) / 2)
	for _, walk in ipairs(Workspace:GetPartBoundsInBox(box, Vector3.new(maxX - minX + 16, 600, maxZ - minZ + 16), walkBox)) do
		if isWalk(walk) and walk.Size.Z >= 4 and name(walk) ~= "" and name(walk) ~= "road" then
			local side = roadSide(walk)
			if side then
				local half = walk.Size.Z / 2
				local runStart, runEnd
				local z = -half + 1
				while z <= half - 1 do
					local probe = walk.CFrame * Vector3.new(-side * (walk.Size.X / 2 + 2), 0, z)
					if inside(probe.X, probe.Z, ring) then
						runStart = runStart or z
						runEnd = z
					elseif runStart then
						if not best or runEnd - runStart > best[3] - best[2] then best = { walk, runStart, runEnd } end
						runStart, runEnd = nil, nil
					end
					z += 2
				end
				if runStart and (not best or runEnd - runStart > best[3] - best[2]) then
					best = { walk, runStart, runEnd }
				end
			end
		end
	end
	if best and best[3] - best[2] >= 8 then
		local runLength = best[3] - best[2] + 2
		local ok, reason = tryCrossing(best[1], (best[2] + best[3]) / 2,
			math.clamp(runLength, 10, 16), "lot:" .. tostring(lot.id), best[2], best[3])
		if not ok then note("lot:" .. tostring(lot.id), reason) end
	end
	if lotIndex % 10 == 0 then task.wait() end
end

print(("[ChesterWorld AccessCrossings] candidates=%d built=%d apronOnly=%d walksSplit=%d partsAdded=%d partsRemoved=%d skipped: mappedAccess=%d gas=%d blocked=%d noRoad=%d curb=%d lotGrade=%d lotTooLow=%d noFrontage=%d seconds=%.1f")
	:format(stats.candidates, stats.built, stats.apronOnly, stats.walksSplit, stats.added, stats.removed,
		stats.mappedAccess, stats.gas, stats.blocked, stats.noRoad, stats.curbOdd, stats.lotGrade,
		stats.lotTooLow, stats.noFrontage, os.clock() - started))
print(("[ChesterWorld AccessCrossings] wheelStep maxBefore=%.2f maxAfter=%.2f meanBefore=%.2f meanAfter=%.2f")
	:format(stats.beforeMax, stats.afterMax, stats.beforeSum / math.max(stats.built, 1),
		stats.afterSum / math.max(stats.built, 1)))
for _, line in ipairs(samples) do print("[ChesterWorld AccessCrossing] " .. line) end
for _, line in ipairs(rejections) do print("[ChesterWorld AccessCrossingSkipped] " .. line) end
Workspace:SetAttribute("CW_AccessCrossingsBuilt", stats.built)
Workspace:SetAttribute("CW_AccessCrossingStepBeforeMax", stats.beforeMax)
Workspace:SetAttribute("CW_AccessCrossingStepAfterMax", stats.afterMax)
Workspace:SetAttribute("CW_AccessCrossingsComplete", true)
