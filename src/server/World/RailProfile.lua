-- ChesterWorld | Railway vertical profile (Amtrak NEC, CSX Phila Sub, Conrail
-- Chester Secondary, Linwood Industrial Track).
--
-- The rail lines were laid on the bare-earth DEM. The NEC runs through Chester
-- on a raised stone embankment with steel girder bridges over every street
-- (DVRPC 2025 aerial: crossing_aerial.py barry_4, barry_amtrak, st_industrial;
-- the bridges show as brown deck rectangles over Reaney, Flower, Eddystone...)
-- and the bare-earth DEM has those bridges removed: the track dived into each
-- street underpass and pieces steeper than the street limit were dropped,
-- leaving gaps. The CSX has the same problem where it bridges streets.
--
-- Like HighwayProfile, but for track:
--   1. chain each line's records into continuous strokes (straightest
--      continuation through junctions and switches),
--   2. sample the terrain every STEP studs,
--   3. cut narrow DEM spikes, fill narrow notches (bridged dips: street
--      underpasses, creek valleys),
--   4. hold clearance over every street that crosses under the line
--      (the street at the crossing is well below the filled line),
--   5. hold a gentle rail grade (upper Lipschitz envelope, raise only),
--   6. classify each station: "span" (bridge over a street / bridged dip),
--      "fill" (embankment wall), "grade".
-- TileBuilderV2 builds ballast, rails and structures from it.
local RailProfile = {}

local STEP = 6
local SPIKE_WINDOW = 60          -- studs: DEM bumps narrower than this are cut
local NOTCH_WINDOW = 320         -- studs: dips narrower than this are bridged
local GRADE = 0.012              -- stud per stud (~1.6 % real: Mercator horizontal)
local STREET_CLEARANCE = 13      -- studs over a street the line bridges (~4.3 m)
local DECK = 2.2                 -- bed + girder depth above the opening
local OVER_STREET_MIN = 6        -- line this far above a crossing street => bridge
local SPAN_FILL = 10             -- filled more than this over the ground => bridge

local strokes = {}
local infoByRoad = {}
local stats = {}
local streetGrid, STREET_CELL = {}, 120

local function lerp(a, b, t) return a + (b - a) * t end

local function windowExtremes(values, w, useMax)
	local n = #values
	local left, right = table.create(n), table.create(n)
	for i = 1, n do
		local best = values[i]
		for k = math.max(1, i - w), i do
			local v = values[k]
			if useMax then best = math.max(best, v) else best = math.min(best, v) end
		end
		left[i] = best
		best = values[i]
		for k = i, math.min(n, i + w) do
			local v = values[k]
			if useMax then best = math.max(best, v) else best = math.min(best, v) end
		end
		right[i] = best
	end
	return left, right
end

local function segIntersect(ax, az, bx, bz, cx, cz, dx, dz)
	local rx, rz = bx - ax, bz - az
	local sx, sz = dx - cx, dz - cz
	local den = rx * sz - rz * sx
	if math.abs(den) < 1e-9 then return nil end
	local qx, qz = cx - ax, cz - az
	local t = (qx * sz - qz * sx) / den
	local u = (qx * rz - qz * rx) / den
	if t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999 then return t, u end
	return nil
end

