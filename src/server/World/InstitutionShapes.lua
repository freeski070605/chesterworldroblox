-- Exact-footprint geometry for bespoke institution models (Chester High and
-- other photo-matched schools). Plans are traced in a building-local frame of
-- source metres (u across, v along the county `a` axis), checked against the
-- county polygon and the 1 m DVRPC aerial (tools/harness/plan_overlay.py).
--
--   * extrude: one wall part per polygon edge, a coping per edge and a flat
--     roof filled with wedge triangles (ear clipping) - no bounding boxes, so
--     angled pods, bowed fronts and rounded corners keep their real outline
--   * punched: a grid of punched windows on a wall for (columns + floors-1)
--     parts instead of one part per pane: a glass column per window bay and
--     wall-coloured spandrel strips between the floors
--   * group: a photographed window group (slots, tall triples) with a stone
--     surround
local Shapes = {}

local UP = Vector3.new(0, 1, 0)

local function hex(v)
	return Color3.fromRGB(math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
end
Shapes.hex = hex

-- building-local frame: (u, v) source metres -> world studs (y = 0)
function Shapes.frame(ctx, origin, a)
	local t = math.rad(a)
	local U = { math.sin(t), -math.cos(t) }
	local V = { math.cos(t), math.sin(t) }
	local F = { S = ctx.S, ctx = ctx }
	function F.pt(u, v)
		local x, z = ctx.toStuds(origin[1] + U[1] * u + V[1] * v, origin[2] + U[2] * u + V[2] * v)
		return Vector3.new(x, 0, z)
	end
	function F.dir(du, dv)
		return (F.pt(du, dv) - F.pt(0, 0)).Unit
	end
	function F.ground(u, v)
		local p = F.pt(u, v)
		return ctx.terrainY(p.X, p.Z)
	end
	return F
end

-- replace corners of a (u, v) polygon with circular arcs of radius r.
-- corners: list of vertex indices, or "convex" (with `keep`, a set of vertex
-- indices left sharp, e.g. the ends of a cut between parts). Returns the new
-- polygon and, per new vertex, the index of the original edge that leaves it
-- (0 on arc segments) so callers can still address edges by their index.
function Shapes.round(poly, corners, r, segs, keep)
	segs = segs or 5
	local n = #poly
	local want = {}
	if corners == "convex" then
		local area = 0
		for i = 1, n do
			local a, c = poly[i], poly[i % n + 1]
			area += a[1] * c[2] - c[1] * a[2]
		end
		for i = 1, n do
			local p, c, q = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]
			local cr = (c[1] - p[1]) * (q[2] - c[2]) - (c[2] - p[2]) * (q[1] - c[1])
			if cr * area > 0 and not (keep and keep[i]) then want[i] = true end
		end
	else
		for _, i in ipairs(corners) do want[i] = true end
	end
	local out, ids = {}, {}
	for i = 1, n do
		local p, c, q = poly[(i - 2) % n + 1], poly[i], poly[i % n + 1]
		if not want[i] then
			table.insert(out, c)
			table.insert(ids, i)
		else
			local ax, ay = p[1] - c[1], p[2] - c[2]
			local bx, by = q[1] - c[1], q[2] - c[2]
			local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
			ax, ay, bx, by = ax / la, ay / la, bx / lb, by / lb
			local cosT = math.clamp(ax * bx + ay * by, -1, 1)
			local theta = math.acos(cosT)
			local d = math.min(r / math.tan(theta / 2), la * 0.45, lb * 0.45)
			local rr = d * math.tan(theta / 2)
			local s1 = { c[1] + ax * d, c[2] + ay * d }
			local s2 = { c[1] + bx * d, c[2] + by * d }
			-- centre along the bisector
			local mx, my = ax + bx, ay + by
			local ml = math.sqrt(mx * mx + my * my)
			local h = math.sqrt(d * d + rr * rr)
			local o = { c[1] + mx / ml * h, c[2] + my / ml * h }
			local a1 = math.atan2(s1[2] - o[2], s1[1] - o[1])
			local a2 = math.atan2(s2[2] - o[2], s2[1] - o[1])
			local da = a2 - a1
			if da > math.pi then da -= 2 * math.pi elseif da < -math.pi then da += 2 * math.pi end
			for k = 0, segs do
				local ang = a1 + da * k / segs
				table.insert(out, { o[1] + math.cos(ang) * rr, o[2] + math.sin(ang) * rr })
				table.insert(ids, k == segs and i or 0)
			end
		end
	end
	return out, ids
end

-- ground under a polygon: lowest and mean terrain at its vertices
function Shapes.groundOf(F, poly)
	local lo, sum, n = math.huge, 0, 0
	for _, p in ipairs(poly) do
		local y = F.ground(p[1], p[2])
		if y then
			lo = math.min(lo, y)
			sum += y
			n += 1
		end
	end
	if n == 0 then return 0, 0 end
	return lo, sum / n
end

