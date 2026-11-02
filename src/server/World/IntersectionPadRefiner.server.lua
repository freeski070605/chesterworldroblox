-- ChesterWorld - IntersectionPadRefiner.server.lua
--
-- Replaces TileBuilderV2's temporary square intersection pads with compact
-- convex polygons derived from the ACTUAL rendered road approaches.
--
-- Why this exists:
--   TileBuilderV2 now owns road geometry correctly, but an axis-aligned square
--   pad still looks wrong at angled/T/offset Chester intersections.
--
-- This refiner:
--   * waits until all 102 tiles are built
--   * indexes the endpoints of rendered ground-road Parts
--   * finds the real approach arms around each intersection pad
--   * builds a convex asphalt prism from those approach widths/directions
--   * keeps existing road approaches, sidewalks, crosswalks and signs
--   * destroys the old square pad only after the polygon mesh succeeds
--
-- It does NOT move roads, Terrain, buildings, bridges or sidewalks.

local AssetService = game:GetService("AssetService")
local Workspace = game:GetService("Workspace")

local world = Workspace:WaitForChild("ChesterWorld")

while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do
	task.wait(0.20)
end

local GRID_SIZE = 72
local ENDPOINT_PAD_EXTRA = 8
local ROAD_OVERLAP = 1.8
local LATERAL_OVERLAP = 0.65
local MIN_POLYGON_AREA = 8

local endpointGrid = {}

local function gridCoord(v)
	return math.floor(v / GRID_SIZE)
end

local function gridKey(gx, gz)
	return tostring(gx) .. ":" .. tostring(gz)
end

local function horizontal(v)
	local h = Vector3.new(v.X, 0, v.Z)
	if h.Magnitude < 0.001 then
		return nil
	end
	return h.Unit
end

local function insertEndpoint(point, dir, width, street, sourcePart)
	local key = gridKey(gridCoord(point.X), gridCoord(point.Z))
	local bucket = endpointGrid[key]
	if not bucket then
		bucket = {}
		endpointGrid[key] = bucket
	end

	table.insert(bucket, {
		point = point,
		dir = dir,
		width = width,
		street = street,
		part = sourcePart,
	})
end

local function roadLongAxis(part)
	-- TileBuilderV2 road strips always store width on X and length on Z.
	local axis = horizontal(part.CFrame.LookVector)
	if not axis then
		return nil, nil
	end
	return axis, part.Size.Z
end

local roadPartCount = 0

