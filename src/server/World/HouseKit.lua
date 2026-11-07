-- Chester house kit (2026-11-07). Built from the Google Street View building
-- fronts (Data/25_GoogleStreetView_Buildings, private reference only) of the
-- 9th & Kerlin blocks and of Parkside / Eddystone / Brookhaven / Woodlyn:
--
--   porch_row       2-storey brick rows (Butler, Kerlin, W 8th): a full-width
--                   porch per unit (posts, rail, shed roof), and a parapet -
--                   stepped "castle" merlons, a bracketed cornice, or a
--                   shingled mansard front with a dormer (Parker St)
--   flat_row        rows with no porch: a stoop per unit, aluminium awnings
--   victorian_twin  2.5-3 storeys, side-gable roof with a front gable dormer
--                   per half, porch, brick below / siding above
--   colonial_twin   suburban 2-storey twin, side gable, siding, shutters
--   victorian_house front-gable detached house with a porch and a chimney
--   colonial_house  side-gable detached house, shutters, small portico
--   apartment       brick walk-up, flat roof with cornice, centre entrance
--
-- Each unit of a row / twin gets its own finish (Chester rows mix red brick
-- and white / grey / beige vinyl siding unit by unit). Windows are modelled
-- per storey: front, back, and exposed side walls only. One front door per
-- unit, a back door, a side door only on a detached house.
--
-- A rentable unit (1 in ~5, deterministic) has a real ground floor: a hollow
-- shell with a living room, kitchen and a stash chest, a FOR RENT sign in the
-- front window, and its front door tagged for Exit6Housing (Exit6Rentable).
local CollectionService = game:GetService("CollectionService")

local HouseKit = {}

local SIDING = {
	Color3.fromRGB(236, 236, 230), Color3.fromRGB(176, 178, 176), Color3.fromRGB(216, 202, 172),
	Color3.fromRGB(226, 208, 146), Color3.fromRGB(124, 140, 154), Color3.fromRGB(154, 166, 144),
	Color3.fromRGB(206, 210, 214),
}
local SHUTTERS = { Color3.fromRGB(30, 34, 40), Color3.fromRGB(36, 64, 44), Color3.fromRGB(110, 30, 32), Color3.fromRGB(40, 56, 92) }
local AWNINGS = { Color3.fromRGB(46, 96, 64), Color3.fromRGB(120, 92, 60), Color3.fromRGB(176, 172, 160), Color3.fromRGB(150, 40, 36) }
local ROOFS = { Color3.fromRGB(62, 60, 60), Color3.fromRGB(84, 64, 56), Color3.fromRGB(70, 74, 80), Color3.fromRGB(96, 92, 86) }
local WINDOW_GLASS = Color3.fromRGB(46, 58, 70)
local WHITE = Color3.fromRGB(236, 234, 226)
local STONE = Color3.fromRGB(186, 178, 164)
local RENT_EVERY = 5

