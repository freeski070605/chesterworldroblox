-- Harness runner (appended to the generated bundle; see build_bundle.py).
-- Globals available here: Mock, SRC, TILES, FEATURES, CORRIDOR, ALLSEG,
-- SKIP_STRUCTURES, REV.

local V3 = Mock.Vector3.new

-- ------------------------------------------------------------- terrain
local function smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function baseTerrain(x, z)
	return 40 + 12 * math.sin(x / 900) * math.cos(z / 1100)
		+ 6 * math.sin((x + z) / 430)
		+ 3 * math.sin(x / 170 + 1.3) * math.sin(z / 230)
end

-- Kerlin / I-95 calibration (Studio baseline 2026-11-04): embankment top
-- ~56.8, Kerlin floor ~38.7, flat floor to ~28 studs from the Kerlin
-- centerline, back to the rim by ~86 studs.
local K_CENTER_X, K_CENTER_Z = 2003.0, 2.4
local K_DIR_X, K_DIR_Z = 0.892, -0.451 -- I-95 direction
local KERLIN_AX, KERLIN_AZ = 2015.268, 25.443
local KERLIN_BX, KERLIN_BZ = 1990.695, -20.670
local kdx, kdz = KERLIN_BX - KERLIN_AX, KERLIN_BZ - KERLIN_AZ
local klen = math.sqrt(kdx * kdx + kdz * kdz)
kdx, kdz = kdx / klen, kdz / klen

local function kerlinTerrain(x, z)
	local rx, rz = x - K_CENTER_X, z - K_CENTER_Z
	local along = rx * K_DIR_X + rz * K_DIR_Z
	local across = math.abs(-rx * K_DIR_Z + rz * K_DIR_X)
	if math.abs(along) > 1600 or across > 400 then
		return nil
	end
	-- embankment ridge carrying both carriageways
	local embank = 1 - smoothstep((across - 70) / 60)
	local ground = 38.7 + 18.1 * embank
	-- Kerlin gap: distance from the Kerlin centerline
	local d = math.abs(-(x - KERLIN_AX) * kdz + (z - KERLIN_AZ) * kdx)
	local notch = 1 - smoothstep((d - 28) / 58)
	ground -= 18.1 * embank * notch
	local blend = smoothstep((math.abs(along) - 1100) / 400)
	return ground, blend
end

local function terrain(x, z)
	local y = baseTerrain(x, z)
	local notchDepth, cutDepth = 0, 0
	for _, f in ipairs(FEATURES) do
		local kind, fx, fz, dx, dz, half = f[1], f[2], f[3], f[4], f[5], f[6]
		local rx, rz = x - fx, z - fz
		if math.abs(rx) < 900 and math.abs(rz) < 900 then
			local along = math.abs(rx * dx + rz * dz)
			local d = math.abs(-rx * dz + rz * dx)
			if kind == 1 then
				-- NOTCH: the lower road runs through a gap under the upper road
				local depth = 17 * (1 - smoothstep((d - (half + 12)) / 55)) * (1 - smoothstep((along - 180) / 60))
				notchDepth = math.max(notchDepth, depth)
			else
				-- CUT: the highway runs below a local overpass (both carriageways
				-- + rail line: ~110 studs either side of the centerline)
				local depth = 18 * (1 - smoothstep((d - 110) / 45)) * (1 - smoothstep((along - 700) / 420))
				cutDepth = math.max(cutDepth, depth)
			end
		end
	end
	y -= math.max(notchDepth, cutDepth)
	local k, blend = kerlinTerrain(x, z)
	if k then
		y = k + (y - k) * blend
	end
	return y
end
Mock.terrainFn = terrain

-- ------------------------------------------------------------- data model
local game = Mock.game
local RS = Mock.methods.FindFirstChild(game, "ReplicatedStorage")
local Shared = Mock.makeFolder(RS, "Shared")
for _, name in ipairs({ "WorldPlacement", "WorldConfig", "StreetData", "HighwayStructureRegistry" }) do
	local src = SRC["shared/" .. name]
	if src then
		Mock.addModule(Shared, name, src)
	end
end
local WorldData = Mock.addModule(Shared, "WorldData", "return {version = 1}")
local Tiles = Mock.makeFolder(WorldData, "Tiles")
for name, src in pairs(TILES) do
	Mock.addModule(Tiles, name, src)
end
local SSS = Mock.methods.FindFirstChild(game, "ServerScriptService")
local Server = Mock.makeFolder(SSS, "Server")
local World = Mock.makeFolder(Server, "World")
for _, name in ipairs({ "TileBuilderV2", "TileBuilderV3", "HighwayProfile" }) do
	if SRC["world/" .. name] then
		Mock.addModule(World, name, SRC["world/" .. name])
	end
end
local scripts = {}
for _, name in ipairs({ "RoadTerrainConformer", "HighwayInfrastructure" }) do
	if SRC["script/" .. name] then
		scripts[name] = Mock.addModule(World, name, SRC["script/" .. name], "Script")
	end
