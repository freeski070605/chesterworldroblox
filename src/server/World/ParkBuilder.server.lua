-- ChesterWorld parks: name signs, walking loops, benches and lamps for each park,
-- and the mapped sports/leisure features (courts, fields, tracks, playgrounds,
-- pools, cemeteries). Data: src/shared/WorldData/Parks.lua (tools/build_parks.py),
-- already in studs, plus the aerial-verified corrections and facilities in
-- src/shared/Exit6VerifiedSports.luau. Runs once the tiles are built.
--
-- Sports surfaces sit on a finished-surface level sampled from the terrain
-- under them (median; fields may follow a <=1% grade along their length), not
-- on the highest sample. The terrain under each surface is conformed at
-- runtime inside the surface plus a short feather ring; columns near roads,
-- sidewalks, buildings, rail or water are never touched, and every write is
-- snapshotted so ServerStorage.Exit6SportsTerrain:Invoke("restore") undoes it.
-- The saved place terrain is never modified.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Parks = require(Shared:WaitForChild("WorldData"):WaitForChild("Parks"))
local VerifiedSports = require(Shared:WaitForChild("Exit6VerifiedSports"))
local SportsMeshes = require(Shared:WaitForChild("Exit6SportsMeshIds"))

while Workspace:GetAttribute("CW_BootstrapComplete") ~= true do task.wait(0.5) end

local Terrain = Workspace.Terrain
local root = Instance.new("Folder")
root.Name = "ChesterParks"
root.Parent = Workspace

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include
terrainParams.FilterDescendantsInstances = { Terrain }
terrainParams.IgnoreWater = true
local function groundY(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 3000, z), Vector3.new(0, -6000, 0), terrainParams)
	return hit and hit.Position.Y or nil
end

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local function rgbOf(t, fallback)
	return t and rgb(t[1], t[2], t[3]) or fallback
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

-- Legacy feature frame (playgrounds, pools): unchanged so those restored
-- features keep their exact placement. Origin at the highest ground sample.
local function frameOfHighest(box)
	local rotation = CFrame.Angles(0, math.rad(box[5]), 0)
	local top
	for ix = -2, 2 do
		for iz = -2, 2 do
			local p = CFrame.new(box[1], 0, box[2]) * rotation * Vector3.new(ix * box[3] / 4, 0, iz * box[4] / 4)
			local y = groundY(p.X, p.Z)
			if y and (not top or y > top) then top = y end
		end
	end
	if not top then return nil end
	return CFrame.new(box[1], top, box[2]) * rotation
end

local SKIRT = 6
local function legacySlab(parent, name, frame, lx, lz, length, width, thick, material, color, lift)
	local skirt = (lift or 0) == 0 and SKIRT or 0
	return counted(part(parent, name, Vector3.new(length, thick + skirt, width),
		frame * CFrame.new(lx, (lift or 0) + (thick - skirt) / 2, lz), material, color))
end