for _, tile in ipairs(world:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, part in ipairs(roads:GetDescendants()) do
			if part:IsA("BasePart") then
				local grade = tonumber(part:GetAttribute("CW_GradeLevel")) or 0
				local bridge = part:GetAttribute("CW_Bridge") == true
				local tunnel = part:GetAttribute("CW_Tunnel") == true

				-- Intersection pads exist only at at-grade nodes. Do not let an
				-- overpass/tunnel become an arm of the ground intersection polygon.
				if grade == 0 and not bridge and not tunnel then
					local axis, length = roadLongAxis(part)
					if axis and length and length > 0.1 then
						local half = length / 2
						local pA = part.Position - axis * half
						local pB = part.Position + axis * half
						local width = tonumber(part:GetAttribute("RoadWidthStuds")) or part.Size.X
						local street = tostring(part:GetAttribute("ChesterStreet") or part.Name or "")

						-- Direction points AWAY from the endpoint into the road corridor.
						insertEndpoint(pA, axis, width, street, part)
						insertEndpoint(pB, -axis, width, street, part)
						roadPartCount += 1
					end
				end
			end
		end
	end
end

local function nearbyEndpoints(center, radius)
	local result = {}
	local minGX = gridCoord(center.X - radius)
	local maxGX = gridCoord(center.X + radius)
	local minGZ = gridCoord(center.Z - radius)
	local maxGZ = gridCoord(center.Z + radius)

	for gx = minGX, maxGX do
		for gz = minGZ, maxGZ do
			local bucket = endpointGrid[gridKey(gx, gz)]
			if bucket then
				for _, endpoint in ipairs(bucket) do
					local dx = endpoint.point.X - center.X
					local dz = endpoint.point.Z - center.Z
					local distance = math.sqrt(dx * dx + dz * dz)
					if distance <= radius then
						table.insert(result, endpoint)
					end
				end
			end
		end
	end

	return result
end

local function directionKey(street, dir)
	local qx = math.floor(dir.X * 16 + (dir.X >= 0 and 0.5 or -0.5))
	local qz = math.floor(dir.Z * 16 + (dir.Z >= 0 and 0.5 or -0.5))
	return string.upper(street) .. ":" .. tostring(qx) .. ":" .. tostring(qz)
end

local function dedupeArms(center, endpoints, searchRadius)
	local armMap = {}

	for _, endpoint in ipairs(endpoints) do
		local radial = horizontal(endpoint.point - center)
		if radial then
			-- Endpoint should lie near the pad perimeter and the road should
			-- continue outward in roughly the same direction.
			local alignment = radial:Dot(endpoint.dir)
			local distance = Vector2.new(
				endpoint.point.X - center.X,
				endpoint.point.Z - center.Z
			).Magnitude

			if alignment >= 0.70 and distance <= searchRadius then
				local key = directionKey(endpoint.street, radial)
				local existing = armMap[key]

				-- Adaptive road splitting can place more than one endpoint from
				-- the same approach inside the search radius. The true intersection
				-- endpoint is the CLOSEST valid one to the pad center. If two are
				-- effectively tied, keep the wider rendered road.
				if
					not existing
					or distance < existing.distance - 0.25
					or (
						math.abs(distance - existing.distance) <= 0.25
						and endpoint.width > existing.width
					)
				then
					armMap[key] = {
						dir = radial,
						width = endpoint.width,
						street = endpoint.street,
						distance = distance,
					}
				end
			end
		end
	end

	local arms = {}
	for _, arm in pairs(armMap) do
		table.insert(arms, arm)
	end

	table.sort(arms, function(a, b)
		return math.atan2(a.dir.Z, a.dir.X) < math.atan2(b.dir.Z, b.dir.X)
	end)

	return arms
end

local function cross2(a, b, c)
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

local function convexHull(points)
	if #points < 3 then
		return points
	end

	local unique = {}
	local keyed = {}

	for _, p in ipairs(points) do
		local key = tostring(math.floor(p.X * 100 + 0.5)) .. ":" .. tostring(math.floor(p.Y * 100 + 0.5))
		if not keyed[key] then
			keyed[key] = true
			table.insert(unique, p)
		end
	end

	if #unique < 3 then
		return unique
	end

	table.sort(unique, function(a, b)
		if a.X == b.X then
			return a.Y < b.Y
		end
		return a.X < b.X
	end)

	local lower = {}
	for _, p in ipairs(unique) do
		while #lower >= 2 and cross2(lower[#lower - 1], lower[#lower], p) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end

	local upper = {}
	for i = #unique, 1, -1 do
		local p = unique[i]
		while #upper >= 2 and cross2(upper[#upper - 1], upper[#upper], p) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end

	table.remove(lower)
	table.remove(upper)

	for _, p in ipairs(upper) do
		table.insert(lower, p)
	end

	return lower
end

local function polygonArea(points)
	local area = 0
	for i = 1, #points do
		local a = points[i]
		local b = points[(i % #points) + 1]
		area += a.X * b.Y - b.X * a.Y
	end
	return math.abs(area) * 0.5
end

local function polygonFromArms(center, arms)
	local points = {}

	for _, arm in ipairs(arms) do
		local dir = arm.dir
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local reach = arm.distance + ROAD_OVERLAP
		local halfWidth = arm.width / 2 + LATERAL_OVERLAP
		local nose = center + dir * reach

		table.insert(points, Vector2.new(
			nose.X + perp.X * halfWidth,
			nose.Z + perp.Z * halfWidth
		))
		table.insert(points, Vector2.new(
			nose.X - perp.X * halfWidth,
			nose.Z - perp.Z * halfWidth
		))
	end

	return convexHull(points)
end

local function planeYAt(pad, x, z, topSurface)
	local normal = pad.CFrame.UpVector
	local planePoint = pad.Position

	if topSurface then
		planePoint += normal * (pad.Size.Y / 2 + 0.025)
	end

	if math.abs(normal.Y) < 0.001 then
		return planePoint.Y
	end

	return planePoint.Y
		- (
			normal.X * (x - planePoint.X)
			+ normal.Z * (z - planePoint.Z)
		) / normal.Y
end

local function makePolygonMesh(pad, polygon)
	local editable = AssetService:CreateEditableMesh()
	if not editable then
		return nil, "CreateEditableMesh returned nil"
	end

	local centerX = pad.Position.X
	local centerY = pad.Position.Y
	local centerZ = pad.Position.Z
	local thickness = math.max(pad.Size.Y, 0.45)

	local topIds = {}
	local bottomIds = {}

	for i, p in ipairs(polygon) do
		local topY = planeYAt(pad, p.X, p.Y, true)
		local bottomY = topY - thickness

		topIds[i] = editable:AddVertex(Vector3.new(
			p.X - centerX,
			topY - centerY,
			p.Y - centerZ
		))

		bottomIds[i] = editable:AddVertex(Vector3.new(
			p.X - centerX,
			bottomY - centerY,
			p.Y - centerZ
		))
	end

	-- Convex hull is ordered counter-clockwise. Fan triangulation is exact.
	for i = 2, #polygon - 1 do
		editable:AddTriangle(topIds[1], topIds[i], topIds[i + 1])
		editable:AddTriangle(bottomIds[1], bottomIds[i + 1], bottomIds[i])
	end

	for i = 1, #polygon do
		local j = (i % #polygon) + 1
		editable:AddTriangle(topIds[i], bottomIds[i], bottomIds[j])
		editable:AddTriangle(topIds[i], bottomIds[j], topIds[j])
	end

	local meshPart
	local ok, err = pcall(function()
		meshPart = AssetService:CreateMeshPartAsync(
			Content.fromObject(editable),
			{ CollisionFidelity = Enum.CollisionFidelity.Hull }
		)
	end)

	editable:Destroy()

	if not ok or not meshPart then
		return nil, tostring(err or "CreateMeshPartAsync returned nil")
	end

	meshPart.Name = "Intersection"
	meshPart.Anchored = true
	meshPart.CanCollide = true
	meshPart.CanTouch = true
	meshPart.CanQuery = true
	meshPart.CastShadow = true
	meshPart.DoubleSided = true
	meshPart.Material = pad.Material
	meshPart.Color = pad.Color
	meshPart.Size = meshPart.MeshSize
	meshPart.CFrame = CFrame.new(centerX, centerY, centerZ)
	meshPart:SetAttribute("CW_IntersectionPad", true)
	meshPart:SetAttribute("CW_IntersectionPolygon", true)
	meshPart:SetAttribute("CW_GradeLevel", 0)

	local label = pad:GetAttribute("Intersection")
	if label then
		meshPart:SetAttribute("Intersection", label)
	end

	return meshPart, nil
end

local pads = {}

for _, tile in ipairs(world:GetChildren()) do
	local intersections = tile:FindFirstChild("Intersections")
	if intersections then
		for _, pad in ipairs(intersections:GetChildren()) do
			if pad:IsA("BasePart") and pad:GetAttribute("CW_IntersectionPad") == true then
				table.insert(pads, pad)
			end
		end
	end
end

local refined = 0
local skipped = 0
local failed = 0
local totalArms = 0

for index, pad in ipairs(pads) do
	local center = pad.Position
	local searchRadius = math.max(pad.Size.X, pad.Size.Z) * 0.78 + ENDPOINT_PAD_EXTRA
	local endpoints = nearbyEndpoints(center, searchRadius)
	local arms = dedupeArms(center, endpoints, searchRadius)

	if #arms >= 2 then
		local polygon = polygonFromArms(center, arms)

		if #polygon >= 3 and polygonArea(polygon) >= MIN_POLYGON_AREA then
			local meshPart, err = makePolygonMesh(pad, polygon)

			if meshPart then
				meshPart.Parent = pad.Parent
				pad:Destroy()
				refined += 1
				totalArms += #arms
			else
				failed += 1
				warn(("[ChesterWorld IntersectionPadRefiner] %s failed: %s"):format(
					pad:GetFullName(),
					tostring(err)
				))
			end
		else
			skipped += 1
		end
	else
		skipped += 1
	end

	if index % 40 == 0 then
		task.wait()
	end
end

Workspace:SetAttribute("CW_IntersectionPadRefineComplete", true)

print(("[ChesterWorld IntersectionPadRefiner] pads=%d refined=%d skipped=%d failed=%d roadPartsIndexed=%d armsUsed=%d"):format(
	#pads,
	refined,
	skipped,
	failed,
	roadPartCount,
	totalArms
))