end
local boot = Mock.addModule(Server, "Bootstrap", SRC.bootstrap, "Script")

local t0 = os.clock()
Mock.runScript(boot)
local t1 = os.clock()
Mock.runScript(scripts.RoadTerrainConformer)
local t2 = os.clock()
if not SKIP_STRUCTURES then
	Mock.runScript(scripts.HighwayInfrastructure)
end
local t3 = os.clock()
print(string.format("HARNESS timing bootstrap=%.1fs conformer=%.1fs structures=%.1fs", t1 - t0, t2 - t1, t3 - t2))

-- ------------------------------------------------------------- audit
local function norm(n)
	local v = string.lower(tostring(n or ""))
	v = v:gsub("[^%w]", " ")
	v = v:gsub("%s+", " ")
	v = v:gsub("^%s+", "")
	v = v:gsub("%s+$", "")
	return v
end

local worldRoot = Mock.methods.FindFirstChild(Mock.Workspace, "ChesterWorld")
local CELL = 32
local grid = {}
local surfaces = 0
local function addPart(p, role)
	local c = p.CFrame
	local s = p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local R, U, B = c.RightVector, c.UpVector, -c.LookVector
	local ex = math.abs(R.X) * hx + math.abs(U.X) * hy + math.abs(B.X) * hz
	local ez = math.abs(R.Z) * hx + math.abs(U.Z) * hy + math.abs(B.Z) * hz
	local item = { p = p, role = role, name = norm(p:GetAttribute("ChesterStreet") or "") }
	for gx = math.floor((c.Position.X - ex) / CELL), math.floor((c.Position.X + ex) / CELL) do
		for gz = math.floor((c.Position.Z - ez) / CELL), math.floor((c.Position.Z + ez) / CELL) do
			local k = gx * 100003 + gz
			local b = grid[k]
			if not b then
				b = {}
				grid[k] = b
			end
			table.insert(b, item)
		end
	end
	surfaces += 1
end
for _, tile in ipairs(worldRoot:GetChildren()) do
	local roads = tile:FindFirstChild("Roads")
	if roads then
		for _, p in ipairs(roads:GetDescendants()) do
			if Mock.isBasePart(p) then
				addPart(p, "road")
			end
		end
	end
	local pads = tile:FindFirstChild("Intersections")
	if pads then
		for _, p in ipairs(pads:GetDescendants()) do
			if Mock.isBasePart(p) then
				addPart(p, "pad")
			end
		end
	end
	if tile.Name == "HighwayInfrastructure" then
		for _, p in ipairs(tile:GetDescendants()) do
			if Mock.isBasePart(p) and p.CanCollide then
				addPart(p, "structure")
			end
		end
	end
end

-- all vertical hits at (x, z): list of {top=, bottom=, item=}
local function hitsAt(x, z)
	local out = {}
	local k = math.floor(x / CELL) * 100003 + math.floor(z / CELL)
	local origin = V3(x, 2000, z)
	local dir = V3(0, -4000, 0)
	local up = V3(x, -2000, z)
	local udir = V3(0, 4000, 0)
	for _, item in ipairs(grid[k] or {}) do
		local p = item.p
		if p.Parent then
			local t = Mock.rayBox(p, origin, dir)
			if t then
				local tb = Mock.rayBox(p, up, udir)
				table.insert(out, { top = 2000 - 4000 * t, bottom = tb and (-2000 + 4000 * tb) or nil, item = item })
			end
		end
	end
	return out
end

local function surfaceFor(x, z, name)
	local best = nil
	for _, h in ipairs(hitsAt(x, z)) do
		if h.item.role == "pad" or (h.item.role == "road" and h.item.name == name) then
			if not best or h.top > best then
				best = h.top
			end
		end
	end
	return best
end

local function auditSegments(list, step, withProfile)
	local m = {
		segments = #list, samples = 0, missing = 0, buried = 0,
		steps = 0, unsafe = 0, cliff = 0, missingSegments = 0, worstStep = 0,
		_buriedEx = {}, _stepEx = {}, _buriedZones = {},
	}
	local missingExamples = {}
	for _, seg in ipairs(list) do
		local ax, az, bx, bz, name = seg[1], seg[2], seg[3], seg[4], seg[5]
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if len > 1 then
			local n = math.max(1, math.floor(len / step))
			local prev = nil
			local segMissing = false
			for i = 0, n do
				local f = math.clamp(i / n, 0.5 / len, 1 - 0.5 / len)
				local x, z = ax + (bx - ax) * f, az + (bz - az) * f
				local top = surfaceFor(x, z, name)
				m.samples += 1
				if not top then
					m.missing += 1
					segMissing = true
					if #missingExamples < 25 and withProfile then
						table.insert(missingExamples, string.format("%s (%.1f, %.1f)", name, x, z))
					end
					prev = nil
				else
					local ground = Mock.groundAt(x, z)
					if withProfile and ground > top + 0.05 then
						m.buried += 1
						if #m._buriedEx < 12 then
							table.insert(m._buriedEx, string.format("%s (%.1f, %.1f) top=%.2f ground=%.2f", name, x, z, top, ground))
						end
						-- per road and 300-stud cell, for locating burial clusters
						local key = string.format("%s|%d|%d", name, math.floor(x / 300), math.floor(z / 300))
						local zone = m._buriedZones[key]
						if not zone then
							zone = { name = name, n = 0, depth = 0 }
							m._buriedZones[key] = zone
						end
						zone.n += 1
						if ground - top > zone.depth then
							zone.depth, zone.x, zone.z = ground - top, x, z
						end
					end
					if prev then
						local dy = math.abs(top - prev)
						local run = len / n
						if withProfile then
							if dy > 1.0 then
								m.steps += 1
								if #m._stepEx < 12 then
									table.insert(m._stepEx, string.format("%s (%.1f, %.1f) dy=%.2f", name, x, z, dy))
								end
								m.worstStep = math.max(m.worstStep, dy)
							end
							if dy / run > 0.15 then
								m.unsafe += 1
							end
							if dy / run > 0.40 then
								m.cliff += 1
							end
						end
					end
					prev = top
				end
			end
			if segMissing then
				m.missingSegments += 1
			end
		end
	end
	return m, missingExamples