local function cross2(o, a, b)
	return (a.X - o.X) * (b.Z - o.Z) - (a.Z - o.Z) * (b.X - o.X)
end

local function inTri(p, a, b, c)
	local d1, d2, d3 = cross2(a, b, p), cross2(b, c, p), cross2(c, a, p)
	local neg = d1 < 0 or d2 < 0 or d3 < 0
	local pos = d1 > 0 or d2 > 0 or d3 > 0
	return not (neg and pos)
end

-- ear clipping on world XZ points (any winding); returns index triples
function Shapes.triangulate(pts)
	local n = #pts
	local area = 0
	for i = 1, n do
		local a, b = pts[i], pts[i % n + 1]
		area += a.X * b.Z - b.X * a.Z
	end
	local sign = area > 0 and 1 or -1
	local idx = {}
	for i = 1, n do idx[i] = i end
	local tris = {}
	local guard = 0
	while #idx > 3 and guard < 5000 do
		guard += 1
		local m = #idx
		local clipped = false
		for k = 1, m do
			local ia, ib, ic = idx[(k - 2) % m + 1], idx[k], idx[k % m + 1]
			local a, b, c = pts[ia], pts[ib], pts[ic]
			if cross2(a, b, c) * sign > 1e-6 then
				local ok = true
				for _, j in ipairs(idx) do
					if j ~= ia and j ~= ib and j ~= ic and inTri(pts[j], a, b, c) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(tris, { ia, ib, ic })
					table.remove(idx, k)
					clipped = true
					break
				end
			end
		end
		if not clipped then
			-- degenerate remainder (collinear points): drop the flattest vertex
			table.remove(idx, 1)
		end
	end
	if #idx == 3 then table.insert(tris, { idx[1], idx[2], idx[3] }) end
	return tris
end

-- a flat triangle a-b-c (world points) as two wedges, slab thickness th
function Shapes.triangle(b, name, a, p, c, th, material, color)
	local ab, ac, bc = p - a, c - a, c - p
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, p = p, a
	end
	ab, ac, bc = p - a, c - a, c - p
	if bc.Magnitude < 0.05 then return end
	local rv = ac:Cross(ab)
	if rv.Magnitude < 1e-4 then return end
	local right = rv.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.05 then return end
	local d1, d2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if d1 > 0.05 then
		b:wedge(name, Vector3.new(th, height, d1), CFrame.fromMatrix((a + p) / 2, right, up, back), material, color)
	end
	if d2 > 0.05 then
		b:wedge(name, Vector3.new(th, height, d2), CFrame.fromMatrix((a + c) / 2, -right, up, -back), material, color)
	end
end

-- flat polygon slab (roof / terrace / plaza) at height y
function Shapes.slab(b, name, pts2, y, th, material, color)
	local pts = {}
	for i, p in ipairs(pts2) do pts[i] = Vector3.new(p.X, y, p.Z) end
	for _, t in ipairs(Shapes.triangulate(pts)) do
		Shapes.triangle(b, name, pts[t[1]], pts[t[2]], pts[t[3]], th, material, color)
	end
end

-- walls along every edge, coping and a flat roof.
-- o: base, top, material, color, t (wall thickness studs), coping={h,color,out},
--    roof={color, material} or false, name
-- returns edges: {p0, p1, mid, len, n (outward), right, face (CFrame on the
-- outer face at y=0, -Z outward), base, top}
function Shapes.extrude(b, F, poly, o)
	local pts = {}
	for i, p in ipairs(poly) do pts[i] = F.pt(p[1], p[2]) end
	local n = #pts
	local area = 0
	for i = 1, n do
		local a, c = pts[i], pts[i % n + 1]
		area += a.X * c.Z - c.X * a.Z
	end
	local t = o.t or 2
	local h = o.top - o.base
	local edges = {}
	for i = 1, n do
		local p0, p1 = pts[i], pts[i % n + 1]
		local d = p1 - p0
		local len = d.Magnitude
		if len > 0.2 then
			d = d / len
			-- outward normal from the winding
			local nrm = area > 0 and Vector3.new(d.Z, 0, -d.X) or Vector3.new(-d.Z, 0, d.X)
			local mid = (p0 + p1) / 2
			local face = CFrame.lookAt(mid, mid + nrm)
			local extra = len < 8 and t * 0.6 or t * 0.5
			b:part(o.name or "Walls", Vector3.new(len + extra, h, t),
				face * CFrame.new(0, o.base + h / 2, t / 2), o.material, o.color, true)
			if o.coping then
				local ch = o.coping.h or 1.6
				local out = o.coping.out or 0.4
				b:part("Coping", Vector3.new(len + extra + out, ch, t + out * 2),
					face * CFrame.new(0, o.top - ch / 2 + 0.3, t / 2), o.coping.material or Enum.Material.SmoothPlastic, o.coping.color)
			end
			table.insert(edges, { p0 = p0, p1 = p1, mid = mid, len = len, n = nrm, face = face,
				right = face.RightVector, base = o.base, top = o.top, i = o.ids and o.ids[i] or i })
		end
	end
	if o.roof ~= false then
		local roof = o.roof or {}
		Shapes.slab(b, "Roof", pts, o.top - 0.6, 1.2, roof.material or Enum.Material.SmoothPlastic,
			roof.color or Color3.fromRGB(200, 200, 196))
	end
	return edges
