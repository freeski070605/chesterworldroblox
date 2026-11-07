-- Real-building facades (2026-11-07): from extruded boxes with the same
-- door-and-window / shop-glass texture on all four walls to Chester homes and
-- walk-in stores.
--
-- Homes (rowhouse / twin / house / apartment): windows on every wall, a
-- modeled front door with trim, transom and stoop per unit on the street front
-- (tools/add_building_fronts.py fb / un), a back door per unit on the rear
-- wall, and a side door on an exposed end wall of a house or twin. No doors on
-- walls hidden behind another part of the same building.
--
-- Stores (a building section with a shop: ss= / sb=): a hollow ground floor
-- you can walk into - floor, ceiling, plain side and back walls, and on the
-- entrance face (the street of the shop's address; both street faces on a
-- corner) a bulkhead, shop glass, piers and a walk-through glass door. Each
-- shop gets an Exit6StoreAnchor (local -Z = its door) in a model tagged
-- Exit6Store, with the size / name attributes gameplay fits the interior from.
local CollectionService = game:GetService("CollectionService")

local RealBuildings = {}

local DOOR_COLORS = {
	Color3.fromRGB(92, 52, 38), Color3.fromRGB(46, 50, 56), Color3.fromRGB(122, 32, 34),
	Color3.fromRGB(36, 70, 52), Color3.fromRGB(150, 130, 104), Color3.fromRGB(40, 56, 92),
}
local TRIM = Color3.fromRGB(232, 228, 216)
local CONCRETE = Color3.fromRGB(176, 172, 164)
local GLASS = Color3.fromRGB(150, 188, 205)
local UNIT_STUDS = 19.2          -- one rowhouse unit (~4.9 m real)

