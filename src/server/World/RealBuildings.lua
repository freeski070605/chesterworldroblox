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
local HouseKit = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("HouseKit"))

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
	-- Chester house kit: archetype facades, porches, roofs, rentable interiors
	HouseKit.Build(model, r, ctx, {
		part = part, faceAxis = faceAxis, faceOf = faceOf, covered = covered, door = door,
		DOOR_COLORS = DOOR_COLORS, TRIM = TRIM, CONCRETE = CONCRETE, UNIT_STUDS = UNIT_STUDS,
	})
end

-- Store section: walk-in ground floor + upper storeys.
-- shop: { name, front (bearing), corner (bearing or nil), placeId, signBg }
function RealBuildings.Store(model, r, ctx, shop)
	local groundTop = math.min(r.streetLevel + math.max(r.storey, 13), r.wallTop)
	local groundH = groundTop - r.streetLevel
    local is777 = shop.photoFacade == "777"
    local blue777 = Color3.fromRGB(34,72,190)
    local blueTrim777 = Color3.fromRGB(20,58,149)
    local wallMaterial = is777 and Enum.Material.Brick or ctx.material
    local baseWallColor = is777 and blue777 or ctx.wall
	-- floors above the shop keep their windows
	if r.wallTop - groundTop > 1 then
		local upper = part(model, "Walls", Vector3.new(r.along, r.wallTop - groundTop, r.across),
			r.frame + Vector3.new(0, (r.wallTop + groundTop) / 2, 0), ctx.material, ctx.wall)
        if shop.photoFacade ~= "777" then ctx.applyFacade(upper, ctx.style, r.storey) end
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
	local entryDoor
	local entryFace
	local entryOffset = 0
	local preferredEntrance = shop.entrance and faceAxis(r.frame, shop.entrance) or nFront
	local fronts = { [tostring(nFront)] = true }
	if shop.corner then
		local nc = faceAxis(r.frame, shop.corner)
		if nc ~= -nFront then fronts[tostring(nc)] = true end
	end
    -- Corner shops are frequently attached to the next property. If the
    -- nominal door wall is covered, select another EXISTING exposed street
    -- face rather than building a store with no walk-through door at all.
    -- Never introduce an unsupported street-facing facade on a rear wall.
    local normals = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }
    local function exposedFront(n)
        local fcf,span = faceOf(r,n)
        return span >= 7 and fronts[tostring(n)]
            and not covered((fcf*CFrame.new(0,0,-2)).Position,ctx.rects,r)
    end
    if not exposedFront(preferredEntrance) then
        if exposedFront(nFront) then
            preferredEntrance = nFront
        else
            for _, normal in ipairs(normals) do
                if exposedFront(normal) then
                    preferredEntrance = normal
                    break
                end
            end
        end
    end
	for _, n in ipairs(normals) do
		local fcf, span = faceOf(r, n)
		local function at(x, y, z) return fcf * CFrame.new(x, 0, z) + Vector3.new(0, y, 0) end
		local y0 = r.streetLevel + 0.4
		local probe = (fcf * CFrame.new(0, 0, -2)).Position
		if fronts[tostring(n)] and not covered(probe, ctx.rects, r) then
            -- A surveyed corner storefront can put its door toward either
            -- street and shift it along that wall. Keep glazing/signage on
            -- both exposed faces, but create only ONE entrance per section.
            local doorOnThisWall = n == preferredEntrance
            local offset = 0
            if doorOnThisWall and shop.entranceOffset then
                local safeSpan = math.max(0,span / 2 - math.min(5,span*0.3) / 2 - 1.8)
                offset = math.clamp(shop.entranceOffset,-1,1)*safeSpan
            end
			-- bulkhead, piers, shop glass, sign band wall, walk-through door
			local h = groundH - 0.4
			part(model, "Bulkhead", Vector3.new(span, 1.6, 0.8), at(0, y0 + 0.8, 0.4), wallMaterial, baseWallColor)
			for _, s in ipairs({ -1, 1 }) do
				part(model, "Pier", Vector3.new(1.2, h, 0.9), at(s * (span / 2 - 0.6), y0 + h / 2, 0.4), wallMaterial, baseWallColor)
			end
			local bandH = math.max(h - 10, 2.4)
			part(model, "SignBandWall", Vector3.new(span, bandH, 0.8), at(0, y0 + h - bandH / 2, 0.4), wallMaterial, baseWallColor)
            -- Photo-specific 777 Food Market corner: long Lincoln glass and
            -- yellow-over-blue fascia, entrance only at the W 9th corner.
            -- Do not create a duplicate shop or sign on the adjacent wall.
            if shop.photoFacade == "777" then
                local faceY = y0 + h - math.max(h - 10, 2.4) + 0.35
                local yellow=Color3.fromRGB(244,198,49)
                local blue=Color3.fromRGB(28,57,128)
                local border=part(model,"777YellowCanopyEdge",
                    Vector3.new(math.max(2,span-0.6),0.65,1.9),
                    at(0,faceY+2.0,-0.95),Enum.Material.Metal,yellow)
                border.CanCollide=false
                local band=part(model,"777PhotoShopFascia",
                    Vector3.new(math.max(2,span-1.8),2.4,0.2),
                    at(0,faceY+0.8,-1.83),Enum.Material.SmoothPlastic,blue)
                band.CanCollide=false
                local board=Instance.new("SurfaceGui")
                board.Name="777MarketSign"
                board.Face=Enum.NormalId.Front
                board.PixelsPerStud=18
                board.SizingMode=Enum.SurfaceGuiSizingMode.PixelsPerStud
                board.Parent=band
                local label=Instance.new("TextLabel")
                label.Size=UDim2.fromScale(1,1)
                label.BackgroundTransparency=1
                label.Text="777 FOOD MARKET"
                label.TextScaled=true
                label.Font=Enum.Font.GothamBlack
                label.TextColor3=Color3.fromRGB(248,217,73)
                label.Parent=board
                -- Upper-floor windows seen above the long corner market.
                -- Backed by brick/plaster rather than a second false storefront.
                if r.wallTop-groundTop>8 then
                    local count=span>38 and 3 or (span>22 and 2 or 1)
                    for wi=1,count do
                        local offset= (wi-(count+1)/2)*math.min(15,(span-6)/count)
                        local win=part(model,"777UpperWindow",
                            Vector3.new(3.3,6.1,0.22),
                            at(offset,groundTop+3.9,-0.55),Enum.Material.Glass,
                            Color3.fromRGB(82,101,110))
                        win.Transparency=0.22
                        local sill=part(model,"777WindowSill",
                            Vector3.new(4.3,0.45,0.65),
                            at(offset,groundTop+0.65,-0.8),Enum.Material.Concrete,
                            Color3.fromRGB(230,224,203))
                        sill.CanCollide=false
                    end
                end
            end
            if shop.photoFacade == "777" and n ~= nFront and r.wallTop-groundTop > 8 then
                -- Distinct small upstairs window over the W 9th entry wall.
                local window=part(model,"777CornerUpperWindow",
                    Vector3.new(3.1,5.5,0.22),at(0,groundTop+4.0,-0.55),
                    Enum.Material.Glass,Color3.fromRGB(76,99,113))
                window.Transparency=0.2
                local sill=part(model,"777CornerWindowSill",
                    Vector3.new(4.0,0.4,0.6),at(0,groundTop+1.1,-0.78),
                    Enum.Material.Concrete,Color3.fromRGB(225,216,199))
                sill.CanCollide=false
            end
            if is777 then
                -- Blue-painted security rail at the base of the street-view
                -- shop windows. Leave the 9th corner doorway completely open.
                local railY=y0+1.45
                local fenceColor=Color3.fromRGB(47,87,176)
                local gapW=doorOnThisWall and math.min(7,span*0.4) or 0
                local segments=doorOnThisWall and {
                    {-span/2+0.5,offset-gapW/2},
                    {offset+gapW/2,span/2-0.5},
                } or {{-span/2+0.5,span/2-0.5}}
                for _,range in ipairs(segments) do
                    if range[2]-range[1]>2 then
                        local rail=part(model,"777WindowSafetyRail",
                            Vector3.new(range[2]-range[1],0.2,0.2),
                            at((range[1]+range[2])/2,railY+1.15,-1.6),
                            Enum.Material.Metal,fenceColor)
                        rail.CanCollide=false
                        local count=math.max(1,math.floor((range[2]-range[1])/2.1))
                        for i=0,count do
                            local bar=part(model,"777SafetyBaluster",
                                Vector3.new(0.16,2.2,0.16),
                                at(range[1]+(range[2]-range[1])*i/count,railY,-1.6),
                                Enum.Material.Metal,fenceColor)
                            bar.CanCollide=false
                        end
                    end
                end
            end
            if is777 then
                -- Painted blue shop piers, recessed window skirts and framing;
                -- the actual storefront is inset, not an all-glass gray box.
                local sillBand = part(model,"777BlueWindowSkirt",
                    Vector3.new(span,2.15,0.3),
                    at(0,y0+0.9,-0.07),Enum.Material.Brick,blue777)
                sillBand.CanCollide=false
                local trimBand = part(model,"777StorefrontBlueTrim",
                    Vector3.new(span,0.4,0.38),
                    at(0,y0+2.15,-0.16),Enum.Material.Metal,blueTrim777)
                trimBand.CanCollide=false
            end
            -- Readable ground-floor shopfront framing: make the canopy,
            -- sign-band edge and glass transom physically distinct instead
            -- of leaving all commercial ground floors as a flat texture.
            -- These are procedural facade details, not photo-specific claims.
			if shop.name and shop.canopy ~= false and span >= 12 and h >= 9 then
                local canopy = part(model,"StorefrontCanopy",Vector3.new(span-1.6,0.28,2.1),
                    at(0,y0+h-bandH-0.2,-0.85),Enum.Material.Metal,
                    shop.signBg or Color3.fromRGB(90,94,98))
                canopy.CanCollide=false
                local fascia = part(model,"StorefrontFascia",Vector3.new(span-1.6,0.7,0.24),
                    at(0,y0+h-bandH+0.08,-1.9),Enum.Material.SmoothPlastic,
                    Color3.fromRGB(45,47,50))
                fascia.CanCollide=false
            end
			local glassTop = y0 + h - bandH
			local doorW = math.min(5, span * 0.3)
            local glassHeight = glassTop - (y0+1.6)
            if glassHeight > 0.5 then
                if doorOnThisWall then
                    -- Panels end exactly at the offset doorway's frames,
                    -- including for doors close to a corner.
                    for _,side in ipairs({-1,1}) do
                        local leftEdge = (side==-1) and (-span/2+1.2) or (offset+doorW/2)
                        local rightEdge = (side==-1) and (offset-doorW/2) or (span/2-1.2)
                        local width = rightEdge-leftEdge
                        if width > 0.6 then
                            local g=part(model,"ShopGlass",Vector3.new(width,glassHeight,0.3),
                                at((leftEdge+rightEdge)/2,(glassTop+y0+1.6)/2,0.4),
                                Enum.Material.Glass,GLASS)
                            g.Transparency=0.45
                            g.Reflectance=0.1
                        end
                    end
                else
                    -- Secondary corner-store facade: continuous glazing
                    -- without a fictitious second walk-through entrance.
                    local g=part(model,"ShopGlass",Vector3.new(math.max(1,span-2.4),glassHeight,0.3),
                        at(0,(glassTop+y0+1.6)/2,0.4),Enum.Material.Glass,GLASS)
                    g.Transparency=0.45
                    g.Reflectance=0.1
                end
            end
            -- Keep one door on the imagery-verified face, not a second
            -- walk-through entrance on every corner storefront wall.
            if doorOnThisWall then
                -- Door center follows a normalized along-wall offset, so an
                -- entrance close to the actual corner can be represented.
                for _,side in ipairs({-1,1}) do
                    part(model,"DoorFrame",Vector3.new(0.35,glassTop-y0,0.5),
                        at(offset+side*doorW/2,(glassTop+y0)/2,0.4),
                        Enum.Material.Metal,Color3.fromRGB(60,62,66))
                end
                local glassDoor=part(model,"ShopDoor",Vector3.new(doorW-0.4,glassTop-y0-0.4,0.15),
                    at(offset,(glassTop+y0)/2,0.55),Enum.Material.Glass,GLASS)
                glassDoor.Transparency=0.55
                glassDoor.CanCollide=false
                if is777 then
                    local threshold=part(model,"777CornerEntranceLanding",
                        Vector3.new(doorW+1.8,0.5,3.1),
                        at(offset,y0+0.1,-1.8),Enum.Material.Concrete,
                        Color3.fromRGB(111,137,189))
                    threshold.CanCollide=true
                    local step=part(model,"777CornerEntranceStep",
                        Vector3.new(doorW+1.8,0.28,1.35),
                        at(offset,y0-0.25,-3.5),Enum.Material.Concrete,
                        Color3.fromRGB(158,162,169))
                    step.CanCollide=true
                end
                entryDoor=glassDoor
                entryFace=n
                entryOffset=offset
                local mat=part(model,"DoorMat",Vector3.new(doorW-0.6,0.1,2.4),
                    at(offset,y0+0.05,-1.4),Enum.Material.Fabric,Color3.fromRGB(40,40,44))
                mat.CanCollide=false
            end
			ctx.stats.storefronts += 1
		else
			local w = part(model, "ShopWall", Vector3.new(span, groundH, 0.8), at(0, r.streetLevel + groundH / 2, 0.4),
                wallMaterial, baseWallColor)
            -- The photo shows an opaque rear/side wall with no rows of
            -- generic shop windows. Preserve it as a solid masonry plane.
            if shop.photoFacade ~= "777" then
                ctx.applyFacade(w, ctx.style, r.storey)
            else
                w:SetAttribute("777SolidSideWall",true)
            end
		end
	end
	-- anchor for the interior (gameplay: Exit6Storefronts), local -Z = the door
	if not shop.name then
		-- Citywide unnamed storefronts: use the existing doorway as a lightweight
		-- interactive counter. No extra physical geometry or cashier NPCs.
		if entryDoor then
			local simple = Instance.new("Model")
			simple.Name = "Shop_Local_" .. ctx.buildingId
			simple:SetAttribute("ShopName", "Neighborhood Market")
			simple:SetAttribute("ChesterBuildingId", ctx.buildingId)
			simple.Parent = model
			local doorRef = Instance.new("ObjectValue")
			doorRef.Name = "Exit6ShopDoor"
			doorRef.Value = entryDoor
			doorRef.Parent = simple
			CollectionService:AddTag(simple, "Exit6SimpleStore")
		end
		return
	end
	local shopModel = Instance.new("Model")
	shopModel.Name = "Shop_" .. shop.name
	shopModel.Parent = model
	local floorCentre = r.frame.Position + Vector3.new(0, r.streetLevel + 0.7, 0)
    local actualFace = entryFace or nFront
    local frontWorld = r.frame:VectorToWorldSpace(actualFace)
    -- Interior anchor stays centered for the fixture layout; direction matches
    -- the actual selected door. Gameplay can resolve physical door separately.
    local anchor = part(shopModel, "Exit6StoreAnchor", Vector3.new(2, 0.2, 2),
        CFrame.lookAt(floorCentre, floorCentre + frontWorld), Enum.Material.SmoothPlastic, Color3.new(1, 1, 1))
    if entryDoor then
        local doorRef = Instance.new("ObjectValue")
        doorRef.Name = "Exit6ShopDoor"
        doorRef.Value = entryDoor
        doorRef.Parent = shopModel
    end
    shopModel:SetAttribute("EntranceFaceVerified", shop.entrance ~= nil)
    shopModel:SetAttribute("EntranceOffset", entryOffset)
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
