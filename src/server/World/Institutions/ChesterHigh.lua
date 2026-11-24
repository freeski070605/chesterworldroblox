-- Chester High School, 200 W 9th Street (county building 155084).
--
-- Evidence (private reference, not redistributed):
--   * county footprint polygon (50 vertices) - the plan below is that polygon
--     split into its real parts, in the building frame of the tile record
--     (origin = rect 2 centre, a = 117.99): u runs ENE along W 9th, v NNW
--   * DVRPC 2025 1 m aerial: white membrane roof over the gym/auditorium,
--     raised stage box at its west end, gravel-roofed classroom pods, grey
--     central spine with a penthouse
--   * Google Street View 2019-2026, 42 views round the building
--     (Data/25_GoogleStreetView_Buildings/images/155084): bowed W 9th front
--     with a recessed glazed entrance bay between curved brick shoulders over
--     a cantilevered concrete balcony on two posts, brick planter terraces,
--     slot windows and tall stone-framed window groups, rounded corners with
--     a cream metal coping, four-storey dark brick pods with paired windows,
--     the Barclay Street plaza with round planters, and the two signs:
--     a tapered stone monument "CHESTER / HIGH SCHOOL" and a black pylon with
--     orange "CHESTER HIGH SCHOOL" faces over an LED board.
local ChesterHigh = {}

local ORIGIN = { 7749.42, 7030.78 }
local A = 117.99

-- plan (source metres, building frame)
local GYM = {
	{ -70.6, -23.2 }, { 0.4, -42.6 }, { 70.6, -23.8 }, { 70.6, 32.3 }, { 50.0, 32.2 },
	{ 51.9, 39.2 }, { -13.7, 39.2 }, { -33.1, 34.0 }, { -70.6, 23.9 },
}
local STAGE = { { -58, -10 }, { -38, -10 }, { -38, 15 }, { -58, 15 } }
local WPOD = {
	{ -56.0, 165.0 }, { -66.8, 124.8 }, { -56.0, 84.6 }, { -49.9, 83.0 }, { -28.8, 83.0 },
	{ -21.4, 110.7 }, { -22.3, 144.8 }, { -28.4, 167.3 }, { -54.8, 167.3 },
}
local EPOD = {
	{ 21.6, 83.0 }, { 28.4, 57.4 }, { 41.3, 54.0 }, { 49.9, 56.3 }, { 56.0, 54.6 },
	{ 67.6, 98.1 }, { 57.7, 135.0 }, { 30.5, 142.3 }, { 22.0, 110.7 },
}
local SPINE = {
	{ -22.3, 144.8 }, { -21.4, 110.7 }, { -13.2, 110.7 }, { -6.5, 85.9 }, { -5.7, 83.0 },
	{ 14.6, 83.0 }, { 21.6, 83.0 }, { 22.0, 110.7 }, { 14.2, 110.7 }, { 7.1, 137.0 },
}
local CONN = {
	{ -24.8, 39.3 }, { 6.0, 39.3 }, { 4.7, 44.2 }, { 11.9, 46.1 }, { 11.8, 72.7 },
	{ 14.6, 83.0 }, { -5.7, 83.0 }, { -4.3, 77.6 }, { -21.8, 77.6 }, { -24.9, 66.1 },
}
-- edges (index i = vertex i -> i+1) that are cuts between parts: no windows
local CUTS = {
	WPOD = { [6] = true, [3] = true, [9] = true },
	EPOD = { [9] = true, [3] = true, [4] = true },
	SPINE = { [1] = true, [5] = true, [7] = true, [4] = true },
	CONN = { [1] = true, [6] = true, [2] = true, [3] = true, [7] = true },
}

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local GYM_BRICK = rgb(148, 80, 62)
local POD_BRICK = rgb(100, 52, 46)
local SPINE_BRICK = rgb(106, 56, 48)
local COPING = rgb(216, 205, 176)
local STONE = rgb(214, 203, 178)
local GLASS = rgb(36, 41, 47)
local ROOF_WHITE = rgb(226, 226, 221)
local GRAVEL = rgb(156, 142, 120)
local ROOF_GREY = rgb(138, 138, 134)
local CONCRETE = rgb(196, 190, 178)
local BLACK = rgb(28, 28, 30)
local ORANGE = rgb(214, 74, 34)

