-- ChesterWorld - IntersectionPadRefiner.server.lua
--
-- FINAL INTERSECTION PAD REFINER
--
-- IMPORTANT:
-- The previous refiner tried to infer junction arms from already-trimmed Roblox
-- road Parts. That was unreliable and removed the visible center of many
-- intersections.
--
-- This version rebuilds the SAME raw 102-tile endpoint graph used by
-- TileBuilderV2 and derives each polygon directly from source road directions
-- and widths. The temporary square pad remains in place unless the replacement
-- mesh is built successfully.
--
-- It does NOT move roads, terrain, sidewalks, buildings, bridges, or markings.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WorldConfig = require(Shared:WaitForChild("WorldConfig"))
local WorldData = Shared:WaitForChild("WorldData")
local Tiles = WorldData:WaitForChild("Tiles")

while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do
	task.wait(0.20)
end

local world = Workspace:WaitForChild("ChesterWorld")

local S = WorldConfig.STUDS_PER_METER
local CENTER_X_M = WorldConfig.WORLD_CENTER_X_M
local CENTER_Z_M = WorldConfig.WORLD_CENTER_Z_M

local NODE_GRID = 48
local NODE_MATCH_RADIUS = 8
local MOUTH_FORWARD_OVERLAP = 1.25
local MOUTH_LATERAL_OVERLAP = 0.75
local MIN_POLYGON_AREA = 8

local function sourceToStuds(xMeters, zMeters)
	return
		(xMeters - CENTER_X_M) * S,
		-(zMeters - CENTER_Z_M) * S
end

local function truthy(value)
	if value == true then
		return true
	end

	local text = string.lower(tostring(value or ""))
	return text ~= ""
		and text ~= "0"
		and text ~= "false"
		and text ~= "no"
		and text ~= "none"
		and text ~= "nil"
end

local function gradeLevelForRoad(road)
	local level = tonumber(road.layer) or 0

	if truthy(road.bridge) and level <= 0 then
		level = 1
	elseif truthy(road.tunnel) and level >= 0 then
		level = -1
	end

	return math.clamp(math.round(level), -5, 5)
end

local function endpointKeyFromStuds(x, z, gradeLevel)
	local q = WorldConfig.INTERSECTION_ENDPOINT_QUANTIZE_STUDS
	return
		tostring(math.floor(x / q + 0.5))
		.. ":"
		.. tostring(math.floor(z / q + 0.5))
		.. ":g"
		.. tostring(gradeLevel or 0)
end

local function armKey(name, dir)
	local qx = math.floor(dir.X * 20 + (dir.X >= 0 and 0.5 or -0.5))
	local qz = math.floor(dir.Z * 20 + (dir.Z >= 0 and 0.5 or -0.5))
	return string.upper(name) .. ":" .. tostring(qx) .. ":" .. tostring(qz)
end

local nodes = {}

local function addEndpoint(tileId, xMeters, zMeters, otherXMeters, otherZMeters, road)
	local gradeLevel = gradeLevelForRoad(road)
	if gradeLevel ~= 0 then
		return
	end

	local x, z = sourceToStuds(xMeters, zMeters)
	local ox, oz = sourceToStuds(otherXMeters, otherZMeters)
	local key = endpointKeyFromStuds(x, z, gradeLevel)

	local node = nodes[key]
	if not node then
		node = {
			xSum = 0,
			zSum = 0,
			count = 0,
			maxWidth = 0,
			names = {},
			rawArms = {},
			arms = {},
			ownerTile = tileId,
			isIntersection = false,
			padSize = 0,
		}
		nodes[key] = node
	elseif tileId < node.ownerTile then
		node.ownerTile = tileId
	end

	local width = math.max((tonumber(road.width_m) or 7) * S, 3)
	local name = tostring(road.name or "")

	node.xSum += x
	node.zSum += z
	node.count += 1
	node.maxWidth = math.max(node.maxWidth, width)

	if name ~= "" and name ~= "Road" then
		node.names[name] = true
	end

	local dx = ox - x
	local dz = oz - z
	local length = math.sqrt(dx * dx + dz * dz)

	if length > 0.001 then
		table.insert(node.rawArms, {
			name = name,
			width = width,
			dir = Vector3.new(dx / length, 0, dz / length),
		})
	end
end

local modules = Tiles:GetChildren()
table.sort(modules, function(a, b)
	return a.Name < b.Name
end)

for moduleIndex, module in ipairs(modules) do
	if module:IsA("ModuleScript") then
		local ok, tile = pcall(require, module)
		if ok and tile then
			local tileId = tostring(tile.tile_id or module.Name)

			for roadIndex, road in ipairs(tile.roads or {}) do
				addEndpoint(tileId, road.x1, road.z1, road.x2, road.z2, road)
				addEndpoint(tileId, road.x2, road.z2, road.x1, road.z1, road)

				if roadIndex % 300 == 0 then
					task.wait()
				end
			end
		end
	end

	if moduleIndex % 10 == 0 then
		task.wait()
	end
end

local nodeGrid = {}

local function gridCoord(v)
	return math.floor(v / NODE_GRID)
end