end

local corridorMetrics, corridorMissing = auditSegments(CORRIDOR, 4, true)
local allMetrics = auditSegments(ALLSEG, 6, false)

-- Kerlin physical check
local kerlin = {}
for _, point in ipairs({
	{ "north_joint", 2015.268, 25.443 },
	{ "underpass_mid", 2002.581, 1.635 },
	{ "south_joint", 1990.695, -20.670 },
}) do
	local x, z = point[2], point[3]
	local i95, kerlinTop = nil, nil
	local hits = hitsAt(x, z)
	for _, h in ipairs(hits) do
		if h.item.role == "road" and h.item.name == "i 95" then
			i95 = math.max(i95 or -math.huge, h.top)
		end
		if h.item.role == "road" and (h.item.name == "kerlin" or h.item.name == "kerlin st") then
			kerlinTop = math.max(kerlinTop or -math.huge, h.top)
		end
	end
	local underside = nil
	if kerlinTop then
		for _, h in ipairs(hits) do
			local bottom = h.bottom
			if bottom and bottom > kerlinTop + 0.5 and h.item.p.CanCollide then
				underside = math.min(underside or math.huge, bottom)
			end
		end
	end
	table.insert(kerlin, string.format("%s i95Top=%s kerlinTop=%s lowestCollidableAbove=%s opening=%s terrain=%.2f",
		point[1], i95 and string.format("%.2f", i95) or "MISSING",
		kerlinTop and string.format("%.2f", kerlinTop) or "MISSING",
		underside and string.format("%.2f", underside) or "none",
		(underside and kerlinTop) and string.format("%.2f", underside - kerlinTop) or "n/a",
		terrain(x, z)))
end

-- I-95 drive profile through Kerlin on both carriageways (top Y every 6 studs)
local drive = {}
for _, lane in ipairs({ { "424/425", 2015.268, 25.443 }, { "423/426", 1990.695, -20.670 } }) do
	local values = {}
	for s = -180, 180, 12 do
		local x, z = lane[2] + K_DIR_X * s, lane[3] + K_DIR_Z * s
		local top = surfaceFor(x, z, "i 95")
		table.insert(values, top and string.format("%.1f", top) or "--")
	end
	table.insert(drive, lane[1] .. ": " .. table.concat(values, " "))
end

local function enc(t)
	local parts = {}
	for k, v in pairs(t) do
		if string.sub(k, 1, 1) == "_" then continue end
		table.insert(parts, string.format("%q:%s", k, type(v) == "number" and string.format("%.3f", v) or string.format("%q", tostring(v))))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end
print("AUDIT_REV " .. REV)
print("AUDIT_SURFACES " .. surfaces)
print("AUDIT_CORRIDOR " .. enc(corridorMetrics))
print("AUDIT_ALLROADS " .. enc(allMetrics))
for _, line in ipairs(kerlin) do
	print("AUDIT_KERLIN " .. line)
end
for _, line in ipairs(drive) do
	print("AUDIT_DRIVE " .. line)
end
for _, line in ipairs(corridorMetrics._buriedEx) do
	print("AUDIT_BURIED " .. line)
end
do
	local zones = {}
	for _, zone in pairs(corridorMetrics._buriedZones) do
		table.insert(zones, zone)
	end
	table.sort(zones, function(a, b)
		return a.n > b.n
	end)
	for i = 1, math.min(25, #zones) do
		local zone = zones[i]
		print(string.format("AUDIT_BURIEDZONE %s samples=%d maxDepth=%.2f at (%.1f, %.1f)",
			zone.name, zone.n, zone.depth, zone.x, zone.z))
	end
end
corridorMetrics._buriedZones = nil
for _, line in ipairs(corridorMetrics._stepEx) do
	print("AUDIT_STEP " .. line)
end
for _, line in ipairs(corridorMissing) do
	print("AUDIT_MISSING " .. line)
end