function ChesterHigh.Build(b, spec, ctx, Shapes)
	local S = ctx.S
	local function H(m) return m * S end          -- true metres, vertical
	local function L(m) return m * S * 1.3 end    -- true metres, horizontal (world is mercator-scaled)
	local F = Shapes.frame(ctx, ORIGIN, A)
	local brick = Enum.Material.Brick

	local function volume(name, poly, height, opts)
		local ids
		if opts.round then poly, ids = Shapes.round(poly, "convex", opts.round, 4, opts.keep) end
		local lo, mean = Shapes.groundOf(F, poly)
		local ground = opts.ground or (opts.fromLowest and lo or mean)
		local top = ground + H(height)
		local edges = Shapes.extrude(b, F, poly, {
			name = name, base = (opts.base or lo) - 1.5, top = top, material = opts.material or brick,
			color = opts.color, t = 2, coping = opts.coping, roof = opts.roof, ids = ids,
		})
		return edges, ground, top, lo
	end

	-------------------------------------------------------------- gym / auditorium
	local gymPoly = Shapes.round(GYM, { 1, 3, 4, 9 }, 7, 5)
	-- one floor level at the W 9th entrance (the site falls ~6 m from Barclay
	-- St to Booth St; the street front is the photographed datum)
	local gymEdges, gymGround, gymTop, gymLo = volume("Walls", gymPoly, 13, {
		ground = F.ground(0, -52), color = GYM_BRICK, coping = { h = H(0.7), color = COPING, out = 0.5 }, roof = { color = ROOF_WHITE },
	})
	-- raised stage box at the west end (aerial + views from Barclay / W 9th)
	volume("StageWalls", STAGE, 18.5, {
		ground = gymGround, base = gymTop - 2, color = GYM_BRICK,
		coping = { h = H(0.6), color = COPING, out = 0.4 }, roof = { color = ROOF_WHITE },
	})
	-- rooftop units seen on the white membrane
	for _, p in ipairs({ { -20, 5 }, { 10, -8 }, { 35, 12 }, { 52, -6 } }) do
		local c = F.pt(p[1], p[2])
		b:part("RoofUnit", Vector3.new(L(3), H(1.6), L(2.2)), CFrame.new(c.X, gymTop + H(0.8), c.Z) * CFrame.lookAt(Vector3.zero, F.dir(1, 0)).Rotation,
			Enum.Material.Metal, rgb(176, 178, 176))
	end

	local function group(u, v, g)
		local e, x = Shapes.edgeAt(F, gymEdges, u, v)
		Shapes.group(b, e, x, gymGround, {
			n = g.n, w = L(g.w), h = H(g.h), sill = H(g.sill), gap = L(g.gap or 0.35), frame = g.frame and STONE or nil,
		}, GLASS, GYM_BRICK, brick)
	end
	local function door(u, v, w, h)
		local e, x = Shapes.edgeAt(F, gymEdges, u, v)
		b:part("DoorSurround", Vector3.new(L(w) + 1.2, H(h) + 0.8, 0.3), e.face * CFrame.new(x, gymGround + H(h) / 2 + 0.2, -0.1),
			Enum.Material.Metal, rgb(60, 60, 62))
		b:part("Door", Vector3.new(L(w), H(h), 0.3), e.face * CFrame.new(x, gymGround + H(h) / 2, -0.25), Enum.Material.Metal, rgb(44, 46, 50))
	end
	-- W 9th front: a row of six slot windows each side of the entrance, a tall
	-- four-light group near each rounded corner, a side door at the steps
	for side = -1, 1, 2 do
		for k = 0, 5 do
			group(side * (17 + k * 3.1), -36, { n = 1, w = 0.75, h = 2.6, sill = 4.6 })
		end
		group(side * 56, -28, { n = 4, w = 0.75, h = 5.6, sill = 4.0, frame = true })
		door(side * 43, -32, 1.8, 2.4)
	end
	-- east end (Booth St side): two tall triples over four lower groups
	group(70.6, -8, { n = 3, w = 0.8, h = 5.4, sill = 6.2, frame = true })
	group(70.6, 14, { n = 3, w = 0.8, h = 5.4, sill = 6.2, frame = true })
	group(70.6, -16, { n = 2, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	group(70.6, -2, { n = 3, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	group(70.6, 8, { n = 3, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	group(70.6, 22, { n = 2, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	-- north side toward the east parking lot
	group(40, 39.2, { n = 2, w = 0.8, h = 5.0, sill = 6.0, frame = true })
	group(22, 39.2, { n = 3, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	group(62, 32.3, { n = 3, w = 1.0, h = 1.8, sill = 2.4, frame = true })
	-- plaza door on the curved north-west wall
	door(-52, 29, 2.0, 2.6)

	-------------------------------------------------------------- entrance bay
	do
		local apex = F.pt(0.4, -42.6)
		local out = -F.dir(0, 1)
		local E = CFrame.lookAt(apex, apex + out)
		local g = gymGround
		-- bay mass with curved brick shoulders round the tall glazing
		b:part("EntranceBay", Vector3.new(L(11), gymTop - g + 1, 6), E * CFrame.new(0, (gymTop + g) / 2 - 1, 1), brick, GYM_BRICK, true)
		b:part("Coping", Vector3.new(L(11) + 1, H(0.7), 7), E * CFrame.new(0, gymTop - H(0.35) + 0.3, 1), Enum.Material.SmoothPlastic, COPING)
		for side = -1, 1, 2 do
			local s = b:part("Shoulder", Vector3.new(gymTop - g - H(5.3), 6, 6),
				E * CFrame.new(side * L(3.9), (gymTop + g + H(5.3)) / 2 - 0.5, -2) * CFrame.Angles(0, 0, math.pi / 2), brick, GYM_BRICK)
			s.Shape = Enum.PartType.Cylinder
		end
		local gw = 2 * L(3.9) - 4
		b:part("BayGlass", Vector3.new(gw, H(5.8), 0.4), E * CFrame.new(0, g + H(5.4) + H(2.9), -2.4), Enum.Material.Glass, GLASS)
		for k = -1, 1 do
			b:part("BayMullion", Vector3.new(0.35, H(5.8), 0.5), E * CFrame.new(k * gw / 4, g + H(8.3), -2.6), Enum.Material.Metal, rgb(70, 72, 76))
		end
		b:part("BayTransom", Vector3.new(gw, 0.35, 0.5), E * CFrame.new(0, g + H(9.6), -2.6), Enum.Material.Metal, rgb(70, 72, 76))
		b:part("BayHead", Vector3.new(gw + 2, H(0.6), 3), E * CFrame.new(0, g + H(11.5), -2), brick, GYM_BRICK)
		-- cantilevered balcony slab on two posts, metal rail
		local depth = L(3.6)
		local slabW = L(17)
		local slabY = g + H(4.3)
		b:part("Balcony", Vector3.new(slabW, H(1.0), depth + 4), E * CFrame.new(0, slabY + H(0.5), -2 - depth / 2 - 2), Enum.Material.Concrete, CONCRETE, true)
		for side = -1, 1, 2 do
			b:part("BalconyPost", Vector3.new(L(0.6), H(4.3), L(0.6)), E * CFrame.new(side * L(4.8), g + H(2.15), -2 - depth + 1), Enum.Material.Concrete, rgb(220, 216, 206), true)
		end
		local railY = slabY + H(1.0) + H(0.55)
		b:part("Rail", Vector3.new(slabW, 0.25, 0.25), E * CFrame.new(0, railY + H(0.5), -2 - depth - 3.5), Enum.Material.Metal, rgb(120, 124, 128))
		for k = 0, 8 do
			b:part("RailPost", Vector3.new(0.2, H(1.0), 0.2), E * CFrame.new(-slabW / 2 + 0.5 + k * (slabW - 1) / 8, railY, -2 - depth - 3.5), Enum.Material.Metal, rgb(120, 124, 128))
		end
		-- recessed entry doors under the balcony
		b:part("EntryRecess", Vector3.new(L(10.5), H(4.2), 0.4), E * CFrame.new(0, g + H(2.1), -2.1), Enum.Material.SmoothPlastic, rgb(30, 30, 32))
		for k = -2, 2 do
			b:part("EntryDoor", Vector3.new(L(1.7), H(2.5), 0.3), E * CFrame.new(k * L(1.95), g + H(1.25), -2.35), Enum.Material.Glass, rgb(58, 66, 72))
		end
		b:part("EntryPaving", Vector3.new(L(13), 8, L(20)), E * CFrame.new(0, g + 0.3 - 4, -L(10)), Enum.Material.Concrete, rgb(206, 198, 184), true)
	end

	-- brick planter terraces along both halves of the bowed front, lawn on top,
	-- concrete steps at their outer ends
	for side = -1, 1, 2 do
		local e, xa = Shapes.edgeAt(F, gymEdges, side * 8, -40)
		local _, xb = Shapes.edgeAt(F, gymEdges, side * 37, -33)
		local x0, x1 = math.min(xa, xb), math.max(xa, xb)
		local w = x1 - x0
		local cx = (x0 + x1) / 2
		local d = L(6)
		-- retaining walls: the lawn rises toward Barclay St behind them
		local wallPt = e.mid + e.right * cx - e.n * d
		local behind = ctx.terrainY(wallPt.X, wallPt.Z) or gymGround
		local th = math.max(H(3.2), behind - gymGround + 1.5)
		b:part("TerraceWall", Vector3.new(w, th + 1.5, 1.6), e.face * CFrame.new(cx, gymGround + (th - 1.5) / 2, -d), brick, GYM_BRICK, true)
		b:part("TerraceLawn", Vector3.new(w, 0.8, d - 0.8), e.face * CFrame.new(cx, gymGround + th - 0.3, -d / 2), Enum.Material.Grass, rgb(98, 138, 62), true)
		b:part("TerraceCap", Vector3.new(w, 0.4, 1.9), e.face * CFrame.new(cx, gymGround + th + 0.2, -d), Enum.Material.Concrete, CONCRETE)
		-- steps: a concrete flight down from the outer end of the terrace
		local outerX = (xa < xb) and x1 or x0
		local dirX = (xa < xb) and 1 or -1
		local stairs = b:wedge("Steps", Vector3.new(d, th, L(4)), e.face * CFrame.new(outerX + dirX * L(2), gymGround + th / 2, -d / 2)
			* CFrame.Angles(0, dirX > 0 and -math.pi / 2 or math.pi / 2, 0), Enum.Material.Concrete, CONCRETE)
		stairs.CanCollide = true
		for _, rx in ipairs({ -d * 0.45, d * 0.45 }) do
			b:part("StepRail", Vector3.new(L(4.2), 0.25, 0.25), e.face * CFrame.new(outerX + dirX * L(2), gymGround + th / 2 + H(1), rx - d / 2)
				* CFrame.Angles(0, 0, -dirX * math.atan2(th, L(4))), Enum.Material.Metal, rgb(170, 172, 170))
		end
	end

	-------------------------------------------------------------- classroom pods + spine + connector
	local function punchAll(edges, cuts, o)
		for _, e in ipairs(edges) do
			if not cuts[e.i] and e.len > o.bay + 2 * (o.margin or 6) then
				Shapes.punched(b, e, o)
			end
		end
	end
	for _, pod in ipairs({ { WPOD, CUTS.WPOD, { -44, 125 }, { [6] = true, [7] = true } }, { EPOD, CUTS.EPOD, { 45, 100 }, { [9] = true, [1] = true } } }) do
		local edges, _, top, lo = volume("PodWalls", pod[1], 15.6, {
			round = 4, keep = pod[4],
			fromLowest = true, color = POD_BRICK, coping = { h = H(0.4), color = rgb(176, 160, 140), out = 0.3 },
			roof = { color = GRAVEL, material = Enum.Material.Slate },
		})
		punchAll(edges, pod[2], {
			ground = lo, floors = 4, storey = H(3.6), sill = H(1.1), h = H(1.8), w = L(0.85), n = 2, gap = L(0.4),
			bay = L(3.7), margin = L(2.4), glass = GLASS, wall = POD_BRICK, wallMat = brick,
		})
		-- rooftop stair / lift penthouse (aerial)
		local c = F.pt(pod[3][1], pod[3][2])
		b:part("Penthouse", Vector3.new(L(5), H(2.8), L(4)), CFrame.new(c.X, top + H(1.4), c.Z) * CFrame.lookAt(Vector3.zero, F.dir(0, 1)).Rotation,
			brick, POD_BRICK)
	end
	do
		local edges, _, top, lo = volume("SpineWalls", SPINE, 11.4, {
			round = 3, keep = { [1] = true, [2] = true, [5] = true, [6] = true, [7] = true, [8] = true },
			fromLowest = true, color = SPINE_BRICK, coping = { h = H(0.5), color = COPING, out = 0.3 }, roof = { color = ROOF_GREY },
		})
		punchAll(edges, CUTS.SPINE, {
			ground = lo, floors = 3, storey = H(3.6), sill = H(1.1), h = H(1.8), w = L(0.85), n = 2, gap = L(0.4),
			bay = L(4.4), margin = L(2), glass = GLASS, wall = SPINE_BRICK, wallMat = brick,
		})
		local c = F.pt(-6, 132)
		b:part("Penthouse", Vector3.new(L(9), H(3), L(7)), CFrame.new(c.X, top + H(1.5), c.Z) * CFrame.lookAt(Vector3.zero, F.dir(0, 1)).Rotation,
			Enum.Material.Concrete, rgb(170, 166, 158))
	end
	do
		-- low entrance connector: glass under a deep cream fascia (plaza photo)
		local edges, ground = volume("ConnectorWalls", CONN, 5.6, {
			color = GYM_BRICK, coping = { h = H(1.7), color = COPING, out = 1.2 }, roof = { color = ROOF_GREY },
		})
		for _, e in ipairs(edges) do
			if not CUTS.CONN[e.i] and e.len > 8 then
				b:part("CurtainGlass", Vector3.new(e.len - 3, H(3.6), 0.3), e.face * CFrame.new(0, ground + H(1.9), -0.15), Enum.Material.Glass, GLASS)
				local mullions = math.floor(e.len / L(1.8))
				for k = 1, mullions - 1 do
					b:part("CurtainMullion", Vector3.new(0.3, H(3.6), 0.45), e.face * CFrame.new(-e.len / 2 + k * e.len / mullions, ground + H(1.9), -0.3), Enum.Material.Metal, rgb(66, 68, 70))
				end
			end
		end
	end

	-------------------------------------------------------------- Barclay St plaza
	do
		local plaza = { { -79, 21 }, { -70.6, 24.5 }, { -33.1, 35 }, { -24.9, 40 }, { -24.9, 77 }, { -28.8, 83 }, { -49.9, 83 }, { -56, 84.6 }, { -79, 84 } }
		local pts = {}
		local _, mean = Shapes.groundOf(F, plaza)
		for i, p in ipairs(plaza) do pts[i] = F.pt(p[1], p[2]) end
		Shapes.slab(b, "Plaza", pts, mean + 0.15, 1.6, Enum.Material.Concrete, rgb(200, 192, 178))
		for _, p in ipairs({ { -58, 46 }, { -44, 58 }, { -62, 66 }, { -40, 72 } }) do
			local c = F.pt(p[1], p[2])
			local y = (F.ground(p[1], p[2]) or mean)
			local pl = b:part("Planter", Vector3.new(H(0.8), L(2.6), L(2.6)), CFrame.new(c.X, math.max(y, mean) + H(0.4), c.Z) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Concrete, rgb(206, 200, 188), true)
			pl.Shape = Enum.PartType.Cylinder
			local shrub = b:part("Shrub", Vector3.new(L(1.8), H(1.0), L(1.8)), CFrame.new(c.X, math.max(y, mean) + H(1.1), c.Z), Enum.Material.Grass, rgb(62, 104, 52))
			shrub.Shape = Enum.PartType.Ball
		end
		for _, p in ipairs({ { -66, 36 }, { -36, 48 }, { -52, 78 }, { -74, 60 } }) do
			local c = F.pt(p[1], p[2])
			local y = math.max(F.ground(p[1], p[2]) or mean, mean)
			b:part("LampPost", Vector3.new(0.6, H(4.6), 0.6), CFrame.new(c.X, y + H(2.3), c.Z), Enum.Material.Metal, rgb(52, 54, 56))
			local head = b:part("LampHead", Vector3.new(1.6, 1.6, 1.6), CFrame.new(c.X, y + H(4.6) + 0.6, c.Z), Enum.Material.SmoothPlastic, rgb(234, 232, 220))
			head.Shape = Enum.PartType.Ball
		end
		local fp = F.pt(-31, 58)
		b:part("Flagpole", Vector3.new(0.4, H(10), 0.4), CFrame.new(fp.X, mean + H(5), fp.Z), Enum.Material.Metal, rgb(200, 202, 204))
	end

	-------------------------------------------------------------- W 9th front lawn
	for _, p in ipairs({ { -17, -71 }, { -9.5, -71 } }) do
		local c = F.pt(p[1], p[2])
		local y = F.ground(p[1], p[2]) or gymGround
		local pl = b:part("Planter", Vector3.new(H(0.7), L(2.2), L(2.2)), CFrame.new(c.X, y + H(0.35), c.Z) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Concrete, rgb(214, 208, 196), true)
		pl.Shape = Enum.PartType.Cylinder
		b:part("TreeTrunk", Vector3.new(0.9, H(5), 0.9), CFrame.new(c.X, y + H(3), c.Z), Enum.Material.Wood, rgb(120, 104, 88))
		local crown = b:part("TreeCrown", Vector3.new(L(4), H(3.6), L(4)), CFrame.new(c.X, y + H(6.6), c.Z), Enum.Material.Grass, rgb(84, 116, 58))
		crown.Shape = Enum.PartType.Ball
	end
	for _, p in ipairs({ { -55, -58 }, { -33, -64 }, { 30, -64 }, { 54, -58 } }) do
		local c = F.pt(p[1], p[2])
		local y = F.ground(p[1], p[2]) or gymGround
		b:part("LampPost", Vector3.new(0.6, H(4.6), 0.6), CFrame.new(c.X, y + H(2.3), c.Z), Enum.Material.Metal, rgb(52, 54, 56))
		local head = b:part("LampHead", Vector3.new(1.6, 1.6, 1.6), CFrame.new(c.X, y + H(4.6) + 0.6, c.Z), Enum.Material.SmoothPlastic, rgb(234, 232, 220))
		head.Shape = Enum.PartType.Ball
	end

	-------------------------------------------------------------- signs (W 9th & Barclay corner lawn)
	do
		-- tapered stone monument, incised serif lettering, faces the corner
		local c = F.pt(-75, -64.5)
		local y = F.ground(-75, -64.5) or gymGround
		local toCam = (F.pt(-65.2, -79.6) - c).Unit
		local M = CFrame.lookAt(Vector3.new(c.X, y, c.Z), Vector3.new(c.X, y, c.Z) + toCam)
		local w, h, d = L(2.6), H(1.15), L(0.7)
		local face = b:part("CHS_Monument", Vector3.new(w, h + 1, d), M * CFrame.new(0, (h - 1) / 2, 0), Enum.Material.Limestone, rgb(190, 178, 154), true)
		for side = -1, 1, 2 do
			b:wedge("MonumentTaper", Vector3.new(d, h + 1, L(0.45)), M * CFrame.new(side * (w / 2 + L(0.225)), (h - 1) / 2, 0)
				* CFrame.Angles(0, side < 0 and math.pi / 2 or -math.pi / 2, 0), Enum.Material.Limestone, rgb(206, 196, 176))
		end
		b:part("MonumentCap", Vector3.new(w + L(0.4), H(0.22), d + 0.6), M * CFrame.new(0, h + H(0.11), 0), Enum.Material.Limestone, rgb(214, 205, 186))
		local signY = 0.18
		Shapes.signText(face, Enum.NormalId.Front, {
			{ text = "C H E S T E R", size = 0.42, y = signY, x = 0.08, wScale = 0.84, font = Enum.Font.Garamond, color = rgb(44, 38, 32) },
			{ text = "H I G H   S C H O O L", size = 0.26, y = signY + 0.44, x = 0.18, wScale = 0.64, font = Enum.Font.Garamond, color = rgb(44, 38, 32) },
		}, 30)
	end
	do
		-- black pylon, orange faces both ways along W 9th, LED board below
		local c = F.pt(-68.8, -66.3)
		local y = F.ground(-68.8, -66.3) or gymGround
		local P = CFrame.lookAt(Vector3.new(c.X, y, c.Z), Vector3.new(c.X, y, c.Z) + F.dir(1, 0))
		b:part("PylonPost", Vector3.new(1.4, H(2.7), 1.4), P * CFrame.new(0, H(1.35), 0), Enum.Material.Metal, BLACK, true)
		local bw, bd = L(1.7), L(0.55)
		local upper = b:part("PylonUpper", Vector3.new(bw, H(1.05), bd), P * CFrame.new(0, H(4.25), 0), Enum.Material.Metal, BLACK)
		local lower = b:part("PylonLower", Vector3.new(bw, H(1.15), bd), P * CFrame.new(0, H(3.15), 0), Enum.Material.Metal, BLACK)
		for _, s in ipairs({ -1, 1 }) do
			local up = b:part("PylonFace", Vector3.new(bw - 0.5, H(1.05) - 0.5, 0.15), P * CFrame.new(0, H(4.25), s * (bd / 2 + 0.05)) * CFrame.Angles(0, s > 0 and math.pi or 0, 0),
				Enum.Material.SmoothPlastic, ORANGE)
			Shapes.signText(up, Enum.NormalId.Front, {
				{ text = "CHESTER", size = 0.46, y = 0.06, font = Enum.Font.Garamond, color = rgb(255, 250, 240) },
				{ text = "HIGH SCHOOL", size = 0.36, y = 0.54, font = Enum.Font.Garamond, color = rgb(255, 250, 240) },
			}, 30)
			local led = b:part("PylonLED", Vector3.new(bw - 0.6, H(1.15) - 0.7, 0.15), P * CFrame.new(0, H(3.15), s * (bd / 2 + 0.05)) * CFrame.Angles(0, s > 0 and math.pi or 0, 0),
				Enum.Material.SmoothPlastic, rgb(200, 62, 30))
			Shapes.signText(led, Enum.NormalId.Front, {
				-- the board scrolls messages; the photographed one names the school
				{ text = "Chester High School", size = 0.5, y = 0.25, font = Enum.Font.Arcade, color = rgb(255, 196, 150) },
			}, 30)
		end
		b:part("PylonCap", Vector3.new(bw + 0.3, 0.5, bd + 0.3), P * CFrame.new(0, H(4.8) + 0.25, 0), Enum.Material.Metal, BLACK)
		local _ = upper and lower
	end
end

return ChesterHigh