local function gridKey(gx, gz)
	return tostring(gx) .. ":" .. tostring(gz)
end

local graphIntersections = 0

for _, node in pairs(nodes) do
	local distinctNames = 0
	for _ in pairs(node.names) do
		distinctNames += 1
	end

	local armMap = {}
	for _, arm in ipairs(node.rawArms) do
		local key = armKey(arm.name, arm.dir)
		local current = armMap[key]
		if not current or arm.width > current.width then
			armMap[key] = arm
		end
	end

	local arms = {}
	for _, arm in pairs(armMap) do
		table.insert(arms, arm)
	end

	table.sort(arms, function(a, b)
		return math.atan2(a.dir.Z, a.dir.X) < math.atan2(b.dir.Z, b.dir.X)
	end)

	node.rawArms = nil
	node.arms = arms
	node.x = node.xSum / math.max(node.count, 1)
	node.z = node.zSum / math.max(node.count, 1)
	node.padSize = math.clamp(
		node.maxWidth * WorldConfig.INTERSECTION_SIZE_MULTIPLIER,
		WorldConfig.INTERSECTION_MIN_SIZE_STUDS,
		WorldConfig.INTERSECTION_MAX_SIZE_STUDS
	)
	node.isIntersection =
		#arms >= WorldConfig.INTERSECTION_MIN_DEGREE
		or distinctNames >= 2

	if node.isIntersection then
		graphIntersections += 1
		local key = gridKey(gridCoord(node.x), gridCoord(node.z))
		local bucket = nodeGrid[key]
		if not bucket then
			bucket = {}
			nodeGrid[key] = bucket
		end
		table.insert(bucket, node)
	end
end

local function nearestNode(point)
	local gx = gridCoord(point.X)
	local gz = gridCoord(point.Z)
	local best = nil
	local bestDistance = NODE_MATCH_RADIUS

	for ix = gx - 1, gx + 1 do
		for iz = gz - 1, gz + 1 do
			local bucket = nodeGrid[gridKey(ix, iz)]
			if bucket then
				for _, node in ipairs(bucket) do
					local dx = node.x - point.X
					local dz = node.z - point.Z
					local distance = math.sqrt(dx * dx + dz * dz)
					if distance < bestDistance then
						bestDistance = distance
						best = node
					end
				end
			end
		end
	end

	return best, bestDistance
end

local function distanceToSquareEdge(node, dir)
	local half = node.padSize / 2
	local dominant = math.max(math.abs(dir.X), math.abs(dir.Z), 0.001)
	return half / dominant
end

local function cross2(a, b, c)
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

local function convexHull(points)
	if #points < 3 then
		return points
	end

	local unique = {}
	local seen = {}

	for _, p in ipairs(points) do
		local key = tostring(math.floor(p.X * 100 + 0.5))
			.. ":"
			.. tostring(math.floor(p.Y * 100 + 0.5))
		if not seen[key] then
			seen[key] = true
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

local function polygonFromNode(node)
	local points = {}
	local center = Vector3.new(node.x, 0, node.z)

	for _, arm in ipairs(node.arms) do
		local dir = arm.dir
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local mouthDistance = distanceToSquareEdge(node, dir) + MOUTH_FORWARD_OVERLAP
		local halfWidth = arm.width / 2 + MOUTH_LATERAL_OVERLAP
		local mouth = center + dir * mouthDistance

		table.insert(points, Vector2.new(
			mouth.X + perp.X * halfWidth,
			mouth.Z + perp.Z * halfWidth
		))
		table.insert(points, Vector2.new(
			mouth.X - perp.X * halfWidth,
			mouth.Z - perp.Z * halfWidth
		))
	end

	return convexHull(points)
end

local function planeYAt(pad, x, z, topSurface)
	local normal = pad.CFrame.UpVector
	local planePoint = pad.Position

	if topSurface then
		planePoint += normal * (pad.Size.Y / 2 + 0.03)
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
	meshPart:SetAttribute("CW_IntersectionGraphDerived", true)
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
local unmatched = 0
local skipped = 0
local failed = 0
local totalArms = 0

for index, pad in ipairs(pads) do
	local node = nearestNode(pad.Position)

	if not node then
		unmatched += 1
	else
		local polygon = polygonFromNode(node)

		if #polygon < 3 or polygonArea(polygon) < MIN_POLYGON_AREA then
			skipped += 1
		else
			local meshPart, err = makePolygonMesh(pad, polygon)
			if meshPart then
				meshPart.Parent = pad.Parent
				pad:Destroy()
				refined += 1
				totalArms += #node.arms
			else
				failed += 1
				warn(("[ChesterWorld IntersectionPadRefiner] %s failed: %s"):format(
					pad:GetFullName(),
					tostring(err)
				))
			end
		end
	end

	if index % 40 == 0 then
		task.wait()
	end
end

Workspace:SetAttribute("CW_IntersectionPadRefineComplete", true)

print(("[ChesterWorld IntersectionPadRefiner] graphNodes=%d pads=%d refined=%d unmatched=%d skipped=%d failed=%d armsUsed=%d"):format(
	graphIntersections,
	#pads,
	refined,
	unmatched,
	skipped,
	failed,
	totalArms
))