---------------------------------------------------------------------------
-- Mesh visuals (SpecialMesh renders MeshSize * Scale about the mesh bounds
-- centre; offsets come from Exit6SportsMeshIds' measured calibration)
---------------------------------------------------------------------------
-- The uploaded sports meshes carry Blender's primitive unwrap UVs, not the
-- palette UVs (verified from the uploaded hoop's EditableMesh UVs), so the
-- palette texture samples arbitrary colours. Render them untextured in the
-- carrier colour (`color`, default white) until they are re-uploaded.
local function meshVisual(parent, name, id, cf, scale, plain, color)
	if not id or id == "" then return false end
	local carrier = counted(part(parent, name, Vector3.one, cf, Enum.Material.SmoothPlastic, color or WHITE))
	carrier.CanCollide = false
	carrier.CanTouch = false
	carrier.CanQuery = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = "rbxassetid://" .. id
	local textureId = SportsMeshes.textures[id] or SportsMeshes.sportsPalette
	if not plain and not SportsMeshes.plainMeshes and textureId and textureId ~= "" then
		mesh.TextureId = "rbxassetid://" .. textureId
	end
	mesh.Scale = scale
	mesh.Parent = carrier
	return true
end

---------------------------------------------------------------------------
-- Surfaces. A sports frame's origin is the finished playing surface (local
-- y = 0). Base surfaces hang `surfaceSkirt` below it into the conformed
-- terrain; overlays (paint, lines, tints) sit on top and never collide.
---------------------------------------------------------------------------
local surfaceSkirt = 1.6
local function surface(parent, name, frame, lx, lz, length, width, material, color)
	return counted(part(parent, name, Vector3.new(length, surfaceSkirt, width),
		frame * CFrame.new(lx, -surfaceSkirt / 2, lz), material, color))
end

local function overlay(parent, name, frame, lx, lz, length, width, thick, color, lift, material)
	local p = counted(part(parent, name, Vector3.new(length, thick, width),
		frame * CFrame.new(lx, (lift or 0) + thick / 2, lz), material, color))
	p.CanCollide = false
	p.CanQuery = false
	return p
end

local LINE = 0.5
local function lines(parent, frame, length, width, lift, crossXs)
	overlay(parent, "Line", frame, 0, width / 2 - LINE / 2, length, LINE, 0.04, WHITE, lift)
	overlay(parent, "Line", frame, 0, -width / 2 + LINE / 2, length, LINE, 0.04, WHITE, lift)
	overlay(parent, "Line", frame, length / 2 - LINE / 2, 0, LINE, width, 0.04, WHITE, lift)
	overlay(parent, "Line", frame, -length / 2 + LINE / 2, 0, LINE, width, 0.04, WHITE, lift)
	for _, x in ipairs(crossXs or {}) do
		overlay(parent, "Line", frame, x, 0, LINE, width, 0.04, WHITE, lift)
	end
end

local function circleLine(parent, frame, radius, lift, cx)
	local n = 20
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local seg = 2 * math.pi * radius / n + 0.2
		local p = counted(part(parent, "Line", Vector3.new(seg, 0.04, LINE),
			frame * CFrame.new((cx or 0) + math.cos(a) * radius, lift + 0.02, math.sin(a) * radius) * CFrame.Angles(0, -a + math.pi / 2, 0),
			nil, WHITE))
		p.CanCollide = false
		p.CanQuery = false
	end
end

---------------------------------------------------------------------------
-- Terrain: sampling, levels and the bounded, reversible conform
---------------------------------------------------------------------------
local function median(t)
	if #t == 0 then return nil end
	local c = table.clone(t)
	table.sort(c)
	local m = (#c + 1) / 2
	return (c[math.floor(m)] + c[math.ceil(m)]) / 2
end

-- Samples at ~`spacing` studs over the rectangle: list of { lx, lz, y }.
local function sampleBox(box, spacing)
	local flat = CFrame.new(box[1], 0, box[2]) * CFrame.Angles(0, math.rad(box[5]), 0)
	local nx = math.clamp(math.ceil(box[3] / spacing), 2, 24)
	local nz = math.clamp(math.ceil(box[4] / spacing), 2, 16)
	local out = {}
	for i = 0, nx do
		for j = 0, nz do
			local lx, lz = (i / nx - 0.5) * box[3], (j / nz - 0.5) * box[4]
			local p = flat * Vector3.new(lx, 0, lz)
			local y = groundY(p.X, p.Z)
			if y then table.insert(out, { lx, lz, y }) end
		end
	end
	return out
end

-- Finished-surface level: median height; `grade` (fraction) allows a plane
-- along local X fitted by least squares and clamped. Returns a, b (y = a + b*lx).
local function levelOf(box, grade)
	local s = sampleBox(box, 12)
	if #s == 0 then return nil end
	local b = 0
	if grade and grade > 0 then
		local mx, my = 0, 0
		for _, v in ipairs(s) do mx += v[1]; my += v[3] end
		mx, my = mx / #s, my / #s
		local sxy, sxx = 0, 0
		for _, v in ipairs(s) do sxy += (v[1] - mx) * (v[3] - my); sxx += (v[1] - mx) ^ 2 end
		b = sxx > 0 and math.clamp(sxy / sxx, -grade, grade) or 0
	end
	local r = {}
	for _, v in ipairs(s) do table.insert(r, v[3] - b * v[1]) end
	return median(r), b, s
end

local function frameFor(box, a, b)
	return CFrame.new(box[1], a, box[2]) * CFrame.Angles(0, math.rad(box[5]), 0) * CFrame.Angles(0, 0, math.atan(b or 0))
end

local conformEnabled = Workspace:GetAttribute("Exit6SportsConform") ~= false
local CONFORM_INSET = 0.6     -- terrain top under a surface, below its top
local CONFORM_MAX_DELTA = 9   -- never cut or fill a column further than this
local VOXEL = 4

local blockerFolders = {}
local worldFolder = Workspace:FindFirstChild("ChesterWorld")
for _, tile in ipairs(worldFolder and worldFolder:GetChildren() or {}) do
	for _, child in ipairs(tile:GetChildren()) do
		if child:IsA("Folder") and (child.Name == "Roads" or child.Name == "Intersections" or child.Name == "Intersection"
			or child.Name == "Sidewalks" or child.Name == "Buildings" or child.Name == "RailStructures"
			or child.Name == "HighwayStructures") then
			table.insert(blockerFolders, child)
		elseif child:IsA("BasePart") and child.Name:match("^Bridge") then
			table.insert(blockerFolders, child)
		end
	end
end
for _, name in ipairs({ "ChesterLandmarks", "ChesterGasStations", "ChesterLocalBridges" }) do
	local f = Workspace:FindFirstChild(name)
	if f then table.insert(blockerFolders, f) end
end
local blockParams = OverlapParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include
blockParams.FilterDescendantsInstances = blockerFolders
blockParams.MaxParts = 1
local BLOCK_CLEAR = 3

local snapshots = {}
local conformStats = { sites = 0, columns = 0, blocked = 0, water = 0, limited = 0 }

-- Conform terrain under rectangle `box` (or, with shape "oval", the stadium
-- shape inscribed in it: straights plus semicircles of radius width/2) to the
-- plane y = a + b*lx (local X), CONFORM_INSET below it, feathering back to the
-- original ground over `margin` studs outside. Returns columns written.
local function conformTerrain(tag, box, a, b, margin, shape)
	if not conformEnabled then return 0 end
	local cx, cz, L, W = box[1], box[2], box[3], box[4]
	local flat = CFrame.new(cx, 0, cz) * CFrame.Angles(0, math.rad(box[5]), 0)
	local hx, hz = L / 2 + margin, W / 2 + margin
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, c in ipairs({ { hx, hz }, { hx, -hz }, { -hx, hz }, { -hx, -hz } }) do
		local p = flat * Vector3.new(c[1], 0, c[2])
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	local tilt = math.abs(b) * L / 2
	local region = Region3.new(Vector3.new(minX, a - tilt - 24, minZ), Vector3.new(maxX, a + tilt + 24, maxZ)):ExpandToGrid(VOXEL)
	local ok, mats, occ = pcall(function() return Terrain:ReadVoxels(region, VOXEL) end)
	if not ok then warn("[Exit6 Sports] conform read failed", tag, mats) return 0 end
	local size = mats.Size
	local origin = region.CFrame.Position - region.Size / 2
	local origM, origO = {}, {}
	for ix = 1, size.X do
		origM[ix], origO[ix] = {}, {}
		for iy = 1, size.Y do
			origM[ix][iy], origO[ix][iy] = table.clone(mats[ix][iy]), table.clone(occ[ix][iy])
		end
	end
	local AIR, WATER = Enum.Material.Air, Enum.Material.Water
	local function voxelTop(ix, iz)
		for iy = size.Y, 1, -1 do
			local m = mats[ix][iy][iz]
			if m == WATER then return nil, nil, true end
			if m ~= AIR and occ[ix][iy][iz] > 0 then
				return origin.Y + (iy - 1) * VOXEL + occ[ix][iy][iz] * VOXEL, m
			end
		end
	end
	-- The rendered surface is not exactly bottom + occupancy * 4 (measured
	-- +2.0 on Chester terrain); calibrate this site against raycasts so the
	-- finished level is in rendered heights.
	local offsets = {}
	for k = 1, 25 do
		local ix = math.clamp(math.floor(size.X * ((k - 1) % 5 + 0.5) / 5) + 1, 1, size.X)
		local iz = math.clamp(math.floor(size.Z * (math.floor((k - 1) / 5) + 0.5) / 5) + 1, 1, size.Z)
		local h, _, w = voxelTop(ix, iz)
		local r = not w and h and groundY(origin.X + (ix - 0.5) * VOXEL, origin.Z + (iz - 0.5) * VOXEL)
		if r and math.abs(r - h) < 4 then table.insert(offsets, r - h) end
	end
	local renderOffset = median(offsets) or 0
	local written = 0
	for ix = 1, size.X do
		local wx = origin.X + (ix - 0.5) * VOXEL
		for iz = 1, size.Z do
			local wz = origin.Z + (iz - 0.5) * VOXEL
			local l = flat:PointToObjectSpace(Vector3.new(wx, 0, wz))
			local d
			if shape == "oval" then
				local ox = math.max(math.abs(l.X) - (L - W) / 2, 0)
				d = math.max(math.sqrt(ox * ox + l.Z * l.Z) - W / 2, 0)
			else
				local dx = math.max(math.abs(l.X) - L / 2, 0)
				local dz = math.max(math.abs(l.Z) - W / 2, 0)
				d = math.sqrt(dx * dx + dz * dz)
			end
			if d <= margin then
				local h0, top, water = voxelTop(ix, iz)
				if water then
					conformStats.water += 1
				elseif h0 then
					local surfaceY = a + b * math.clamp(l.X, -L / 2, L / 2) - renderOffset
					local target
					if d == 0 then
						target = surfaceY - CONFORM_INSET
					else
						local t = d / margin
						t = t * t * (3 - 2 * t)
						target = (surfaceY - 0.25) * (1 - t) + h0 * t
					end
					if math.abs(target - h0) > CONFORM_MAX_DELTA then
						conformStats.limited += 1
					elseif math.abs(target - h0) > 0.05 then
						if #Workspace:GetPartBoundsInBox(CFrame.new(wx, math.max(h0, target) + 4, wz),
							Vector3.new(VOXEL + 2 * BLOCK_CLEAR, 24, VOXEL + 2 * BLOCK_CLEAR), blockParams) > 0 then
							conformStats.blocked += 1
						else
							-- under a surface: no grass decoration poking through
							local fill = d == 0 and Enum.Material.Ground or top
							for iy = 1, size.Y do
								local yb = origin.Y + (iy - 1) * VOXEL
								local m = mats[ix][iy][iz]
								if yb + VOXEL <= target then
									if m == AIR or occ[ix][iy][iz] <= 0 or (d == 0 and yb + 2 * VOXEL > target) then
										mats[ix][iy][iz] = fill
									end
									occ[ix][iy][iz] = 1
								elseif yb < target then
									mats[ix][iy][iz] = (d == 0 or m == AIR) and fill or m
									occ[ix][iy][iz] = (target - yb) / VOXEL
								else
									mats[ix][iy][iz] = AIR
									occ[ix][iy][iz] = 0
								end
							end
							written += 1
						end
					end
				end
			end
		end
		if ix % 16 == 0 then task.wait() end
	end
	if written > 0 then
		Terrain:WriteVoxels(region, VOXEL, mats, occ)
		table.insert(snapshots, { tag = tag, region = region, materials = origM, occupancy = origO, renderOffset = renderOffset })
		conformStats.sites += 1
		conformStats.columns += written
	end
	return written
end

local terrainControl = Instance.new("BindableFunction")
terrainControl.Name = "Exit6SportsTerrain"
terrainControl.OnInvoke = function(action, tag)
	if action == "restore" then
		local n = 0
		for i = #snapshots, 1, -1 do
			local s = snapshots[i]
			if not tag or s.tag == tag then
				Terrain:WriteVoxels(s.region, VOXEL, s.materials, s.occupancy)
				table.remove(snapshots, i)
				n += 1
			end
		end
		return ("restored %d sports terrain sites"):format(n)
	end
	local tags = {}
	for _, s in ipairs(snapshots) do table.insert(tags, s.tag) end
	return ("sites=%d columns=%d blocked=%d water=%d limited=%d: %s"):format(conformStats.sites, conformStats.columns,
		conformStats.blocked, conformStats.water, conformStats.limited, table.concat(tags, ", "))
end
terrainControl.Parent = ServerStorage

-- After conforming, hang a base surface just far enough to meet the ground
-- along its edge (never the old blanket 6-stud skirt).
local function skirtFor(frame, L, W)
	local deepest = 0
	for _, f in ipairs({ { 0.5, 0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { -0.5, -0.5 }, { 0.5, 0 }, { -0.5, 0 }, { 0, 0.5 }, { 0, -0.5 } }) do
		local p = frame * Vector3.new(f[1] * L, 0, f[2] * W)
		local y = groundY(p.X, p.Z)
		if y then deepest = math.max(deepest, p.Y - y) end
	end
	return math.clamp(deepest + 0.8, 1.6, 8)
end

---------------------------------------------------------------------------
-- Sports builders
---------------------------------------------------------------------------
local HOOP = SportsMeshes.hoop
local COURT = SportsMeshes.courtLines
local FOOT = SportsMeshes.footballLines

local function meshSize(id)
	return SportsMeshes.meshSize and SportsMeshes.meshSize[id]
end

-- One hoop. `facing` +1: the hoop stands at the +X end and its rim faces -X
-- (toward the court centre); -1 the reverse. The gameplay Rim BasePart sits
-- exactly on the visible rim centre.
local function hoop(parent, frame, rimX, facing, useMesh)
	local hasMesh = useMesh and meshVisual(parent, "HoopMesh", SportsMeshes.streetHoop,
		frame * CFrame.new(rimX + facing * HOOP.rimOffset.X, HOOP.rimHeight - HOOP.rimOffset.Y, 0)
			* CFrame.Angles(0, facing == 1 and math.pi or 0, 0), Vector3.one, true, rgb(191, 199, 199))
	if hasMesh then
		-- powder-coated rim over the untextured mesh ring (radius 1.02)
		for i = 0, 7 do
			local a = (i + 0.5) / 8 * math.pi * 2
			local seg = counted(part(parent, "RimRing", Vector3.new(0.86, 0.2, 0.2),
				frame * CFrame.new(rimX + math.cos(a) * 1.02, HOOP.rimHeight, math.sin(a) * 1.02) * CFrame.Angles(0, -a + math.pi / 2, 0),
				Enum.Material.Metal, rgb(204, 46, 11)))
			seg.CanCollide = false
			seg.CanQuery = false
		end
	else
		counted(part(parent, "HoopPole", Vector3.new(0.56, 11.4, 0.56), frame * CFrame.new(rimX + facing * 2.4, 5.7, 0), Enum.Material.Metal, POST))
		counted(part(parent, "Backboard", Vector3.new(0.12, 3.5, 6), frame * CFrame.new(rimX + facing * 1.2, 11.4, 0), nil, WHITE))
	end
	-- Exit6Basketball.server reads the Rim BaseParts as shot targets.
	local rim = counted(part(parent, "Rim", Vector3.new(1.6, 0.12, 1.6),
		frame * CFrame.new(rimX, HOOP.rimHeight, 0), Enum.Material.Metal, rgb(214, 96, 32)))
	if hasMesh then
		rim.Transparency = 1
		rim.CanCollide = false
		rim.CanQuery = false
	end
	return rim
end

local BUILDERS = {}
local PITCH = rgb(86, 124, 58)

-- extents of the base surface (and conformed area) around each mapped box
local function extentsOf(key, item)
	local L, W = item.box[3], item.box[4]
	if key == "basketball" then return L + 6, W + 6 end
	if key == "tennis" then return L + 50, W + 28 end
	return L, W
end

BUILDERS.basketball = function(model, frame, L, W, item)
	if not item.group then
		surface(model, "Court", frame, 0, 0, L + 6, W + 6, Enum.Material.Asphalt, rgb(58, 60, 62))
	end
	local sx, sz = (L / 2 - 0.3) / COURT.halfX, (W / 2 - 0.3) / COURT.halfZ
	local rimX = COURT.rimX * sx
	if item.halfCourt then
		local e = item.halfCourt
		lines(model, frame, L - 0.6, W - 0.6, 0)
		-- key and free-throw line at the hoop end, from the paint proportions
		local keyLen, keyW = (COURT.halfX - 34) * sx, 16 * sz
		overlay(model, "Line", frame, e * (L / 2 - keyLen), 0, LINE, keyW, 0.04, WHITE, 0)
		overlay(model, "Line", frame, e * (L / 2 - keyLen / 2), keyW / 2, keyLen, LINE, 0.04, WHITE, 0)
		overlay(model, "Line", frame, e * (L / 2 - keyLen / 2), -keyW / 2, keyLen, LINE, 0.04, WHITE, 0)
		local rim = hoop(model, frame, e * math.min(rimX, L / 2 - 4), e, true)
		-- gameplay needs two targets; both teams share the one rim
		local twin = rim:Clone()
		twin.Transparency = 1
		twin.Parent = model
		counted(twin)
	else
		local id = SportsMeshes.courtPaint
		local size = meshSize(id)
		if not (size and meshVisual(model, "CourtPaintMesh", id, frame * CFrame.new(0, size.Y / 2 + 0.02, 0), Vector3.new(sx, 1, sz), true)) then
			lines(model, frame, L - 0.6, W - 0.6, 0, { 0 })
			circleLine(model, frame, 6 * sz, 0)
		end
		hoop(model, frame, rimX, 1, true)
		hoop(model, frame, -rimX, -1, true)
	end
end

local function net(parent, frame, width, height)
	counted(part(parent, "NetPost", Vector3.new(0.4, height, 0.4), frame * CFrame.new(0, height / 2, width / 2), Enum.Material.Metal, POST))
	counted(part(parent, "NetPost", Vector3.new(0.4, height, 0.4), frame * CFrame.new(0, height / 2, -width / 2), Enum.Material.Metal, POST))
	local n = counted(part(parent, "Net", Vector3.new(0.15, height * 0.45, width), frame * CFrame.new(0, height * 0.75, 0), Enum.Material.Fabric, rgb(30, 30, 32)))
	n.Transparency = 0.35
end

-- OSM tennis outlines trace the 78 x 36 ft doubles lines; real run-off is
-- 21 ft behind each baseline and 12 ft beside each sideline.
BUILDERS.tennis = function(model, frame, L, W, item)
	if not item.group then
		surface(model, "Apron", frame, 0, 0, L + 50, W + 28, Enum.Material.SmoothPlastic, rgb(64, 112, 86))
	end
	overlay(model, "Court", frame, 0, 0, L, W, 0.03, rgb(54, 92, 140), 0)
	local service = L * 21 / 78
	lines(model, frame, L, W, 0.03, { service, -service })
	for _, z in ipairs({ W * 13.5 / 36, -W * 13.5 / 36 }) do
		overlay(model, "Line", frame, 0, z, L, LINE, 0.04, WHITE, 0.03)
	end
	overlay(model, "Line", frame, 0, 0, 2 * service, LINE, 0.04, WHITE, 0.03)
	net(model, frame, W + 6, 3.5)
end

BUILDERS.volleyball = function(model, frame, L, W)
	surface(model, "Court", frame, 0, 0, L, W, Enum.Material.Sand, rgb(214, 196, 150))
	lines(model, frame, L - 4, W - 4, 0)
	net(model, frame, W - 2, 8)
end
BUILDERS.beachvolleyball = BUILDERS.volleyball

-- Baseball: home plate at the box corner `item.home` (local signs), foul
-- lines along the two box edges from that corner, base path `item.base`.
BUILDERS.baseball = function(model, frame, L, W, item)
	surface(model, "Outfield", frame, 0, 0, L, W, Enum.Material.Grass, PITCH)
	local hsx, hsz = (item.home or { -1, -1 })[1], (item.home or { -1, -1 })[2]
	local base = item.base or math.clamp(math.min(L, W) * 0.24, 60, 107)
	local d1, d2 = Vector3.new(-hsx, 0, 0), Vector3.new(0, 0, -hsz)
	local diag = (d1 + d2).Unit
	local corner = Vector3.new(hsx * L / 2, 0, hsz * W / 2)
	local DIRT = rgb(150, 108, 72)
	local home
	if item.infieldOnly then
		base = math.min(base, math.min(L, W) * 0.9)
		home = corner + (d1 + d2) * (math.min(L, W) - base) / 2
		overlay(model, "Infield", frame, (home + (d1 + d2) * base / 2).X, (home + (d1 + d2) * base / 2).Z,
			base * 1.12, base * 1.12, 0.06, DIRT, 0, Enum.Material.Ground)
		overlay(model, "InfieldGrass", frame, (home + (d1 + d2) * base / 2).X, (home + (d1 + d2) * base / 2).Z,
			base * 0.86, base * 0.86, 0.06, PITCH, 0.03, Enum.Material.Grass)
	else
		home = corner + (d1 + d2) * (0.3 * base)
		local mound = home + diag * (0.672 * base)
		-- dirt arc (95 ft at 90 ft paths) around the mound, then infield grass
		local r = 1.056 * base
		local arc = counted(part(model, "Infield", Vector3.new(0.06, 2 * r, 2 * r),
			frame * CFrame.new(mound.X, 0.03, mound.Z) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Ground, DIRT, Enum.PartType.Cylinder))
		arc.CanCollide = false
		local centre = home + (d1 + d2) * base / 2
		overlay(model, "InfieldGrass", frame, centre.X, centre.Z, base * 0.86, base * 0.86, 0.06, PITCH, 0.04, Enum.Material.Grass)
		local plate = counted(part(model, "HomeCircle", Vector3.new(0.06, 0.29 * base, 0.29 * base),
			frame * CFrame.new(home.X, 0.08, home.Z) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Ground, DIRT, Enum.PartType.Cylinder))
		plate.CanCollide = false
		counted(part(model, "Mound", Vector3.new(0.6, 0.2 * base, 0.2 * base),
			frame * CFrame.new(mound.X, 0.2, mound.Z) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Ground, DIRT, Enum.PartType.Cylinder))
		-- foul lines to the box edges
		for _, dir in ipairs({ d1, d2 }) do
			local reach = dir.X ~= 0 and (L / 2 - dir.X * home.X) or (W / 2 - dir.Z * home.Z)
			local mid = home + dir * reach / 2
			overlay(model, "FoulLine", frame, mid.X, mid.Z, dir.X ~= 0 and reach or LINE, dir.X ~= 0 and LINE or reach, 0.04, WHITE, 0.1)
		end
		-- backstop behind home plate
		local back = home - diag * math.min(0.25 * base, 22)
		local bcf = frame * CFrame.new(back.X, 0, back.Z) * CFrame.lookAt(Vector3.zero, diag)
		for i = -2, 2 do
			counted(part(model, "BackstopPost", Vector3.new(0.4, 14, 0.4), bcf * CFrame.new(i * 6, 7, 0), Enum.Material.Metal, POST))
		end
		local fence = counted(part(model, "Backstop", Vector3.new(24, 13, 0.2), bcf * CFrame.new(0, 7, 0), Enum.Material.DiamondPlate, rgb(150, 150, 150)))
		fence.Transparency = 0.55
	end
	for _, b in ipairs({ home, home + d1 * base, home + (d1 + d2) * base, home + d2 * base }) do
		counted(part(model, "Base", Vector3.new(2, 0.2, 2), frame * CFrame.new(b.X, 0.18, b.Z), nil, WHITE)).CanCollide = false
	end
end

local function soccerGoal(model, frame, x, width, height)
	counted(part(model, "GoalPost", Vector3.new(0.5, height, 0.5), frame * CFrame.new(x, height / 2, width / 2), nil, WHITE))
	counted(part(model, "GoalPost", Vector3.new(0.5, height, 0.5), frame * CFrame.new(x, height / 2, -width / 2), nil, WHITE))
	counted(part(model, "Crossbar", Vector3.new(0.5, 0.5, width), frame * CFrame.new(x, height, 0), nil, WHITE))
end

local function field(model, frame, L, W, item, noSurface)
	if not noSurface and not (item and item.group) then surface(model, "Pitch", frame, 0, 0, L, W, Enum.Material.Grass, PITCH) end
	local pl, pw = L - 4, W - 4
	lines(model, frame, pl, pw, 0, { 0 })
	local s = math.min(1, pl / 410)    -- full size at ~105 m
	circleLine(model, frame, 35.7 * s, 0)
	for _, side in ipairs({ -1, 1 }) do
		-- penalty area 18 x 44 yd, goal area 6 x 20 yd
		local boxL, boxW = 64.4 * s, math.min(157 * s, pw - 2)
		overlay(model, "Line", frame, side * (pl / 2 - boxL), 0, LINE, boxW, 0.04, WHITE, 0)
		overlay(model, "Line", frame, side * (pl / 2 - boxL / 2), boxW / 2, boxL, LINE, 0.04, WHITE, 0)
		overlay(model, "Line", frame, side * (pl / 2 - boxL / 2), -boxW / 2, boxL, LINE, 0.04, WHITE, 0)
		soccerGoal(model, frame, side * (pl / 2), 28.6 * s, 9.5 * math.max(s, 0.7))
	end
end
BUILDERS.soccer = field
BUILDERS.pitch = field

-- American football at map scale: 360 x 160 ft lines, high-school goalposts
-- (23 ft 4 in wide, crossbar 10 ft) on the end lines.
local GOLD = rgb(220, 192, 65)
local function football(model, frame, L, W, item)
	if not item.group then
		surface(model, "FootballField", frame, 0, 0, L, W, Enum.Material.Grass, PITCH)
	end
	local lineL, lineW = L - 2, W - 2
	for _, side in ipairs({ -1, 1 }) do
		overlay(model, "EndZone", frame, side * (lineL / 2 - lineL / 24), 0, lineL / 12, lineW, 0.03, rgb(66, 109, 51), 0, Enum.Material.Grass)
	end
	local id = SportsMeshes.footballPaint
	local size = meshSize(id)
	if not (size and meshVisual(model, "FootballPaintMesh", id, frame * CFrame.new(0, size.Y / 2 + 0.04, 0),
		Vector3.new((lineL / 2) / FOOT.halfX, 1, (lineW / 2) / FOOT.halfZ), true)) then
		lines(model, frame, lineL, lineW, 0.03)
		for i = -10, 10 do
			overlay(model, "YardLine", frame, i * lineL / 24, 0, 0.35, lineW, 0.04, WHITE, 0.03)
		end
	end
	local ft = L / 360
	local crossbar, width, upright = 10 * ft, 23.33 * ft, 20 * ft
	for _, side in ipairs({ -1, 1 }) do
		local x = side * (L / 2 + 1)
		local post = counted(part(model, "GoalPost", Vector3.new(0.6, crossbar, 0.6), frame * CFrame.new(x + side * 2, crossbar / 2, 0), Enum.Material.Metal, GOLD))
		post.CanCollide = false
		counted(part(model, "GoalArm", Vector3.new(2.4, 0.5, 0.5), frame * CFrame.new(x + side * 1, crossbar, 0), Enum.Material.Metal, GOLD)).CanCollide = false
		counted(part(model, "GoalCrossbar", Vector3.new(0.5, 0.5, width), frame * CFrame.new(x, crossbar, 0), Enum.Material.Metal, GOLD)).CanCollide = false
		for _, z in ipairs({ -width / 2, width / 2 }) do
			counted(part(model, "GoalUpright", Vector3.new(0.45, upright, 0.45), frame * CFrame.new(x, crossbar + upright / 2, z), Enum.Material.Metal, GOLD)).CanCollide = false
		end
	end
end
BUILDERS.american_football = football

-- Oval track from measured geometry: straights of half-length `straightHalf`
-- along local X, semicircular ends of inner radius `innerR`, `lanes` lanes in
-- a band of `band` studs. Optional chute extends one straight.
local function ovalTrack(model, frame, spec)
	local lanes, band, innerR, half = spec.lanes, spec.band, spec.innerRadius, spec.straightHalf
	local laneW = band / lanes
	local midR, outerR = innerR + band / 2, innerR + band
	local color = rgbOf(spec.color, rgb(158, 72, 54))
	local thick = 0.06
	local function strip(name, lx, lz, len, wid, rot, lift, c)
		-- surfacing strips reach 1.2 below the finished level (hidden where a
		-- pad lies under them); lane lines are thin overlays
		local depth = c and thick or thick + 1.54
		local p = counted(part(model, name, Vector3.new(len, depth, wid),
			frame * CFrame.new(lx, (lift or 0) + thick - depth / 2, lz) * CFrame.Angles(0, rot or 0, 0), Enum.Material.SmoothPlastic, c or color))
		p.CanCollide = false
		return p
	end
	-- straights
	for _, side in ipairs({ -1, 1 }) do
		strip("TrackStraight", 0, side * midR, 2 * half, band, 0)
		for k = 0, lanes do
			strip("LaneLine", 0, side * (innerR + k * laneW), 2 * half, 0.3, 0, 0.02, WHITE)
		end
	end
	if spec.chute then
		local c = spec.chute
		local len = math.abs(c.toX - c.fromX)
		local cx = (c.fromX + c.toX) / 2
		strip("TrackChute", cx, c.side * midR, len, band, 0)
		for k = 0, lanes do
			strip("LaneLine", cx, c.side * (innerR + k * laneW), len, 0.3, 0, 0.02, WHITE)
		end
	end
	-- semicircular ends, 24 facets each
	local n = 24
	for _, e in ipairs({ -1, 1 }) do
		for i = 0, n - 1 do
			local a = (i + 0.5) / n * math.pi - math.pi / 2
			local dirX, dirZ = e * math.cos(a), math.sin(a)
			local rot = -math.atan2(dirZ, dirX) + math.pi / 2
			local chord = 2 * outerR * math.sin(math.pi / (2 * n)) + 0.4
			strip("TrackCurve", e * half + dirX * midR, dirZ * midR, chord, band, rot)
			for k = 0, lanes do
				local r = innerR + k * laneW
				strip("LaneLine", e * half + dirX * r, dirZ * r, 2 * r * math.sin(math.pi / (2 * n)) + 0.1, 0.3, rot, 0.02, WHITE)
			end
		end
	end
	-- the infield inside the inner kerb is natural grass on the conformed
	-- terrain; a thin grass skin keeps decoration from clipping lane edges
end

BUILDERS.athletics = function(model, frame, L, W, item)
	local lanes = item.lanes or 6
	local band = lanes * 4.77
	local r, half = W / 2 - band, L / 2 - W / 2
	-- infield base only; the track band is its own solid surface
	surface(model, "Infield", frame, 0, 0, 2 * half, 2 * r, Enum.Material.Grass, PITCH)
	for _, e in ipairs({ -1, 1 }) do
		counted(part(model, "InfieldEnd", Vector3.new(surfaceSkirt, 2 * r, 2 * r),
			frame * CFrame.new(e * half, -surfaceSkirt / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Grass, PITCH, Enum.PartType.Cylinder))
	end
	ovalTrack(model, frame, { lanes = lanes, band = band, innerRadius = r, straightHalf = half, color = item.trackColor })
	-- Gillespie Field already has a separate, mapped football pitch. Do not
	-- place a second generic field over that pitch.
	if math.abs(frame.Position.X - 8364) > 10 or math.abs(frame.Position.Z + 7027) > 10 then
		field(model, frame, L - W, W - 2 * band - 8, item, true)
	end
end

-- Aluminium bleachers from the uploaded section mesh: rows rise toward the
-- mesh's -Z, so +Z (the front row) faces `toward`.
local function stand(parent, name, x, z, length, depth, toward, axisYaw)
	local samples = sampleBox({ x, z, length, depth, axisYaw }, 10)
	local ys = {}
	for _, s in ipairs(samples) do table.insert(ys, s[3]) end
	local y = median(ys)
	if not y then return end
	local along = Vector3.new(math.cos(math.rad(axisYaw)), 0, -math.sin(math.rad(axisYaw)))
	local front = Vector3.new(toward[1] - x, 0, toward[2] - z)
	front = (front - along * front:Dot(along)).Unit
	local right = Vector3.yAxis:Cross(front)
	local id = SportsMeshes.bleacherSection
	local size = meshSize(id)
	local sections = math.max(1, math.ceil(length / 62))
	local sectionLen = length / sections
	local s = depth / size.Z
	local model = Instance.new("Model")
	model.Name = name
	for i = 1, sections do
		local offset = (i - 0.5 - sections / 2) * sectionLen
		local pos = Vector3.new(x, y + size.Y * s / 2, z) + right * offset
		local cf = CFrame.fromMatrix(pos, right, Vector3.yAxis, front)
		if not meshVisual(model, "BleacherMesh", id, cf, Vector3.new(sectionLen / size.X, s, s), true, rgb(191, 199, 199)) then
			counted(part(model, "Bleacher", Vector3.new(sectionLen, size.Y * s, depth), cf, Enum.Material.Metal, rgb(176, 180, 182)))
		end
	end
	model:SetAttribute("Ground", y)
	model.Parent = parent
end

local function lightPole(parent, x, z, height)
	local y = groundY(x, z)
	if not y then return end
	counted(part(parent, "LightPole", Vector3.new(1.2, height, 1.2), CFrame.new(x, y + height / 2, z), Enum.Material.Metal, rgb(120, 124, 126)))
	local head = counted(part(parent, "LightBank", Vector3.new(6, 3, 1), CFrame.new(x, y + height + 1, z), Enum.Material.Metal, rgb(90, 92, 94)))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = 60
	light.Angle = 80
	light.Brightness = 1.5
	light.Shadows = false
	light.Parent = head
end

local function chainFence(parent, pts, height)
	for i = 1, #pts - 3, 2 do
		local a, b = Vector3.new(pts[i], 0, pts[i + 1]), Vector3.new(pts[i + 2], 0, pts[i + 3])
		local len = (b - a).Magnitude
		local n = math.max(1, math.ceil(len / 10))
		for k = 0, n - 1 do
			local p0, p1 = a:Lerp(b, k / n), a:Lerp(b, (k + 1) / n)
			local y0, y1 = groundY(p0.X, p0.Z), groundY(p1.X, p1.Z)
			if y0 and y1 then
				local y = math.min(y0, y1)
				counted(part(parent, "FencePost", Vector3.new(0.3, height + 0.6, 0.3), CFrame.new(p0.X, y0 + height / 2, p0.Z), Enum.Material.Metal, POST))
				local mid = (p0 + p1) / 2
				local panel = counted(part(parent, "FenceMesh", Vector3.new((p1 - p0).Magnitude, height, 0.15),
					CFrame.lookAt(Vector3.new(mid.X, y + height / 2, mid.Z), Vector3.new(p1.X, y + height / 2, p1.Z)) * CFrame.Angles(0, math.pi / 2, 0),
					Enum.Material.DiamondPlate, rgb(150, 150, 150)))
				panel.Transparency = 0.6
			end
		end
	end
end

---------------------------------------------------------------------------
-- Restored non-sports builders (unchanged geometry)
---------------------------------------------------------------------------
BUILDERS.playground = function(model, frame, L, W)
	legacySlab(model, "Surface", frame, 0, 0, L, W, 0.3, Enum.Material.Fabric, rgb(150, 82, 52))
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
	legacySlab(model, "Deck", frame, 0, 0, L + 6, W + 6, 0.4, Enum.Material.Concrete, rgb(200, 196, 186))
	local water = legacySlab(model, "Water", frame, 0, 0, math.max(L - 2, 2), math.max(W - 2, 2), 0.2, Enum.Material.Glass, rgb(70, 160, 210), 0.42)
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
local built, skipped, dropped = {}, 0, 0
-- a sports feature box lying across a rail bed is a mis-drawn polygon (a
-- 460 x 444 "outfield" over the CSX): skip it rather than pave the tracks
local railBeds = {}
for _, tile in ipairs(Workspace:WaitForChild("ChesterWorld"):GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	for _, p in ipairs(roads and roads:GetChildren() or {}) do
		if p:IsA("BasePart") and p:GetAttribute("CW_Rail") == true and p.Name ~= "Rail" then
			table.insert(railBeds, p)
		end
	end
end
local railParams = OverlapParams.new()
railParams.FilterType = Enum.RaycastFilterType.Include
railParams.FilterDescendantsInstances = railBeds
railParams.MaxParts = 1
local onRail = 0

-- apply aerial-verified corrections to the OSM features
local function correctionFor(item)
	for _, c in ipairs(VerifiedSports.corrections or {}) do
		if math.abs(item.box[1] - c.at[1]) < 1 and math.abs(item.box[2] - c.at[2]) < 1 then return c end
	end
end
local sportsFeatures, legacyFeatures = {}, {}
local function classify(item)
	if item.kind == "pitch" or item.kind == "track" then
		table.insert(sportsFeatures, item)
	else
		table.insert(legacyFeatures, item)
	end
end
for _, source in ipairs(Parks.features) do
	local c = correctionFor(source)
	if c and c.drop then
		dropped += 1
	elseif c and c.replace then
		for _, r in ipairs(c.replace) do classify(table.clone(r)) end
	else
		local item = table.clone(source)
		for k, v in pairs(c and c.set or {}) do item[k] = v end
		classify(item)
	end
end
for _, fac in ipairs(VerifiedSports.facilities or {}) do
	for _, f in ipairs(fac.features or {}) do
		local item = table.clone(f)
		item.verified = fac.id
		classify(item)
	end
end

local function keyOf(item)
	if item.kind == "pitch" then return item.sport or "pitch" end
	if item.kind == "track" then return item.sport or "athletics" end
	return item.kind
end

-- 1a. shared level groups (one finished level + one conform per group)
local groupFolder = Instance.new("Folder")
groupFolder.Name = "SportsSurfaces"
groupFolder.Parent = featureFolder
local groups = {}
for name, g in pairs(VerifiedSports.levelGroups or {}) do
	local a = levelOf(g.box, 0)
	if a then
		local frame = frameFor(g.box, a, 0)
		conformTerrain(name, g.box, a, 0, g.margin or 16, g.shape)
		surfaceSkirt = g.shape == "oval" and 1.6 or skirtFor(frame, g.box[3], g.box[4])
		local m = Instance.new("Model")
		m.Name = name
		m:SetAttribute("SurfaceY", a)
		local material = Enum.Material[g.pad and g.pad.material or "Grass"]
		local color = rgbOf(g.pad and g.pad.color, PITCH)
		if g.shape == "oval" then
			-- infield only (inside the inner kerb): the track band is its own
			-- solid surface, so nothing is coplanar with it
			local half, r = g.pad.half, g.pad.radius
			surface(m, "Pad", frame, 0, 0, 2 * half, 2 * r, material, color)
			for _, e in ipairs({ -1, 1 }) do
				counted(part(m, "PadEnd", Vector3.new(surfaceSkirt, 2 * r, 2 * r),
					frame * CFrame.new(e * half, -surfaceSkirt / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), material, color, Enum.PartType.Cylinder))
			end
		else
			surface(m, "Pad", frame, 0, 0, g.box[3], g.box[4], material, color)
		end
		m.WorldPivot = frame
		m.Parent = groupFolder
		groups[name] = { a = a, frame = frame }
	end
end

-- 1b. sports surfaces: level, conform, build
local sportsReport = {}
for _, item in ipairs(sportsFeatures) do
	local key = keyOf(item)
	local builder = BUILDERS[key] or (item.kind == "pitch" and BUILDERS.pitch)
	-- Three nearby OSM steeplechase details are not whole stadium tracks.
	if key == "athletics" and (item.box[3] < 300 or item.box[4] < 150) then builder = nil end
	local L, W = item.box[3], item.box[4]
	local frame, a, b
	local group = item.group and groups[item.group]
	if group then
		a, b = group.a, 0
	else
		local grade = item.grade or ((key == "soccer" or key == "pitch" or key == "american_football" or key == "baseball") and 0.01 or 0)
		a, b = levelOf(item.box, grade)
	end
	if a then frame = frameFor(item.box, a, b) end
	if frame and #railBeds > 0
		and #Workspace:GetPartBoundsInBox(frame, Vector3.new(L, 40, W), railParams) > 0 then
		onRail += 1
		frame = nil
	end
	if builder and frame then
		local ex, ez = extentsOf(key, item)
		if not group then
			local ebox = { item.box[1], item.box[2], ex, ez, item.box[5] }
			conformTerrain(key .. "@" .. math.floor(item.box[1]) .. "," .. math.floor(item.box[2]), ebox, a, b,
				(key == "basketball" or key == "tennis" or key == "volleyball" or key == "beachvolleyball") and 12 or 20,
				key == "athletics" and "oval" or nil)
			surfaceSkirt = skirtFor(frame, ex, ez)
		else
			surfaceSkirt = 1.6
		end
		local model = Instance.new("Model")
		model.Name = key
		if item.facility then model:SetAttribute("Facility", item.facility) end
		if item.verified then model:SetAttribute("Verified", item.verified) end
		model:SetAttribute("SurfaceY", a)
		model:SetAttribute("Grade", b)
		builder(model, frame, L, W, item)
		model.WorldPivot = frame
		model.Parent = featureFolder
		if key == "basketball" then
			-- street basketball (Exit6Basketball.server) plays on these
			model:SetAttribute("CourtLength", L)
			model:SetAttribute("CourtWidth", W)
			game:GetService("CollectionService"):AddTag(model, "Exit6Court")
		end
		built[key] = (built[key] or 0) + 1
		if item.verified or item.facility then
			table.insert(sportsReport, ("%s %s at (%.1f, %.1f) %.0fx%.0f yaw %.1f surface %.2f grade %.3f"):format(
				item.facility or item.verified, key, item.box[1], item.box[2], L, W, item.box[5], a, b))
		end
	else
		skipped += 1
	end
end

-- 1c. verified facility structures (tracks, stands, lights, fences)
for _, fac in ipairs(VerifiedSports.facilities or {}) do
	local model = Instance.new("Model")
	model.Name = fac.id
	model:SetAttribute("Facility", fac.name)
	model:SetAttribute("Address", fac.address)
	model:SetAttribute("Source", fac.source)
	local t = fac.track
	if t then
		local group = t.group and groups[t.group]
		local a = group and group.a or levelOf({ t.centre[1], t.centre[2], 2 * (t.straightHalf + t.innerRadius + t.band), 2 * (t.innerRadius + t.band), t.yaw }, 0)
		if a then
			local frame = frameFor({ t.centre[1], t.centre[2], 0, 0, t.yaw }, a, 0)
			local track = Instance.new("Model")
			track.Name = "Track"
			ovalTrack(track, frame, t)
			track.WorldPivot = frame
			track:SetAttribute("SurfaceY", a)
			track.Parent = model
			table.insert(sportsReport, ("%s track at (%.1f, %.1f) infield %.0fx%.0f lanes %d yaw %.2f surface %.2f"):format(
				fac.name, t.centre[1], t.centre[2], 2 * (t.straightHalf + t.innerRadius), 2 * t.innerRadius, t.lanes, t.yaw, a))
		end
	end
	for i, s in ipairs(fac.stands or {}) do
		stand(model, s.name or ("Stand" .. i), s.at[1], s.at[2], s.length, s.depth, s.face, s.axisYaw)
	end
	for _, p in ipairs(fac.lightPoles or {}) do lightPole(model, p[1], p[2], 70) end
	for _, f in ipairs(fac.fences or {}) do chainFence(model, f, 8) end
	model.Parent = featureFolder
end

-- 1d. restored non-sports features keep their original placement logic
for _, item in ipairs(legacyFeatures) do
	local key = keyOf(item)
	local builder = BUILDERS[key]
	local frame = frameOfHighest(item.box)
	if frame and #railBeds > 0 and key ~= "cemetery"
		and #Workspace:GetPartBoundsInBox(frame, Vector3.new(item.box[3], 40, item.box[4]), railParams) > 0 then
		onRail += 1
		frame = nil
	end
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
for _, line in ipairs(sportsReport) do print("[Exit6 Sports] " .. line) end
print("[Exit6 Sports] terrain " .. terrainControl:Invoke("report"):sub(1, 200))

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

-- A park outline is not a road edge. Crozer Park's first near-road vertex
-- placed its sign in Kerlin Street. Check the entire sign envelope (including
-- both posts) against actual pavement and sidewalks before choosing a spot.
local occupied = OverlapParams.new()
occupied.FilterType = Enum.RaycastFilterType.Include
occupied.MaxParts = 1
local occupiedFolders = {}
for _, tile in ipairs(world and world:GetChildren() or {}) do
	for _, name in ipairs({ "Roads", "Intersections", "Intersection", "Sidewalks" }) do
		local folder = tile:FindFirstChild(name)
		if folder then table.insert(occupiedFolders, folder) end
	end
end
occupied.FilterDescendantsInstances = occupiedFolders

local function insideOutline(x, z, pts)
	local inside = false
	local j = #pts - 1
	for i = 1, #pts - 1, 2 do
		local xi, zi, xj, zj = pts[i], pts[i + 1], pts[j], pts[j + 1]
		if (zi > z) ~= (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function clearSign(x, z, pts)
	if not insideOutline(x, z, pts) then return false end
	local y = groundY(x, z)
	if not y then return false end
	-- Include verge clearance so posts and board do not overhang a lane,
	-- sidewalk, or driveway mouth. Broadphase uses real placed Parts.
	return #Workspace:GetPartBoundsInBox(CFrame.new(x, y + 3, z),
		Vector3.new(17, 10, 8), occupied) == 0
end

-- The imported walking loop can run outside its park polygon. Check the full
-- footprint, not just the centre point, before adding collision geometry.
local function clearParkFootprint(frame, width, depth, outline, clearance)
	local halfX, halfZ = width / 2 + clearance, depth / 2 + clearance
	for _, localPoint in ipairs({
		Vector3.new(-halfX, 0, -halfZ), Vector3.new(-halfX, 0, halfZ),
		Vector3.new(halfX, 0, -halfZ), Vector3.new(halfX, 0, halfZ),
		Vector3.new(0, 0, -halfZ), Vector3.new(0, 0, halfZ),
		Vector3.new(-halfX, 0, 0), Vector3.new(halfX, 0, 0),
		Vector3.new(0, 0, 0),
	}) do
		local p = frame * localPoint
		if not insideOutline(p.X, p.Z, outline) then return false end
	end
	return #Workspace:GetPartBoundsInBox(frame * CFrame.new(0, 2, 0),
		Vector3.new(width + 2 * clearance, 6, depth + 2 * clearance), occupied) == 0
end

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
	-- Search park-side candidates at a mapped roadside vertex. The sign is
	-- omitted if no collision-free entrance/verge exists in the source outline.
	if park.name then
		for i = 1, n do
			local x, z = pts[2 * i - 1], pts[2 * i]
			local y = groundY(x, z)
			if y and #Workspace:GetPartBoundsInRadius(Vector3.new(x, y, z), 30, roadParams) > 0 then
				local inward = Vector3.new(cx - x, 0, cz - z)
				inward = inward.Magnitude > 0 and inward.Unit or Vector3.zero
				for _, offset in ipairs({ 10, 16, 24, 32 }) do
					local sx, sz = x + inward.X * offset, z + inward.Z * offset
					if clearSign(sx, sz, pts) then
						sign(model, sx, sz, park.name)
						signs += 1
						break
					end
				end
				if model:FindFirstChild("Sign") then break end
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
				local pathFrame
				if y0 and y1 then
					local a, b = Vector3.new(x0, y0 + 0.15, z0), Vector3.new(x1, y1 + 0.15, z1)
					pathFrame = CFrame.lookAt((a + b) / 2, b)
					if clearParkFootprint(pathFrame, 6, (b - a).Magnitude + 0.6, pts, 1) then
						counted(part(model, "Path", Vector3.new(6, 0.3, (b - a).Magnitude + 0.6),
							pathFrame, Enum.Material.Concrete, CONCRETE))
						pathParts += 1
						budget -= 1
					else
						pathFrame = nil
					end
				end
				travelled += length / steps
				if pathFrame and travelled >= nextBench and benches < 2000 then
					local dir = Vector3.new(x1 - x0, 0, z1 - z0)
					if dir.Magnitude > 0 and y1 then
						local side = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X) * 5
						local p = Vector3.new(x1, y1, z1) + side
						local by = groundY(p.X, p.Z)
						local seatFrame = by and CFrame.lookAt(Vector3.new(p.X, by, p.Z), Vector3.new(x1, by, z1))
						if seatFrame and clearParkFootprint(seatFrame, 5, 1.5, pts, 3) then
							bench(model, seatFrame)
							benches += 1
						end
					end
					nextBench += 70
				end
				if pathFrame and travelled >= nextLamp and y1 then
					local dir = Vector3.new(x1 - x0, 0, z1 - z0)
					if dir.Magnitude > 0 then
						local side = Vector3.new(dir.Unit.Z, 0, -dir.Unit.X) * 5
						local p = Vector3.new(x1, 0, z1) + side
						local ly = groundY(p.X, p.Z)
						if ly and clearParkFootprint(CFrame.new(p.X, ly, p.Z), 1.4, 1.4, pts, 3) then
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
print(("[ChesterWorld Parks] parks=%d signs=%d pathParts=%d benches=%d lamps=%d features: %s skipped=%d onRail=%d parts=%d")
	:format(#Parks.parks, signs, pathParts, benches, lamps, table.concat(summary, " "), skipped, onRail, parts))
Workspace:SetAttribute("CW_ParksComplete", true)
