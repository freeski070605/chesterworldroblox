-- Photo-reviewed architecture for schools, churches and other institutions
-- (data: InstitutionReconstruction.lua, inventory: tools/reconstruction/
-- institution_inventory.py). Called by TileBuilderV2.buildFootprintBuilding
-- after the county rectangles are built; replaces the generic block's roof,
-- windows and trim with what the reference photograph shows.
--
-- Two massing modes:
--   mass  - churches and small buildings: the main rectangles are merged into
--           one oriented body (nave / hall) carrying a single roof; smaller
--           rectangles stay as lower annexes.
--   wings - large schools and campus halls: every county rectangle keeps its
--           own box (courtyards stay open); material, roof trim and windows
--           are re-dressed per box.
--
-- Only features listed in the spec are built, and the data module may only
-- list a feature that its `seen` field records from the photo (enforced by
-- tools/reconstruction/test_institutions.py). Part budget: no per-brick or
-- per-pane geometry; repeating windows on schools are textures or one glass
-- strip per storey.
local InstitutionArchitecture = {}
local Shapes = require(script.Parent.InstitutionShapes)
local Poly = require(script.Parent.InstitutionPoly)
local Footprints = require(script.Parent.InstitutionFootprints)

local function hex(v)
	return Color3.fromRGB(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local WHITE = rgb(236, 234, 226)
local DARK_GLASS = rgb(52, 58, 66)
local STAINED = { rgb(150, 36, 40), rgb(40, 66, 140), rgb(196, 150, 40), rgb(48, 112, 70), rgb(118, 46, 110) }
local DOOR = { red = rgb(168, 30, 32), white = rgb(226, 224, 216), wood = rgb(104, 70, 44),
	blue = rgb(40, 70, 150), dark = rgb(58, 54, 52), glass = rgb(70, 86, 96), green = rgb(150, 190, 60) }

local function mat(name, fallback)
	if not name then return fallback end
	local ok, m = pcall(function() return Enum.Material[name] end)
	return ok and m or fallback
end

local Builder = {}
Builder.__index = Builder

function Builder:part(name, size, cf, material, color, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color or WHITE
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = self.model
	self.count += 1
	return p
end

function Builder:wedge(name, size, cf, material, color)
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Material = material
	w.Color = color
	w.Parent = self.model
	self.count += 1
	return w
end

-- square (or rectangular) pyramid: four CornerWedgeParts. A corner wedge's
-- apex sits over its local (+X, -Z) corner (probed in Studio 2026-11-24), so
-- each quadrant is turned to put that corner on the centre line.
function Builder:pyramid(name, cf, wx, wz, height, material, color)
	for k = 0, 3 do
		local theta = k * math.pi / 2
		local rot = CFrame.Angles(0, theta, 0)
		-- the apex direction (1, 0, -1) after rotation, scaled to the quadrant
		local apex = rot:VectorToWorldSpace(Vector3.new(1, 0, -1))
		local qx = (k % 2 == 0) and wx or wz
		local qz = (k % 2 == 0) and wz or wx
		local c = Instance.new("CornerWedgePart")
		c.Name = name
		c.Anchored = true
		c.Size = Vector3.new(qx / 2, height, qz / 2)
		c.CFrame = cf * CFrame.new(-apex.X * wx / 4, height / 2, -apex.Z * wz / 4) * rot
		c.Material = material
		c.Color = color
		c.Parent = self.model
		self.count += 1
	end
end

-- gable over a box frame `cf` (at eave height, centre of the box): ridge
-- along local X (length) with the given span along local Z. The triangle
-- ends are wall coloured, the slopes are roof slabs with an overhang.
function Builder:gable(cf, length, span, rise, wallMat, wallColor, roofColor, overhang, roofMat)
	overhang = overhang or 1.2
	for side = -1, 1, 2 do
		self:wedge("GableEnd", Vector3.new(length, rise, span / 2),
			cf * CFrame.new(0, rise / 2, side * span / 4) * CFrame.Angles(0, side == 1 and math.pi or 0, 0),
			wallMat, wallColor)
	end
	local half = span / 2
	local slope = math.sqrt(half * half + rise * rise)
	local angle = math.atan2(rise, half)
	for side = -1, 1, 2 do
		local p = self:part("Roof", Vector3.new(length + overhang * 2, 0.7, slope + overhang),
			cf * CFrame.new(0, rise / 2 + 0.35, side * (half / 2 + overhang / 2 * math.cos(angle)))
				* CFrame.Angles(side * angle, 0, 0),
			roofMat or Enum.Material.Slate, roofColor, true)
		p.CanCollide = true
	end
end

-- hip roof over a box (cf at eave, centre): a ridge prism plus a half
-- pyramid at each end
function Builder:hip(cf, length, span, rise, roofColor)
	if length > span + 0.5 then
		for side = -1, 1, 2 do
			self:wedge("Roof", Vector3.new(length - span, rise, span / 2),
				cf * CFrame.new(0, rise / 2, side * span / 4) * CFrame.Angles(0, side == 1 and math.pi or 0, 0),
				Enum.Material.Slate, roofColor)
		end
	end
	local ends = length > span + 0.5 and { -(length - span) / 2, (length - span) / 2 } or { 0 }
	for _, x in ipairs(ends) do
		self:pyramid("Roof", cf * CFrame.new(x, 0, 0), math.min(span, length), span, rise, Enum.Material.Slate, roofColor)
	end
end

-- the four vertical faces of a box part (cf centre, size): frames at world
-- y = 0, LookVector outward, with their width
local function facesOf(cf, size)
	local out = {}
	for _, f in ipairs({
		{ Vector3.new(0, 0, -1), size.X, size.Z }, { Vector3.new(0, 0, 1), size.X, size.Z },
		{ Vector3.new(-1, 0, 0), size.Z, size.X }, { Vector3.new(1, 0, 0), size.Z, size.X },
	}) do
		local half = (f[1].X ~= 0 and size.X or size.Z) / 2
		local c = cf:PointToWorldSpace(f[1] * half)
		local n = cf:VectorToWorldSpace(f[1])
		local base = Vector3.new(c.X, 0, c.Z)
		table.insert(out, { frame = CFrame.lookAt(base, base + Vector3.new(n.X, 0, n.Z)), width = f[2], depth = f[3],
			normal = Vector3.new(n.X, 0, n.Z).Unit })
	end
	return out
end

-- one window on a face frame: glass plus an arched head
function Builder:window(face, u, y0, w, h, style, color)
	local glass = self:part("Window", Vector3.new(w, h, 0.4), face * CFrame.new(u, y0 + h / 2, -0.25),
		Enum.Material.Glass, color)
	if style == "lancet" then
		local d = w / math.sqrt(2)
		self:part("WindowHead", Vector3.new(d, d, 0.4), face * CFrame.new(u, y0 + h, -0.25) * CFrame.Angles(0, 0, math.rad(45)),
			Enum.Material.Glass, color)
	elseif style == "round" then
		self:part("WindowHead", Vector3.new(0.4, w, w), face * CFrame.new(u, y0 + h, -0.25) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.Material.Glass, color).Shape = Enum.PartType.Cylinder
	end
	return glass
end

function Builder:windowRow(face, width, y0, h, w, bay, style, stained, skipCentre)
	local n = math.clamp(math.floor((width - 4) / bay), 0, 9)
	if n == 0 then return end
	local step = (width - 4) / n
	for i = 1, n do
		local u = -width / 2 + 2 + (i - 0.5) * step
		if not (skipCentre and math.abs(u) < skipCentre) then
			local color = stained and STAINED[(i + self.seed) % #STAINED + 1] or self.glass or DARK_GLASS
			self:window(face, u, y0, math.min(w, step * 0.7), h, style, color)
		end
	end
end

function Builder:cross(cf, h, color, flat)
	color = color or rgb(214, 210, 196)
	local t = math.max(h * 0.09, 0.35)
	self:part("Cross", Vector3.new(t, h, flat and 0.3 or t), cf * CFrame.new(0, h / 2, 0), Enum.Material.Metal, color)
	self:part("Cross", Vector3.new(h * 0.6, t, flat and 0.3 or t), cf * CFrame.new(0, h * 0.68, 0), Enum.Material.Metal, color)
end

function Builder:door(face, u, y0, spec, wall)
	local w = spec.w or 6
	local h = spec.h or 9
	local color = DOOR[spec.color or "wood"] or DOOR.wood
	self:part("Door", Vector3.new(w, h, 0.5), face * CFrame.new(u, y0 + h / 2, -0.3), Enum.Material.Wood, color)
	if spec.style == "pointed" then
		local d = w / math.sqrt(2)
		self:part("DoorHead", Vector3.new(d, d, 0.5), face * CFrame.new(u, y0 + h, -0.3) * CFrame.Angles(0, 0, math.rad(45)),
			Enum.Material.Wood, color)
	elseif spec.style == "round" then
		self:part("DoorHead", Vector3.new(0.5, w, w), face * CFrame.new(u, y0 + h, -0.3) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.Material.Wood, color).Shape = Enum.PartType.Cylinder
	end
	if spec.surround then
		-- classical door case: pilasters and an entablature
		local c = hex(spec.surround)
		for side = -1, 1, 2 do
			self:part("DoorCase", Vector3.new(1.2, h + 1, 0.9), face * CFrame.new(u + side * (w / 2 + 0.8), y0 + (h + 1) / 2, -0.45),
				Enum.Material.Concrete, c)
		end
		self:part("DoorCase", Vector3.new(w + 4.4, 1.6, 1.2), face * CFrame.new(u, y0 + h + 1.8, -0.6), Enum.Material.Concrete, c)
	end
	if spec.hood then
		self:part("DoorHood", Vector3.new(w + 3, 0.6, 3.5), face * CFrame.new(u, y0 + h + (spec.style and w / 2 + 1 or 1), -1.75),
			Enum.Material.Metal, spec.hood == true and rgb(70, 70, 72) or hex(spec.hood))
	end
	local steps = spec.steps or 0
	for k = 1, steps do
		-- each step one stud high, stacked toward the door
		local depth = (steps - k + 1) * 2
		self:part("Steps", Vector3.new(w + 4, 1, depth), face * CFrame.new(u, y0 - steps + k - 0.5, -depth / 2 - 0.3),
			Enum.Material.Concrete, rgb(176, 172, 164), true)
	end
end

-- tower / steeple stages from a base frame at the tower's foot
function Builder:tower(B, spec, ctx)
	local S = ctx.S
	local tw = (spec.w or 5) * S
	local x = 0
	if spec.pos == "fl" then x = ctx.W / 2 - tw / 2 elseif spec.pos == "fr" then x = -(ctx.W / 2 - tw / 2) end
	local proj = (spec.out or 0.35) * tw
	local fromY = spec.from == "roof" and ctx.eave or ctx.ground
	local z = -ctx.D / 2 + tw / 2 - proj
	if spec.from == "roof" then z = -ctx.D / 2 + tw / 2 + 0.5 end
	local shaftTop = ctx.ground + (spec.h or 15) * S
	if spec.from == "roof" then
		shaftTop = math.max(shaftTop, ctx.eave + tw * 0.8)   -- a roof-mounted stage always clears the eave
	end
	local shaftMat = mat(spec.material, ctx.material)
	local shaftCol = spec.color and hex(spec.color) or ctx.wall
	local foot = B * CFrame.new(x, 0, z)
	local trimCol = spec.trim and hex(spec.trim) or WHITE
	self:part("Tower", Vector3.new(tw, shaftTop - fromY + (spec.from == "roof" and 0 or (ctx.ground - ctx.base)), tw),
		foot * CFrame.new(0, (shaftTop + (spec.from == "roof" and fromY or ctx.base)) / 2, 0), shaftMat, shaftCol, true)
	local faces = facesOf(foot * CFrame.new(0, shaftTop, 0), Vector3.new(tw, 1, tw))
	if spec.belfry then
		-- louvred openings near the top of each face
		for _, f in ipairs(faces) do
			self:window(f.frame, 0, shaftTop - tw * 0.75 - 1, tw * 0.38, tw * 0.5, spec.belfry, rgb(40, 38, 36))
		end
	end
	if spec.clock then
		for _, f in ipairs(faces) do
			self:part("ClockFace", Vector3.new(0.4, tw * 0.55, tw * 0.55),
				f.frame * CFrame.new(0, shaftTop - tw * (spec.belfry and 1.55 or 0.7), -0.3) * CFrame.Angles(0, math.pi / 2, 0),
				Enum.Material.SmoothPlastic, rgb(240, 236, 220)).Shape = Enum.PartType.Cylinder
		end
	end
	if spec.lancet then
		local f = faces[1]
		for _, ff in ipairs(faces) do
			if ff.normal:Dot((B.LookVector)) > 0.7 then f = ff end
		end
		self:window(f.frame, 0, ctx.ground + (spec.h or 15) * S * 0.35, tw * 0.3, tw * 0.9, "lancet", DARK_GLASS)
	end
	local top = foot * CFrame.new(0, shaftTop, 0)
	local topY = shaftTop
	local kind = spec.top or "flat"
	if kind == "spire" then
		local sh = (spec.spire or 10) * S
		self:pyramid("Spire", top, tw * 0.92, tw * 0.92, sh, mat(spec.spireMaterial, Enum.Material.Slate),
			spec.spireColor and hex(spec.spireColor) or rgb(70, 72, 78))
		topY += sh
	elseif kind == "pinnacles" or kind == "crenel" then
		self:part("TowerCap", Vector3.new(tw + 0.8, 1, tw + 0.8), top * CFrame.new(0, 0.5, 0), shaftMat, shaftCol)
		for cx = -1, 1, 2 do
			for cz = -1, 1, 2 do
				if kind == "pinnacles" then
					self:part("Pinnacle", Vector3.new(1.4, 6, 1.4), top * CFrame.new(cx * (tw / 2 - 0.7), 4, cz * (tw / 2 - 0.7)), shaftMat, shaftCol)
					self:pyramid("PinnacleTip", top * CFrame.new(cx * (tw / 2 - 0.7), 7, cz * (tw / 2 - 0.7)), 1.6, 1.6, 3, shaftMat, shaftCol)
				else
					self:part("Merlon", Vector3.new(tw * 0.3, 2.4, tw * 0.3), top * CFrame.new(cx * tw * 0.35, 2.2, cz * tw * 0.35), shaftMat, shaftCol)
				end
			end
		end
		topY += kind == "pinnacles" and 10 or 3.4
	elseif kind == "colonial" then
		-- white belfry stage with arched louvres, a lantern and a tall spire
		local bw, bh = tw * 0.82, tw * 0.95
		local belfry = top * CFrame.new(0, bh / 2, 0)
		self:part("Belfry", Vector3.new(bw, bh, bw), belfry, Enum.Material.SmoothPlastic, trimCol)
		for _, f in ipairs(facesOf(belfry, Vector3.new(bw, 1, bw))) do
			self:window(f.frame, 0, topY + bh * 0.18, bw * 0.4, bh * 0.45, "round", rgb(46, 46, 46))
		end
		self:part("BelfryCornice", Vector3.new(bw + 1, 0.8, bw + 1), top * CFrame.new(0, bh + 0.4, 0), Enum.Material.SmoothPlastic, trimCol)
		local lw, lh = bw * 0.7, bh * 0.6
		self:part("Lantern", Vector3.new(lw, lh, lw), top * CFrame.new(0, bh + 0.8 + lh / 2, 0), Enum.Material.SmoothPlastic, trimCol)
		local sh = (spec.spire or 12) * S
		self:pyramid("Spire", top * CFrame.new(0, bh + 0.8 + lh, 0), lw, lw, sh, Enum.Material.SmoothPlastic, trimCol)
		topY += bh + 0.8 + lh + sh
	elseif kind == "cupola" or kind == "onion" then
		local cw = tw * (kind == "onion" and 0.6 or 0.75)
		local copper = spec.domeColor and hex(spec.domeColor) or rgb(96, 150, 124)
		local drumH = cw * 0.9
		self:part("Drum", Vector3.new(drumH, cw, cw), top * CFrame.new(0, drumH / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Enum.Material.SmoothPlastic, kind == "onion" and trimCol or copper).Shape = Enum.PartType.Cylinder
		local ball = self:part("Dome", Vector3.new(cw * 1.05, cw * 1.05, cw * 1.05), top * CFrame.new(0, drumH + cw * 0.35, 0),
			Enum.Material.Metal, copper)
		ball.Shape = Enum.PartType.Ball
		self:pyramid("DomeTip", top * CFrame.new(0, drumH + cw * 0.8, 0), cw * 0.3, cw * 0.3, cw * 0.7, Enum.Material.Metal, copper)
		topY += drumH + cw * 1.5
	elseif kind == "belfry_cap" then
		self:pyramid("TowerRoof", top, tw + 1, tw + 1, tw * 0.5, Enum.Material.Slate, rgb(70, 72, 78))
		topY += tw * 0.5
	else
		self:part("TowerCap", Vector3.new(tw + 0.6, 0.8, tw + 0.6), top * CFrame.new(0, 0.4, 0), Enum.Material.Concrete,
			spec.trim and trimCol or shaftCol)
	end
	if spec.cross then
		self:cross(foot * CFrame.new(0, topY, 0), 4, spec.crossColor and hex(spec.crossColor) or nil)
	end
end

local function chooseMain(rects, spec, yaw)
	local main, total = {}, 0
	for _, r in ipairs(rects) do total += r.along * r.across end
	if spec.main == "all" then
		for _, r in ipairs(rects) do main[r] = true end
	elseif type(spec.main) == "table" then
		for _, i in ipairs(spec.main) do
			for _, r in ipairs(rects) do
				if r.index == i - 1 then main[r] = true end
			end
		end
	else
		-- the nave / hall: the largest rectangle plus the county slices that
		-- continue it (same width band in either direction); wings and
		-- porches stay annexes so an L-shaped complex is not one huge roof
		local L = rects[1]
		for _, r in ipairs(rects) do if r.along * r.across > L.along * L.across then L = r end end
		local f = CFrame.new(L.x, 0, L.z) * yaw
		local function overlap(a0, a1, b0, b1) return math.max(0, math.min(a1, b1) - math.max(a0, b0)) end
		for _, r in ipairs(rects) do
			local p = f:PointToObjectSpace(Vector3.new(r.x, 0, r.z))
			local ov = overlap(p.Z - r.across / 2, p.Z + r.across / 2, -L.across / 2, L.across / 2)
			local ou = overlap(p.X - r.along / 2, p.X + r.along / 2, -L.along / 2, L.along / 2)
			if r == L or (r.along * r.across >= 0.04 * total and (
				(ov >= 0.7 * math.min(r.across, L.across) and r.across >= 0.6 * L.across)
				or (ou >= 0.7 * math.min(r.along, L.along) and r.along >= 0.6 * L.along))) then
				main[r] = true
			end
		end
	end
	if next(main) == nil then
		local best = rects[1]
		for _, r in ipairs(rects) do if r.along * r.across > best.along * best.across then best = r end end
		main[best] = true
	end
	return main
end

local GENERIC = { Walls = true, GroundStorey = true, Foundation = true, Roof = true, Cornice = true,
	GothicLancet = true, GothicMullion = true, GothicButtress = true }

local function clearGeneric(model)
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("BasePart") and GENERIC[c.Name] then c:Destroy() end
	end
end

local function windowSpec(builder, faceList, spec, eaveH, ground, storey, frontNormal)
	local win = spec.win
	if not win or win.style == "none" then return end
	for _, f in ipairs(faceList) do
		local isFront = frontNormal and f.normal:Dot(frontNormal) > 0.7
		local isBack = frontNormal and f.normal:Dot(frontNormal) < -0.7
		local want = win.faces == "all" or (win.faces == "front" and isFront)
			or ((win.faces == nil or win.faces == "sides") and not isFront and not isBack)
			or (win.faces == "front_sides" and not isBack)
		if want and f.width >= 8 then
			local style = win.style
			if style == "ribbon" then
				local floors = math.max(1, math.floor(eaveH / storey + 0.3))
				for k = 0, floors - 1 do
					local y = ground + k * storey + storey * 0.35
					builder:part("RibbonWindow", Vector3.new(f.width - 3, storey * (win.tall or 0.42), 0.4),
						f.frame * CFrame.new(0, y + storey * (win.tall or 0.42) / 2, -0.25), Enum.Material.Glass,
						win.color and hex(win.color) or rgb(64, 78, 90))
				end
			else
				local rows = win.rows or 1
				local h = win.h and win.h * builder.S or math.min(eaveH * (rows == 1 and 0.5 or 0.28), 18)
				h = math.min(h, eaveH * (rows == 1 and 0.62 or 0.5 / rows))
				local w = win.w and win.w * builder.S or (style == "rect" and 4 or 3.6)
				for k = 0, rows - 1 do
					local y0 = ground + (rows == 1 and eaveH * (win.sill or 0.22) or (k * eaveH / rows + eaveH / rows * 0.28))
					builder:windowRow(f.frame, f.width, y0, h, w, (win.bay or 4) * builder.S, style, win.stained,
						isFront and spec.door and 5 or nil)
				end
			end
		end
	end
end

-- texture-based repeating windows (school / campus classroom grids)
local function textureFaces(ctx, block, key, storey)
	if key and ctx.applyFacade then
		ctx.applyFacade(block, key, storey)
	end
end

function InstitutionArchitecture.Build(model, spec, ctx)
	local S = ctx.S
	local b = setmetatable({ model = model, count = 0, S = S, seed = tonumber(ctx.buildingId) or 0,
		glass = spec.win and spec.win.color and hex(spec.win.color) or nil }, Builder)
	local roofMat = mat(spec.roofMaterial, Enum.Material.Slate)
	local rects = ctx.rects
	if #rects == 0 then return 0 end
	if spec.poly and ctx.toStuds and ctx.terrainY then
		-- photo-matched massing on the exact county footprint
		local fp = Footprints[ctx.buildingId]
		if fp then
			for _, c in ipairs(model:GetChildren()) do
				if c:IsA("BasePart") then c:Destroy() end
			end
			Poly.Build(b, spec, ctx, Shapes, fp)
			model:SetAttribute("InstitutionPoly", true)
			model:SetAttribute("InstitutionParts", b.count)
			return b.count
		end
	end
	if spec.custom then
		-- bespoke, photo-matched model traced from the county polygon
		-- (Institutions/<custom>.lua): the county boxes give way to it
		local module = script.Parent:FindFirstChild("Institutions") and script.Parent.Institutions:FindFirstChild(spec.custom)
		if module and ctx.toStuds and ctx.terrainY then
			for _, c in ipairs(model:GetChildren()) do
				if c:IsA("BasePart") then c:Destroy() end
			end
			require(module).Build(b, spec, ctx, Shapes)
			model:SetAttribute("InstitutionCustom", spec.custom)
			model:SetAttribute("InstitutionParts", b.count)
			return b.count
		end
	end
	local wall = spec.wall and hex(spec.wall) or ctx.wall
	local material = mat(spec.material, ctx.material)
	local roofColor = spec.roofColor and hex(spec.roofColor) or ctx.roofColor or rgb(70, 66, 62)
	local trim = spec.trim and hex(spec.trim) or nil
	local H = ctx.hStuds
	local frontBearing = spec.front or ctx.front or 0
	local frontDir = Vector3.new(math.sin(math.rad(frontBearing)), 0, -math.cos(math.rad(frontBearing)))
	clearGeneric(model)

	local mode = spec.mode or ((spec.kind == "school" or spec.kind == "campus") and "wings" or "mass")
	local main = mode == "mass" and chooseMain(rects, spec, ctx.yaw) or {}
	local frame0 = CFrame.new(rects[1].x, 0, rects[1].z) * ctx.yaw
	local umin, umax, vmin, vmax = math.huge, -math.huge, math.huge, -math.huge
	local ground, base = math.huge, math.huge
	for _, r in ipairs(rects) do
		if main[r] then
			local p = frame0:PointToObjectSpace(Vector3.new(r.x, 0, r.z))
			umin, umax = math.min(umin, p.X - r.along / 2), math.max(umax, p.X + r.along / 2)
			vmin, vmax = math.min(vmin, p.Z - r.across / 2), math.max(vmax, p.Z + r.across / 2)
			ground, base = math.min(ground, r.streetLevel), math.min(base, r.base)
		end
	end

	if mode == "wings" then
		-- every rectangle keeps its own box
		local frontRect, frontScore
		for _, r in ipairs(rects) do
			local top = r.wallTop
			local cf = CFrame.new(r.x, (top + r.base) / 2, r.z) * ctx.yaw
			local size = Vector3.new(r.along, top - r.base, r.across)
			local block = b:part("Walls", size, cf, material, wall, true)
			block:SetAttribute("GroundY", r.streetLevel + 0.4)
			local eaveH = top - r.streetLevel
			if spec.band then
				local from = r.streetLevel + eaveH * (spec.band.from or 0.5)
				b:part("Cladding", Vector3.new(r.along + 0.3, top - from, r.across + 0.3),
					CFrame.new(r.x, (top + from) / 2, r.z) * ctx.yaw, mat(spec.band.material, Enum.Material.SmoothPlastic), hex(spec.band.color))
			end
			if spec.plinth then
				local ph = eaveH * (spec.plinth.h or 0.15)
				b:part("Plinth", Vector3.new(r.along + 0.3, ph + (r.streetLevel - r.base), r.across + 0.3),
					CFrame.new(r.x, (r.base + r.streetLevel + ph) / 2, r.z) * ctx.yaw, mat(spec.plinth.material, Enum.Material.Cobblestone), hex(spec.plinth.color))
			end
			local faceList = facesOf(cf, size)
			if spec.win and spec.win.texture then
				textureFaces(ctx, block, spec.win.texture, r.storey)
			else
				windowSpec(b, faceList, spec, eaveH, r.streetLevel, r.storey, nil)
			end
			local roofCf = CFrame.new(r.x, top, r.z) * ctx.yaw
			if spec.roof == "side_gable" or spec.roof == "hip" then
				local long = math.max(r.along, r.across)
				local short = math.min(r.along, r.across)
				local rcf = r.along >= r.across and roofCf or roofCf * CFrame.Angles(0, math.pi / 2, 0)
				local rise = math.min(short * 0.5 * (spec.pitch or 0.6), 16)
				if spec.roof == "hip" then
					b:hip(rcf, long + 1, short + 1, rise, roofColor)
				else
					b:gable(rcf, long, short, rise, material, wall, roofColor, nil, roofMat)
				end
				for k = 1, (spec.chimneys or 0) do
					local x = (k % 2 == 1 and -1 or 1) * long * 0.32
					b:part("Chimney", Vector3.new(2.4, rise + 5, 3.6), rcf * CFrame.new(x, (rise + 5) / 2, 0), material, wall)
				end
			elseif spec.fascia then
				b:part("RoofFascia", Vector3.new(r.along + spec.fascia * 2, 1.2, r.across + spec.fascia * 2),
					roofCf * CFrame.new(0, 0.6, 0), Enum.Material.SmoothPlastic, trim or WHITE)
			else
				b:part("Coping", Vector3.new(r.along + 0.8, spec.parapet and 2 or 0.9, r.across + 0.8),
					roofCf * CFrame.new(0, spec.parapet and 1 or 0.45, 0), Enum.Material.Concrete, trim or rgb(190, 184, 170))
				b:part("Roof", Vector3.new(r.along - 0.4, 0.3, r.across - 0.4), roofCf * CFrame.new(0, 0.2, 0),
					Enum.Material.Concrete, ctx.roofColor or rgb(96, 94, 90))
			end
			-- the box reaching furthest toward the front carries the entrance
			local p = Vector3.new(r.x, 0, r.z)
			local reach = p:Dot(frontDir) + math.max(r.along, r.across) * 0.05
			if r.along * r.across > 150 and (not frontScore or reach > frontScore) then frontRect, frontScore = r, reach end
		end
		frontRect = frontRect or rects[1]
		local fcf = CFrame.new(frontRect.x, 0, frontRect.z) * ctx.yaw
		local best, bestDot
		for _, f in ipairs(facesOf(fcf, Vector3.new(frontRect.along, 1, frontRect.across))) do
			local d = f.normal:Dot(frontDir)
			if not bestDot or d > bestDot then best, bestDot = f, d end
		end
		local eaveH = frontRect.wallTop - frontRect.streetLevel
		if spec.pavilion and best.width > 30 then
			-- projecting entrance pavilion at the middle of the front
			local pw = math.min(best.width * 0.24, 36)
			local pc = best.frame * CFrame.new(0, (frontRect.wallTop + 2 + frontRect.base) / 2, -1.5)
			b:part("EntrancePavilion", Vector3.new(pw, frontRect.wallTop + 2 - frontRect.base, 3), pc,
				material, spec.pavilion == true and wall or hex(spec.pavilion), true)
			b:part("PavilionCornice", Vector3.new(pw + 1.2, 1.2, 4.2), best.frame * CFrame.new(0, frontRect.wallTop + 2.6, -1.5),
				Enum.Material.Concrete, trim or rgb(200, 194, 180))
			best = { frame = best.frame * CFrame.new(0, 0, -3), width = pw, normal = best.normal }
		end
		if spec.door then
			b:door(best.frame, (spec.door.at or 0) * best.width / 2, frontRect.streetLevel, spec.door, wall)
		end
		if spec.canopy then
			b:part("EntranceCanopy", Vector3.new(math.min(best.width * 0.4, spec.canopy * S), 0.9, 10),
				best.frame * CFrame.new((spec.door and spec.door.at or 0) * best.width / 2, frontRect.streetLevel + 11, -5),
				Enum.Material.Concrete, trim or rgb(210, 206, 196))
		end
		if spec.curtain then
			b:part("CurtainWall", Vector3.new(spec.curtain * S, eaveH - 1, 0.6),
				best.frame * CFrame.new(best.width * (spec.curtainAt or 0.35), frontRect.streetLevel + eaveH / 2, -0.35),
				Enum.Material.Glass, rgb(92, 120, 138))
		end
		if spec.portico then
			InstitutionArchitecture._portico(b, best.frame, best.width, frontRect.streetLevel, math.min(eaveH - 2, spec.portico.h and spec.portico.h * S or 30), spec.portico, trim)
		end
		if spec.cupola then
			local c = CFrame.new(frontRect.x, 0, frontRect.z) * ctx.yaw   -- tower() works in absolute heights
			b:tower(c * CFrame.new(0, 0, 0), { w = spec.cupola.w or 3, h = spec.cupola.base or 1.5, top = spec.cupola.top or "cupola",
				clock = spec.cupola.clock, color = 0xeceae2, domeColor = spec.cupola.domeColor, material = "SmoothPlastic",
				from = "roof", out = 0 }, { S = S, W = 0, D = 0, ground = frontRect.wallTop, base = frontRect.wallTop,
				eave = frontRect.wallTop, material = Enum.Material.SmoothPlastic, wall = WHITE })
		end
		if spec.sign then
			InstitutionArchitecture._sign(b, best.frame, best.width, frontRect.streetLevel + math.min(eaveH - 3, spec.sign.y and spec.sign.y * S or 14), spec.sign)
		end
		model:SetAttribute("InstitutionParts", b.count)
		return b.count
	end

	-- mass mode: one oriented body for the main rectangles
	local uc, vc = (umin + umax) / 2, (vmin + vmax) / 2
	local mainFrame = frame0 * CFrame.new(uc, 0, vc)
	local Lu, Lv = umax - umin, vmax - vmin
	-- front frame B: LookVector out of the front face, x across the front
	local best, bestDot
	for _, n in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local w = mainFrame:VectorToWorldSpace(n)
		local d = w:Dot(frontDir)
		if not bestDot or d > bestDot then best, bestDot = n, d end
	end
	local roofKind = spec.roof or "flat"
	if roofKind == "front_gable" then
		-- a front-gabled church shows its gable on a NARROW end: when the street
		-- front is a long side, the gable end is the narrow face nearest it
		-- (photographed `gableFront`, else the corner street fb2)
		local isLong = (best.X ~= 0 and Lv or Lu) > (best.X ~= 0 and Lu or Lv) * 1.15
		if spec.gableFront or isLong then
			local want = spec.gableFront or ctx.corner
			local wantDir = want and Vector3.new(math.sin(math.rad(want)), 0, -math.cos(math.rad(want))) or frontDir
			-- narrow ends: the faces whose normal runs along the long dimension
			local narrow = (Lu > Lv) and { Vector3.xAxis, -Vector3.xAxis } or { Vector3.zAxis, -Vector3.zAxis }
			if spec.gableFront then narrow = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } end
			local nb, nd
			for _, n in ipairs(narrow) do
				local d = mainFrame:VectorToWorldSpace(n):Dot(wantDir)
				if not nd or d > nd then nb, nd = n, d end
			end
			best = nb
		end
	end
	local out = mainFrame:VectorToWorldSpace(best)
	local centre = mainFrame.Position
	local B = CFrame.lookAt(Vector3.new(centre.X, 0, centre.Z), Vector3.new(centre.X + out.X, 0, centre.Z + out.Z))
	local W = best.X ~= 0 and Lv or Lu     -- across the front
	local D = best.X ~= 0 and Lu or Lv     -- front to back
	local roof = spec.roof or "flat"
	local ridgeAlongDepth = roof == "front_gable" or roof == "front_hip"
	local span = ridgeAlongDepth and W or D
	local pitch = spec.pitch or 0.6
	local rise = 0
	if roof == "front_gable" or roof == "side_gable" or roof == "hip" or roof == "front_hip" then
		rise = math.min(span / 2 * pitch, 40)
		if not spec.eave then rise = math.min(rise, H * 0.45) end
	end
	-- LiDAR height is the roof peak; the eave sits a rise below it unless the
	-- photo gives the eave directly (spec.eave in metres)
	local eave = spec.eave and (ground + spec.eave * S) or (ground + math.max(H - rise, 9))
	if spec.eave == nil and roof ~= "flat" and roof ~= "parapet" and roof ~= "castellated" and roof ~= "stepped" and roof ~= "none" then
		eave = math.max(eave, ground + 9)
	end
	local eaveH = eave - ground
	local storey = math.clamp(eaveH / math.max(spec.floors or 1, 1), 8, 14)
	local wallCf = B * CFrame.new(0, (eave + base) / 2, 0)
	local bodySize = Vector3.new(W, eave - base, D)
	if roof == "none" then
		-- roofless shell (fire ruin): four walls, blackened tops
		for _, f in ipairs(facesOf(wallCf, bodySize)) do
			local sh = eave - base
			b:part("RuinWall", Vector3.new(f.width, sh, 1.6), f.frame * CFrame.new(0, (eave + base) / 2, 0.8), material, wall, true)
			b:part("RuinScorch", Vector3.new(f.width, 2.5, 1.8), f.frame * CFrame.new(0, eave - 1.2, 0.8), Enum.Material.Slate, rgb(36, 32, 30))
		end
		b:part("Rubble", Vector3.new(W - 4, 1.5, D - 4), B * CFrame.new(0, ground + 0.6, 0), Enum.Material.Ground, rgb(92, 84, 74), true)
	else
		local body = b:part("Walls", bodySize, wallCf, material, wall, true)
		body:SetAttribute("GroundY", ground + 0.4)
		if spec.win and spec.win.texture then
			textureFaces(ctx, body, spec.win.texture, storey)
		end
	end
	if spec.plinth and roof ~= "none" then
		local ph = eaveH * (spec.plinth.h or 0.15)
		b:part("Plinth", Vector3.new(W + 0.3, ph + (ground - base), D + 0.3), B * CFrame.new(0, (base + ground + ph) / 2, 0),
			mat(spec.plinth.material, Enum.Material.Cobblestone), hex(spec.plinth.color))
	end
	if spec.band then
		local from = ground + eaveH * (spec.band.from or 0.5)
		if spec.band.faces == "front" then
			b:part("Cladding", Vector3.new(W + 0.2, eave - from, 0.5), B * CFrame.new(0, (eave + from) / 2, -D / 2 - 0.2),
				mat(spec.band.material, Enum.Material.WoodPlanks), hex(spec.band.color))
		else
			b:part("Cladding", Vector3.new(W + 0.3, eave - from, D + 0.3), B * CFrame.new(0, (eave + from) / 2, 0),
				mat(spec.band.material, Enum.Material.SmoothPlastic), hex(spec.band.color))
		end
	end
	-- annexes: the rectangles outside the main body, capped below its eave
	for _, r in ipairs(rects) do
		if not main[r] and roof ~= "none" then
			local top = math.min(r.wallTop, spec.annex and (r.streetLevel + spec.annex * S) or eave, r.wallTop)
			top = math.max(top, r.streetLevel + 7)
			b:part("Walls", Vector3.new(r.along, top - r.base, r.across), CFrame.new(r.x, (top + r.base) / 2, r.z) * ctx.yaw,
				material, wall, true)
			b:part("Roof", Vector3.new(r.along + 0.6, 0.6, r.across + 0.6), CFrame.new(r.x, top + 0.3, r.z) * ctx.yaw,
				Enum.Material.Concrete, trim or roofColor)
		end
	end
	-- roof over the body
	local roofBase = B * CFrame.new(0, eave, 0)
	if roof == "front_gable" then
		b:gable(roofBase * CFrame.Angles(0, math.pi / 2, 0), D, W, rise, material, wall, roofColor, 1.0, roofMat)
	elseif roof == "side_gable" then
		b:gable(roofBase, W, D, rise, material, wall, roofColor, 1.0, roofMat)
	elseif roof == "hip" then
		if W >= D then b:hip(roofBase, W + 1.5, D + 1.5, rise, roofColor)
		else b:hip(roofBase * CFrame.Angles(0, math.pi / 2, 0), D + 1.5, W + 1.5, rise, roofColor) end
	elseif roof == "flat" or roof == "parapet" or roof == "castellated" or roof == "stepped" then
		local capCol = trim or (roof == "flat" and roofColor) or wall
		b:part("Coping", Vector3.new(W + 0.8, roof == "flat" and 0.8 or 2.2, D + 0.8),
			roofBase * CFrame.new(0, roof == "flat" and 0.4 or 1.1, 0), Enum.Material.Concrete, capCol)
		if roof == "castellated" then
			local n = math.max(3, math.floor(W / 7))
			for i = 0, n - 1 do
				if i % 2 == 0 then
					b:part("Merlon", Vector3.new(W / n, 3, 1.6), B * CFrame.new(-W / 2 + (i + 0.5) * W / n, eave + 3.5, -D / 2 + 0.8), material, wall)
				end
			end
		elseif roof == "stepped" then
			b:part("Parapet", Vector3.new(W * 0.5, 3, 1.2), B * CFrame.new(0, eave + 3.7, -D / 2 + 0.6), material, wall)
			b:part("Parapet", Vector3.new(W * 0.2, 2.5, 1.2), B * CFrame.new(0, eave + 6.4, -D / 2 + 0.6), material, wall)
		end
	end
	if spec.cornice and roof ~= "none" then
		b:part("Cornice", Vector3.new(W + 1.6, 1.4, D + 1.6), B * CFrame.new(0, eave - 0.7, 0), Enum.Material.Concrete, hex(spec.cornice))
	end
	if spec.fascia then
		b:part("RoofFascia", Vector3.new(W + spec.fascia * 2, 1.2, D + spec.fascia * 2), roofBase * CFrame.new(0, 0.6, 0),
			Enum.Material.SmoothPlastic, trim or WHITE)
	end

	local faces = facesOf(wallCf, bodySize)
	local frontFace
	for _, f in ipairs(faces) do
		if f.normal:Dot(B.LookVector) > 0.7 then frontFace = f end
	end
	if not (spec.win and spec.win.texture) and roof ~= "none" then
		windowSpec(b, faces, spec, eaveH, ground, storey, B.LookVector)
	elseif roof == "none" and spec.win then
		-- burnt-out openings: dark voids through the shell
		for _, f in ipairs(faces) do
			b:windowRow(f.frame * CFrame.new(0, 0, -0.9), f.width, ground + eaveH * 0.3, eaveH * 0.35, 5, 14, spec.win.style, false)
		end
	end
	local F = frontFace.frame
	local ctxT = { S = S, W = W, D = D, ground = ground, base = base, eave = eave, material = material, wall = wall }
	if spec.rose then
		local d = math.min(W * 0.32, (rise > 0 and roof == "front_gable") and rise * 0.85 or eaveH * 0.4, (spec.rose.d or 5) * S)
		local y = (roof == "front_gable" and rise > d) and (eave + rise * 0.36) or (ground + eaveH * 0.66)
		b:part("RoseWindow", Vector3.new(0.5, d, d), F * CFrame.new(0, y, -0.3) * CFrame.Angles(0, math.pi / 2, 0), Enum.Material.Glass,
			spec.rose.stained and STAINED[2] or DARK_GLASS).Shape = Enum.PartType.Cylinder
		b:part("RoseFrame", Vector3.new(0.4, d + 1.4, d + 1.4), F * CFrame.new(0, y, -0.15) * CFrame.Angles(0, math.pi / 2, 0),
			Enum.Material.Concrete, spec.rose.frame and hex(spec.rose.frame) or rgb(206, 198, 180)).Shape = Enum.PartType.Cylinder
	end
	if spec.bigWindow then
		-- the single large front window (pointed or round headed)
		local w = math.min(W * 0.36, (spec.bigWindow.w or 4) * S)
		local h = math.min(eaveH * 0.55, (spec.bigWindow.h or 6) * S)
		b:window(F, spec.bigWindow.at and spec.bigWindow.at * W / 2 or 0, ground + eaveH * 0.3, w, h, spec.bigWindow.style or "lancet",
			spec.bigWindow.stained and STAINED[(b.seed % #STAINED) + 1] or DARK_GLASS)
	end
	if spec.door then
		b:door(F, (spec.door.at or 0) * W / 2, ground, spec.door, wall)
	end
	if spec.portico then
		InstitutionArchitecture._portico(b, F, W, ground, math.min(eaveH, spec.portico.h and spec.portico.h * S or eaveH), spec.portico, trim)
	end
	if spec.porch then
		-- full-width front porch (Friends meetinghouse)
		local depth = (spec.porch.d or 2.4) * S
		b:part("PorchFloor", Vector3.new(W - 2, 1, depth), F * CFrame.new(0, ground + 0.5, -depth / 2), Enum.Material.Concrete, rgb(170, 166, 158), true)
		local ph = math.min(10, eaveH - 1)
		b:part("PorchRoof", Vector3.new(W - 1, 0.8, depth + 1), F * CFrame.new(0, ground + ph + 0.5, -depth / 2) * CFrame.Angles(math.rad(-8), 0, 0),
			Enum.Material.Slate, roofColor)
		local n = math.max(2, math.floor(W / 14))
		for i = 0, n do
			b:part("PorchPost", Vector3.new(0.8, ph, 0.8), F * CFrame.new(-W / 2 + 1.5 + i * (W - 3) / n, ground + ph / 2 + 0.5, -depth + 0.6), Enum.Material.Wood, WHITE)
		end
	end
	for _, t in ipairs(spec.towers or (spec.tower and { spec.tower }) or {}) do
		b:tower(B, t, ctxT)
	end
	if spec.cupola then
		local c = spec.cupola
		local ridgeY = eave + rise
		b:tower(B * CFrame.new(0, 0, (c.z or 0) * D / 2), { w = c.w or 3, h = c.base or 1.2, top = c.top or "colonial", spire = c.spire or 3,
			cross = c.cross, color = c.color or 0xeceae2, trim = c.color or 0xeceae2, material = "SmoothPlastic", from = "roof", clock = c.clock,
			domeColor = c.domeColor, belfry = c.belfry },
			{ S = S, W = 0, D = 0, ground = ridgeY - 1, base = ridgeY - 1, eave = ridgeY - 1, material = Enum.Material.SmoothPlastic, wall = WHITE })
	end
	local c = spec.cross
	if c == "apex" and roof == "front_gable" then
		b:cross(F * CFrame.new(0, eave + rise + 0.3, 0.3), 5, spec.crossColor and hex(spec.crossColor) or nil)
	elseif c == "wall" or c == "painted" then
		local h = math.min(eaveH * 0.45, 14)
		b:cross(F * CFrame.new(spec.crossAt and spec.crossAt * W / 2 or 0, ground + eaveH * 0.4, -0.35), h,
			spec.crossColor and hex(spec.crossColor) or rgb(132, 30, 30), true)
	elseif c == "pylon" then
		-- free-standing brick bell pylon carrying a tall cross beside the front
		local p = F * CFrame.new(W / 2 + 3, 0, -2)
		b:part("CrossPylon", Vector3.new(3.4, eaveH + rise * 0.8, 3.4), p * CFrame.new(0, ground + (eaveH + rise * 0.8) / 2, 0), material, wall, true)
		b:cross(p * CFrame.new(0, ground + eaveH + rise * 0.8, 0), 9, rgb(150, 146, 140))
	end
	if spec.sign then
		InstitutionArchitecture._sign(b, F, W, ground + math.min(eaveH - 3, spec.sign.y and spec.sign.y * S or 12), spec.sign)
	end
	model:SetAttribute("InstitutionParts", b.count)
	return b.count
end

function InstitutionArchitecture._portico(b, F, width, ground, height, spec, trim)
	local color = spec.color and hex(spec.color) or WHITE
	local span = math.min(width * (spec.w or 0.55), 70)
	local depth = (spec.d or 3) * b.S
	local cols = spec.cols or 4
	for i = 0, cols - 1 do
		local x = -span / 2 + 1.5 + (span - 3) * i / math.max(cols - 1, 1)
		b:part("Column", Vector3.new(height, 2.4, 2.4), F * CFrame.new(x, ground + height / 2, -depth + 1.5) * CFrame.Angles(0, 0, math.pi / 2),
			Enum.Material.Concrete, color, true).Shape = Enum.PartType.Cylinder
	end
	b:part("Entablature", Vector3.new(span + 2, 2.6, depth + 0.5), F * CFrame.new(0, ground + height + 1.3, -depth / 2), Enum.Material.Concrete, color)
	b:part("PorticoFloor", Vector3.new(span + 2, 1.2, depth + 1), F * CFrame.new(0, ground + 0.6, -depth / 2), Enum.Material.Concrete, rgb(190, 186, 178), true)
	if spec.pediment ~= false then
		local rise = math.min(span * 0.2, 12)
		for side = -1, 1, 2 do
			b:wedge("Pediment", Vector3.new(depth + 0.5, rise, (span + 2) / 2),
				F * CFrame.new(side * (span + 2) / 4, ground + height + 2.6 + rise / 2, -depth / 2)
					* CFrame.Angles(0, side == 1 and -math.pi / 2 or math.pi / 2, 0),
				Enum.Material.Concrete, color)
		end
	end
end

function InstitutionArchitecture._sign(b, F, width, y, spec)
	local w = math.min(width * 0.7, spec.w and spec.w * b.S or 40)
	local board = b:part("InstitutionSign", Vector3.new(w, spec.h or 4, 0.5), F * CFrame.new(spec.at and spec.at * width / 2 or 0, y, -0.45),
		Enum.Material.SmoothPlastic, spec.bg and hex(spec.bg) or rgb(30, 40, 70))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 16
	gui.LightInfluence = 0.3
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = spec.fg and hex(spec.fg) or WHITE
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = spec.text
	label.Parent = gui
end

return InstitutionArchitecture