-- entries: { {road=..}, ... } (all tile roads); opts: sourceToStuds,
-- terrainY(x, z), isRail(name)
function RailProfile.Prepare(entries, opts)
	strokes, infoByRoad = {}, {}
	stats = { strokes = 0, segments = 0, spanStations = 0, fillStations = 0, streetBridges = 0, maxFill = 0 }
	local toStuds, terrainY, isRail = opts.sourceToStuds, opts.terrainY, opts.isRail

	-- 1. rail segments and nodes
	local segs, nodes = {}, {}
	local function nk(x, z) return math.floor(x + 0.5) .. ":" .. math.floor(z + 0.5) end
	local others = {}
	for _, entry in ipairs(entries) do
		local road = entry.road
		local ax, az = toStuds(road.x1, road.z1)
		local bx, bz = toStuds(road.x2, road.z2)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if len > 0.05 then
			if isRail(tostring(road.name or "")) then
				local seg = { road = road, ax = ax, az = az, bx = bx, bz = bz, len = len, name = tostring(road.name) }
				table.insert(segs, seg)
				for e, p in ipairs({ { ax, az }, { bx, bz } }) do
					local k = seg.name .. "|" .. nk(p[1], p[2])
					nodes[k] = nodes[k] or {}
					table.insert(nodes[k], { seg = seg, e = e })
					seg["k" .. e] = k
				end
			else
				table.insert(others, { road = road, ax = ax, az = az, bx = bx, bz = bz })
			end
		end
	end
	stats.segments = #segs
	-- grid of the other roads for crossing tests (kept for ClearOfStreets)
	local CELL = STREET_CELL
	local grid = {}
	streetGrid = grid
	for _, o in ipairs(others) do
		for gx = math.floor(math.min(o.ax, o.bx) / CELL), math.floor(math.max(o.ax, o.bx) / CELL) do
			for gz = math.floor(math.min(o.az, o.bz) / CELL), math.floor(math.max(o.az, o.bz) / CELL) do
				local k = gx .. ":" .. gz
				grid[k] = grid[k] or {}
				table.insert(grid[k], o)
			end
		end
	end
	local function candidates(x0, z0, x1, z1)
		local out, seen = {}, {}
		for gx = math.floor(math.min(x0, x1) / CELL), math.floor(math.max(x0, x1) / CELL) do
			for gz = math.floor(math.min(z0, z1) / CELL), math.floor(math.max(z0, z1) / CELL) do
				for _, o in ipairs(grid[gx .. ":" .. gz] or {}) do
					if not seen[o] then seen[o] = true table.insert(out, o) end
				end
			end
		end
		return out
	end

	-- 2. strokes: straightest continuation at each node
	local visited = {}
	local function dirFrom(seg, e)
		-- unit direction leaving the node at end e along the segment
		if e == 1 then return (seg.bx - seg.ax) / seg.len, (seg.bz - seg.az) / seg.len end
		return (seg.ax - seg.bx) / seg.len, (seg.az - seg.bz) / seg.len
	end
	local function nextFrom(seg, e)
		-- arriving at seg's end e: pick the unvisited segment leaving that node
		-- straightest ahead
		local inx, inz = dirFrom(seg, e)       -- leaves node back along seg
		local best, bestDot
		for _, arm in ipairs(nodes[seg["k" .. e]] or {}) do
			if arm.seg ~= seg and not visited[arm.seg] then
				local ox, oz = dirFrom(arm.seg, arm.e)
				local dot = inx * ox + inz * oz      -- straight ahead => -1
				if dot < -0.6 and (not bestDot or dot < bestDot) then best, bestDot = arm, dot end
			end
		end
		return best
	end
	for _, start in ipairs(segs) do
		if not visited[start] then
			visited[start] = true
			local chain = { { seg = start, forward = true } }
			-- extend forward from end 2
			local cur, e = start, 2
			while true do
				local arm = nextFrom(cur, e)
				if not arm then break end
				visited[arm.seg] = true
				table.insert(chain, { seg = arm.seg, forward = arm.e == 1 })
				cur, e = arm.seg, (arm.e == 1) and 2 or 1
			end
			-- extend backward from end 1
			cur, e = start, 1
			while true do
				local arm = nextFrom(cur, e)
				if not arm then break end
				visited[arm.seg] = true
				table.insert(chain, 1, { seg = arm.seg, forward = arm.e == 2 })
				cur, e = arm.seg, (arm.e == 1) and 2 or 1
			end
			table.insert(strokes, { parts = chain })
		end
	end

	-- 3-6. profile each stroke
	for strokeIndex, stroke in ipairs(strokes) do
		if opts.yield and strokeIndex % 4 == 0 then opts.yield() end
		-- polyline and stations
		local px, pz, ps = {}, {}, {}
		local s = 0
		for i, item in ipairs(stroke.parts) do
			local seg = item.seg
			local x0, z0, x1, z1 = seg.ax, seg.az, seg.bx, seg.bz
			if not item.forward then x0, z0, x1, z1 = x1, z1, x0, z0 end
			if i == 1 then table.insert(px, x0) table.insert(pz, z0) table.insert(ps, 0) end
			item.s0 = s
			s += seg.len
			item.s1 = s
			table.insert(px, x1) table.insert(pz, z1) table.insert(ps, s)
			infoByRoad[seg.road] = { stroke = stroke, item = item }
		end
		stroke.length = s
		local n = math.max(1, math.ceil(s / STEP))
		local ds = s / n
		stroke.ds = ds
		local function at(st)
			local lo = 1
			while lo < #ps - 1 and ps[lo + 1] < st do lo += 1 end
			local span = ps[lo + 1] - ps[lo]
			local f = span > 1e-6 and math.clamp((st - ps[lo]) / span, 0, 1) or 0
			return lerp(px[lo], px[lo + 1], f), lerp(pz[lo], pz[lo + 1], f)
		end
		local t, xs, zs = {}, {}, {}
		local known
		for i = 1, n + 1 do
			local x, z = at((i - 1) * ds)
			xs[i], zs[i] = x, z
			t[i] = terrainY(x, z)
			if t[i] then known = t[i] end
		end
		if not known then
			stroke.G = nil
		else
			-- fill missing samples
			local last
			for i = 1, #t do
				if t[i] then
					if last and last < i - 1 then
						for j = last + 1, i - 1 do t[j] = lerp(t[last], t[i], (j - last) / (i - last)) end
					elseif not last then
						for j = 1, i - 1 do t[j] = t[i] end
					end
					last = i
				end
			end
			for j = (last or #t) + 1, #t do t[j] = t[last] end

			local count = #t
			-- a. spikes
			local sw = math.max(1, math.floor(SPIKE_WINDOW / ds / 2 + 0.5))
			local minL, minR = windowExtremes(t, sw, false)
			local c = table.create(count)
			for i = 1, count do c[i] = math.min(t[i], math.max(minL[i], minR[i])) end
			-- b. notches
			local nw = math.max(1, math.floor(NOTCH_WINDOW / ds / 2 + 0.5))
			local maxL, maxR = windowExtremes(c, nw, true)
			local f = table.create(count)
			for i = 1, count do f[i] = math.max(c[i], math.min(maxL[i], maxR[i])) end

			-- c. streets crossing under the line. Judged against the profile the
			-- line ends up on: the grade envelope lifts it further over streets
			-- that looked close to its level first (Upland, Welsh, Morton ...),
			-- so detection repeats on the smoothed profile until nothing new
			-- turns up.
			local spanMask = table.create(count, false)
			stroke.crossings = {}
			-- a street end this close to the centreline meets the line (the
			-- county stops streets at the edge of a wide bed: Concord Ave at the NEC)
			local reach2 = 16 * 16
			local function detectCrossings(level)
			local added = 0
			for i = 1, #px - 1 do
				for _, o in ipairs(candidates(px[i], pz[i], px[i + 1], pz[i + 1])) do
					do
						local tt, uu = segIntersect(px[i], pz[i], px[i + 1], pz[i + 1], o.ax, o.az, o.bx, o.bz)
						if not tt then
							-- the county splits a street where it meets the track:
							-- an end of the street lying on the line is a crossing too
							local rx, rz = px[i + 1] - px[i], pz[i + 1] - pz[i]
							local r2 = rx * rx + rz * rz
							if r2 > 1e-6 then
								for e, q in ipairs({ { o.ax, o.az }, { o.bx, o.bz } }) do
									local w = ((q[1] - px[i]) * rx + (q[2] - pz[i]) * rz) / r2
									-- (also a street stopping just short of the line at
									-- a bridge abutment; never one running alongside)
									local ox, oz = o.bx - o.ax, o.bz - o.az
									local ol = math.sqrt(ox * ox + oz * oz)
									local along = ol > 1e-6 and math.abs((ox * rx + oz * rz) / (ol * math.sqrt(r2))) or 1
									-- (w may be 0 / 1: the street often ends ON a rail vertex)
									if w >= 0 and w <= 1 and along < 0.85 then
										local cx, cz = px[i] + rx * w, pz[i] + rz * w
										if (q[1] - cx) ^ 2 + (q[2] - cz) ^ 2 < reach2 then
											tt, uu = w, (e == 1) and 0 or 1
											break
										end
									end
								end
							end
						end
						if tt then
							local stHere = lerp(ps[i], ps[i + 1], tt)
							for _, c in ipairs(stroke.crossings) do
								if math.abs(c.s - stHere) < 10 and c.name == tostring(o.road.name or "") then
									tt = nil
									break
								end
							end
						end
						if tt then
							local st = lerp(ps[i], ps[i + 1], tt)
							local k = math.clamp(math.floor(st / ds + 0.5) + 1, 1, count)
							local gx, gz = lerp(o.ax, o.bx, uu), lerp(o.az, o.bz, uu)
							-- the DEM carries the railway embankment over the
							-- street (Concord Ave): take the street's lowest ground
							-- within 36 studs either side, clear of the bed
							local street = terrainY(gx, gz) or t[k]
							do
								local ox, oz = o.bx - o.ax, o.bz - o.az
								local ol = math.sqrt(ox * ox + oz * oz)
								if ol > 1e-6 then
									for _, d in ipairs({ -36, -24, -12, 12, 24, 36 }) do
										local u = math.clamp(uu + d / ol, 0, 1)
										local y = terrainY(lerp(o.ax, o.bx, u), lerp(o.az, o.bz, u))
										if y then street = math.min(street, y) end
									end
								end
							end
							if level[k] - street > OVER_STREET_MIN then
								local width = math.max((tonumber(o.road.width_m) or 7) * 3, 6)
								local need = street + STREET_CLEARANCE + DECK
								-- the opening along the line: street + sidewalks,
								-- longer where the street crosses at an angle
								local rx, rz = px[i + 1] - px[i], pz[i + 1] - pz[i]
								local ox, oz = o.bx - o.ax, o.bz - o.az
								local rl, ol = math.sqrt(rx * rx + rz * rz), math.sqrt(ox * ox + oz * oz)
								local sin = (rl > 1e-6 and ol > 1e-6) and math.abs(rx * oz - rz * ox) / (rl * ol) or 1
								local half = math.min((width / 2 + 10) / math.max(sin, 0.4), 90)
								for m = math.max(1, math.floor((st - half) / ds) + 1), math.min(count, math.ceil((st + half) / ds) + 1) do
									f[m] = math.max(f[m], need)
									spanMask[m] = true
								end
								stats.streetBridges += 1
								added += 1
								table.insert(stroke.crossings, { s = st, half = half, name = tostring(o.road.name or "") })
							end
						end
					end
				end
			end
			return added
			end

			-- d. grade envelope (raise only) and a light rounding
			local g = GRADE * ds
			local function smooth()
				for i = 2, count do f[i] = math.max(f[i], f[i - 1] - g) end
				for i = count - 1, 1, -1 do f[i] = math.max(f[i], f[i + 1] - g) end
				local G = table.clone(f)
				for _ = 1, 2 do
					local avg = table.create(count)
					for i = 1, count do
						local lo, hi = math.max(1, i - 3), math.min(count, i + 3)
						local sum = 0
						for k = lo, hi do sum += G[k] end
						avg[i] = sum / (hi - lo + 1)
					end
					for i = 1, count do G[i] = math.max(avg[i], f[i] - 0.3) end
				end
				for i = 2, count do G[i] = math.max(G[i], G[i - 1] - g) end
				for i = count - 1, 1, -1 do G[i] = math.max(G[i], G[i + 1] - g) end
				return G
			end
			detectCrossings(f)
			local G = smooth()
			for _ = 1, 4 do
				if detectCrossings(G) == 0 then break end
				G = smooth()
			end

			-- e. classify
			local kind = table.create(count, "grade")
			for i = 1, count do
				local fill = G[i] - t[i]
				stats.maxFill = math.max(stats.maxFill, fill)
				if spanMask[i] or fill > SPAN_FILL then
					kind[i] = "span"
					stats.spanStations += 1
				elseif fill > 1.5 then
					kind[i] = "fill"
					stats.fillStations += 1
				end
			end
			stroke.G, stroke.t, stroke.kind = G, t, kind
		end
		stats.strokes += 1
	end
end

function RailProfile.Info(road)
	return infoByRoad[road]
end

local function stationIndex(stroke, st)
	return math.clamp(st / stroke.ds, 0, #stroke.G - 1)
end

-- station along the stroke of a road at fraction f of ITS OWN x1->x2 direction
local function stationOf(info, f)
	local item = info.item
	local frac = item.forward and f or (1 - f)
	return item.s0 + (item.s1 - item.s0) * frac
end

function RailProfile.HeightAt(info, f)
	local stroke = info.stroke
	if not stroke.G then return nil end
	local x = stationIndex(stroke, stationOf(info, f))
	local i = math.min(math.floor(x), #stroke.G - 2)
	return lerp(stroke.G[i + 1], stroke.G[i + 2], x - i)
end

function RailProfile.GroundAt(info, f)
	local stroke = info.stroke
	if not stroke.t then return nil end
	local x = stationIndex(stroke, stationOf(info, f))
	local i = math.min(math.floor(x), #stroke.t - 2)
	return lerp(stroke.t[i + 1], stroke.t[i + 2], x - i)
end

function RailProfile.KindAt(info, f)
	local stroke = info.stroke
	if not stroke.kind then return "grade" end
	local i = math.floor(stationIndex(stroke, stationOf(info, f)) + 0.5) + 1
	return stroke.kind[math.clamp(i, 1, #stroke.kind)]
end

function RailProfile.StationAt(info, f)
	return stationOf(info, f)
end

-- is station st inside the opening of a street the line bridges?
function RailProfile.OverStreet(info, st)
	for _, c in ipairs(info.stroke.crossings or {}) do
		if math.abs(st - c.s) < c.half then return true end
	end
	return false
end

-- false when a pier / abutment footprint of radius r at (x, z) would stand on
-- a street, its junction or its sidewalks (any non-rail road centreline
-- closer than its half width + sidewalk + r)
function RailProfile.ClearOfStreets(x, z, r)
	local gx, gz = math.floor(x / STREET_CELL), math.floor(z / STREET_CELL)
	for ix = gx - 1, gx + 1 do
		for iz = gz - 1, gz + 1 do
			for _, o in ipairs(streetGrid[ix .. ":" .. iz] or {}) do
				local vx, vz = o.bx - o.ax, o.bz - o.az
				local l2 = vx * vx + vz * vz
				local u = l2 > 1e-6 and math.clamp(((x - o.ax) * vx + (z - o.az) * vz) / l2, 0, 1) or 0
				local dx, dz = x - (o.ax + vx * u), z - (o.az + vz * u)
				local half = math.max((tonumber(o.road.width_m) or 7) * 3, 6) / 2 + 6
				if dx * dx + dz * dz < (half + r) ^ 2 then return false end
			end
		end
	end
	return true
end

function RailProfile.Stats()
	return stats
end

return RailProfile