local function hash(a, b)
	local h = 2166136261
	local s = tostring(a) .. ":" .. tostring(b)
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end
local function pick(list, h, salt)
	return list[(hash(h, salt) % #list) + 1]
end
local function vary(c, h, amt)
	local d = ((hash(h, "v") % 100) / 100 - 0.5) * amt
	return Color3.new(math.clamp(c.R + d, 0, 1), math.clamp(c.G + d * 0.9, 0, 1), math.clamp(c.B + d * 0.8, 0, 1))
end

local function archetypeFor(ctx, floors, span)
	local h = hash(ctx.buildingId, "arch")
	local style = ctx.style
	if style == "rowhouse" then
		return ctx.porch and "porch_row" or "flat_row"
	elseif style == "twin" then
		return (floors >= 3 or h % 3 == 0) and "victorian_twin" or "colonial_twin"
	elseif style == "house" then
		if floors >= 3 then return "victorian_house" end
		return (h % 2 == 0) and "victorian_house" or "colonial_house"
	end
	return "apartment"
end

-- H: helpers from RealBuildings { part, faceAxis, faceOf, covered, door, DOOR_COLORS, TRIM, CONCRETE, UNIT_STUDS }
function HouseKit.Build(model, r, ctx, H)
	local part = H.part
	local stats = ctx.stats
	local storeyH = math.clamp(r.storey, 9, 12)
	local floorY = r.streetLevel + 0.4
	-- Chester rows and twins are two storeys at least (Street View); the county
	-- heights put some at one (e.g. 144078 on Butler St: 4.7 m, really 2 floors)
	if (ctx.style == "rowhouse" or ctx.style == "twin") and r.wallTop < floorY + 2 * storeyH then
		r.wallTop = floorY + 2 * storeyH + 0.6
	end
	local floors = math.max(1, math.floor((r.wallTop - floorY) / storeyH + 0.35))
	local function solid(name, size, cf, mat, color)
		return part(model, name, size, cf, mat, color)
	end

	-- no street front (a rear addition / garage): a plain block with a few windows
	local nFront = ctx.front and H.faceAxis(r.frame, ctx.front)
	local fcf, span = nil, 0
	if nFront then fcf, span = H.faceOf(r, nFront) end
	local frontExposed = nFront and span >= 7 and not H.covered((fcf * CFrame.new(0, 0, -2.5)).Position, ctx.rects, r)
	local depth = nFront and ((nFront.X ~= 0) and r.along or r.across) or math.min(r.along, r.across)

	local h0 = hash(ctx.buildingId, math.floor(r.frame.X) .. ":" .. math.floor(r.frame.Z))
	local arch = archetypeFor(ctx, floors, span)
	local brick = ctx.material == Enum.Material.Brick
	local baseWall = ctx.wall
	local roofColor = pick(ROOFS, h0, "roof")
	local function at(face, u, y, z)
		return face * CFrame.new(u, 0, z) + Vector3.new(0, y, 0)
	end
	local function exposed(face, u)
		return not H.covered((face * CFrame.new(u, 0, -2.5)).Position, ctx.rects, r)
	end

	-- a modelled window: trim frame + dark glass (+ sill), optional shutters / awning
	local function window(face, u, y, w, hgt, opts)
		opts = opts or {}
		solid("WindowTrim", Vector3.new(w + 0.7, hgt + 0.7, 0.28), at(face, u, y, -0.1), Enum.Material.SmoothPlastic, opts.trim or WHITE)
		local g = solid("WindowGlass", Vector3.new(w, hgt, 0.3), at(face, u, y, -0.16), Enum.Material.Glass, WINDOW_GLASS)
		g.Transparency = opts.clear and 0.55 or 0.15
		solid("WindowMullion", Vector3.new(w, 0.18, 0.34), at(face, u, y + hgt * 0.08, -0.18), Enum.Material.SmoothPlastic, opts.trim or WHITE)
		if opts.sill then
			solid("Sill", Vector3.new(w + 1.0, 0.3, 0.6), at(face, u, y - hgt / 2 - 0.45, -0.3), Enum.Material.Concrete, STONE)
		end
		if opts.shutters then
			for _, s in ipairs({ -1, 1 }) do
				solid("Shutter", Vector3.new(1.0, hgt + 0.4, 0.2), at(face, u + s * (w / 2 + 0.95), y, -0.12), Enum.Material.WoodPlanks, opts.shutters)
			end
		end
		if opts.awning then
			local a = solid("Awning", Vector3.new(w + 1.2, 0.2, 2.0), at(face, u, y + hgt / 2 + 0.7, -1.0) * CFrame.Angles(math.rad(28), 0, 0),
				Enum.Material.Metal, opts.awning)
			a.CanCollide = false
		end
		return g
	end

	-- walls: one slice per unit (its own finish), or one block
	if not nFront or not frontExposed then
		local block = solid("Walls", Vector3.new(r.along, r.wallTop - r.base, r.across), r.frame + Vector3.new(0, (r.wallTop + r.base) / 2, 0),
			ctx.material, baseWall)
		block:SetAttribute("GroundY", floorY)
		for _, n in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
			local face, fspan = H.faceOf(r, n)
			if fspan >= 10 and exposed(face, 0) then
				for k = 0, floors - 1 do
					window(face, 0, floorY + k * storeyH + storeyH * 0.55, 3.4, 4.6, { sill = brick })
				end
			end
		end
		solid("Roof", Vector3.new(r.along + 0.6, 0.6, r.across + 0.6), r.frame + Vector3.new(0, r.wallTop + 0.3, 0), Enum.Material.Concrete, roofColor)
		return
	end

	local units = 1
	if ctx.style == "rowhouse" then
		units = math.max(1, math.floor(span / H.UNIT_STUDS + 0.5))
	elseif ctx.style == "twin" and span >= 26 then
		units = 2
	end
	local w = span / units
	local wallH = r.wallTop - r.base
	local groundTop = floorY + storeyH
	local porchDepth = math.clamp(ctx.porchDepth or 7, 5, 10)
	local hasPorch = arch == "porch_row" or arch == "victorian_twin" or arch == "victorian_house"
		or (ctx.porch and arch ~= "flat_row" and arch ~= "apartment")
	local parapet = ({ "castle", "castle", "cornice", "mansard" })[(hash(ctx.buildingId, "parapet") % 4) + 1]
	local shutterColor = pick(SHUTTERS, h0, "shutter")
	local awningColor = pick(AWNINGS, h0, "awning")

	for i = 1, units do
		local hu = hash(ctx.buildingId, "unit" .. i .. ":" .. math.floor(r.frame.X))
		local u = -span / 2 + w * (i - 0.5)
		-- finish of this unit
		local siding
		if arch == "colonial_twin" or arch == "colonial_house" then
			siding = (hu % 10 < 8)
		elseif arch == "victorian_twin" or arch == "victorian_house" then
			siding = (hu % 10 < 5)
		elseif arch == "apartment" then
			siding = false
		else
			siding = (hu % 10 < 3)
		end
		local mat = siding and Enum.Material.WoodPlanks or ctx.material
		local col = siding and pick(SIDING, hu, "siding") or vary(baseWall, hu, 0.08)
		local trim = siding and WHITE or (hu % 3 == 0 and Color3.fromRGB(40, 40, 42) or WHITE)
		local rentable = (arch ~= "apartment") and (hu % RENT_EVERY == 0) and w >= 12 and depth >= 18
		-- door position: toward one side of the unit, mirrored pair by pair
		local side = (i % 2 == 0) and 1 or -1
		if units == 1 then side = (hu % 2 == 0) and 1 or -1 end
		local doorU = u + side * math.min(w * 0.25, 4.2)
		local winU = u - side * math.min(w * 0.2, 3.8)
		if units == 1 and arch ~= "flat_row" and arch ~= "porch_row" then
			doorU = u + side * math.min(w * 0.12, 3)
		end
		local sliceCf = fcf * CFrame.new(u, 0, depth / 2)
		if rentable then
			-- hollow ground floor; the storeys above stay solid
			local upperH = r.wallTop - groundTop
			if upperH > 0.5 then
				solid("Walls", Vector3.new(w, upperH, depth), sliceCf + Vector3.new(0, (r.wallTop + groundTop) / 2, 0), mat, col)
			end
			if floorY - r.base > 0.2 then
				solid("Foundation", Vector3.new(w, floorY - r.base, depth), sliceCf + Vector3.new(0, (floorY + r.base) / 2, 0), Enum.Material.Concrete,
					H.CONCRETE)
			end
			local gh = storeyH
			-- (floor top a hair above the foundation: no z-fighting)
			solid("HomeFloor", Vector3.new(w - 0.2, 0.4, depth - 0.2), sliceCf + Vector3.new(0, floorY - 0.14, 0), Enum.Material.WoodPlanks,
				Color3.fromRGB(150, 110, 76))
			solid("HomeCeiling", Vector3.new(w, 0.5, depth), sliceCf + Vector3.new(0, groundTop - 0.25, 0), Enum.Material.SmoothPlastic,
				Color3.fromRGB(236, 232, 224))
			local function wallPiece(x0, x1, y0, y1, z)
				if x1 - x0 < 0.05 or y1 - y0 < 0.05 then return end
				solid("HomeWall", Vector3.new(x1 - x0, y1 - y0, 0.8), at(fcf, (x0 + x1) / 2, (y0 + y1) / 2, z), mat, col)
			end
			-- front wall around the door and the window
			local open = {
				{ doorU - 2.2, doorU + 2.2, floorY, floorY + 8.6 },
				{ winU - 2.3, winU + 2.3, floorY + 2.6, floorY + 8.2 },
			}
			table.sort(open, function(a, b) return a[1] < b[1] end)
			local x = u - w / 2
			for _, o in ipairs(open) do
				wallPiece(x, o[1], floorY, groundTop, 0.4)
				wallPiece(o[1], o[2], o[4], groundTop, 0.4)
				wallPiece(o[1], o[2], floorY, o[3], 0.4)
				x = o[2]
			end
			wallPiece(x, u + w / 2, floorY, groundTop, 0.4)
			-- back and party walls
			solid("HomeWall", Vector3.new(w, gh, 0.8), at(fcf, u, floorY + gh / 2, depth - 0.4), mat, col)
			for _, s in ipairs({ -1, 1 }) do
				solid("HomeWall", Vector3.new(0.8, gh, depth), at(fcf, u + s * (w / 2 - 0.4), floorY + gh / 2, depth / 2), mat, col)
			end
			local inner = function(x, y, z) return at(fcf, u + x, floorY + y, z) end
			-- drywall inside the shell (the walls themselves carry the outside finish)
			local DRY = pick({ Color3.fromRGB(232, 226, 212), Color3.fromRGB(214, 222, 226), Color3.fromRGB(226, 216, 196) }, hu, "paint")
			solid("Drywall", Vector3.new(w - 1.6, gh - 0.6, 0.12), at(fcf, u, floorY + gh / 2 - 0.3, depth - 0.86), Enum.Material.SmoothPlastic, DRY)
			for _, s in ipairs({ -1, 1 }) do
				solid("Drywall", Vector3.new(0.12, gh - 0.6, depth - 1.8), at(fcf, u + s * (w / 2 - 0.86), floorY + gh / 2 - 0.3, depth / 2), Enum.Material.SmoothPlastic, DRY)
			end
			-- a partition between the front room and the kitchen, doorway in the middle
			local pz = math.min(depth * 0.55, 26)
			for _, s in ipairs({ -1, 1 }) do
				local pw = (w - 1.6) / 2 - 2.2
				if pw > 0.5 then
					solid("Partition", Vector3.new(pw, gh - 0.6, 0.5), at(fcf, u + s * (2.2 + pw / 2), floorY + gh / 2 - 0.3, pz), Enum.Material.SmoothPlastic, DRY)
				end
			end
			solid("Partition", Vector3.new(4.4, gh - 0.6 - 8, 0.5), at(fcf, u, floorY + 8 + (gh - 0.6 - 8) / 2, pz), Enum.Material.SmoothPlastic, DRY)
			-- dining table and chairs in the back room
			local dz = pz + (depth - pz) * 0.45
			solid("DiningTable", Vector3.new(4, 0.3, 6), inner(0, 2.9, dz), Enum.Material.Wood, Color3.fromRGB(120, 86, 56))
			solid("TableLeg", Vector3.new(0.4, 2.8, 0.4), inner(0, 1.4, dz), Enum.Material.Wood, Color3.fromRGB(100, 70, 46))
			for _, c in ipairs({ { -2.6, -1.5 }, { -2.6, 1.5 }, { 2.6, -1.5 }, { 2.6, 1.5 } }) do
				solid("Chair", Vector3.new(1.6, 1.8, 1.6), inner(c[1], 0.9, dz + c[2]), Enum.Material.Wood, Color3.fromRGB(110, 78, 52))
			end
			-- furniture: living room at the front, kitchen at the back
			local wood = Color3.fromRGB(110, 78, 52)
			local fabric = pick({ Color3.fromRGB(60, 70, 96), Color3.fromRGB(110, 60, 50), Color3.fromRGB(70, 90, 70), Color3.fromRGB(90, 86, 82) }, hu, "couch")
			local cx = -side * (w / 2 - 3)
			solid("Couch", Vector3.new(2.6, 2.2, 7), inner(cx, 1.1, depth * 0.38), Enum.Material.Fabric, fabric)
			solid("CouchBack", Vector3.new(0.9, 3.4, 7), inner(cx + (cx > 0 and 1.3 or -1.3), 1.7, depth * 0.38), Enum.Material.Fabric, fabric)
			solid("CoffeeTable", Vector3.new(2.4, 1.4, 4), inner(cx + (cx > 0 and -3.4 or 3.4), 0.7, depth * 0.38), Enum.Material.Wood, wood)
			solid("Rug", Vector3.new(7, 0.1, 9), inner(cx + (cx > 0 and -3 or 3), 0.05, depth * 0.38), Enum.Material.Fabric, Color3.fromRGB(150, 120, 96))
			solid("TVStand", Vector3.new(1.6, 2.4, 5), inner(-cx, 1.2, depth * 0.38), Enum.Material.Wood, wood)
			solid("TV", Vector3.new(0.3, 2.8, 4.6), inner(-cx + (cx > 0 and 0.6 or -0.6), 3.9, depth * 0.38), Enum.Material.SmoothPlastic,
				Color3.fromRGB(16, 16, 18))
			solid("KitchenCounter", Vector3.new(w - 3, 3.2, 2.4), inner(0, 1.6, depth - 2.2), Enum.Material.Marble, Color3.fromRGB(220, 216, 208))
			solid("Fridge", Vector3.new(3, 6.6, 2.6), inner(side * (w / 2 - 2.4), 3.3, depth - 5), Enum.Material.SmoothPlastic, Color3.fromRGB(226, 228, 230))
			local stash = solid("StashChest", Vector3.new(3.4, 2.2, 2.2), inner(-side * (w / 2 - 2.6), 1.1, depth - 6.5), Enum.Material.WoodPlanks,
				Color3.fromRGB(120, 86, 56))
			stash:SetAttribute("Exit6Stash", true)
			local lamp = solid("CeilingLamp", Vector3.new(1.6, 0.4, 1.6), inner(0, groundTop - floorY - 0.7, depth * 0.45), Enum.Material.Neon,
				Color3.fromRGB(255, 240, 210))
			local light = Instance.new("PointLight")
			light.Range = 22
			light.Brightness = 1.2
			light.Color = Color3.fromRGB(255, 236, 200)
			light.Parent = lamp
			rentable = { stash = stash, depth = depth }
		else
			local block = solid("Walls", Vector3.new(w, wallH, depth), sliceCf + Vector3.new(0, (r.wallTop + r.base) / 2, 0), mat, col)
			block:SetAttribute("GroundY", floorY)
		end

		-- front: door, ground window, upper windows
		local doorColor = H.DOOR_COLORS[(hu % #H.DOOR_COLORS) + 1]
		local d = H.door(model, fcf, doorU, r.streetLevel + 0.4, doorColor, not hasPorch)
		CollectionService:AddTag(d, "Exit6FrontDoor")
		ctx.homeDoors = (ctx.homeDoors or 0) + 1
		d:SetAttribute("Exit6HomeId", tostring(ctx.buildingId) .. ":" .. ctx.homeDoors)
		d:SetAttribute("Exit6HomeStyle", ctx.style)
		stats.frontDoors += 1
		local opts = { sill = not siding, trim = trim, clear = rentable and true or false,
			shutters = (arch == "colonial_twin" or arch == "colonial_house") and shutterColor or nil,
			awning = (arch == "flat_row" or (arch == "porch_row" and hu % 4 == 0)) and awningColor or nil }
		local gwin = window(fcf, winU, floorY + storeyH * 0.52, 4.4, 5.4, { sill = opts.sill, trim = trim, clear = opts.clear,
			shutters = opts.shutters, awning = (arch == "flat_row") and awningColor or nil })
		for k = 1, floors - 1 do
			local y = floorY + k * storeyH + storeyH * 0.52
			if w >= 15 then
				window(fcf, u - w * 0.22, y, 3.4, 4.8, opts)
				window(fcf, u + w * 0.22, y, 3.4, 4.8, opts)
			else
				window(fcf, u, y, 3.6, 4.8, opts)
			end
		end
		if rentable then
			d:SetAttribute("Exit6Rentable", true)
			d:SetAttribute("Exit6HomeDepth", depth)
			-- FOR RENT sign stuck on the front window
			local sign = Instance.new("Part")
			sign.Name = "RentSign"
			sign.Anchored = true
			sign.CanCollide = false
			sign.Size = Vector3.new(3.2, 2.0, 0.1)
			sign.CFrame = at(fcf, winU, floorY + storeyH * 0.45, -0.45)
			sign.Color = Color3.fromRGB(240, 240, 236)
			sign.Material = Enum.Material.SmoothPlastic
			local sg = Instance.new("SurfaceGui")
			sg.Face = Enum.NormalId.Front
			sg.PixelsPerStud = 40
			sg.Parent = sign
			local tl = Instance.new("TextLabel")
			tl.Name = "Text"
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Text = "FOR RENT"
			tl.TextColor3 = Color3.fromRGB(190, 24, 28)
			tl.Font = Enum.Font.GothamBlack
			tl.TextScaled = true
			tl.Parent = sg
			sign.Parent = d
			stats.rentals = (stats.rentals or 0) + 1
		end

		-- porch (per unit) or the stoop the door already has
		if hasPorch then
			local pf = r.streetLevel + 0.7
			local floorPart = solid("PorchFloor", Vector3.new(w, pf - r.base, porchDepth), at(fcf, u, (pf + r.base) / 2, -porchDepth / 2),
				Enum.Material.Concrete, Color3.fromRGB(150, 146, 140))
			floorPart.CanCollide = true
			local roofY = groundTop + 0.2
			local pr = solid("PorchRoof", Vector3.new(w + 0.1, 0.45, porchDepth + 0.8), at(fcf, u, roofY, -(porchDepth + 0.8) / 2 + 0.2)
				* CFrame.Angles(math.rad(-7), 0, 0), Enum.Material.SmoothPlastic, (arch == "porch_row" and hu % 2 == 0) and roofColor or trim)
			pr.CanCollide = false
			solid("PorchFascia", Vector3.new(w + 0.1, 0.9, 0.3), at(fcf, u, roofY - 0.3, -porchDepth - 0.1), Enum.Material.SmoothPlastic, trim)
			for _, s in ipairs({ -1, 1 }) do
				if s == -1 or i == units then
					local post = solid("PorchPost", Vector3.new(0.7, roofY - pf, 0.7), at(fcf, u + s * (w / 2 - 0.45), (roofY + pf) / 2, -porchDepth + 0.5),
						Enum.Material.SmoothPlastic, trim)
					post.CanCollide = false
				end
			end
			-- railing across the front, open at the steps in front of the door
			local gapL, gapR = doorU - 2.4, doorU + 2.4
			local function rail(x0, x1)
				if x1 - x0 < 0.8 then return end
				local c = (x0 + x1) / 2
				solid("PorchRail", Vector3.new(x1 - x0, 0.3, 0.3), at(fcf, c, pf + 3.0, -porchDepth + 0.4), Enum.Material.SmoothPlastic, trim)
				local spindles = solid("PorchSpindles", Vector3.new(x1 - x0, 2.6, 0.12), at(fcf, c, pf + 1.6, -porchDepth + 0.4), Enum.Material.DiamondPlate, trim)
				spindles.Transparency = 0.35
			end
			rail(u - w / 2 + 0.8, gapL)
			rail(gapR, u + w / 2 - 0.8)
			solid("PorchStep", Vector3.new(4.4, 0.4, 1.4), at(fcf, doorU, r.streetLevel + 0.2, -porchDepth - 0.7), Enum.Material.Concrete,
				Color3.fromRGB(150, 146, 140))
		end

		-- back: a door and a window per storey
		local bcf, bspan = H.faceOf(r, -nFront)
		local bu = -u   -- the back face runs the other way
		if bspan >= 7 and exposed(bcf, bu) then
			H.door(model, bcf, bu + side * math.min(w * 0.25, 4), r.streetLevel + 0.4, doorColor, false)
			stats.backDoors += 1
			for k = 0, floors - 1 do
				window(bcf, bu - side * math.min(w * 0.22, 3.6), floorY + k * storeyH + storeyH * 0.52, 3.2, 4.4, { trim = trim, sill = not siding })
			end
		end

		-- roof details per unit
		if arch == "porch_row" or arch == "flat_row" then
			if parapet == "castle" then
				-- stepped brick parapet with a raised centre per unit (Butler St)
				local py = r.wallTop
				solid("ParapetBand", Vector3.new(w, 0.6, 0.9), at(fcf, u, py - 1.2, -0.25), Enum.Material.Concrete, STONE)
				local merlons = math.max(3, math.floor(w / 3.2))
				for m = 1, merlons do
					local mu = u - w / 2 + (m - 0.5) * (w / merlons)
					local centreBoost = (m == math.ceil(merlons / 2)) and 1.6 or 0
					if m % 2 == 1 or centreBoost > 0 then
						solid("Merlon", Vector3.new(w / merlons, 2.0 + centreBoost, 0.9), at(fcf, mu, py + 1.0 + centreBoost / 2, 0.45), mat, col)
					end
				end
				solid("Parapet", Vector3.new(w, 1.0, 0.9), at(fcf, u, py + 0.5, 0.45), mat, col)
			elseif parapet == "cornice" then
				solid("Cornice", Vector3.new(w + 0.1, 1.3, 1.4), at(fcf, u, r.wallTop + 0.3, -0.3), Enum.Material.SmoothPlastic, trim)
				for b = -1, 1 do
					solid("Bracket", Vector3.new(0.5, 1.2, 1.0), at(fcf, u + b * (w / 2 - 1), r.wallTop - 0.8, -0.4), Enum.Material.SmoothPlastic, trim)
				end
			else
				-- shingled mansard front with a dormer
				local m = Instance.new("WedgePart")
				m.Name = "Mansard"
				m.Anchored = true
				m.Material = Enum.Material.Slate
				m.Color = roofColor
				m.Size = Vector3.new(w, 4.6, 3.2)
				m.CFrame = at(fcf, u, r.wallTop + 2.3, 1.2) * CFrame.Angles(0, math.pi, 0)
				m.Parent = model
				solid("Dormer", Vector3.new(4.4, 3.6, 2.6), at(fcf, u, r.wallTop + 2.3, 0.4), Enum.Material.WoodPlanks, trim)
				window(fcf, u, r.wallTop + 2.3, 2.6, 2.4, { trim = trim })
			end
		elseif arch == "victorian_twin" or arch == "victorian_house" then
			-- a front gable over each half
			local gw = math.min(w * 0.7, 14)
			local rise = math.min(gw * 0.5, 7)
			for s = -1, 1, 2 do
				local wd = Instance.new("WedgePart")
				wd.Name = "FrontGable"
				wd.Anchored = true
				wd.Material = mat
				wd.Color = col
				wd.Size = Vector3.new(0.9, rise, gw / 2)
				wd.CFrame = at(fcf, u + s * gw / 4, r.wallTop + rise / 2, 0.45) * CFrame.Angles(0, s == 1 and math.rad(-90) or math.rad(90), 0)
				wd.Parent = model
			end
			window(fcf, u, r.wallTop + rise * 0.38, 2.4, 2.8, { trim = trim })
		end
	end

	-- exposed side walls: windows per storey (and a side door on a house)
	for _, n in ipairs({ Vector3.new(nFront.Z, 0, -nFront.X), Vector3.new(-nFront.Z, 0, nFront.X) }) do
		local scf, sspan = H.faceOf(r, n)
		if sspan >= 14 then
			for _, t in ipairs({ -0.25, 0.25 }) do
				local su = sspan * t
				if exposed(scf, su) then
					for k = 0, floors - 1 do
						window(scf, su, floorY + k * storeyH + storeyH * 0.52, 3.2, 4.4, { sill = brick })
					end
				end
			end
			if (arch == "colonial_house" or arch == "victorian_house") and exposed(scf, sspan * 0.1) then
				-- side door toward the back
				local backWorld = r.frame:VectorToWorldSpace(-nFront)
				local su = sspan * 0.1 * ((scf.RightVector:Dot(backWorld) >= 0) and 1 or -1)
				H.door(model, scf, su, r.streetLevel + 0.4, H.DOOR_COLORS[(h0 % #H.DOOR_COLORS) + 1], false)
				stats.sideDoors += 1
			end
		end
	end

	-- roof over the whole section
	local top = r.frame.Position * Vector3.new(1, 0, 1) + Vector3.new(0, r.wallTop, 0)
	local faceRot = fcf.Rotation
	local function gable(ridgeAlongFront, rise)
		-- two wedges meeting at the ridge (wedge tall edge is local +Z)
		local length = ridgeAlongFront and (span + 1.2) or (depth + 1.2)
		local half = (ridgeAlongFront and (depth + 1.2) or (span + 1.2)) / 2
		local base = CFrame.new(top) * faceRot * (ridgeAlongFront and CFrame.new() or CFrame.Angles(0, math.pi / 2, 0))
		for s = -1, 1, 2 do
			local wd = Instance.new("WedgePart")
			wd.Name = "Roof"
			wd.Anchored = true
			wd.Material = Enum.Material.Slate
			wd.Color = roofColor
			wd.Size = Vector3.new(length, rise, half)
			wd.CFrame = base * CFrame.new(0, rise / 2, s * half / 2) * CFrame.Angles(0, s == 1 and math.pi or 0, 0)
			wd.Parent = model
		end
	end
	if arch == "colonial_twin" or arch == "colonial_house" or arch == "victorian_twin" then
		gable(true, math.clamp(depth * 0.3, 4, 10))
	elseif arch == "victorian_house" then
		gable(false, math.clamp(span * 0.42, 5, 11))
	else
		solid("Roof", Vector3.new(r.along + 0.4, 0.6, r.across + 0.4), r.frame + Vector3.new(0, r.wallTop + 0.3, 0), Enum.Material.Concrete,
			Color3.fromRGB(70, 68, 66))
		if arch == "apartment" then
			solid("Cornice", Vector3.new(span + 0.6, 1.2, 1.2), at(fcf, 0, r.wallTop + 0.2, -0.3), Enum.Material.Concrete, STONE)
		end
	end
	-- a chimney on detached houses and twins
	if arch ~= "porch_row" and arch ~= "flat_row" and arch ~= "apartment" and h0 % 3 ~= 0 then
		solid("Chimney", Vector3.new(2.0, 9, 2.0), at(fcf, span / 2 - 2.5, r.wallTop + 3.5, depth * 0.55), Enum.Material.Brick,
			Color3.fromRGB(140, 70, 54))
	end
end

return HouseKit