local function part(parent, name, size, cframe, material, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- local axis of the rect whose face looks toward a compass bearing
local function faceAxis(frame, bearingDeg)
	local rad = math.rad(bearingDeg)
	local dir = Vector3.new(math.sin(rad), 0, -math.cos(rad))
	local best, bestDot
	for _, n in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local d = frame:VectorToWorldSpace(n):Dot(dir)
		if not bestDot or d > bestDot then best, bestDot = n, d end
	end
	return best
end

-- a face of the rect: centre (y = 0), outward world normal, span along it
local function faceOf(r, n)
	local half = (n.X ~= 0) and r.along / 2 or r.across / 2
	local span = (n.X ~= 0) and r.across or r.along
	local centre = r.frame * (n * half)
	local normal = r.frame:VectorToWorldSpace(n)
	-- face frame: -Z outward, X along the wall
	return CFrame.lookAt(Vector3.new(centre.X, 0, centre.Z), Vector3.new(centre.X, 0, centre.Z) + normal), span, normal
end

-- is a point (world, horizontal) inside another rect of the same building?
local function covered(p, rects, self)
	for _, o in ipairs(rects) do
		if o ~= self then
			local l = o.frame:PointToObjectSpace(Vector3.new(p.X, 0, p.Z))
			if math.abs(l.X) < o.along / 2 - 0.1 and math.abs(l.Z) < o.across / 2 - 0.1 then return true end
		end
	end
	return false
end

local function door(parent, fcf, u, groundY, color, withStoop)
	local lift = withStoop and 1.1 or 0.3
	local function at(x, y, z) return fcf * CFrame.new(x, 0, z) + Vector3.new(0, y, 0) end
	part(parent, "DoorTrim", Vector3.new(4.8, 8.9, 0.3), at(u, groundY + lift + 4.45, -0.12), Enum.Material.SmoothPlastic, TRIM)
	local d = part(parent, "Door", Vector3.new(3.6, 7.3, 0.35), at(u, groundY + lift + 3.65, -0.22), Enum.Material.Wood, color)
	local transom = part(parent, "Transom", Vector3.new(3.6, 0.9, 0.3), at(u, groundY + lift + 7.9, -0.2), Enum.Material.Glass, GLASS)
	transom.Transparency = 0.3
	part(parent, "DoorKnob", Vector3.new(0.3, 0.3, 0.3), at(u + 1.25, groundY + lift + 3.4, -0.45), Enum.Material.Metal,
		Color3.fromRGB(196, 170, 96))
	if withStoop then
		part(parent, "Stoop", Vector3.new(5.4, 1.1, 3.0), at(u, groundY + 0.55, -1.5), Enum.Material.Concrete, CONCRETE)
		part(parent, "StoopStep", Vector3.new(5.4, 0.55, 1.4), at(u, groundY + 0.275, -3.6), Enum.Material.Concrete, CONCRETE)
	else
		part(parent, "DoorPad", Vector3.new(4.6, 0.3, 2.2), at(u, groundY + 0.15, -1.1), Enum.Material.Concrete, CONCRETE)
	end
	return d
end

-- Home: windows all round (applyFacade), doors on the front / back / side.
-- r: { frame, along, across, x, z, streetLevel, base, wallTop }, ctx: building context
function RealBuildings.Home(model, r, ctx)
	local block = part(model, "Walls", Vector3.new(r.along, r.wallTop - r.base, r.across),
		r.frame * CFrame.new(0, 0, 0) + Vector3.new(0, (r.wallTop + r.base) / 2, 0), ctx.material, ctx.wall)
	block:SetAttribute("GroundY", r.streetLevel + 0.4)
	ctx.applyFacade(block, ctx.style, r.storey)
	if not ctx.front then return end
	local doorColor = DOOR_COLORS[(ctx.seed % #DOOR_COLORS) + 1]
	local nFront = faceAxis(r.frame, ctx.front)
	local function exposed(fcf, span, u)
		local p = (fcf * CFrame.new(u, 0, -2.5)).Position
		return not covered(p, ctx.rects, r)
	end
	-- front: one door per unit (rowhouse), two on a twin, one on a house
	local fcf, span = faceOf(r, nFront)
	local units = 1
	if ctx.style == "rowhouse" then
		units = math.max(1, math.floor(span / UNIT_STUDS + 0.5))
	elseif ctx.style == "twin" and span >= 28 then
		units = 2
	elseif ctx.style == "apartment" then
		units = 1
	end
	if span >= 7 then
		local w = span / units
		for i = 1, units do
			-- door toward one side of its unit, mirrored pair by pair as on a real row
			local side = (i % 2 == 0) and 1 or -1
			local u = -span / 2 + w * (i - 0.5) + side * math.min(w * 0.22, 3)
			if exposed(fcf, span, u) then
				-- every unit of a row has its own door colour
				local unitColor = DOOR_COLORS[((ctx.seed + i * 7) % #DOOR_COLORS) + 1]
				local d = door(model, fcf, u, r.streetLevel + 0.4, units > 1 and unitColor or doorColor, not ctx.porch)
				-- the address a delivery goes to (Exit6Delivery.server)
				CollectionService:AddTag(d, "Exit6FrontDoor")
				ctx.stats.frontDoors += 1
			end
		end
	end
	-- back: one door per unit
	local bcf, bspan = faceOf(r, -nFront)
	if bspan >= 7 then
		local w = bspan / units
		for i = 1, units do
			local u = -bspan / 2 + w * (i - 0.5)
			if exposed(bcf, bspan, u) then
				door(model, bcf, u, r.streetLevel + 0.4, doorColor, false)
				ctx.stats.backDoors += 1
			end
		end
	end
	-- side: a house or twin end wall that is exposed, toward the back
	if ctx.style == "house" or ctx.style == "twin" then
		local sideAxis = Vector3.new(nFront.Z, 0, -nFront.X)
		if ctx.corner then
			sideAxis = faceAxis(r.frame, ctx.corner)
			if sideAxis == nFront or sideAxis == -nFront then sideAxis = Vector3.new(nFront.Z, 0, -nFront.X) end
		end
		local scf, sspan = faceOf(r, sideAxis)
		if sspan >= 22 then
			-- toward the back of the house along this wall
			local backWorld = r.frame:VectorToWorldSpace(-nFront)
			local u = sspan * 0.25 * ((scf.RightVector:Dot(backWorld) >= 0) and 1 or -1)
			if exposed(scf, sspan, u) then
				door(model, scf, u, r.streetLevel + 0.4, doorColor, false)
				ctx.stats.sideDoors += 1
			end
		end
	end
end

-- Store section: walk-in ground floor + upper storeys.
-- shop: { name, front (bearing), corner (bearing or nil), placeId, signBg }
function RealBuildings.Store(model, r, ctx, shop)
	local groundTop = math.min(r.streetLevel + math.max(r.storey, 13), r.wallTop)
	local groundH = groundTop - r.streetLevel
	-- floors above the shop keep their windows
	if r.wallTop - groundTop > 1 then
		local upper = part(model, "Walls", Vector3.new(r.along, r.wallTop - groundTop, r.across),
			r.frame + Vector3.new(0, (r.wallTop + groundTop) / 2, 0), ctx.material, ctx.wall)
		ctx.applyFacade(upper, ctx.style, r.storey)
	end
	if r.streetLevel - r.base > 0.3 then
		part(model, "Foundation", Vector3.new(r.along, r.streetLevel - r.base, r.across),
			r.frame + Vector3.new(0, (r.streetLevel + r.base) / 2, 0), Enum.Material.Concrete, Color3.fromRGB(128, 124, 118))
	end
	part(model, "ShopFloor", Vector3.new(r.along, 0.4, r.across), r.frame + Vector3.new(0, r.streetLevel + 0.2, 0),
		Enum.Material.SmoothPlastic, Color3.fromRGB(214, 210, 200))
	part(model, "ShopCeiling", Vector3.new(r.along, 0.6, r.across), r.frame + Vector3.new(0, groundTop - 0.3, 0),
		Enum.Material.SmoothPlastic, Color3.fromRGB(236, 234, 228))
	local nFront = faceAxis(r.frame, shop.front)
	local fronts = { [tostring(nFront)] = true }
	if shop.corner then
		local nc = faceAxis(r.frame, shop.corner)
		if nc ~= -nFront then fronts[tostring(nc)] = true end
	end
	for _, n in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local fcf, span = faceOf(r, n)
		local function at(x, y, z) return fcf * CFrame.new(x, 0, z) + Vector3.new(0, y, 0) end
		local y0 = r.streetLevel + 0.4
		local probe = (fcf * CFrame.new(0, 0, -2)).Position
		if fronts[tostring(n)] and not covered(probe, ctx.rects, r) then
			-- bulkhead, piers, shop glass, sign band wall, walk-through door
			local h = groundH - 0.4
			part(model, "Bulkhead", Vector3.new(span, 1.6, 0.8), at(0, y0 + 0.8, 0.4), ctx.material, ctx.wall)
			for _, s in ipairs({ -1, 1 }) do
				part(model, "Pier", Vector3.new(1.2, h, 0.9), at(s * (span / 2 - 0.6), y0 + h / 2, 0.4), ctx.material, ctx.wall)
			end
			local bandH = math.max(h - 10, 2.4)
			part(model, "SignBandWall", Vector3.new(span, bandH, 0.8), at(0, y0 + h - bandH / 2, 0.4), ctx.material, ctx.wall)
			local glassTop = y0 + h - bandH
			local doorW = math.min(5, span * 0.3)
			local paneW = (span - 2.4 - doorW) / 2
			if paneW > 0.6 then
				for _, s in ipairs({ -1, 1 }) do
					local g = part(model, "ShopGlass", Vector3.new(paneW, glassTop - (y0 + 1.6), 0.3),
						at(s * (doorW / 2 + paneW / 2), (glassTop + y0 + 1.6) / 2, 0.4), Enum.Material.Glass, GLASS)
					g.Transparency = 0.45
					g.Reflectance = 0.1
				end
			end
			-- door frame + a glass door you can walk through
			for _, s in ipairs({ -1, 1 }) do
				part(model, "DoorFrame", Vector3.new(0.35, glassTop - y0, 0.5), at(s * doorW / 2, (glassTop + y0) / 2, 0.4),
					Enum.Material.Metal, Color3.fromRGB(60, 62, 66))
			end
			local glassDoor = part(model, "ShopDoor", Vector3.new(doorW - 0.4, glassTop - y0 - 0.4, 0.15),
				at(0, (glassTop + y0) / 2, 0.55), Enum.Material.Glass, GLASS)
			glassDoor.Transparency = 0.55
			glassDoor.CanCollide = false
			local mat = part(model, "DoorMat", Vector3.new(doorW - 0.6, 0.1, 2.4), at(0, y0 + 0.05, -1.4),
				Enum.Material.Fabric, Color3.fromRGB(40, 40, 44))
			mat.CanCollide = false
			ctx.stats.storefronts += 1
		else
			local w = part(model, "ShopWall", Vector3.new(span, groundH, 0.8), at(0, r.streetLevel + groundH / 2, 0.4),
				ctx.material, ctx.wall)
			ctx.applyFacade(w, ctx.style, r.storey)
		end
	end
	-- anchor for the interior (gameplay: Exit6Storefronts), local -Z = the door
	if not shop.name then return end   -- an unnamed shopfront: shell only
	local shopModel = Instance.new("Model")
	shopModel.Name = "Shop_" .. shop.name
	shopModel.Parent = model
	local floorCentre = r.frame.Position + Vector3.new(0, r.streetLevel + 0.7, 0)
	local frontWorld = r.frame:VectorToWorldSpace(nFront)
	local anchor = part(shopModel, "Exit6StoreAnchor", Vector3.new(2, 0.2, 2),
		CFrame.lookAt(floorCentre, floorCentre + frontWorld), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	local width = (nFront.X ~= 0) and r.across or r.along
	local depth = (nFront.X ~= 0) and r.along or r.across
	shopModel:SetAttribute("ShopName", shop.name)
	shopModel:SetAttribute("BrandName", shop.name)
	shopModel:SetAttribute("ChesterBuildingId", ctx.buildingId)
	shopModel:SetAttribute("PlaceId", shop.placeId)
	shopModel:SetAttribute("Exit6StoreShell", "building")
	shopModel:SetAttribute("Exit6StoreWidth", width - 1.6)
	shopModel:SetAttribute("Exit6StoreDepth", depth - 1.6)
	shopModel:SetAttribute("Exit6StoreHeight", groundH)
	if shop.signBg then shopModel:SetAttribute("BrandFascia", shop.signBg) end
	CollectionService:AddTag(shopModel, "Exit6Store")
	ctx.stats.shops += 1
end

return RealBuildings