end

-- nearest edge to a (u, v) anchor and the anchor's coordinate along it
function Shapes.edgeAt(F, edges, u, v)
	local p = F.pt(u, v)
	local best, bestD, bestX
	for _, e in ipairs(edges) do
		local d = e.p1 - e.p0
		local s = math.clamp((p - e.p0):Dot(d) / d:Dot(d), 0, 1)
		local q = e.p0 + d * s
		local dist = (p - q).Magnitude
		if not bestD or dist < bestD then
			best, bestD, bestX = e, dist, (q - e.mid):Dot(e.right)
		end
	end
	return best, bestX
end

-- punched window grid on one edge (see header)
-- o: ground, floors, storey, sill, h, w, n (windows per bay), gap (mullion),
--    bay, margin, glass, wall, wallMat, stone (sill colour or nil)
function Shapes.punched(b, e, o)
	local margin = o.margin or 6
	local span = e.len - 2 * margin
	if span < o.bay * 0.8 then return end
	local cols = math.max(1, math.floor(span / o.bay))
	local per = o.n or 1
	local gap = o.gap or 0.9
	local w = per * o.w + (per - 1) * gap
	local y0 = o.ground + o.sill
	local y1 = o.ground + o.sill + (o.floors - 1) * o.storey + o.h
	local skip = o.skip or {}
	for i = 1, cols do
		local x = -span / 2 + (i - 0.5) * span / cols
		local skipped = false
		for _, s in ipairs(skip) do
			if math.abs(x - s[1]) < s[2] then skipped = true end
		end
		if not skipped then
			b:part("WindowGlass", Vector3.new(w, y1 - y0, 0.2), e.face * CFrame.new(x, (y0 + y1) / 2, -0.1),
				Enum.Material.Glass, o.glass)
			for k = 1, per - 1 do
				b:part("Mullion", Vector3.new(gap, y1 - y0, 0.4),
					e.face * CFrame.new(x - w / 2 + k * o.w + (k - 0.5) * gap, (y0 + y1) / 2, -0.2), o.wallMat, o.wall)
			end
			if o.stone then
				b:part("Sill", Vector3.new(w + 0.8, 0.5, 0.7), e.face * CFrame.new(x, y0 - 0.25, -0.35),
					Enum.Material.Concrete, o.stone)
			end
		end
	end
	for k = 1, o.floors - 1 do
		local a = o.ground + o.sill + (k - 1) * o.storey + o.h
		local c = o.ground + o.sill + k * o.storey
		b:part("Spandrel", Vector3.new(span + 2, c - a, 0.4), e.face * CFrame.new(0, (a + c) / 2, -0.2), o.wallMat, o.wall)
	end
end

-- one photographed window group centred at x on an edge face
-- g: n, w, h, sill (studs above ground), gap, frame (stone colour or nil)
function Shapes.group(b, e, x, ground, g, glass, wall, wallMat)
	local n, w, gap = g.n or 1, g.w, g.gap or 1.2
	local total = n * w + (n - 1) * gap
	local y = ground + g.sill + g.h / 2
	if g.frame then
		b:part("WindowSurround", Vector3.new(total + 1.4, g.h + 1.4, 0.3), e.face * CFrame.new(x, y, -0.12),
			Enum.Material.Limestone, g.frame)
	end
	b:part("WindowGlass", Vector3.new(total, g.h, 0.2), e.face * CFrame.new(x, y, -0.25), Enum.Material.Glass, glass)
	for k = 1, n - 1 do
		b:part("Mullion", Vector3.new(gap, g.h, 0.3),
			e.face * CFrame.new(x - total / 2 + k * w + (k - 0.5) * gap, y, -0.32), g.frame and Enum.Material.Limestone or wallMat,
			g.frame or wall)
	end
end

-- a sign face: SurfaceGui with stacked text lines on the -Z face of `part`
-- lines: { {text, size (0-1 share of height), font, color} }
function Shapes.signText(part, face, lines, pps)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps or 24
	gui.LightInfluence = 0.6
	gui.Parent = part
	local y = 0
	for _, l in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(l.x or 0.04, l.y or y)
		label.Size = UDim2.fromScale(l.wScale or 0.92, l.size)
		label.TextScaled = true
		label.Font = l.font or Enum.Font.Garamond
		label.TextColor3 = l.color or Color3.new(1, 1, 1)
		label.Text = l.text
		label.TextXAlignment = l.align or Enum.TextXAlignment.Center
		label.Parent = gui
		y += l.size
	end
	return gui
end

return Shapes
